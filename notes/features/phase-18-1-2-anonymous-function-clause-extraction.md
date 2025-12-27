# Phase 18.1.2: Anonymous Function Clause Extraction

## Overview

This task enhances the AnonymousFunction extractor to provide standalone clause extraction capabilities and richer pattern analysis for parameters. While 18.1.1 implemented the basic Clause struct and extraction as part of whole-function extraction, this task adds:

1. Public `extract_clause/1` function for extracting individual `{:->, _, _}` nodes
2. Integration with the Pattern extractor for detailed parameter pattern analysis
3. Enhanced clause metadata including pattern types and variable bindings

## Current State (from 18.1.1)

The `AnonymousFunction.Clause` struct already exists with:
- `parameters` - List of parameter AST nodes
- `guard` - Guard expression or nil
- `body` - Clause body AST
- `order` - 1-indexed clause order
- `location` - Source location

## Planned Enhancements

### 1. Public Clause Extraction Function

Add `extract_clause/1` that takes a `{:->, meta, [[params], body]}` AST node directly:

```elixir
@spec extract_clause(Macro.t()) :: {:ok, Clause.t()} | {:error, atom()}
def extract_clause({:->, _meta, [params_with_guard, body]} = node) do
  # ...
end
```

### 2. Enhanced Clause Struct

Extend the Clause struct with additional metadata:

```elixir
defstruct [
  :parameters,        # List of parameter ASTs
  :guard,             # Guard expression AST or nil
  :body,              # Clause body AST
  :order,             # 1-indexed clause order (nil for standalone)
  :arity,             # Number of parameters
  :parameter_patterns, # List of Pattern.t() for each parameter
  :bound_variables,   # All variables bound by parameters
  location: nil,
  metadata: %{}
]
```

### 3. Pattern Integration

Use `Pattern.extract/1` to analyze each parameter:

```elixir
parameter_patterns = Enum.map(parameters, fn param ->
  case Pattern.extract(param) do
    {:ok, pattern} -> pattern
    _ -> nil
  end
end)

bound_variables =
  parameter_patterns
  |> Enum.flat_map(fn p -> if p, do: p.bindings, else: [] end)
  |> Enum.uniq()
```

## Implementation Steps

### Step 1: Add arity to Clause struct
- [x] Already have parameters, can calculate arity

### Step 2: Add parameter_patterns and bound_variables fields
- [ ] Extend Clause struct with new fields
- [ ] Use Pattern.extract/1 for each parameter

### Step 3: Add public extract_clause/1 and extract_clause/2 functions
- [ ] `extract_clause/1` - Extract from bare clause AST (no order)
- [ ] `extract_clause/2` - Extract with explicit order

### Step 4: Add clause_ast?/1 predicate
- [ ] Check if AST is a `{:->, _, _}` clause node

### Step 5: Add tests for new functionality
- [ ] Test extract_clause/1 standalone extraction
- [ ] Test parameter pattern extraction
- [ ] Test bound variable collection
- [ ] Test guard extraction
- [ ] Test various pattern types in parameters

## Success Criteria

1. `extract_clause/1` can extract a standalone clause AST
2. Each clause has `parameter_patterns` with Pattern.t() structs
3. Each clause has `bound_variables` listing all bound vars
4. All existing tests continue to pass
5. New tests cover the enhanced functionality

## Files to Modify

- `lib/elixir_ontologies/extractors/anonymous_function.ex` - Enhance Clause struct and add functions
- `test/elixir_ontologies/extractors/anonymous_function_test.exs` - Add clause extraction tests
