# Phase 16.3.2: Use Extraction - Summary

## Completed

Implemented extraction of use directives which invoke the `__using__/1` macro of a module, allowing modules to inject code at compile time.

## Changes Made

### New Module: Use Extractor

Created `lib/elixir_ontologies/extractors/directive/use.ex`:

```elixir
defmodule UseDirective do
  @type use_options :: keyword() | term() | nil

  @type t :: %__MODULE__{
          module: [atom()] | atom(),
          options: use_options(),
          location: SourceLocation.t() | nil,
          scope: :module | :function | :block | nil,
          metadata: map()
        }

  @enforce_keys [:module]
  defstruct [:module, :options, :location, :scope, metadata: %{}]
end
```

### Public Functions

- `use?/1` - Check if AST is a use directive
- `extract/2` - Extract single use directive
- `extract!/2` - Extract with raise on error
- `extract_all/2` - Extract all uses from module body
- `extract_all_with_scope/2` - Extract with scope tracking
- `module_name/1` - Get module as dot-separated string
- `has_options?/1` - Check if use has options
- `keyword_options?/1` - Check if options are keyword list

### Supported Use Forms

- Basic: `use GenServer`
- With keyword options: `use GenServer, restart: :temporary`
- With multiple options: `use Plug.Builder, init_mode: :runtime, log_on_halt: :debug`
- With non-keyword option: `use MyApp.Web, :controller`
- Erlang modules: `use :gen_server` (rare)

## Files Modified

- `lib/elixir_ontologies/extractors/directive/use.ex` (new)
- `test/elixir_ontologies/extractors/directive/use_test.exs` (new)
- `notes/planning/extractors/phase-16.md` - Marked 16.3.2 tasks complete
- `notes/features/phase-16-3-2-use-extraction.md` (new)

## Test Results

- 18 doctests, 46 tests, 0 failures
- `mix compile --warnings-as-errors` passes
- `mix credo --strict` passes (only refactoring suggestions)

## Notes

The `options` field supports both keyword lists and single values (atoms, strings, etc.) which are passed directly to the `__using__/1` callback of the target module.

## Next Task

**16.3.3 Use Option Analysis** - Analyze use options to understand configuration passed to `__using__` callbacks, including parsing keyword options and handling dynamic values.
