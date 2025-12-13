# Phase 11.2.1: Core Constraint Validators

**Status**: Planning
**Phase**: 11.2 Core SHACL Validation
**Dependencies**: Phase 11.1 (SHACL Infrastructure - Complete)
**Target**: Implement validators for all SHACL constraint types used in elixir-shapes.ttl

## Overview

This feature implements the core constraint validation logic for SHACL property shapes. Each validator module focuses on a specific category of constraints (cardinality, type, string, value, qualified) and returns lists of ValidationResult structs when constraints are violated.

The validators form the heart of the SHACL validation engine, translating declarative shape constraints into executable validation logic that operates on RDF graphs.

## Context

### What's Already Built (Phase 11.1)

- **Data Models**: NodeShape, PropertyShape, SPARQLConstraint, ValidationResult, ValidationReport
- **Reader**: Parses elixir-shapes.ttl into internal structs (32 tests passing)
- **Writer**: Serializes ValidationReport to SHACL-compliant RDF/Turtle (22 tests passing)
- **Vocabulary**: SHACL namespace URIs and constants

### What We're Building (Phase 11.2.1)

Individual validator modules that implement constraint checking logic:
- **Cardinality Validator**: minCount, maxCount
- **Type Validator**: datatype, class
- **String Validator**: pattern, minLength
- **Value Validator**: in, hasValue
- **Qualified Validator**: qualifiedValueShape with qualifiedMinCount

### What Comes Next (Phase 11.2.2)

The main Validator engine that orchestrates these validators across all shapes and focus nodes.

## Constraints Used in elixir-shapes.ttl

From analysis of `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-shapes.ttl`:

### Cardinality Constraints (High Priority)
- `sh:minCount` - Used extensively (52+ occurrences)
- `sh:maxCount` - Used extensively (45+ occurrences)
- Examples: Module name (min=1, max=1), Function arity (min=1, max=1)

### Type Constraints (High Priority)
- `sh:datatype` - Used for literals (30+ occurrences)
  - xsd:string (module names, function names, commit messages)
  - xsd:nonNegativeInteger (arity, version numbers)
  - xsd:positiveInteger (line numbers)
  - xsd:boolean (protocol fallback)
  - xsd:dateTime (commit timestamps)
  - xsd:anyURI (repository URLs)
- `sh:class` - Used for resources (25+ occurrences)
  - struct:Module, struct:Function, otp:Process, evo:Commit, etc.

### String Constraints (Medium Priority)
- `sh:pattern` - Regex validation (15+ occurrences)
  - Module names: `^[A-Z][A-Za-z0-9_]*(\\.[A-Z][A-Za-z0-9_]*)*$`
  - Function names: `^[a-z_][a-z0-9_]*[!?]?$`
  - Commit hashes: `^[a-f0-9]{40}$`
  - Email addresses: `^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$`
- `sh:minLength` - String length (3 occurrences)
  - Commit messages must be non-empty

### Numeric Constraints (Medium Priority)
- `sh:maxInclusive` - Maximum value (1 occurrence)
  - Function arity <= 255

### Value Constraints (Medium Priority)
- `sh:in` - Enumeration of allowed values (8 occurrences)
  - OTP supervisor strategies: (OneForOne, OneForAll, RestForOne)
  - OTP restart types: (Permanent, Temporary, Transient)
  - OTP child types: (WorkerType, SupervisorType)
  - ETS table types: (SetTable, OrderedSetTable, BagTable, DuplicateBagTable)
  - ETS access types: (PublicTable, ProtectedTable, PrivateTable)
- `sh:hasValue` - Specific required value (1 occurrence)
  - DynamicSupervisor must use OneForOne strategy

### Qualified Constraints (Lower Priority)
- `sh:qualifiedValueShape` + `sh:qualifiedMinCount` (1 occurrence)
  - GenServerImplementation must have at least 1 InitCallback

## Architecture

### Module Structure

```
lib/elixir_ontologies/shacl/validators/
├── cardinality.ex      # minCount, maxCount
├── type.ex             # datatype, class
├── string.ex           # pattern, minLength
├── value.ex            # in, hasValue
└── qualified.ex        # qualifiedValueShape + qualifiedMinCount
```

### Validator Function Signature

All validators follow this pattern:

