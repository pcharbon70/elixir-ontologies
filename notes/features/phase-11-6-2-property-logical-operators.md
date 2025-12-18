# Phase 11.6.2: Property-Level Logical Operators Implementation Plan

**Date**: 2025-12-14
**Status**: Planning
**Branch**: `feature/phase-11-6-2-property-logical-operators`
**Previous Phase**: Phase 11.6.1 (Node-Level Logical Operators - Completed)

## Problem Statement

### Current Status
- **W3C Test Pass Rate:** 64.2% (34/53 tests)
- **Blocked Tests:** 1 W3C test failing due to missing property-level logical operators
  - `xone-duplicate` - Tests sh:xone on property values (not focus node)

### What We Have (Phase 11.6.1 Complete)
Our SHACL implementation now supports **node-level logical operators** via the `LogicalOperators` validator module:

```turtle
# Node-level: Validates the FOCUS NODE itself
ex:PersonShape
  rdf:type sh:NodeShape ;
  sh:targetClass ex:Person ;
  sh:xone (
    [ sh:property [ sh:path ex:fullName ; sh:minCount 1 ] ]
    [ sh:property [ sh:path ex:firstName ; sh:minCount 1 ]
      sh:property [ sh:path ex:lastName ; sh:minCount 1 ] ]
  ) .

# Validation: Does the focus node (ex:Bob) conform to exactly one of the shapes?
# Result: ex:Bob has firstName+lastName → conforms to second shape only → PASS
```

### The Gap: Property-Level Logical Operators

**What we don't support:**

```turtle
# Property-level: Validates PROPERTY VALUES
ex:TestShape
  rdf:type sh:NodeShape ;
  sh:targetClass ex:C1 ;
  sh:property [
    sh:path ex:value ;
    sh:xone (                    # Applied to VALUES of ex:value property
      [ sh:datatype xsd:string ]
      [ sh:datatype xsd:integer ]
    )
  ] .

# Validation: For each value of ex:value, does it conform to exactly one datatype?
# Example: ex:obj1 ex:value "hello", 42 → both values should fail (each matches one type)
```

### Critical Difference: Node-Level vs Property-Level

| Aspect | Node-Level (✅ Complete) | Property-Level (❌ Missing) |
|--------|-------------------------|----------------------------|
| **Placement** | Directly on `sh:NodeShape` | On `sh:property` within `sh:NodeShape` |
| **Validates** | Focus node itself | Values obtained via `sh:path` |
| **Test Example** | `xone-001` (working) | `xone-duplicate` (failing) |
| **Data Model** | `NodeShape.node_xone` | `PropertyShape.property_xone` (needs adding) |
| **Validator** | `LogicalOperators.validate_node/4` | `LogicalOperators.validate_property/4` (needs adding) |

### Impact of xone-duplicate Test Failure

**Test Definition** (from W3C test suite):
```turtle
# Shapes
ex:s1 a sh:NodeShape ;
  sh:targetClass ex:C1 ;
  sh:xone ( ex:s2 ex:s2 ) .    # DUPLICATE shape reference!
ex:s2 sh:class ex:C2 .

# Data
ex:i a ex:C1 .                 # Instance of C1, NOT C2
ex:j a ex:C1 , ex:C2 .         # Instance of BOTH C1 and C2

# Expected Results:
# ex:i → VIOLATION (conforms to ex:s2 zero times, need exactly 1)
# ex:j → VIOLATION (conforms to ex:s2 TWICE because duplicate, need exactly 1)
```

**Current Behavior:** Test passes incorrectly (conforms = true)

**Root Cause Analysis:**

Looking at the test more carefully, this is actually a **node-level** xone test with a special edge case: duplicate shape references in the list. The test name "by property constraints" is misleading - it tests that sh:xone handles duplicate shapes correctly.

**Re-assessment:** This test is actually testing node-level xone with edge case handling, not property-level logical operators. However, implementing property-level logical operators is still valuable for completeness.

### Revised Understanding: True Property-Level Logical Operators

After analyzing the W3C test suite and SHACL specification, property-level logical operators would look like:

```turtle
# Example: Value must be string XOR integer (not both)
ex:TestShape a sh:NodeShape ;
  sh:targetClass ex:Thing ;
  sh:property [
    sh:path ex:mixedValue ;
    sh:xone (
      [ sh:datatype xsd:string ]
      [ sh:datatype xsd:integer ]
    )
  ] .

# This validates EACH VALUE individually
# ex:obj1 ex:mixedValue "hello" .     # Valid: string only
# ex:obj2 ex:mixedValue 42 .          # Valid: integer only
# ex:obj3 ex:mixedValue "42"^^xsd:integer . # Invalid: matches integer pattern but is string
```

### Why This Matters

