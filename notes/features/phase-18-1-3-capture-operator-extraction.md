# Phase 18.1.3: Capture Operator Extraction

## Overview

Implement extraction of capture operator expressions (`&`) for creating function references. This covers named function captures, local function captures, and shorthand captures.

## AST Pattern Research

### Local Function Capture: `&foo/1`
```elixir
{:&, [],
 [{:/, _, [{:foo, [], Elixir}, 1]}]}
```

### Remote Function Capture: `&String.upcase/1`
```elixir
{:&, [],
 [{:/, _,
   [{{:., [], [{:__aliases__, _, [:String]}, :upcase]}, _, []}, 1]}]}
```

### Erlang Module Capture: `&:erlang.element/2`
```elixir
{:&, [],
 [{:/, _,
   [{{:., [], [:erlang, :element]}, _, []}, 2]}]}
```

### Shorthand Capture: `&(&1 + 1)`
```elixir
{:&, [],
 [{:+, _, [{:&, [], [1]}, 1]}]}
```
- Contains `{:&, [], [n]}` for placeholder references

### Multi-arg Shorthand: `&(&1 + &2)`
```elixir
{:&, [],
 [{:+, _, [{:&, [], [1]}, {:&, [], [2]}]}]}
```

### Complex Shorthand with Remote Call: `&String.split(&1, ",")`
```elixir
{:&, [],
 [{{:., [], [{:__aliases__, _, [:String]}, :split]}, [],
   [{:&, [], [1]}, ","]}]}
```

## Capture Types

1. **`:named_local`** - Local function capture (`&foo/1`)
2. **`:named_remote`** - Remote function capture (`&Module.func/1` or `&:mod.func/1`)
3. **`:shorthand`** - Shorthand capture with expression (`&(&1 + 1)`)

## Implementation Plan

### Step 1: Create Capture struct
```elixir
defmodule Capture do
  @type capture_type :: :named_local | :named_remote | :shorthand

  defstruct [
    :type,           # :named_local | :named_remote | :shorthand
    :module,         # Module for remote captures (nil for local/shorthand)
    :function,       # Function name for named captures (nil for shorthand)
    :arity,          # Arity (explicit or calculated from placeholders)
    :expression,     # Body expression for shorthand captures
    :placeholders,   # List of placeholder positions found
    :location,
    :metadata
  ]
end
```

### Step 2: Implement capture?/1 predicate
Detect `{:&, _, _}` AST pattern.

### Step 3: Implement extract_capture/1
Main extraction function handling all capture types.

### Step 4: Implement helper functions
- `extract_named_capture/1` - For `{:/, _, [target, arity]}` pattern
- `extract_shorthand_capture/1` - For expression-based captures
- `find_placeholders/1` - Find all `{:&, [], [n]}` in expression

### Step 5: Add comprehensive tests

## Success Criteria

1. `capture?/1` correctly identifies all capture patterns
2. `extract_capture/1` returns proper Capture struct for all types
3. Named captures extract module, function, and arity
4. Shorthand captures find all placeholders and calculate arity
5. All tests pass

## Files to Create/Modify

- `lib/elixir_ontologies/extractors/capture.ex` - New capture extractor module
- `test/elixir_ontologies/extractors/capture_test.exs` - Tests
