# Phase 17.3.1: Try Block Extraction

## Overview

This task implements extraction of try expressions with all their clause types (rescue, catch, else, after) from Elixir AST. Try expressions are fundamental to exception handling in Elixir.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.3.1.1 Create `lib/elixir_ontologies/extractors/exception.ex`
- 17.3.1.2 Define `%TryExpression{body: ..., rescue: [...], catch: [...], else: [...], after: ...}` struct
- 17.3.1.3 Extract try body expression
- 17.3.1.4 Track all clause types present
- 17.3.1.5 Handle try with only some clauses (e.g., try/after without rescue)
- 17.3.1.6 Add try block extraction tests

## Research Findings

### Try Expression AST Patterns

```elixir
# Basic structure
{:try, meta, [[do: body, rescue: rescue_clauses, catch: catch_clauses, else: else_clauses, after: after_body]]}

# Minimal try/rescue
{:try, [], [[do: body, rescue: clauses]]}

# Try/after only
{:try, [], [[do: body, after: after_body]]}

# Full try with all clauses
{:try, [], [[do: body, rescue: [...], catch: [...], else: [...], after: after_body]]}
```

### Rescue Clause Patterns

```elixir
# Bare rescue (catch-all with variable)
{:->, [], [[{:e, [], nil}], body]}

# Bare rescue (catch-all with underscore)
{:->, [], [[{:_, [], nil}], body]}

# Exception type match
{:->, [], [[{:__aliases__, _, [:ArgumentError]}], body]}

# Variable binding with exception type
{:->, [], [[{:in, _, [var, {:__aliases__, _, [:ArgumentError]}]}], body]}

# Multiple exception types
{:->, [], [[{:in, _, [var, [type1, type2]]}], body]}
```

### Catch Clause Patterns

```elixir
# Catch with type (two-element pattern)
{:->, [], [[:throw, pattern], body]}
{:->, [], [[:exit, pattern], body]}
{:->, [], [[:error, pattern], body]}

# Catch without type (single pattern - catches throws)
{:->, [], [[pattern], body]}
```

### Else Clause Patterns

```elixir
# Same as case clauses
{:->, [], [[pattern], body]}
```

## Technical Design

### RescueClause Struct

```elixir
defmodule RescueClause do
  @type t :: %__MODULE__{
    exceptions: [atom() | Macro.t()],  # Exception types or empty for catch-all
    variable: Macro.t() | nil,          # Bound variable if any
    body: Macro.t(),
    is_catch_all: boolean(),            # True if no exception types specified
    location: SourceLocation.t() | nil
  }
end
```

### CatchClause Struct

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

### ElseClause Struct

```elixir
defmodule ElseClause do
  @type t :: %__MODULE__{
    pattern: Macro.t(),
    body: Macro.t(),
    location: SourceLocation.t() | nil
  }
end
```

### TryExpression Struct

```elixir
defmodule TryExpression do
  @type t :: %__MODULE__{
    body: Macro.t(),
    rescue_clauses: [RescueClause.t()],
    catch_clauses: [CatchClause.t()],
    else_clauses: [ElseClause.t()],
    after_body: Macro.t() | nil,
    has_rescue: boolean(),
    has_catch: boolean(),
    has_else: boolean(),
    has_after: boolean(),
    location: SourceLocation.t() | nil,
    metadata: map()
  }
end
```

### Functions to Implement

```elixir
# Type predicate
@spec try_expression?(Macro.t()) :: boolean()

# Single extraction
@spec extract_try(Macro.t(), keyword()) :: {:ok, TryExpression.t()} | {:error, term()}
@spec extract_try!(Macro.t(), keyword()) :: TryExpression.t()

# Bulk extraction
@spec extract_try_expressions(Macro.t(), keyword()) :: [TryExpression.t()]
```

## Implementation Plan

### Step 1: Create Module and Structs
- [x] Create `lib/elixir_ontologies/extractors/exception.ex`
- [x] Define `RescueClause` struct
- [x] Define `CatchClause` struct
- [x] Define `ElseClause` struct
- [x] Define `TryExpression` struct

### Step 2: Implement Type Detection
- [x] Implement `try_expression?/1` predicate

### Step 3: Implement Rescue Clause Extraction
- [x] Extract exception types from rescue pattern
- [x] Handle `e in ExceptionType` binding
- [x] Handle `e in [Type1, Type2]` multiple types
- [x] Handle bare rescue (catch-all)

### Step 4: Implement Catch Clause Extraction
- [x] Extract catch kind (:throw, :exit, :error)
- [x] Handle catch without explicit type

### Step 5: Implement Try Extraction
- [x] Implement `extract_try/2`
- [x] Extract body expression
- [x] Extract rescue clauses if present
- [x] Extract catch clauses if present
- [x] Extract else clauses if present
- [x] Extract after body if present
- [x] Track which clause types are present

### Step 6: Implement Bulk Extraction
- [x] Implement `extract_try_expressions/2`
- [x] Walk AST to find all try expressions
- [x] Handle nested try expressions

### Step 7: Write Tests
- [x] Test type predicate
- [x] Test try/rescue extraction
- [x] Test try/catch extraction
- [x] Test try/after extraction
- [x] Test try/else extraction
- [x] Test full try with all clauses
- [x] Test rescue with exception types
- [x] Test rescue with variable binding
- [x] Test catch with different kinds
- [x] Test bulk extraction

## Success Criteria

- [x] `try_expression?/1` correctly identifies try expressions
- [x] All clause types extracted correctly
- [x] Rescue exception patterns parsed correctly
- [x] Catch kinds identified correctly
- [x] Partial try expressions handled (e.g., try/after only)
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only pre-existing suggestions)
