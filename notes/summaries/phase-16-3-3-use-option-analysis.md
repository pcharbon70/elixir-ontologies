# Phase 16.3.3: Use Option Analysis - Summary

## Completed

Implemented analysis of use directive options to understand configuration passed to `__using__` callbacks, including parsing keyword options and handling dynamic values.

## Changes Made

### New Struct: UseOption

Added `UseOption` struct to `lib/elixir_ontologies/extractors/directive/use.ex`:

```elixir
defmodule UseOption do
  @type value_type ::
          :atom | :string | :integer | :float | :boolean | :nil |
          :list | :tuple | :module | :dynamic

  @type t :: %__MODULE__{
          key: atom() | nil,
          value: term(),
          value_type: value_type(),
          dynamic: boolean(),
          raw_ast: Macro.t() | nil
        }

  defstruct [:key, :value, :value_type, :raw_ast, dynamic: false]
end
```

### New Public Functions

- `analyze_options/1` - Analyze options from UseDirective into UseOption list
- `parse_option/1` - Parse single keyword option tuple
- `dynamic_value?/1` - Check if AST value is dynamic (unresolvable)
- `value_type/1` - Determine type classification of a value
- `extract_literal_value/1` - Extract literal value if possible

### Value Type Classifications

Implemented detection for:
- **Literals**: `:atom`, `:string`, `:integer`, `:float`, `:boolean`, `:nil`
- **Compound**: `:list`, `:tuple`
- **References**: `:module` (for `{:__aliases__, _, parts}`)
- **Dynamic**: `:dynamic` (variables, function calls, unresolved AST)

### Dynamic Value Detection

Values marked as dynamic:
- Variable references: `{:some_var, [], Elixir}`
- Function calls: `{{:., [], [module, func]}, [], args}`
- Any AST node that can't be resolved at analysis time

## Files Modified

- `lib/elixir_ontologies/extractors/directive/use.ex` - Added UseOption struct and analysis functions
- `test/elixir_ontologies/extractors/directive/use_test.exs` - Added 48 new tests
- `notes/planning/extractors/phase-16.md` - Marked 16.3.3 tasks complete
- `notes/features/phase-16-3-3-use-option-analysis.md` (new)

## Test Results

- 40 doctests, 94 tests, 0 failures
- `mix compile --warnings-as-errors` passes
- `mix credo --strict` passes (only refactoring suggestions)

## Usage Examples

```elixir
# Analyze keyword options
directive = %UseDirective{
  module: [:GenServer],
  options: [restart: :temporary, max_restarts: 3]
}
options = Use.analyze_options(directive)
# => [%UseOption{key: :restart, value: :temporary, value_type: :atom, dynamic: false},
#     %UseOption{key: :max_restarts, value: 3, value_type: :integer, dynamic: false}]

# Analyze dynamic option
directive = %UseDirective{
  module: [:GenServer],
  options: [restart: {:some_var, [], Elixir}]
}
[option] = Use.analyze_options(directive)
# => %UseOption{key: :restart, value_type: :dynamic, dynamic: true, raw_ast: {...}}
```

## Next Task

**16.4.1 Dependency Graph Builder** - Generate RDF triples representing module dependencies from directives.
