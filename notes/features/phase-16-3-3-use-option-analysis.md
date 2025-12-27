# Phase 16.3.3: Use Option Analysis

## Overview

Analyze use options to understand configuration passed to `__using__` callbacks, including parsing keyword options and handling dynamic values.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-16.md`:
- 16.3.3.1 Parse keyword options in use directives
- 16.3.3.2 Track common option patterns (e.g., `use GenServer, restart: :temporary`)
- 16.3.3.3 Extract literal option values
- 16.3.3.4 Handle dynamic option values (mark as unresolved)
- 16.3.3.5 Create `%UseOption{key: ..., value: ..., dynamic: boolean()}` struct
- 16.3.3.6 Add use option analysis tests

## Research Findings

### Use Option AST Patterns

```elixir
# Keyword options - options is a keyword list
{:use, _, [{:__aliases__, _, [:GenServer]}, [restart: :temporary]]}

# Multiple keyword options
{:use, _, [{:__aliases__, _, [:Plug, :Builder]}, [init_mode: :runtime, log_on_halt: :debug]]}

# Non-keyword option - options is a single value
{:use, _, [{:__aliases__, _, [:MyApp, :Web]}, :controller]}

# Variable value (dynamic) - value is a tuple with atom name
[restart: {:some_var, [], Elixir}]

# Module value - value is __aliases__ tuple
[namespace: {:__aliases__, [alias: false], [:MyApp, :Web]}]

# Function call (dynamic) - value contains dot-call tuple
[restart: {{:., [], [{:__aliases__, _, [:String]}, :to_atom]}, [], ["temp"]}]

# Tuple value with nested keyword
[restart: {:one_for_one, [max_restarts: 3]}]

# List value
[callbacks: [:init, :handle_call]]
```

### Value Type Classification

1. **Literal Values** (static, resolvable at analysis time):
   - Atoms: `:temporary`, `:permanent`
   - Strings: `"controller"`
   - Integers: `1`, `100`
   - Floats: `1.5`
   - Booleans: `true`, `false`
   - `nil`
   - Lists of literals: `[:init, :handle_call]`
   - Tuples of literals: `{:one_for_one, 3}`

2. **Module References** (static, resolvable):
   - `{:__aliases__, _, parts}` - e.g., `MyApp.Web`

3. **Dynamic Values** (not resolvable at analysis time):
   - Variable references: `{name, _, context}` where name is atom
   - Function calls: `{{:., _, _}, _, _}`
   - Any AST with unquote

## Technical Design

### UseOption Struct

```elixir
defmodule UseOption do
  @type value_type :: :atom | :string | :integer | :float | :boolean | :nil |
                      :list | :tuple | :module | :dynamic

  @type t :: %__MODULE__{
          key: atom(),
          value: term(),
          value_type: value_type(),
          dynamic: boolean(),
          raw_ast: Macro.t() | nil
        }

  defstruct [:key, :value, :value_type, :raw_ast, dynamic: false]
end
```

### Functions to Add to Use Module

```elixir
# Analyze options from UseDirective
@spec analyze_options(UseDirective.t()) :: [UseOption.t()]

# Parse a single option
@spec parse_option({atom(), term()}) :: UseOption.t()

# Check if value is dynamic
@spec dynamic_value?(term()) :: boolean()

# Get value type
@spec value_type(term()) :: value_type()

# Extract literal value if possible
@spec extract_literal_value(term()) :: {:ok, term()} | {:dynamic, Macro.t()}
```

## Implementation Plan

### Step 1: Add UseOption Struct
- [x] Add UseOption struct to use.ex
- [x] Define value_type type

### Step 2: Implement Value Analysis
- [x] Implement `dynamic_value?/1`
- [x] Implement `value_type/1`
- [x] Implement `extract_literal_value/1`

### Step 3: Implement Option Parsing
- [x] Implement `parse_option/1` for single option
- [x] Implement `analyze_options/1` for UseDirective

### Step 4: Write Tests
- [x] Test literal atom values
- [x] Test literal string values
- [x] Test literal number values
- [x] Test list values
- [x] Test tuple values
- [x] Test module reference values
- [x] Test dynamic variable values
- [x] Test dynamic function call values
- [x] Test analyze_options with keyword list
- [x] Test analyze_options with non-keyword option

## Success Criteria

- [x] UseOption struct defined with proper typespec
- [x] `analyze_options/1` parses UseDirective options
- [x] Literal values correctly extracted
- [x] Dynamic values correctly marked
- [x] Tests pass (40 doctests, 94 tests)
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes (only refactoring suggestions)
