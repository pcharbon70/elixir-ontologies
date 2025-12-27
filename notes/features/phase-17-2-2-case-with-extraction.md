# Phase 17.2.2: Case and With Expression Extraction

## Overview

This task implements extraction of case and with expressions from Elixir AST. Both are pattern matching constructs - case for matching against a subject value, and with for chaining pattern matching operations.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.2.2.1 Implement `extract_case/1` for case expressions
- 17.2.2.2 Define `%CaseExpression{subject: ..., clauses: [...], location: ...}` struct
- 17.2.2.3 Extract each case clause with pattern and guard
- 17.2.2.4 Implement `extract_with/1` for with expressions
- 17.2.2.5 Define `%WithExpression{clauses: [...], else: ..., location: ...}` struct
- 17.2.2.6 Add case/with extraction tests

## Research Findings

### Case Expression AST Patterns

```elixir
# Basic case
{:case, meta, [subject, [do: clauses]]}

# Each clause is an arrow expression
{:->, clause_meta, [[pattern], body]}

# Clause with guard
{:->, clause_meta, [[{:when, [], [pattern, guard]}], body]}

# Examples:
# case x do :a -> 1 end
{:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}

# case x do n when n > 0 -> :positive end
{:case, [], [
  {:x, [], nil},
  [do: [
    {:->, [], [[{:when, [], [{:n, [], nil}, {:>, [], [{:n, [], nil}, 0]}]}], :positive]}
  ]]
]}
```

### With Expression AST Patterns

```elixir
# Basic with - clauses are in args list, last element is [do: body]
{:with, meta, [clause1, clause2, ..., [do: body]]}

# With else - last element is [do: body, else: else_clauses]
{:with, meta, [clause1, clause2, ..., [do: body, else: else_clauses]]}

# Match clause (<-)
{:<-, meta, [pattern, expression]}

# Bare match clause (=)
{:=, meta, [pattern, expression]}

# Examples:
# with {:ok, a} <- get_a() do a end
{:with, [], [
  {:<-, [], [{:ok, {:a, [], nil}}, {:get_a, [], []}]},
  [do: {:a, [], nil}]
]}

# with {:ok, a} <- get_a() do a else {:error, e} -> e end
{:with, [], [
  {:<-, [], [{:ok, {:a, [], nil}}, {:get_a, [], []}]},
  [do: {:a, [], nil}, else: [{:->, [], [[{:error, {:e, [], nil}}], {:e, [], nil}]}]]
]}
```

### Design Decisions

1. **New module** - Create `lib/elixir_ontologies/extractors/case_with.ex`
2. **Separate structs** - CaseExpression, WithExpression, CaseClause, WithClause
3. **Guard extraction** - Extract guards from case clauses when present
4. **Pattern tracking** - Store the pattern AST for each clause
5. **Clause types** - Track `<-` vs `=` for with clauses

## Technical Design

### CaseClause Struct

```elixir
defmodule CaseClause do
  @type t :: %__MODULE__{
    index: non_neg_integer(),
    pattern: Macro.t(),
    guard: Macro.t() | nil,
    body: Macro.t(),
    has_guard: boolean(),
    location: SourceLocation.t() | nil
  }
end
```

### CaseExpression Struct

```elixir
defmodule CaseExpression do
  @type t :: %__MODULE__{
    subject: Macro.t(),
    clauses: [CaseClause.t()],
    location: SourceLocation.t() | nil,
    metadata: map()
  }
end
```

### WithClause Struct

```elixir
defmodule WithClause do
  @type t :: %__MODULE__{
    index: non_neg_integer(),
    type: :match | :bare_match,    # <- vs =
    pattern: Macro.t(),
    expression: Macro.t(),
    location: SourceLocation.t() | nil
  }
end
```

### WithExpression Struct

```elixir
defmodule WithExpression do
  @type t :: %__MODULE__{
    clauses: [WithClause.t()],
    body: Macro.t(),
    else_clauses: [CaseClause.t()],   # Reuse CaseClause for else
    has_else: boolean(),
    location: SourceLocation.t() | nil,
    metadata: map()
  }
end
```

### Functions to Add

```elixir
# Type predicates
@spec case_expression?(Macro.t()) :: boolean()
@spec with_expression?(Macro.t()) :: boolean()

# Single extraction
@spec extract_case(Macro.t(), keyword()) :: {:ok, CaseExpression.t()} | {:error, term()}
@spec extract_case!(Macro.t(), keyword()) :: CaseExpression.t()
@spec extract_with(Macro.t(), keyword()) :: {:ok, WithExpression.t()} | {:error, term()}
@spec extract_with!(Macro.t(), keyword()) :: WithExpression.t()

# Bulk extraction
@spec extract_case_expressions(Macro.t(), keyword()) :: [CaseExpression.t()]
@spec extract_with_expressions(Macro.t(), keyword()) :: [WithExpression.t()]
```

## Implementation Plan

### Step 1: Create Module and Structs ✅
- [x] Create `lib/elixir_ontologies/extractors/case_with.ex`
- [x] Define `CaseClause` struct
- [x] Define `CaseExpression` struct
- [x] Define `WithClause` struct
- [x] Define `WithExpression` struct

### Step 2: Implement Type Detection ✅
- [x] Implement `case_expression?/1` predicate
- [x] Implement `with_expression?/1` predicate

### Step 3: Implement Case Extraction ✅
- [x] Implement `extract_case/2`
- [x] Extract subject expression
- [x] Extract all clauses with patterns
- [x] Extract guards when present
- [x] Track clause indices

### Step 4: Implement With Extraction ✅
- [x] Implement `extract_with/2`
- [x] Extract all match clauses (<-)
- [x] Handle bare match clauses (=)
- [x] Extract body expression
- [x] Extract else clauses if present

### Step 5: Implement Bulk Extraction ✅
- [x] Implement `extract_case_expressions/2`
- [x] Implement `extract_with_expressions/2`
- [x] Walk AST to find all expressions
- [x] Handle nested expressions

### Step 6: Write Tests ✅
- [x] Test type predicates
- [x] Test case extraction with various patterns
- [x] Test case extraction with guards
- [x] Test with extraction with match clauses
- [x] Test with extraction with else
- [x] Test bulk extraction
- [x] Test location tracking

## Success Criteria

- [x] `case_expression?/1` correctly identifies case expressions
- [x] `with_expression?/1` correctly identifies with expressions
- [x] Case subject and clauses extracted correctly
- [x] Case guards extracted when present
- [x] With clauses extracted with correct types
- [x] With else clauses handled properly
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only pre-existing suggestions)
