# Phase 17.2.3: Receive Expression Extraction

## Overview

This task implements extraction of receive expressions from Elixir AST. Receive expressions are used in OTP and concurrent programming to handle messages from the process mailbox.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.2.3.1 Implement `extract_receive/1` for receive blocks
- 17.2.3.2 Define `%ReceiveExpression{clauses: [...], after: ..., location: ...}` struct
- 17.2.3.3 Extract message patterns in receive clauses
- 17.2.3.4 Extract `after` timeout clause
- 17.2.3.5 Track receive as potential blocking point
- 17.2.3.6 Add receive extraction tests

## Research Findings

### Receive Expression AST Patterns

```elixir
# Basic receive
{:receive, meta, [[do: clauses]]}

# Receive with after timeout
{:receive, meta, [[do: clauses, after: after_clauses]]}

# Each clause is an arrow expression (same as case)
{:->, clause_meta, [[pattern], body]}

# Clause with guard
{:->, clause_meta, [[{:when, [], [pattern, guard]}], body]}

# After clause
{:->, clause_meta, [[timeout_value], body]}
```

### Examples

```elixir
# Basic receive
# receive do {:msg, data} -> data end
{:receive, [], [[do: [{:->, [], [[{:msg, {:data, [], nil}}], {:data, [], nil}]}]]]}

# Receive with after
# receive do {:msg, data} -> data after 5000 -> :timeout end
{:receive, [], [[
  do: [{:->, [], [[{:msg, {:data, [], nil}}], {:data, [], nil}]}],
  after: [{:->, [], [[5000], :timeout]}]
]]}

# Receive with only after (immediate timeout check)
# receive do after 0 -> :no_messages end
{:receive, [], [[do: {:__block__, [], []}, after: [{:->, [], [[0], :no_messages]}]]]}
```

### Design Decisions

1. **Extend case_with module** - Add receive to existing module since it shares clause structure
2. **Reuse CaseClause** - Receive clauses have same structure as case clauses
3. **AfterClause struct** - Dedicated struct for after with timeout tracking
4. **Blocking flag** - Track receive as potential blocking point in metadata

## Technical Design

### AfterClause Struct

```elixir
defmodule AfterClause do
  @type t :: %__MODULE__{
    timeout: Macro.t(),           # Timeout expression (usually integer)
    body: Macro.t(),              # Body to execute on timeout
    is_immediate: boolean(),      # True if timeout is literal 0
    location: SourceLocation.t() | nil
  }
end
```

### ReceiveExpression Struct

```elixir
defmodule ReceiveExpression do
  @type t :: %__MODULE__{
    clauses: [CaseClause.t()],    # Message pattern clauses
    after_clause: AfterClause.t() | nil,
    has_after: boolean(),
    location: SourceLocation.t() | nil,
    metadata: map()               # is_blocking, clause_count, etc.
  }
end
```

### Functions to Add

```elixir
# Type predicate
@spec receive_expression?(Macro.t()) :: boolean()

# Single extraction
@spec extract_receive(Macro.t(), keyword()) :: {:ok, ReceiveExpression.t()} | {:error, term()}
@spec extract_receive!(Macro.t(), keyword()) :: ReceiveExpression.t()

# Bulk extraction
@spec extract_receive_expressions(Macro.t(), keyword()) :: [ReceiveExpression.t()]
```

## Implementation Plan

### Step 1: Add Structs to case_with.ex
- [x] Define `AfterClause` struct
- [x] Define `ReceiveExpression` struct

### Step 2: Implement Type Detection
- [x] Implement `receive_expression?/1` predicate

### Step 3: Implement Receive Extraction
- [x] Implement `extract_receive/2`
- [x] Extract message clauses (reuse case clause building)
- [x] Extract after clause if present
- [x] Track is_immediate for timeout 0
- [x] Track is_blocking in metadata

### Step 4: Implement Bulk Extraction
- [x] Implement `extract_receive_expressions/2`
- [x] Walk AST to find all receive expressions
- [x] Handle nested expressions

### Step 5: Write Tests
- [x] Test type predicate
- [x] Test receive extraction without after
- [x] Test receive extraction with after
- [x] Test receive with guards
- [x] Test receive with only after (timeout 0)
- [x] Test bulk extraction
- [x] Test blocking point detection

## Success Criteria

- [x] `receive_expression?/1` correctly identifies receive expressions
- [x] Message clauses extracted with patterns and guards
- [x] After clause extracted with timeout value
- [x] Immediate timeout (0) detected
- [x] Blocking point tracked in metadata
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only pre-existing suggestions)