1. **Specification Compliance**: Property-level logical operators are part of core SHACL spec
2. **Completeness**: Phase 11.6.1 implemented half the feature (node-level only)
3. **Real-World Use Cases**: Validate alternative property value structures
4. **Architecture Consistency**: Mirrors node-level implementation for symmetry

---

## Solution Overview

### High-Level Approach

Extend PropertyShape to support logical operators, mirroring the node-level implementation:

1. **Extend PropertyShape Model** - Add logical operator fields
2. **Update Reader** - Parse property-level logical operators from RDF
3. **Extend LogicalOperators Validator** - Add property-level validation functions
4. **Update Validator Orchestration** - Integrate property-level logical validation

### Conceptual Model

**Before** (Node-Level Only):
```
NodeShape
  ├─ Node-Level Logical Operators (node_and, node_or, node_xone, node_not)
  │    └─ Validated by: LogicalOperators.validate_node/4
  │         └─ Validates: Focus node itself
  └─ PropertyShapes[]
       └─ Constraints (datatype, minCount, pattern, etc.)
            └─ Validated by: Type.validate, String.validate, etc.
                 └─ Validates: Property values
```

**After** (Node-Level + Property-Level):
```
NodeShape
  ├─ Node-Level Logical Operators (node_and, node_or, node_xone, node_not)
  │    └─ Validated by: LogicalOperators.validate_node/4
  │         └─ Validates: Focus node itself
  └─ PropertyShapes[]
       ├─ Property-Level Logical Operators (property_and, property_or, property_xone, property_not)
       │    └─ Validated by: LogicalOperators.validate_property/5
       │         └─ Validates: Each property value individually
       └─ Other Constraints (datatype, minCount, pattern, etc.)
            └─ Validated by: Type.validate, String.validate, etc.
```

### Key Design Insight: Recursive Validation at Value Level

Property-level logical operators validate **each value** obtained via `sh:path`:

```elixir
# For each value V of property P on focus node F:
#   If PropertyShape has property_xone = [shape1, shape2]:
#     1. Validate V against shape1 → result1
#     2. Validate V against shape2 → result2
#     3. Count passing validations
#     4. If count != 1 → violation for value V
```

This differs from node-level where we validate the focus node F once.

---

## Technical Details

### 1. Data Model Changes

#### File: `lib/elixir_ontologies/shacl/model/property_shape.ex`

**Before**:
```elixir
defmodule ElixirOntologies.SHACL.Model.PropertyShape do
  @enforce_keys [:id, :path]
  defstruct [
    :id,
    :path,
    :message,

    # Cardinality
    min_count: nil,
    max_count: nil,

    # Type
    datatype: nil,
    class: nil,

    # String
    pattern: nil,
    min_length: nil,

    # Numeric
    min_inclusive: nil,
    max_inclusive: nil,

    # Value
    in: [],
    has_value: nil,

    # Qualified
    qualified_class: nil,
    qualified_min_count: nil
  ]
end
```

**After**:
```elixir
defmodule ElixirOntologies.SHACL.Model.PropertyShape do
  @enforce_keys [:id, :path]
  defstruct [
    :id,
    :path,
    :message,

    # Cardinality
    min_count: nil,
    max_count: nil,

    # Type
    datatype: nil,
    class: nil,

    # String
    pattern: nil,
    min_length: nil,

    # Numeric
    min_inclusive: nil,
    max_inclusive: nil,

    # Value
    in: [],
    has_value: nil,

    # Qualified
    qualified_class: nil,
    qualified_min_count: nil,

    # NEW: Property-level Logical Operators
    # These validate individual property values (not the focus node)
    property_and: nil,   # [RDF.IRI.t() | RDF.BlankNode.t()] | nil
    property_or: nil,    # [RDF.IRI.t() | RDF.BlankNode.t()] | nil
    property_xone: nil,  # [RDF.IRI.t() | RDF.BlankNode.t()] | nil
    property_not: nil    # RDF.IRI.t() | RDF.BlankNode.t() | nil
  ]

  @type t :: %__MODULE__{
    # ... existing types ...

    # Property-level logical operators
    property_and: [RDF.IRI.t() | RDF.BlankNode.t()] | nil,
    property_or: [RDF.IRI.t() | RDF.BlankNode.t()] | nil,
    property_xone: [RDF.IRI.t() | RDF.BlankNode.t()] | nil,
    property_not: RDF.IRI.t() | RDF.BlankNode.t() | nil
  }
end
```

**Key Changes**:
- Add 4 new fields: `property_and`, `property_or`, `property_xone`, `property_not`
- Default to `nil` (no logical constraints)
- Store shape references (IRIs or blank nodes) that will be resolved via shape_map

---

### 2. Reader Changes

#### File: `lib/elixir_ontologies/shacl/reader.ex`

**Update `parse_property_shape/2` function:**

