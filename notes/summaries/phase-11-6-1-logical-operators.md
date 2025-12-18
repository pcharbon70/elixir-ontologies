# Phase 11.6.1 Summary: SHACL Logical Operators Implementation

**Date:** 2025-12-14
**Phase:** 11.6.1 - Logical Operators (sh:and, sh:or, sh:xone, sh:not)
**Status:** ✅ Complete
**W3C Pass Rate:** 64.2% (34/53 tests) - **Target Exceeded** (~60% target)

## Overview

Implemented complete support for SHACL logical constraint operators per W3C SHACL Recommendation sections 4.1-4.4. This enables complex validation logic through recursive shape combinations including:
- `sh:and` - All shapes must conform (conjunction)
- `sh:or` - At least one shape must conform (disjunction)
- `sh:xone` - Exactly one shape must conform (exclusive or)
- `sh:not` - Shape must NOT conform (negation)

## Implementation Summary

### Files Modified

1. **lib/elixir_ontologies/shacl/vocabulary.ex**
   - Added logical operator predicates (sh:and, sh:or, sh:xone, sh:not)
   - Added constraint component IRIs for violation reporting
   - Lines added: 8 module attributes + 8 accessor functions

2. **lib/elixir_ontologies/shacl/model/node_shape.ex**
   - Added fields for node-level logical operators
   - Fields: `node_and`, `node_or`, `node_xone`, `node_not`
   - Updated type specifications

3. **lib/elixir_ontologies/shacl/reader.ex** (Major changes)
   - Added RDF list parsing for sh:and, sh:or, sh:xone
   - Added single value extraction for sh:not (with list normalization fix)
   - Implemented recursive inline blank node shape parsing
   - New functions:
     - `parse_inline_shapes/3` - Recursively discover and parse inline shapes
     - `parse_inline_shapes_recursive/4` - Helper for recursive discovery
     - `collect_logical_shape_refs/1` - Extract shape references from logical operators
     - `extract_logical_and/2`, `extract_logical_or/2`, `extract_logical_xone/2`, `extract_logical_not/1`
   - Lines added: ~150

4. **lib/elixir_ontologies/shacl/validators/logical_operators.ex** (New file)
   - Complete validator module for logical constraints
   - Features:
     - Recursion depth limit (@max_recursion_depth = 50)
     - Cycle detection via depth tracking
     - Recursive shape validation via shape_map
   - Functions:
     - `validate_node/5` - Main entry point
     - `validate_and/5`, `validate_or/5`, `validate_xone/5`, `validate_not/5`
     - `validate_against_shape/4` - Recursive shape resolution
     - `validate_shape_constraints/4` - Full constraint validation
   - Lines added: ~290

5. **lib/elixir_ontologies/shacl/validator.ex**
   - Added shape_map building and distribution
   - New function: `build_shape_map/1`
   - Updated signatures for `validate_node_shape/3`, `validate_focus_node/4`, `validate_node_constraints/4`
   - Integrated LogicalOperators validator
   - Lines modified: ~15

### Key Technical Achievements

#### 1. Inline Blank Node Shape Parsing
Problem: Logical operators often reference inline blank node shapes not explicitly typed as sh:NodeShape.

Solution: Implemented recursive discovery algorithm:
```elixir
defp parse_inline_shapes_recursive(graph, shapes, parsed_ids, opts) do
  # Collect all shape references from logical operators
  referenced_shape_ids = shapes |> Enum.flat_map(&collect_logical_shape_refs/1)

  # Find unparsed blank nodes
  new_blank_nodes = referenced_shape_ids
    |> Enum.filter(fn ref -> match?(%RDF.BlankNode{}, ref) && !MapSet.member?(parsed_ids, ref) end)

  # Recursively parse until no new blank nodes found
  # ... (handles nested inline shapes)
end
```

#### 2. Shape Map Architecture
Implemented shape resolution via map-based lookup:
```elixir
shape_map = %{
  shape_id => NodeShape.t(),
  blank_node_id => NodeShape.t(),
  ...
}
```

This enables O(1) shape lookups during recursive validation, supporting both named IRI shapes and inline blank node shapes.

#### 3. Recursion Safety
- Maximum depth limit: 50 levels
- Graceful degradation on overflow (logs error, returns empty results)
- Prevents stack overflow from circular shape references

#### 4. sh:not List Normalization Bug Fix
Discovered and fixed issue where `RDF.Description.get/2` returns a list for sh:not values:
```elixir
# Before (caused warnings):
{:ok, RDF.Description.get(desc, SHACL.not_operator())}

# After (handles list properly):
value = case desc |> RDF.Description.get(SHACL.not_operator()) |> normalize_to_list() do
  [] -> nil
  [first | _] -> first
end
```

### Test Results

#### W3C SHACL Test Suite (Core Tests)
- **Total tests:** 53
- **Passing:** 34 (64.2%)
- **Failing:** 19 (35.8%)
- **Excluded:** 4
- **Baseline:** 47.2% → **Improvement: +17.0 percentage points**

