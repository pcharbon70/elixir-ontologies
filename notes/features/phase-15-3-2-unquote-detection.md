# Phase 15.3.2: Unquote Detection

## Overview

Enhance the Quote extractor's unquote detection to track nesting depth for nested quote/unquote scenarios and add convenience helper functions.

## Current State

The Quote extractor (`lib/elixir_ontologies/extractors/quote.ex`) already has:
- `UnquoteExpression` struct with fields: `kind`, `value`, `location`, `metadata`
- `find_unquotes/1` to find all unquote/unquote_splicing in AST
- Detection functions: `unquote?/1`, `unquote_splicing?/1`
- Does not descend into nested quote blocks

## Requirements from Phase Plan

From `notes/planning/extractors/phase-15.md`:
- 15.3.2.1 Implement `extract_unquotes/1` finding all unquote calls in AST
- 15.3.2.2 Extract unquoted expression for each unquote call
- 15.3.2.3 Detect `unquote_splicing` calls
- 15.3.2.4 Track unquote nesting depth (for nested quotes)
- 15.3.2.5 Create `%Unquote{expression: ..., splicing: boolean(), depth: ...}` struct
- 15.3.2.6 Add unquote detection tests

## Analysis

Most functionality exists. The key enhancement is **depth tracking** for nested quotes:

```elixir
quote do
  quote do
    unquote(x)      # depth 2 (inside 2 quotes)
  end
  unquote(y)        # depth 1 (inside 1 quote)
end
```

The `find_unquotes/1` currently doesn't track depth and stops at nested quotes (correct for single-level extraction). For depth tracking, we need to:
1. Add `depth` field to `UnquoteExpression`
2. Track quote nesting as we traverse
3. Add convenience helpers like `splicing?/1`, `nested?/1`

## Technical Design

### UnquoteExpression Enhancement

```elixir
defmodule UnquoteExpression do
  @type t :: %__MODULE__{
    kind: :unquote | :unquote_splicing,
    value: Macro.t(),
    depth: non_neg_integer(),
    location: SourceLocation.t() | nil,
    metadata: map()
  }

  defstruct [
    :kind,
    :value,
    :location,
    depth: 1,
    metadata: %{}
  ]
end
```

### New Helper Functions

On `UnquoteExpression`:
- `splicing?/1` - Check if this is unquote_splicing
- `nested?/1` - Check if depth > 1
- `at_depth?/2` - Check if at specific depth

On `Quote` module:
- `extract_unquotes/1` - Alias for find_unquotes for clearer naming
- `find_unquotes_at_depth/2` - Filter by depth
- `max_unquote_depth/1` - Get deepest nesting level

### Depth Tracking Logic

The `do_find_unquotes/2` becomes `do_find_unquotes/3`:
```elixir
defp do_find_unquotes(ast, acc, depth \\ 1)

# When entering a quote, increment depth but continue traversing
defp do_find_unquotes({:quote, _, _} = node, acc, depth) do
  # Extract body and continue with depth + 1
  ...
end
```

## Implementation Plan

### Step 1: Update UnquoteExpression Struct
- [x] Add `depth` field with default of 1
- [x] Update type spec

### Step 2: Add UnquoteExpression Helpers
- [x] Add `splicing?/1`
- [x] Add `nested?/1`
- [x] Add `at_depth?/2`

### Step 3: Update find_unquotes for Depth Tracking
- [x] Change `do_find_unquotes/2` to track depth
- [x] Continue into nested quotes with incremented depth
- [x] Set depth on each UnquoteExpression

### Step 4: Add Quote Module Helpers
- [x] Add `extract_unquotes/1` as alias
- [x] Add `find_unquotes_at_depth/2`
- [x] Add `max_unquote_depth/1`
- [x] Add `has_nested_unquotes?/1`
- [x] Add `count_unquotes_by_kind/1`

### Step 5: Write Tests
- [x] Test single-level unquote depth
- [x] Test nested quote/unquote depth
- [x] Test unquote_splicing depth
- [x] Test helper functions
- [x] Test edge cases (deeply nested)

## Success Criteria

- [x] UnquoteExpression has depth field
- [x] Depth correctly tracked for nested quotes
- [x] Helper functions work correctly
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes

## Notes

- Backward compatibility: depth defaults to 1, so existing code works
- The current find_unquotes stops at nested quotes; new version descends with depth tracking
- Depth 0 would mean outside all quotes (not applicable in practice)
