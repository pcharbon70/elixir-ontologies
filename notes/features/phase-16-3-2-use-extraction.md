# Phase 16.3.2: Use Extraction

## Overview

Implement extraction of use directives which invoke the `__using__/1` macro of a module, allowing modules to inject code at compile time.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.3.2.1 Create `lib/elixir_ontologies/extractors/directive/use.ex`
- 16.3.2.2 Define `%UseDirective{module: ..., options: [...], location: ..., scope: ...}` struct
- 16.3.2.3 Extract `use Module` form
- 16.3.2.4 Extract `use Module, option: value` form with all options
- 16.3.2.5 Track use as macro invocation of __using__/1
- 16.3.2.6 Add use extraction tests

## Research Findings

### Use AST Structure

```elixir
# Basic use
{:use, [context: Elixir, imports: ...], [{:__aliases__, [alias: false], [:GenServer]}]}

# Use with keyword options
{:use, [...], [{:__aliases__, [...], [:GenServer]}, [restart: :temporary]]}

# Use with multiple options
{:use, [...], [{:__aliases__, [...], [:Plug, :Builder]}, [init_mode: :runtime, log_on_halt: :debug]]}

# Use with non-keyword option (single atom)
{:use, [...], [{:__aliases__, [...], [:MyApp, :Web]}, :controller]}
```

### Key Observations

1. Use is similar to require/import but with options instead of as/only/except
2. Options can be a keyword list or a single value (like `:controller`)
3. The use invokes `__using__/1` callback in the target module
4. Options are passed directly to `__using__/1`

## Technical Design

### UseDirective Struct

```elixir
defmodule UseDirective do
  @type use_options :: keyword() | term() | nil

  @type t :: %__MODULE__{
          module: [atom()] | atom(),
          options: use_options(),
          location: SourceLocation.t() | nil,
          scope: :module | :function | :block | nil,
          metadata: map()
        }

  defstruct [:module, :options, :location, :scope, metadata: %{}]
end
```

### Functions to Implement

```elixir
# Type detection
@spec use?(Macro.t()) :: boolean()

# Basic extraction
@spec extract(Macro.t(), keyword()) :: {:ok, UseDirective.t()} | {:error, term()}
@spec extract!(Macro.t(), keyword()) :: UseDirective.t()

# Extract all from module body
@spec extract_all(Macro.t(), keyword()) :: [UseDirective.t()]

# Scope-aware extraction
@spec extract_all_with_scope(Macro.t(), keyword()) :: [UseDirective.t()]

# Convenience
@spec module_name(UseDirective.t()) :: String.t()
@spec has_options?(UseDirective.t()) :: boolean()
```

## Implementation Plan

### Step 1: Create Use Module
- [x] Create `lib/elixir_ontologies/extractors/directive/use.ex`
- [x] Add moduledoc with examples
- [x] Define UseDirective struct

### Step 2: Implement Type Detection
- [x] Add `use?/1` function

### Step 3: Implement Basic Extraction
- [x] Implement `extract/2` for basic use
- [x] Implement `extract/2` for use with keyword options
- [x] Handle non-keyword options (single values)
- [x] Extract location

### Step 4: Implement extract_all
- [x] Implement `extract_all/2` for module body

### Step 5: Implement Scope Tracking
- [x] Implement `extract_all_with_scope/2`

### Step 6: Write Tests
- [x] Test basic use extraction
- [x] Test use with keyword options
- [x] Test use with single value option
- [x] Test location extraction
- [x] Test extract_all
- [x] Test scope tracking

## Success Criteria

- [x] UseDirective struct defined with proper typespec
- [x] `use?/1` correctly identifies use AST
- [x] `extract/2` handles all use forms
- [x] Options correctly extracted (keyword and non-keyword)
- [x] Scope tracking works correctly
- [x] Tests pass (18 doctests, 46 tests)
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only refactoring suggestions)
