# Phase 16.3.1: Require Extraction

## Overview

Implement extraction of require directives needed for macro availability. The require directive makes a module's macros available for use at compile time.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.3.1.1 Create `lib/elixir_ontologies/extractors/directive/require.ex`
- 16.3.1.2 Define `%RequireDirective{module: ..., as: ..., location: ..., scope: ...}` struct
- 16.3.1.3 Extract `require Module` form
- 16.3.1.4 Extract `require Module, as: Short` form
- 16.3.1.5 Track which macros become available via require
- 16.3.1.6 Add require extraction tests

## Research Findings

### Require AST Structure

```elixir
# Basic require
{:require, [context: Elixir], [{:__aliases__, [alias: false], [:Logger]}]}

# Require with as
{:require, [context: Elixir],
 [{:__aliases__, [alias: false], [:Logger]}, [as: {:__aliases__, [alias: false], [:L]}]]}

# Erlang module
{:require, [context: Elixir], [:ets]}

# Multi-part module
{:require, [context: Elixir], [{:__aliases__, [alias: false], [:MyApp, :Macros]}]}
```

### Key Observations

1. Very similar structure to import and alias
2. Has optional `as:` option for aliasing (same as alias)
3. Erlang modules can be required (atom instead of __aliases__)
4. Purpose is to make macros available at compile time

### Note on 16.3.1.5

"Track which macros become available via require" cannot be done statically without analyzing the required module. We'll note this in metadata but won't implement full macro tracking.

## Technical Design

### RequireDirective Struct

```elixir
defmodule RequireDirective do
  @type t :: %__MODULE__{
          module: [atom()] | atom(),
          as: atom() | nil,
          location: SourceLocation.t() | nil,
          scope: :module | :function | :block | nil,
          metadata: map()
        }

  defstruct [:module, :as, :location, :scope, metadata: %{}]
end
```

### Functions to Implement

```elixir
# Type detection
@spec require?(Macro.t()) :: boolean()

# Basic extraction
@spec extract(Macro.t(), keyword()) :: {:ok, RequireDirective.t()} | {:error, term()}
@spec extract!(Macro.t(), keyword()) :: RequireDirective.t()

# Extract all from module body
@spec extract_all(Macro.t(), keyword()) :: [RequireDirective.t()]

# Scope-aware extraction
@spec extract_all_with_scope(Macro.t(), keyword()) :: [RequireDirective.t()]

# Convenience
@spec module_name(RequireDirective.t()) :: String.t()
```

## Implementation Plan

### Step 1: Create Require Module
- [x] Create `lib/elixir_ontologies/extractors/directive/require.ex`
- [x] Add moduledoc with examples
- [x] Define RequireDirective struct

### Step 2: Implement Type Detection
- [x] Add `require?/1` function

### Step 3: Implement Basic Extraction
- [x] Implement `extract/2` for basic require
- [x] Implement `extract/2` for require with as option
- [x] Handle Erlang module requires
- [x] Extract location

### Step 4: Implement extract_all
- [x] Implement `extract_all/2` for module body

### Step 5: Implement Scope Tracking
- [x] Implement `extract_all_with_scope/2`

### Step 6: Write Tests
- [x] Test basic require extraction
- [x] Test require with as option
- [x] Test Erlang module require
- [x] Test location extraction
- [x] Test extract_all
- [x] Test scope tracking

## Success Criteria

- [x] RequireDirective struct defined with proper typespec
- [x] `require?/1` correctly identifies require AST
- [x] `extract/2` handles all require forms
- [x] Scope tracking works correctly
- [x] Tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
