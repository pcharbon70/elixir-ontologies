# Feature 11.1.3: Validation Report Writer

## Problem Statement

Tasks 11.1.1 (SHACL Data Model) and 11.1.2 (SHACL Shapes Reader) have successfully established internal Elixir structs for SHACL shapes and validation results. However, validation results currently exist only as Elixir structs in memory - there's no way to serialize them back to standardized RDF/Turtle format for:

1. **Standards compliance** - SHACL validation reports must conform to the W3C SHACL specification's report vocabulary
2. **Interoperability** - Reports must be consumable by other SHACL tools and RDF processors
3. **Persistence** - Reports need to be saved to files for archival, debugging, and compliance verification
4. **Round-trip testing** - Validation workflow testing requires serializing reports to RDF for comparison
5. **Debugging** - Human-readable Turtle format aids in understanding validation failures

The SHACL Validation Report Writer must:

1. **Convert ValidationReport structs to RDF graphs** - Map Elixir data structures to SHACL vocabulary triples
2. **Serialize to Turtle format** - Produce clean, readable Turtle documents with proper prefixes
3. **Handle blank nodes correctly** - Generate blank nodes for ValidationResult resources
4. **Map severity levels** - Convert Elixir atoms (:violation, :warning, :info) to SHACL IRIs
5. **Preserve nil values** - Omit optional properties (like sh:resultPath) when nil
6. **Support validation workflow** - Enable seamless parse-shapes → validate → write-report cycle

Without this writer, validation results remain trapped in Elixir structs, preventing integration with standard RDF tooling and making debugging difficult.

## Solution Overview

Create `lib/elixir_ontologies/shacl/writer.ex` as the struct-to-RDF serialization layer that converts ValidationReport structs into RDF graphs following the SHACL validation report vocabulary, then serializes to Turtle format.

**Architecture:**

```
Input: ValidationReport struct
  ↓
Writer.to_graph/1
  ├─ Create base report node (blank node or named IRI)
  ├─ Add sh:conforms triple (boolean literal)
  └─ For each ValidationResult:
      ├─ Create result blank node
      ├─ Add sh:result link from report
      ├─ Add sh:ValidationResult type
      ├─ Add sh:focusNode (IRI, blank node, or literal)
      ├─ Add sh:resultPath (IRI, optional - skip if nil)
      ├─ Add sh:sourceShape (IRI)
      ├─ Add sh:resultSeverity (map :violation/:warning/:info to IRI)
      ├─ Add sh:resultMessage (string literal)
      └─ Add sh:value for details (optional, future extension)
  ↓
Output: RDF.Graph.t()
  ↓
Writer.to_turtle/1 or Writer.to_turtle/2
  ↓
Output: {:ok, turtle_string} or {:error, reason}
```

**Key Design Decisions:**

1. **Blank nodes for reports and results** - Use RDF.BlankNode.new() for both report and result resources (no need to persist IRI identities)
2. **SHACL vocabulary constants** - Define module attributes for all SHACL IRIs (sh:ValidationReport, sh:conforms, etc.)
3. **Severity IRI mapping** - Map Elixir atoms to SHACL severity IRIs:
   - `:violation` → `http://www.w3.org/ns/shacl#Violation`
   - `:warning` → `http://www.w3.org/ns/shacl#Warning`
   - `:info` → `http://www.w3.org/ns/shacl#Info`
4. **Optional property handling** - Use guards to skip nil values (path, message)
5. **Details field** - Initially ignore ValidationResult.details map; reserve for future extensions (sh:value, sh:detail)
6. **Turtle formatting** - Leverage RDF.Turtle.write_string/2 with SHACL prefix map for clean output
7. **Two-step API** - Separate to_graph/1 (struct → RDF) from to_turtle/1 (RDF → string) for flexibility

## Technical Details

### File Structure

```
lib/elixir_ontologies/shacl/
├── model/
│   ├── node_shape.ex          # ✓ Exists (from 11.1.1)
│   ├── property_shape.ex      # ✓ Exists (from 11.1.1)
│   ├── sparql_constraint.ex   # ✓ Exists (from 11.1.1)
│   ├── validation_result.ex   # ✓ Exists (from 11.1.1)
│   └── validation_report.ex   # ✓ Exists (from 11.1.1)
├── reader.ex                  # ✓ Exists (from 11.1.2)
└── writer.ex                  # NEW - This task
```

