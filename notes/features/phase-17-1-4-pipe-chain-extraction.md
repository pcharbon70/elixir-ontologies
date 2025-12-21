# Phase 17.1.4: Pipe Chain Extraction

## Overview

This task implements extraction of pipe chains from Elixir AST. Pipe chains are sequences of function calls connected by the `|>` operator, where each function receives the result of the previous expression as its first argument.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.1.4.1 Implement `extract_pipe_chain/1` for `|>` operator sequences
- 17.1.4.2 Define `%PipeChain{steps: [...], start_value: ..., location: ...}` struct
- 17.1.4.3 Extract each step as a function call with implicit first argument
- 17.1.4.4 Track pipe chain order and length
- 17.1.4.5 Handle partial function application in pipes
- 17.1.4.6 Add pipe chain extraction tests

## Research Findings

### Pipe Chain AST Patterns

Pipe chains are left-associative, meaning `a |> b |> c` becomes:
```elixir
# a |> b |> c
{:|>, meta, [
  {:|>, meta, [a, b]},  # left is nested pipe
  c                      # right is the last step
]}
```

Examples:

```elixir
# Simple: data |> transform() |> output()
{:|>, [], [
  {:|>, [], [{:data, [], nil}, {:transform, [], []}]},
  {:output, [], []}
]}

# With remote calls: list |> Enum.map(fn x -> x end) |> Enum.sum()
{:|>, [], [
  {:|>, [], [
    {:list, [], nil},
    {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], [fn_ast]}
  ]},
  {{:., [], [{:__aliases__, [], [:Enum]}, :sum]}, [], []}
]}

# Single pipe: x |> foo()
{:|>, [], [{:x, [], nil}, {:foo, [], []}]}

# With literal start: [1,2,3] |> Enum.sum()
{:|>, [], [[1, 2, 3], {{:., [], [{:__aliases__, [], [:Enum]}, :sum]}, [], []}]}
```

### Key Insights

1. **Left-associative nesting** - Traverse left to find the start value
2. **Start value** - First element that's not a pipe (variable, literal, expression)
3. **Steps** - Each right-hand side is a function call (local or remote)
4. **Implicit first argument** - Each step receives previous result as arg 0

### Design Decisions

1. **New module for pipe chains** - Create `lib/elixir_ontologies/extractors/pipe.ex`
2. **Separate struct** - `%PipeChain{}` distinct from `%FunctionCall{}`
3. **PipeStep for each step** - Track step index, call type, and arguments
4. **Flatten the chain** - Convert nested structure to ordered list of steps
5. **Reference existing extractors** - Use Call extractor for step function calls

## Technical Design

### PipeChain Struct

```elixir
defmodule PipeChain do
  @type t :: %__MODULE__{
    start_value: Macro.t(),
    steps: [PipeStep.t()],
    length: non_neg_integer(),
    location: SourceLocation.t() | nil,
    metadata: map()
  }

  defstruct [:start_value, steps: [], length: 0, location: nil, metadata: %{}]
end

defmodule PipeStep do
  @type t :: %__MODULE__{
    index: non_neg_integer(),      # 0-based position in chain
    call: FunctionCall.t(),        # The function being called
    explicit_args: [Macro.t()],    # Args provided (not including piped value)
    location: SourceLocation.t() | nil
  }

  defstruct [:index, :call, explicit_args: [], location: nil]
end
```

### Functions to Add

```elixir
# Type predicate
@spec pipe_chain?(Macro.t()) :: boolean()

# Single pipe chain extraction
@spec extract_pipe_chain(Macro.t(), keyword()) :: {:ok, PipeChain.t()} | {:error, term()}

# Raising version
@spec extract_pipe_chain!(Macro.t(), keyword()) :: PipeChain.t()

# Bulk extraction from AST
@spec extract_pipe_chains(Macro.t(), keyword()) :: [PipeChain.t()]
```

## Implementation Plan

### Step 1: Create Module and Structs ✅
- [x] Create `lib/elixir_ontologies/extractors/pipe.ex`
- [x] Define `PipeStep` struct
- [x] Define `PipeChain` struct

### Step 2: Implement Type Detection ✅
- [x] Implement `pipe_chain?/1` predicate
- [x] Handle single pipe case
- [x] Handle nested pipe case

### Step 3: Implement Chain Flattening ✅
- [x] Implement `flatten_pipe_chain/1` helper
- [x] Extract start value from leftmost position
- [x] Collect all steps in order

### Step 4: Implement Extraction ✅
- [x] Implement `extract_pipe_chain/2` for single chain
- [x] Implement `extract_pipe_chain!/2` raising version
- [x] Convert each step to PipeStep with FunctionCall
- [x] Track step indices and locations

### Step 5: Implement Bulk Extraction ✅
- [x] Implement `extract_pipe_chains/2`
- [x] Walk AST to find all pipe chains
- [x] Handle nested pipe chains

### Step 6: Write Tests ✅
- [x] Test `pipe_chain?/1` predicate
- [x] Test single pipe extraction
- [x] Test multi-step chain extraction
- [x] Test with local and remote calls
- [x] Test with literals as start value
- [x] Test step ordering
- [x] Test bulk extraction
- [x] Test nested chains

## Success Criteria

- [x] `pipe_chain?/1` correctly identifies pipe chains
- [x] Single and multi-step chains extracted
- [x] Start value correctly identified
- [x] Steps ordered correctly (0-indexed)
- [x] Both local and remote calls in steps handled
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only pre-existing suggestions)
