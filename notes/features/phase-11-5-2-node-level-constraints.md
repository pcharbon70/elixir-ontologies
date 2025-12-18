# Phase 11.5.2: Node-Level Constraints

**Date**: 2025-12-13
**Status**: Planning
**Context**: Phase 11.5.1 W3C Test Suite integration revealed 22 failing tests (43% of failures)
**Goal**: Increase W3C test pass rate from 18% (9/51) to 61% (31/51) by implementing node-level constraints

---

## 1. Problem Statement

### Current Situation

Our SHACL implementation currently achieves **18% pass rate** (9/51 tests) on the W3C SHACL test suite. Analysis of the 42 failing tests reveals:

- **22 tests (43% of failures)** fail because they apply constraints directly to NodeShapes
- **20 tests (39% of failures)** fail for other reasons (unimplemented features, path expressions, etc.)

### The Gap: Node-Level vs Property-Level Constraints

**What we support (Property-Level Constraints):**

```turtle
ex:PersonShape
  rdf:type sh:NodeShape ;
  sh:property [
    sh:path ex:age ;           # Constrains VALUES of ex:age property
    sh:datatype xsd:integer ;  # Values must be integers
    sh:minInclusive 0 ;        # Values must be >= 0
  ] .
```

**What we don't support (Node-Level Constraints):**

```turtle
ex:TestShape
  rdf:type sh:NodeShape ;
  sh:datatype xsd:integer ;    # Constraint on FOCUS NODE itself (not a property)
  sh:minInclusive 0 ;          # Focus node must be >= 0
  sh:targetNode 42 .           # Target: the integer 42
```

### Impact on Test Results

From our test run:
```
Finished in 0.5 seconds (0.5s async, 0.00s sync)
53 tests, 46 failures

Tests failing due to node-level constraints:
- datatype_001, datatype_002      (sh:datatype on NodeShape)
- class_001, class_002, class_003 (sh:class on NodeShape)
- in_001                          (sh:in on NodeShape)
- pattern_001, pattern_002        (sh:pattern on NodeShape)
- minLength_001, maxLength_001    (string constraints on NodeShape)
- minInclusive_001-003            (numeric constraints on NodeShape)
- hasValue_001                    (sh:hasValue on NodeShape)
- nodeKind_001                    (sh:nodeKind on NodeShape)
- languageIn_001                  (sh:languageIn on NodeShape)
- equals_001, disjoint_001        (comparison constraints on NodeShape)
- node_001                        (sh:node on NodeShape)
... and 5 more
```

### Why This Matters

1. **Specification Compliance**: Node-level constraints are part of core SHACL spec
2. **Test Coverage**: Fixing this unlocks 22 additional passing tests (+43% pass rate)
3. **Real-World Use Cases**: Validating literal values directly (e.g., "is this a valid integer?")
4. **Foundation**: Required before implementing logical operators (sh:and, sh:or, sh:not)

---

## 2. Solution Overview

### High-Level Approach

Instead of treating NodeShapes as containers for PropertyShapes only, we need to:

1. **Parse node-level constraints** from NodeShapes (same constraints as PropertyShapes)
2. **Store node-level constraints** in NodeShape struct (new field)
3. **Validate focus nodes directly** against node-level constraints (treat node as its own value)

### Conceptual Model

**Current Model** (Property-Level Only):
```
NodeShape
  └─ PropertyShapes[]
       └─ Constraints (datatype, minCount, pattern, etc.)
            └─ Applied to: VALUES of property

Validation Flow:
  Focus Node → Property → Values → Validate Each Value
```

**New Model** (Node-Level + Property-Level):
```
NodeShape
  ├─ Node-Level Constraints (datatype, class, in, pattern, etc.)
  │    └─ Applied to: FOCUS NODE itself
  └─ PropertyShapes[]
       └─ Constraints (datatype, minCount, pattern, etc.)
            └─ Applied to: VALUES of property

Validation Flow:
  Focus Node → [1] Validate Node Itself
             → [2] Validate Properties → Values
```

### Key Insight: Constraint Reuse

Node-level constraints use the **same constraint types** as property-level constraints:
- `sh:datatype` - Focus node must have this datatype
- `sh:class` - Focus node must be instance of this class
- `sh:in` - Focus node must be in this enumeration
- `sh:pattern` - Focus node (as string) must match pattern
- `sh:minInclusive`, `sh:maxInclusive` - Numeric range constraints
- etc.

The **validation logic is identical**, only the **value being validated differs**:
- Property-level: Validate each value at `focusNode → property → value`
- Node-level: Validate `focusNode` itself (as if it were a value)

---

## 3. Agent Consultations Performed

### 3.1. Research Agent: SHACL Specification Analysis

**Question**: What does the SHACL specification say about node-level constraints vs property-level constraints?

**Research Findings**:

**SHACL 1.0 Specification - Section 2.1 (Shapes)**

> "Constraints may be specified on a shape. For node shapes, the constraints apply to each focus node directly. For property shapes, the constraints apply to each value node."

**Section 2.1.1 (Node Shapes)**

> "Node shapes are shapes in the shapes graph that are not the subject of a sh:path triple. All constraint components specified on a node shape apply to the focus node directly."

**Section 2.1.2 (Property Shapes)**

> "Property shapes are shapes in the shapes graph that are the subject of a sh:path triple. All constraint components specified on a property shape apply to the value nodes of the focus node for the given property."

**Key Constraints Applicable to Both:**

From SHACL Core Constraint Components (Section 4):
- **Value Type Constraints** (4.1): `sh:class`, `sh:datatype`, `sh:nodeKind`
- **Cardinality Constraints** (4.2): `sh:minCount`, `sh:maxCount` (property-only)
- **Value Range Constraints** (4.3): `sh:minInclusive`, `sh:maxInclusive`, `sh:minExclusive`, `sh:maxExclusive`
- **String-based Constraints** (4.4): `sh:minLength`, `sh:maxLength`, `sh:pattern`, `sh:languageIn`, `sh:uniqueLang`
- **Property Pair Constraints** (4.5): `sh:equals`, `sh:disjoint`, `sh:lessThan`, `sh:lessThanOrEquals`
- **Logical Constraints** (4.6): `sh:and`, `sh:or`, `sh:xone`, `sh:not`
- **Shape-based Constraints** (4.7): `sh:node`, `sh:qualifiedValueShape`
- **Other Constraints** (4.8): `sh:closed`, `sh:hasValue`, `sh:in`

**Property-Only Constraints:**
- `sh:minCount`, `sh:maxCount` - Only meaningful for properties (count values)
- `sh:uniqueLang` - Only for properties with multiple values
- `sh:equals`, `sh:disjoint`, `sh:lessThan` - Require two properties to compare