### SHACL Vocabulary Mapping

The writer must map Elixir structs to these SHACL RDF terms:

| Elixir Struct/Field | SHACL RDF Term | RDF Type | Notes |
|---------------------|----------------|----------|-------|
| `ValidationReport{}` | `sh:ValidationReport` | Class | Report resource type |
| `.conforms?` | `sh:conforms` | `xsd:boolean` | true/false literal |
| `.results` | `sh:result` | Object property | Links to result nodes |
| `ValidationResult{}` | `sh:ValidationResult` | Class | Result resource type |
| `.focus_node` | `sh:focusNode` | RDF.Term.t() | Any RDF term |
| `.path` | `sh:resultPath` | RDF.IRI.t() | Optional - skip if nil |
| `.source_shape` | `sh:sourceShape` | RDF.IRI.t() | Shape IRI |
| `.severity` | `sh:resultSeverity` | IRI | Map atom to IRI |
| `.message` | `sh:resultMessage` | `xsd:string` | Error message |
| `.details` | (reserved) | - | Future: sh:value, sh:detail |

### Implementation Details

#### 1. Module Structure and Constants

```elixir
defmodule ElixirOntologies.SHACL.Writer do
  @moduledoc """
  Serialize SHACL validation reports to RDF graphs and Turtle format.

  This module converts ValidationReport structs into RDF graphs following
  the W3C SHACL validation report vocabulary, then serializes to Turtle.

  ## Usage

      # Given a validation report
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/Module1>,
            path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
            source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
            severity: :violation,
            message: "Module name must match pattern",
            details: %{}
          }
        ]
      }

      # Convert to RDF graph
      {:ok, graph} = Writer.to_graph(report)

      # Serialize to Turtle
      {:ok, turtle} = Writer.to_turtle(graph)

      # Or directly from report to Turtle
      {:ok, turtle} = Writer.to_turtle(report)
  """

  alias ElixirOntologies.SHACL.Model.{ValidationReport, ValidationResult}

  # SHACL Vocabulary
  @sh_validation_report RDF.iri("http://www.w3.org/ns/shacl#ValidationReport")
  @sh_validation_result RDF.iri("http://www.w3.org/ns/shacl#ValidationResult")
  @sh_conforms RDF.iri("http://www.w3.org/ns/shacl#conforms")
  @sh_result RDF.iri("http://www.w3.org/ns/shacl#result")
  @sh_focus_node RDF.iri("http://www.w3.org/ns/shacl#focusNode")
  @sh_result_path RDF.iri("http://www.w3.org/ns/shacl#resultPath")
  @sh_source_shape RDF.iri("http://www.w3.org/ns/shacl#sourceShape")
  @sh_result_severity RDF.iri("http://www.w3.org/ns/shacl#resultSeverity")
  @sh_result_message RDF.iri("http://www.w3.org/ns/shacl#resultMessage")

  # Severity IRIs
  @sh_violation RDF.iri("http://www.w3.org/ns/shacl#Violation")
  @sh_warning RDF.iri("http://www.w3.org/ns/shacl#Warning")
  @sh_info RDF.iri("http://www.w3.org/ns/shacl#Info")

  # RDF Vocabulary
  @rdf_type RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")

  # SHACL prefix map for Turtle serialization
  @shacl_prefixes %{
    sh: "http://www.w3.org/ns/shacl#",
    rdf: "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    xsd: "http://www.w3.org/2001/XMLSchema#"
  }
end
```

#### 2. Main API: to_graph/1

Converts ValidationReport struct to RDF.Graph.t():

```elixir
@spec to_graph(ValidationReport.t()) :: {:ok, RDF.Graph.t()} | {:error, term()}
def to_graph(%ValidationReport{} = report) do
  try do
    # Create blank node for report
    report_node = RDF.BlankNode.new()

    # Start with empty graph
    graph = RDF.Graph.new()

    # Add report type and conforms
    graph =
      graph
      |> RDF.Graph.add({report_node, @rdf_type, @sh_validation_report})
      |> RDF.Graph.add({report_node, @sh_conforms, report.conforms?})

    # Add all validation results
    graph =
      Enum.reduce(report.results, graph, fn result, acc_graph ->
        add_validation_result(acc_graph, report_node, result)
      end)

    {:ok, graph}
  rescue
    error -> {:error, Exception.message(error)}
  end
end
```

