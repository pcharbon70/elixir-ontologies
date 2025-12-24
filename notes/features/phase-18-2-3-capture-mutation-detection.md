# Phase 18.2.3: Capture Mutation Detection

## Overview

Implement detection of potential issues with captured variables in closures. This includes detecting when a captured variable is shadowed inside the closure, when it's rebound, and tracking variable mutation patterns that might cause confusion.

## Current State

From Phase 18.2.1-18.2.2:
- `Closure` module detects free variables in anonymous functions
- `FreeVariable` struct tracks name, reference locations
- `ClosureScope` and `ScopeAnalysis` track scope hierarchy
- `find_variable_references/1` traverses AST with scope awareness

## Problem Statement

When closures capture variables, several patterns can cause confusion or bugs:

1. **Shadowing**: A captured variable is rebound with the same name inside the closure
   ```elixir
   x = 1
   fn -> x = 2; x end  # x shadows outer x
   ```

2. **Internal Rebinding**: A captured variable is rebound inside the closure body
   ```elixir
   x = 1
   fn -> x = x + 1; x end  # x is rebound after capture
   ```

3. **Immutable Use**: Variable is captured and used without modification (safe pattern)

Detecting these patterns helps:
- Identify potential bugs from unexpected shadowing
- Document closure semantics for code analysis
- Enable refactoring safety checks

## Solution Approach

### Mutation Pattern Types

| Type | Description | Example |
|------|-------------|---------|
| `:shadow` | Same name rebound, hides captured value | `fn -> x = 2 end` |
| `:rebind` | Captured var rebound using its value | `fn -> x = x + 1 end` |
| `:immutable` | Captured var used but never rebound | `fn -> x + 1 end` |

### Implementation Strategy

1. Add `MutationPattern` struct to represent detected patterns
2. Add `MutationAnalysis` struct for complete analysis results
3. Implement `detect_mutation_patterns/1` to find patterns in closure body
4. Integrate with existing `analyze_closure/1`

## Planned Structs

### MutationPattern Struct

```elixir
defmodule MutationPattern do
  @type pattern_type :: :shadow | :rebind | :immutable

  @type t :: %__MODULE__{
    variable: atom(),              # Variable name
    type: pattern_type(),          # Type of mutation pattern
    locations: [map()],            # Where the pattern occurs
    metadata: map()                # Additional info
  }
end
```

### MutationAnalysis Struct

```elixir
defmodule MutationAnalysis do
  @type t :: %__MODULE__{
    patterns: [MutationPattern.t()],  # All detected patterns
    has_shadows: boolean(),           # Any shadowing detected
    has_rebinds: boolean(),           # Any rebinding detected
    all_immutable: boolean(),         # All captures are immutable
    metadata: map()
  }
end
```

## Implementation Steps

### Step 1: Add MutationPattern struct
- [ ] Define struct with variable, type, locations, metadata
- [ ] Add typespecs

### Step 2: Add MutationAnalysis struct
- [ ] Define struct with patterns, flags
- [ ] Add typespecs

### Step 3: Implement binding detection in closure body
- [ ] Find all `=` assignments in body
- [ ] Extract variable names being bound
- [ ] Compare with captured variable names

### Step 4: Implement detect_mutation_patterns/1
- [ ] Accept anonymous function AST or struct
- [ ] Find captured variables
- [ ] Check each for shadowing/rebinding
- [ ] Return MutationAnalysis

### Step 5: Implement pattern classification
- [ ] Shadow: captured var rebound without using captured value
- [ ] Rebind: captured var rebound using its captured value
- [ ] Immutable: captured var never rebound

### Step 6: Add comprehensive tests
- [ ] Test shadowing detection
- [ ] Test rebinding detection
- [ ] Test immutable pattern
- [ ] Test complex bodies
- [ ] Test nested closures

## Success Criteria

1. `MutationPattern` captures variable, type, and locations
2. `detect_mutation_patterns/1` correctly identifies all pattern types
3. Works with complex body expressions
4. All tests pass

## Files to Modify

- `lib/elixir_ontologies/extractors/closure.ex` - Add structs and functions
- `test/elixir_ontologies/extractors/closure_test.exs` - Add mutation tests
- `notes/planning/extractors/phase-18.md` - Mark complete