**Validation Algorithm** (Section 3.4):

```
For each focus node F:
  1. Validate F against all node-level constraints (F is the "value node")
  2. For each property shape P with path PT:
     a. Select all value nodes V where (F, PT, V) in data graph
     b. Validate each V against property-level constraints
```

**Example from Spec** (Section 2.1.1):

```turtle
ex:IntegerShape
  a sh:NodeShape ;
  sh:targetNode 42 ;
  sh:datatype xsd:integer ;     # Node-level constraint
  sh:minInclusive 0 .           # Node-level constraint

# Validates: Is 42 an integer >= 0?
# Answer: Yes (conforms)
```

**Summary**:
- Node-level constraints validate the **focus node itself**
- Property-level constraints validate **values of properties**
- Most constraints work on both levels (except cardinality/comparison)
- Validation logic is identical, only the "value" being validated differs

---

### 3.2. Elixir Expert: Data Structure Design

**Question**: How should we structure the NodeShape to hold direct constraints while maintaining compatibility with our existing validator architecture?

**Recommendations**:

#### Option A: Separate Constraint Fields (Recommended)

Add specific fields to `NodeShape` for each constraint type:

```elixir
defmodule ElixirOntologies.SHACL.Model.NodeShape do
  @enforce_keys [:id]
  defstruct [
    :id,
    target_classes: [],
    implicit_class_target: nil,

    # Existing property-level constraints
    property_shapes: [],
    sparql_constraints: [],

    # NEW: Node-level constraints (applied to focus node itself)
    # Value Type Constraints
    datatype: nil,              # RDF.IRI.t() | nil
    class: nil,                 # RDF.IRI.t() | nil
    node_kind: nil,             # :iri | :blank_node | :literal | nil

    # Value Range Constraints
    min_inclusive: nil,         # number | nil
    max_inclusive: nil,         # number | nil
    min_exclusive: nil,         # number | nil
    max_exclusive: nil,         # number | nil

    # String Constraints
    min_length: nil,            # non_neg_integer() | nil
    max_length: nil,            # non_neg_integer() | nil
    pattern: nil,               # String.t() | nil
    pattern_flags: nil,         # String.t() | nil
    language_in: [],            # [String.t()]

    # Value Constraints
    in: [],                     # [RDF.Term.t()]
    has_value: nil,             # RDF.Term.t() | nil

    # Shape-based Constraints
    node: [],                   # [RDF.IRI.t()] (references to other shapes)

    # Logical Constraints
    and: [],                    # [RDF.IRI.t()] (references to other shapes)
    or: [],                     # [RDF.IRI.t()] (references to other shapes)
    xone: [],                   # [RDF.IRI.t()] (references to other shapes)
    not: [],                    # [RDF.IRI.t()] (references to other shapes)

    # Other Constraints
    closed: false,              # boolean()
    ignored_properties: []      # [RDF.IRI.t()]
  ]
end
```

**Pros**:
- Explicit, self-documenting structure
- Easy to pattern match in validators
- No overhead for shapes without node constraints
- Clear separation of concerns

**Cons**:
- Many new fields (verbose struct)
- Duplication with PropertyShape fields

#### Option B: Nested NodeConstraints Struct

Create a separate struct for node-level constraints:

```elixir
defmodule ElixirOntologies.SHACL.Model.NodeConstraints do
  defstruct [
    datatype: nil,
    class: nil,
    node_kind: nil,
    min_inclusive: nil,
    max_inclusive: nil,
    # ... all constraint fields
  ]
end

defmodule ElixirOntologies.SHACL.Model.NodeShape do
  defstruct [
    :id,
    target_classes: [],
    implicit_class_target: nil,
    property_shapes: [],
    sparql_constraints: [],
    node_constraints: %NodeConstraints{}  # NEW
  ]
end
```

**Pros**:
- Cleaner NodeShape struct
- Constraints grouped logically
- Easy to check if any node constraints exist

**Cons**:
- Extra layer of nesting
- Harder to pattern match

#### Option C: Shared Constraint Module

Extract shared constraint logic into a common module:

```elixir
defmodule ElixirOntologies.SHACL.Model.Constraints do
  defstruct [
    datatype: nil,
    class: nil,
    # ... all constraints
  ]
end

# NodeShape has node-level constraints
defmodule NodeShape do
  defstruct [
    :id,
    constraints: %Constraints{},  # Applied to focus node
    property_shapes: []
  ]
end

# PropertyShape has property-level constraints
defmodule PropertyShape do
  defstruct [
    :id,
    :path,
    constraints: %Constraints{}  # Applied to property values
  ]
end
```

**Pros**:
- DRY principle (no duplication)
- Same validation logic works for both
- Clear symmetry

**Cons**:
- Breaking change to existing PropertyShape
- Migration effort for existing code

**Recommendation**: **Option A** (Separate Constraint Fields)
- Minimal breaking changes (only NodeShape affected)
- Clear, explicit structure
- Pattern matching is straightforward
- We can refactor to Option C later if needed

---

### 3.3. Senior Engineer Reviewer: Architecture & Validation Flow

**Question**: What is the optimal architectural approach for integrating node-level constraint validation into our existing validator?

**Architectural Assessment**:

#### Current Validator Flow

```elixir
Validator.run(data_graph, shapes_graph)
  ├─ Reader.parse_shapes(shapes_graph) → [NodeShape]
  ├─ For each NodeShape:
  │   ├─ select_target_nodes() → [focus_node]
  │   └─ For each focus_node:
  │       └─ validate_focus_node()
  │           └─ For each PropertyShape:
  │               └─ validate_property_shape()
  │                   ├─ Validators.Cardinality.validate()
  │                   ├─ Validators.Type.validate()
  │                   ├─ Validators.String.validate()
  │                   ├─ Validators.Value.validate()
  │                   └─ Validators.Qualified.validate()
  └─ Aggregate results → ValidationReport
```

#### Proposed Enhanced Flow

```elixir
Validator.run(data_graph, shapes_graph)
  ├─ Reader.parse_shapes(shapes_graph) → [NodeShape with node constraints]
  ├─ For each NodeShape:
  │   ├─ select_target_nodes() → [focus_node]
  │   └─ For each focus_node:
  │       ├─ validate_node_constraints(focus_node, node_shape)  ← NEW
  │       │   ├─ Validators.Type.validate_node()
  │       │   ├─ Validators.String.validate_node()
  │       │   ├─ Validators.Value.validate_node()
  │       │   └─ etc.
  │       └─ validate_focus_node() (existing property validation)
  │           └─ For each PropertyShape: ...
  └─ Aggregate results → ValidationReport
```

#### Key Architectural Decisions

**Decision 1: Validator Module Extension**

