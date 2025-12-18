# Feature: Phase 11.1 SHACL Infrastructure Review Fixes

## Overview

This feature addresses all issues identified in the comprehensive Section 11.1 SHACL Infrastructure code review. The review evaluated seven dimensions (Factual Accuracy, QA/Test Coverage, Senior Engineering, Security, Consistency, Redundancy, Elixir Code Quality) and found the implementation to be production-ready with an overall grade of **B+ (87/100)**.

**Review Document:** `notes/reviews/section-11-1-shacl-infrastructure-review.md`

**Overall Status:** Section 11.1 is production-ready after addressing 2 blockers. All other findings enhance quality but don't block deployment.

**Total Issues:** 14 identified
- 2 BLOCKERS (Critical)
- 4 HIGH PRIORITY
- 8 MEDIUM/LOW PRIORITY

---

## Source Review Summary

### Test Coverage
- **Total Tests:** 112/67 target (167%)
- **Model Tests:** 58/15 (387%)
- **Reader Tests:** 32/20 (160%)
- **Writer Tests:** 22/10 (220%)

### Code Quality Scores
- **Idiomatic Elixir:** 94/100
- **Consistency:** 99.4%
- **Security Rating:** B+ (Good)
- **Architecture Grade:** B+ (88/100)

### Technical Debt Identified
- **Lines of Duplication:** ~120 lines
- **Security Vulnerabilities:** 1 high, 2 medium
- **Architectural Issues:** 1 critical (dual model hierarchy)
- **Missing Features:** 1 blocker (sh:maxInclusive)

---

## Issues by Priority

### 🚨 BLOCKERS (Must Fix Before Section 11.2)

#### B1. Missing sh:maxInclusive Support
**Severity:** CRITICAL BLOCKER
**Effort:** 4-6 hours
**Review Section:** QA and Test Coverage Review
**Files Affected:**
- `lib/elixir_ontologies/shacl/model/property_shape.ex`
- `lib/elixir_ontologies/shacl/reader.ex`
- `test/elixir_ontologies/shacl/reader_test.exs`
- `priv/ontologies/elixir-shapes.ttl` (uses the constraint at line 241-243)

**Problem:**
The production SHACL shapes file (`elixir-shapes.ttl`) actively uses the `sh:maxInclusive` constraint in `FunctionArityMatchShape` (line 241-243), but this constraint is:
- Not defined in the PropertyShape struct
- Not parsed by Reader
- Not tested in reader_test.exs
- Not documented in planning documents

**Impact:**
Production shapes use a feature that doesn't exist. This is a blocker for Section 11.2 validators which will attempt to enforce constraints that can't be read.

**Solution:**

1. Add field to PropertyShape struct:
```elixir
# In property_shape.ex
defstruct [
  # ... existing fields ...
  :min_inclusive,
  :max_inclusive,
  # ... existing fields ...
]

@type t :: %__MODULE__{
  # ... existing types ...
  min_inclusive: integer() | nil,
  max_inclusive: integer() | nil,
  # ... existing types ...
}
```

2. Add constants and parsing to Reader:
```elixir
# In reader.ex (around line 70)
@sh_min_inclusive RDF.iri("http://www.w3.org/ns/shacl#minInclusive")
@sh_max_inclusive RDF.iri("http://www.w3.org/ns/shacl#maxInclusive")

# In extract_property_constraints/1 (around line 352)
min_inclusive: extract_optional_integer(desc, @sh_min_inclusive),
max_inclusive: extract_optional_integer(desc, @sh_max_inclusive),
```

3. Add tests to reader_test.exs:
```elixir
describe "numeric range constraints" do
  test "parses sh:minInclusive constraint" do
    # Test parsing of minInclusive
  end

  test "parses sh:maxInclusive constraint" do
    # Test parsing of maxInclusive from elixir-shapes.ttl
  end

  test "parses both min and max inclusive constraints" do
    # Test combined constraints
  end
end
```

**Success Criteria:**
- [ ] PropertyShape struct includes min_inclusive and max_inclusive fields
- [ ] Reader parses both constraints from RDF graphs
- [ ] FunctionArityMatchShape from elixir-shapes.ttl parses successfully with maxInclusive: 255
- [ ] 3-5 new tests cover minInclusive/maxInclusive parsing
- [ ] All existing tests continue to pass

**Implementation Steps:**
1. Add fields to PropertyShape struct definition
2. Add SHACL constants to Reader
3. Add extraction in extract_property_constraints/1
4. Write 3-5 tests for numeric range constraints
5. Verify elixir-shapes.ttl parses correctly
6. Update planning document with new constraint support

---

#### B2. Dual Model Hierarchy Confusion
**Severity:** CRITICAL ARCHITECTURAL BLOCKER
**Effort:** 8-12 hours
**Review Section:** Senior Engineering Review
**Files Affected:**
- `lib/elixir_ontologies/shacl/model/validation_report.ex`
- `lib/elixir_ontologies/validator/report.ex`
- `lib/elixir_ontologies/validator.ex`
- `lib/elixir_ontologies/shacl/writer.ex`
- `test/elixir_ontologies/validator_test.exs`
- All validator integration tests

**Problem:**
Two incompatible validation report models exist:

**SHACL.Model.ValidationReport** (Phase 11.1.1):
```elixir
defstruct [:conforms?, :results]

@type t :: %__MODULE__{
  conforms?: boolean(),
  results: [ValidationResult.t()]
}
```

**Validator.Report** (Phase 10.1.1):
```elixir
defstruct [:conforms, :violations, :warnings]

@type t :: %__MODULE__{
  conforms: boolean(),
  violations: [Violation.t()],
  warnings: [Violation.t()]
}
```

**Current State:**
```elixir
# Validator.validate/2 returns:
{:ok, %Validator.Report{conforms: false, violations: [...]}}

# But Writer.to_graph/1 expects:
{:ok, %SHACL.Model.ValidationReport{conforms?: false, results: [...]}}

# These are INCOMPATIBLE - field names differ, structure differs
```

