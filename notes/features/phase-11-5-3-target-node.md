# Phase 11.5.3: sh:targetNode Support - Implementation Plan

**Date**: 2025-12-14
**Status**: Planning Complete, Ready for Implementation
**Branch**: `feature/phase-11-5-3-target-node`

## Problem Statement

Phase 11.5.2 implemented node-level constraint VALIDATION but NOT node-level TARGETING. The validation logic works correctly, but W3C test pass rate only improved from 18% to 19% because tests use `sh:targetNode` to explicitly target specific nodes (including literals, IRIs, and blank nodes).

**Impact**: 22+ W3C node-level constraint tests are blocked on explicit node targeting.

## Solution Overview

Implement `sh:targetNode` support per SHACL 2.1.2 "Node Targets" to allow targeting:
- IRIs (resources)
- Blank nodes
- Literals (strings, numbers, dates, etc.)

This is different from `sh:targetClass` which selects nodes by their rdf:type.

## Current State Analysis

**What Works (Phase 11.5.2)**:
- ✅ NodeShape has node-level constraint fields (node_datatype, node_class, etc.)
- ✅ Reader extracts node-level constraints from shapes graph
- ✅ Validator has `validate_node_constraints/3` working correctly
- ✅ Validators have `validate_node/3` functions implemented

**What's Missing**:
- ❌ `sh:targetNode` is not parsed from shapes graph
- ❌ NodeShape struct lacks `target_nodes` field
- ❌ Validator doesn't select nodes via explicit `sh:targetNode` targeting

## Example from W3C Test

```turtle
ex:TestShape
  rdf:type sh:NodeShape ;
  sh:minExclusive 4 ;
  sh:targetNode ex:John ;      # Targets an IRI
  sh:targetNode 3.9 ;          # Targets a literal (decimal)
  sh:targetNode 4.0 ;          # Targets a literal (float)
  sh:targetNode "Hello" .      # Targets a literal (string)
```

## Implementation Plan

### Step 1: Add SHACL Vocabulary ⏳

**File**: `lib/elixir_ontologies/shacl/vocabulary.ex`

**Changes**:
- Add module attribute: `@sh_target_node RDF.iri("http://www.w3.org/ns/shacl#targetNode")`
- Add public function: `def target_node, do: @sh_target_node`

**Example**:
```elixir
# Targeting
@sh_target_class RDF.iri("http://www.w3.org/ns/shacl#targetClass")
@sh_target_node RDF.iri("http://www.w3.org/ns/shacl#targetNode")  # NEW

# ... later in file

@doc "SHACL targetNode predicate IRI"
def target_node, do: @sh_target_node  # NEW
```

**Estimated**: 5 minutes

---

### Step 2: Extend NodeShape Data Model ⏳

**File**: `lib/elixir_ontologies/shacl/model/node_shape.ex`

**Changes**:
- Add `target_nodes: []` field to defstruct
- Add to @type spec: `target_nodes: [RDF.Term.t()]`
- Update moduledoc with sh:targetNode documentation

**Example**:
```elixir
defstruct [
  :id,
  target_classes: [],
  target_nodes: [],  # NEW: Explicit node targeting
  implicit_class_target: nil,
  # ... rest of fields
]

@type t :: %__MODULE__{
  id: RDF.IRI.t() | RDF.BlankNode.t(),
  target_classes: [RDF.IRI.t()],
  target_nodes: [RDF.Term.t()],  # NEW
  # ... rest
}
```

**Rationale**: `sh:targetNode` can target any RDF term (IRI, literal, or blank node)

**Estimated**: 10 minutes

---

### Step 3: Extract target_nodes in Reader ⏳

**File**: `lib/elixir_ontologies/shacl/reader.ex`

**Changes**:
1. Add `extract_target_nodes/1` function
2. Update `parse_node_shape/2` to call it
3. Populate `target_nodes` field in NodeShape

**Implementation**:

```elixir
# Add new extraction function after extract_target_classes
@spec extract_target_nodes(RDF.Description.t()) :: {:ok, [RDF.Term.t()]} | {:error, term()}
defp extract_target_nodes(desc) do
  target_nodes =
    desc
    |> RDF.Description.get(SHACL.target_node(), [])
    |> List.wrap()

  {:ok, target_nodes}
end

# Modify parse_node_shape/2
defp parse_node_shape(graph, shape_id) do
  desc = RDF.Graph.description(graph, shape_id)

  with {:ok, target_classes} <- extract_target_classes(desc),
       {:ok, target_nodes} <- extract_target_nodes(desc),  # NEW
       {:ok, implicit_class_target} <- extract_implicit_class_target(desc, shape_id),
       # ... rest of extractions
  do
    {:ok,
     %NodeShape{
       id: shape_id,
       target_classes: target_classes,
       target_nodes: target_nodes,  # NEW
       # ... rest of fields
     }}
  end
end
```

**Key Points**:
- `sh:targetNode` can appear multiple times (targets multiple nodes)
- Values can be IRIs, literals, or blank nodes
- Use `List.wrap/1` to handle both single and multiple values

**Estimated**: 20 minutes

---

### Step 4: Use target_nodes in Validator ⏳

**File**: `lib/elixir_ontologies/shacl/validator.ex`