#### 3. Helper: add_validation_result/3

Adds a single ValidationResult to the graph:

```elixir
@spec add_validation_result(RDF.Graph.t(), RDF.BlankNode.t(), ValidationResult.t()) :: RDF.Graph.t()
defp add_validation_result(graph, report_node, result) do
  # Create blank node for this result
  result_node = RDF.BlankNode.new()

  # Link result to report
  graph = RDF.Graph.add(graph, {report_node, @sh_result, result_node})

  # Add result type
  graph = RDF.Graph.add(graph, {result_node, @rdf_type, @sh_validation_result})

  # Add focus node
  graph = RDF.Graph.add(graph, {result_node, @sh_focus_node, result.focus_node})

  # Add source shape
  graph = RDF.Graph.add(graph, {result_node, @sh_source_shape, result.source_shape})

  # Add severity
  severity_iri = severity_to_iri(result.severity)
  graph = RDF.Graph.add(graph, {result_node, @sh_result_severity, severity_iri})

  # Add optional path (skip if nil)
  graph =
    if result.path do
      RDF.Graph.add(graph, {result_node, @sh_result_path, result.path})
    else
      graph
    end

  # Add optional message (skip if nil)
  graph =
    if result.message do
      RDF.Graph.add(graph, {result_node, @sh_result_message, result.message})
    else
      graph
    end

  graph
end
```

#### 4. Helper: severity_to_iri/1

Maps Elixir severity atoms to SHACL severity IRIs:

```elixir
@spec severity_to_iri(ValidationResult.severity()) :: RDF.IRI.t()
defp severity_to_iri(:violation), do: @sh_violation
defp severity_to_iri(:warning), do: @sh_warning
defp severity_to_iri(:info), do: @sh_info
```

#### 5. Turtle Serialization: to_turtle/1 and to_turtle/2

Serializes RDF graph or ValidationReport to Turtle string:

```elixir
@spec to_turtle(ValidationReport.t() | RDF.Graph.t()) :: {:ok, String.t()} | {:error, term()}
def to_turtle(%ValidationReport{} = report) do
  with {:ok, graph} <- to_graph(report) do
    to_turtle(graph, [])
  end
end

def to_turtle(%RDF.Graph{} = graph) do
  to_turtle(graph, [])
end

@spec to_turtle(RDF.Graph.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
def to_turtle(graph, opts) when is_map(graph) or is_struct(graph, RDF.Graph) do
  # Extract RDF.Graph if wrapped in ValidationReport
  rdf_graph =
    case graph do
      %RDF.Graph{} -> graph
      %ValidationReport{} = report ->
        case to_graph(report) do
          {:ok, g} -> g
          {:error, _} = error -> return error
        end
    end

  # Merge user prefixes with SHACL prefixes
  prefixes = Keyword.get(opts, :prefixes, %{})
  merged_prefixes = Map.merge(@shacl_prefixes, prefixes)

  # Build Turtle options
  turtle_opts =
    [prefixes: merged_prefixes]
    |> maybe_add_opt(:base, Keyword.get(opts, :base))
    |> maybe_add_opt(:indent, Keyword.get(opts, :indent, 4))

  # Serialize to Turtle
  RDF.Turtle.write_string(rdf_graph, turtle_opts)
end

# Helper to conditionally add options
defp maybe_add_opt(opts, _key, nil), do: opts
defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)
```

#### 6. Example Output

Given this validation report:

```elixir
%ValidationReport{
  conforms?: false,
  results: [
    %ValidationResult{
      focus_node: ~I<http://example.org/BadModule>,
      path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
      source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
      severity: :violation,
      message: "Module name must match pattern ^[A-Z][a-zA-Z0-9_]*$",
      details: %{}
    }
  ]
}
```

The writer produces this Turtle:

```turtle
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

[] a sh:ValidationReport ;
    sh:conforms false ;
    sh:result [
        a sh:ValidationResult ;
        sh:focusNode <http://example.org/BadModule> ;
        sh:resultPath <https://w3id.org/elixir-code/structure#moduleName> ;
        sh:sourceShape <https://w3id.org/elixir-code/shapes#ModuleShape> ;
        sh:resultSeverity sh:Violation ;
        sh:resultMessage "Module name must match pattern ^[A-Z][a-zA-Z0-9_]*$"
    ] .
```

### Dependencies