Add new function to `Validator` module:

```elixir
# lib/elixir_ontologies/shacl/validator.ex

defp validate_focus_node(data_graph, focus_node, node_shape) do
  # NEW: Validate node-level constraints (focus node as value)
  node_results = validate_node_constraints(data_graph, focus_node, node_shape)

  # Existing: Validate property shapes
  property_results =
    node_shape.property_shapes
    |> Enum.flat_map(fn property_shape ->
      validate_property_shape(data_graph, focus_node, property_shape)
    end)

  # Existing: Validate SPARQL constraints
  sparql_results = Validators.SPARQL.validate(...)

  node_results ++ property_results ++ sparql_results
end

# NEW: Validate focus node against node-level constraints
defp validate_node_constraints(data_graph, focus_node, node_shape) do
  []
  |> concat(Validators.Type.validate_node(data_graph, focus_node, node_shape))
  |> concat(Validators.String.validate_node(data_graph, focus_node, node_shape))
  |> concat(Validators.Value.validate_node(data_graph, focus_node, node_shape))
  # ... more validators
end
```

**Decision 2: Validator Interface Standardization**

Each validator module should have two interfaces:

```elixir
defmodule ElixirOntologies.SHACL.Validators.Type do
  # Existing: Validate property values
  @spec validate(RDF.Graph.t(), RDF.Term.t(), PropertyShape.t()) ::
    [ValidationResult.t()]
  def validate(data_graph, focus_node, property_shape) do
    # Get values for property
    values = get_property_values(data_graph, focus_node, property_shape.path)

    # Validate each value
    Enum.flat_map(values, fn value ->
      validate_value(value, property_shape, focus_node)
    end)
  end

  # NEW: Validate focus node directly
  @spec validate_node(RDF.Graph.t(), RDF.Term.t(), NodeShape.t()) ::
    [ValidationResult.t()]
  def validate_node(data_graph, focus_node, node_shape) do
    # Validate focus_node as if it were a value
    validate_value(focus_node, node_shape, focus_node)
  end

  # SHARED: Core validation logic (works for both)
  defp validate_value(value, constraints, focus_node) do
    # constraints could be PropertyShape or NodeShape
    # Both have .datatype, .class, .node_kind fields

    # Check datatype constraint
    if constraints.datatype && !matches_datatype?(value, constraints.datatype) do
      [create_violation(focus_node, value, :datatype, constraints)]
    else
      []
    end
  end
end
```

**Key Points**:
- `validate/3` - Property-level (iterates over values)
- `validate_node/3` - Node-level (treats focus node as value)
- `validate_value/3` - Shared logic (works for both)

**Decision 3: Minimal Breaking Changes**

- ✅ Keep existing `PropertyShape` unchanged
- ✅ Only modify `NodeShape` (add constraint fields)
- ✅ Add new `validate_node/3` functions (existing functions unchanged)
- ✅ Reader changes isolated to node shape parsing
- ✅ Existing tests continue to pass

**Decision 4: Constraint Component Identification**

For validation results, we need to identify which constraint component failed:

```elixir
# Node-level constraint violation
%ValidationResult{
  focus_node: ~L"42",
  value: ~L"42",  # Same as focus_node for node constraints
  source_constraint_component: SHACL.datatype_constraint_component(),
  source_shape: ~I<ex:TestShape>,
  result_path: nil  # No path for node-level constraints
}

# Property-level constraint violation
%ValidationResult{
  focus_node: ~I<ex:Person1>,
  value: ~L"invalid",
  source_constraint_component: SHACL.datatype_constraint_component(),
  source_shape: ~I<ex:TestShape>,
  result_path: ~I<ex:age>  # Path present for property constraints
}
```

**Key**: `result_path` differentiates node vs property violations

#### Testing Strategy

1. **Unit Tests** - Each validator's `validate_node/3` function
   ```elixir
   test "Type.validate_node with sh:datatype on NodeShape" do
     node_shape = %NodeShape{
       id: ~I<ex:TestShape>,
       datatype: ~I<http://www.w3.org/2001/XMLSchema#integer>
     }

     # Valid: Integer literal
     assert [] = Validators.Type.validate_node(graph, ~L"42"^^xsd:integer, node_shape)

     # Invalid: String literal
     assert [%ValidationResult{} | _] =
       Validators.Type.validate_node(graph, ~L"hello", node_shape)
   end
   ```

2. **Integration Tests** - Full W3C test cases
   ```bash
   # Should pass after implementation
   mix test --only w3c_core:datatype
   mix test --only w3c_core:class
   mix test --only w3c_core:in
   ```

3. **Regression Tests** - Ensure existing property-level validation still works
   ```bash
   # Should still pass
   mix test test/elixir_ontologies/shacl_test.exs
   ```

#### Performance Considerations

- **Minimal overhead**: Only validate node constraints if any exist
- **Early return**: Skip node validation if all constraint fields are nil/empty
- **Parallel execution**: Node and property validation can be concurrent (future)

```elixir
defp validate_node_constraints(data_graph, focus_node, node_shape) do
  # Early return if no node constraints
  if has_node_constraints?(node_shape) do
    # Perform validation
  else
    []
  end
end

defp has_node_constraints?(node_shape) do
  node_shape.datatype != nil ||
  node_shape.class != nil ||
  node_shape.in != [] ||
  # ... check other constraint fields
end
```

**Recommendation**: Proceed with described architecture
- Minimal changes to existing code
- Clear separation of node vs property validation
- Reuses existing constraint validation logic
- Testable at multiple levels
- Performance-conscious design

---

## 4. Technical Details

### 4.1. Data Model Changes

#### File: `lib/elixir_ontologies/shacl/model/node_shape.ex`

**Before**:
```elixir
defmodule ElixirOntologies.SHACL.Model.NodeShape do
  @enforce_keys [:id]
  defstruct [
    :id,
    target_classes: [],
    implicit_class_target: nil,
    property_shapes: [],
    sparql_constraints: []
  ]
end
```

