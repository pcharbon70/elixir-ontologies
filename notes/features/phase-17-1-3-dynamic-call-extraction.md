# Phase 17.1.3: Dynamic Call Extraction

## Overview

This task implements extraction of dynamic function calls from Elixir AST. Dynamic calls are calls where the target function or module cannot be determined at compile time, including `apply/2`, `apply/3`, and anonymous function invocations (`fun.(args)`).

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.1.3.1 Implement `extract_dynamic_calls/1` for apply patterns
- 17.1.3.2 Define `%FunctionCall{type: :dynamic, ...}` for unresolved targets
- 17.1.3.3 Detect `apply(module, function, args)` calls
- 17.1.3.4 Detect `fun.(args)` anonymous function calls
- 17.1.3.5 Track known vs unknown targets
- 17.1.3.6 Add dynamic call extraction tests

## Research Findings

### Dynamic Call AST Patterns

```elixir
# apply/3 with module and function atoms
{:apply, meta, [{:__aliases__, _, [:Module]}, :func, [1, 2]]}

# apply/2 with function reference
{:apply, meta, [{:fun, [], Elixir}, [1, 2]]}

# Kernel.apply/3 (remote call to apply)
{{:., [], [{:__aliases__, [], [:Kernel]}, :apply]}, [], [module, func, args]}

# Anonymous function call: fun.(arg)
{{:., [], [{:fun, [], Elixir}]}, [], [arg]}

# Anonymous function call: callback.(1, 2, 3)
{{:., [], [{:callback, [], Elixir}]}, [], [1, 2, 3]}
```

### Key Distinctions

1. **apply/3**: `{:apply, meta, [module, function, args_list]}`
   - Module can be literal or variable
   - Function can be atom or variable
   - Args is always a list

2. **apply/2**: `{:apply, meta, [fun, args_list]}`
   - Fun is a captured function or variable
   - Args is a list

3. **Anonymous function call**: `{{:., [], [fun_var]}, [], args}`
   - The dot call with single element (no function name)
   - Fun_var is a variable holding a function

### Design Decisions

1. **Dynamic type already exists** - FunctionCall struct has `:dynamic` type
2. **Track what's known** - Store known module/function in metadata when determinable
3. **Distinguish apply types** - Track whether it's apply/2, apply/3, or anon call
4. **Handle Kernel.apply** - Detect remote call to Kernel.apply as dynamic

## Technical Design

### Dynamic Call Subtypes (in metadata)

```elixir
# For apply/3 with known module
%{dynamic_type: :apply_3, known_module: [:Module], known_function: :func}

# For apply/3 with variable module
%{dynamic_type: :apply_3, module_variable: :mod, function_variable: :func}

# For apply/2
%{dynamic_type: :apply_2, function_variable: :fun}

# For anonymous function call
%{dynamic_type: :anonymous_call, function_variable: :callback}
```

### Functions to Add

```elixir
# Type predicate
@spec dynamic_call?(Macro.t()) :: boolean()

# Single dynamic call extraction
@spec extract_dynamic(Macro.t(), keyword()) :: {:ok, FunctionCall.t()} | {:error, term()}

# Raising version
@spec extract_dynamic!(Macro.t(), keyword()) :: FunctionCall.t()

# Bulk extraction from AST
@spec extract_dynamic_calls(Macro.t(), keyword()) :: [FunctionCall.t()]
```

## Implementation Plan

### Step 1: Implement Type Detection ✅
- [x] Implement `dynamic_call?/1` predicate
- [x] Handle apply/3 pattern
- [x] Handle apply/2 pattern
- [x] Handle anonymous function call pattern
- [x] Handle Kernel.apply/3 remote call

### Step 2: Implement Extraction ✅
- [x] Implement `extract_dynamic/2` for single call
- [x] Implement `extract_dynamic!/2` raising version
- [x] Extract known module/function when literal
- [x] Track variable names when dynamic
- [x] Set appropriate metadata

### Step 3: Implement Bulk Extraction ✅
- [x] Implement `extract_dynamic_calls/2`
- [x] Update `extract_all_calls/2` to include dynamic calls

### Step 4: Write Tests ✅
- [x] Test `dynamic_call?/1` predicate
- [x] Test apply/3 extraction
- [x] Test apply/2 extraction
- [x] Test anonymous function call extraction
- [x] Test Kernel.apply/3 extraction
- [x] Test bulk extraction
- [x] Test combined extraction with all types

## Success Criteria

- [x] `dynamic_call?/1` correctly identifies dynamic calls
- [x] apply/3, apply/2, and anonymous calls extracted
- [x] Known targets stored in metadata
- [x] Variable names tracked for unknown targets
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only pre-existing suggestions)
