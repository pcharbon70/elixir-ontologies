# Phase 17.2.4: Loop Expression Extraction

## Overview

This task enhances the existing Comprehension extractor to add loop semantics, bulk extraction, and a structured `ForLoop` alias for consistency with other control flow extractors.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.2.4.1 Update `lib/elixir_ontologies/extractors/comprehension.ex` for loop semantics
- 17.2.4.2 Define `%ForLoop{generators: [...], filters: [...], into: ..., body: ...}` struct
- 17.2.4.3 Extract generators (binding patterns)
- 17.2.4.4 Extract filters (guard expressions)
- 17.2.4.5 Extract `into:` accumulator target
- 17.2.4.6 Add loop extraction tests

## Research Findings

### Current State

The existing `Comprehension` module already provides:
- `comprehension?/1` - Type predicate
- `generator?/1`, `bitstring_generator?/1` - Generator detection
- `extract/1`, `extract!/1` - Single extraction
- `extract_generator/1`, `extract_bitstring_generator/1` - Generator extraction
- Options extraction: `into`, `reduce`, `uniq`
- Metadata: generator_count, filter_count, has_into, has_reduce, has_uniq

### What's Missing

1. **ForLoop alias** - A `ForLoop` type alias for naming consistency
2. **Bulk extraction** - `extract_for_loops/2` to find all for comprehensions in AST
3. **Generator struct** - Currently generators are maps, should be proper structs
4. **Filter struct** - Wrap filter expressions with location info

### For Comprehension AST Patterns

```elixir
# Basic: {:for, meta, [generators_filters..., [do: body]]}
{:for, [], [{:<-, [], [pattern, enumerable]}, [do: body]]}

# With filter: filter expression between generators and do block
{:for, [], [{:<-, [], [pattern, enum]}, filter_expr, [do: body]]}

# With into: in options keyword list
{:for, [], [{:<-, [], [pattern, enum]}, [into: target, do: body]]}

# With reduce: separate reduce and do keyword lists
{:for, [], [{:<-, [], [pattern, enum]}, [reduce: init], [do: clauses]]}
```

## Technical Design

### Generator Struct

```elixir
defmodule Generator do
  @type t :: %__MODULE__{
    type: :generator | :bitstring_generator,
    pattern: Macro.t(),
    enumerable: Macro.t(),
    location: SourceLocation.t() | nil
  }
  defstruct [:type, :pattern, :enumerable, :location]
end
```

### Filter Struct

```elixir
defmodule Filter do
  @type t :: %__MODULE__{
    expression: Macro.t(),
    location: SourceLocation.t() | nil
  }
  defstruct [:expression, :location]
end
```

### ForLoop Alias

```elixir
# ForLoop is an alias for the main Comprehension struct
@type for_loop :: t()
```

### Functions to Add

```elixir
# Type predicate alias
@spec for_loop?(Macro.t()) :: boolean()

# Bulk extraction
@spec extract_for_loops(Macro.t(), keyword()) :: [t()]
```

## Implementation Plan

### Step 1: Add Generator and Filter Structs
- [x] Define `Generator` struct with enforced keys
- [x] Define `Filter` struct with expression and location

### Step 2: Update Extraction to Use Structs
- [x] Modify `extract_generator/1` to return `Generator` struct
- [x] Modify `extract_bitstring_generator/1` to return `Generator` struct
- [x] Wrap filter expressions in `Filter` struct

### Step 3: Add ForLoop Alias and Predicate
- [x] Add `for_loop?/1` as alias for `comprehension?/1`
- [x] Document the alias in moduledoc

### Step 4: Implement Bulk Extraction
- [x] Implement `extract_for_loops/2`
- [x] Walk AST recursively to find all for comprehensions
- [x] Handle nested for loops

### Step 5: Add Tests
- [x] Test Generator struct fields
- [x] Test Filter struct fields
- [x] Test for_loop? predicate
- [x] Test bulk extraction
- [x] Test nested for loops
- [x] Test location tracking

## Success Criteria

- [x] Generator struct properly defined
- [x] Filter struct properly defined
- [x] `for_loop?/1` predicate works
- [x] Bulk extraction finds all nested for comprehensions
- [x] All existing tests still pass
- [x] New tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only pre-existing suggestions)
