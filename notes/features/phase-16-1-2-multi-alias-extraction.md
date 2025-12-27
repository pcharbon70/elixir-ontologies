# Phase 16.1.2: Multi-Alias Extraction

## Overview

Extend the alias extractor to handle multi-alias forms using the curly brace syntax (`alias Module.{A, B, C}`), including nested multi-alias patterns.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.1.2.1 Implement `extract_multi_alias/1` for `alias Module.{A, B, C}` syntax
- 16.1.2.2 Expand multi-alias into individual alias directives
- 16.1.2.3 Track source location for each expanded alias
- 16.1.2.4 Handle nested multi-alias (e.g., `alias Module.{Sub.{A, B}, C}`)
- 16.1.2.5 Preserve relationship to original multi-alias form
- 16.1.2.6 Add multi-alias tests

## Research Findings

### Multi-Alias AST Structure

```elixir
# alias MyApp.{Users, Accounts}
{:alias, meta,
 [
   {{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [],
    [
      {:__aliases__, [], [:Users]},
      {:__aliases__, [], [:Accounts]}
    ]}
 ]}

# alias MyApp.Sub.{A, B}
{:alias, meta,
 [
   {{:., [], [{:__aliases__, [], [:MyApp, :Sub]}, :{}]}, [],
    [{:__aliases__, [], [:A]}, {:__aliases__, [], [:B]}]}
 ]}

# alias MyApp.{Sub.A, Sub.B} (nested in braces)
{:alias, meta,
 [
   {{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [],
    [
      {:__aliases__, [], [:Sub, :A]},
      {:__aliases__, [], [:Sub, :B]}
    ]}
 ]}

# alias MyApp.{Sub.{A, B}, Other} (deeply nested)
{:alias, meta,
 [
   {{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [],
    [
      {{:., [], [{:__aliases__, [], [:Sub]}, :{}]}, [],
       [
         {:__aliases__, [], [:A]},
         {:__aliases__, [], [:B]}
       ]},
      {:__aliases__, [], [:Other]}
    ]}
 ]}
```

### Key Observations

1. Multi-alias uses `{{:., [], [prefix, :{}]}, [], suffixes}` structure
2. `prefix` is `{:__aliases__, [], [...]}` with the common prefix
3. `suffixes` is a list of either:
   - `{:__aliases__, [], [...]}` for simple suffixes
   - Another `{{:., [], [prefix, :{}]}, [], ...}` for nested multi-alias
4. The `:{}` atom identifies the curly brace syntax

## Technical Design

### MultiAliasGroup Struct (for tracking original form)

```elixir
defmodule MultiAliasGroup do
  @type t :: %__MODULE__{
    prefix: [atom()],
    aliases: [AliasDirective.t()],
    location: SourceLocation.t() | nil,
    metadata: map()
  }

  defstruct [:prefix, aliases: [], location: nil, metadata: %{}]
end
```

### Extended AliasDirective

Add a field to track multi-alias origin:
```elixir
# Add to AliasDirective metadata:
%{
  from_multi_alias: true,
  multi_alias_prefix: [:MyApp],
  multi_alias_index: 0  # position in the original group
}
```

### New Functions

```elixir
# Detect multi-alias form
@spec multi_alias?(Macro.t()) :: boolean()

# Extract multi-alias, returning individual directives
@spec extract_multi_alias(Macro.t(), keyword()) :: {:ok, [AliasDirective.t()]} | {:error, term()}

# Extract with group info preserved
@spec extract_multi_alias_group(Macro.t(), keyword()) :: {:ok, MultiAliasGroup.t()} | {:error, term()}
```

## Implementation Plan

### Step 1: Add MultiAliasGroup Struct
- [x] Define MultiAliasGroup struct in alias.ex
- [x] Add typespec

### Step 2: Implement Type Detection
- [x] Add `multi_alias?/1` function
- [x] Update `alias?/1` to include multi-alias forms

### Step 3: Implement Multi-Alias Extraction
- [x] Implement `extract_multi_alias/2` returning list of AliasDirective
- [x] Handle simple multi-alias (`alias A.{B, C}`)
- [x] Handle nested suffixes (`alias A.{B.C, D.E}`)
- [x] Handle deeply nested multi-alias (`alias A.{B.{C, D}, E}`)

### Step 4: Implement Group Extraction
- [x] Implement `extract_multi_alias_group/2`
- [x] Track prefix and all expanded aliases
- [x] Preserve location

### Step 5: Update extract_all
- [x] Update `extract_all/2` to handle multi-alias forms

### Step 6: Write Tests
- [x] Test simple multi-alias
- [x] Test multi-alias with nested prefix
- [x] Test nested suffixes in braces
- [x] Test deeply nested multi-alias
- [x] Test multi-alias metadata tracking
- [x] Test extract_all with mixed aliases

## Success Criteria

- [x] `multi_alias?/1` correctly identifies multi-alias AST
- [x] `extract_multi_alias/2` expands to individual directives
- [x] Nested multi-alias handled correctly
- [x] Original multi-alias relationship preserved in metadata
- [x] Tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
