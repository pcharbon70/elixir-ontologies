# Feature: Phase 14.2.4 - Tuple Types Enhancement

## Problem Statement

Task 14.2.4 from the Phase 14 plan calls for extracting tuple types with specific element types. The existing `TypeExpression` extractor already handles tuple parsing comprehensively, including tagged tuples. This task adds helper functions for tuple introspection and additional tests for edge cases.

**Current Implementation:**
- Empty tuple `{}` detected with `arity: 0`
- N-tuples (3+) detected via `{:{}, _, elements}` pattern
- 2-tuples detected via `{left, right}` pattern
- Tagged 2-tuples detected with `tagged: true` and `tag` metadata
- `tuple?/1` helper exists
- `arity` stored in metadata

**What's Missing:**
1. `tuple_arity/1` helper for getting tuple arity
2. `tuple_elements/1` helper for getting element types
3. `tagged_tuple?/1` helper for detecting tagged tuples
4. `tuple_tag/1` helper for getting the tag from tagged tuples
5. Additional tests for complex tuple scenarios

## Solution Overview

Add helper functions for tuple introspection and comprehensive tests for all tuple type scenarios.

## Technical Details

### File Locations
- **Extractor**: `lib/elixir_ontologies/extractors/type_expression.ex`
- **Tests**: `test/elixir_ontologies/extractors/type_expression_test.exs`

### Existing Tuple Type Implementation

The current implementation already handles:

```elixir
# Empty tuple
defp do_parse({:{}, _, []} = ast) do
  %__MODULE__{kind: :tuple, elements: [], ast: ast, metadata: %{arity: 0}}
end

# N-tuple (3 or more elements)
defp do_parse({:{}, _, elements} = ast) when is_list(elements) do
  %__MODULE__{kind: :tuple, elements: Enum.map(elements, &do_parse/1), ast: ast, metadata: %{arity: length(elements)}}
end

# 2-tuple
defp do_parse({left, right} = ast) when not is_list(right) and not is_atom(left) do
  %__MODULE__{kind: :tuple, elements: [do_parse(left), do_parse(right)], ast: ast, metadata: %{arity: 2}}
end

# Tagged 2-tuple like {:ok, term()}
defp do_parse({tag, right} = ast) when is_atom(tag) and not is_list(right) do
  %__MODULE__{kind: :tuple, elements: [do_parse(tag), do_parse(right)], ast: ast, metadata: %{arity: 2, tagged: true, tag: tag}}
end
```

### Proposed Helper Functions

1. `tuple_arity/1`:
```elixir
@spec tuple_arity(t()) :: non_neg_integer() | nil
def tuple_arity(%__MODULE__{kind: :tuple, metadata: %{arity: arity}}), do: arity
def tuple_arity(_), do: nil
```

2. `tuple_elements/1`:
```elixir
@spec tuple_elements(t()) :: [t()] | nil
def tuple_elements(%__MODULE__{kind: :tuple, elements: elements}), do: elements
def tuple_elements(_), do: nil
```

3. `tagged_tuple?/1`:
```elixir
@spec tagged_tuple?(t()) :: boolean()
def tagged_tuple?(%__MODULE__{kind: :tuple, metadata: %{tagged: true}}), do: true
def tagged_tuple?(_), do: false
```

4. `tuple_tag/1`:
```elixir
@spec tuple_tag(t()) :: atom() | nil
def tuple_tag(%__MODULE__{kind: :tuple, metadata: %{tag: tag}}), do: tag
def tuple_tag(_), do: nil
```

## Success Criteria

- [ ] `tuple_arity/1` returns the tuple arity
- [ ] `tuple_elements/1` returns the list of element types
- [ ] `tagged_tuple?/1` detects tagged tuples
- [ ] `tuple_tag/1` returns the tag from tagged tuples
- [ ] Tests for all tuple type scenarios
- [ ] Tests for nested tuples
- [ ] Tests for tuples with complex element types
- [ ] All existing tests continue to pass

## Implementation Plan

### Step 1: Add `tuple_arity/1` Helper Function
Add helper to get tuple arity from metadata.

### Step 2: Add `tuple_elements/1` Helper Function
Add helper to get element type expressions.

### Step 3: Add `tagged_tuple?/1` Helper Function
Add helper to detect tagged tuples.

### Step 4: Add `tuple_tag/1` Helper Function
Add helper to get the tag from tagged tuples.

### Step 5: Add Comprehensive Tests
Add tests for all tuple type scenarios including edge cases.

## Current Status

- **Branch**: `feature/phase-14-2-4-tuple-types`
- **Status**: Planning complete
- **How to run**: `mix test test/elixir_ontologies/extractors/type_expression_test.exs`

## Notes

- Tuple parsing is already comprehensive
- Focus is on adding introspection helpers
- Tagged tuples are a common Elixir pattern (`{:ok, value}`, `{:error, reason}`)
- The generic `tuple()` type is handled as a basic type with `kind: :basic`
