# Phase 16.1.3: Alias Scope Tracking

## Overview

Implement lexical scope detection for alias directives to track whether an alias is defined at module-level, function-level, or block-level.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.1.3.1 Implement scope detection for alias directives
- 16.1.3.2 Track module-level aliases (top of module)
- 16.1.3.3 Track function-level aliases (inside function bodies)
- 16.1.3.4 Track block-level aliases (inside blocks, comprehensions)
- 16.1.3.5 Create `%LexicalScope{type: ..., start_line: ..., end_line: ...}` struct
- 16.1.3.6 Add scope tracking tests

## Research Findings

### Elixir Scope Types

1. **Module-level**: Aliases at the top level of a module body, visible throughout the module
2. **Function-level**: Aliases inside function definitions (`def`, `defp`), visible only within that function
3. **Block-level**: Aliases inside blocks (`if`, `case`, `with`, `for`, etc.), visible only within that block

### AST Structure

```elixir
# Module structure
{:defmodule, meta, [
  {:__aliases__, _, [:Test]},
  [do: {:__block__, [], body_statements}]
]}

# Function structure
{:def, meta, [
  {:name, _, args},
  [do: function_body]
]}
```

### Existing AliasDirective

The `scope` field already exists with type `:module | :function | :block | nil`.

## Technical Design

### LexicalScope Struct

```elixir
defmodule LexicalScope do
  @type scope_type :: :module | :function | :block

  @type t :: %__MODULE__{
    type: scope_type(),
    name: atom() | nil,           # Function name for function scope
    start_line: pos_integer() | nil,
    end_line: pos_integer() | nil,
    parent: t() | nil             # For nested scopes
  }

  defstruct [:type, :name, :start_line, :end_line, :parent]
end
```

### Scope Detection Approach

1. **extract_all_with_scope/2** - New function that extracts aliases with scope context
2. Walk the AST tracking current scope
3. When entering a function, push function scope
4. When entering a block, push block scope
5. When finding an alias, tag it with current scope

### New Functions

```elixir
# Extract all aliases from module with scope tracking
@spec extract_all_with_scope(Macro.t(), keyword()) :: [AliasDirective.t()]

# Detect scope of a single alias given context
@spec detect_scope(Macro.t(), keyword()) :: LexicalScope.t() | nil
```

## Implementation Plan

### Step 1: Create LexicalScope Struct
- [x] Define LexicalScope struct in alias.ex
- [x] Add typespec

### Step 2: Implement Scope Detection
- [x] Add `extract_all_with_scope/2` function
- [x] Implement AST walker tracking scope context
- [x] Handle module-level scope
- [x] Handle function-level scope
- [x] Handle block-level scope

### Step 3: Update AliasDirective
- [x] Populate scope field during extraction
- [x] Update build_directive to accept scope

### Step 4: Write Tests
- [x] Test module-level alias scope
- [x] Test function-level alias scope
- [x] Test block-level alias scope
- [x] Test nested scopes
- [x] Test mixed scopes in same module

## Success Criteria

- [x] LexicalScope struct defined with proper typespec
- [x] `extract_all_with_scope/2` correctly tracks scope
- [x] Module-level aliases tagged correctly
- [x] Function-level aliases tagged correctly
- [x] Block-level aliases tagged correctly
- [x] Tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