**Changes**:
1. Add `select_explicit_target_nodes/1` function
2. Update `validate_node_shape/3` to include explicit targets
3. Combine all target sources

**Implementation**:

```elixir
# Add new target selection function (around line 200)
@spec select_explicit_target_nodes([RDF.Term.t()]) :: [RDF.Term.t()]
defp select_explicit_target_nodes(target_nodes) do
  # sh:targetNode explicitly lists the nodes to target
  # No lookup needed - the nodes are directly specified
  target_nodes
end

# Modify validate_node_shape/3 (around line 163)
defp validate_node_shape(data_graph, %NodeShape{} = node_shape) do
  # Find all target nodes via explicit targeting (sh:targetClass)
  explicit_targets = select_target_nodes(data_graph, node_shape.target_classes)

  # Find target nodes via sh:targetNode (NEW)
  node_targets = select_explicit_target_nodes(node_shape.target_nodes)

  # Find all target nodes via implicit class targeting (SHACL 2.1.3.1)
  implicit_targets = select_implicit_target_nodes(data_graph, node_shape.implicit_class_target)

  # Combine and deduplicate target nodes
  target_nodes = (explicit_targets ++ node_targets ++ implicit_targets) |> Enum.uniq()

  # Validate each target node
  Enum.flat_map(target_nodes, fn focus_node ->
    validate_focus_node(data_graph, focus_node, node_shape)
  end)
end
```

**Rationale**:
- Unlike `sh:targetClass` which requires queries to find instances
- `sh:targetNode` directly specifies the nodes to validate
- No data graph lookup needed - just use the terms as-is

**Estimated**: 20 minutes

---

### Step 5: Run W3C Tests ⏳

**Commands**:
```bash
# Run full W3C test suite
mix test test/elixir_ontologies/w3c_test.exs

# Test specific node-level constraint tests
mix test test/elixir_ontologies/w3c_test.exs --only w3c_core
```

**Expected Results**:
- Pass rate jumps from 19% to ~60%+
- 22+ additional tests passing
- Tests like datatype-001, minInclusive-001, class-001 should pass

**Estimated**: 15 minutes

---

### Step 6: Write Summary Document ⏳

**File**: `notes/summaries/phase-11-5-3-target-node.md`

**Contents**:
- Implementation summary
- Test results with before/after comparison
- Files modified
- Next steps

**Estimated**: 30 minutes

---

## Edge Cases to Handle

**Blank Node Targeting**:
```turtle
ex:Shape sh:targetNode _:b1 .
_:b1 rdf:type ex:TestClass .
```
- Blank node identifiers are scoped to the graph

**Literal Targeting**:
```turtle
ex:Shape
  sh:targetNode "hello" ;
  sh:targetNode 42 ;
  sh:targetNode "2024-01-01"^^xsd:date .
```
- Literals targeted directly (not looked up in data graph)

**Multiple Targets**:
```turtle
ex:Shape
  sh:targetNode ex:Node1 ;
  sh:targetNode ex:Node2 ;
  sh:targetNode 42 .
```
- Each creates a separate focus node

**Combined Targeting**:
```turtle
ex:Shape
  sh:targetClass ex:Class1 ;
  sh:targetNode ex:SpecificNode ;
  sh:targetNode 42 .
```
- All targeting mechanisms work together
- Results are unioned and deduplicated

## Expected Outcomes

**Test Results**:
- Current: 19% pass rate (10/53 tests)
- After implementation: 60%+ pass rate (31+/51 tests)
- 22+ additional tests passing

**Files Modified** (4 files):
1. `lib/elixir_ontologies/shacl/vocabulary.ex` - Add target_node constant
2. `lib/elixir_ontologies/shacl/model/node_shape.ex` - Add target_nodes field
3. `lib/elixir_ontologies/shacl/reader.ex` - Extract target_nodes
4. `lib/elixir_ontologies/shacl/validator.ex` - Use target_nodes for selection

**Estimated Changes**: ~40-50 lines of code

**Time Estimate**: 2-3 hours total

## Validation Checklist

Before considering Phase 11.5.3 complete:

- [ ] NodeShape has `target_nodes` field
- [ ] Vocabulary has `target_node()` function
- [ ] Reader extracts `sh:targetNode` values
- [ ] Validator includes target_nodes in focus node selection
- [ ] W3C test `targetNode-001` passes (if exists)
- [ ] W3C tests `datatype-001`, `datatype-002` pass
- [ ] W3C tests `minInclusive-001`, `minInclusive-002`, `minInclusive-003` pass
- [ ] W3C tests `class-001`, `class-002`, `class-003` pass
- [ ] Overall W3C pass rate is 60%+ (31+/51 tests)
- [ ] No regression in existing tests

## Implementation Status

- [⏳] Step 1: Add SHACL Vocabulary
- [⏳] Step 2: Extend NodeShape Data Model
- [⏳] Step 3: Extract target_nodes in Reader
- [⏳] Step 4: Use target_nodes in Validator
- [⏳] Step 5: Run W3C Tests
- [⏳] Step 6: Write Summary Document

## Notes

- This is a straightforward feature addition
- No complex logic - just parsing and using explicit targets
- Validates Phase 11.5.2 node-level constraint implementation
- Critical for W3C compliance improvement