```elixir
defp parse_property_shape(graph, property_shape_id) do
  with {:ok, path} <- parse_path(graph, property_shape_id),
       {:ok, message} <- parse_message(graph, property_shape_id),
       {:ok, constraints} <- parse_property_constraints(graph, property_shape_id),
       # NEW: Parse property-level logical operators
       {:ok, logical_ops} <- parse_property_logical_operators(graph, property_shape_id) do

    {:ok, %PropertyShape{
      id: property_shape_id,
      path: path,
      message: message,

      # Existing constraints
      min_count: constraints.min_count,
      max_count: constraints.max_count,
      datatype: constraints.datatype,
      class: constraints.class,
      pattern: constraints.pattern,
      min_length: constraints.min_length,
      min_inclusive: constraints.min_inclusive,
      max_inclusive: constraints.max_inclusive,
      in: constraints.in,
      has_value: constraints.has_value,
      qualified_class: constraints.qualified_class,
      qualified_min_count: constraints.qualified_min_count,

      # NEW: Logical operators
      property_and: logical_ops.and,
      property_or: logical_ops.or,
      property_xone: logical_ops.xone,
      property_not: logical_ops.not
    }}
  end
end

# NEW: Parse property-level logical operators
defp parse_property_logical_operators(graph, property_shape_id) do
  logical_ops = %{
    and: parse_rdf_list(graph, property_shape_id, SHACL.and()),
    or: parse_rdf_list(graph, property_shape_id, SHACL.or()),
    xone: parse_rdf_list(graph, property_shape_id, SHACL.xone()),
    not: get_single_object(graph, property_shape_id, SHACL.not())
  }

  {:ok, logical_ops}
end
```

**Implementation Notes**:
- Reuse existing `parse_rdf_list/3` helper (used for node-level operators)
- Same RDF predicates (`sh:and`, `sh:or`, `sh:xone`, `sh:not`)
- Different context: on PropertyShape instead of NodeShape

---

### 3. Validator Changes

#### File: `lib/elixir_ontologies/shacl/validators/logical_operators.ex`

**Add property-level validation functions:**

