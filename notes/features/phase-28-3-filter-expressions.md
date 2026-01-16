# Phase 28.3: Filter Expression Integration

**Feature Branch:** `feature/phase-28-3-filter-expressions`
**Created:** 2026-01-16
**Based On:** Phase 28 Expressions Plan (Section 28.3)

---

## Problem Statement

The current ControlFlowBuilder comprehension builder does not extract filter expressions when `include_expressions: true`. Filters are boolean expressions that determine which elements from the generator are included in the comprehension result.

**Examples of filters:**
```elixir
# Single filter
for x <- xs, x > 0, do: x * 2

# Multiple filters
for x <- xs, x > 0, x < 100, do: x * 2

# Complex filters
for x <- xs, is_binary(x) and byte_size(x) > 0, do: x

# Guard expressions
for {k, v} <- map, is_atom(k), do: {k, v}
```

**Current limitation:** Filters are not extracted in full mode, preventing analysis of filtering logic in comprehensions.

---

## Solution Overview

Update `ControlFlowBuilder.build_comprehension/3` to integrate with `ExpressionBuilder` for filter expression extraction when `include_expressions: true`:

1. Detect filter clauses in comprehension AST (clauses without `<-` operator)
2. Create filter IRIs: `{comp_iri}/filter/{index}`
3. Extract filter expressions via `ExpressionBuilder.build_expression/3`
4. Link filters via `hasFilter` property
5. Support multiple filters in order
6. Preserve filter expression tree structure

---

## Technical Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/control_flow_builder.ex` | Add filter extraction in comprehension builder |
| `test/elixir_ontologies/builders/control_flow_builder_test.exs` | Unit tests for filter expression extraction |

### Comprehension AST Structure for Filters

```elixir
# for x <- xs, x > 0, do: x * 2
{:for, [], [
  [{:<-, [], [{:x, [], nil}, {:xs, [], nil}]},   # generator
   {:>, [], [{:x, [], nil}, 0]}],                # filter
  [do: {:*, [], [{:x, [], nil}, 2]}]
]}

# for x <- xs, x > 0, x < 100, do: x
{:for, [], [
  [{:<-, [], [{:x, [], nil}, {:xs, [], nil}]},   # generator
   {:>, [], [{:x, [], nil}, 0]},                 # filter 1
   {:<, [], [{:x, [], nil}, 100]}],              # filter 2
  [do: {:x, [], nil}]
]}

# for x <- xs, is_binary(x) and byte_size(x) > 0, do: x
{:for, [], [
  [{:<-, [], [{:x, [], nil}, {:xs, [], nil}]},   # generator
   {:and, [], [                                  # complex filter
     {:is_binary, [], [{:x, [], nil}]},
     {:>, [], [{:byte_size, [], [{:x, [], nil}]}, 0]}
   ]}],
  [do: {:x, [], nil}]
]}
```

**Key distinction:** Filters are clauses that are NOT generators (don't have `<-` operator).

### Implementation Plan

1. **Identify filters** - Separate generators from filters in comprehension clauses
2. **Create filter IRIs** - Generate `{comp_iri}/filter/{index}` for each filter
3. **Extract filter expressions** - Call `ExpressionBuilder.build_expression/3`
4. **Link filters** - Use `hasFilter` property from comprehension
5. **Handle complex filters** - Preserve and/or structure, function calls, guards

### Ontology Properties

- `Core.hasFilter()` - Links comprehension to its filter expressions
- Filter expression type determined by `ExpressionBuilder.build_expression/3`

---

## Implementation Tasks

- [x] 28.3.1.1 Identify filter clauses in comprehension AST
- [x] 28.3.1.2 Match filter pattern: filter expression (not <- assignment)
- [x] 28.3.1.3 When `include_expressions: true`: extract filter via ExpressionBuilder
- [x] 28.3.1.4 Generate child IRI: `{comp_iri}/filter/{index}`
- [x] 28.3.1.5 Extract filter expression recursively
- [x] 28.3.1.6 Link filter via `hasFilter` property
- [x] 28.3.1.7 Handle multiple filters: `for x <- xs, x > 0, x < 100`
- [x] 28.3.2.1 Handle filters with and/or: `for x <- xs, is_binary(x) and byte_size(x) > 0`
- [x] 28.3.2.2 Handle filters with function calls: `for x <- xs, valid?(x)`
- [x] 28.3.2.3 Handle filters with comparison operators
- [x] 28.3.2.4 Handle filters with guard expressions
- [x] 28.3.2.5 Ensure filter expression tree is preserved

---

## Success Criteria

- [x] Filter expressions are extracted in full mode
- [x] Light mode remains unchanged (backward compatibility)
- [x] Multiple filters are supported
- [x] Filter order is preserved
- [x] All unit tests pass (114 tests)
- [x] Integration with ExpressionBuilder verified

---

## Unit Tests to Write

- [x] Test filter expression extraction in full mode
- [x] Test filter extraction handles boolean expressions (and/or)
- [x] Test filter extraction handles function calls
- [x] Test filter extraction handles multiple filters
- [x] Test filter extraction preserves filter structure
- [x] Test filter extraction handles complex guards
- [x] Test light mode backward compatibility (no filter IRIs)

---

## Current Status

**Status:** ✅ COMPLETE

**What was done:**
- Created feature branch `feature/phase-28-3-filter-expressions`
- Analyzed Phase 28 plan requirements
- Verified that filter extraction was already implemented in `ControlFlowBuilder.add_filter_triples` (lines 1522-1564)
- Added 6 comprehensive unit tests:
  - Filter expression extraction with comparison operator
  - Multiple filter expressions in order
  - Filter expression with boolean and
  - Filter expression with function call
  - Filter expression with guard
  - Light mode backward compatibility
- All 114 tests passing (108 existing + 6 new)

**Files Modified:**
- `test/elixir_ontologies/builders/control_flow_builder_test.exs`
  - Lines 1310-1611: Added 6 tests in "filter expression extraction in full mode" describe block

**Key Finding:** The filter extraction implementation already existed in `add_filter_triples` and `add_filter_expression_triple` functions. This phase added test coverage to verify the behavior.

**Test Results:**
- 114 tests, 0 failures (108 before + 6 new)

---

*Last Updated:* 2026-01-16
*Branch:* feature/phase-28-3-filter-expressions
*Status:* ✅ COMPLETE - Ready for commit and merge permission request
