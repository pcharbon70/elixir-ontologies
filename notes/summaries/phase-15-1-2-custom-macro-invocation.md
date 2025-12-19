# Phase 15.1.2: Custom Macro Invocation - Summary

## Overview

Extended the `MacroInvocation` extractor to detect custom macro invocations from libraries and user-defined modules, track import/require statements, and support resolution status tracking.

## Changes Made

### Modified Files

**`lib/elixir_ontologies/extractors/macro_invocation.ex`** (+220 lines)

1. **New Struct Fields**:
   - `resolution_status`: `:resolved | :unresolved | :kernel`
   - Added `import_info` and `require_info` types

2. **Known Library Macros**:
   - Logger macros: `debug`, `info`, `warning`, `error`, etc.
   - Ecto.Query macros: `from`, `where`, `select`, `join`, etc.
   - Phoenix macros: `get`, `post`, `resources`, `scope`, etc.
   - ExUnit macros: `test`, `describe`, `assert`, etc.

3. **Qualified Call Detection**:
   - `qualified_call?/1` - Detects `Module.function` form
   - `extract/2` now handles `{{:., _, [module, name]}, _, args}` pattern
   - Automatic categorization as `:library` or `:custom`

4. **Import/Require Tracking**:
   - `extract_imports/1` - Extracts import statements with only/except filters
   - `extract_requires/1` - Extracts require statements with optional alias

5. **Resolution Helpers**:
   - `resolved?/1` - Returns true for resolved or kernel macros
   - `unresolved?/1` - Returns true for unresolved macros
   - `qualified?/1` - Returns true for qualified calls
   - `library?/1` - Returns true for known library macros
   - `filter_unresolved/1` - Filters list to unresolved only

6. **Classification Functions**:
   - `known_library_macros/0` - Returns module->macros map
   - `known_library_macro?/1` - Checks if name is a library macro
   - `logger_macros/0`, `ecto_query_macros/0` - Specific macro lists

**`test/elixir_ontologies/extractors/macro_invocation_test.exs`** (+335 lines)

Added comprehensive test suites:
- Qualified call detection tests
- Library macro classification tests
- Import/require extraction tests
- Resolution status tests
- Qualified and library predicate tests
- Recursive extraction with qualified calls

## Test Results

```
160 tests, 0 failures
- 48 doctests
- 112 unit tests
```

## Verification

- `mix compile --warnings-as-errors`: Pass
- `mix credo --strict`: Pass (no issues)
- All tests pass

## Key Design Decisions

1. **Category Extension**: Added `:library` and `:custom` categories to distinguish known library macros from user-defined ones.

2. **Resolution Status**: Three states - `:kernel` (Kernel macros), `:resolved` (qualified calls), `:unresolved` (unknown module).

3. **Pre-registered Library Macros**: Common macros from Logger, Ecto.Query, Phoenix.Router, and ExUnit.Case are recognized automatically.

4. **Import/Require Extraction**: Separate functions allow tracking of module dependencies for macro resolution context.

## Usage Examples

```elixir
# Detect qualified macro call
ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [], ["msg"]}
{:ok, inv} = MacroInvocation.extract(ast)
inv.macro_module  # => Logger
inv.category      # => :library
inv.resolution_status  # => :resolved

# Extract imports from module body
imports = MacroInvocation.extract_imports(module_body)
# => [%{module: Enum, only: [map: 2], except: nil, location: ...}]

# Filter unresolved calls
unresolved = MacroInvocation.filter_unresolved(invocations)
```

## Next Steps

The next logical task is **15.1.3 Macro Expansion Context**, which will:
- Extract `__CALLER__` context information
- Track expansion module, file, and line
- Create `%MacroContext{}` struct
- Associate context with macro invocations