```elixir
@doc """
Validate property-level logical constraints on property values.

For each value obtained via property path, validates against logical operator shapes.

## Parameters

- `data_graph` - RDF.Graph.t() containing the data to validate
- `focus_node` - RDF.Term.t() the node being validated
- `property_shape` - PropertyShape.t() containing logical operator constraints
- `shape_map` - Map of shape_id -> NodeShape for resolving references
- `depth` - Current recursion depth (default: 0)

## Returns

List of ValidationResult.t() structs (empty = no violations)
"""
@spec validate_property(
        RDF.Graph.t(),
        RDF.Term.t(),
        PropertyShape.t(),
        %{(RDF.IRI.t() | RDF.BlankNode.t()) => NodeShape.t()},
        non_neg_integer()
      ) :: [ValidationResult.t()]
def validate_property(data_graph, focus_node, property_shape, shape_map, depth \\ 0) do
  if depth > @max_recursion_depth do
    Logger.error(
      "Max recursion depth exceeded validating property logical operators for #{inspect(property_shape.id)}"
    )
    []
  else
    # Get all values for this property
    values = get_property_values(data_graph, focus_node, property_shape.path)

    # Validate each value against logical operators
    Enum.flat_map(values, fn value ->
      []
      |> concat(validate_property_and(data_graph, focus_node, value, property_shape, shape_map, depth))
      |> concat(validate_property_or(data_graph, focus_node, value, property_shape, shape_map, depth))
      |> concat(validate_property_xone(data_graph, focus_node, value, property_shape, shape_map, depth))
      |> concat(validate_property_not(data_graph, focus_node, value, property_shape, shape_map, depth))
    end)
  end
end

# sh:and on PropertyShape - All shapes must conform for each value
defp validate_property_and(data_graph, focus_node, value, property_shape, shape_map, depth) do
  case property_shape.property_and do
    nil -> []
    [] -> []

    shape_refs ->
      # Validate value against each shape and collect violations
      all_violations =
        Enum.flat_map(shape_refs, fn shape_ref ->
          validate_value_against_shape(data_graph, value, shape_ref, shape_map, depth + 1)
        end)

      # If ANY shape failed, create AND violation for this value
      if length(all_violations) > 0 do
        [
          Helpers.build_property_violation(
            focus_node,
            value,
            property_shape,
            "AND constraint failed on property value: not all shapes conform",
            %{
              constraint_component: SHACL.and_constraint_component(),
              failing_shapes: count_failing_shapes_for_value(shape_refs, data_graph, value, shape_map, depth)
            }
          )
        ]
      else
        []
      end
  end
end

# sh:or on PropertyShape - At least one shape must conform for each value
defp validate_property_or(data_graph, focus_node, value, property_shape, shape_map, depth) do
  case property_shape.property_or do
    nil -> []
    [] -> []

    shape_refs ->
      # Check if ANY shape passes for this value
      any_passes? =
        Enum.any?(shape_refs, fn shape_ref ->
          results = validate_value_against_shape(data_graph, value, shape_ref, shape_map, depth + 1)
          length(results) == 0
        end)

      # If NO shape passed, create OR violation for this value
      if not any_passes? do
        [
          Helpers.build_property_violation(
            focus_node,
            value,
            property_shape,
            "OR constraint failed on property value: no shape conforms",
            %{
              constraint_component: SHACL.or_constraint_component(),
              tested_shapes: length(shape_refs)
            }
          )
        ]
      else
        []
      end
  end
end

# sh:xone on PropertyShape - Exactly one shape must conform for each value
defp validate_property_xone(data_graph, focus_node, value, property_shape, shape_map, depth) do
  case property_shape.property_xone do
    nil -> []
    [] -> []

    shape_refs ->
      # Count how many shapes pass for this value
      pass_count =
        Enum.count(shape_refs, fn shape_ref ->
          results = validate_value_against_shape(data_graph, value, shape_ref, shape_map, depth + 1)
          length(results) == 0
        end)

      # Must be exactly 1
      if pass_count != 1 do
        [
          Helpers.build_property_violation(
            focus_node,
            value,
            property_shape,
            "XONE constraint failed on property value: #{pass_count} shapes conform (expected exactly 1)",
            %{
              constraint_component: SHACL.xone_constraint_component(),
              conforming_count: pass_count,
              tested_shapes: length(shape_refs)
            }
          )
        ]
      else
        []
      end
  end
end

# sh:not on PropertyShape - Shape must NOT conform for each value
defp validate_property_not(data_graph, focus_node, value, property_shape, shape_map, depth) do
  case property_shape.property_not do
    nil -> []

    shape_ref ->
      results = validate_value_against_shape(data_graph, value, shape_ref, shape_map, depth + 1)

      # If shape passed (no violations), NOT fails
      if length(results) == 0 do
        [
          Helpers.build_property_violation(
            focus_node,
            value,
            property_shape,
            "NOT constraint failed on property value: negated shape conforms",
            %{
              constraint_component: SHACL.not_constraint_component(),
              negated_shape: shape_ref
            }
          )
        ]
      else
        # Shape failed as expected - negation succeeds
        []
      end
  end
end

# Validate a property value against a referenced shape
# This treats the VALUE as if it were a focus node
defp validate_value_against_shape(data_graph, value, shape_ref, shape_map, depth) do
  case Map.get(shape_map, shape_ref) do
    nil ->
      Logger.warning("Referenced shape not found in shape_map: #{inspect(shape_ref)}")
      []

    referenced_shape ->
      # Validate value as if it were a focus node against this shape
      validate_shape_constraints(data_graph, value, referenced_shape, shape_map, depth)
  end
end

# Helper: Get property values from data graph
defp get_property_values(data_graph, focus_node, path) do
  data_graph
  |> RDF.Graph.triples()
  |> Enum.filter(fn {s, p, _o} -> s == focus_node && p == path end)
  |> Enum.map(fn {_s, _p, o} -> o end)
end

# Helper: Count failing shapes for diagnostic info
defp count_failing_shapes_for_value(shape_refs, data_graph, value, shape_map, depth) do
  Enum.count(shape_refs, fn shape_ref ->
    results = validate_value_against_shape(data_graph, value, shape_ref, shape_map, depth + 1)
    length(results) > 0
  end)
end
```

**Key Points**:
- `validate_property/5` - Entry point for property-level validation
- Iterates over each value obtained via `sh:path`
- Validates each value independently against logical operators
- Reuses `validate_shape_constraints/4` (treats value as focus node)

---

### 4. Validator Orchestration Changes

#### File: `lib/elixir_ontologies/shacl/validator.ex`

**Update property validation to include logical operators:**

```elixir
defp validate_property_shape(data_graph, focus_node, property_shape, shape_map) do
  # Existing: Validate standard constraints
  standard_results =
    []
    |> concat(Validators.Cardinality.validate(data_graph, focus_node, property_shape))
    |> concat(Validators.Type.validate(data_graph, focus_node, property_shape))
    |> concat(Validators.String.validate(data_graph, focus_node, property_shape))
    |> concat(Validators.Value.validate(data_graph, focus_node, property_shape))
    |> concat(Validators.Qualified.validate(data_graph, focus_node, property_shape))

  # NEW: Validate property-level logical operators
  logical_results =
    Validators.LogicalOperators.validate_property(
      data_graph,
      focus_node,
      property_shape,
      shape_map
    )

  standard_results ++ logical_results
end
```