**After**:
```elixir
defmodule ElixirOntologies.SHACL.Model.NodeShape do
  @enforce_keys [:id]
  defstruct [
    :id,
    target_classes: [],
    implicit_class_target: nil,
    property_shapes: [],
    sparql_constraints: [],

    # Node-level Value Type Constraints
    datatype: nil,              # RDF.IRI.t() | nil - sh:datatype
    class: nil,                 # RDF.IRI.t() | nil - sh:class
    node_kind: nil,             # atom() | nil - sh:nodeKind

    # Node-level Value Range Constraints
    min_inclusive: nil,         # number() | nil - sh:minInclusive
    max_inclusive: nil,         # number() | nil - sh:maxInclusive
    min_exclusive: nil,         # number() | nil - sh:minExclusive
    max_exclusive: nil,         # number() | nil - sh:maxExclusive

    # Node-level String Constraints
    min_length: nil,            # non_neg_integer() | nil - sh:minLength
    max_length: nil,            # non_neg_integer() | nil - sh:maxLength
    pattern: nil,               # Regex.t() | nil - sh:pattern
    flags: nil,                 # String.t() | nil - sh:flags
    language_in: [],            # [String.t()] - sh:languageIn

    # Node-level Value Constraints
    in: [],                     # [RDF.Term.t()] - sh:in
    has_value: nil,             # RDF.Term.t() | nil - sh:hasValue

    # Node-level Shape-based Constraints
    node: [],                   # [RDF.IRI.t()] - sh:node

    # Node-level Logical Constraints
    and: [],                    # [RDF.IRI.t()] - sh:and
    or: [],                     # [RDF.IRI.t()] - sh:or
    xone: [],                   # [RDF.IRI.t()] - sh:xone
    not: [],                    # [RDF.IRI.t()] - sh:not

    # Node-level Other Constraints
    closed: false,              # boolean() - sh:closed
    ignored_properties: [],     # [RDF.IRI.t()] - sh:ignoredProperties
    equals: nil,                # RDF.IRI.t() | nil - sh:equals
    disjoint: nil               # RDF.IRI.t() | nil - sh:disjoint
  ]

  @type t :: %__MODULE__{
    id: RDF.IRI.t() | RDF.BlankNode.t(),
    target_classes: [RDF.IRI.t()],
    implicit_class_target: RDF.IRI.t() | nil,
    property_shapes: [PropertyShape.t()],
    sparql_constraints: [SPARQLConstraint.t()],

    # Node-level constraints
    datatype: RDF.IRI.t() | nil,
    class: RDF.IRI.t() | nil,
    node_kind: atom() | nil,
    min_inclusive: number() | nil,
    max_inclusive: number() | nil,
    min_exclusive: number() | nil,
    max_exclusive: number() | nil,
    min_length: non_neg_integer() | nil,
    max_length: non_neg_integer() | nil,
    pattern: Regex.t() | nil,
    flags: String.t() | nil,
    language_in: [String.t()],
    in: [RDF.Term.t()],
    has_value: RDF.Term.t() | nil,
    node: [RDF.IRI.t()],
    and: [RDF.IRI.t()],
    or: [RDF.IRI.t()],
    xone: [RDF.IRI.t()],
    not: [RDF.IRI.t()],
    closed: boolean(),
    ignored_properties: [RDF.IRI.t()],
    equals: RDF.IRI.t() | nil,
    disjoint: RDF.IRI.t() | nil
  }
end
```

### 4.2. Reader Changes

#### File: `lib/elixir_ontologies/shacl/reader.ex`

Add node-level constraint parsing to `parse_node_shape/2` function:

```elixir
defp parse_node_shape(graph, shape_iri) do
  with {:ok, target_classes} <- parse_target_classes(graph, shape_iri),
       {:ok, implicit_class_target} <- detect_implicit_class_target(graph, shape_iri),
       {:ok, property_shapes} <- parse_property_shapes(graph, shape_iri),
       {:ok, sparql_constraints} <- parse_sparql_constraints(graph, shape_iri),
       # NEW: Parse node-level constraints
       {:ok, node_constraints} <- parse_node_constraints(graph, shape_iri) do

    {:ok, %NodeShape{
      id: shape_iri,
      target_classes: target_classes,
      implicit_class_target: implicit_class_target,
      property_shapes: property_shapes,
      sparql_constraints: sparql_constraints,
      # Merge node constraints into struct
      datatype: node_constraints.datatype,
      class: node_constraints.class,
      node_kind: node_constraints.node_kind,
      min_inclusive: node_constraints.min_inclusive,
      max_inclusive: node_constraints.max_inclusive,
      # ... all other constraints
    }}
  end
end

# NEW: Parse all node-level constraints
defp parse_node_constraints(graph, shape_iri) do
  constraints = %{
    datatype: get_single_object(graph, shape_iri, SHACL.datatype()),
    class: get_single_object(graph, shape_iri, SHACL.class()),
    node_kind: parse_node_kind(graph, shape_iri),
    min_inclusive: parse_numeric_literal(graph, shape_iri, SHACL.min_inclusive()),
    max_inclusive: parse_numeric_literal(graph, shape_iri, SHACL.max_inclusive()),
    min_exclusive: parse_numeric_literal(graph, shape_iri, SHACL.min_exclusive()),
    max_exclusive: parse_numeric_literal(graph, shape_iri, SHACL.max_exclusive()),
    min_length: parse_integer_literal(graph, shape_iri, SHACL.min_length()),
    max_length: parse_integer_literal(graph, shape_iri, SHACL.max_length()),
    pattern: parse_pattern(graph, shape_iri),
    flags: get_literal_value(graph, shape_iri, SHACL.flags()),
    language_in: parse_language_in(graph, shape_iri),
    in: parse_in_list(graph, shape_iri),
    has_value: get_single_object(graph, shape_iri, SHACL.has_value()),
    node: get_all_objects(graph, shape_iri, SHACL.node()),
    and: parse_and_list(graph, shape_iri),
    or: parse_or_list(graph, shape_iri),
    xone: parse_xone_list(graph, shape_iri),
    not: get_all_objects(graph, shape_iri, SHACL.not()),
    closed: get_boolean(graph, shape_iri, SHACL.closed(), false),
    ignored_properties: parse_ignored_properties(graph, shape_iri),
    equals: get_single_object(graph, shape_iri, SHACL.equals()),
    disjoint: get_single_object(graph, shape_iri, SHACL.disjoint())
  }

  {:ok, constraints}
end
```

**Note**: Most helper functions already exist in Reader for PropertyShape parsing - reuse them!

### 4.3. Validator Changes

#### File: `lib/elixir_ontologies/shacl/validator.ex`

Modify `validate_focus_node/3` to include node-level validation:

```elixir
defp validate_focus_node(data_graph, focus_node, node_shape) do
  # NEW: Validate node-level constraints (focus node as value)
  node_results = validate_node_constraints(data_graph, focus_node, node_shape)

  # Existing: Validate property shapes
  property_results =
    node_shape.property_shapes
    |> Enum.flat_map(fn property_shape ->
      validate_property_shape(data_graph, focus_node, property_shape)
    end)

  # Existing: Validate SPARQL constraints
  sparql_results = Validators.SPARQL.validate(data_graph, focus_node, node_shape.sparql_constraints)

  node_results ++ property_results ++ sparql_results
end

# NEW: Validate focus node against node-level constraints
defp validate_node_constraints(_data_graph, focus_node, node_shape) do
  # Early return if no node constraints
  unless has_node_constraints?(node_shape) do
    return []
  end

  []
  |> concat(Validators.Type.validate_node(focus_node, node_shape))
  |> concat(Validators.String.validate_node(focus_node, node_shape))
  |> concat(Validators.Value.validate_node(focus_node, node_shape))
  |> concat(validate_node_range_constraints(focus_node, node_shape))
  |> concat(validate_node_logical_constraints(focus_node, node_shape))
  |> concat(validate_node_shape_constraints(focus_node, node_shape))
end

# Helper: Check if NodeShape has any node-level constraints
defp has_node_constraints?(node_shape) do
  node_shape.datatype != nil ||
  node_shape.class != nil ||
  node_shape.node_kind != nil ||
  node_shape.min_inclusive != nil ||
  node_shape.max_inclusive != nil ||
  node_shape.min_exclusive != nil ||
  node_shape.max_exclusive != nil ||
  node_shape.min_length != nil ||
  node_shape.max_length != nil ||
  node_shape.pattern != nil ||
  node_shape.language_in != [] ||
  node_shape.in != [] ||
  node_shape.has_value != nil ||
  node_shape.node != [] ||
  node_shape.and != [] ||
  node_shape.or != [] ||
  node_shape.xone != [] ||
  node_shape.not != [] ||
  node_shape.closed ||
  node_shape.equals != nil ||
  node_shape.disjoint != nil
end
```

### 4.4. Validator Module Extensions

Each validator module needs a `validate_node/2` function:

#### File: `lib/elixir_ontologies/shacl/validators/type.ex`

```elixir
# NEW: Validate node-level type constraints
@spec validate_node(RDF.Term.t(), NodeShape.t()) :: [ValidationResult.t()]
def validate_node(focus_node, node_shape) do
  []
  |> concat(validate_datatype_node(focus_node, node_shape))
  |> concat(validate_class_node(focus_node, node_shape))
  |> concat(validate_node_kind_node(focus_node, node_shape))
end

defp validate_datatype_node(focus_node, node_shape) do
  case node_shape.datatype do
    nil -> []
    required_datatype ->
      if matches_datatype?(focus_node, required_datatype) do
        []
      else
        [create_violation(
          focus_node,
          focus_node,  # value is the focus node itself
          SHACL.datatype_constraint_component(),
          node_shape.id,
          nil  # No result_path for node constraints
        )]
      end
  end
end

# Similar for class, node_kind...
```

#### File: `lib/elixir_ontologies/shacl/validators/string.ex`

```elixir
# NEW: Validate node-level string constraints
@spec validate_node(RDF.Term.t(), NodeShape.t()) :: [ValidationResult.t()]
def validate_node(focus_node, node_shape) do
  []
  |> concat(validate_min_length_node(focus_node, node_shape))
  |> concat(validate_max_length_node(focus_node, node_shape))
  |> concat(validate_pattern_node(focus_node, node_shape))
  |> concat(validate_language_in_node(focus_node, node_shape))
end

defp validate_pattern_node(focus_node, node_shape) do
  case node_shape.pattern do
    nil -> []
    pattern_regex ->
      string_value = literal_to_string(focus_node)
      if Regex.match?(pattern_regex, string_value) do
        []
      else
        [create_violation(
          focus_node,
          focus_node,
          SHACL.pattern_constraint_component(),
          node_shape.id,
          nil
        )]
      end
  end
end
```

#### File: `lib/elixir_ontologies/shacl/validators/value.ex`

```elixir
# NEW: Validate node-level value constraints
@spec validate_node(RDF.Term.t(), NodeShape.t()) :: [ValidationResult.t()]
def validate_node(focus_node, node_shape) do
  []
  |> concat(validate_in_node(focus_node, node_shape))
  |> concat(validate_has_value_node(focus_node, node_shape))
end

defp validate_in_node(focus_node, node_shape) do
  case node_shape.in do
    [] -> []
    allowed_values ->
      if focus_node in allowed_values do
        []
      else
        [create_violation(
          focus_node,
          focus_node,
          SHACL.in_constraint_component(),
          node_shape.id,
          nil
        )]
      end
  end
end
```

### 4.5. New Helper Functions (Validator Module)

```elixir
# Validate numeric range constraints on focus node
defp validate_node_range_constraints(focus_node, node_shape) do
  []
  |> concat(validate_min_inclusive_node(focus_node, node_shape))
  |> concat(validate_max_inclusive_node(focus_node, node_shape))
  |> concat(validate_min_exclusive_node(focus_node, node_shape))
  |> concat(validate_max_exclusive_node(focus_node, node_shape))
end

defp validate_min_inclusive_node(focus_node, node_shape) do
  case {node_shape.min_inclusive, RDF.Literal.value(focus_node)} do
    {nil, _} -> []
    {min, value} when is_number(value) and value >= min -> []
    {_min, _value} ->
      [create_violation(
        focus_node,
        focus_node,
        SHACL.min_inclusive_constraint_component(),
        node_shape.id,
        nil
      )]
  end
end

# Validate logical constraints (sh:and, sh:or, sh:not, sh:xone)
defp validate_node_logical_constraints(focus_node, node_shape) do
  # Future implementation (Phase 11.5.3 or later)
  # For now, return empty (these constraints not in failing tests)
  []
end

# Validate shape-based constraints (sh:node)
defp validate_node_shape_constraints(focus_node, node_shape) do
  # Future implementation
  # Requires recursive shape validation
  []
end
```

---

## 5. Success Criteria

Phase 11.5.2 is complete when:

### Test Pass Rate (Required)

- ✅ W3C test pass rate increases from **18% to 61%** (9/51 → 31/51 tests)
- ✅ All 22 node-level constraint tests pass:
  - `datatype_001`, `datatype_002` (sh:datatype on NodeShape)
  - `class_001`, `class_002`, `class_003` (sh:class on NodeShape)
  - `in_001` (sh:in on NodeShape)
  - `pattern_001`, `pattern_002` (sh:pattern on NodeShape)
  - `minLength_001`, `maxLength_001` (string length on NodeShape)
  - `minInclusive_001`, `minInclusive_002`, `minInclusive_003` (numeric range)
  - `maxInclusive_001`, `minExclusive_001`, `maxExclusive_001`
  - `hasValue_001` (sh:hasValue on NodeShape)
  - `nodeKind_001` (sh:nodeKind on NodeShape)
  - `languageIn_001` (sh:languageIn on NodeShape)
  - `equals_001`, `disjoint_001` (comparison constraints)
  - `node_001` (sh:node on NodeShape)

### Implementation Complete (Required)

