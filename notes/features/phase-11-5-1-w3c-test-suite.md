# Phase 11.5.1: W3C Test Suite Integration

**STATUS**: In Progress - Infrastructure complete, blocked on implicit class targeting feature

## Current Status Summary

**Completed** (Steps 1-3):
- ✅ Downloaded 52 W3C test files (49 core + 3 SPARQL)
- ✅ Created W3CTestRunner module with RDF manifest parsing
- ✅ Implemented dynamic ExUnit test generation
- ✅ 8/8 parser unit tests passing

**Blocked** (Steps 4-6):
- ❌ W3C tests currently failing (0% pass rate)
- ❌ **Root Cause**: Implicit class targeting not implemented
- ❌ CI integration pending test fixes

See `notes/features/phase-11-5-1-w3c-test-suite-STATUS.md` for detailed status.

---

# Phase 11.5.1: W3C Test Suite Integration

## Problem Statement

Our native Elixir SHACL implementation (Phase 11.1-11.4) needs validation against the official W3C SHACL test suite to ensure compliance with the SHACL specification and identify any gaps in constraint support. Currently, we only have project-specific tests that validate against `elixir-shapes.ttl`, but we lack verification against the standardized W3C SHACL core tests.

**Why This Matters:**

- **Specification Compliance**: Ensures our SHACL implementation correctly interprets the W3C SHACL specification
- **Interoperability**: Validates that we produce compliant validation reports that match reference implementations
- **Quality Assurance**: Identifies edge cases and constraint combinations we may have missed
- **Future-Proofing**: Provides regression testing as we enhance the implementation
- **Credibility**: Demonstrates conformance to industry standards (targeting >90% pass rate)

**Context:**

The W3C Data Shapes Working Group maintains an official test suite at https://github.com/w3c/data-shapes with 121 core validation tests covering all SHACL constraint components. Each test includes:
- Data graph to validate
- Shapes graph with constraints
- Expected validation report (conformance + detailed results)
- Test metadata (status: proposed/approved/rejected)

## Solution Overview

Integrate a curated subset of the W3C SHACL test suite into our test infrastructure by:

1. **Downloading Core Tests**: Obtain W3C core constraint tests from GitHub (node shapes, property shapes, cardinality, type, string, value, qualified constraints)
2. **Creating Manifest Parser**: Build RDF manifest parser to read W3C test definitions (uses `mf:Manifest`, `sht:Validate` vocabulary)
3. **Implementing Test Runner**: Create ExUnit test generator that dynamically creates tests from manifest entries
4. **Categorizing Tests**: Separate tests into "expected to pass" (core constraints we support) vs "known limitations" (complex SPARQL)
5. **Documenting Results**: Track pass rates and document any W3C features we intentionally don't support

**High-Level Architecture:**

```
W3C Test Suite (GitHub)
    ↓ (download/commit to repo)
test/fixtures/w3c/
    ├── core/
    │   ├── node/          (sh:and, sh:or, sh:datatype, etc.)
    │   └── property/      (sh:minCount, sh:class, sh:pattern, etc.)
    └── manifests/
        └── core-manifest.ttl
    ↓ (parsed at test runtime)
ElixirOntologies.SHACL.W3CTestRunner
    ↓ (generates ExUnit tests)
test/elixir_ontologies/shacl/w3c_test.exs
    ↓ (runs validation)
SHACL.validate/3 API
    ↓ (produces)
ValidationReport
    ↓ (compared to)
Expected Result from Manifest
```

**Key Design Decisions:**

1. **Commit Tests to Repo**: Store curated W3C tests in `test/fixtures/w3c/` for reproducibility (not dynamic downloads)
2. **Dynamic Test Generation**: Use ExUnit's runtime test generation to create one test case per manifest entry
3. **Partial Compliance Initially**: Target boolean conformance first (`sh:conforms`), full report isomorphism later
4. **SPARQL Filtering**: Explicitly exclude SPARQL constraint tests with known SPARQL.ex limitations
5. **Manifest-Driven**: Parse official W3C manifest format rather than inventing our own structure

## Agent Consultations Performed

### research-agent: W3C SHACL Test Suite Structure and Format

**Question**: What is the structure, format, and location of the W3C SHACL test suite? How are tests organized and manifested?

**Findings**:

**Test Suite Location:**
- Official repository: https://github.com/w3c/data-shapes (gh-pages branch)
- Test suite path: `data-shapes-test-suite/tests/`
- Documentation: https://w3c.github.io/data-shapes/data-shapes-test-suite/
- Categories: `core/` (121 tests), `sparql/` (SPARQL-based constraints)

**Test Organization:**
- Hierarchical folders: `core/node/`, `core/property/`, `core/complex/`, `core/validation-reports/`
- Each folder contains manifest files listing test cases
- Individual test files in Turtle format (.ttl)

**Manifest Format (RDF Turtle):**
```turtle
@prefix mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#> .
@prefix sht: <http://www.w3.org/ns/shacl-test#> .
@prefix sh: <http://www.w3.org/ns/shacl#> .

<> a mf:Manifest ;
   rdfs:label "Core Node Constraint Tests" ;
   mf:entries (
     <#and-001>
     <#or-001>
     <#datatype-001>
     # ... more tests
   ) .

<#and-001> a sht:Validate ;
   mf:name "sh:and with multiple alternatives" ;
   mf:action [
     sht:shapesGraph <and-001-shapes.ttl> ;
     sht:dataGraph <and-001-data.ttl> ;
   ] ;
   mf:result <and-001-result.ttl> ;  # Expected ValidationReport
   mf:status sht:approved .
```

**Test Case Structure:**
- Each test is typed `sht:Validate` (validation test)
- `mf:action` specifies `sht:shapesGraph` and `sht:dataGraph` (input files)
- `mf:result` specifies expected `sh:ValidationReport` (expected output)
- `mf:status` indicates test maturity: `sht:proposed`, `sht:approved`, `sht:rejected`

**Pass/Fail Criteria:**
- **Partial Compliance**: Correct `sh:conforms` boolean value
- **Full Compliance**: Validation report is graph-isomorphic to expected result (after normalization: ignore blank node IDs, nested results, filter to specific predicates)

**Test Categories:**
- **Node Shapes**: sh:and, sh:or, sh:xone, sh:not, sh:datatype, sh:nodeKind, sh:minInclusive, etc.
- **Property Shapes**: sh:minCount, sh:maxCount, sh:class, sh:pattern, sh:minLength, sh:in, sh:hasValue, etc.
- **Qualified Constraints**: sh:qualifiedValueShape, sh:qualifiedMinCount, sh:qualifiedMaxCount
- **SPARQL Constraints**: sh:sparql with custom SPARQL queries (separate category)