**Update `validate_focus_node/4` to pass shape_map:**

```elixir
defp validate_focus_node(data_graph, focus_node, node_shape, shape_map) do
  # Validate node-level constraints
  node_results = validate_node_constraints(data_graph, focus_node, node_shape, shape_map)

  # Validate property shapes (NOW WITH SHAPE_MAP)
  property_results =
    node_shape.property_shapes
    |> Enum.flat_map(fn property_shape ->
      validate_property_shape(data_graph, focus_node, property_shape, shape_map)
    end)

  # Validate SPARQL constraints
  sparql_results = Validators.SPARQL.validate(data_graph, focus_node, node_shape.sparql_constraints)

  node_results ++ property_results ++ sparql_results
end
```

---

### 5. Helper Module Changes

#### File: `lib/elixir_ontologies/shacl/validators/helpers.ex`

**Add helper for property violations:**

```elixir
@doc """
Build a ValidationResult for a property-level constraint violation.

Similar to build_node_violation but for property constraints.
"""
@spec build_property_violation(
        RDF.Term.t(),
        RDF.Term.t(),
        PropertyShape.t(),
        String.t(),
        map()
      ) :: ValidationResult.t()
def build_property_violation(focus_node, value, property_shape, message, metadata) do
  %ValidationResult{
    severity: :violation,
    focus_node: focus_node,
    value: value,
    result_path: property_shape.path,
    source_shape: property_shape.id,
    source_constraint_component: metadata.constraint_component,
    message: property_shape.message || message
  }
end
```

---

## Implementation Plan

### Step 1: Extend PropertyShape Data Model (1-2 hours)

**File**: `lib/elixir_ontologies/shacl/model/property_shape.ex`

- [ ] Add logical operator fields to PropertyShape struct
- [ ] Update `@type` spec with new fields
- [ ] Update moduledoc with property-level logical operator examples
- [ ] Add doctests showing property-level vs node-level usage

**Verification**:
```bash
mix compile
# Should compile without errors
```

---

### Step 2: Update Reader to Parse Property-Level Logical Operators (2-3 hours)

**File**: `lib/elixir_ontologies/shacl/reader.ex`

- [ ] Implement `parse_property_logical_operators/2` function
- [ ] Update `parse_property_shape/2` to call new function
- [ ] Reuse existing `parse_rdf_list/3` for sh:and, sh:or, sh:xone
- [ ] Reuse existing `get_single_object/3` for sh:not

**Verification**:
```elixir
# Create test fixture
cat > test/fixtures/property_logical_test.ttl << 'EOF'
@prefix ex: <http://example.org/> .
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

ex:TestShape
  a sh:NodeShape ;
  sh:targetClass ex:Thing ;
  sh:property [
    sh:path ex:value ;
    sh:xone (
      [ sh:datatype xsd:string ]
      [ sh:datatype xsd:integer ]
    )
  ] .
EOF

# Test parsing
iex -S mix
> {:ok, graph} = RDF.Turtle.read_file("test/fixtures/property_logical_test.ttl")
> {:ok, shapes} = ElixirOntologies.SHACL.Reader.parse_shapes(graph)
> property_shape = hd(hd(shapes).property_shapes)
> property_shape.property_xone
[~B<_:shape1>, ~B<_:shape2>]
```

---

### Step 3: Implement LogicalOperators.validate_property/5 (3-4 hours)

**File**: `lib/elixir_ontologies/shacl/validators/logical_operators.ex`

- [ ] Implement `validate_property/5` function
- [ ] Implement `validate_property_and/6` helper
- [ ] Implement `validate_property_or/6` helper
- [ ] Implement `validate_property_xone/6` helper
- [ ] Implement `validate_property_not/6` helper
- [ ] Implement `validate_value_against_shape/4` helper
- [ ] Implement `get_property_values/3` helper

**Verification**:
```elixir
test "validate_property with property_xone" do
  property_shape = %PropertyShape{
    id: ~B<_:prop1>,
    path: ~I<ex:value>,
    property_xone: [~B<_:s1>, ~B<_:s2>]
  }

  shape_map = %{
    ~B<_:s1> => %NodeShape{id: ~B<_:s1>, node_datatype: ~I<xsd:string>},
    ~B<_:s2> => %NodeShape{id: ~B<_:s2>, node_datatype: ~I<xsd:integer>}
  }

  # Valid: value is string only
  graph = RDF.Graph.new([{~I<ex:obj>, ~I<ex:value>, ~L"hello"}])
  assert [] = LogicalOperators.validate_property(graph, ~I<ex:obj>, property_shape, shape_map)

  # Invalid: value is neither (literal without datatype)
  graph2 = RDF.Graph.new([{~I<ex:obj>, ~I<ex:value>, ~L"hello"}])
  assert [%ValidationResult{}] = LogicalOperators.validate_property(graph2, ~I<ex:obj>, property_shape, shape_map)
end
```

