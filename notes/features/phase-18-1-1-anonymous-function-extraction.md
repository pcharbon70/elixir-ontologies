# Phase 18.1.1: Basic Anonymous Function Extraction

## Problem Statement

The codebase lacks extraction of anonymous functions (`fn -> end` syntax). Anonymous functions are fundamental to Elixir's functional programming style, used extensively for callbacks, higher-order functions, and closures. Without this extraction, we cannot:

1. Track anonymous function definitions in analyzed code
2. Understand function arity of anonymous functions
3. Build the foundation for closure analysis (captured variables)
4. Complete call graph analysis for anonymous function invocations

## Solution Overview

Create `lib/elixir_ontologies/extractors/anonymous_function.ex` with:
- `AnonymousFunction` struct for representing anonymous function definitions
- `AnonymousFunctionClause` struct for individual clauses
- `extract/1` function to extract anonymous functions from AST
- Support for single and multi-clause anonymous functions
- Arity calculation from parameters

## AST Patterns

### Single-clause anonymous function
```elixir
# fn x -> x + 1 end
{:fn, [],
 [
   {:->, [],
    [
      [{:x, [], Elixir}],    # parameters list
      {:+, [...], [...]}     # body
    ]}
 ]}
```

### Multi-clause anonymous function
```elixir
# fn 0 -> :zero; n when n > 0 -> :positive; _ -> :negative end
{:fn, [],
 [
   {:->, [], [[0], :zero]},
   {:->, [], [[{:when, [], [{:n, [], Elixir}, ...]}], :positive]},
   {:->, [], [[{:_, [], Elixir}], :negative]}
 ]}
```

### Key observations:
- Anonymous function is `{:fn, meta, [clauses]}`
- Each clause is `{:->, meta, [[params...], body]}`
- Guards appear as `{:when, meta, [pattern, guard_expr]}` wrapping the pattern
- Arity = length of parameters list in first clause

## Technical Details

### Files to Create
- `lib/elixir_ontologies/extractors/anonymous_function.ex`
- `test/elixir_ontologies/extractors/anonymous_function_test.exs`

### Struct Design

```elixir
defmodule AnonymousFunction do
  defstruct [
    :clauses,        # List of AnonymousFunctionClause
    :arity,          # Number of parameters
    :location,       # Source location
    :metadata        # Additional info (captured_vars placeholder for 18.2)
  ]
end

defmodule AnonymousFunctionClause do
  defstruct [
    :parameters,     # List of parameter patterns
    :guard,          # Guard expression or nil
    :body,           # Clause body AST
    :order,          # 1-indexed clause order
    :location        # Source location if available
  ]
end
```

## Implementation Plan

### Step 1: Create module structure
- [x] Create `anonymous_function.ex` with moduledoc
- [x] Define `AnonymousFunction` struct
- [x] Define `AnonymousFunctionClause` struct

### Step 2: Implement type detection
- [x] Implement `anonymous_function?/1` predicate
- [x] Handle `{:fn, _, _}` AST pattern

### Step 3: Implement extraction
- [x] Implement `extract/1` main function
- [x] Implement `extract_clause/2` for individual clauses
- [x] Handle guard extraction from `{:when, _, _}` pattern
- [x] Calculate arity from first clause parameters

### Step 4: Add tests
- [x] Test single-clause extraction
- [x] Test multi-clause extraction
- [x] Test guard extraction
- [x] Test arity calculation
- [x] Test parameter extraction
- [x] Test location extraction

### Step 5: Quality checks
- [x] `mix compile --warnings-as-errors`
- [x] `mix credo --strict`
- [x] `mix test test/elixir_ontologies/extractors/anonymous_function_test.exs`

## Success Criteria

1. `anonymous_function?/1` correctly identifies anonymous function AST
2. `extract/1` returns `{:ok, %AnonymousFunction{}}` for valid input
3. Multi-clause anonymous functions extract all clauses in order
4. Guards are properly separated from parameters
5. Arity is correctly calculated
6. All tests pass
7. Quality checks pass

## Current Status

- [x] Step 1: Create module structure
- [x] Step 2: Implement type detection
- [x] Step 3: Implement extraction
- [x] Step 4: Add tests
- [x] Step 5: Quality checks
