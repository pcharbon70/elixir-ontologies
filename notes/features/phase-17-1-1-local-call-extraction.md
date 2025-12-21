# Phase 17.1.1: Local Function Call Extraction

## Overview

This task implements extraction of local function calls from Elixir AST. Local calls are calls to functions defined in the same module, represented in AST as `{name, meta, args}` where `name` is an atom and `args` is a list.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.1.1.1 Create `lib/elixir_ontologies/extractors/call.ex`
- 17.1.1.2 Define `%FunctionCall{type: :local, name: ..., arity: ..., arguments: ..., location: ...}` struct
- 17.1.1.3 Implement `extract_local_calls/1` finding all local function calls in AST
- 17.1.1.4 Distinguish calls from variable references
- 17.1.1.5 Track call site location
- 17.1.1.6 Add local call extraction tests

## Research Findings

### Local Call AST Patterns

```elixir
# Simple local call: foo()
{:foo, [line: 1], []}

# Local call with args: bar(1, 2)
{:bar, [line: 2], [1, 2]}

# Call with variable args: baz(x, y)
{:baz, [line: 3], [{:x, [], nil}, {:y, [], nil}]}

# Zero-arity call (could be confused with variable)
{:my_func, [line: 4], []}  # call if there's a function my_func/0 defined
{:my_var, [line: 4], nil}  # variable reference (context is atom or nil, not list)
```

### Key Distinction: Calls vs Variables

The critical difference between a local function call and a variable reference:

```elixir
# Variable reference - args is nil (atom context)
{:x, [line: 1], nil}
{:x, [line: 1], Elixir}

# Local function call - args is a list (even if empty)
{:foo, [line: 1], []}
```

**Rule**: If the third element is `nil` or an atom (module context), it's a variable. If it's a list, it's a function call.

### Special Forms to Exclude

Not all `{atom, meta, list}` tuples are local calls. We must exclude:
- Definition forms: `def`, `defp`, `defmacro`, `defmodule`, etc.
- Control flow: `if`, `unless`, `case`, `cond`, `with`, `for`, `try`, `receive`
- Directives: `import`, `require`, `use`, `alias`
- Operators: `|>`, `=`, `|`, etc.
- Special forms: `fn`, `quote`, `unquote`, `super`, `__block__`, `__aliases__`

The `Helpers.special_forms()` list provides these exclusions.

## Technical Design

### FunctionCall Struct

```elixir
defmodule FunctionCall do
  @typedoc """
  Represents a function call extracted from AST.

  - `:type` - Call type (:local, :remote, :dynamic)
  - `:name` - Function name as atom
  - `:arity` - Number of arguments
  - `:arguments` - List of argument AST nodes
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """

  @type call_type :: :local | :remote | :dynamic

  @type t :: %__MODULE__{
    type: call_type(),
    name: atom(),
    arity: non_neg_integer(),
    arguments: [Macro.t()],
    location: SourceLocation.t() | nil,
    metadata: map()
  }

  @enforce_keys [:type, :name, :arity]
  defstruct [:type, :name, :arity, arguments: [], location: nil, metadata: %{}]
end
```

### Functions to Implement

```elixir
# Type predicate
@spec local_call?(Macro.t()) :: boolean()

# Single extraction
@spec extract(Macro.t(), keyword()) :: {:ok, FunctionCall.t()} | {:error, term()}

# Raising version
@spec extract!(Macro.t(), keyword()) :: FunctionCall.t()

# Bulk extraction from AST
@spec extract_local_calls(Macro.t(), keyword()) :: [FunctionCall.t()]

# Helper to check if name is a special form
defp special_form_or_operator?(name)
```

## Implementation Plan

### Step 1: Create Call Module and FunctionCall Struct ✅
- [x] Create `lib/elixir_ontologies/extractors/call.ex`
- [x] Define FunctionCall struct with typespec
- [x] Add moduledoc with examples

### Step 2: Implement Type Detection ✅
- [x] Implement `local_call?/1` predicate
- [x] Handle special forms exclusion
- [x] Distinguish calls from variables

### Step 3: Implement Extraction ✅
- [x] Implement `extract/2` for single call
- [x] Implement `extract!/2` raising version
- [x] Implement `extract_local_calls/1` for bulk extraction
- [x] Track location via Helpers

### Step 4: Implement AST Walking ✅
- [x] Walk module body for calls
- [x] Walk function bodies
- [x] Handle nested blocks and control flow
- [x] Recurse into arguments

### Step 5: Write Tests ✅
- [x] Test `local_call?/1` predicate
- [x] Test simple call extraction
- [x] Test call with arguments
- [x] Test variable vs call distinction
- [x] Test special form exclusion
- [x] Test bulk extraction
- [x] Test location tracking
- [x] Test nested calls

## Success Criteria

- [x] FunctionCall struct defined with proper typespec
- [x] `local_call?/1` correctly identifies local calls
- [x] Variables are NOT extracted as calls
- [x] Special forms are NOT extracted as calls
- [x] Location tracking works correctly
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only pre-existing suggestions)