---

### Step 4: Update Validator Orchestration (1-2 hours)

**File**: `lib/elixir_ontologies/shacl/validator.ex`

- [ ] Update `validate_property_shape/4` signature to accept shape_map
- [ ] Add LogicalOperators.validate_property call
- [ ] Update `validate_focus_node/4` to pass shape_map to property validation

**Verification**:
```bash
mix test test/elixir_ontologies/shacl/validator_test.exs
# Existing tests should still pass
```

---

### Step 5: Add Helpers Module Support (1 hour)

**File**: `lib/elixir_ontologies/shacl/validators/helpers.ex`

- [ ] Implement `build_property_violation/5` function
- [ ] Ensure consistent violation structure

**Verification**:
```elixir
test "build_property_violation creates correct structure" do
  property_shape = %PropertyShape{id: ~B<_:p1>, path: ~I<ex:prop>}

  result = Helpers.build_property_violation(
    ~I<ex:node>,
    ~L"value",
    property_shape,
    "Test message",
    %{constraint_component: SHACL.xone_constraint_component()}
  )

  assert result.focus_node == ~I<ex:node>
  assert result.value == ~L"value"
  assert result.result_path == ~I<ex:prop>
  assert result.source_shape == ~B<_:p1>
end
```

---

### Step 6: W3C Test Analysis and Edge Cases (2-3 hours)

**Current Failing Test**: `xone-duplicate`

**Action Items**:
- [ ] Re-analyze xone-duplicate test to confirm if it's truly property-level or node-level edge case
- [ ] If node-level: Fix duplicate shape handling in node-level validator
- [ ] If property-level: Ensure new implementation handles it
- [ ] Test with other logical operator combinations

**Investigation**:
```bash
# Run xone-duplicate test in isolation
mix test test/elixir_ontologies/w3c_test.exs --only xone_duplicate

# Analyze test output
# Expected: 2 violations (ex:i and ex:j)
# Actual: Currently passes (incorrect)
```

---

### Step 7: Unit Tests for Property-Level Logical Operators (3-4 hours)

**New Test File**: `test/elixir_ontologies/shacl/validators/logical_operators_property_test.exs`

**Test Coverage**:

```elixir
defmodule ElixirOntologies.SHACL.Validators.LogicalOperatorsPropertyTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.SHACL.Validators.LogicalOperators
  alias ElixirOntologies.SHACL.Model.{PropertyShape, NodeShape}

  describe "validate_property/5 with property_and" do
    test "all shapes conform - passes" do
      # Test implementation
    end

    test "one shape fails - violation" do
      # Test implementation
    end
  end

  describe "validate_property/5 with property_or" do
    test "at least one shape conforms - passes" do
      # Test implementation
    end

    test "no shapes conform - violation" do
      # Test implementation
    end
  end

  describe "validate_property/5 with property_xone" do
    test "exactly one shape conforms - passes" do
      # Test implementation
    end

    test "zero shapes conform - violation" do
      # Test implementation
    end

    test "two shapes conform - violation" do
      # Test implementation
    end
  end

  describe "validate_property/5 with property_not" do
    test "shape does not conform - passes" do
      # Test implementation
    end

    test "shape conforms - violation" do
      # Test implementation
    end
  end

  describe "validate_property/5 with multiple values" do
    test "validates each value independently" do
      # Test implementation
    end
  end
end
```

---

### Step 8: Integration Testing and Debugging (2-3 hours)