**Impact:**
- Writer cannot serialize reports from Validator.validate/2
- Different field names: `conforms?` vs `conforms`
- Different result structures: unified `results` list vs separated `violations`/`warnings`
- Breaking API change required for integration

**Solution Options:**

**Option 1 (RECOMMENDED): Migrate to SHACL.Model.ValidationReport**
- Deprecate `Validator.Report` module
- Update `Validator.validate/2` to return `SHACL.Model.ValidationReport.t()`
- Convert `Violation.t()` to `ValidationResult.t()`
- Map severity: violations → sh:Violation, warnings → sh:Warning
- Update all tests to use new structure

**Pros:**
- Proper SHACL compliance
- Writer integration works immediately
- Single source of truth
- Standard W3C SHACL vocabulary

**Cons:**
- Breaking API change
- All existing tests need updates
- Validator.Report module becomes deprecated

**Option 2: Keep Both + Add Adapter**
- Create `ValidationReport.from_report/1` adapter function
- Writer accepts both types via pattern matching
- Document when to use each type

**Pros:**
- Backward compatible
- No test changes required
- Gradual migration path

**Cons:**
- Permanent duplication
- Confusion about which to use
- Technical debt accumulates

**Option 3: Merge into Unified Model**
- Create new unified model in `ElixirOntologies.Validator.ValidationReport`
- Support both field naming conventions
- Complex migration path

**Pros:**
- Single source of truth eventually
- Could support both APIs temporarily

**Cons:**
- Most complex migration
- Longer implementation time
- Risk of introducing bugs

**Recommended Approach: Option 1**

**Implementation Steps:**

1. Add conversion helper to SHACL.Model.ValidationResult:
```elixir
def from_violation(%Validator.Violation{} = v) do
  %__MODULE__{
    focus_node: v.focus_node,
    result_path: v.property_path,
    value: v.value,
    source_constraint_component: v.constraint,
    result_severity: severity_from_type(v),
    result_message: v.message
  }
end

defp severity_from_type(%{type: :violation}), do: @sh_violation
defp severity_from_type(%{type: :warning}), do: @sh_warning
```

2. Update Validator.validate/2:
```elixir
def validate(data_graph, shapes_graph) do
  # ... existing validation logic ...

  # Convert to SHACL.Model.ValidationReport
  results = Enum.map(violations ++ warnings, &ValidationResult.from_violation/1)

  {:ok, %SHACL.Model.ValidationReport{
    conforms?: Enum.empty?(violations),
    results: results
  }}
end
```

3. Deprecate Validator.Report:
```elixir
@deprecated "Use ElixirOntologies.SHACL.Model.ValidationReport instead"
defmodule ElixirOntologies.Validator.Report do
  # Keep for backward compatibility but mark deprecated
end
```

4. Update all tests to use new structure

5. Update documentation and examples

**Success Criteria:**
- [ ] Validator.validate/2 returns SHACL.Model.ValidationReport.t()
- [ ] Writer.to_graph/1 works directly with validator output
- [ ] All violations/warnings properly converted to ValidationResults
- [ ] Severity levels correctly mapped (violation → sh:Violation, warning → sh:Warning)
- [ ] All existing tests updated and passing
- [ ] Deprecation warnings in place for old Report module
- [ ] Documentation updated with migration guide

---

### ⚠️ HIGH PRIORITY (Fix During Section 11.2)

#### H1. ReDoS Vulnerability in Regex Compilation
**Severity:** HIGH SECURITY
**Effort:** 2-3 hours
**Review Section:** Security Review
**Files Affected:**
- `lib/elixir_ontologies/shacl/reader.ex` (lines 404-413)
- `test/elixir_ontologies/shacl/reader_test.exs`

**Problem:**
User-controlled regex patterns from SHACL shapes are compiled without validation or timeouts. Malicious patterns can cause catastrophic backtracking (ReDoS attack).

**Attack Vector:**
```turtle
:MaliciousShape
  sh:pattern "^(a+)+b$" ;  # Exponential backtracking
```

**Vulnerable Code:**
```elixir
defp extract_optional_pattern(desc, predicate) do
  case extract_optional_string(desc, predicate) do
    {:ok, nil} -> {:ok, nil}
    {:ok, pattern_string} ->
      case Regex.compile(pattern_string) do  # No timeout!
        {:ok, regex} -> {:ok, regex}
        {:error, _reason} -> {:ok, nil}
      end
    {:error, _} -> {:ok, nil}
  end
end
```

**Proof of Concept:**
```elixir
# This hangs for seconds/minutes
pattern = "^(a+)+b$"
regex = Regex.compile!(pattern)
Regex.match?(regex, "aaaaaaaaaaaaaaaaaaaaac")  # CPU exhaustion
```

**Impact:**
- CPU exhaustion on malicious SHACL shapes
- DoS attack vector if shapes loaded from untrusted sources
- Affects Reader.parse_shapes/2

**Solution:**
Add length limits and compilation timeouts:

```elixir
@max_regex_length 500
@regex_compile_timeout 100  # milliseconds

defp extract_optional_pattern(desc, predicate) do
  case extract_optional_string(desc, predicate) do
    {:ok, nil} ->
      {:ok, nil}

    {:ok, pattern_string} when byte_size(pattern_string) > @max_regex_length ->
      Logger.warning("Skipping excessively long regex pattern (#{byte_size(pattern_string)} bytes)")
      {:ok, nil}

    {:ok, pattern_string} ->
      task = Task.async(fn -> Regex.compile(pattern_string) end)

      case Task.yield(task, @regex_compile_timeout) || Task.shutdown(task) do
        {:ok, {:ok, regex}} ->
          {:ok, regex}
        {:ok, {:error, reason}} ->
          Logger.warning("Regex compilation failed: #{inspect(reason)}")
          {:ok, nil}
        nil ->
          Logger.warning("Regex compilation timed out: #{pattern_string}")
          {:ok, nil}
      end

    {:error, _} ->
      {:ok, nil}
  end
end
```

