# Phase 18.2.2: Closure Scope Analysis

## Overview

Implement scope tracking for closures to determine which enclosing scope provides each captured variable. This enables analysis of where captured values originate - from enclosing function parameters, local bindings, module attributes, or intermediate closure scopes.

## Current State

From Phase 18.2.1:
- `Closure` module detects free variables in anonymous functions
- `FreeVariable` struct captures name, reference_count, locations
- `FreeVariableAnalysis` identifies which variables are captured
- `find_variable_references/1` traverses AST with scope awareness

## Problem Statement

When analyzing closures, knowing *which* variables are free is only part of the picture. We also need to know:
1. **Scope level** - Is this from the immediate enclosing function, or further up?
2. **Scope type** - Function scope vs module scope (attributes)?
3. **Nested capture chains** - For nested closures, which scope provides which variable?

This enables:
- Understanding closure memory footprint
- Tracking data provenance through closure chains
- Detecting potential stale capture issues
- Refactoring safety analysis

## Solution Approach

### Scope Model

Scopes form a tree/chain:
```
Module scope (level 0)
  └── Function scope (level 1)
        ├── Local bindings (level 1)
        └── Closure scope (level 2)
              └── Nested closure (level 3)
```

### Implementation Strategy

1. Add `ClosureScope` struct to represent a scope level
2. Add `ScopeChain` struct to represent the full scope hierarchy
3. Implement `build_scope_chain/1` to construct scope hierarchy from AST context
4. Implement `analyze_closure_scope/2` to map free variables to their source scopes
5. Integrate with existing `analyze_closure/1`

## Planned Structs

### ClosureScope Struct

```elixir
defmodule ClosureScope do
  @type scope_type :: :module | :function | :closure | :block

  @type t :: %__MODULE__{
    level: non_neg_integer(),       # 0 = module, 1 = function, 2+ = nested
    type: scope_type(),             # What kind of scope this is
    variables: [atom()],            # Variables available in this scope
    location: map() | nil,          # Where this scope is defined
    parent: t() | nil,              # Parent scope (nil for module level)
    metadata: map()
  }
end
```

### ScopeAnalysis Struct

```elixir
defmodule ScopeAnalysis do
  @type t :: %__MODULE__{
    scope_chain: [ClosureScope.t()],  # From innermost to outermost
    variable_sources: %{atom() => ClosureScope.t()},  # Which scope provides each var
    capture_depth: non_neg_integer(), # Max depth of capture chain
    crosses_function_boundary: boolean(),  # Captures from enclosing function
    metadata: map()
  }
end
```

## Implementation Steps

### Step 1: Add ClosureScope struct
- [ ] Define struct with level, type, variables, location, parent
- [ ] Add typespecs

### Step 2: Add ScopeAnalysis struct
- [ ] Define struct with scope_chain, variable_sources, capture_depth
- [ ] Add typespecs

### Step 3: Implement build_scope_chain/1
- [ ] Build scope chain from enclosing context
- [ ] Track function boundaries
- [ ] Handle module scope

### Step 4: Implement analyze_closure_scope/2
- [ ] Accept free variables and scope chain
- [ ] Map each free variable to its source scope
- [ ] Calculate capture depth

### Step 5: Integration
- [ ] Add `scope_analysis` field to FreeVariableAnalysis
- [ ] Update analyze_closure/1 to include scope info when context provided

### Step 6: Add comprehensive tests
- [ ] Test single-level closure
- [ ] Test nested closures
- [ ] Test module attribute captures
- [ ] Test function parameter captures

## Success Criteria

1. `ClosureScope` captures scope hierarchy
2. `analyze_closure_scope/2` maps variables to source scopes
3. Nested closure chains handled correctly
4. All tests pass

## Files to Modify

- `lib/elixir_ontologies/extractors/closure.ex` - Add scope structs and functions
- `test/elixir_ontologies/extractors/closure_test.exs` - Add scope analysis tests
- `notes/planning/extractors/phase-18.md` - Mark complete
