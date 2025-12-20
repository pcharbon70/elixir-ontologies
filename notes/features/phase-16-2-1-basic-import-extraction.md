# Phase 16.2.1: Basic Import Extraction

## Overview

Implement basic extraction of import directives with their module references. This is the foundation for later selective import extraction (16.2.2).

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.2.1.1 Create `lib/elixir_ontologies/extractors/directive/import.ex`
- 16.2.1.2 Define `%ImportDirective{module: ..., only: ..., except: ..., location: ..., scope: ...}` struct
- 16.2.1.3 Extract `import Module` full import form
- 16.2.1.4 Extract imported module reference
- 16.2.1.5 Track import location
- 16.2.1.6 Add basic import tests

## Research Findings

### Import AST Structure

```elixir
# Basic import
{:import, [context: Elixir], [{:__aliases__, [alias: false], [:Enum]}]}

# Import with only (function list)
{:import, [context: Elixir],
 [{:__aliases__, [alias: false], [:Enum]}, [only: [map: 2, filter: 2]]]}

# Import with except
{:import, [context: Elixir],
 [{:__aliases__, [alias: false], [:Enum]}, [except: [map: 2]]]}

# Import only :functions
{:import, [context: Elixir],
 [{:__aliases__, [alias: false], [:Enum]}, [only: :functions]]}

# Import only :macros
{:import, [context: Elixir],
 [{:__aliases__, [alias: false], [:Kernel]}, [only: :macros]]}
```

### Key Observations

1. Import uses `{:import, meta, [module_ref]}` or `{:import, meta, [module_ref, opts]}` structure
2. Module reference is `{:__aliases__, meta, [...]}` for Elixir modules
3. Module reference is an atom for Erlang modules
4. Options are keyword list with `:only` and/or `:except` keys
5. `:only` can be a function/arity list or the atoms `:functions`/`:macros`/`:sigils`

## Technical Design

### ImportDirective Struct

```elixir
defmodule ImportDirective do
  @type import_selector :: [{atom(), non_neg_integer()}] | :functions | :macros | :sigils | nil

  @type t :: %__MODULE__{
          module: [atom()] | atom(),
          only: import_selector(),
          except: [{atom(), non_neg_integer()}] | nil,
          location: SourceLocation.t() | nil,
          scope: :module | :function | :block | nil,
          metadata: map()
        }

  defstruct [:module, only: nil, except: nil, location: nil, scope: nil, metadata: %{}]
end
```

### Functions to Implement

```elixir
# Type detection
@spec import?(Macro.t()) :: boolean()

# Basic extraction
@spec extract(Macro.t(), keyword()) :: {:ok, ImportDirective.t()} | {:error, term()}
@spec extract!(Macro.t(), keyword()) :: ImportDirective.t()

# Extract all imports from module body
@spec extract_all(Macro.t(), keyword()) :: [ImportDirective.t()]

# Convenience functions
@spec module_name(ImportDirective.t()) :: String.t()
```

## Implementation Plan

### Step 1: Create Import Module
- [x] Create `lib/elixir_ontologies/extractors/directive/import.ex`
- [x] Add moduledoc with examples
- [x] Define ImportDirective struct

### Step 2: Implement Type Detection
- [x] Add `import?/1` function

### Step 3: Implement Basic Extraction
- [x] Implement `extract/2` for basic import form
- [x] Implement `extract/2` for import with options (only/except)
- [x] Handle Erlang module imports
- [x] Extract location

### Step 4: Implement extract_all
- [x] Implement `extract_all/2` for module body

### Step 5: Add Convenience Functions
- [x] Implement `module_name/1`

### Step 6: Write Tests
- [x] Test basic import extraction
- [x] Test import with only option (function list)
- [x] Test import with except option
- [x] Test import with only: :functions
- [x] Test import with only: :macros
- [x] Test Erlang module import
- [x] Test location extraction
- [x] Test extract_all

## Success Criteria

- [x] ImportDirective struct defined with proper typespec
- [x] `import?/1` correctly identifies import AST
- [x] `extract/2` handles all basic import forms
- [x] Location is properly extracted
- [x] Tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