**Test Requirements:**
```elixir
describe "regex security" do
  test "rejects excessively long regex patterns" do
    long_pattern = String.duplicate("a", 501)
    # Assert pattern is skipped with warning
  end

  test "times out on catastrophic backtracking patterns" do
    malicious_pattern = "^(a+)+b$"
    # Assert compilation times out gracefully
  end

  test "handles valid complex patterns" do
    valid_pattern = "^[a-zA-Z][a-zA-Z0-9_]*$"
    # Assert pattern compiles successfully
  end
end
```

**Success Criteria:**
- [ ] Maximum regex length enforced (500 bytes)
- [ ] Compilation timeout enforced (100ms)
- [ ] Timeouts handled gracefully with logging
- [ ] 3+ security tests added
- [ ] Existing valid patterns still compile successfully
- [ ] No performance regression on normal patterns

---

#### H2. SHACL Vocabulary Duplication
**Severity:** HIGH REDUNDANCY
**Effort:** 4-6 hours
**Review Section:** Redundancy Review
**Files Affected:**
- `lib/elixir_ontologies/shacl/reader.ex` (lines 52-79) - 15+ constants
- `lib/elixir_ontologies/shacl/writer.ex` (lines 94-111) - 12+ constants
- `lib/elixir_ontologies/validator/report_parser.ex` (lines 41-54) - 10+ constants
- `test/elixir_ontologies/shacl/writer_test.exs` (lines 10-22) - 13+ constants

**Problem:**
35+ SHACL vocabulary constants are duplicated across 4 files, creating maintenance burden and inconsistency risk.

**Duplicated Constants:**
```elixir
# Repeated across 3-4 files each:
@sh_conforms RDF.iri("http://www.w3.org/ns/shacl#conforms")
@sh_result RDF.iri("http://www.w3.org/ns/shacl#result")
@sh_focus_node RDF.iri("http://www.w3.org/ns/shacl#focusNode")
@sh_validation_report RDF.iri("http://www.w3.org/ns/shacl#ValidationReport")
# ... 31 more ...
```

**Impact:**
- ~100 lines of duplicate code
- Risk of inconsistency if constants need updating
- Violates DRY principle
- Makes maintenance harder

**Solution:**
Create centralized SHACL vocabulary module:

**File:** `lib/elixir_ontologies/shacl/vocabulary.ex`

```elixir
defmodule ElixirOntologies.SHACL.Vocabulary do
  @moduledoc """
  SHACL vocabulary constants following W3C SHACL Recommendation.

  Centralized SHACL IRI definitions for use across reader, writer,
  validator, and test modules. Eliminates duplication and ensures
  consistency with W3C SHACL specification.

  ## References
  - [W3C SHACL Specification](https://www.w3.org/TR/shacl/)
  """

  alias RDF.XSD

  # Namespace
  @shacl_ns "http://www.w3.org/ns/shacl#"
  @rdf_ns "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

  # Core Classes
  def node_shape, do: RDF.iri(@shacl_ns <> "NodeShape")
  def property_shape, do: RDF.iri(@shacl_ns <> "PropertyShape")
  def validation_report, do: RDF.iri(@shacl_ns <> "ValidationReport")
  def validation_result, do: RDF.iri(@shacl_ns <> "ValidationResult")

  # Targeting Properties
  def target_class, do: RDF.iri(@shacl_ns <> "targetClass")
  def target_node, do: RDF.iri(@shacl_ns <> "targetNode")
  def target_subjects_of, do: RDF.iri(@shacl_ns <> "targetSubjectsOf")
  def target_objects_of, do: RDF.iri(@shacl_ns <> "targetObjectsOf")

  # Property Constraint Properties
  def property, do: RDF.iri(@shacl_ns <> "property")
  def path, do: RDF.iri(@shacl_ns <> "path")
  def min_count, do: RDF.iri(@shacl_ns <> "minCount")
  def max_count, do: RDF.iri(@shacl_ns <> "maxCount")
  def min_inclusive, do: RDF.iri(@shacl_ns <> "minInclusive")
  def max_inclusive, do: RDF.iri(@shacl_ns <> "maxInclusive")
  def min_exclusive, do: RDF.iri(@shacl_ns <> "minExclusive")
  def max_exclusive, do: RDF.iri(@shacl_ns <> "maxExclusive")
  def min_length, do: RDF.iri(@shacl_ns <> "minLength")
  def max_length, do: RDF.iri(@shacl_ns <> "maxLength")
  def pattern, do: RDF.iri(@shacl_ns <> "pattern")
  def datatype, do: RDF.iri(@shacl_ns <> "datatype")
  def class_constraint, do: RDF.iri(@shacl_ns <> "class")
  def node_kind, do: RDF.iri(@shacl_ns <> "nodeKind")
  def in_constraint, do: RDF.iri(@shacl_ns <> "in")

  # Logical Constraints
  def and_constraint, do: RDF.iri(@shacl_ns <> "and")
  def or_constraint, do: RDF.iri(@shacl_ns <> "or")
  def not_constraint, do: RDF.iri(@shacl_ns <> "not")
  def xone, do: RDF.iri(@shacl_ns <> "xone")

  # Qualified Shapes
  def qualified_value_shape, do: RDF.iri(@shacl_ns <> "qualifiedValueShape")
  def qualified_min_count, do: RDF.iri(@shacl_ns <> "qualifiedMinCount")
  def qualified_max_count, do: RDF.iri(@shacl_ns <> "qualifiedMaxCount")

  # SPARQL Constraints
  def sparql, do: RDF.iri(@shacl_ns <> "sparql")
  def select, do: RDF.iri(@shacl_ns <> "select")

  # Validation Report Properties
  def conforms, do: RDF.iri(@shacl_ns <> "conforms")
  def result, do: RDF.iri(@shacl_ns <> "result")
  def focus_node, do: RDF.iri(@shacl_ns <> "focusNode")
  def result_path, do: RDF.iri(@shacl_ns <> "resultPath")
  def result_severity, do: RDF.iri(@shacl_ns <> "resultSeverity")
  def result_message, do: RDF.iri(@shacl_ns <> "resultMessage")
  def source_constraint_component, do: RDF.iri(@shacl_ns <> "sourceConstraintComponent")
  def value, do: RDF.iri(@shacl_ns <> "value")

  # Severity Levels
  def violation, do: RDF.iri(@shacl_ns <> "Violation")
  def warning, do: RDF.iri(@shacl_ns <> "Warning")
  def info, do: RDF.iri(@shacl_ns <> "Info")

  # Node Kinds
  def iri, do: RDF.iri(@shacl_ns <> "IRI")
  def blank_node, do: RDF.iri(@shacl_ns <> "BlankNode")
  def literal, do: RDF.iri(@shacl_ns <> "Literal")

  # RDF Vocabulary
  def rdf_type, do: RDF.iri(@rdf_ns <> "type")
  def rdf_first, do: RDF.iri(@rdf_ns <> "first")
  def rdf_rest, do: RDF.iri(@rdf_ns <> "rest")
  def rdf_nil, do: RDF.iri(@rdf_ns <> "nil")

  # Prefix Map
  def prefix_map do
    %{
      sh: @shacl_ns,
      rdf: @rdf_ns,
      xsd: XSD.ns()
    }
  end
end
```

