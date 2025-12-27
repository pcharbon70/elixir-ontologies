# Phase 15.1.3: Macro Expansion Context - Summary

## Overview

Extended the `MacroInvocation` extractor to capture macro expansion context, tracking where macros expand (module, file, line) and the function context when inside a function body.

## Changes Made

### Modified Files

**`lib/elixir_ontologies/extractors/macro_invocation.ex`** (+165 lines)

1. **MacroContext Nested Module**:
   - New struct capturing expansion context
   - Fields: `module`, `file`, `line`, `function`, `aliases`
   - Functions: `new/1`, `from_meta/1`, `merge/2`, `populated?/1`
   - Full typespec and documentation

2. **Context-Aware Extraction Functions**:
   - `extract_with_context/2` - Extracts invocation with context
   - `extract_with_context!/2` - Bang version
   - `extract_all_recursive_with_context/2` - Recursive extraction with context
   - `build_context/2` - Private helper to construct context from AST metadata and options

3. **Context Helper Functions**:
   - `has_context?/1` - Checks if invocation has populated context
   - `get_context/1` - Returns the MacroContext or nil
   - `context_module/1` - Gets module from context
   - `context_file/1` - Gets file path from context
   - `context_line/1` - Gets line number from context
   - `context_function/1` - Gets function context `{name, arity}`

**`test/elixir_ontologies/extractors/macro_invocation_test.exs`** (+135 lines)

Added comprehensive test suites:
- MacroContext struct tests (8 tests)
- Context-aware extraction tests (5 tests)
- `extract_with_context!/2` tests (2 tests)
- `extract_all_recursive_with_context/2` tests (3 tests)
- Context helper function tests (17 tests)
- Context with qualified calls tests (1 test)

## Test Results

```
206 tests, 0 failures
- 61 doctests
- 145 unit tests
```

## Verification

- `mix compile --warnings-as-errors`: Pass
- `mix credo --strict`: Pass (no issues)
- All tests pass

## Key Design Decisions

1. **Nested Module**: MacroContext is defined as a nested module inside MacroInvocation for encapsulation and discoverability.

2. **Context in Metadata**: Context is stored in the invocation's `metadata` field under the `:context` key, keeping the main struct simple.

3. **Opt-in Context**: Context extraction is opt-in via `extract_with_context/2`. The existing `extract/2` function is unchanged for backward compatibility.

4. **AST + Options Merge**: Context is built by merging AST metadata (line, file) with provided options (module, function), allowing partial context to be specified.

5. **Empty Context Detection**: `has_context?/1` returns false for empty contexts (no fields populated), so callers can distinguish between "has context" and "has no context".

## Usage Examples

```elixir
# Basic context extraction
ast = {:if, [line: 10], [true, [do: :ok]]}
{:ok, inv} = MacroInvocation.extract_with_context(ast, module: MyModule)
MacroInvocation.context_module(inv)  # => MyModule
MacroInvocation.context_line(inv)    # => 10

# Recursive extraction with shared context
body = {:def, [line: 1], [{:foo, [], []}, [do: {:if, [line: 2], [true, [do: :ok]]}]]}
results = MacroInvocation.extract_all_recursive_with_context(body, module: MyMod)
# All invocations have context with module: MyMod and their respective line numbers

# Context for qualified calls
ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [line: 25], ["msg"]}
{:ok, inv} = MacroInvocation.extract_with_context(ast, function: {:log_it, 1})
MacroInvocation.context_function(inv)  # => {:log_it, 1}
```

## Implementation Notes

- Full `__CALLER__` information requires runtime access; we capture what's available statically from AST
- File paths in AST metadata may be relative or absolute depending on compilation
- Function context must be provided explicitly as it requires parent AST traversal
- Aliases are supported but typically need to be resolved from module context

## Next Steps

Section 15.1 (Macro Invocation Tracking) is now complete. The next logical section is **15.2 Module Attribute Values**, which will:
- Extract compile-time values assigned to module attributes
- Handle documentation content from @moduledoc, @doc, @typedoc
- Extract @compile, @on_definition, @before_compile values
