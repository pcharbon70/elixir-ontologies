# Phase 17.2.1: Conditional Expression Extraction

## Overview

This task enhances the existing control flow extractor to provide a dedicated `Conditional` struct for if/unless/cond expressions, with detailed branch and clause extraction.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.2.1.1 Update `lib/elixir_ontologies/extractors/control_flow.ex` for detailed extraction
- 17.2.1.2 Define `%Conditional{type: :if|:unless|:cond, condition: ..., branches: [...]}` struct
- 17.2.1.3 Extract `if` condition and both branches (true/else)
- 17.2.1.4 Extract `unless` condition and both branches
- 17.2.1.5 Extract `cond` with all clause conditions
- 17.2.1.6 Add conditional extraction tests

## Research Findings

### Existing Implementation

The `control_flow.ex` module already has basic extraction for conditionals:
- `extract_if/1` - extracts if expressions
- `extract_unless/1` - extracts unless expressions
- `extract_cond/1` - extracts cond expressions

However, these return a generic `%ControlFlow{}` struct. The task requires a dedicated `%Conditional{}` struct.

### Conditional AST Patterns

```elixir
# if with else
{:if, meta, [condition, [do: then_branch, else: else_branch]]}

# if without else
{:if, meta, [condition, [do: then_branch]]}

# unless with else
{:unless, meta, [condition, [do: body, else: fallback]]}

# cond - clauses are arrow expressions
{:cond, meta, [[do: [
  {:->, [], [[condition1], body1]},
  {:->, [], [[condition2], body2]},
  {:->, [], [[true], default_body]}
]]]}
```

### Design Decisions

1. **New module** - Create `lib/elixir_ontologies/extractors/conditional.ex` for focused conditional handling
2. **Dedicated struct** - `%Conditional{}` struct per the plan requirements
3. **CondClause substruct** - For cond expression clauses
4. **Branch struct** - For if/unless branches with condition tracking
5. **Reuse helpers** - Leverage existing Helpers module for location extraction

## Technical Design

### Conditional Struct

```elixir
defmodule Conditional do
  @type conditional_type :: :if | :unless | :cond

  @type t :: %__MODULE__{
    type: conditional_type(),
    condition: Macro.t() | nil,        # Main condition for if/unless, nil for cond
    branches: [Branch.t()],            # Branches for if/unless
    clauses: [CondClause.t()],         # Clauses for cond
    location: SourceLocation.t() | nil,
    metadata: map()
  }
end

defmodule Branch do
  @type t :: %__MODULE__{
    type: :then | :else,
    body: Macro.t(),
    location: SourceLocation.t() | nil
  }
end

defmodule CondClause do
  @type t :: %__MODULE__{
    index: non_neg_integer(),
    condition: Macro.t(),
    body: Macro.t(),
    is_catch_all: boolean(),           # true if condition is literal `true`
    location: SourceLocation.t() | nil
  }
end
```

### Functions to Add

```elixir
# Type predicates
@spec conditional?(Macro.t()) :: boolean()
@spec if_expression?(Macro.t()) :: boolean()
@spec unless_expression?(Macro.t()) :: boolean()
@spec cond_expression?(Macro.t()) :: boolean()

# Single extraction
@spec extract_conditional(Macro.t(), keyword()) :: {:ok, Conditional.t()} | {:error, term()}
@spec extract_conditional!(Macro.t(), keyword()) :: Conditional.t()

# Type-specific extraction
@spec extract_if(Macro.t(), keyword()) :: {:ok, Conditional.t()} | {:error, term()}
@spec extract_unless(Macro.t(), keyword()) :: {:ok, Conditional.t()} | {:error, term()}
@spec extract_cond(Macro.t(), keyword()) :: {:ok, Conditional.t()} | {:error, term()}

# Bulk extraction
@spec extract_conditionals(Macro.t(), keyword()) :: [Conditional.t()]
```

## Implementation Plan

### Step 1: Create Module and Structs ✅
- [x] Create `lib/elixir_ontologies/extractors/conditional.ex`
- [x] Define `Branch` struct
- [x] Define `CondClause` struct
- [x] Define `Conditional` struct

### Step 2: Implement Type Detection ✅
- [x] Implement `conditional?/1` predicate
- [x] Implement `if_expression?/1`
- [x] Implement `unless_expression?/1`
- [x] Implement `cond_expression?/1`

### Step 3: Implement If Extraction ✅
- [x] Implement `extract_if/2`
- [x] Extract condition
- [x] Extract then branch
- [x] Extract else branch (if present)
- [x] Track has_else metadata

### Step 4: Implement Unless Extraction ✅
- [x] Implement `extract_unless/2`
- [x] Extract condition (semantically inverted)
- [x] Extract then branch
- [x] Extract else branch

### Step 5: Implement Cond Extraction ✅
- [x] Implement `extract_cond/2`
- [x] Extract all clauses in order
- [x] Detect catch-all clauses (literal `true`)
- [x] Track clause indices

### Step 6: Implement Bulk Extraction ✅
- [x] Implement `extract_conditionals/2`
- [x] Walk AST to find all conditionals
- [x] Handle nested conditionals

### Step 7: Write Tests ✅
- [x] Test type predicates
- [x] Test if extraction with and without else
- [x] Test unless extraction
- [x] Test cond extraction with multiple clauses
- [x] Test bulk extraction
- [x] Test location tracking

## Success Criteria

- [x] `conditional?/1` correctly identifies if/unless/cond
- [x] If expressions extracted with condition and both branches
- [x] Unless expressions extracted correctly
- [x] Cond clauses extracted in order with indices
- [x] Catch-all clauses detected
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only pre-existing suggestions)