- **RDF.ex (v2.0)** - Already in deps, provides:
  - `RDF.Graph` - Graph data structure
  - `RDF.BlankNode.new/0` - Blank node generation
  - `RDF.Graph.add/2` - Triple insertion
  - `RDF.Turtle.write_string/2` - Turtle serialization

No new dependencies required.

### Testing Strategy

Create `test/elixir_ontologies/shacl/writer_test.exs` with comprehensive coverage:

#### Test Categories (Target: 10+ tests)

1. **Basic Report Conversion (3 tests)**
   - Empty report (conforms?: true, results: [])
   - Single violation report
   - Multiple results report (violations + warnings)

2. **Severity Mapping (3 tests)**
   - Violation severity → sh:Violation
   - Warning severity → sh:Warning
   - Info severity → sh:Info

3. **Optional Fields (2 tests)**
   - Result with nil path (omitted from graph)
   - Result with nil message (omitted from graph)

4. **Focus Node Types (3 tests)**
   - IRI focus node
   - Blank node focus node
   - Literal focus node (edge case, rare but valid)

5. **Turtle Serialization (2 tests)**
   - Valid Turtle syntax (parseable)
   - Correct prefix declarations

6. **Round-trip Testing (2 tests)**
   - Parse shapes → validate (mock) → write report → parse report → verify structure
   - Conformant report serialization and re-parsing

7. **Edge Cases (2 tests)**
   - Large report (100+ results) for performance
   - Unicode in messages

8. **Error Handling (1 test)**
   - Invalid input handling

#### Example Test Structure

```elixir
defmodule ElixirOntologies.SHACL.WriterTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.SHACL.Writer
  alias ElixirOntologies.SHACL.Model.{ValidationReport, ValidationResult}

  describe "to_graph/1" do
    test "converts empty report to RDF graph" do
      report = %ValidationReport{conforms?: true, results: []}

      assert {:ok, graph} = Writer.to_graph(report)
      assert RDF.Graph.triple_count(graph) >= 2  # type + conforms

      # Verify report node exists with correct type
      [report_node] = RDF.Graph.subjects(graph) |> Enum.filter(&match?(%RDF.BlankNode{}, &1))
      assert RDF.Graph.include?(graph, {report_node, RDF.type(), sh_validation_report()})
      assert RDF.Graph.include?(graph, {report_node, sh_conforms(), true})
    end

    test "converts single violation to RDF graph" do
      report = %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            focus_node: ~I<http://example.org/BadModule>,
            path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
            source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
            severity: :violation,
            message: "Invalid module name",
            details: %{}
          }
        ]
      }

      assert {:ok, graph} = Writer.to_graph(report)

      # Verify result node structure
      # ... assertions on result triples
    end
  end

  describe "to_turtle/1" do
    test "serializes report to valid Turtle" do
      report = %ValidationReport{conforms?: true, results: []}

      assert {:ok, turtle} = Writer.to_turtle(report)
      assert is_binary(turtle)
      assert String.contains?(turtle, "@prefix sh:")
      assert String.contains?(turtle, "sh:ValidationReport")
      assert String.contains?(turtle, "sh:conforms")

      # Verify round-trip: Turtle → Graph → equivalent structure
      assert {:ok, reparsed} = RDF.Turtle.read_string(turtle)
      assert RDF.Graph.triple_count(reparsed) == RDF.Graph.triple_count(graph_from_report)
    end
  end

  describe "severity mapping" do
    test "maps :violation to sh:Violation" do
      # ... test severity IRI mapping
    end
  end

  # ... more test groups

  # Helper functions
  defp sh_validation_report, do: RDF.iri("http://www.w3.org/ns/shacl#ValidationReport")
  defp sh_conforms, do: RDF.iri("http://www.w3.org/ns/shacl#conforms")
  # ... other helpers
end
```

## Success Criteria

The Writer module is complete when:

1. **Functionality**
   - [ ] `Writer.to_graph/1` converts ValidationReport to RDF.Graph.t()
   - [ ] `Writer.to_turtle/1` serializes report or graph to Turtle string
   - [ ] `Writer.to_turtle/2` accepts options (prefixes, base, indent)
   - [ ] Blank nodes are used for report and result resources
   - [ ] All required SHACL properties are included (type, conforms, result, focusNode, sourceShape, severity)
   - [ ] Optional properties (path, message) are conditionally included
   - [ ] Severity atoms correctly map to SHACL severity IRIs