**Usage Pattern:**
```elixir
# In Reader.ex, Writer.ex, ReportParser.ex
alias ElixirOntologies.SHACL.Vocabulary, as: SHACL

def parse_shapes(graph) do
  shapes = graph
    |> RDF.Graph.triples()
    |> Enum.filter(fn {_s, p, o} ->
      p == SHACL.rdf_type() && o == SHACL.node_shape()
    end)
end
```

**Implementation Steps:**
1. Create `lib/elixir_ontologies/shacl/vocabulary.ex` with all constants
2. Add comprehensive @moduledoc with W3C SHACL reference
3. Update Reader.ex to use `alias SHACL.Vocabulary, as: SHACL`
4. Replace all @sh_* constants with SHACL.* function calls
5. Update Writer.ex similarly
6. Update ReportParser.ex similarly
7. Update WriterTest.exs similarly
8. Run full test suite to ensure no breakage
9. Remove duplicate constant definitions
10. Update documentation

**Success Criteria:**
- [ ] Vocabulary module created with all 35+ SHACL terms
- [ ] Reader uses Vocabulary (no more @sh_* module attributes)
- [ ] Writer uses Vocabulary
- [ ] ReportParser uses Vocabulary
- [ ] WriterTest uses Vocabulary
- [ ] All tests passing (112 tests)
- [ ] ~100 lines of duplication eliminated
- [ ] Single source of truth for SHACL vocabulary
- [ ] Documentation includes W3C SHACL reference

---

#### H3. RDF List Depth Limit Missing
**Severity:** HIGH SECURITY
**Effort:** 2 hours
**Review Section:** Security Review
**Files Affected:**
- `lib/elixir_ontologies/shacl/reader.ex` (lines 441-472)
- `test/elixir_ontologies/shacl/reader_test.exs`

**Problem:**
Unbounded recursion in RDF list parsing allows:
- Stack overflow on deeply nested lists (10,000+ nodes)
- Infinite loops on circular lists
- Resource exhaustion attack vector

**Vulnerable Code:**
```elixir
defp parse_rdf_list(_graph, @rdf_nil), do: {:ok, []}

defp parse_rdf_list(graph, list_node) do
  # No depth limit - vulnerable to stack overflow
  with [first | _] <- first_values,
       [rest | _] <- rest_values,
       {:ok, rest_list} <- parse_rdf_list(graph, rest) do  # Recursive without limit
    {:ok, [first | rest_list]}
  end
end
```

**Attack Vector:**
```turtle
:Shape1 sh:in _:list1 .
_:list1 rdf:first "a" ; rdf:rest _:list2 .
_:list2 rdf:first "b" ; rdf:rest _:list3 .
# ... 10,000 more nested nodes causing stack overflow
```

**Solution:**
Add depth tracking with configurable limit:

```elixir
@max_rdf_list_depth 1000

defp parse_rdf_list(graph, list_node, depth \\ 0)

defp parse_rdf_list(_graph, @rdf_nil, _depth), do: {:ok, []}

defp parse_rdf_list(_graph, _list_node, depth) when depth > @max_rdf_list_depth do
  {:error, "RDF list exceeds maximum depth of #{@max_rdf_list_depth}"}
end

defp parse_rdf_list(graph, list_node, depth) do
  first_values =
    graph
    |> RDF.Graph.get(list_node, @rdf_first)
    |> normalize_to_list()

  rest_values =
    graph
    |> RDF.Graph.get(list_node, @rdf_rest)
    |> normalize_to_list()

  with [first | _] <- first_values,
       [rest | _] <- rest_values,
       {:ok, rest_list} <- parse_rdf_list(graph, rest, depth + 1) do
    {:ok, [first | rest_list]}
  else
    _ -> {:error, "Malformed RDF list at #{inspect(list_node)}"}
  end
end
```

**Test Requirements:**
```elixir
describe "RDF list parsing security" do
  test "rejects deeply nested lists exceeding max depth" do
    # Build list with 1001 nodes
    # Assert {:error, "RDF list exceeds maximum depth"}
  end

  test "parses lists up to max depth successfully" do
    # Build list with exactly 1000 nodes
    # Assert {:ok, list} with correct values
  end

  test "handles circular list references gracefully" do
    # Build circular list: _:a -> _:b -> _:a
    # Assert error returned (either depth or malformed)
  end
end
```

**Success Criteria:**
- [ ] Maximum depth enforced (1000 nodes)
- [ ] Depth parameter added to parse_rdf_list/3
- [ ] Clear error messages for depth exceeded
- [ ] 3+ security tests for deep/circular lists
- [ ] Existing valid lists still parse correctly
- [ ] No performance impact on normal lists (<100 nodes)