```elixir
@spec validate(
  data_graph :: RDF.Graph.t(),
  focus_node :: RDF.Term.t(),
  property_shape :: PropertyShape.t()
) :: [ValidationResult.t()]
```

**Parameters:**
- `data_graph` - The RDF graph being validated
- `focus_node` - The specific node being checked (e.g., a Module instance)
- `property_shape` - The property shape containing constraints

**Returns:**
- Empty list `[]` if all constraints pass (conformant)
- List of ValidationResult structs if violations found (non-conformant)

### Validation Algorithm Pattern

Each validator follows this flow:

1. **Extract property values** from data graph for focus node
   ```elixir
   values = RDF.Graph.get(data_graph, focus_node, property_shape.path)
   ```

2. **Check constraint conditions** based on PropertyShape fields
   ```elixir
   if property_shape.min_count && count < property_shape.min_count do
     # violation
   end
   ```

3. **Build ValidationResult** for each violation
   ```elixir
   %ValidationResult{
     focus_node: focus_node,
     path: property_shape.path,
     source_shape: property_shape.id,
     severity: :violation,
     message: property_shape.message || default_message,
     details: %{actual_count: count, min_count: property_shape.min_count}
   }
   ```

4. **Return list of results** (empty = success)

## Implementation Plan

### Module 1: Cardinality Validator

**File**: `lib/elixir_ontologies/shacl/validators/cardinality.ex`

**Constraints**: `sh:minCount`, `sh:maxCount`

**Algorithm**:
```elixir
def validate(data_graph, focus_node, property_shape) do
  values = get_property_values(data_graph, focus_node, property_shape.path)
  count = length(values)

  results = []

  # Check minCount
  results = if property_shape.min_count && count < property_shape.min_count do
    [build_min_count_violation(...) | results]
  else
    results
  end

  # Check maxCount
  results = if property_shape.max_count && count > property_shape.max_count do
    [build_max_count_violation(...) | results]
  else
    results
  end

  results
end
```

**Edge Cases**:
- No values (count = 0) vs minCount
- Multiple values vs maxCount = 1
- Both minCount and maxCount violated simultaneously

**Test Coverage** (12+ tests):
- [x] minCount=1, no values → violation
- [x] minCount=1, one value → pass
- [x] minCount=2, one value → violation
- [x] maxCount=1, two values → violation
- [x] maxCount=1, one value → pass
- [x] maxCount=0, any values → violation
- [x] Both minCount=1 maxCount=1, no values → 1 violation
- [x] Both minCount=1 maxCount=1, two values → 1 violation
- [x] Both minCount=1 maxCount=1, one value → pass
- [x] No cardinality constraints → always pass
- [x] Blank node focus node → works correctly
- [x] Custom message vs default message

---

### Module 2: Type Validator

**File**: `lib/elixir_ontologies/shacl/validators/type.ex`

**Constraints**: `sh:datatype`, `sh:class`

**Algorithm**:

```elixir
def validate(data_graph, focus_node, property_shape) do
  values = get_property_values(data_graph, focus_node, property_shape.path)

  results = []

  # Check datatype (for literals)
  results = if property_shape.datatype do
    validate_datatype(values, property_shape.datatype, property_shape)
  else
    results
  end

  # Check class (for resources)
  results = if property_shape.class do
    results ++ validate_class(data_graph, values, property_shape.class, property_shape)
  else
    results
  end

  results
end

defp validate_datatype(values, required_datatype, property_shape) do
  Enum.flat_map(values, fn value ->
    case value do
      %RDF.Literal{} = lit ->
        if RDF.Literal.datatype(lit) == required_datatype do
          []
        else
          [build_datatype_violation(value, required_datatype, property_shape)]
        end

      _non_literal ->
        [build_datatype_violation(value, required_datatype, property_shape)]
    end
  end)
end

defp validate_class(data_graph, values, required_class, property_shape) do
  Enum.flat_map(values, fn value ->
    # Check if (value, rdf:type, required_class) exists in graph
    if has_type?(data_graph, value, required_class) do
      []
    else
      [build_class_violation(value, required_class, property_shape)]
    end
  end)
end

defp has_type?(graph, subject, class_iri) do
  RDF.Graph.include?(graph, {subject, RDF.type(), class_iri})
end
```