- ✅ `NodeShape` struct extended with all constraint fields
- ✅ `Reader` parses node-level constraints from RDF
- ✅ `Validator` validates node-level constraints before property constraints
- ✅ Each validator module has `validate_node/2` function:
  - `Validators.Type.validate_node/2`
  - `Validators.String.validate_node/2`
  - `Validators.Value.validate_node/2`
  - Helper functions for range, logical, shape constraints

### Regression Tests (Required)

- ✅ All existing SHACL tests still pass (no regressions)
- ✅ `elixir-shapes.ttl` validation still works correctly
- ✅ Property-level constraint validation unchanged

### Documentation (Required)

- ✅ `NodeShape` moduledoc updated with node-level constraint examples
- ✅ `Validator` moduledoc explains node vs property validation flow
- ✅ This planning document serves as implementation reference

---

## 6. Implementation Plan

### Step 1: Extend NodeShape Data Model (2-3 hours)

**File**: `lib/elixir_ontologies/shacl/model/node_shape.ex`

- [ ] Add constraint fields to `NodeShape` struct (datatype, class, node_kind, etc.)
- [ ] Update `@type` spec with new fields
- [ ] Update moduledoc with node-level constraint examples
- [ ] Update doctests to show node-level constraints

**Verification**:
```bash
mix compile
# Should compile without errors
```

---

### Step 2: Extend Reader to Parse Node-Level Constraints (4-6 hours)

**File**: `lib/elixir_ontologies/shacl/reader.ex`

- [ ] Implement `parse_node_constraints/2` function
- [ ] Reuse existing helper functions where possible:
  - `get_single_object/3` for datatype, class, has_value, etc.
  - `parse_rdf_list/2` for sh:in, sh:languageIn
  - Existing pattern parsing logic
- [ ] Update `parse_node_shape/2` to call `parse_node_constraints/2`
- [ ] Merge constraint map into NodeShape struct

**Verification**:
```bash
# Create test fixture with node-level constraints
cat > test/fixtures/node_constraint_test.ttl << 'EOF'
@prefix ex: <http://example.org/> .
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

ex:IntegerShape
  a sh:NodeShape ;
  sh:targetNode 42 ;
  sh:datatype xsd:integer ;
  sh:minInclusive 0 .
EOF

# Test parsing
iex -S mix
> {:ok, graph} = RDF.Turtle.read_file("test/fixtures/node_constraint_test.ttl")
> {:ok, shapes} = ElixirOntologies.SHACL.Reader.parse_shapes(graph)
> shape = hd(shapes)
> shape.datatype
~I<http://www.w3.org/2001/XMLSchema#integer>
> shape.min_inclusive
0
```

---

### Step 3: Implement Validator.validate_node_constraints/3 (3-4 hours)

**File**: `lib/elixir_ontologies/shacl/validator.ex`

- [ ] Implement `has_node_constraints?/1` helper
- [ ] Implement `validate_node_constraints/3` function
- [ ] Modify `validate_focus_node/3` to call node validation first
- [ ] Implement `validate_node_range_constraints/2` helper
- [ ] Add placeholder for logical constraints (empty for now)

**Verification**:
```elixir
# Unit test
test "validate_node_constraints with no constraints returns empty" do
  node_shape = %NodeShape{id: ~I<ex:Shape>}
  assert [] = Validator.validate_node_constraints(graph, ~L"42", node_shape)
end

test "validate_node_constraints with datatype constraint" do
  node_shape = %NodeShape{
    id: ~I<ex:Shape>,
    datatype: ~I<http://www.w3.org/2001/XMLSchema#integer>
  }

  # Valid
  assert [] = Validator.validate_node_constraints(graph, ~L"42"^^xsd:integer, node_shape)

  # Invalid
  assert [%ValidationResult{}] =
    Validator.validate_node_constraints(graph, ~L"hello", node_shape)
end
```

---

### Step 4: Implement Validators.Type.validate_node/2 (2-3 hours)

**File**: `lib/elixir_ontologies/shacl/validators/type.ex`

- [ ] Implement `validate_node/2` function
- [ ] Implement `validate_datatype_node/2` helper
- [ ] Implement `validate_class_node/2` helper
- [ ] Implement `validate_node_kind_node/2` helper
- [ ] Reuse existing `matches_datatype?/2` logic

**Verification**:
```bash
mix test test/elixir_ontologies/shacl/validators/type_test.exs
# Add new tests for validate_node/2
```

---

### Step 5: Implement Validators.String.validate_node/2 (2-3 hours)

**File**: `lib/elixir_ontologies/shacl/validators/string.ex`

- [ ] Implement `validate_node/2` function
- [ ] Implement `validate_pattern_node/2` helper
- [ ] Implement `validate_min_length_node/2` helper
- [ ] Implement `validate_max_length_node/2` helper
- [ ] Implement `validate_language_in_node/2` helper

**Verification**:
```bash
mix test test/elixir_ontologies/shacl/validators/string_test.exs
```

---

### Step 6: Implement Validators.Value.validate_node/2 (2-3 hours)

**File**: `lib/elixir_ontologies/shacl/validators/value.ex`

- [ ] Implement `validate_node/2` function
- [ ] Implement `validate_in_node/2` helper
- [ ] Implement `validate_has_value_node/2` helper
- [ ] Reuse existing value comparison logic

**Verification**:
```bash
mix test test/elixir_ontologies/shacl/validators/value_test.exs
```

---

### Step 7: Implement Numeric Range Constraint Validation (2-3 hours)

**File**: `lib/elixir_ontologies/shacl/validator.ex`

- [ ] Implement `validate_min_inclusive_node/2`
- [ ] Implement `validate_max_inclusive_node/2`
- [ ] Implement `validate_min_exclusive_node/2`
- [ ] Implement `validate_max_exclusive_node/2`
- [ ] Handle numeric literal extraction from RDF

**Verification**:
```elixir
test "numeric range constraints on node" do
  node_shape = %NodeShape{
    id: ~I<ex:Shape>,
    min_inclusive: 0,
    max_inclusive: 100
  }

  assert [] = validate_node_constraints(graph, ~L"42"^^xsd:integer, node_shape)
  assert [%ValidationResult{}] =
    validate_node_constraints(graph, ~L"150"^^xsd:integer, node_shape)
end
```

---

### Step 8: Run W3C Tests and Debug (4-6 hours)

- [ ] Run W3C test suite: `mix test test/elixir_ontologies/w3c_test.exs`
- [ ] Identify failing node-level constraint tests
- [ ] Debug each failure:
  - Check Reader parsing (are constraints extracted correctly?)
  - Check Validator dispatch (is validate_node being called?)
  - Check constraint logic (is validation correct?)
- [ ] Fix bugs until all 22 tests pass

