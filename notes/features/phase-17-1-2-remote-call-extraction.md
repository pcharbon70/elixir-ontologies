# Phase 17.1.2: Remote Function Call Extraction

## Overview

This task implements extraction of remote function calls from Elixir AST. Remote calls are calls to functions in other modules using the `Module.function(args)` syntax.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.1.2.1 Implement `extract_remote_calls/1` for `Module.function(args)` pattern
- 17.1.2.2 Define `%FunctionCall{type: :remote, module: ..., name: ..., arity: ...}` fields
- 17.1.2.3 Handle aliased module calls (resolve alias to full module name)
- 17.1.2.4 Handle imported function calls (resolve to source module)
- 17.1.2.5 Track whether module is aliased or full name
- 17.1.2.6 Add remote call extraction tests

## Research Findings

### Remote Call AST Patterns

```elixir
# Simple remote call: String.upcase("hello")
{{:., [], [{:__aliases__, [alias: false], [:String]}, :upcase]}, [], ["hello"]}

# Remote call with multiple args: Enum.map([1,2,3], fn x -> x end)
{{:., [], [{:__aliases__, [alias: false], [:Enum]}, :map]}, [], [args...]}

# Erlang module call: :ets.new(:table, [])
{{:., [], [:ets, :new]}, [], [:table, []]}

# Nested module call: MyApp.Services.User.create(%{})
{{:., [], [{:__aliases__, [alias: false], [:MyApp, :Services, :User]}, :create]}, [], [args]}

# Call on variable (dynamic - handled in 17.1.3): mod.func(x)
{{:., [], [{:mod, [], Elixir}, :func]}, [], [{:x, [], Elixir}]}

# __MODULE__ call: __MODULE__.helper()
{{:., [], [{:__MODULE__, [], Elixir}, :helper]}, [], []}
```

### Key AST Pattern Structure

Remote calls have this general structure:
```elixir
{{:., meta, [receiver, function_name]}, call_meta, args}
```

Where `receiver` can be:
1. `{:__aliases__, _, module_parts}` - Standard Elixir module
2. `atom` - Erlang module (like `:ets`)
3. `{:__MODULE__, _, _}` - Current module reference
4. `{var_name, _, context}` - Variable (dynamic, not statically resolved)

### Design Decisions

1. **Extend FunctionCall struct** - Add `:module` field for remote calls
2. **Module representation** - Store as list of atoms `[:MyApp, :User]` for Elixir, single atom for Erlang
3. **Track alias info** - Store in metadata whether module was aliased
4. **Imported functions** - Cannot be resolved without alias context (deferred to later)
5. **Dynamic receivers** - Mark as unresolved in metadata

## Technical Design

### Updated FunctionCall Struct

```elixir
@type t :: %__MODULE__{
  type: call_type(),
  name: atom(),
  arity: non_neg_integer(),
  module: [atom()] | atom() | nil,  # NEW: module for remote calls
  arguments: [Macro.t()],
  location: SourceLocation.t() | nil,
  metadata: map()
}

defstruct [:type, :name, :arity, :module, arguments: [], location: nil, metadata: %{}]
```

### Functions to Add

```elixir
# Type predicate
@spec remote_call?(Macro.t()) :: boolean()

# Single remote call extraction
@spec extract_remote(Macro.t(), keyword()) :: {:ok, FunctionCall.t()} | {:error, term()}

# Raising version
@spec extract_remote!(Macro.t(), keyword()) :: FunctionCall.t()

# Bulk extraction from AST
@spec extract_remote_calls(Macro.t(), keyword()) :: [FunctionCall.t()]

# Combined extraction (both local and remote)
@spec extract_all_calls(Macro.t(), keyword()) :: [FunctionCall.t()]
```

## Implementation Plan

### Step 1: Update FunctionCall Struct ✅
- [x] Add `:module` field to struct
- [x] Update typespec

### Step 2: Implement Type Detection ✅
- [x] Implement `remote_call?/1` predicate
- [x] Handle all receiver types

### Step 3: Implement Extraction ✅
- [x] Implement `extract_remote/2` for single call
- [x] Implement `extract_remote!/2` raising version
- [x] Extract module from `__aliases__`
- [x] Extract module from Erlang atoms
- [x] Handle `__MODULE__` receiver

### Step 4: Implement Bulk Extraction ✅
- [x] Implement `extract_remote_calls/2`
- [x] Integrate with existing AST walking
- [x] Implement `extract_all_calls/2` for combined extraction

### Step 5: Track Alias Information ✅
- [x] Store original module reference in metadata
- [x] Mark `__MODULE__` calls in metadata
- [x] Mark dynamic receivers in metadata

### Step 6: Write Tests ✅
- [x] Test `remote_call?/1` predicate
- [x] Test simple module.function extraction
- [x] Test Erlang module extraction
- [x] Test nested module extraction
- [x] Test `__MODULE__` calls
- [x] Test dynamic receiver detection
- [x] Test bulk extraction
- [x] Test combined extraction
- [x] Test location tracking

## Success Criteria

- [x] FunctionCall struct extended with `:module` field
- [x] `remote_call?/1` correctly identifies remote calls
- [x] Elixir modules extracted as `[:Module, :Name]`
- [x] Erlang modules extracted as atoms
- [x] `__MODULE__` calls marked in metadata
- [x] Dynamic receivers marked as unresolved
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only pre-existing suggestions)

## Notes

- Imported function resolution requires alias context not available at AST level
- This will be addressed in call graph builder phase where context is available
- Dynamic receivers (variable modules) are detected but not resolved
