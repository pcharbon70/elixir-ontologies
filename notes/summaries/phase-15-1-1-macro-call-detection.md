# Phase 15.1.1: Macro Call Detection - Summary

## Overview

Implemented a new `MacroInvocation` extractor that detects and extracts macro invocations from Elixir AST. This enables tracking of macro usage in module bodies, distinguishing macro calls from regular function calls.

## Changes Made

### New Files

1. **`lib/elixir_ontologies/extractors/macro_invocation.ex`** (480 LOC)
   - Defines `%MacroInvocation{}` struct with fields: `macro_module`, `macro_name`, `arity`, `arguments`, `category`, `location`, `metadata`
   - Implements detection for 40+ Kernel macros organized into categories:
     - **Definition macros**: `def`, `defp`, `defmacro`, `defmodule`, `defstruct`, etc.
     - **Control flow macros**: `if`, `unless`, `case`, `cond`, `with`, `for`, `try`, `receive`, etc.
     - **Import macros**: `import`, `require`, `use`, `alias`
     - **Quote macros**: `quote`, `unquote`, `unquote_splicing`
     - **Attribute macro**: `@` for module attributes
     - **Other macros**: `and`, `or`, `in`, `binding`, `var!`, sigils, etc.
   - Key functions:
     - `macro_invocation?/1` - predicate to check if AST is a macro invocation
     - `kernel_macro?/1` - predicate to check if a name is a Kernel macro
     - `extract/2` - extract single macro invocation
     - `extract_all/2` - shallow extraction from module body
     - `extract_all_recursive/2` - deep extraction traversing entire AST
   - Helper predicates: `definition?/1`, `control_flow?/1`, `import?/1`, `attribute?/1`

2. **`test/elixir_ontologies/extractors/macro_invocation_test.exs`** (450 LOC)
   - 76 unit tests + 32 doctests = 108 tests
   - Covers all macro categories
   - Tests location extraction
   - Tests bulk extraction (`extract_all`, `extract_all_recursive`)
   - Tests error handling

### Modified Files

- **`notes/planning/extractors/phase-15.md`** - Marked task 15.1.1 complete with all subtasks

## Test Results

```
108 tests, 0 failures
- 32 doctests
- 76 unit tests
```

## Verification

- `mix compile --warnings-as-errors`: Pass
- `mix credo --strict`: Pass (no issues)
- All tests pass

## Design Decisions

1. **Category-based classification**: Macros are categorized into `:definition`, `:control_flow`, `:import`, `:attribute`, `:quote`, and `:other` for easier filtering and analysis.

2. **Shallow vs recursive extraction**: Provided both `extract_all/2` (shallow, for module-level statements) and `extract_all_recursive/2` (deep, for complete AST traversal).

3. **Attribute metadata**: For `@` macro invocations, the attribute name (e.g., `:doc`, `:spec`) is stored in metadata.

4. **Qualified calls deferred**: Detection of qualified macro calls like `Kernel.if` is deferred to task 15.1.2 (Custom Macro Invocation).

## Next Steps

The next logical task is **15.1.2 Custom Macro Invocation**, which will:
- Detect non-Kernel macro calls
- Track imported macros via `import Module, only: [macro: arity]`
- Track required macros via `require Module`
- Link invocations to definitions when available