---

#### H4. Enhanced Error Handling in Reader
**Severity:** MEDIUM-HIGH QUALITY
**Effort:** 3-4 hours
**Review Section:** QA and Test Coverage Review
**Files Affected:**
- `lib/elixir_ontologies/shacl/reader.ex`
- `test/elixir_ontologies/shacl/reader_test.exs`

**Problem:**
Current test coverage only includes 3 tests for malformed input. Missing error handling tests for:
- Invalid regex patterns (compilation failures)
- Blank node handling as shape IDs
- Empty graphs
- Graphs with zero shapes
- Nested qualified shape constraints

**Impact:**
- Unknown behavior on edge cases
- Potential crashes on malformed SHACL shapes
- Poor error messages for debugging

**Solution:**
Enhance error handling and add comprehensive tests:

**Test Requirements:**
```elixir
describe "error handling" do
  test "handles empty RDF graphs" do
    graph = RDF.Graph.new()
    assert {:ok, []} = Reader.parse_shapes(graph)
  end

  test "handles graphs with no shapes" do
    graph = RDF.Graph.new()
    |> RDF.Graph.add({RDF.iri("ex:Thing"), RDF.type(), RDF.iri("ex:Class")})
    assert {:ok, []} = Reader.parse_shapes(graph)
  end

  test "handles blank node shape IDs" do
    # Test shapes identified by blank nodes
  end

  test "returns error for invalid regex patterns" do
    # Test shape with invalid regex: "[abc"
    # Assert graceful handling
  end

  test "handles deeply nested qualified shapes" do
    # Test sh:qualifiedValueShape within sh:qualifiedValueShape
  end

  test "handles missing required properties gracefully" do
    # Test shape missing sh:path
    # Assert clear error message
  end
end
```

**Implementation Steps:**
1. Review current error handling in Reader
2. Add tests for empty/zero-shape graphs
3. Add tests for blank node shape IDs
4. Add tests for invalid regex patterns
5. Add tests for nested qualified shapes
6. Improve error messages where needed
7. Document error behavior in @moduledoc

**Success Criteria:**
- [ ] 10+ new error handling tests added
- [ ] Empty graphs handled gracefully
- [ ] Blank node shapes supported
- [ ] Invalid regex patterns logged and skipped
- [ ] Clear error messages for all failure cases
- [ ] All tests passing
- [ ] Documentation updated with error scenarios

---

### 💡 MEDIUM PRIORITY (Nice to Have)

#### M1. Extract normalize_to_list Helper
**Severity:** MEDIUM CODE QUALITY
**Effort:** 1 hour
**Review Section:** Redundancy Review
**Files Affected:**
- `lib/elixir_ontologies/shacl/reader.ex` (9+ occurrences, ~40 lines)

**Problem:**
Pattern repeated 9+ times in Reader.ex (~40 duplicate lines):

```elixir
# Repeated in extract_required_iri, extract_optional_iri, etc.
values =
  desc
  |> RDF.Description.get(predicate)
  |> case do
    nil -> []
    list when is_list(list) -> list
    single -> [single]
  end
```

**Solution:**
Extract to helper function:

```elixir
# Add to Reader.ex private helpers section
@doc false
defp normalize_to_list(nil), do: []
defp normalize_to_list(list) when is_list(list), do: list
defp normalize_to_list(single), do: [single]

# Then use:
values = desc |> RDF.Description.get(predicate) |> normalize_to_list()
```

**Implementation Steps:**
1. Add normalize_to_list/1 helper to Reader.ex
2. Replace all 9+ occurrences with helper call
3. Run tests to ensure no behavior change
4. Verify ~40 lines reduced

**Success Criteria:**
- [ ] normalize_to_list/1 helper added
- [ ] All 9+ occurrences replaced
- [ ] ~40 lines of duplication eliminated
- [ ] All tests still passing
- [ ] No behavior changes

---

#### M2. Create RDFTestHelpers Module
**Severity:** MEDIUM CODE QUALITY
**Effort:** 2 hours
**Review Section:** Redundancy Review
**Files Affected:**
- `test/support/rdf_test_helpers.ex` (new file)
- `test/elixir_ontologies/shacl/writer_test.exs`
- `lib/elixir_ontologies/validator/report_parser.ex`

**Problem:**
`get_objects/2` helper duplicated in writer_test.exs and report_parser.ex with different signatures.

**Solution:**
Create shared test helper module:

**File:** `test/support/rdf_test_helpers.ex`

```elixir
defmodule ElixirOntologies.RDFTestHelpers do
  @moduledoc """
  Shared RDF testing utilities.

  Provides common helpers for working with RDF graphs in tests.
  """

  @doc """
  Gets all objects for a given predicate in a graph.

  Unwraps literals to their values for easier assertions.
  """
  def get_objects(graph, predicate) do
    graph
    |> RDF.Graph.triples()
    |> Enum.filter(fn {_s, p, _o} -> p == predicate end)
    |> Enum.map(fn {_s, _p, o} -> unwrap_literal(o) end)
  end

  @doc """
  Gets all subjects for a given predicate and object.
  """
  def get_subjects(graph, predicate, object) do
    graph
    |> RDF.Graph.triples()
    |> Enum.filter(fn {_s, p, o} -> p == predicate && o == object end)
    |> Enum.map(fn {s, _p, _o} -> s end)
  end

  defp unwrap_literal(%RDF.Literal{} = lit), do: RDF.Literal.value(lit)
  defp unwrap_literal(%RDF.XSD.Boolean{} = lit), do: RDF.Literal.value(lit)
  defp unwrap_literal(%RDF.XSD.Integer{} = lit), do: RDF.Literal.value(lit)
  defp unwrap_literal(%RDF.XSD.String{} = lit), do: RDF.Literal.value(lit)
  defp unwrap_literal(term), do: term
end
```