**Target Tests**:
```bash
# Should pass after Step 8
mix test test/elixir_ontologies/w3c_test.exs --only datatype
mix test test/elixir_ontologies/w3c_test.exs --only class
mix test test/elixir_ontologies/w3c_test.exs --only in
mix test test/elixir_ontologies/w3c_test.exs --only pattern
# ... etc for all 22 tests
```

---

### Step 9: Regression Testing (2-3 hours)

- [ ] Run all existing SHACL tests: `mix test test/elixir_ontologies/shacl_test.exs`
- [ ] Run all existing validator tests: `mix test test/elixir_ontologies/shacl/validators/`
- [ ] Validate `elixir-shapes.ttl` still works: `mix shacl.validate`
- [ ] Fix any regressions

**Success Criteria**:
```bash
mix test
# All tests pass (no regressions)

mix shacl.validate
# elixir-shapes.ttl validation still works
```

---

### Step 10: Documentation and Cleanup (2-3 hours)

- [ ] Update `NodeShape` moduledoc with comprehensive examples
- [ ] Update `Validator` moduledoc with node vs property flow diagram
- [ ] Add doctests for node-level constraint validation
- [ ] Update CHANGELOG.md with Phase 11.5.2 changes
- [ ] Update this planning document with actual results

**Documentation Additions**:
```elixir
# NodeShape moduledoc example
"""
## Node-Level Constraints

Constraints can be applied directly to the focus node:

    ex:IntegerShape
      a sh:NodeShape ;
      sh:targetNode 42 ;
      sh:datatype xsd:integer ;    # Focus node must be an integer
      sh:minInclusive 0 .          # Focus node must be >= 0

This validates: "Is 42 an integer >= 0?" (Yes, conforms)
"""
```

---

## 7. Testing Strategy

### 7.1. Unit Tests

**New Test Files**:

- `test/elixir_ontologies/shacl/validators/type_node_test.exs`
- `test/elixir_ontologies/shacl/validators/string_node_test.exs`
- `test/elixir_ontologies/shacl/validators/value_node_test.exs`

**Test Coverage**:

```elixir
defmodule ElixirOntologies.SHACL.Validators.TypeNodeTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.SHACL.Validators.Type
  alias ElixirOntologies.SHACL.Model.NodeShape

  describe "validate_node/2 with sh:datatype" do
    test "valid integer literal passes" do
      node_shape = %NodeShape{
        id: ~I<ex:Shape>,
        datatype: ~I<http://www.w3.org/2001/XMLSchema#integer>
      }

      assert [] = Type.validate_node(~L"42"^^xsd:integer, node_shape)
    end

    test "invalid datatype fails" do
      node_shape = %NodeShape{
        id: ~I<ex:Shape>,
        datatype: ~I<http://www.w3.org/2001/XMLSchema#integer>
      }

      results = Type.validate_node(~L"hello", node_shape)
      assert [%ValidationResult{} = result] = results
      assert result.source_constraint_component ==
        ~I<http://www.w3.org/ns/shacl#DatatypeConstraintComponent>
    end

    test "IRI fails datatype check" do
      node_shape = %NodeShape{
        id: ~I<ex:Shape>,
        datatype: ~I<http://www.w3.org/2001/XMLSchema#integer>
      }

      assert [%ValidationResult{}] = Type.validate_node(~I<ex:NotAnInteger>, node_shape)
    end
  end

  describe "validate_node/2 with sh:class" do
    test "instance of class passes" do
      # Test with RDFS inference
    end

    test "non-instance fails" do
      # Test validation failure
    end
  end

  describe "validate_node/2 with sh:nodeKind" do
    test "IRI matches nodeKind IRI" do
      node_shape = %NodeShape{
        id: ~I<ex:Shape>,
        node_kind: :iri
      }

      assert [] = Type.validate_node(~I<ex:SomeIRI>, node_shape)
    end

    test "literal fails nodeKind IRI" do
      node_shape = %NodeShape{
        id: ~I<ex:Shape>,
        node_kind: :iri
      }

      assert [%ValidationResult{}] = Type.validate_node(~L"42", node_shape)
    end
  end
end
```

### 7.2. Integration Tests (W3C Test Suite)

Target 22 specific tests:

```bash
# Test datatype constraints
mix test --only w3c_test:datatype_001
mix test --only w3c_test:datatype_002

# Test class constraints
mix test --only w3c_test:class_001
mix test --only w3c_test:class_002
mix test --only w3c_test:class_003

# Test value constraints
mix test --only w3c_test:in_001
mix test --only w3c_test:hasValue_001

# Test string constraints
mix test --only w3c_test:pattern_001
mix test --only w3c_test:pattern_002
mix test --only w3c_test:minLength_001
mix test --only w3c_test:maxLength_001

# Test numeric constraints
mix test --only w3c_test:minInclusive_001
mix test --only w3c_test:minInclusive_002
mix test --only w3c_test:minInclusive_003
mix test --only w3c_test:maxInclusive_001
mix test --only w3c_test:minExclusive_001
mix test --only w3c_test:maxExclusive_001

# Test other constraints
mix test --only w3c_test:nodeKind_001
mix test --only w3c_test:languageIn_001
mix test --only w3c_test:equals_001
mix test --only w3c_test:disjoint_001
mix test --only w3c_test:node_001
```

### 7.3. Regression Tests

Ensure existing functionality still works:

```bash
# Existing SHACL tests
mix test test/elixir_ontologies/shacl_test.exs

# Validator unit tests
mix test test/elixir_ontologies/shacl/validators/

# Reader tests
mix test test/elixir_ontologies/shacl/reader_test.exs

# End-to-end validation
mix shacl.validate
```

### 7.4. Performance Tests

Ensure node-level validation doesn't degrade performance:

```bash
# Benchmark before and after
mix run benchmark/shacl_validation.exs

# Expect:
# - Minimal overhead (<5%) for shapes without node constraints
# - Reasonable overhead (<20%) for shapes with node constraints
```

---

## 8. Risk Assessment and Mitigation

### Risk 1: Breaking Changes to NodeShape

**Impact**: High
**Likelihood**: Medium
**Mitigation**:
- All new fields have default values (nil or [])
- Existing code doesn't access new fields
- Backward compatible struct extension

**Fallback**:
- Use Option B (nested NodeConstraints struct) if struct becomes too large

---

### Risk 2: Complex Reader Changes

**Impact**: Medium
**Likelihood**: Low
**Mitigation**:
- Reuse existing helper functions
- Incremental testing of each constraint type
- Clear error handling for malformed RDF

**Fallback**:
- Implement constraints incrementally (datatype first, then class, etc.)

---

### Risk 3: Validator Performance Impact

