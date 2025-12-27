# Phase 18.2.1: Free Variable Detection

## Overview

Implement detection of free variables in anonymous functions. Free variables are variables that appear in a function body but are not bound by the function's parameters - they must be captured from the enclosing scope.

## Current State

From Phase 18.1:
- `AnonymousFunction` module extracts anonymous functions with clauses
- `AnonymousFunction.Clause` includes `bound_variables` from parameters
- `Pattern` module provides `collect_bindings/1` to find variables bound by patterns

## Problem Statement

When analyzing closures, we need to identify which variables in the function body:
1. Come from the function's own parameters (bound)
2. Come from the outer scope (free/captured)

Free variable detection enables:
- Closure analysis (what external state does this function depend on?)
- Data flow tracking (where do captured values originate?)
- Refactoring safety (can this closure be moved?)

## Solution Approach

### Free Variable Definition

A **free variable** in a function is a variable that:
1. Is referenced in the function body
2. Is NOT bound by the function's parameters
3. Is NOT a special form, module name, or function call name

### Implementation Strategy

1. Create a new `Closure` module in `lib/elixir_ontologies/extractors/closure.ex`
2. Add `FreeVariable` struct with location and binding information
3. Implement `detect_free_variables/2` to find variables not in bound set
4. Implement helper to find all variable references in AST

## Planned Structs

### FreeVariable Struct

```elixir
defmodule FreeVariable do
  @type t :: %__MODULE__{
    name: atom(),                    # Variable name
    reference_locations: [map()],    # Where this variable is referenced
    captured_at: map() | nil,        # Location of the fn/capture that captures it
    metadata: map()                  # Additional info (usage_count, etc.)
  }
end
```

### FreeVariableAnalysis Struct

```elixir
defmodule FreeVariableAnalysis do
  @type t :: %__MODULE__{
    free_variables: [FreeVariable.t()],
    bound_variables: [atom()],       # Variables bound by parameters
    all_references: [atom()],        # All variable references in body
    has_captures: boolean(),         # Whether any free variables exist
    metadata: map()
  }
end
```

## Implementation Steps

### Step 1: Create Closure module with FreeVariable struct
- [ ] Create `lib/elixir_ontologies/extractors/closure.ex`
- [ ] Define `FreeVariable` struct
- [ ] Define `FreeVariableAnalysis` struct

### Step 2: Implement variable reference finder
- [ ] Create `find_variable_references/1` to traverse AST
- [ ] Handle special cases (function calls, module names, special forms)
- [ ] Track locations of each reference

### Step 3: Implement detect_free_variables/2
- [ ] Accept AST and list of bound variable names
- [ ] Find all variable references in body
- [ ] Filter out bound variables
- [ ] Return FreeVariableAnalysis

### Step 4: Integrate with AnonymousFunction
- [ ] Add helper `analyze_closure/1` that works on AnonymousFunction.t()
- [ ] Uses bound_variables from clauses

### Step 5: Add comprehensive tests
- [ ] Test basic free variable detection
- [ ] Test nested scopes
- [ ] Test shadowing
- [ ] Test edge cases (no free vars, multiple refs)

## Success Criteria

1. `FreeVariable` struct captures name, locations, and metadata
2. `detect_free_variables/2` correctly identifies free vs bound variables
3. Works with all clause types (with/without guards)
4. Handles complex body expressions (case, with, comprehensions)
5. All tests pass

## Files to Create/Modify

- Create: `lib/elixir_ontologies/extractors/closure.ex`
- Create: `test/elixir_ontologies/extractors/closure_test.exs`
- Modify: `notes/planning/extractors/phase-18.md` (mark complete)