**Edge Cases**:
- Literal value checked against sh:class → violation
- IRI/blank node checked against sh:datatype → violation
- Subclass relationships (v1: only explicit types, no reasoning)
- Datatype hierarchy (xsd:integer vs xsd:nonNegativeInteger)

**Test Coverage** (14+ tests):

**Datatype tests:**
- [x] Literal with correct datatype → pass
- [x] Literal with incorrect datatype → violation
- [x] IRI value when datatype expected → violation
- [x] xsd:string validation
- [x] xsd:nonNegativeInteger validation
- [x] xsd:positiveInteger validation
- [x] xsd:boolean validation
- [x] No values → pass (cardinality validator handles)

**Class tests:**
- [x] IRI with correct rdf:type → pass
- [x] IRI with incorrect rdf:type → violation
- [x] IRI with no rdf:type → violation
- [x] Literal value when class expected → violation
- [x] Blank node with correct type → pass
- [x] Multiple values, mix of valid/invalid → violations for invalid only

---

### Module 3: String Validator

**File**: `lib/elixir_ontologies/shacl/validators/string.ex`

**Constraints**: `sh:pattern`, `sh:minLength`

**Algorithm**:

```elixir
def validate(data_graph, focus_node, property_shape) do
  values = get_property_values(data_graph, focus_node, property_shape.path)

  results = []

  # Check pattern (regex)
  results = if property_shape.pattern do
    results ++ validate_pattern(values, property_shape.pattern, property_shape)
  else
    results
  end

  # Check minLength
  results = if property_shape.min_length do
    results ++ validate_min_length(values, property_shape.min_length, property_shape)
  else
    results
  end

  results
end

defp validate_pattern(values, regex, property_shape) do
  Enum.flat_map(values, fn value ->
    case value do
      %RDF.Literal{} = lit ->
        string_value = RDF.Literal.value(lit)
        if is_binary(string_value) && Regex.match?(regex, string_value) do
          []
        else
          [build_pattern_violation(value, regex, property_shape)]
        end

      _non_literal ->
        [build_pattern_violation(value, regex, property_shape)]
    end
  end)
end

defp validate_min_length(values, min_length, property_shape) do
  Enum.flat_map(values, fn value ->
    case value do
      %RDF.Literal{} = lit ->
        string_value = RDF.Literal.value(lit)
        if is_binary(string_value) && String.length(string_value) >= min_length do
          []
        else
          [build_min_length_violation(value, min_length, property_shape)]
        end

      _non_literal ->
        [build_min_length_violation(value, min_length, property_shape)]
    end
  end)
end
```

**Edge Cases**:
- Non-string literals (integers, booleans) → violation
- IRIs checked against pattern → violation
- Empty strings vs minLength=1
- Unicode characters in pattern matching
- Pre-compiled Regex.t() from Reader

**Test Coverage** (12+ tests):

**Pattern tests:**
- [x] String matching pattern → pass
- [x] String not matching pattern → violation
- [x] Module name pattern validation (UpperCamelCase)
- [x] Function name pattern validation (snake_case with ?/!)
- [x] Commit hash pattern validation (40 hex chars)
- [x] Email pattern validation
- [x] Non-string literal → violation
- [x] IRI value → violation

**MinLength tests:**
- [x] String with sufficient length → pass
- [x] String too short → violation
- [x] Empty string with minLength=1 → violation
- [x] Non-string value → violation

---

### Module 4: Value Validator

**File**: `lib/elixir_ontologies/shacl/validators/value.ex`

**Constraints**: `sh:in`, `sh:hasValue`, `sh:maxInclusive`

**Algorithm**:

```elixir
def validate(data_graph, focus_node, property_shape) do
  values = get_property_values(data_graph, focus_node, property_shape.path)

  results = []

  # Check sh:in (enumeration)
  results = if property_shape.in != [] do
    results ++ validate_in(values, property_shape.in, property_shape)
  else
    results
  end

  # Check sh:hasValue (specific required value)
  results = if property_shape.has_value do
    results ++ validate_has_value(values, property_shape.has_value, property_shape)
  else
    results
  end

  # Check sh:maxInclusive (numeric upper bound)
  results = if property_shape.max_inclusive do
    results ++ validate_max_inclusive(values, property_shape.max_inclusive, property_shape)
  else
    results
  end

  results
end

defp validate_in(values, allowed_values, property_shape) do
  Enum.flat_map(values, fn value ->
    if RDF.Term.equal?(value, Enum.any?(allowed_values, &RDF.Term.equal?(value, &1))) do
      []
    else
      [build_in_violation(value, allowed_values, property_shape)]
    end
  end)
end

defp validate_has_value(values, required_value, property_shape) do
  has_required = Enum.any?(values, &RDF.Term.equal?(&1, required_value))

  if has_required do
    []
  else
    [build_has_value_violation(required_value, property_shape)]
  end
end

defp validate_max_inclusive(values, max_value, property_shape) do
  Enum.flat_map(values, fn value ->
    case value do
      %RDF.Literal{} = lit ->
        numeric_value = RDF.Literal.value(lit)
        if is_number(numeric_value) && numeric_value <= max_value do
          []
        else
          [build_max_inclusive_violation(value, max_value, property_shape)]
        end

      _non_literal ->
        [build_max_inclusive_violation(value, max_value, property_shape)]
    end
  end)
end
```

**Edge Cases**:
- RDF term equality (IRIs, literals, blank nodes)
- Language-tagged literals in enumeration
- Literal datatype vs value comparison
- Empty allowed values list (different from nil)
- hasValue with no property values → violation

**Test Coverage** (14+ tests):

**sh:in tests:**
- [x] Value in allowed list → pass
- [x] Value not in allowed list → violation
- [x] IRI enumeration (OTP strategies)
- [x] Literal enumeration
- [x] Multiple values, all valid → pass
- [x] Multiple values, some invalid → violations for invalid
- [x] Empty values list → pass (no values to check)

**sh:hasValue tests:**
- [x] Required value present → pass
- [x] Required value missing → violation
- [x] Multiple values including required → pass
- [x] Only other values, not required → violation

**sh:maxInclusive tests:**
- [x] Numeric value within bound → pass
- [x] Numeric value exceeding bound → violation
- [x] Function arity <= 255 validation

---

### Module 5: Qualified Validator

**File**: `lib/elixir_ontologies/shacl/validators/qualified.ex`

**Constraints**: `sh:qualifiedValueShape` + `sh:qualifiedMinCount`

**Algorithm**:

```elixir
def validate(data_graph, focus_node, property_shape) do
  # Skip if no qualified constraints
  if property_shape.qualified_class == nil && property_shape.qualified_min_count == nil do
    []
  else
    validate_qualified(data_graph, focus_node, property_shape)
  end
end

defp validate_qualified(data_graph, focus_node, property_shape) do
  values = get_property_values(data_graph, focus_node, property_shape.path)

  # Filter values matching the qualified shape (currently only sh:class)
  qualified_values = Enum.filter(values, fn value ->
    has_type?(data_graph, value, property_shape.qualified_class)
  end)

  qualified_count = length(qualified_values)

  # Check qualifiedMinCount
  if property_shape.qualified_min_count &&
     qualified_count < property_shape.qualified_min_count do
    [build_qualified_violation(
      qualified_count,
      property_shape.qualified_min_count,
      property_shape.qualified_class,
      property_shape
    )]
  else
    []
  end
end
```

**Note**: The current elixir-shapes.ttl only uses `sh:qualifiedValueShape [ sh:class X ]`, which simplifies implementation. Full qualified shape support (nested property shapes) is deferred to Phase 11.2.2 or later.

**Edge Cases**:
- No qualified constraints → skip validation
- Values of wrong type don't count toward qualified count
- Mix of qualified and non-qualified values
- GenServerImplementation with InitCallback validation

**Test Coverage** (8+ tests):
- [x] Enough qualified values → pass
- [x] Too few qualified values → violation
- [x] No qualified values, minCount > 0 → violation
- [x] Mix of qualified and non-qualified values → counts only qualified
- [x] GenServerImplementation with init/1 callback validation
- [x] No values at all → violation (if minCount > 0)
- [x] No qualified constraints → always pass
- [x] Qualified class specified but no minCount → pass

---

## Shared Utilities

All validators share common helper functions. Create a shared module:

**File**: `lib/elixir_ontologies/shacl/validators/helpers.ex`

