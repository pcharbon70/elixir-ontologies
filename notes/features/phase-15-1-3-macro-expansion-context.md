# Phase 15.1.3: Macro Expansion Context

## Problem Statement

Task 15.1.1 and 15.1.2 implemented detection of macro invocations, but we don't capture the **expansion context** - where the macro expands and what information is available to it at compile time.

In Elixir macros, `__CALLER__` provides access to the caller's environment including:
- The module where the macro is being called
- The file and line number
- Function context if inside a function
- Aliases and imports in scope

**Impact**: Capturing expansion context enables:
- Understanding macro hygiene and variable scoping
- Tracking module dependencies at compile time
- Debugging macro expansion issues
- Building accurate code navigation for macros

## Solution Overview

Create a `MacroContext` struct that captures expansion context information:
1. Define `%MacroContext{}` struct with module, file, line, and function fields
2. Extract context from AST metadata where available
3. Associate context with macro invocations via the existing `metadata` field
4. Provide helper functions for context queries

## Technical Details

### Files to Modify
- **Modify**: `lib/elixir_ontologies/extractors/macro_invocation.ex`
- **Modify**: `test/elixir_ontologies/extractors/macro_invocation_test.exs`
- **Modify**: `notes/planning/extractors/phase-15.md` (mark task complete)

### MacroContext Struct

```elixir
defmodule ElixirOntologies.Extractors.MacroInvocation.MacroContext do
  defstruct [
    :module,        # Module where macro expands (atom)
    :file,          # File path (string)
    :line,          # Line number (integer)
    :function,      # Function context if any {name, arity} | nil
    :aliases,       # Aliases in scope (list of {alias, module})
  ]
end
```

### Context Sources

1. **From AST metadata**: `[line: n, column: c, file: "path"]`
2. **From module context**: When extracting within a known module
3. **From function context**: When extracting within a function body

### Design Decisions

- Context is **optional** - not all invocations will have complete context
- Context is stored in the invocation's `metadata` field under `:context` key
- Use `nil` for unknown/unavailable context fields
- Provide `extract_with_context/3` for context-aware extraction

## Implementation Plan

### Step 1: Define MacroContext Struct
- [x] Create `MacroContext` struct inside MacroInvocation module
- [x] Add typespec for context
- [x] Add constructor function

### Step 2: Extract Context from AST
- [x] Extract file from AST metadata when present
- [x] Extract line from AST metadata
- [x] Extract column from AST metadata

### Step 3: Context-Aware Extraction
- [x] Add `extract_with_context/2` function
- [x] Accept module and function context as options
- [x] Populate context in invocation metadata

### Step 4: Context Helpers
- [x] Add `has_context?/1` predicate
- [x] Add `get_context/1` accessor
- [x] Add `context_module/1` helper
- [x] Add `context_file/1` helper
- [x] Add `context_line/1` helper
- [x] Add `context_function/1` helper

### Step 5: Write Tests
- [x] Test MacroContext struct creation
- [x] Test context extraction from AST
- [x] Test context-aware extraction
- [x] Test context helpers
- [x] Test invocations without context

## Success Criteria

- [x] All subtasks in phase-15.md marked complete
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
- [x] All tests pass
- [x] Context extraction works for macro invocations

## Notes

- Full `__CALLER__` information requires runtime access - we capture what's available statically
- File paths in AST metadata may be relative or absolute depending on compilation
- Function context tracking requires parent AST traversal
