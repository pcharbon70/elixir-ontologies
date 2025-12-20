# Phase 16.1.1: Basic Alias Extraction

## Overview

Create a dedicated extractor for alias directives with detailed extraction of source module, alias name, and source location. This is the foundation for Phase 16's module dependency graph.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.1.1.1 Create `lib/elixir_ontologies/extractors/directive/alias.ex`
- 16.1.1.2 Define `%AliasDirective{source: ..., as: ..., location: ..., scope: ...}` struct
- 16.1.1.3 Extract `alias Module.Name` simple form
- 16.1.1.4 Extract `alias Module.Name, as: Short` explicit form
- 16.1.1.5 Extract computed alias name when `as:` not specified
- 16.1.1.6 Add basic alias tests

## Research Findings

### Existing Module Extractor Pattern

The Module extractor already extracts basic alias info as maps:
```elixir
@type alias_info :: %{
  module: [atom()],
  as: atom() | nil,
  location: SourceLocation.t() | nil
}
```

### Elixir AST for Alias

```elixir
# Simple: alias MyApp.Users
{:alias, meta, [{:__aliases__, _, [:MyApp, :Users]}]}

# With as: alias MyApp.Users, as: U
{:alias, meta, [{:__aliases__, _, [:MyApp, :Users]}, [as: {:__aliases__, _, [:U]}]]}

# Erlang module: alias :crypto
{:alias, meta, [:crypto]}

# Erlang with as: alias :crypto, as: Crypto
{:alias, meta, [:crypto, [as: {:__aliases__, _, [:Crypto]}]]}
```

### Computed Alias Name

When no `as:` option is given, Elixir uses the last segment:
- `alias MyApp.Users` → aliased as `Users`
- `alias MyApp.Users.Admin` → aliased as `Admin`

## Technical Design

### AliasDirective Struct

```elixir
defmodule ElixirOntologies.Extractors.Directive.Alias do
  defmodule AliasDirective do
    @type t :: %__MODULE__{
      source: [atom()],           # Full module path: [:MyApp, :Users]
      as: atom(),                 # Alias name: :Users or :U
      explicit_as: boolean(),     # True if `as:` was explicitly provided
      location: SourceLocation.t() | nil,
      scope: :module | nil,       # For 16.1.3 scope tracking
      metadata: map()
    }

    defstruct [:source, :as, explicit_as: false, location: nil, scope: nil, metadata: %{}]
  end
end
```

### Public API

```elixir
# Type detection
@spec alias?(Macro.t()) :: boolean()

# Main extraction
@spec extract(Macro.t(), keyword()) :: {:ok, AliasDirective.t()} | {:error, term()}
@spec extract!(Macro.t(), keyword()) :: AliasDirective.t()

# Batch extraction from module body
@spec extract_all(Macro.t(), keyword()) :: [AliasDirective.t()]

# Convenience functions
@spec source_module_name(AliasDirective.t()) :: String.t()
@spec aliased_as(AliasDirective.t()) :: atom()
```

## Implementation Plan

### Step 1: Create File Structure
- [x] Create `lib/elixir_ontologies/extractors/directive/alias.ex`
- [x] Add module documentation
- [x] Define AliasDirective struct

### Step 2: Implement Type Detection
- [x] Implement `alias?/1` function

### Step 3: Implement Extract Functions
- [x] Implement `extract/2` for simple alias
- [x] Implement `extract/2` for alias with explicit `as:`
- [x] Implement computed alias name derivation
- [x] Implement `extract!/2` raising version
- [x] Implement `extract_all/2` for batch extraction

### Step 4: Add Convenience Functions
- [x] Implement `source_module_name/1`
- [x] Implement `aliased_as/1`

### Step 5: Write Tests
- [x] Test simple alias extraction
- [x] Test alias with explicit `as:` option
- [x] Test computed alias name derivation
- [x] Test Erlang module alias
- [x] Test location extraction
- [x] Test extract_all with multiple aliases
- [x] Test error cases

## Success Criteria

- [x] AliasDirective struct defined with proper typespec
- [x] `alias?/1` correctly identifies alias AST
- [x] `extract/2` handles all alias forms
- [x] Computed alias name works correctly
- [x] Location extracted properly
- [x] Tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