**Impact**: Low
**Likelihood**: Low
**Mitigation**:
- Early return if no node constraints exist
- Reuse existing validation logic
- Maintain parallel validation

**Monitoring**:
- Benchmark before/after
- Profile with `:fprof` if performance issues arise

---

### Risk 4: Incomplete Test Coverage

**Impact**: Medium
**Likelihood**: Medium
**Mitigation**:
- Target specific 22 failing tests
- Add unit tests for each constraint type
- Regression test existing functionality

**Fallback**:
- Phase 11.5.3 can address any remaining edge cases

---

## 9. Future Enhancements (Out of Scope)

These are explicitly **not** part of Phase 11.5.2 but may be future work:

### Phase 11.5.3: Logical Constraints

- `sh:and`, `sh:or`, `sh:xone`, `sh:not` on NodeShapes
- Recursive shape validation
- Complex constraint combinations

### Phase 11.5.4: Advanced Path Expressions

- `sh:alternativePath`, `sh:inversePath`, `sh:zeroOrMorePath`, `sh:oneOrMorePath`
- Path expression evaluation

### Phase 11.5.5: Closed Shapes

- `sh:closed` with `sh:ignoredProperties`
- Validation of allowed properties

---

## 10. Estimated Effort

| Step | Description | Hours |
|------|-------------|-------|
| 1 | Extend NodeShape data model | 2-3 |
| 2 | Extend Reader parsing | 4-6 |
| 3 | Implement Validator.validate_node_constraints | 3-4 |
| 4 | Implement Type.validate_node | 2-3 |
| 5 | Implement String.validate_node | 2-3 |
| 6 | Implement Value.validate_node | 2-3 |
| 7 | Implement numeric range validation | 2-3 |
| 8 | W3C test debugging | 4-6 |
| 9 | Regression testing | 2-3 |
| 10 | Documentation and cleanup | 2-3 |
| **Total** | | **25-37 hours** |

**Realistic Timeline**: 4-5 working days (assuming 8-hour days)

---

## 11. Appendix: Example Test Cases

### Example 1: sh:datatype on NodeShape

**Input** (from W3C test `datatype-001.ttl`):
```turtle
ex:TestShape
  rdf:type sh:NodeShape ;
  sh:datatype xsd:integer ;
  sh:targetNode 42 ;               # Valid: integer literal
  sh:targetNode xsd:integer ;      # Invalid: IRI, not integer
  sh:targetNode "aldi"^^xsd:integer .  # Invalid: malformed integer

# Expected: 2 violations (xsd:integer IRI and "aldi")
```

**Validation Flow**:
```
1. Reader parses sh:datatype xsd:integer → node_shape.datatype = ~I<xsd:integer>
2. Reader parses sh:targetNode → focus_nodes = [42, xsd:integer, "aldi"^^xsd:integer]
3. Validator validates each focus node:
   - validate_node_constraints(42, node_shape)
     → Type.validate_node(42, node_shape)
     → matches_datatype?(42, xsd:integer) → true → []
   - validate_node_constraints(xsd:integer, node_shape)
     → Type.validate_node(xsd:integer, node_shape)
     → matches_datatype?(xsd:integer, xsd:integer) → false → [ValidationResult]
   - validate_node_constraints("aldi"^^xsd:integer, node_shape)
     → Type.validate_node("aldi", node_shape)
     → matches_datatype?("aldi", xsd:integer) → false → [ValidationResult]
4. Report: conforms = false, 2 violations
```

### Example 2: sh:in on NodeShape

**Input** (from W3C test `in-001.ttl`):
```turtle
ex:TestShape
  rdf:type rdfs:Class ;
  rdf:type sh:NodeShape ;
  sh:in ( ex:Red ex:Green ex:Blue ) .

ex:Red rdf:type ex:TestShape .      # Valid: in list
ex:Green rdf:type ex:TestShape .    # Valid: in list
ex:Yellow rdf:type ex:TestShape .   # Invalid: not in list

# Expected: 1 violation (Yellow)
```

**Validation Flow**:
```
1. Reader parses sh:in ( ex:Red ex:Green ex:Blue ) → node_shape.in = [ex:Red, ex:Green, ex:Blue]
2. Reader detects implicit class target → implicit_class_target = ex:TestShape
3. Validator finds instances: [ex:Red, ex:Green, ex:Yellow]
4. Validator validates each:
   - validate_node_constraints(ex:Red, node_shape)
     → Value.validate_node(ex:Red, node_shape)
     → ex:Red in [ex:Red, ex:Green, ex:Blue] → true → []
   - validate_node_constraints(ex:Green, node_shape)
     → Value.validate_node(ex:Green, node_shape)
     → ex:Green in [ex:Red, ex:Green, ex:Blue] → true → []
   - validate_node_constraints(ex:Yellow, node_shape)
     → Value.validate_node(ex:Yellow, node_shape)
     → ex:Yellow in [ex:Red, ex:Green, ex:Blue] → false → [ValidationResult]
5. Report: conforms = false, 1 violation
```

### Example 3: sh:pattern on NodeShape

**Input** (from W3C test `pattern-001.ttl`):
```turtle
ex:TestShape
  rdf:type sh:NodeShape ;
  sh:pattern "^[A-Z]" ;     # Must start with uppercase letter
  sh:targetNode "Alice" ;   # Valid
  sh:targetNode "bob" .     # Invalid

# Expected: 1 violation (bob)
```

**Validation Flow**:
```
1. Reader parses sh:pattern "^[A-Z]" → node_shape.pattern = ~r/^[A-Z]/
2. Reader parses sh:targetNode → focus_nodes = ["Alice", "bob"]
3. Validator validates each:
   - validate_node_constraints("Alice", node_shape)
     → String.validate_node("Alice", node_shape)
     → Regex.match?(~r/^[A-Z]/, "Alice") → true → []
   - validate_node_constraints("bob", node_shape)
     → String.validate_node("bob", node_shape)
     → Regex.match?(~r/^[A-Z]/, "bob") → false → [ValidationResult]
4. Report: conforms = false, 1 violation
```

---

## 12. Summary

Phase 11.5.2 will implement **node-level constraints** to validate focus nodes directly, unlocking 22 additional W3C test passes and increasing our pass rate from **18% to 61%**.

**Key Changes**:
1. Extend `NodeShape` struct with constraint fields
2. Extend `Reader` to parse node-level constraints
3. Extend `Validator` to validate focus nodes directly
4. Add `validate_node/2` functions to each validator module

**Impact**:
- +43% W3C test pass rate
- Core SHACL spec compliance
- Foundation for logical operators (sh:and, sh:or, etc.)
- Minimal breaking changes

**Timeline**: 25-37 hours (4-5 days)

---

**End of Planning Document**