2. **Testing**
   - [ ] Minimum 10 tests covering all code paths
   - [ ] Test coverage ≥ 95% for writer.ex
   - [ ] Round-trip test: report → graph → turtle → parsed graph → equivalent structure
   - [ ] Edge cases tested (nil values, various focus node types, unicode messages)
   - [ ] Performance test with large reports (100+ results)

3. **Code Quality**
   - [ ] All functions have @spec type specifications
   - [ ] Comprehensive @moduledoc and @doc documentation
   - [ ] Examples in docstrings are doctests where applicable
   - [ ] No Dialyzer warnings
   - [ ] No Credo warnings at default strictness
   - [ ] Follows Elixir naming conventions and style guide

4. **Integration**
   - [ ] Module exports public API: `to_graph/1`, `to_turtle/1`, `to_turtle/2`
   - [ ] Works seamlessly with Reader output and Validator output (future)
   - [ ] Generated Turtle is valid and parseable by RDF.ex
   - [ ] SHACL prefix map is consistent with Reader's expectations

## Implementation Plan

### Step 1: Module Scaffolding (30 minutes)

1. Create `lib/elixir_ontologies/shacl/writer.ex`
2. Add module documentation with examples
3. Define all SHACL vocabulary constants (@sh_*, @rdf_type)
4. Define severity mapping constants
5. Define @shacl_prefixes map

### Step 2: Core Conversion - to_graph/1 (1 hour)

1. Implement `to_graph/1` function:
   - Create report blank node
   - Add report type triple
   - Add sh:conforms triple
   - Iterate over results with Enum.reduce
2. Implement `add_validation_result/3` helper:
   - Create result blank node
   - Add all required triples (type, focusNode, sourceShape, severity)
   - Conditionally add optional triples (path, message)
3. Implement `severity_to_iri/1` helper with pattern matching
4. Add error handling (try/rescue for unexpected failures)

### Step 3: Turtle Serialization (45 minutes)

1. Implement `to_turtle/1` for ValidationReport
2. Implement `to_turtle/1` for RDF.Graph
3. Implement `to_turtle/2` with options:
   - Merge user prefixes with @shacl_prefixes
   - Pass through base, indent options to RDF.Turtle.write_string/2
4. Implement `maybe_add_opt/3` helper for optional keyword list building

### Step 4: Test Suite (2 hours)

1. Create `test/elixir_ontologies/shacl/writer_test.exs`
2. Write basic conversion tests:
   - Empty report
   - Single violation
   - Multiple results (mixed severities)
3. Write severity mapping tests (3 tests)
4. Write optional field tests (nil path, nil message)
5. Write focus node type tests (IRI, blank node)
6. Write Turtle serialization tests:
   - Valid syntax (round-trip parse)
   - Prefix declarations present
7. Write round-trip integration test:
   - Create report → to_graph → to_turtle → parse Turtle → verify structure
8. Write edge case tests:
   - Large report (100+ results)
   - Unicode messages
9. Add test helpers (sh_* IRI constructors)
10. Run tests: `mix test test/elixir_ontologies/shacl/writer_test.exs`

### Step 5: Documentation and Examples (30 minutes)

1. Add comprehensive @moduledoc with:
   - Overview of functionality
   - Usage examples (to_graph and to_turtle)
   - SHACL vocabulary explanation
2. Add @doc for all public functions with:
   - Parameter descriptions
   - Return value specifications
   - Usage examples
3. Add inline code comments for complex logic
4. Consider adding doctests for simple examples

### Step 6: Quality Checks (30 minutes)

1. Run type checker: `mix dialyzer`
   - Fix any type errors
2. Run linter: `mix credo --strict`
   - Fix any code style issues
3. Check test coverage: `mix test --cover`
   - Ensure ≥ 95% coverage for writer.ex
4. Run full test suite: `mix test`
   - Ensure no regressions in other modules
5. Generate docs: `mix docs`
   - Verify documentation renders correctly

### Step 7: Integration Validation (30 minutes)

