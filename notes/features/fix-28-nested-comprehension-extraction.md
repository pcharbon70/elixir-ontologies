# Fix: Nested Comprehension Extraction

**Feature Branch:** `feature/fix-28-nested-comprehension-extraction`
**Created:** 2026-01-16
**Based On:** Limitation discovered in Phase 28.6

---

## Problem Statement

During Phase 28.6 (Comprehension Nesting and Complexity), a limitation was discovered where nested comprehensions in body position were not recursively extracted as `ForComprehension` types.

**Example:**
```elixir
for x <- xs, do: for y <- ys, do: {x, y}
```

**Expected behavior:** Both the outer and inner comprehensions should be extracted as `ForComprehension` types with full type information.

**Actual behavior (before fix):**
- Outer comprehension extracted as `ForComprehension` ✓
- Inner comprehension passed to `ExpressionBuilder.build_expression/3` which doesn't recognize `Comprehension` struct format ✗

**Root cause:** The `add_comprehension_body_triple` function in `ControlFlowBuilder` was passing all bodies to `expression_builder.build/3`, which doesn't recognize the `Comprehension` struct format returned by the `Comprehension` extractor.

---

## Solution Overview

Add pattern matching in `add_comprehension_body_triple` to detect nested `Comprehension` structs and recursively call `build_comprehension/3` instead of delegating to `ExpressionBuilder`.

**Implementation approach:**
1. Add a new function clause matching `%Comprehension{}` struct
2. The new clause executes before the generic body handling
3. Recursively calls `build_comprehension/3` with updated index
4. Ensures nested comprehensions are extracted with full `ForComprehension` type information

---

## Technical Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/control_flow_builder.ex` | Add pattern matching clause for nested comprehensions |
| `test/elixir_ontologies/builders/control_flow_builder_test.exs` | Add test for deeply nested comprehensions (3 levels) |

### Implementation

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex`

**Function:** `add_comprehension_body_triple/8`

**New clause (before generic body handling):**
```elixir
defp add_comprehension_body_triple(triples, _expr_iri, nil, _expression_builder, _build_expressions?, _context, _containing_function, _index), do: triples

defp add_comprehension_body_triple(triples, expr_iri, %Comprehension{} = body_comprehension, expression_builder, build_expressions?, context, containing_function, comprehension_index) do
  if build_expressions? do
    # Nested comprehension - recursively build it with updated index
    nested_index = comprehension_index * 100 + 99
    {body_iri, body_triples} = build_comprehension(body_comprehension, context, containing_function: containing_function, index: nested_index, expression_builder: expression_builder)
    link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), body_iri)
    body_triples ++ [link_triple | triples]
  else
    triples
  end
end

defp add_comprehension_body_triple(triples, expr_iri, body, expression_builder, build_expressions?, context, containing_function, comprehension_index) do
  # Generic body handling (unchanged)
  ...
end
```

**Key design decisions:**
1. Pattern matching with `%Comprehension{}` struct before generic clause
2. Recursive call to `build_comprehension/3` preserves full comprehension structure
3. Index calculation: `comprehension_index * 100 + 99` maintains IRI hierarchy
4. Light mode (when `build_expressions?` is false) returns triples unchanged

---

## Implementation Tasks

- [x] Analyze the limitation in `add_comprehension_body_triple`
- [x] Add pattern matching clause for `%Comprehension{}` struct
- [x] Implement recursive call to `build_comprehension/3`
- [x] Update existing nested comprehension test to verify fix
- [x] Add test for deeply nested comprehensions (3 levels)
- [x] Run all tests to verify nothing broke
- [x] Create planning document
- [ ] Create summary document
- [ ] Ask for commit and merge permission

---

## Success Criteria

- [x] Nested comprehensions are extracted as `ForComprehension` types
- [x] Deeply nested comprehensions (3+ levels) work correctly
- [x] All unit tests pass (134 tests)
- [x] Light mode remains unchanged (backward compatibility)
- [x] No breaking changes to existing functionality

---

## Test Results

### Before Fix
- Nested comprehension in body: Inner comprehension NOT extracted as `ForComprehension`

### After Fix
- Nested comprehension in body: Inner comprehension IS extracted as `ForComprehension`
- Deeply nested comprehensions (3 levels): All levels extracted as `ForComprehension`
- **134 tests, 0 failures** (was 133 before adding 3-level nested test)

### Tests Added/Modified

1. **Modified:** "handles nested list comprehension in body"
   - Now verifies inner comprehension is a `ForComprehension` type
   - Verifies inner comprehension has its own generator

2. **Added:** "handles deeply nested comprehensions (3 levels)"
   - Tests 3 levels of nesting: outer → middle → innermost
   - Verifies all three levels are extracted as `ForComprehension`
   - Verifies innermost comprehension has its own generator

---

## Current Status

**Status:** ✅ COMPLETE

**What was done:**
- Created feature branch `feature/fix-28-nested-comprehension-extraction`
- Analyzed the limitation in `add_comprehension_body_triple`
- Implemented fix with pattern matching for `%Comprehension{}` struct
- Added recursive call to `build_comprehension/3`
- Modified existing nested comprehension test to verify fix
- Added new test for deeply nested comprehensions (3 levels)
- All 134 tests passing

**Files Modified:**
- `lib/elixir_ontologies/builders/control_flow_builder.ex`
  - Lines 1566-1598: Added new function clause for nested comprehensions
- `test/elixir_ontologies/builders/control_flow_builder_test.exs`
  - Lines 2160-2175: Updated nested comprehension test
  - Lines 2177-2266: Added deeply nested comprehension test (3 levels)

---

*Last Updated:* 2026-01-16
*Branch:* feature/fix-28-nested-comprehension-extraction
*Status:* ✅ COMPLETE - Ready for commit and merge permission request
