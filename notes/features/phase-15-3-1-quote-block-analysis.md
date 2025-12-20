# Phase 15.3.1: Quote Block Analysis

## Overview

Enhance the Quote extractor to provide structured quote option analysis with a dedicated `QuoteOptions` struct and additional helper functions.

## Current State

The Quote extractor (`lib/elixir_ontologies/extractors/quote.ex`) already:
- Extracts quote blocks with `extract/1`
- Parses `bind_quoted`, `context`, `location`, `unquote` options into a map
- Finds unquotes within quote blocks
- Has helper functions `has_bind_quoted?/1`, `has_context?/1`, `has_unquotes?/1`

## Requirements from Phase Plan

From `notes/planning/extractors/phase-15.md`:
- 15.3.1.1 Update `lib/elixir_ontologies/extractors/quote.ex` for quote options
- 15.3.1.2 Extract `quote bind_quoted: [...]` bindings
- 15.3.1.3 Extract `quote unquote: false` option
- 15.3.1.4 Extract `quote location: :keep` option
- 15.3.1.5 Extract `quote context: Module` option
- 15.3.1.6 Add quote option tests

## Analysis

Looking at the existing code, most functionality is already present. The enhancement needed is:

1. **QuoteOptions struct** - Create a nested struct for structured option access
2. **Additional options** - Add support for `line:`, `file:`, `generated:` options
3. **Helper functions** - Add more introspection helpers
4. **bind_quoted analysis** - Extract binding names and types

## Technical Design

### QuoteOptions Struct

```elixir
defmodule QuoteOptions do
  @type t :: %__MODULE__{
    bind_quoted: keyword() | nil,
    context: module() | atom() | nil,
    location: :keep | nil,
    unquote: boolean(),
    line: pos_integer() | nil,
    file: String.t() | nil,
    generated: boolean() | nil
  }

  defstruct [
    bind_quoted: nil,
    context: nil,
    location: nil,
    unquote: true,
    line: nil,
    file: nil,
    generated: nil
  ]
end
```

### New Helper Functions

- `location_keep?/1` - Check if location: :keep is set
- `unquoting_disabled?/1` - Check if unquote: false
- `bind_quoted_vars/1` - Get list of bound variable names
- `get_context/1` - Get the context option value
- `generated?/1` - Check if generated: true

## Implementation Plan

### Step 1: Define QuoteOptions Struct
- [x] Create `QuoteOptions` nested module in Quote extractor
- [x] Add all option fields
- [x] Add constructor and type predicates

### Step 2: Update Option Parsing
- [x] Update `parse_quote_options/1` to return `QuoteOptions` struct
- [x] Add support for `line:`, `file:`, `generated:` options
- [x] Update `QuotedExpression` to use `QuoteOptions` struct

### Step 3: Add Helper Functions
- [x] Add `location_keep?/1`
- [x] Add `unquoting_disabled?/1`
- [x] Add `bind_quoted_vars/1`
- [x] Add `get_context/1`
- [x] Add `generated?/1`

### Step 4: Write Tests
- [x] Test QuoteOptions struct creation
- [x] Test all option extraction
- [x] Test helper functions
- [x] Test with quoted code

## Success Criteria

- [x] QuoteOptions struct defined with all fields
- [x] All quote options correctly extracted
- [x] Helper functions provide easy introspection
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes

## Notes

- Maintain backward compatibility with existing API
- The `options` field on `QuotedExpression` will change from map to `QuoteOptions` struct
- Existing tests should continue to pass with minimal changes