1. Manual integration test:
   ```elixir
   # In IEx
   alias ElixirOntologies.SHACL.{Reader, Writer}
   alias ElixirOntologies.SHACL.Model.{ValidationReport, ValidationResult}

   # Create a sample report
   report = %ValidationReport{
     conforms?: false,
     results: [
       %ValidationResult{
         focus_node: ~I<http://example.org/Module1>,
         path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
         source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
         severity: :violation,
         message: "Test violation",
         details: %{}
       }
     ]
   }

   # Convert to Turtle
   {:ok, turtle} = Writer.to_turtle(report)
   IO.puts(turtle)

   # Parse back to graph
   {:ok, graph} = RDF.Turtle.read_string(turtle)
   RDF.Graph.triples(graph) |> IO.inspect()
   ```

2. Verify Turtle output:
   - Correct prefixes
   - Readable formatting
   - Valid SHACL structure

### Estimated Timeline

- **Step 1 (Scaffolding)**: 30 minutes
- **Step 2 (Core Conversion)**: 1 hour
- **Step 3 (Turtle Serialization)**: 45 minutes
- **Step 4 (Test Suite)**: 2 hours
- **Step 5 (Documentation)**: 30 minutes
- **Step 6 (Quality Checks)**: 30 minutes
- **Step 7 (Integration Validation)**: 30 minutes

**Total: ~6 hours**

## Notes and Considerations

### 1. Blank Node Strategy

**Decision**: Use blank nodes for both ValidationReport and ValidationResult resources.

**Rationale**:
- Validation reports are typically ephemeral (not referenced across documents)
- Blank nodes reduce IRI minting complexity
- SHACL spec doesn't require named IRIs for reports
- Simplifies implementation (no need for IRI generation scheme)

**Alternative** (future extension):
- Add optional `report_iri` parameter to `to_graph/2` for named reports
- Useful for persistent storage or cross-document references

### 2. Details Field Handling

**Decision**: Ignore `ValidationResult.details` map in initial implementation.

**Rationale**:
- SHACL has multiple optional properties for additional context (sh:value, sh:detail, sh:resultAnnotation)
- Details field structure is currently undefined (free-form map)
- No immediate requirement for this data in reports

**Future Extension**:
- Map specific details keys to SHACL properties:
  - `details[:actual_value]` → `sh:value`
  - `details[:constraint_component]` → `sh:sourceConstraintComponent`
  - `details[:expected_value]` → custom annotation
- Requires standardization of details map keys first

### 3. Focus Node Type Handling

ValidationResult.focus_node is typed as RDF.Term.t(), which includes:
- RDF.IRI.t() - Most common (references to resources)
- RDF.BlankNode.t() - Valid but rare (anonymous resources)
- RDF.Literal.t() - Edge case (literals as focus nodes)

**Implementation**: Accept all types without special handling, as RDF.Graph.add/2 accepts any RDF.Term.t().

### 4. Turtle Formatting Options

The writer supports these formatting options via `to_turtle/2`:

- `:prefixes` - Merge custom prefixes with SHACL prefixes (allows adding elixir-code vocab)
- `:base` - Set @base IRI for relative IRI resolution
- `:indent` - Control indentation width (default: 4 spaces)

**Example**:
```elixir
Writer.to_turtle(report,
  prefixes: %{
    struct: "https://w3id.org/elixir-code/structure#",
    shapes: "https://w3id.org/elixir-code/shapes#"
  },
  indent: 2
)
```

### 5. Performance Considerations

- **Blank node generation**: RDF.BlankNode.new() is fast (simple counter increment)
- **Graph building**: RDF.Graph.add/2 is optimized for batch operations
- **Large reports**: Tested with 100+ results should complete in < 100ms
- **Memory**: Each result adds ~10 triples, so 1000 results ≈ 10,000 triples (manageable)

### 6. Error Handling Philosophy

**Strategy**: Fail fast on structural errors, return {:error, reason} tuples.

**Rationale**:
- Invalid structs indicate programming errors (should be caught in tests)
- RDF.Graph operations are generally safe (rare runtime failures)
- Turtle serialization failures are also rare (malformed IRIs)

**Implementation**:
- Wrap `to_graph/1` body in try/rescue for unexpected errors
- Propagate RDF.Turtle.write_string/2 errors directly (already returns {:ok, _} | {:error, _})

### 7. SHACL Vocabulary Completeness

The initial implementation covers the core SHACL validation report vocabulary:

**Included**:
- sh:ValidationReport, sh:ValidationResult (types)
- sh:conforms, sh:result (report properties)
- sh:focusNode, sh:resultPath, sh:sourceShape (result identity)
- sh:resultSeverity, sh:resultMessage (result details)

