# Phase 15.1.1: Macro Call Detection

## Problem Statement

The current codebase extracts macro **definitions** (via `extractors/macro.ex`) but does not track macro **invocations** - the actual calls to macros within module bodies. This creates a gap in the ontology's ability to represent metaprogramming patterns.

**Impact**: Without macro invocation tracking, we cannot:
- Represent how modules use macros from Kernel, Logger, or custom modules
- Analyze metaprogramming dependencies between modules
- Track which standard library macros are used in a codebase
- Build complete call graphs that include compile-time constructs

## Solution Overview

Create a new `MacroInvocation` extractor that:
1. Detects calls to known macros (Kernel, standard library, custom)
2. Captures the call site location
3. Distinguishes macro invocations from regular function calls
4. Tracks the source module and arity of the invoked macro

## Technical Details

### Files to Create/Modify
- **Create**: `lib/elixir_ontologies/extractors/macro_invocation.ex`
- **Create**: `test/elixir_ontologies/extractors/macro_invocation_test.exs`
- **Modify**: `notes/planning/extractors/phase-15.md` (mark task complete)

### Struct Definition

```elixir
defstruct [
  :macro_module,    # Module containing the macro (e.g., Kernel, Logger)
  :macro_name,      # Macro name as atom
  :arity,           # Number of arguments
  :arguments,       # List of argument AST nodes
  :location,        # Source location
  :metadata         # Additional info (e.g., imported?, required?)
]
```

### Standard Library Macros to Detect

**Definition macros** (from Kernel):
- `defmodule`, `def`, `defp`, `defmacro`, `defmacrop`
- `defstruct`, `defexception`, `defdelegate`
- `defguard`, `defguardp`, `defprotocol`, `defimpl`
- `defoverridable`

**Control flow macros** (from Kernel):
- `if`, `unless`, `case`, `cond`, `with`
- `for`, `try`, `receive`, `raise`, `throw`
- `quote`, `unquote`, `unquote_splicing`

**Import/Require macros** (from Kernel):
- `import`, `require`, `use`, `alias`

**Other Kernel macros**:
- `@` (attribute), `|>`, `&&`, `||`, `!`
- `and`, `or`, `not`, `in`
- `binding`, `var!`, `match?`, `destructure`

## Implementation Plan

### Step 1: Create MacroInvocation Module
- [x] Create `lib/elixir_ontologies/extractors/macro_invocation.ex`
- [x] Add moduledoc with ontology mapping
- [x] Define `%MacroInvocation{}` struct with typespec

### Step 2: Implement Detection Functions
- [x] Implement `macro_invocation?/1` predicate
- [x] Implement `extract/2` for single invocation
- [x] Define `@kernel_macros` and `@definition_macros` lists

### Step 3: Implement Standard Library Detection
- [x] Create `extract_kernel_macro/1` for Kernel macros
- [x] Handle unqualified (`if`) forms
- [x] Track arity correctly for each macro

### Step 4: Implement Kernel Macro Categories
- [x] Create `@definition_macros` list
- [x] Create `@control_flow_macros` list
- [x] Create `@import_macros` list
- [x] Add category metadata to invocations

### Step 5: Track Call Site Locations
- [x] Extract line and column from AST metadata
- [x] Use `Helpers.extract_location/1` for consistency
- [x] Store location in invocation struct

### Step 6: Write Tests
- [x] Test detection of `def`/`defp` as macro invocations
- [x] Test detection of `if`/`unless`/`case`/`cond`
- [x] Test detection of `with`/`for` as macro invocations
- [x] Test macro arity calculation
- [x] Test location extraction
- [x] Test `extract_all/1` for module bodies
- [ ] Test qualified macro calls (e.g., `Kernel.if`) - deferred to 15.1.2

## Success Criteria

- [x] All subtasks in phase-15.md marked complete
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
- [x] All tests pass (108 tests: 32 doctests + 76 unit tests)
- [x] Detection covers all common Kernel macros

## Notes

- This task focuses only on detection - builder integration comes in 15.4.1
- Custom macro detection is handled in 15.1.2
- We treat `@` as a macro invocation (module attribute)
- Some constructs like `|>` are operators but also macros