**Download Strategy:**
- Use raw GitHub URLs: `https://raw.githubusercontent.com/w3c/data-shapes/gh-pages/data-shapes-test-suite/tests/core/...`
- Commit curated subset to `test/fixtures/w3c/` for version control and reproducibility
- Focus on `core/node/` and `core/property/` tests (avoid complex SPARQL tests initially)

**References:**
- [SHACL Test Suite Documentation](https://w3c.github.io/data-shapes/data-shapes-test-suite/)
- [W3C Data Shapes Repository](https://github.com/w3c/data-shapes)
- [SHACL 1.2 Core Specification](https://www.w3.org/TR/shacl12-core/)

### elixir-expert: Parsing RDF Manifests and ExUnit Integration

**Question**: What are the best practices for parsing RDF test manifests in Elixir and dynamically generating ExUnit tests from external data sources?

**Recommendations**:

**RDF Manifest Parsing (Using RDF.ex):**

The project already uses `rdf` library (see `mix.exs`), which provides Turtle parsing. For manifest parsing:

```elixir
# Parse manifest file
{:ok, manifest_graph} = RDF.Turtle.read_file("test/fixtures/w3c/manifest.ttl")

# Query for manifest entries (RDF list)
entries_list = RDF.Graph.get(manifest_graph,
  manifest_iri,
  ~I<http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#entries>
)

# Convert RDF list to Elixir list
test_iris = RDF.List.values(entries_list, manifest_graph)

# For each test IRI, extract metadata
for test_iri <- test_iris do
  name = get_literal(manifest_graph, test_iri, mf_name)
  action = get_object(manifest_graph, test_iri, mf_action)
  shapes_graph_file = get_object(manifest_graph, action, sht_shapesGraph)
  data_graph_file = get_object(manifest_graph, action, sht_dataGraph)
  result_file = get_object(manifest_graph, test_iri, mf_result)
  status = get_object(manifest_graph, test_iri, mf_status)

  %{name: name, shapes: shapes_graph_file, data: data_graph_file, ...}
end
```

**RDF List Traversal:**

The existing `SHACL.Reader` module already has list traversal logic (see `parse_rdf_list/2` function). We can reuse this pattern:

```elixir
defp parse_rdf_list(graph, list_node, acc \\ [], depth \\ 0)
defp parse_rdf_list(_graph, @rdf_nil, acc, _depth), do: {:ok, Enum.reverse(acc)}
defp parse_rdf_list(_graph, _node, _acc, depth) when depth > @max_list_depth do
  {:error, "RDF list depth exceeds maximum (#{@max_list_depth})"}
end
defp parse_rdf_list(graph, list_node, acc, depth) do
  # Get rdf:first and rdf:rest...
end
```

**Dynamic ExUnit Test Generation:**

ExUnit supports compile-time and runtime test generation. For manifest-driven tests, use compile-time macros:

```elixir
defmodule ElixirOntologies.SHACL.W3CTest do
  use ExUnit.Case, async: true

  @moduletag :w3c_test_suite

  # Parse manifests at compile time
  @test_cases ElixirOntologies.SHACL.W3CTestRunner.load_tests()

  # Generate one test per manifest entry
  for test_case <- @test_cases do
    @test_case test_case
    test test_case.name do
      # Access compile-time assigned test case
      tc = @test_case

      # Load data and shapes
      {:ok, data} = RDF.Turtle.read_file(tc.data_file)
      {:ok, shapes} = RDF.Turtle.read_file(tc.shapes_file)
      {:ok, expected} = load_expected_result(tc.result_file)

      # Run validation
      {:ok, report} = SHACL.validate(data, shapes)

      # Assert conformance matches
      assert report.conforms? == expected.conforms?,
        "Expected conforms=#{expected.conforms?}, got #{report.conforms?}"
    end
  end
end
```

**Best Practices:**

1. **Compile-Time Parsing**: Parse manifests during compilation to catch errors early
2. **Descriptive Test Names**: Use manifest `mf:name` as ExUnit test description for clear output
3. **Test Tagging**: Tag W3C tests with `@moduletag :w3c_test_suite` for selective running
4. **Categorization**: Use `@tag category: :core` or `@tag category: :sparql` for filtering
5. **Skip Known Failures**: Use `@tag :skip` or `ExUnit.Case.skip/1` for tests with known limitations
6. **Fixture Organization**: Mirror W3C structure in `test/fixtures/w3c/core/node/`, etc.

**Module Structure:**

```
lib/elixir_ontologies/shacl/
  └── w3c_test_runner.ex       # Manifest parser and test case loader

test/elixir_ontologies/shacl/
  └── w3c_test.exs              # Dynamic test generation

test/fixtures/w3c/
  ├── core/
  │   ├── node/
  │   │   ├── and-001.ttl       # Test data/shapes (combined or separate)
  │   │   ├── or-001.ttl
  │   │   └── ...
  │   └── property/
  │       ├── minCount-001.ttl
  │       └── ...
  └── manifests/
      └── core-manifest.ttl     # Master manifest
```

**Pattern Consistency:**

Follow existing test patterns from `test/elixir_ontologies/shacl_test.exs`:
- Use `async: true` for parallel test execution
- Use `RDF.Turtle.read_file/1` for loading graphs
- Use `SHACL.validate/3` public API (not internal Validator)
- Assert on `ValidationReport` structure and `conforms?` boolean

**Error Handling:**

```elixir
# Graceful handling of missing files
case RDF.Turtle.read_file(path) do
  {:ok, graph} -> graph
  {:error, reason} ->
    flunk("Failed to load test fixture #{path}: #{inspect(reason)}")
end
```

### senior-engineer-reviewer: Test Organization Strategy and Success Criteria

**Question**: What is the optimal strategy for integrating 121 W3C tests into our test suite, and what realistic success criteria should we target given our known SPARQL limitations?

**Strategic Assessment**:

**Test Selection Strategy:**

**Phase 1: Core Constraint Tests (Target: >90% pass rate)**

Focus on tests that exercise constraints we've implemented:
- Cardinality: sh:minCount, sh:maxCount
- Type: sh:datatype, sh:class, sh:nodeKind
- String: sh:pattern, sh:minLength, sh:maxLength
- Value: sh:in, sh:hasValue, sh:minInclusive, sh:maxInclusive
- Logical: sh:and, sh:or, sh:xone, sh:not
- Qualified: sh:qualifiedValueShape, sh:qualifiedMinCount, sh:qualifiedMaxCount

**Phase 2: Known Limitations (Document, don't run)**

Explicitly exclude and document:
- Complex SPARQL with nested subqueries
- SPARQL with `FILTER NOT EXISTS` (known SPARQL.ex limitation per Phase 11.3)
- Advanced path expressions (sh:alternativePath, sh:inversePath, sh:oneOrMorePath)
- Closed shapes (sh:closed, sh:ignoredProperties) if not implemented

**Realistic Success Criteria:**

Given our implementation scope (Phase 11.1-11.4):

1. **Core Constraints: >90% pass rate** (realistic target)
   - We implemented all core constraint validators
   - Edge cases may still exist (e.g., specific datatype coercion rules)

2. **SPARQL Constraints: 50-70% pass rate** (acceptable given limitations)
   - Simple SPARQL constraints should work
   - Complex nested queries will fail (documented limitation)

3. **Overall: >85% pass rate** (strong showing for native implementation)
   - Demonstrates specification compliance
   - Competitive with other implementations (report shows 68-100% range)

**Test Organization Architecture:**

**Directory Structure:**
```
test/fixtures/w3c/
  ├── core/                    # Core constraint tests (focus here)
  │   ├── node/               # Node shape tests (~30 tests)
  │   ├── property/           # Property shape tests (~40 tests)
  │   ├── misc/               # Miscellaneous (~20 tests)
  │   └── complex/            # Complex shapes (~15 tests)
  ├── sparql/                  # SPARQL constraint tests (careful selection)
  │   ├── component/          # sh:SPARQLConstraintComponent
  │   └── pre-binding/        # SPARQL with sh:prefixes
  ├── manifests/
  │   ├── core-manifest.ttl   # Master manifest for core tests
  │   └── sparql-manifest.ttl # SPARQL tests (subset)
  └── README.md               # Attribution and update instructions
```

**Test Execution Strategy:**

1. **Categorized Test Modules:**
   ```elixir
   # test/elixir_ontologies/shacl/w3c_core_test.exs
   @moduletag :w3c_core
   @moduletag timeout: 1000  # Fast tests

   # test/elixir_ontologies/shacl/w3c_sparql_test.exs
   @moduletag :w3c_sparql
   @moduletag :skip_in_ci  # Skip known failures in CI
   ```

2. **Selective Execution:**
   ```bash
   # Run only core tests (should pass >90%)
   mix test --only w3c_core

   # Run all W3C tests including SPARQL (expect some failures)
   mix test --include w3c_sparql
   ```

3. **Failure Documentation:**
   ```elixir
   @tag :known_limitation
   @tag skip: "Requires SPARQL.ex support for nested NOT EXISTS"
   test "complex-sparql-001" do
     # Test definition (for documentation)
   end
   ```

**Continuous Integration Impact:**

- **CI Default**: Run core tests only (fast, high pass rate, CI green)
- **Nightly/Manual**: Run full suite including SPARQL (identify regressions)
- **Fail CI on Core Regressions**: If core pass rate drops below 90%
- **Allow SPARQL Failures**: Expected until SPARQL.ex limitations resolved

**Scalability Considerations:**

1. **Incremental Adoption**: Start with 20-30 core tests, expand to full 121 as confidence grows
2. **Manifest Versioning**: Document which W3C test suite version we're testing against
3. **Automated Updates**: Script to fetch latest W3C tests (run manually, not in CI)
4. **Performance**: 121 tests should run in <5 seconds (RDF parsing is fast, validation is parallel)

**Quality Metrics:**

Track over time in CI:
```
W3C SHACL Test Suite Results:
  Core Constraints: 92/100 (92%) ✓
  SPARQL Constraints: 12/21 (57%) ⚠
  Overall: 104/121 (86%) ✓

Known Limitations: 17 tests (documented in test/fixtures/w3c/LIMITATIONS.md)
```

**Long-Term Maintainability:**

1. **Upstream Tracking**: Document test suite commit hash we're based on
2. **Change Management**: Review new W3C tests before adding (avoid breaking changes)
3. **Regression Prevention**: Lock passing tests (new failures = regressions)
4. **Documentation**: Each limitation documented with:
   - Test name
   - SHACL feature required
   - Why we don't support it
   - Potential future implementation path

**Risk Assessment:**

**Low Risk:**
- Breaking existing elixir-shapes.ttl tests (W3C tests are additive)
- Performance degradation (tests are small, run in parallel)

**Medium Risk:**
- Uncovering bugs in our constraint validators (good to find early!)
- Manifest parsing complexity (RDF.ex handles this well)

**High Risk (Mitigated):**
- False sense of completeness if we cherry-pick easy tests
  - **Mitigation**: Run comprehensive core suite, document all exclusions
- Test suite version drift from W3C updates
  - **Mitigation**: Pin to specific commit, document update process

**Recommendation**:

Start with **Phase 1 approach** (core constraints only, ~60-80 tests). Achieve >90% pass rate. Document all failures as either bugs to fix or known limitations. This provides high value (specification compliance) with manageable scope and clear success criteria.

## Technical Details

### Test Suite Download and Organization

**Source Repository:**
- GitHub: https://github.com/w3c/data-shapes
- Branch: `gh-pages`
- Base Path: `data-shapes-test-suite/tests/`

**Downloaded Test Categories:**

1. **Core Node Tests** (`core/node/`):
   - `and-*.ttl` - sh:and constraint tests
   - `or-*.ttl` - sh:or constraint tests
   - `xone-*.ttl` - sh:xone (exclusive or) tests
   - `not-*.ttl` - sh:not constraint tests
   - `datatype-*.ttl` - sh:datatype tests
   - `class-*.ttl` - sh:class tests
   - `nodeKind-*.ttl` - sh:nodeKind tests
   - `minInclusive-*.ttl`, `maxInclusive-*.ttl` - numeric range tests
   - `minExclusive-*.ttl`, `maxExclusive-*.ttl` - exclusive range tests
   - `languageIn-*.ttl` - language tag tests

2. **Core Property Tests** (`core/property/`):
   - `minCount-*.ttl`, `maxCount-*.ttl` - cardinality tests
   - `pattern-*.ttl` - regex pattern tests
   - `minLength-*.ttl`, `maxLength-*.ttl` - string length tests
   - `in-*.ttl` - sh:in enumeration tests
   - `hasValue-*.ttl` - sh:hasValue tests
   - `node-*.ttl` - property with nested node shapes

3. **Qualified Constraints** (`core/property/` or `core/misc/`):
   - `qualifiedValueShape-*.ttl` - qualified shape constraints
   - `qualifiedMinCount-*.ttl`, `qualifiedMaxCount-*.ttl` - qualified cardinality

4. **SPARQL Constraints** (selective, `sparql/`):
   - `component/sparql-*.ttl` - Simple SPARQL constraint validators
   - Exclude: Complex nested subqueries, FILTER NOT EXISTS patterns

**Local Directory Structure:**

```
test/fixtures/w3c/
├── README.md                           # Attribution, version, update instructions
├── LIMITATIONS.md                      # Documented unsupported features
├── core/
│   ├── node/
│   │   ├── and-001.ttl
│   │   ├── or-001.ttl
│   │   ├── datatype-001.ttl
│   │   └── ... (30-40 test files)
│   ├── property/
│   │   ├── minCount-001.ttl
│   │   ├── pattern-001.ttl
│   │   └── ... (40-50 test files)
│   └── misc/
│       ├── qualifiedValueShape-001.ttl
│       └── ... (10-20 test files)
├── sparql/                             # Optional, later phase
│   └── component/
│       ├── ask-001.ttl
│       └── ... (10-15 simple tests)
└── manifests/
    ├── core-node-manifest.ttl          # Generated or curated manifest
    ├── core-property-manifest.ttl
    └── core-manifest.ttl               # Master manifest including all core tests
```

### Manifest Parser Module

**Module:** `ElixirOntologies.SHACL.W3CTestRunner`

**Location:** `lib/elixir_ontologies/shacl/w3c_test_runner.ex`

**Responsibilities:**
- Parse W3C RDF manifests (Turtle format)
- Extract test metadata (name, status, action, result)
- Resolve file paths relative to manifest location
- Convert RDF test definitions to Elixir structs
- Provide test case list for ExUnit test generation

**Data Structures:**

```elixir
defmodule ElixirOntologies.SHACL.W3CTestRunner.TestCase do
  @moduledoc "Represents a single W3C SHACL test case"

  @type t :: %__MODULE__{
    id: RDF.IRI.t(),
    name: String.t(),
    status: :proposed | :approved | :rejected,
    shapes_graph_file: Path.t(),
    data_graph_file: Path.t(),
    expected_result_file: Path.t() | nil,
    expected_conforms: boolean() | nil,
    category: :core_node | :core_property | :sparql | :misc
  }

  defstruct [
    :id,
    :name,
    :status,
    :shapes_graph_file,
    :data_graph_file,
    :expected_result_file,
    :expected_conforms,
    :category
  ]
end
```

**Key Functions:**

```elixir
@spec load_manifest(Path.t()) :: {:ok, [TestCase.t()]} | {:error, term()}
def load_manifest(manifest_file)

@spec load_all_tests() :: [TestCase.t()]
def load_all_tests()  # Loads from all manifests in test/fixtures/w3c/manifests/

@spec parse_test_entry(RDF.Graph.t(), RDF.IRI.t(), Path.t()) :: {:ok, TestCase.t()} | {:error, term()}
defp parse_test_entry(graph, test_iri, manifest_dir)

@spec parse_expected_result(Path.t()) :: {:ok, %{conforms: boolean()}} | {:error, term()}
defp parse_expected_result(result_file)
```

**RDF Vocabularies:**

```elixir
@mf_manifest ~I<http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#Manifest>
@mf_entries ~I<http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#entries>
@mf_name ~I<http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#name>
@mf_action ~I<http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#action>
@mf_result ~I<http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#result>
@mf_status ~I<http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#status>

@sht_validate ~I<http://www.w3.org/ns/shacl-test#Validate>
@sht_shapes_graph ~I<http://www.w3.org/ns/shacl-test#shapesGraph>
@sht_data_graph ~I<http://www.w3.org/ns/shacl-test#dataGraph>
@sht_proposed ~I<http://www.w3.org/ns/shacl-test#proposed>
@sht_approved ~I<http://www.w3.org/ns/shacl-test#approved>
@sht_rejected ~I<http://www.w3.org/ns/shacl-test#rejected>

@sh_conforms ~I<http://www.w3.org/ns/shacl#conforms>
@sh_validation_report ~I<http://www.w3.org/ns/shacl#ValidationReport>
```

**Parsing Logic:**

```elixir
def load_manifest(manifest_file) do
  with {:ok, graph} <- RDF.Turtle.read_file(manifest_file),
       {:ok, manifest_iri} <- find_manifest_iri(graph),
       {:ok, entries_list} <- get_entries_list(graph, manifest_iri),
       {:ok, test_iris} <- parse_rdf_list(graph, entries_list),
       manifest_dir <- Path.dirname(manifest_file) do

    test_cases =
      Enum.map(test_iris, fn test_iri ->
        parse_test_entry(graph, test_iri, manifest_dir)
      end)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, tc} -> tc end)

    {:ok, test_cases}
  end
end

defp parse_test_entry(graph, test_iri, manifest_dir) do
  with {:ok, name} <- get_literal(graph, test_iri, @mf_name),
       {:ok, action} <- get_object(graph, test_iri, @mf_action),
       {:ok, shapes_file} <- get_object(graph, action, @sht_shapes_graph),
       {:ok, data_file} <- get_object(graph, action, @sht_data_graph) do

    status = get_status(graph, test_iri)
    result_file = get_optional_object(graph, test_iri, @mf_result)

    shapes_path = resolve_path(manifest_dir, shapes_file)
    data_path = resolve_path(manifest_dir, data_file)
    result_path = result_file && resolve_path(manifest_dir, result_file)

    expected_conforms =
      if result_path do
        parse_expected_conforms(result_path)
      else
        nil
      end

    {:ok, %TestCase{
      id: test_iri,
      name: name,
      status: status,
      shapes_graph_file: shapes_path,
      data_graph_file: data_path,
      expected_result_file: result_path,
      expected_conforms: expected_conforms,
      category: infer_category(shapes_path)
    }}
  end
end
```

### ExUnit Test Generation

**Module:** `ElixirOntologies.SHACL.W3CTest`

**Location:** `test/elixir_ontologies/shacl/w3c_test.exs`

**Test Generation Pattern:**

```elixir
defmodule ElixirOntologies.SHACL.W3CTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.SHACL
  alias ElixirOntologies.SHACL.W3CTestRunner

  @moduletag :w3c_test_suite
  @moduletag timeout: 2000

  # Load test cases at compile time
  @test_cases W3CTestRunner.load_all_tests()

  # Group by category for reporting
  @core_node_tests Enum.filter(@test_cases, &(&1.category == :core_node))
  @core_property_tests Enum.filter(@test_cases, &(&1.category == :core_property))
  @sparql_tests Enum.filter(@test_cases, &(&1.category == :sparql))

  describe "W3C Core Node Constraint Tests" do
    for test_case <- @core_node_tests do
      @test_case test_case
      @tag category: :core_node
      @tag w3c_test: true

      # Skip rejected tests
      if test_case.status == :rejected do
        @tag :skip
      end

      test test_case.name do
        run_test_case(@test_case)
      end
    end
  end

  describe "W3C Core Property Constraint Tests" do
    for test_case <- @core_property_tests do
      @test_case test_case
      @tag category: :core_property
      @tag w3c_test: true

      if test_case.status == :rejected do
        @tag :skip
      end

      test test_case.name do
        run_test_case(@test_case)
      end
    end
  end

  describe "W3C SPARQL Constraint Tests (Known Limitations)" do
    for test_case <- @sparql_tests do
      @test_case test_case
      @tag category: :sparql
      @tag w3c_test: true
      @tag :known_sparql_limitations

      # Many SPARQL tests expected to fail - don't fail CI
      if has_known_limitation?(@test_case) do
        @tag skip: "SPARQL.ex limitation: #{limitation_reason(@test_case)}"
      end

      test test_case.name do
        run_test_case(@test_case)
      end
    end
  end

  # Test execution helper
  defp run_test_case(test_case) do
    # Load data and shapes graphs
    {:ok, data_graph} = RDF.Turtle.read_file(test_case.data_graph_file)
    {:ok, shapes_graph} = RDF.Turtle.read_file(test_case.shapes_graph_file)

    # Run SHACL validation
    {:ok, report} = SHACL.validate(data_graph, shapes_graph)

    # Assert conformance matches expected
    if test_case.expected_conforms do
      assert report.conforms? == test_case.expected_conforms,
        """
        Test: #{test_case.name}
        Expected conforms: #{test_case.expected_conforms}
        Actual conforms: #{report.conforms?}
        Violations: #{length(report.results)}
        """
    else
      # No expected result file - just ensure validation runs
      assert is_struct(report, SHACL.Model.ValidationReport)
    end

    # Optional: Check detailed validation results (full compliance)
    if test_case.expected_result_file && full_compliance_mode?() do
      assert_report_matches_expected(report, test_case.expected_result_file)
    end
  end

  # Helper to check for known SPARQL limitations
  defp has_known_limitation?(test_case) do
    # Check if test uses complex SPARQL features we don't support
    case File.read!(test_case.shapes_graph_file) do
      content when content =~ "FILTER NOT EXISTS" -> true
      content when content =~ "SELECT (COUNT" -> true  # Nested subqueries
      _ -> false
    end
  end

  defp limitation_reason(test_case) do
    content = File.read!(test_case.shapes_graph_file)
    cond do
      content =~ "FILTER NOT EXISTS" -> "FILTER NOT EXISTS not supported by SPARQL.ex"
      content =~ "SELECT (COUNT" -> "Nested subqueries not fully supported"
      true -> "Complex SPARQL pattern"
    end
  end
end
```

### Configuration and Execution

**Mix Test Configuration:**

Add to `mix.exs` test configuration:

```elixir
def project do
  [
    # ...
    test_coverage: [
      ignore_modules: [ElixirOntologies.SHACL.W3CTestRunner]  # Don't count test infrastructure
    ],
    preferred_cli_env: [
      "test.w3c": :test,
      "test.w3c.core": :test
    ]
  ]
end
```

**Test Execution Commands:**

```bash
# Run all W3C tests
mix test test/elixir_ontologies/shacl/w3c_test.exs

# Run only core constraint tests (should pass >90%)
mix test --only category:core_node
mix test --only category:core_property

# Run including SPARQL tests (expect failures)
mix test --include known_sparql_limitations

# Run W3C tests excluding known limitations
mix test test/elixir_ontologies/shacl/w3c_test.exs --exclude known_sparql_limitations

# Get detailed output for failures
mix test test/elixir_ontologies/shacl/w3c_test.exs --trace
```

**CI Integration:**

Add to CI workflow (`.github/workflows/ci.yml` or equivalent):

```yaml
- name: Run W3C SHACL Core Tests
  run: mix test --only w3c_test --exclude known_sparql_limitations

- name: Report W3C Test Pass Rate
  run: |
    mix test --only w3c_test --exclude known_sparql_limitations --formatter json > w3c_results.json
    # Parse and report pass rate
```

### Documentation Files

**test/fixtures/w3c/README.md:**

```markdown
# W3C SHACL Test Suite

This directory contains a curated subset of the official W3C SHACL test suite
for validating our native Elixir SHACL implementation.

## Source

- **Repository**: https://github.com/w3c/data-shapes
- **Branch**: gh-pages
- **Path**: data-shapes-test-suite/tests/
- **Version**: Commit [hash] from [date]

## Test Categories

- `core/node/`: Node shape constraint tests (sh:and, sh:or, sh:datatype, etc.)
- `core/property/`: Property shape constraint tests (sh:minCount, sh:pattern, etc.)
- `core/misc/`: Qualified constraints and miscellaneous tests
- `sparql/`: SPARQL-based constraint tests (selective inclusion)

## Updating Tests

To update to latest W3C test suite:

1. Check for new tests: https://github.com/w3c/data-shapes/tree/gh-pages/data-shapes-test-suite/tests
2. Download new test files to appropriate category directories
3. Update manifests to include new tests
4. Run tests and document any new limitations in LIMITATIONS.md
5. Update version/commit in this README

## Attribution

These tests are copyright W3C and distributed under the W3C Software License:
https://www.w3.org/Consortium/Legal/2015/copyright-software-and-document
```

**test/fixtures/w3c/LIMITATIONS.md:**

```markdown
# Known Limitations and Unsupported W3C SHACL Features

This document tracks W3C SHACL test cases we intentionally skip due to known
limitations in our implementation or dependencies.

## SPARQL Constraint Limitations

**Root Cause**: SPARQL.ex library limitations with complex query patterns

### FILTER NOT EXISTS

- **Tests Affected**: sparql/component/filter-not-exists-*.ttl (3 tests)
- **SHACL Feature**: sh:sparql with FILTER NOT EXISTS clauses
- **Status**: Not supported by SPARQL.ex as of v0.3.x
- **Workaround**: None currently
- **Future**: May be resolved by SPARQL.ex updates or alternative SPARQL engine

### Nested Subqueries

- **Tests Affected**: sparql/component/nested-select-*.ttl (2 tests)
- **SHACL Feature**: sh:sparql with SELECT inside SELECT
- **Status**: Partially supported, complex nesting fails
- **Workaround**: Restructure SPARQL queries to avoid deep nesting
- **Future**: Improve SPARQL.ex parser or contribute fix upstream

## Advanced Path Expressions (Not Implemented)

**Root Cause**: Not part of Phase 11 scope

### Alternative Paths

- **Tests Affected**: core/path/alternativePath-*.ttl (estimated 2-3 tests)
- **SHACL Feature**: sh:alternativePath (path1 | path2)
- **Status**: Not implemented (Phase 11 focused on property paths only)
- **Workaround**: Multiple property shapes instead of alternative paths
- **Future**: Potential Phase 12 feature

### Inverse Paths

- **Tests Affected**: core/path/inversePath-*.ttl (estimated 2-3 tests)
- **SHACL Feature**: sh:inversePath (^property)
- **Status**: Not implemented
- **Workaround**: Create shapes on both sides of relationship
- **Future**: Potential Phase 12 feature

## Pass Rate Impact

- **Total W3C Core Tests**: 121
- **Tests Affected by Limitations**: ~10-15 (8-12%)
- **Expected Pass Rate**: >90% (110+ tests passing)
- **SPARQL Tests**: Separate category, 50-70% pass rate acceptable

## Updating This Document

When adding new test limitations:

1. Identify root cause (dependency limitation vs not implemented)
2. List affected test files and count
3. Document SHACL feature involved
4. Note workarounds if available
5. Assess future implementation feasibility
```

## Success Criteria

**Phase 11.5.1 is complete when:**

### Core Test Integration (Required for Completion)

- [ ] Downloaded 60-80 W3C core constraint tests to `test/fixtures/w3c/core/`
- [ ] Created manifest parser (`W3CTestRunner`) that successfully parses W3C RDF manifests
- [ ] Implemented dynamic ExUnit test generation in `w3c_test.exs`
- [ ] **All core constraint tests run successfully** (no parsing errors, tests execute)
- [ ] **>90% pass rate on core constraint tests** (at least 54/60 or 72/80 tests passing)

### SPARQL Test Integration (Required for Completion)

- [ ] Downloaded 10-15 simple SPARQL constraint tests to `test/fixtures/w3c/sparql/`
- [ ] SPARQL tests execute (may fail, but should run without errors)
- [ ] Tests with known limitations are tagged `@tag :skip` with documented reasons
- [ ] **>50% pass rate on SPARQL tests** (acceptable given known SPARQL.ex limitations)

### Documentation (Required for Completion)

- [ ] Created `test/fixtures/w3c/README.md` with attribution, version, update instructions
- [ ] Created `test/fixtures/w3c/LIMITATIONS.md` documenting all known unsupported features
- [ ] Each skipped test has documented reason in test file or LIMITATIONS.md
- [ ] Updated project README or docs to mention W3C test suite compliance

### Test Quality (Required for Completion)

- [ ] Tests run in parallel (`async: true`)
- [ ] Tests complete in <10 seconds total
- [ ] No flaky tests (deterministic results)
- [ ] CI runs W3C core tests on every commit (excluding known limitations)
- [ ] Test output clearly shows pass rate by category (core node, core property, SPARQL)

### Regression Prevention (Required for Completion)

- [ ] Passing tests locked in (future failures = regressions)
- [ ] CI fails if core test pass rate drops below 90%
- [ ] Test manifest version documented (W3C commit hash)

## Implementation Plan

### Step 1: Download and Organize W3C Test Files

**Objective**: Obtain curated subset of W3C SHACL test suite and organize in project structure

**Tasks**:

- [ ] Create directory structure `test/fixtures/w3c/{core,sparql,manifests}/`
- [ ] Research W3C test suite structure at https://github.com/w3c/data-shapes/tree/gh-pages/data-shapes-test-suite/tests
- [ ] Download core node constraint tests (sh:and, sh:or, sh:datatype, sh:class, sh:nodeKind, sh:minInclusive, sh:maxInclusive, etc.)
  - Target: ~30-40 test files from `core/node/`
- [ ] Download core property constraint tests (sh:minCount, sh:maxCount, sh:pattern, sh:minLength, sh:in, sh:hasValue, etc.)
  - Target: ~30-40 test files from `core/property/`
- [ ] Download qualified constraint tests (sh:qualifiedValueShape, sh:qualifiedMinCount, etc.)
  - Target: ~10-15 test files from `core/misc/` or `core/property/`
- [ ] Download 10-15 simple SPARQL constraint tests from `sparql/component/`
  - Exclude: Tests with FILTER NOT EXISTS, complex nested subqueries
- [ ] Create `test/fixtures/w3c/README.md` with attribution and W3C commit hash
- [ ] Document downloaded tests in README (counts by category)

**Success Criteria**:
- 60-80 core test files downloaded and organized
- 10-15 SPARQL test files downloaded
- README.md with proper W3C attribution and version

**Estimated Effort**: 2-3 hours (manual download and organization)

### Step 2: Create Test Manifest Parser

**Objective**: Implement RDF manifest parser to extract W3C test metadata

**Tasks**:

- [ ] Create module `ElixirOntologies.SHACL.W3CTestRunner` in `lib/elixir_ontologies/shacl/w3c_test_runner.ex`
- [ ] Define `TestCase` struct with fields: id, name, status, shapes_graph_file, data_graph_file, expected_result_file, expected_conforms, category
- [ ] Implement RDF vocabulary constants for manifest parsing (mf:Manifest, mf:entries, sht:Validate, etc.)
- [ ] Implement `load_manifest/1` function to parse Turtle manifest file
  - Use `RDF.Turtle.read_file/1` to load manifest graph
  - Find manifest IRI (subject of type mf:Manifest)
  - Extract mf:entries RDF list
- [ ] Implement `parse_rdf_list/2` helper to convert RDF list to Elixir list
  - Reuse pattern from `SHACL.Reader.parse_rdf_list/2`
  - Traverse rdf:first/rdf:rest chain
  - Return list of test IRIs
- [ ] Implement `parse_test_entry/3` to extract test metadata
  - Extract mf:name (test name)
  - Extract mf:action (action blank node)
  - Extract sht:shapesGraph and sht:dataGraph from action
  - Extract mf:result (expected result file)
  - Extract mf:status (proposed/approved/rejected)
  - Resolve file paths relative to manifest directory
- [ ] Implement `parse_expected_result/1` to extract sh:conforms boolean
  - Load result file as RDF graph
  - Find ValidationReport node
  - Extract sh:conforms value
- [ ] Implement `load_all_tests/0` to load from all manifests in test/fixtures/w3c/manifests/
- [ ] Write unit tests for W3CTestRunner in `test/elixir_ontologies/shacl/w3c_test_runner_test.exs`
  - Test manifest parsing with sample manifest
  - Test RDF list parsing
  - Test file path resolution
  - Test expected result parsing

**Success Criteria**:
- W3CTestRunner successfully parses W3C manifest format
- Returns list of TestCase structs with all metadata
- Unit tests verify manifest parsing correctness
- Handles missing or malformed manifests gracefully

**Estimated Effort**: 4-6 hours (RDF parsing, path resolution, error handling)

### Step 3: Create W3C Test Manifests

**Objective**: Create RDF manifest files listing all downloaded W3C tests

**Tasks**:

- [ ] Analyze W3C manifest format from source repository
- [ ] Create `test/fixtures/w3c/manifests/core-node-manifest.ttl`
  - List all core/node/ test files
  - Use mf:Manifest vocabulary
  - Include test names and file references
- [ ] Create `test/fixtures/w3c/manifests/core-property-manifest.ttl`
  - List all core/property/ test files
- [ ] Create `test/fixtures/w3c/manifests/core-manifest.ttl` (master)
  - Include all core tests via mf:include or consolidated entries list
- [ ] Create `test/fixtures/w3c/manifests/sparql-manifest.ttl`
  - List all sparql/ test files
- [ ] Test manifest parsing with W3CTestRunner.load_manifest/1
- [ ] Verify all test file paths resolve correctly

**Manifest Format Example**:

```turtle
@prefix mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#> .
@prefix sht: <http://www.w3.org/ns/shacl-test#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

<> a mf:Manifest ;
   rdfs:label "SHACL Core Node Constraint Tests" ;
   mf:entries (
     <#and-001>
     <#or-001>
     <#datatype-001>
   ) .

<#and-001> a sht:Validate ;
   mf:name "sh:and with two alternatives" ;
   mf:action [
     sht:shapesGraph <../core/node/and-001.ttl> ;
     sht:dataGraph <../core/node/and-001.ttl> ;  # Many W3C tests combine in one file
   ] ;
   mf:result <../core/node/and-001.ttl> ;
   mf:status sht:approved .
```

**Success Criteria**:
- All manifests parse successfully with W3CTestRunner
- All referenced test files exist and paths resolve
- Test count matches downloaded files

**Estimated Effort**: 3-4 hours (manifest creation, testing)

### Step 4: Implement ExUnit Test Generation

**Objective**: Create dynamic ExUnit tests from W3C test cases

**Tasks**:

- [ ] Create `test/elixir_ontologies/shacl/w3c_test.exs`
- [ ] Load test cases at compile time using `@test_cases W3CTestRunner.load_all_tests()`
- [ ] Group test cases by category (core_node, core_property, sparql)
- [ ] Create `describe` block for each category
- [ ] Generate tests using `for test_case <- @test_cases` pattern
- [ ] Implement `run_test_case/1` helper function:
  - Load data_graph with RDF.Turtle.read_file/1
  - Load shapes_graph with RDF.Turtle.read_file/1
  - Call SHACL.validate(data_graph, shapes_graph)
  - Assert report.conforms? matches expected_conforms
  - Provide detailed error message on failure
- [ ] Add test tags:
  - `@moduletag :w3c_test_suite` for all W3C tests
  - `@tag category: :core_node` per category
  - `@tag :skip` for rejected tests
- [ ] Implement `has_known_limitation?/1` to detect SPARQL limitations
  - Check test file content for "FILTER NOT EXISTS"
  - Check for nested SELECT patterns
- [ ] Tag SPARQL tests with limitations as `@tag skip: "reason"`
- [ ] Test with `mix test test/elixir_ontologies/shacl/w3c_test.exs`

**Success Criteria**:
- All test cases execute (no compilation errors)
- Tests run in parallel (async: true)
- Test output shows clear descriptions from mf:name
- Failed tests show helpful error messages
- Known limitations are skipped with documented reasons

**Estimated Effort**: 4-5 hours (test generation, error handling, debugging)

### Step 5: Run Tests and Document Results

**Objective**: Execute W3C test suite and analyze results

**Tasks**:

- [ ] Run core node tests: `mix test --only category:core_node`
  - Record pass count and total
  - Identify failing tests
- [ ] Run core property tests: `mix test --only category:core_property`
  - Record pass count and total
  - Identify failing tests
- [ ] Run SPARQL tests: `mix test --only category:sparql --include known_sparql_limitations`
  - Record pass count (expect lower rate)
  - Confirm known limitations are skipped
- [ ] For each failing test:
  - Analyze validation report vs expected result
  - Determine if bug in our implementation or edge case
  - Document in LIMITATIONS.md if unsupported feature
  - Create GitHub issue if bug to fix
- [ ] Calculate pass rates:
  - Core constraints pass rate (target >90%)
  - SPARQL constraints pass rate (target >50%)
  - Overall pass rate (target >85%)
- [ ] Create `test/fixtures/w3c/LIMITATIONS.md` documenting:
  - Each unsupported SHACL feature
  - Tests affected (count and names)
  - Root cause (SPARQL.ex limitation vs not implemented)
  - Potential workarounds
  - Future implementation path
- [ ] Update W3C README with actual test counts and pass rates

**Success Criteria**:
- **Core constraint pass rate >90%**
- SPARQL constraint pass rate >50%
- All limitations documented in LIMITATIONS.md
- Pass rates documented in README

**Estimated Effort**: 3-4 hours (test execution, failure analysis, documentation)

### Step 6: Integrate with CI and Final Documentation

**Objective**: Add W3C tests to CI pipeline and complete documentation

**Tasks**:

- [ ] Update CI configuration to run W3C core tests
  - Add step: `mix test --only w3c_test --exclude known_sparql_limitations`
  - Configure CI to fail if pass rate < 90%
- [ ] Add test execution commands to project documentation
  - Document how to run W3C tests
  - Document how to run with/without SPARQL tests
  - Document how to update test suite
- [ ] Update project README.md or docs/testing.md:
  - Mention W3C SHACL test suite compliance
  - Link to test/fixtures/w3c/README.md
  - Display pass rate badges or statistics
- [ ] Add mix aliases for convenience:
  - `mix test.w3c` - Run all W3C tests
  - `mix test.w3c.core` - Run only core tests
- [ ] Verify tests run in CI successfully
- [ ] Create summary report in planning document:
  - Total tests integrated
  - Pass rates by category
  - Known limitations count
  - Comparison to other SHACL implementations (if available)

**Success Criteria**:
- CI runs W3C core tests on every commit
- CI passes with >90% core test pass rate
- Documentation clearly explains W3C test compliance
- Future developers can easily run and update W3C tests

**Estimated Effort**: 2-3 hours (CI configuration, documentation)

## Notes/Considerations

### Edge Cases and Potential Issues

**Manifest Parsing Challenges:**
- W3C manifests may use different RDF serialization patterns than we expect
- Some tests may combine data/shapes in single file (need to handle)
- Blank node identifiers in manifests need careful handling
- RDF list parsing must be robust (reuse SHACL.Reader patterns)

**Test File Format Variations:**
- Some tests embed all graphs in one file (data, shapes, expected result)
- Some tests use separate files for each graph
- Need flexible parsing to handle both patterns
- File path resolution relative to manifest location

**Expected Result Comparison:**
- Partial compliance (sh:conforms only) is easier to verify
- Full compliance (graph isomorphism) requires:
  - Blank node normalization
  - Ignoring nested validation results (sh:detail)
  - Comparing specific predicates only
- Start with partial compliance, enhance to full compliance later

**SPARQL Limitation Detection:**
- Heuristic approach (check file content for patterns) is fragile
- May need manual curation of known-limitation list
- Could miss new SPARQL patterns in future W3C tests

### Future Improvements and Extensibility

**Phase 11.5.2 Potential Enhancements:**
- Full compliance mode (graph isomorphism checking)
- Automated W3C test suite updates (script to fetch latest)
- Performance benchmarking against other SHACL implementations
- Extended test coverage (advanced path expressions if implemented)

**Upstream Contributions:**
- Report any W3C test issues discovered (malformed manifests, incorrect expected results)
- Contribute SHACL.ex implementation to W3C implementation report

**Test Suite Evolution:**
- W3C may add new tests over time (SHACL 1.2, 2.0)
- Need versioning strategy (lock to commit hash, document update process)
- Consider automated alerts for new W3C test releases

### Related Issues and Technical Debt

**From Phase 11.3 (SPARQL Evaluator):**
- Known SPARQL.ex limitations with FILTER NOT EXISTS
- Nested subquery support incomplete
- May need to contribute fixes to SPARQL.ex or fork

**From Phase 11.4 (Public API):**
- ValidationReport struct is stable public API
- W3C tests validate this API works correctly
- Any breaking changes to API would require W3C test updates

**Integration with Existing Tests:**
- W3C tests complement (not replace) elixir-shapes.ttl tests
- elixir-shapes.ttl tests validate domain-specific ontology constraints
- W3C tests validate general SHACL compliance

### Risk Assessment and Mitigation

**Risk: Lower than expected pass rate (<90%)**
- **Mitigation**: Start with conservative test selection (known constraints only)
- **Mitigation**: Exclude edge cases initially, add incrementally
- **Fallback**: Document as known limitations, plan Phase 11.5.2 for fixes

**Risk: Manifest parsing complexity**
- **Mitigation**: Study W3C manifest format thoroughly before implementation
- **Mitigation**: Reuse RDF.ex and existing SHACL.Reader patterns
- **Fallback**: Create simplified custom manifest format if W3C format too complex

**Risk: Test maintenance burden**
- **Mitigation**: Lock to specific W3C commit hash, update intentionally
- **Mitigation**: Automate as much as possible (dynamic test generation)
- **Fallback**: Reduce test count if maintenance becomes excessive

**Risk: False failures due to implementation differences**
- **Mitigation**: Use partial compliance (sh:conforms only) initially
- **Mitigation**: Study other implementations' test results for comparison
- **Fallback**: Document acceptable deviations from spec if justified

### Performance Considerations

**Test Execution Time:**
- 121 tests with parallel execution should complete in <10 seconds
- RDF parsing is fast (RDF.ex is efficient)
- SHACL validation is parallel (Phase 11.2)
- SPARQL tests may be slower (complex queries)

**CI Impact:**
- Adding W3C tests to CI adds <10 seconds per build
- Minimal impact on developer workflow
- Consider running SPARQL tests only in nightly builds if too slow

**Memory Usage:**
- 121 small RDF graphs should fit easily in memory
- No persistent state between tests (async: true)
- Test isolation prevents memory leaks

### Success Metrics and Reporting

**Track Over Time:**
```
W3C SHACL Test Suite Compliance Report
======================================

Core Constraint Tests:
  Node Shapes: 32/35 (91%) ✓
  Property Shapes: 38/40 (95%) ✓
  Qualified: 12/15 (80%) ⚠
  Total Core: 82/90 (91%) ✓

SPARQL Constraint Tests:
  Simple SPARQL: 8/10 (80%) ✓
  Complex SPARQL: 2/8 (25%) ✗ (known limitations)
  Total SPARQL: 10/18 (56%) ⚠

Overall: 92/108 (85%) ✓

Known Limitations: 13 tests (documented in LIMITATIONS.md)
  - SPARQL FILTER NOT EXISTS: 5 tests
  - Nested subqueries: 3 tests
  - Advanced paths (not implemented): 5 tests

Comparison to Other Implementations:
  - TopQuadrant SHACL (Java): 100% (121/121)
  - pySHACL (Python): 95% (115/121)
  - ElixirOntologies (Elixir): 85% (92/108) + 13 intentionally excluded

Next Steps:
  - Fix qualified constraint edge case (3 failing tests)
  - Investigate SPARQL.ex updates for FILTER NOT EXISTS
  - Consider implementing advanced path expressions (Phase 12?)
```

This comprehensive planning document provides a complete roadmap for integrating the W3C SHACL test suite into our native Elixir implementation, with realistic success criteria, detailed implementation steps, and thorough consideration of edge cases and future extensibility.