**Implementation Steps:**
1. Create test/support/rdf_test_helpers.ex
2. Move get_objects/2 from writer_test.exs
3. Update writer_test.exs to import RDFTestHelpers
4. Update report_parser.ex if needed
5. Add additional helpers (get_subjects, etc.)

**Success Criteria:**
- [ ] RDFTestHelpers module created
- [ ] get_objects/2 helper centralized
- [ ] writer_test.exs uses RDFTestHelpers
- [ ] Duplication eliminated
- [ ] All tests passing

---

#### M3. Fix Temp File Race Condition
**Severity:** MEDIUM SECURITY
**Effort:** 1 hour
**Review Section:** Security Review
**Files Affected:**
- `lib/elixir_ontologies/validator/shacl_engine.ex` (lines 115-153)
- `test/elixir_ontologies/validator/shacl_engine_test.exs`

**Problem:**
Race condition in temp file creation - multiple processes could generate same timestamp.

**Vulnerable Code:**
```elixir
defp write_temp_file(content, suffix) do
  timestamp = System.system_time(:millisecond)
  filename = System.tmp_dir!() <> "/shacl_#{timestamp}_#{suffix}"
  # ^ Collision possible with concurrent calls

  case File.write(filename, content) do
    :ok -> {:ok, filename}
    {:error, reason} -> {:error, {:file_write_error, reason}}
  end
end
```

**Solution:**
Use cryptographically random filenames with atomic file creation:

```elixir
defp write_temp_file(content, suffix) do
  # Use :crypto.strong_rand_bytes for uniqueness
  random = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  filename = Path.join(System.tmp_dir!(), "shacl_#{random}_#{suffix}")

  case File.write(filename, content, [:exclusive]) do
    :ok ->
      {:ok, filename}
    {:error, :eexist} ->
      # Retry on collision (extremely unlikely)
      write_temp_file(content, suffix)
    {:error, reason} ->
      {:error, {:file_write_error, reason}}
  end
end
```

**Implementation Steps:**
1. Update write_temp_file/2 to use :crypto.strong_rand_bytes
2. Add [:exclusive] flag to File.write
3. Add retry logic for :eexist (collision)
4. Add test for concurrent temp file creation
5. Verify no regressions in existing tests

**Success Criteria:**
- [ ] Temp files use cryptographic random names
- [ ] File.write uses [:exclusive] flag
- [ ] Collision retry logic in place
- [ ] Test for concurrent file creation
- [ ] No race conditions
- [ ] All tests passing

---

#### M4. Module Naming Consistency
**Severity:** LOW CONSISTENCY
**Effort:** 1 hour
**Review Section:** Consistency Review
**Files Affected:**
- `lib/elixir_ontologies/validator/shacl_engine.ex` → rename to `shacl_engine.ex`
- All imports/aliases referencing ShaclEngine
- Tests

**Problem:**
Module name inconsistency:
- ✅ `ElixirOntologies.SHACL.Reader`
- ✅ `ElixirOntologies.SHACL.Writer`
- ❌ `ElixirOntologies.Validator.ShaclEngine` (should be SHACLEngine)

**Solution:**
Rename module to maintain acronym capitalization:

```elixir
# Before
defmodule ElixirOntologies.Validator.ShaclEngine do

# After
defmodule ElixirOntologies.Validator.SHACLEngine do
```

**Implementation Steps:**
1. Rename file: `shacl_engine.ex` → `shacl_engine.ex` (filename stays same)
2. Update module name: `ShaclEngine` → `SHACLEngine`
3. Update all aliases in Validator module
4. Update test module name
5. Update documentation references
6. Run full test suite

**Success Criteria:**
- [ ] Module renamed to SHACLEngine
- [ ] All imports/aliases updated
- [ ] Test module renamed
- [ ] Consistency with SHACL.* modules
- [ ] All tests passing
- [ ] No breaking changes in public API

---

#### M5. Improve Pattern Matching in has_violations?
**Severity:** LOW CODE QUALITY
**Effort:** 15 minutes
**Review Section:** Elixir Code Quality Review
**Files Affected:**
- `lib/elixir_ontologies/validator/report.ex` (lines 94-96)

**Problem:**
Using length/1 check where pattern matching is more idiomatic:

```elixir
# Current
def has_violations?(%__MODULE__{violations: violations}) do
  length(violations) > 0
end
```

**Solution:**
Use pattern matching for O(1) check:

```elixir
# Better - O(1) and idiomatic
def has_violations?(%__MODULE__{violations: []}), do: false
def has_violations?(%__MODULE__{violations: [_ | _]}), do: true
```

**Implementation Steps:**
1. Replace implementation with pattern matching
2. Run tests to verify behavior unchanged
3. Check for similar patterns elsewhere

**Success Criteria:**
- [ ] Pattern matching implementation
- [ ] All tests passing
- [ ] No behavior changes

---

#### M6. Optimize String.split in ShaclEngine
**Severity:** LOW CODE QUALITY
**Effort:** 10 minutes
**Review Section:** Elixir Code Quality Review
**Files Affected:**
- `lib/elixir_ontologies/validator/shacl_engine.ex` (lines 185-193)

**Problem:**
Not using `trim: true` option with String.split:

```elixir
# Current
output
|> String.split("\n")
|> Enum.find(&(String.trim(&1) != ""), fn -> "Unknown validation error" end)
```

**Solution:**
Use trim option and simplify:

```elixir
# Better
output
|> String.split("\n", trim: true)
|> Enum.find("Unknown validation error", &(String.trim(&1) != ""))
```

**Implementation Steps:**
1. Add trim: true to String.split
2. Swap argument order in Enum.find (default first)
3. Verify error messages still extracted correctly

**Success Criteria:**
- [ ] trim: true option added
- [ ] Enum.find argument order corrected
- [ ] Tests passing
- [ ] Error messages still correct

---

### 🟢 LOW PRIORITY (Future Improvements)