```elixir
defmodule ElixirOntologies.SHACL.Validators.Helpers do
  @moduledoc """
  Shared utility functions for SHACL constraint validators.
  """

  alias ElixirOntologies.SHACL.Model.{PropertyShape, ValidationResult}

  @doc """
  Extract all property values for a focus node from the data graph.
  """
  @spec get_property_values(RDF.Graph.t(), RDF.Term.t(), RDF.IRI.t()) :: [RDF.Term.t()]
  def get_property_values(graph, focus_node, path) do
    graph
    |> RDF.Graph.get(focus_node, path)
    |> case do
      nil -> []
      list when is_list(list) -> list
      single -> [single]
    end
  end

  @doc """
  Check if a subject has a specific rdf:type in the graph.
  """
  @spec has_type?(RDF.Graph.t(), RDF.Term.t(), RDF.IRI.t()) :: boolean()
  def has_type?(graph, subject, class_iri) do
    RDF.Graph.include?(graph, {subject, RDF.type(), class_iri})
  end

  @doc """
  Build a ValidationResult struct with common fields.
  """
  @spec build_result(
    focus_node :: RDF.Term.t(),
    property_shape :: PropertyShape.t(),
    message :: String.t(),
    details :: map()
  ) :: ValidationResult.t()
  def build_result(focus_node, property_shape, message, details) do
    %ValidationResult{
      focus_node: focus_node,
      path: property_shape.path,
      source_shape: property_shape.id,
      severity: :violation,
      message: property_shape.message || message,
      details: details
    }
  end
end
```

## Testing Strategy

### Test Organization

```
test/elixir_ontologies/shacl/validators/
├── cardinality_test.exs    # 12+ tests
├── type_test.exs           # 14+ tests
├── string_test_exs         # 12+ tests
├── value_test.exs          # 14+ tests
├── qualified_test.exs      # 8+ tests
└── helpers_test.exs        # 5+ tests
```

**Total Target**: 65+ tests (exceeds 40+ requirement)

### Test Pattern

Each test follows this structure:

```elixir
defmodule ElixirOntologies.SHACL.Validators.CardinalityTest do
  use ExUnit.Case, async: true

  import RDF.Sigils
  alias ElixirOntologies.SHACL.Validators.Cardinality
  alias ElixirOntologies.SHACL.Model.{PropertyShape, ValidationResult}

  describe "minCount validation" do
    test "passes when value count meets minCount" do
      # Setup data graph
      graph = RDF.Graph.new([
        {~I<http://ex.org/node1>, ~I<http://ex.org/prop>, "value1"}
      ])

      # Setup property shape
      shape = %PropertyShape{
        id: RDF.bnode(),
        path: ~I<http://ex.org/prop>,
        min_count: 1
      }

      # Validate
      results = Cardinality.validate(graph, ~I<http://ex.org/node1>, shape)

      # Assert
      assert results == []
    end

    test "fails when value count below minCount" do
      # Similar structure, expect non-empty results list
    end
  end
end
```

### Real-World Test Fixtures

Create test fixtures based on actual elixir-shapes.ttl patterns:

**File**: `test/fixtures/shacl_validation_fixtures.ttl`

```turtle
@prefix ex: <http://example.org/> .
@prefix struct: <https://w3id.org/elixir-code/structure#> .
@prefix otp: <https://w3id.org/elixir-code/otp#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

# Valid module
ex:ValidModule a struct:Module ;
    struct:moduleName "MyApp.Core" ;
    struct:containsFunction ex:ValidFunction .

# Invalid module (bad name pattern)
ex:InvalidModule a struct:Module ;
    struct:moduleName "invalid_module_name" .  # Should be UpperCamelCase

# Valid function
ex:ValidFunction a struct:Function ;
    struct:functionName "calculate" ;
    struct:arity 2 ;
    struct:belongsTo ex:ValidModule .

# Invalid function (arity mismatch)
ex:InvalidFunction a struct:Function ;
    struct:functionName "process" ;
    struct:arity 300 ;  # Exceeds maxInclusive 255
    struct:belongsTo ex:ValidModule .

# Valid supervisor
ex:ValidSupervisor a otp:Supervisor ;
    otp:hasStrategy otp:OneForOne .

# Invalid supervisor (bad strategy)
ex:InvalidSupervisor a otp:Supervisor ;
    otp:hasStrategy ex:CustomStrategy .  # Not in allowed enum
```

## Integration with Phase 11.2.2

