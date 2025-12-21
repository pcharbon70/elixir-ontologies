# Phase 17.3.2: Rescue Clause Extraction

## Overview

This task focuses on rescue clause extraction from try expressions. The core functionality was implemented as part of task 17.3.1 (Try Block Extraction). This task validates the implementation and adds any missing functionality.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.3.2.1 Implement `extract_rescue_clauses/1` for rescue blocks
- 17.3.2.2 Define `%RescueClause{exceptions: [...], variable: ..., body: ...}` struct
- 17.3.2.3 Extract exception type patterns (e.g., `ArgumentError`)
- 17.3.2.4 Extract exception variable binding (e.g., `rescue e ->`)
- 17.3.2.5 Handle bare rescue (catch-all)
- 17.3.2.6 Add rescue clause extraction tests

## Implementation Status (from 17.3.1)

All requirements were implemented in task 17.3.1:

### RescueClause Struct ✓
```elixir
defmodule RescueClause do
  @type t :: %__MODULE__{
    exceptions: [atom() | Macro.t()],  # Exception types, empty for catch-all
    variable: Macro.t() | nil,          # Bound variable if any
    body: Macro.t(),                    # Body expression
    is_catch_all: boolean(),            # True if no exception types
    location: SourceLocation.t() | nil
  }
end
```

### Functions Implemented ✓
- `extract_rescue_clauses/2` - Extract rescue clauses from AST list
- Pattern parsing for all rescue formats

### Patterns Supported ✓
1. Bare rescue with underscore: `rescue _ -> body`
2. Bare rescue with variable: `rescue e -> body`
3. Exception type match: `rescue ArgumentError -> body`
4. Variable binding with type: `rescue e in ArgumentError -> body`
5. Multiple exception types: `rescue e in [ArgumentError, RuntimeError] -> body`

### Existing Tests ✓
- 6 rescue-specific tests in exception_test.exs
- Tests cover all pattern types

## Enhancements for 17.3.2

### Additional Edge Case Tests
- [x] Test rescue with complex exception patterns
- [x] Test standalone extract_rescue_clauses/2 function
- [x] Test nested module exception types

## Implementation Plan

### Step 1: Validate Existing Implementation
- [x] Review RescueClause struct - complete
- [x] Review extract_rescue_clauses/2 function - complete
- [x] Review pattern parsing - complete

### Step 2: Add Edge Case Tests
- [x] Add test for standalone extract_rescue_clauses/2
- [x] Add test for empty clauses handling
- [x] Add test for exception module name extraction
- [x] Add test for multiple exception types
- [x] Add test for nested module exception types

### Step 3: Mark Complete
- [x] Update phase plan
- [x] Write summary

## Success Criteria

- [x] `extract_rescue_clauses/2` extracts all rescue clause types
- [x] RescueClause struct captures all relevant information
- [x] Exception types extracted correctly
- [x] Variable binding extracted correctly
- [x] Bare rescue (catch-all) handled correctly
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only pre-existing suggestions)
