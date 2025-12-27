# Phase 15.1.2: Custom Macro Invocation

## Problem Statement

Task 15.1.1 implemented detection of Kernel macros, but codebases also use custom macros from:
- External libraries (Logger, Ecto, Phoenix, etc.)
- Local project modules
- Imported/required macros

Without tracking these, we miss a significant portion of metaprogramming usage.

**Impact**: Custom macro tracking enables:
- Complete macro usage analysis across a codebase
- Dependency tracking for macros from external libraries
- Understanding of import/require patterns
- Linking macro invocations to their definitions

## Solution Overview

Extend the `MacroInvocation` extractor to:
1. Detect qualified macro calls (e.g., `Logger.debug`, `Ecto.Query.from`)
2. Track `import` statements to identify imported macros
3. Track `require` statements to identify required macros
4. Attempt to resolve macro module when call is unqualified but imported/required
5. Mark unresolved calls for later cross-module analysis

## Technical Details

### Files to Modify
- **Modify**: `lib/elixir_ontologies/extractors/macro_invocation.ex`
- **Modify**: `test/elixir_ontologies/extractors/macro_invocation_test.exs`
- **Modify**: `notes/planning/extractors/phase-15.md` (mark task complete)

### Key Custom Macro Patterns

**Qualified calls** (module.macro form):
```elixir
Logger.debug("message")          # Logger.debug/1
Ecto.Query.from(u in User, ...)  # Ecto.Query.from/2
Phoenix.Component.attr(:name, :string)
```

**Imported macros**:
```elixir
import Logger
debug("message")  # Should resolve to Logger.debug
```

**Required macros**:
```elixir
require Logger
Logger.debug("message")  # Logger must be required for compile-time macros
```

### Struct Changes

Add new fields to `%MacroInvocation{}`:
```elixir
defstruct [
  # ... existing fields ...
  :resolution_status,  # :resolved | :unresolved | :kernel
  :import_info,        # %{module: ..., only: [...]} if imported
  :require_info        # %{module: ...} if required
]
```

## Implementation Plan

### Step 1: Add Qualified Macro Call Detection
- [x] Detect `{{:., _, [module, name]}, _, args}` pattern
- [x] Extract module from `{:__aliases__, _, parts}` or atom
- [x] Create `qualified_call?/1` function
- [x] Update `macro_invocation?/1` to detect qualified calls

### Step 2: Track Import Statements
- [x] Create `import_info` type
- [x] Implement `extract_imports/1` for module body
- [x] Handle `import Module, only: [...]` filtering
- [x] Handle `import Module, except: [...]` filtering

### Step 3: Track Require Statements
- [x] Create `require_info` type
- [x] Implement `extract_requires/1` for module body
- [x] Handle `require Module, as: Alias` form

### Step 4: Resolution Status
- [x] Add `resolution_status` field (:resolved, :unresolved, :kernel)
- [x] Qualified calls set as `:resolved`
- [x] Kernel macros set as `:kernel`

### Step 5: Handle Unresolved Calls
- [x] Add `unresolved?/1` predicate
- [x] Add `filter_unresolved/1` helper
- [x] Provide `resolved?/1` predicate

### Step 6: Write Tests
- [x] Test qualified macro call detection
- [x] Test import tracking with only/except
- [x] Test require tracking
- [x] Test resolution status
- [x] Test unresolved call handling
- [x] Test common library macros (Logger, Ecto)

## Success Criteria

- [x] All subtasks in phase-15.md marked complete
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
- [x] All tests pass (160 tests: 48 doctests + 112 unit tests)
- [x] Detection covers qualified and imported macro calls

## Notes

- Known library macros (Logger, Ecto) can be pre-registered for better detection
- Resolution is best-effort since full module resolution requires compilation
- Cross-module linking is deferred to builder phase