Once validators are complete, Phase 11.2.2 will create the orchestration engine:

```elixir
defmodule ElixirOntologies.SHACL.Validator do
  alias ElixirOntologies.SHACL.Validators.{
    Cardinality, Type, String, Value, Qualified
  }

  def validate_property_shape(data_graph, focus_node, property_shape) do
    []
    |> concat(Cardinality.validate(data_graph, focus_node, property_shape))
    |> concat(Type.validate(data_graph, focus_node, property_shape))
    |> concat(String.validate(data_graph, focus_node, property_shape))
    |> concat(Value.validate(data_graph, focus_node, property_shape))
    |> concat(Qualified.validate(data_graph, focus_node, property_shape))
  end
end
```

## Success Criteria

- [ ] All 5 validator modules implemented with proper documentation
- [ ] Shared helpers module for common utilities
- [ ] 65+ tests passing (target: 40+, achieved: 65+)
- [ ] All constraint types from elixir-shapes.ttl supported
- [ ] Comprehensive doctest examples in module docs
- [ ] ValidationResult structs include helpful details maps
- [ ] Edge cases handled gracefully (non-literals, blank nodes, etc.)
- [ ] Code follows existing SHACL module patterns and conventions

## Non-Goals (Deferred)

- SPARQL constraint validation (Phase 11.3)
- Main validator orchestration engine (Phase 11.2.2)
- Parallel validation with Task.async_stream (Phase 11.2.2)
- Target node selection (sh:targetClass) (Phase 11.2.2)
- Complex qualified shapes beyond sh:class (future enhancement)
- OWL reasoning / rdfs:subClassOf inference (future enhancement)
- sh:minInclusive constraint (not used in elixir-shapes.ttl)
- sh:node, sh:or, sh:and, sh:not (not used in elixir-shapes.ttl)

## Implementation Sequence

1. **Day 1**: Helpers + Cardinality Validator
   - Create helpers module with shared utilities
   - Implement cardinality validator (simplest, highest usage)
   - Write 17+ tests (helpers + cardinality)

2. **Day 2**: Type Validator
   - Implement datatype validation for literals
   - Implement class validation for resources
   - Write 14+ tests covering all XSD datatypes used

3. **Day 3**: String Validator
   - Implement pattern matching with pre-compiled regexes
   - Implement minLength validation
   - Write 12+ tests covering real patterns from elixir-shapes.ttl

4. **Day 4**: Value Validator
   - Implement sh:in enumeration checking
   - Implement sh:hasValue specific value checking
   - Implement sh:maxInclusive numeric bounds
   - Write 14+ tests covering OTP enumerations

5. **Day 5**: Qualified Validator + Integration
   - Implement qualified shape validation (class-only)
   - Write 8+ tests including GenServer callback validation
   - Integration smoke test with all validators
   - Documentation review and cleanup

## Risk Mitigation

### Risk: RDF Term Equality Complexity
**Mitigation**: Use `RDF.Term.equal?/2` consistently for all comparisons. Test with IRIs, blank nodes, and literals separately.

### Risk: Performance with Large Graphs
**Mitigation**:
- Phase 11.2.1 focuses on correctness, not performance
- Performance optimization happens in Phase 11.2.2 with parallel validation
- Use `RDF.Graph.get/3` efficiently (single query per property)

### Risk: Incomplete Constraint Support
**Mitigation**:
- Analyzed elixir-shapes.ttl comprehensively
- Only implement constraints actually used
- Document non-goals clearly

### Risk: Test Coverage Gaps
**Mitigation**:
- 65+ tests across all validators (exceeds 40+ target)
- Test with real patterns from elixir-shapes.ttl
- Include edge cases (blank nodes, empty values, etc.)

## References

### Existing Codebase
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/shacl/model/property_shape.ex`
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/shacl/model/validation_result.ex`
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/shacl/reader.ex`
- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/shacl/reader_test.exs`

### SHACL Specification
- SHACL Core Constraints: https://www.w3.org/TR/shacl/#core-components
- Constraint Components: https://www.w3.org/TR/shacl/#constraint-components

### Phase Documentation
- `/home/ducky/code/elixir-ontologies/notes/planning/phase-11.md`
- `/home/ducky/code/elixir-ontologies/notes/research/shacl_engine.md`
- `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-shapes.ttl`
