# Phase 16.2.2: Selective Import Extraction

## Overview

Complete the import directive extraction with scope tracking. Most of 16.2.2's planned work was already done in 16.2.1 (only/except extraction, type-based imports, function/arity parsing).

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.2.2.1 Extract `import Module, only: [func: arity]` form - DONE in 16.2.1
- 16.2.2.2 Extract `import Module, except: [func: arity]` form - DONE in 16.2.1
- 16.2.2.3 Extract `import Module, only: :functions` form - DONE in 16.2.1
- 16.2.2.4 Extract `import Module, only: :macros` form - DONE in 16.2.1
- 16.2.2.5 Parse function/arity lists into structured data - DONE in 16.2.1
- 16.2.2.6 Add selective import tests - DONE in 16.2.1

Remaining from Section 16.2 Unit Tests:
- [ ] Test import scope tracking

## Technical Design

### Add Scope Tracking

Following the same pattern as alias extractor:

```elixir
@spec extract_all_with_scope(Macro.t(), keyword()) :: [ImportDirective.t()]
def extract_all_with_scope(ast, opts \\ []) do
  extract_with_scope(ast, :module, opts)
end
```

Private helper functions for AST walking with scope context.

## Implementation Plan

### Step 1: Add extract_all_with_scope/2
- [x] Add public function with doctest
- [x] Add private extract_with_scope helpers

### Step 2: Add Scope Tracking Tests
- [x] Test module-level import scope
- [x] Test function-level import scope
- [x] Test block-level import scope

### Step 3: Update Phase Plan
- [x] Mark 16.2.2 subtasks as complete
- [x] Mark scope tracking test as complete

## Success Criteria

- [x] `extract_all_with_scope/2` correctly tracks scope
- [x] Module-level imports tagged correctly
- [x] Function-level imports tagged correctly
- [x] Block-level imports tagged correctly
- [x] Tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
