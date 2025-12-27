# Phase 19.3.1: Child Ordering Extraction

## Overview

Extract the order of children in supervision tree with enriched struct and comprehensive handling of different child patterns.

## Review Recommendations Addressed

From `notes/reviews/phase-19-3-planning-review.md`:

1. **Enriched struct** - Use expanded `%ChildOrder{}` with position, child_spec, id, is_dynamic, metadata
2. **Separate function** - Create `extract_ordered_children/1` separate from `extract_children/1`
3. **Dynamic children handling** - Mark DynamicSupervisor children with `is_dynamic: true`
4. **Children callback support** - Handle `children/0` callback pattern in addition to inline `init/1`

## Task Requirements (from phase-19.md)

- [x] 19.3.1.1 Track child position in children list
- [x] 19.3.1.2 Create ordered list of child specs
- [x] 19.3.1.3 Preserve original definition order
- [x] 19.3.1.4 Handle dynamic children markers
- [x] 19.3.1.5 Create `%ChildOrder{position: ..., child_spec: ...}` struct (enriched)
- [x] 19.3.1.6 Add child ordering tests (38 tests)

## Implementation Plan

### Step 1: Define ChildOrder Struct
Create enriched `%ChildOrder{}` struct with:
- `position` - Zero-based position in children list
- `child_spec` - The extracted ChildSpec struct
- `id` - Child ID extracted from spec
- `is_dynamic` - Whether this is a DynamicSupervisor (children added at runtime)
- `metadata` - Additional information

### Step 2: Add extract_ordered_children/1
New function that:
- Calls existing `extract_children/1` to get child specs
- Wraps each in `%ChildOrder{}` with position
- Preserves original definition order
- Marks DynamicSupervisor children appropriately

### Step 3: Add Convenience Functions
- `child_at_position/2` - Get child at specific position
- `child_count/1` - Get number of children
- `first_child/1`, `last_child/1` - Get first/last child
- `children_after/2` - Get children after a position (for rest_for_one analysis)
- `is_ordered?/1` - Verify ordering integrity

### Step 4: Handle children/0 Callback Pattern
Some supervisors define children separately:
```elixir
def children do
  [child1, child2]
end

def init(_) do
  Supervisor.init(children(), strategy: :one_for_one)
end
```

### Step 5: Add Comprehensive Tests
- Test position tracking
- Test ordering preservation
- Test DynamicSupervisor detection
- Test children/0 callback pattern
- Test convenience functions

## Files to Modify

1. `lib/elixir_ontologies/extractors/otp/supervisor.ex`
   - Add ChildOrder struct
   - Add extract_ordered_children/1
   - Add convenience functions

2. `test/elixir_ontologies/extractors/otp/supervisor_test.exs`
   - Add ChildOrder tests
   - Add ordering tests

## Success Criteria

1. All existing tests continue to pass
2. Child ordering correctly extracted
3. Position tracking works
4. DynamicSupervisor detection works
5. Code compiles without warnings

## Progress

- [x] Step 1: Define ChildOrder struct
- [x] Step 2: Add extract_ordered_children/1
- [x] Step 3: Add convenience functions
- [x] Step 4: Handle children/0 callback (via extract_children/1 integration)
- [x] Step 5: Add comprehensive tests (38 tests)
- [x] Quality checks pass

## Implementation Summary

### ChildOrder Struct
Added enriched `%ChildOrder{}` struct with:
- `position` - Zero-based position in children list
- `child_spec` - The extracted ChildSpec struct
- `id` - Child ID extracted from spec
- `is_dynamic` - Whether this is a DynamicSupervisor (children added at runtime)
- `metadata` - Map with `is_first`, `is_last`, `total_children`

### Functions Added
1. `extract_ordered_children/1` - Returns `{:ok, [ChildOrder.t()]}`
2. `extract_ordered_children!/1` - Bang variant
3. `child_at_position/2` - Get child at specific position
4. `ordered_child_count/1` - Count ordered children
5. `first_child/1` - Get first child
6. `last_child/1` - Get last child
7. `children_after/2` - Get children after a position (for rest_for_one analysis)
8. `children_before/2` - Get children before a position
9. `is_ordered?/1` - Verify sequential positions
10. `ordering_description/1` - Human-readable description

### Tests Added
38 tests covering:
- Position tracking
- Ordering preservation
- DynamicSupervisor detection
- Empty children list
- All convenience functions
- Edge cases