#### Logical Operator Tests (7 tests)
| Test | Status | Notes |
|------|--------|-------|
| and_001 | ✅ Pass | Conjunction with inline blank node shapes |
| and_002 | ✅ Pass | Multiple AND constraints |
| or_001 | ✅ Pass | Disjunction with inline shapes |
| not_001 | ✅ Pass | Negation with property shape (no warnings) |
| not_002 | ✅ Pass | Negation edge cases (no warnings) |
| xone_001 | ✅ Pass | Exclusive OR basic case |
| xone_duplicate | ❌ Fail | Property-level xone (not implemented) |

**Pass Rate: 6/7 (85.7%)**

Note: xone_duplicate failure is expected - it tests property-level logical operators which are not in scope for Phase 11.6.1 (node-level operators only).

### Known Limitations

1. **Property-level logical operators:** Not implemented (sh:and/or/xone/not on PropertyShape)
2. **Blank node warnings resolved:** Initial implementation had warnings about blank nodes not found in shape_map, fixed via list normalization in extract_logical_not

### Architecture Notes

#### Validation Flow
```
1. Reader.parse_shapes(shapes_graph)
   ├─ Find top-level sh:NodeShape instances
   ├─ Parse each NodeShape (extract logical operators as references)
   └─ parse_inline_shapes: Recursively discover and parse blank node shapes

2. Validator.run(data_graph, shapes_graph)
   ├─ build_shape_map: Create ID → NodeShape lookup map
   └─ For each target node:
       ├─ validate_node_constraints (includes LogicalOperators)
       └─ validate_property_shapes

3. LogicalOperators.validate_node(focus_node, node_shape, shape_map)
   ├─ validate_and: Check all shapes pass
   ├─ validate_or: Check at least one passes
   ├─ validate_xone: Check exactly one passes
   └─ validate_not: Check shape does NOT pass
       └─ validate_against_shape: Recursive validation via shape_map
```

#### Recursion Strategy
- **Top-down:** Validator calls LogicalOperators for each focus node
- **Recursive:** LogicalOperators calls validate_shape_constraints for referenced shapes
- **Bottom-up:** Results bubble up through recursion stack
- **Depth tracking:** Prevents infinite loops from circular references

### Dependencies

**New dependencies:** None

**Modified dependencies:**
- Existing SHACL validators (Type, String, Value, Cardinality, Qualified)
- All called recursively from LogicalOperators.validate_shape_constraints

### Code Quality

- **Compiler warnings:** 0
- **Pattern matching:** Extensive use for nil handling and list processing
- **Documentation:** Comprehensive moduledoc and function docs
- **Type specs:** Complete @spec annotations for all public/private functions
- **Error handling:** Graceful degradation (log + return empty results)

### Performance Characteristics

- **Shape map building:** O(n) where n = number of shapes
- **Shape lookup:** O(1) via map-based resolution
- **Recursive validation:** O(d × c) where:
  - d = maximum depth (50)
  - c = constraints per shape
- **Inline shape discovery:** O(s × r) where:
  - s = number of shapes
  - r = average shape references per shape

### Future Work (Out of Scope)

1. **Property-level logical operators** (Phase 11.6.2?)
   - sh:and/or/xone/not on PropertyShape
   - Would require PropertyShape model updates
   - Would enable xone_duplicate test to pass

2. **SPARQL-based logical constraints**
   - Alternative to declarative logical operators
   - Already partially supported via sh:sparql

3. **Performance optimization**
   - Memoization of shape validation results
   - Could reduce redundant recursive validations

4. **Enhanced error reporting**
   - Include nested validation failures in violation details
   - Currently only reports top-level logical constraint failures

## Testing

### Commands Used
```bash
# Compile
mix compile

# Run W3C test suite
mix test test/elixir_ontologies/w3c_test.exs --only w3c_core --seed 0

# Run with trace
mix test test/elixir_ontologies/w3c_test.exs --only w3c_core --seed 0 --trace
```

### Verification
All code changes compile cleanly with zero warnings. All 6 node-level logical operator tests pass. The xone_duplicate test fails as expected (property-level operators not in scope).

## Lessons Learned

1. **RDF list normalization:** Always normalize values from RDF.Description.get to handle both single values and lists
2. **Blank node parsing:** Inline blank nodes require recursive discovery since they're not explicitly typed
3. **Shape map necessity:** Critical for O(1) lookups during recursive validation
4. **Test-driven development:** W3C test suite provided excellent validation of implementation correctness

## Conclusion

Phase 11.6.1 successfully implements complete node-level logical operator support for SHACL validation. The implementation:
- ✅ Passes 6/7 logical operator tests (85.7%)
- ✅ Increases overall W3C pass rate from 47.2% to 64.2% (+17.0 points)
- ✅ Exceeds target pass rate of ~60%
- ✅ Handles complex inline blank node shapes
- ✅ Provides recursion safety with depth limits
- ✅ Maintains zero compiler warnings
- ✅ Follows existing codebase patterns

The only failing test (xone_duplicate) tests property-level logical operators, which are intentionally out of scope for this phase.

**Recommendation:** Proceed with Phase 11.6.2 or next priority task in implementation plan.