#### L1. Add Reader.parse_file/2 Convenience Function
**Severity:** LOW ENHANCEMENT
**Effort:** 30 minutes
**Review Section:** Senior Engineering Review
**Files Affected:**
- `lib/elixir_ontologies/shacl/reader.ex`
- `test/elixir_ontologies/shacl/reader_test.exs`

**Enhancement:**
Add convenience functions for common use cases:

```elixir
@spec parse_file(Path.t(), keyword()) :: {:ok, [NodeShape.t()]} | {:error, term()}
def parse_file(path, opts \\ []) do
  with {:ok, graph} <- RDF.Turtle.read_file(path) do
    parse_shapes(graph, opts)
  end
end

@spec parse_turtle(String.t(), keyword()) :: {:ok, [NodeShape.t()]} | {:error, term()}
def parse_turtle(turtle_string, opts \\ []) do
  with {:ok, graph} <- RDF.Turtle.read_string(turtle_string) do
    parse_shapes(graph, opts)
  end
end
```

**Success Criteria:**
- [ ] parse_file/2 function added
- [ ] parse_turtle/2 function added
- [ ] Documentation with examples
- [ ] 2+ tests for new functions

---

#### L2. Add Property-Based Tests with StreamData
**Severity:** LOW QUALITY ENHANCEMENT
**Effort:** 4-6 hours
**Review Section:** QA and Test Coverage Review
**Files Affected:**
- `test/elixir_ontologies/shacl/reader_property_test.exs` (new)

**Enhancement:**
Add property-based tests for RDF list parsing and graph structures:

```elixir
defmodule ElixirOntologies.SHACL.ReaderPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "parses any valid RDF list" do
    check all list_values <- list_of(integer(), min_length: 0, max_length: 100) do
      graph = build_rdf_list(list_values)
      assert {:ok, parsed} = Reader.parse_rdf_list(graph, list_head)
      assert parsed == list_values
    end
  end
end
```

---

#### L3. Add Performance Tests for Large Graphs
**Severity:** LOW QUALITY ENHANCEMENT
**Effort:** 2-3 hours
**Review Section:** QA and Test Coverage Review
**Files Affected:**
- `test/elixir_ontologies/shacl/reader_performance_test.exs` (new)

**Enhancement:**
Add performance benchmarks for large SHACL graphs:

```elixir
@tag :performance
test "parses graph with 1000+ shapes efficiently" do
  graph = generate_large_shape_graph(1000)

  {time_us, {:ok, shapes}} = :timer.tc(fn ->
    Reader.parse_shapes(graph)
  end)

  assert length(shapes) == 1000
  assert time_us < 5_000_000  # Less than 5 seconds
end
```

---

#### L4. Add PropertyShape.validate/1 Constructor
**Severity:** LOW ENHANCEMENT
**Effort:** 3-4 hours
**Review Section:** Senior Engineering Review
**Files Affected:**
- `lib/elixir_ontologies/shacl/model/property_shape.ex`

**Enhancement:**
Add validation for constraint combinations:

```elixir
@spec validate(t()) :: {:ok, t()} | {:error, String.t()}
def validate(%__MODULE__{} = shape) do
  with :ok <- validate_datatype_class_exclusive(shape),
       :ok <- validate_count_constraints(shape),
       :ok <- validate_length_constraints(shape) do
    {:ok, shape}
  end
end

defp validate_datatype_class_exclusive(shape) do
  if shape.datatype != nil && shape.class != nil do
    {:error, "PropertyShape cannot have both datatype and class constraints"}
  else
    :ok
  end
end
```

---

## Implementation Roadmap

### Phase 1: Critical Blockers (Before Section 11.2)
**Timeline:** 1-2 days
**Estimated Effort:** 12-18 hours
**Must Complete Before:** Task 11.2.1 starts

**Tasks:**
1. **B1: Add sh:maxInclusive Support** (4-6 hours)
   - Add fields to PropertyShape struct
   - Update Reader to parse constraints
   - Add 3-5 tests
   - Verify elixir-shapes.ttl parses correctly

2. **B2: Resolve Dual Model Hierarchy** (8-12 hours)
   - Implement Option 1: Migrate to SHACL.Model.ValidationReport
   - Add conversion helpers
   - Update Validator.validate/2
   - Deprecate old Report module
   - Update all tests
   - Add migration documentation

**Exit Criteria:**
- [ ] All production shapes parse successfully (including maxInclusive)
- [ ] Writer integrates seamlessly with Validator.validate/2
- [ ] Single validation report model in use
- [ ] No breaking changes in test suite
- [ ] All 112 tests passing
- [ ] Documentation updated

**Priority:** MUST COMPLETE - Cannot proceed to Section 11.2 without these fixes.

---

### Phase 2: Security Fixes (During Section 11.2)
**Timeline:** 1 day
**Estimated Effort:** 12-18 hours
**Can be done in parallel with validator implementation**

**Tasks:**
3. **H1: Fix ReDoS Vulnerability** (2-3 hours)
   - Add max regex length check (500 bytes)
   - Add compilation timeout (100ms)
   - Implement Task-based timeout handling
   - Add security tests

4. **H2: Create SHACL.Vocabulary Module** (4-6 hours)
   - Create vocabulary.ex with all 35+ constants
   - Migrate Reader to use Vocabulary
   - Migrate Writer to use Vocabulary
   - Migrate ReportParser to use Vocabulary
   - Migrate WriterTest to use Vocabulary
   - Remove duplicate constants

5. **H3: Add RDF List Depth Limit** (2 hours)
   - Add depth parameter to parse_rdf_list/3
   - Implement max depth check (1000)
   - Add security tests for deep/circular lists

6. **H4: Enhanced Error Handling** (3-4 hours)
   - Add 10+ error handling tests
   - Test empty graphs, blank nodes, invalid patterns
   - Improve error messages

**Exit Criteria:**
- [ ] No ReDoS vulnerability
- [ ] Zero vocabulary duplication (~100 lines eliminated)
- [ ] Deep recursion protected
- [ ] Comprehensive error handling
- [ ] All security tests passing
- [ ] All 112+ tests passing

