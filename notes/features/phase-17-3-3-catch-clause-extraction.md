# Phase 17.3.3: Catch Clause Extraction

## Overview

This task focuses on catch clause extraction from try expressions. The core functionality was implemented as part of task 17.3.1 (Try Block Extraction). This task validates the implementation and adds standalone tests.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.3.3.1 Implement `extract_catch_clauses/1` for catch blocks
- 17.3.3.2 Define `%CatchClause{type: :throw|:exit|:error, pattern: ..., body: ...}` struct
- 17.3.3.3 Extract catch type (:throw, :exit, :error)
- 17.3.3.4 Extract catch pattern
- 17.3.3.5 Handle catch without explicit type
- 17.3.3.6 Add catch clause extraction tests

## Implementation Status (from 17.3.1)

All requirements were implemented in task 17.3.1:

### CatchClause Struct ✓
```elixir
defmodule CatchClause do
  @type t :: %__MODULE__{
    kind: :throw | :exit | :error | nil,  # nil if no explicit type
    pattern: Macro.t(),
    body: Macro.t(),
    location: SourceLocation.t() | nil
  }
end
```

Note: The struct uses `:kind` instead of `:type` to avoid confusion with the Elixir `@type` attribute.

### Functions Implemented ✓
- `extract_catch_clauses/2` - Extract catch clauses from AST list
- Pattern parsing for all catch formats

### Patterns Supported ✓
1. Catch with :throw kind: `catch :throw, value -> body`
2. Catch with :exit kind: `catch :exit, reason -> body`
3. Catch with :error kind: `catch :error, reason -> body`
4. Catch without explicit kind: `catch value -> body` (kind is nil)

### Existing Tests ✓
- 5 catch-specific tests in exception_test.exs
- Tests cover all pattern types

## Enhancements for 17.3.3

### Additional Edge Case Tests
- [x] Test standalone extract_catch_clauses/2 function
- [x] Test empty list and nil handling
- [x] Test pattern extraction with complex patterns

## Implementation Plan

### Step 1: Validate Existing Implementation
- [x] Review CatchClause struct - complete
- [x] Review extract_catch_clauses/2 function - complete
- [x] Review pattern parsing - complete

### Step 2: Add Edge Case Tests
- [x] Add test for standalone extract_catch_clauses/2
- [x] Add test for empty clauses handling
- [x] Add test for complex patterns

### Step 3: Mark Complete
- [x] Update phase plan
- [x] Write summary

## Success Criteria

- [x] `extract_catch_clauses/2` extracts all catch clause types
- [x] CatchClause struct captures all relevant information
- [x] Catch kind extracted correctly (:throw, :exit, :error, nil)
- [x] Catch pattern extracted correctly
- [x] Catch without explicit type handled correctly
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only pre-existing suggestions)
