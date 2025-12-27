# Summary: Phase 14.2.4 - Tuple Types Enhancement

## Overview

Task 14.2.4 enhances tuple type handling in the TypeExpression extractor. The existing implementation already handled tuple parsing comprehensively (empty, 2-tuple, N-tuple, tagged tuples). This task added helper functions for tuple introspection and comprehensive tests for edge cases.

## Changes Made

### 1. Added `tuple_arity/1` Helper

Returns the arity of a tuple type:

```elixir
@spec tuple_arity(t()) :: non_neg_integer() | nil
def tuple_arity(%__MODULE__{kind: :tuple, metadata: %{arity: arity}}), do: arity
def tuple_arity(_), do: nil
```

### 2. Added `tuple_elements/1` Helper

Returns the element type expressions for a tuple:

```elixir
@spec tuple_elements(t()) :: [t()] | nil
def tuple_elements(%__MODULE__{kind: :tuple, elements: elements}), do: elements
def tuple_elements(_), do: nil
```

### 3. Added `tagged_tuple?/1` Helper

Detects tagged tuples like `{:ok, value}` or `{:error, reason}`:

```elixir
@spec tagged_tuple?(t()) :: boolean()
def tagged_tuple?(%__MODULE__{kind: :tuple, metadata: %{tagged: true}}), do: true
def tagged_tuple?(_), do: false
```

### 4. Added `tuple_tag/1` Helper

Returns the atom tag from tagged tuples:

```elixir
@spec tuple_tag(t()) :: atom() | nil
def tuple_tag(%__MODULE__{kind: :tuple, metadata: %{tag: tag}}), do: tag
def tuple_tag(_), do: nil
```

### 5. New Tests

Added 20 new tests in 2 describe blocks + 11 doctests:

**Tuple type parsing:**
- Nested tuple `{{atom(), integer()}, binary()}`
- Tuple with union element `{atom(), :ok | :error}`
- Tuple with remote type `{String.t(), integer()}`
- Tagged tuple with error tag `{:error, reason}`
- 4-tuple parsing
- Generic `tuple()` vs fixed-arity tuple distinction

**Tuple type helpers:**
- `tuple_arity/1` for 2-tuple, 3-tuple, empty tuple, non-tuple
- `tuple_elements/1` for tuple, empty tuple, non-tuple
- `tagged_tuple?/1` for tagged, untagged, non-tuple
- `tuple_tag/1` for :ok, :error, untagged, non-tuple

## Test Results

All 252 tests pass (73 doctests + 179 tests):
```
mix test test/elixir_ontologies/extractors/type_expression_test.exs
```

## Files Modified

1. `lib/elixir_ontologies/extractors/type_expression.ex`
   - Added `tuple_arity/1` helper function (3 doctests)
   - Added `tuple_elements/1` helper function (2 doctests)
   - Added `tagged_tuple?/1` helper function (3 doctests)
   - Added `tuple_tag/1` helper function (3 doctests)

2. `test/elixir_ontologies/extractors/type_expression_test.exs`
   - Added 7 new tests to "parse/1 tuple types" describe block
   - Added 13 new tests in "tuple type helpers" describe block

## New Public Functions

- `tuple_arity/1` - Get arity from tuple type
- `tuple_elements/1` - Get element types from tuple type
- `tagged_tuple?/1` - Detect tagged tuples
- `tuple_tag/1` - Get tag from tagged tuples

## Design Decisions

1. **Helper functions return `nil` for non-tuple types**: Consistent with other helpers in the module.

2. **Tagged tuples detected via metadata**: The existing parser already sets `tagged: true` and `tag: atom` in metadata for tagged tuples.

3. **Generic `tuple()` vs fixed-arity tuples**: Generic `tuple()` is `kind: :basic`, while fixed-arity tuples are `kind: :tuple`. This distinction is tested explicitly.

4. **Empty tuple returns empty list from `tuple_elements/1`**: Consistent with the elements field being an empty list for empty tuples.

## Section 14.2 Complete

With task 14.2.4 complete, all tasks in Section 14.2 (Special Type Forms) are now finished:
- 14.2.1 Function Types
- 14.2.2 Struct Types
- 14.2.3 Literal Types
- 14.2.4 Tuple Types

## Next Task

The next logical task is **14.3.1 Union Type Builder** in Section 14.3 (Type System Builder Enhancement). This task will generate RDF triples for union types using the `structure:UnionType` class and `hasUnionMember` property.
