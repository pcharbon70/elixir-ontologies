# Phase 15.3.3: Macro Hygiene Analysis

## Overview

Implement detection and analysis of macro hygiene violations in Elixir code, specifically tracking `var!/1`, `var!/2`, and `Macro.escape/1` usage within quote blocks.

## Background

Elixir macros are hygienic by default - variables defined inside a macro don't leak to the caller's scope. However, developers can explicitly break hygiene using:

1. **`var!/1`** - Access a variable from the caller's context
2. **`var!/2`** - Access a variable from a specific context
3. **`Macro.escape/1`** - Escape a value to be injected into quoted code

These constructs are legitimate but should be tracked for understanding macro behavior.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-15.md`:
- 15.3.3.1 Detect `var!/1` and `var!/2` usage in quote blocks
- 15.3.3.2 Track unhygienic variable introductions
- 15.3.3.3 Detect `Macro.escape/1` usage
- 15.3.3.4 Track context parameter manipulation
- 15.3.3.5 Create `%HygieneViolation{variable: ..., context: ...}` struct
- 15.3.3.6 Add hygiene analysis tests

## Technical Design

### HygieneViolation Struct

```elixir
defmodule HygieneViolation do
  @type violation_type :: :var_bang | :macro_escape | :context_manipulation

  @type t :: %__MODULE__{
    type: violation_type(),
    variable: atom() | nil,
    context: atom() | module() | nil,
    expression: Macro.t(),
    location: SourceLocation.t() | nil,
    metadata: map()
  }

  defstruct [
    :type,
    :variable,
    :context,
    :expression,
    :location,
    metadata: %{}
  ]
end
```

### Detection Functions

- `find_hygiene_violations/1` - Find all hygiene violations in AST
- `find_var_bang/1` - Find all var!/1 and var!/2 calls
- `find_macro_escapes/1` - Find all Macro.escape/1 calls
- `var_bang?/1` - Check if node is var!/1 or var!/2
- `macro_escape?/1` - Check if node is Macro.escape/1

### AST Patterns

```elixir
# var!/1 - single argument
{:var!, [], [{:name, [], context}]}

# var!/2 - with explicit context
{:var!, [], [{:name, [], _}, context_expr]}

# Macro.escape/1
{{:., [], [{:__aliases__, [], [:Macro]}, :escape]}, [], [value]}
# or
{{:., [], [Macro, :escape]}, [], [value]}
```

## Implementation Plan

### Step 1: Create HygieneViolation Struct
- [x] Define struct in Quote extractor module
- [x] Add type specs
- [x] Add helper functions for struct

### Step 2: Implement var! Detection
- [x] Add `var_bang?/1` predicate
- [x] Add `find_var_bang/1` to find all var! calls
- [x] Extract variable name and context from var! calls
- [x] Track whether var!/1 or var!/2

### Step 3: Implement Macro.escape Detection
- [x] Add `macro_escape?/1` predicate
- [x] Add `find_macro_escapes/1` to find all Macro.escape calls
- [x] Extract escaped expression

### Step 4: Implement Combined Analysis
- [x] Add `find_hygiene_violations/1` combining all detections
- [x] Add `has_hygiene_violations?/1` predicate
- [x] Add `count_hygiene_violations/1` helper
- [x] Add `get_unhygienic_variables/1` helper

### Step 5: Write Tests
- [x] Test var!/1 detection
- [x] Test var!/2 detection with context
- [x] Test Macro.escape/1 detection
- [x] Test combined hygiene violation finding
- [x] Test helper functions
- [x] Test with quoted code

## Success Criteria

- [x] HygieneViolation struct defined with all fields
- [x] var!/1 and var!/2 correctly detected
- [x] Macro.escape/1 correctly detected
- [x] Helper functions work correctly
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes

## Notes

- Focus on detection, not judgment - these are legitimate constructs
- Track location for each violation for tooling integration
- Consider nested quotes when finding violations
