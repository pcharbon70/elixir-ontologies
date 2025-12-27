# Feature: Phase 14.1.1 - Union and Intersection Types

## Problem Statement

Task 14.1.1 from the Phase 14 plan calls for implementing union type extraction in the TypeExpression extractor. Upon review, the core union type extraction is **already implemented** in `lib/elixir_ontologies/extractors/type_expression.ex`:

- Union type detection via `{:|, _, [left, right]}` pattern matching
- Nested union flattening via `flatten_union/1` helper
- `%TypeExpression{kind: :union, elements: [...]}` struct variant
- Comprehensive test coverage in `type_expression_test.exs`

**Gap Identified**: The only missing feature from the subtasks is **position tracking** for each union member (subtask 14.1.1.4).

## Solution Overview

Enhance the existing union type extraction to include position information for each union member:
1. Add `position` field to union member metadata
2. Track the ordinal position of each type in the flattened union
3. Add additional tests for position tracking
4. Ensure complex nested unions preserve position information

## Technical Details

### File Locations
- **Extractor**: `lib/elixir_ontologies/extractors/type_expression.ex`
- **Tests**: `test/elixir_ontologies/extractors/type_expression_test.exs`

### Current Implementation Analysis

```elixir
# Current union parsing (lines 205-214)
defp do_parse({:|, _, [_left, _right]} = ast) do
  elements = flatten_union(ast)

  %__MODULE__{
    kind: :union,
    elements: Enum.map(elements, &do_parse/1),
    ast: ast,
    metadata: %{element_count: length(elements)}
  }
end

# Current flattening (lines 621-625)
defp flatten_union({:|, _, [left, right]}) do
  flatten_union(left) ++ flatten_union(right)
end

defp flatten_union(type), do: [type]
```

### Enhancement Required

Add position tracking to each parsed element:

```elixir
defp do_parse({:|, _, [_left, _right]} = ast) do
  elements = flatten_union(ast)

  parsed_elements =
    elements
    |> Enum.with_index()
    |> Enum.map(fn {element, index} ->
      parsed = do_parse(element)
      %{parsed | metadata: Map.put(parsed.metadata, :union_position, index)}
    end)

  %__MODULE__{
    kind: :union,
    elements: parsed_elements,
    ast: ast,
    metadata: %{element_count: length(elements)}
  }
end
```

## Success Criteria

- [x] Union type detection works correctly
- [x] Nested unions are flattened into single union
- [ ] Each union member has `union_position` in metadata
- [ ] Tests verify position tracking for simple unions
- [ ] Tests verify position tracking for nested unions
- [ ] All existing tests continue to pass

## Implementation Plan

### Step 1: Add Position Tracking ✅
Update `do_parse/1` for union types to track position of each element.
- Added `union_position` field to metadata for each union member
- Implemented using `Enum.with_index/1` in the union parsing code

### Step 2: Add Position Tests ✅
Add tests for union member position tracking.
- Added 3 new tests:
  - "union members have position tracking"
  - "nested union members have correct positions after flattening"
  - "union with 5+ members preserves all positions"

### Step 3: Verify All Tests Pass ✅
Run test suite to ensure no regressions.
- All 90 tests pass (22 doctests + 68 tests)

### Step 4: Update Phase Plan ✅
Mark task 14.1.1 as complete in `notes/planning/extractors/phase-14.md`.

## Current Status

- **Branch**: `feature/phase-14-1-1-union-types`
- **What works**:
  - Core union extraction with `{:|, _, [left, right]}` pattern
  - Nested union flattening via `flatten_union/1`
  - Position tracking for all union members (`union_position` in metadata)
  - All existing and new tests pass
- **Complete**: Feature implementation is done
- **How to run**: `mix test test/elixir_ontologies/extractors/type_expression_test.exs`

## Notes

- Intersection types are not part of Elixir's type system (they exist in TypeScript/other languages)
- The plan mentioned "intersection types" but Elixir only has union types in typespecs
- We should update the plan to reflect this - intersection types are not applicable
