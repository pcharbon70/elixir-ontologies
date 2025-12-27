# Feature: Phase 14.2.3 - Literal Types Enhancement

## Problem Statement

Task 14.2.3 from the Phase 14 plan calls for extracting literal type values. The existing `TypeExpression` extractor already handles basic literal types (atoms, integers, floats) but doesn't support range literals or binary literal types with size specifications.

**Current Implementation:**
- Atom literals detected: `:ok`, `:error`, `true`, `false`, `nil`
- Integer literals detected: `42`, `-1`
- Float literals detected: `3.14`
- `literal?/1` helper exists
- `literal_type` metadata field exists

**What's Missing:**
1. Range literal types (`1..10`, `1..100//5`)
2. Binary literal types with size specifications (`<<_::8>>`, `<<_::binary>>`)
3. `literal_value/1` helper for getting the literal value
4. `range?/1` helper for detecting range literals
5. `binary_literal?/1` helper for detecting binary literals

## Solution Overview

Enhance literal type parsing to support range literals and binary literals, then add helper functions for introspection.

## Technical Details

### File Locations
- **Extractor**: `lib/elixir_ontologies/extractors/type_expression.ex`
- **Tests**: `test/elixir_ontologies/extractors/type_expression_test.exs`

### AST Structures

**Range literals:**
```elixir
# 1..10
{:.., _, [1, 10]}

# 1..100//5 (step range)
{:..//, _, [1, 100, 5]}

# Negative ranges use nested :- operator
{:.., _, [{:-, _, [10]}, {:-, _, [1]}]}
```

**Binary literals:**
```elixir
# <<>>
{:<<>>, [], []}

# <<_::8>>
{:<<>>, [], [{:"::", [], [{:_, [], Elixir}, 8]}]}

# <<_::binary>>
{:<<>>, [], [{:"::", [], [{:_, [], Elixir}, {:binary, [], Elixir}]}]}

# <<_::_*8>> (variable size)
{:<<>>, [], [{:"::", [], [{:_, [], Elixir}, {:*, _, [{:_, [], Elixir}, 8]}]}]}
```

### Proposed Implementation

1. Add range literal parsing:

```elixir
# Range literal: 1..10
defp do_parse({:.., _, [start, finish]} = ast) do
  %__MODULE__{
    kind: :literal,
    name: nil,
    ast: ast,
    metadata: %{
      literal_type: :range,
      range_start: evaluate_literal(start),
      range_end: evaluate_literal(finish)
    }
  }
end

# Step range literal: 1..100//5
defp do_parse({:..//, _, [start, finish, step]} = ast) do
  %__MODULE__{
    kind: :literal,
    name: nil,
    ast: ast,
    metadata: %{
      literal_type: :range,
      range_start: evaluate_literal(start),
      range_end: evaluate_literal(finish),
      range_step: evaluate_literal(step)
    }
  }
end
```

2. Add binary literal parsing:

```elixir
# Empty binary: <<>>
defp do_parse({:<<>>, _, []} = ast) do
  %__MODULE__{
    kind: :literal,
    name: nil,
    ast: ast,
    metadata: %{literal_type: :binary, binary_size: 0}
  }
end

# Binary with segments
defp do_parse({:<<>>, _, segments} = ast) when is_list(segments) do
  parsed_segments = Enum.map(segments, &parse_binary_segment/1)

  %__MODULE__{
    kind: :literal,
    name: nil,
    elements: parsed_segments,
    ast: ast,
    metadata: %{literal_type: :binary, segment_count: length(segments)}
  }
end
```

3. Add helper functions:

```elixir
@spec literal_value(t()) :: term() | nil
def literal_value(%__MODULE__{kind: :literal, name: value}), do: value
def literal_value(_), do: nil

@spec range?(t()) :: boolean()
def range?(%__MODULE__{kind: :literal, metadata: %{literal_type: :range}}), do: true
def range?(_), do: false

@spec binary_literal?(t()) :: boolean()
def binary_literal?(%__MODULE__{kind: :literal, metadata: %{literal_type: :binary}}), do: true
def binary_literal?(_), do: false
```

## Success Criteria

- [ ] Range literals parse correctly with start/end values
- [ ] Step ranges parse with step value
- [ ] Binary literals parse with segment information
- [ ] `literal_value/1` returns the literal value
- [ ] `range?/1` detects range literals
- [ ] `binary_literal?/1` detects binary literals
- [ ] Tests for all literal type scenarios
- [ ] All existing tests continue to pass

## Implementation Plan

### Step 1: Add Range Literal Parsing
Add `do_parse/1` clauses for `{:.., _, _}` and `{:..//, _, _}` patterns.

### Step 2: Add Binary Literal Parsing
Add `do_parse/1` clauses for `{:<<>>, _, _}` pattern with segment parsing.

### Step 3: Add Helper for Evaluating Literal Values
Add private `evaluate_literal/1` helper for extracting values from negated integers etc.

### Step 4: Add `literal_value/1` Helper
Add public helper to get the value from literal types.

### Step 5: Add `range?/1` Helper
Add helper to detect range literal types.

### Step 6: Add `binary_literal?/1` Helper
Add helper to detect binary literal types.

### Step 7: Add Comprehensive Tests
Add tests for all new literal type scenarios.

## Current Status

- **Branch**: `feature/phase-14-2-3-literal-types`
- **Status**: Planning complete
- **How to run**: `mix test test/elixir_ontologies/extractors/type_expression_test.exs`

## Notes

- Range literals don't have a simple `name` value since they represent a range
- Binary literals store segment information for complex specifications
- Negative numbers in ranges need special handling (nested unary `-` operator)
- The `t()` convention is handled at the type definition level, not literal level