- [ ] Run full W3C test suite: `mix test test/elixir_ontologies/w3c_test.exs`
- [ ] Verify xone-duplicate test passes (if it's property-level)
- [ ] Check for any regressions in existing tests
- [ ] Test with complex nested logical operators

**Target**:
- W3C pass rate: 64.2% → 66% (if xone-duplicate is property-level)
- Or: Identify and fix actual issue with xone-duplicate (if node-level edge case)

---

### Step 9: Documentation and Examples (2-3 hours)

- [ ] Update PropertyShape moduledoc with logical operator examples
- [ ] Update LogicalOperators moduledoc with property-level examples
- [ ] Add doctests demonstrating property vs node level usage
- [ ] Update CHANGELOG.md with Phase 11.6.2 changes

**Documentation Additions**:

```elixir
# PropertyShape moduledoc example
"""
## Property-Level Logical Operators

Logical operators can be applied to property values:

    ex:TestShape
      a sh:NodeShape ;
      sh:targetClass ex:Thing ;
      sh:property [
        sh:path ex:mixedValue ;
        sh:xone (                    # Each value must conform to exactly one
          [ sh:datatype xsd:string ]
          [ sh:datatype xsd:integer ]
        )
      ] .

This validates: "For each value of ex:mixedValue, does it conform to exactly
one of the datatypes (string XOR integer)?"

Example:
- ex:obj1 ex:mixedValue "hello" .     # Valid: string only
- ex:obj2 ex:mixedValue 42 .          # Valid: integer only
- ex:obj3 ex:mixedValue "hello", 42 . # Invalid: each value passes, but different types
"""
```

---

### Step 10: Performance Testing and Optimization (1-2 hours)

- [ ] Benchmark property-level logical validation
- [ ] Ensure no performance regression
- [ ] Profile with `:fprof` if needed
- [ ] Optimize recursive validation if necessary

**Performance Expectations**:
- Minimal overhead for properties without logical operators
- Reasonable performance for nested logical operators (< 20% overhead)

---

## Success Criteria

Phase 11.6.2 is complete when:

### Implementation Complete (Required)

- ✅ PropertyShape extended with logical operator fields
- ✅ Reader parses property-level logical operators
- ✅ LogicalOperators.validate_property/5 implemented
- ✅ Validator orchestration updated to call property-level validation
- ✅ Helpers.build_property_violation/5 implemented

### Test Coverage (Required)

- ✅ Unit tests for all four property-level operators (and, or, xone, not)
- ✅ Integration tests for nested property-level operators
- ✅ Edge case tests for multiple values per property
- ✅ Regression tests pass (no existing test failures)

### W3C Test Suite (Target)

- ✅ xone-duplicate test analyzed and resolved (either as property-level or node-level edge case)
- ✅ W3C pass rate >= 64.2% (no regressions)
- ✅ If xone-duplicate is property-level: pass rate increases to 66%

### Code Quality (Required)

- ✅ Zero compiler warnings
- ✅ All doctests pass
- ✅ Comprehensive moduledoc with examples
- ✅ CHANGELOG.md updated

### Documentation (Required)

- ✅ PropertyShape moduledoc explains property-level vs node-level
- ✅ LogicalOperators moduledoc covers both validation modes
- ✅ Examples demonstrate real-world use cases

---

## Testing Strategy

### 1. Unit Tests

**Focus**: Individual property-level logical operator functions

```elixir
# Test property_xone with datatype alternatives
test "property_xone validates each value independently" do
  property_shape = %PropertyShape{
    id: ~B<_:prop>,
    path: ~I<ex:value>,
    property_xone: [~B<_:s1>, ~B<_:s2>]
  }

  shape_map = %{
    ~B<_:s1> => %NodeShape{id: ~B<_:s1>, node_datatype: ~I<xsd:string>},
    ~B<_:s2> => %NodeShape{id: ~B<_:s2>, node_datatype: ~I<xsd:integer>}
  }

  # Object with two values: one string, one integer
  # Each value should pass (each conforms to exactly one shape)
  graph = RDF.Graph.new([
    {~I<ex:obj>, ~I<ex:value>, ~L"hello"^^xsd:string},
    {~I<ex:obj>, ~I<ex:value>, ~L"42"^^xsd:integer}
  ])

  results = LogicalOperators.validate_property(graph, ~I<ex:obj>, property_shape, shape_map)
  assert results == []
end
```

### 2. Integration Tests

**Focus**: End-to-end validation with real SHACL shapes

```bash
mix test test/elixir_ontologies/w3c_test.exs
mix test test/elixir_ontologies/shacl/validators/logical_operators_test.exs
```

### 3. Edge Case Tests

**Test Scenarios**:
- Multiple values per property (each validated independently)
- Nested logical operators (and within xone, etc.)
- Empty property values (no values)
- Circular shape references (should detect via recursion limit)
- Duplicate shape references (like xone-duplicate test)

---

## Risk Assessment

### Risk 1: xone-duplicate is Actually Node-Level Edge Case

**Impact**: Medium
**Likelihood**: High (based on test analysis)
**Mitigation**:
- Analyze test carefully before implementation
- If node-level: Fix in Phase 11.6.1 codebase instead
- If property-level: Proceed with implementation

**Fallback**: Implement both node-level duplicate handling AND property-level operators

---

### Risk 2: Shape Map Not Available in Property Validation

**Impact**: Medium
**Likelihood**: Low (already passed in validator orchestration)
**Mitigation**:
- Update all property validation signatures to accept shape_map
- Verify shape_map is populated correctly

**Fallback**: Pass shape_map through existing validator structure

---

### Risk 3: Performance Impact of Recursive Validation

**Impact**: Low
**Likelihood**: Low
**Mitigation**:
- Reuse existing recursion depth limit (@max_recursion_depth = 50)
- Benchmark before/after
- Early return for properties without logical operators

**Monitoring**: Profile with `:fprof` if performance degrades

---

### Risk 4: Breaking Changes to PropertyShape

**Impact**: Low
**Likelihood**: Very Low
**Mitigation**:
- All new fields default to nil
- Backward compatible extension
- Existing property validation unaffected

---

## Future Enhancements (Out of Scope)

### Phase 11.6.3: Advanced Property Paths

- sh:alternativePath
- sh:inversePath
- sh:zeroOrMorePath
- sh:oneOrMorePath

### Phase 11.6.4: Property Pair Constraints with Logical Operators

- Combining sh:equals with logical operators
- sh:lessThan with complex conditions

---

## Estimated Effort

| Step | Description | Hours |
|------|-------------|-------|
| 1 | Extend PropertyShape model | 1-2 |
| 2 | Update Reader parsing | 2-3 |
| 3 | Implement LogicalOperators.validate_property | 3-4 |
| 4 | Update Validator orchestration | 1-2 |
| 5 | Add Helpers support | 1 |
| 6 | W3C test analysis and edge cases | 2-3 |
| 7 | Unit tests | 3-4 |
| 8 | Integration testing and debugging | 2-3 |
| 9 | Documentation and examples | 2-3 |
| 10 | Performance testing | 1-2 |
| **Total** | | **18-27 hours** |

**Realistic Timeline**: 3-4 working days (assuming 8-hour days)

---

## Appendix: Property-Level vs Node-Level Examples

### Example 1: Node-Level sh:xone (Working - Phase 11.6.1)

```turtle
# Shape
ex:PersonShape
  rdf:type sh:NodeShape ;
  sh:targetClass ex:Person ;
  sh:xone (
    [ sh:property [ sh:path ex:fullName ; sh:minCount 1 ] ]
    [ sh:property [ sh:path ex:firstName ; sh:minCount 1 ]
      sh:property [ sh:path ex:lastName ; sh:minCount 1 ] ]
  ) .

# Data
ex:Bob a ex:Person ;
  ex:firstName "Robert" ;
  ex:lastName "Coin" .

# Validation: Focus node ex:Bob must conform to exactly one of the two shapes
# Result: ex:Bob has firstName+lastName → conforms to second shape only → PASS
```

### Example 2: Property-Level sh:xone (Target - Phase 11.6.2)

```turtle
# Shape
ex:TestShape
  rdf:type sh:NodeShape ;
  sh:targetClass ex:Thing ;
  sh:property [
    sh:path ex:value ;
    sh:xone (
      [ sh:datatype xsd:string ]
      [ sh:datatype xsd:integer ]
    )
  ] .

# Data
ex:obj1 a ex:Thing ;
  ex:value "hello" .         # Valid: string only

ex:obj2 a ex:Thing ;
  ex:value 42 .              # Valid: integer only

ex:obj3 a ex:Thing ;
  ex:value "hello" ;         # Valid: each value independently valid
  ex:value 42 .

# Validation: Each VALUE of ex:value must conform to exactly one datatype
# Result:
# - ex:obj1: "hello" is string → conforms to first shape only → PASS
# - ex:obj2: 42 is integer → conforms to second shape only → PASS
# - ex:obj3: "hello" is string (pass), 42 is integer (pass) → PASS
```

### Example 3: xone-duplicate Test (Node-Level Edge Case)

```turtle
# Shape
ex:s1 a sh:NodeShape ;
  sh:targetClass ex:C1 ;
  sh:xone ( ex:s2 ex:s2 ) .    # DUPLICATE shape reference!
ex:s2 sh:class ex:C2 .

# Data
ex:i a ex:C1 .                 # Instance of C1 only
ex:j a ex:C1 , ex:C2 .         # Instance of both C1 and C2

# Validation (Node-Level):
# ex:i: Focus node is NOT instance of C2
#   - First ex:s2: FAIL (not C2)
#   - Second ex:s2: FAIL (not C2)
#   - Pass count: 0 (need exactly 1) → VIOLATION ✓
#
# ex:j: Focus node IS instance of C2
#   - First ex:s2: PASS (is C2)
#   - Second ex:s2: PASS (is C2)
#   - Pass count: 2 (need exactly 1) → VIOLATION ✓
```

---

## Summary

Phase 11.6.2 implements **property-level logical operators** to complete the logical operators feature started in Phase 11.6.1. This enables validation of property values against logical combinations of shapes.

**Key Changes**:
1. Extend PropertyShape with logical operator fields
2. Update Reader to parse property-level operators
3. Implement LogicalOperators.validate_property/5
4. Update Validator orchestration

**Impact**:
- Complete SHACL logical operators specification compliance
- Architectural symmetry (node-level + property-level)
- Foundation for complex property value validation
- Minimal breaking changes

**Timeline**: 18-27 hours (3-4 days)

**Dependencies**: Phase 11.6.1 (Node-Level Logical Operators) must be complete

---

**End of Planning Document**
