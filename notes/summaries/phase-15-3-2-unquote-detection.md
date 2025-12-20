# Phase 15.3.2: Unquote Detection - Summary

## Overview

Enhanced the Quote extractor with depth tracking for unquote expressions and added helper functions for analyzing unquotes in nested quote scenarios.

## Changes Made

### UnquoteExpression Struct Enhancement

Added `depth` field to `lib/elixir_ontologies/extractors/quote.ex`:

```elixir
defmodule UnquoteExpression do
  @type t :: %__MODULE__{
    kind: :unquote | :unquote_splicing,
    value: Macro.t(),
    depth: pos_integer(),
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

### UnquoteExpression Helper Functions

- `splicing?/1` - Check if this is an unquote_splicing expression
- `nested?/1` - Check if this unquote is nested (depth > 1)
- `at_depth?/2` - Check if at a specific depth

### Updated find_unquotes/2

- Now tracks nesting depth when descending into nested quote blocks
- Accepts `:depth` option to set starting depth
- Accepts `:descend_into_quotes` option (default: true)
- Automatically detects if starting on a quote node and adjusts starting depth

### New Quote Module Functions

- `extract_unquotes/1` - Alias for find_unquotes for clearer naming
- `find_unquotes_at_depth/2` - Filter unquotes by specific depth
- `max_unquote_depth/1` - Get deepest nesting level
- `has_nested_unquotes?/1` - Check if any unquotes have depth > 1
- `count_unquotes_by_kind/1` - Count :unquote vs :unquote_splicing

## Depth Tracking Logic

When traversing nested quotes, depth increments at each quote boundary:

```elixir
quote do                    # depth 0 -> 1
  unquote(a)                # found at depth 1
  quote do                  # depth 1 -> 2
    unquote(b)              # found at depth 2
    quote do                # depth 2 -> 3
      unquote(c)            # found at depth 3
    end
  end
end
```

## Test Results

- 47 doctests + 103 unit tests = 150 tests passing
- `mix compile --warnings-as-errors` passes
- `mix credo --strict` passes

## Files Modified

- `lib/elixir_ontologies/extractors/quote.ex` - Added depth tracking and helpers (~120 lines added)
- `test/elixir_ontologies/extractors/quote_test.exs` - Added comprehensive tests (~100 lines added)
- `notes/planning/extractors/phase-15.md` - Marked task 15.3.2 complete
- `notes/features/phase-15-3-2-unquote-detection.md` - Planning document

## Backward Compatibility

The change is backward compatible:
- `depth` field defaults to 1
- `find_unquotes/1` continues to work, now with depth tracking
- Existing code accessing unquotes will still work

## Next Task

The next logical task is **Phase 15.3.3: Macro Hygiene Analysis** which will:
- Detect `var!/1` and `var!/2` usage in quote blocks
- Track unhygienic variable introductions
- Detect `Macro.escape/1` usage
- Track context parameter manipulation
- Create `%HygieneViolation{variable: ..., context: ...}` struct