**Priority:** HIGH - Should complete during Section 11.2 to ensure security.

---

### Phase 3: Code Quality Improvements (After Section 11.2)
**Timeline:** 1 day
**Estimated Effort:** 7-9 hours
**Low priority technical debt cleanup**

**Tasks:**
7. **M1: Extract normalize_to_list Helper** (1 hour)
   - Create helper function
   - Replace 9+ occurrences
   - Eliminate ~40 lines duplication

8. **M2: Create RDFTestHelpers Module** (2 hours)
   - Create test/support/rdf_test_helpers.ex
   - Centralize get_objects/2
   - Add get_subjects/3

9. **M3: Fix Temp File Race Condition** (1 hour)
   - Use :crypto.strong_rand_bytes
   - Add [:exclusive] flag
   - Add collision retry

10. **M4: Module Naming Consistency** (1 hour)
    - Rename ShaclEngine → SHACLEngine
    - Update all references

11. **M5: Pattern Matching in has_violations?** (15 minutes)
    - Replace length check with pattern matching

12. **M6: Optimize String.split** (10 minutes)
    - Add trim: true option

**Exit Criteria:**
- [ ] Code duplication minimized
- [ ] Consistency at 100%
- [ ] No race conditions
- [ ] Idiomatic Elixir patterns throughout
- [ ] All tests passing

**Priority:** MEDIUM - Nice to have, improves maintainability.

---

### Phase 4: Future Enhancements (Optional)
**Timeline:** 2-3 days (optional)
**Estimated Effort:** 10-15 hours
**Enhancement features, not required**

**Tasks:**
13. **L1: Reader Convenience Functions** (30 minutes)
    - Add parse_file/2
    - Add parse_turtle/2

14. **L2: Property-Based Tests** (4-6 hours)
    - Add StreamData tests for RDF lists
    - Add property tests for graph parsing

15. **L3: Performance Tests** (2-3 hours)
    - Add benchmarks for large graphs (1000+ shapes)
    - Set performance baselines

16. **L4: PropertyShape.validate/1** (3-4 hours)
    - Add constraint validation
    - Prevent invalid constraint combinations

**Exit Criteria:**
- [ ] Convenience functions available
- [ ] Property-based test coverage
- [ ] Performance benchmarks established
- [ ] Shape validation available

**Priority:** LOW - Future improvements, not blocking.

---

## Summary Statistics

### Issues by Priority
- **BLOCKERS:** 2 (sh:maxInclusive, dual models)
- **HIGH:** 4 (ReDoS, vocabulary duplication, RDF depth, error handling)
- **MEDIUM:** 6 (helpers, test helpers, race condition, naming, optimizations)
- **LOW:** 4 (convenience functions, property tests, performance, validation)

### Total Effort Estimate
- **Phase 1 (Blockers):** 12-18 hours
- **Phase 2 (Security):** 12-18 hours
- **Phase 3 (Quality):** 7-9 hours
- **Phase 4 (Future):** 10-15 hours
- **TOTAL:** 41-60 hours (~1-1.5 weeks)

### Files Affected
- **Core SHACL:** 5 files (vocabulary.ex, reader.ex, writer.ex, property_shape.ex, validation_report.ex)
- **Validator:** 3 files (validator.ex, report.ex, shacl_engine.ex)
- **Tests:** 4 files (reader_test.exs, writer_test.exs, validator_test.exs, rdf_test_helpers.ex)
- **Total:** ~12 files

### Expected Improvements
- **Test Count:** 112 → 130+ tests
- **Lines Removed:** ~140 lines of duplication
- **Security Issues:** 3 → 0
- **Code Quality:** 94/100 → 98/100
- **Consistency:** 99.4% → 100%
- **Overall Grade:** B+ (87/100) → A (95/100)

---

## Current Status

- **Review Completed:** 2025-12-12
- **Planning Document Created:** 2025-12-12
- **Next Step:** Begin Phase 1 - Fix Blockers
- **Branch:** `feature/phase-11-1-review-fixes` (to be created)
- **Target:** Complete Phase 1 before Section 11.2 begins

---

## How to Execute

### Phase 1 (REQUIRED)
```bash
# Create feature branch
git checkout -b feature/phase-11-1-critical-fixes

# Fix B1: sh:maxInclusive support
# Edit: lib/elixir_ontologies/shacl/model/property_shape.ex
# Edit: lib/elixir_ontologies/shacl/reader.ex
# Edit: test/elixir_ontologies/shacl/reader_test.exs

# Fix B2: Dual model hierarchy
# Edit: lib/elixir_ontologies/shacl/model/validation_result.ex
# Edit: lib/elixir_ontologies/validator.ex
# Edit: lib/elixir_ontologies/validator/report.ex
# Update all tests

# Verify
mix test
mix credo --strict
```

### Phase 2 (HIGH PRIORITY)
```bash
# Create feature branch
git checkout -b feature/phase-11-1-security-fixes

# Fix H1: ReDoS vulnerability
# Fix H2: SHACL vocabulary duplication
# Fix H3: RDF list depth limit
# Fix H4: Error handling

# Verify
mix test
mix credo --strict
```

### Phase 3 (CLEANUP)
```bash
# Create feature branch
git checkout -b feature/phase-11-1-code-quality

# Fix M1-M6 (medium priority items)

# Verify
mix test
mix credo --strict
```

### Phase 4 (OPTIONAL)
```bash
# Add enhancements as time permits
# L1-L4 (low priority enhancements)
```

---

## References

- **Review Document:** `/home/ducky/code/elixir-ontologies/notes/reviews/section-11-1-shacl-infrastructure-review.md`
- **W3C SHACL Specification:** https://www.w3.org/TR/shacl/
- **Phase 11 Planning:** `/home/ducky/code/elixir-ontologies/notes/planning/phase-11.md`
- **Existing Code:** `lib/elixir_ontologies/shacl/` and `lib/elixir_ontologies/validator/`
