# Phase 22.7: Tuple Literal Extraction - Summary

**Status:** ✅ Complete
**Branch:** `feature/phase-22-7-tuple-literals`
**Date:** 2025-01-10

## Overview

Section 22.7 of the expressions plan covers tuple literal extraction. This phase implemented extraction for tuples of all sizes (empty, 2-tuple, 3+ tuples), including nested and heterogeneous tuples.

## Key Findings

### Elixir AST Behavior for Tuples

| Source Code | AST Representation | Current Handling |
|-------------|-------------------|------------------|
| `{}` | `{:{}, [], []}` | ✅ TupleLiteral |
| `{1, 2}` | `{1, 2}` | ✅ TupleLiteral (2-tuple) |
| `{1, 2, 3}` | `{:{}, [], [1, 2, 3]}` | ✅ TupleLiteral (3-tuple) |
| `{1, 2, 3, 4}` | `{:{}, [], [1, 2, 3, 4]}` | ✅ TupleLiteral (4+ tuple) |
| `{{1, 2}, {3, 4}}` | `{{1, 2}, {3, 4}}` | ✅ TupleLiteral (nested) |
| `{1, "two", :three}` | `{:{}, [], [1, "two", :three]}` | ✅ TupleLiteral (heterogeneous) |
| `{:ok, 42}` | `{:ok, 42}` | ✅ TupleLiteral (tagged) |

### Key Design Decisions

**AST vs Literal Tuples:**
A critical discovery was that Elixir distinguishes between:
- **Literal tuples** like `{}` (0-tuple), `{1, 2}` (2-tuple) - runtime values
- **AST tuples** from `quote do: {}` which transform to `{:{}, [], []}` format

Tests must use `quote do: ...` to get proper AST representation, not pass literal tuples directly.

**2-Tuple Special Case:**
The 2-tuple `{left, right}` is a special form in Elixir AST. Unlike 3+ tuples which use the `{:{}, meta, elements}` form, 2-tuples appear directly as 2-element tuples. This required:
1. Separate handler for `{:{}, meta, elements}` pattern (empty and 3+ tuples)
2. Separate handler for `{left, right}` pattern (2-tuples)

**Handler Ordering:**
Tuple handlers must come BEFORE the local call handler to avoid pattern matching conflicts. The local call pattern `{function, meta, args}` matches 3-tuples, while 2-tuple handler matches 2-tuples.

## Changes Made

### ExpressionBuilder Implementation

**File:** `lib/elixir_ontologies/builders/expression_builder.ex`

1. **Added tuple handlers** (lines 367-376):
   - Handler for `{:{}, _meta, elements}` pattern - empty and 3+ tuples
   - Handler for `{left, right}` pattern - 2-tuples
   - Placed before local call handler to ensure correct matching order

2. **Added `build_tuple_literal/3` helper** (lines 648-665):
   - Creates TupleLiteral type triple
   - Recursively extracts child expressions
   - Returns all triples (type + children)

### Test Changes

**File:** `test/elixir_ontologies/builders/expression_builder_test.exs`

1. **Added 8 new tests for tuple literals:**
   - Empty tuple behavior
   - 2-tuple behavior
   - 3-tuple behavior
   - 4+ tuple behavior
   - Nested tuples
   - Heterogeneous tuples
   - Tagged tuples (first element is atom)
   - Child expression extraction verification

2. **Updated 1 existing test:**
   - "unknown expressions" test that used 2-element tuple as unusual AST
   - Changed to use 4-element tuple instead (which truly doesn't match any pattern)

## Test Results

- **ExpressionBuilder tests:** 124 tests (up from 116), 0 failures
- **Full test suite:** 7156 tests (up from 7148), 0 failures, 361 excluded

## Notes

### Quote vs Literal

A significant issue discovered during testing: tests passing literal tuples (e.g., `ExpressionBuilder.build({}, context, [])`) were not matching the tuple handlers because:
- Literal `{}` is a 0-tuple
- AST `{}` (from `quote do: {}`) is a 3-tuple `{:{}, [], []}`

All tuple tests were updated to use `quote do: ...` to get proper AST representation.

### Useless Guard

Initially added a guard `when is_tuple({left, right})` to the 2-tuple handler. This guard is meaningless because `{left, right}` is a tuple literal, so `is_tuple({left, right})` is always `true`. The guard was removed.

### Child Expression Linking

Tuple elements are extracted recursively and included as child triples. The `hasChild` property exists in the ontology but is not currently used to link tuple elements. Order is implicitly preserved by the sequence of child expression extraction.

## Files Modified

1. `lib/elixir_ontologies/builders/expression_builder.ex` - Added tuple handlers and build_tuple_literal helper
2. `test/elixir_ontologies/builders/expression_builder_test.exs` - Added 8 new tests, updated 1 old test
3. `notes/features/phase-22-7-tuple-literals.md` - Planning document
4. `notes/summaries/phase-22-7-tuple-literals.md` - This summary document

## Next Steps

Phase 22.7 is complete and ready to merge into the `expressions` branch. The tuple literal extraction for all tuple sizes is functional with comprehensive test coverage.
