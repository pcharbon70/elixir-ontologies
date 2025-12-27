# Phase 17.3.4: Raise and Throw Extraction

## Overview

This task implements extraction of `raise`, `reraise`, `throw`, and `exit` expressions from Elixir AST. These expressions represent explicit flow control for error signaling and process termination.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.3.4.1 Implement `extract_raise/1` for raise expressions
- 17.3.4.2 Define `%RaiseExpression{exception: ..., message: ..., attributes: ...}` struct
- 17.3.4.3 Extract exception module being raised
- 17.3.4.4 Implement `extract_throw/1` for throw expressions
- 17.3.4.5 Define `%ThrowExpression{value: ..., location: ...}` struct
- 17.3.4.6 Add raise/throw extraction tests

## AST Research

### Raise Patterns

1. **Raise with message string**: `raise "error message"`
   ```elixir
   {:raise, _meta, ["error message"]}
   ```

2. **Raise with exception module only**: `raise RuntimeError`
   ```elixir
   {:raise, _meta, [{:__aliases__, _, [:RuntimeError]}]}
   ```

3. **Raise with exception and message**: `raise ArgumentError, "bad argument"`
   ```elixir
   {:raise, _meta, [{:__aliases__, _, [:ArgumentError]}, "bad argument"]}
   ```

4. **Raise with exception and keyword opts**: `raise RuntimeError, message: "failed"`
   ```elixir
   {:raise, _meta, [{:__aliases__, _, [:RuntimeError]}, [message: "failed"]]}
   ```

5. **Raise with exception struct**: `raise %RuntimeError{message: "oops"}`
   ```elixir
   {:raise, _meta, [{:%, [], [{:__aliases__, _, [:RuntimeError]}, {:%{}, [], [message: "oops"]}]}]}
   ```

### Reraise Patterns

1. **Reraise with stacktrace**: `reraise e, __STACKTRACE__`
   ```elixir
   {:reraise, _meta, [{:e, _, _}, {:__STACKTRACE__, _, _}]}
   ```

2. **Reraise with message and stacktrace**: `reraise "error", stacktrace`
   ```elixir
   {:reraise, _meta, ["error", {:stacktrace, _, _}]}
   ```

### Throw Patterns

1. **Throw with value**: `throw :value`
   ```elixir
   {:throw, _meta, [:value]}
   ```

2. **Throw with tuple**: `throw {:error, :reason}`
   ```elixir
   {:throw, _meta, [error: :reason]}  # Note: keyword list representation
   ```

3. **Throw with variable**: `throw value`
   ```elixir
   {:throw, _meta, [{:value, _, _}]}
   ```

### Exit Patterns

1. **Exit with reason**: `exit :normal`
   ```elixir
   {:exit, _meta, [:normal]}
   ```

2. **Exit with tuple**: `exit {:shutdown, :reason}`
   ```elixir
   {:exit, _meta, [shutdown: :reason]}  # Note: keyword list representation
   ```

## Implementation Plan

### Step 1: Define Structs

Add to `lib/elixir_ontologies/extractors/exception.ex`:

- [x] `RaiseExpression` struct with:
  - `exception` - Exception module or nil (for message-only raise)
  - `message` - Message string or expression
  - `attributes` - Keyword list of exception attributes
  - `is_reraise` - True if this is a reraise
  - `stacktrace` - Stacktrace expression for reraise
  - `location` - Source location

- [x] `ThrowExpression` struct with:
  - `value` - The thrown value
  - `location` - Source location

- [x] `ExitExpression` struct with:
  - `reason` - The exit reason
  - `location` - Source location

### Step 2: Implement Type Predicates

- [x] `raise_expression?/1` - Check if AST is raise/reraise
- [x] `throw_expression?/1` - Check if AST is throw
- [x] `exit_expression?/1` - Check if AST is exit

### Step 3: Implement Extraction Functions

- [x] `extract_raise/2` - Extract raise expression
- [x] `extract_raise!/2` - Extract or raise error
- [x] `extract_throw/2` - Extract throw expression
- [x] `extract_throw!/2` - Extract or raise error
- [x] `extract_exit/2` - Extract exit expression
- [x] `extract_exit!/2` - Extract or raise error

### Step 4: Implement Bulk Extraction

- [x] `extract_raises/2` - Extract all raise expressions from AST
- [x] `extract_throws/2` - Extract all throw expressions from AST
- [x] `extract_exits/2` - Extract all exit expressions from AST

### Step 5: Add Tests

- [x] Test raise with message only
- [x] Test raise with exception module
- [x] Test raise with exception and message
- [x] Test raise with exception and keyword opts
- [x] Test raise with exception struct
- [x] Test reraise with stacktrace
- [x] Test throw with various values
- [x] Test exit with various reasons
- [x] Test bulk extraction functions
- [x] Test error handling for non-matching AST

### Step 6: Quality Checks

- [x] `mix compile --warnings-as-errors`
- [x] `mix credo --strict`
- [x] `mix test`

### Step 7: Complete

- [x] Update phase plan
- [x] Write summary

## Success Criteria

- [x] All raise patterns extracted correctly
- [x] All throw patterns extracted correctly
- [x] All exit patterns extracted correctly
- [x] Reraise distinguished from raise
- [x] Exception module extracted when present
- [x] Message/attributes extracted correctly
- [x] All tests pass
- [x] Quality checks pass