**Omitted** (future extensions):
- sh:value - Actual value that caused violation (details field)
- sh:sourceConstraintComponent - Which constraint type failed
- sh:detail - Nested detail results
- sh:resultAnnotation - Custom annotations

All omitted properties are optional per SHACL spec.

### 8. Round-trip Testing Strategy

Round-trip testing validates the complete workflow:

1. Create ValidationReport struct (manual or from validator)
2. Convert to RDF graph: `Writer.to_graph/1`
3. Serialize to Turtle: `Writer.to_turtle/1`
4. Parse Turtle: `RDF.Turtle.read_string/1`
5. Verify structure: Check types, properties, values

**Key Assertion**: The parsed graph should be isomorphic to the original graph (ignoring blank node labels).

**Implementation**:
```elixir
test "round-trip: report → graph → turtle → graph maintains structure" do
  report = %ValidationReport{...}

  # Original graph
  {:ok, graph1} = Writer.to_graph(report)

  # Round-trip through Turtle
  {:ok, turtle} = Writer.to_turtle(graph1)
  {:ok, graph2} = RDF.Turtle.read_string(turtle)

  # Graphs should be isomorphic (same triples, different blank node IDs)
  assert RDF.Graph.triple_count(graph1) == RDF.Graph.triple_count(graph2)
  assert graphs_isomorphic?(graph1, graph2)
end
```

### 9. Integration with Phase 11 Workflow

The Writer completes the SHACL infrastructure:

```
Phase 11.1.1 (Data Model)
    ↓ Structs
Phase 11.1.2 (Reader)
    ↓ Parse shapes.ttl → NodeShape structs
Phase 11.1.3 (Writer) ← Current task
    ↓ ValidationReport → Turtle report
Phase 11.2.x (Validator Engine)
    ↓ Use shapes to validate data → ValidationReport
    → Writer.to_turtle(report) → Save report.ttl
```

This enables the complete validation workflow:
1. Parse SHACL shapes (Reader)
2. Validate data graph (Validator - future)
3. Generate validation report (Validator - future)
4. Serialize report to Turtle (Writer)
5. Inspect/store/share report

### 10. SHACL Prefix Standardization

The writer defines canonical SHACL prefixes:

```elixir
@shacl_prefixes %{
  sh: "http://www.w3.org/ns/shacl#",
  rdf: "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
  xsd: "http://www.w3.org/2001/XMLSchema#"
}
```

These should be consistent across Reader, Writer, and future Validator modules for maintainability.

**Consideration**: Extract to shared module (`ElixirOntologies.SHACL.Vocabulary`)?
- **Pros**: Single source of truth, easier updates
- **Cons**: Extra indirection, overkill for 3-4 modules
- **Decision**: Keep module-local for now, consolidate if more SHACL modules are added

## Open Questions

1. **Named vs Blank Node Reports**: Should we support named IRI for ValidationReport?
   - **Recommendation**: Add in future if persistence/cross-document linking is needed

2. **Details Field Mapping**: Which details map keys should map to which SHACL properties?
   - **Recommendation**: Defer to Phase 11.2 (Validator) implementation - see what details are actually generated

3. **Custom Prefixes**: Should Writer automatically include elixir-code vocabulary prefixes?
   - **Recommendation**: No - keep writer generic; users can pass custom prefixes via options

4. **Validation of Validation Reports**: Should Writer validate report structure before serialization?
   - **Recommendation**: No - trust structs are well-formed; use Dialyzer for type safety

5. **File I/O**: Should Writer include `write_file/2` convenience function?
   - **Recommendation**: Yes, add as utility: `Writer.write_file(report, path, opts)`
   - Wraps `to_turtle/2` + `File.write/2`
   - Consistent with ElixirOntologies.Graph.save_file/2 pattern

## References

- **W3C SHACL Specification**: https://www.w3.org/TR/shacl/#validation-report
- **SHACL Validation Report Vocabulary**: https://www.w3.org/TR/shacl/#results-validation-report
- **RDF.ex Documentation**: https://hexdocs.pm/rdf/
- **Phase 11.1.1 Planning**: notes/features/phase-11-1-1-shacl-data-model.md
- **Phase 11.1.2 Planning**: notes/features/phase-11-1-2-shacl-shapes-reader.md
- **SHACL Engine Research**: notes/research/shacl_engine.md
