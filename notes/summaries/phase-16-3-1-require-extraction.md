# Phase 16.3.1: Require Extraction - Summary

## Completed

Implemented extraction of require directives which make a module's macros available at compile time.

## Changes Made

### New Module: Require Extractor

Created `lib/elixir_ontologies/extractors/directive/require.ex`:

```elixir
defmodule RequireDirective do
  @type t :: %__MODULE__{
          module: [atom()] | atom(),
          as: atom() | nil,
          location: SourceLocation.t() | nil,
          scope: :module | :function | :block | nil,
          metadata: map()
        }

  defstruct [:module, :as, :location, :scope, metadata: %{}]
end
```

### Public Functions

- `require?/1` - Check if AST is a require directive
- `extract/2` - Extract single require directive
- `extract!/2` - Extract with raise on error
- `extract_all/2` - Extract all requires from module body
- `extract_all_with_scope/2` - Extract with scope tracking
- `module_name/1` - Get module as dot-separated string

### Supported Require Forms

- Basic: `require Logger`
- With as: `require Logger, as: L`
- Erlang modules: `require :ets`
- Multi-part: `require MyApp.Macros`

## Files Modified

- `lib/elixir_ontologies/extractors/directive/require.ex` (new)
- `test/elixir_ontologies/extractors/directive/require_test.exs` (new)
- `notes/planning/extractors/phase-16.md` - Marked 16.3.1 tasks complete
- `notes/features/phase-16-3-1-require-extraction.md` (new)

## Test Results

- 13 doctests, 33 tests, 0 failures
- `mix compile --warnings-as-errors` passes
- `mix credo --strict` passes (only refactoring suggestions)

## Notes

Task 16.3.1.5 "Track which macros become available via require" cannot be fully implemented without analyzing the required module. The require directive is extracted with all information needed to link to the module later.

## Next Task

**16.3.2 Use Extraction** - Implement extraction for use directives with their options.
