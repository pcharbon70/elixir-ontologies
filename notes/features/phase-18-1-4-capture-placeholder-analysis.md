# Phase 18.1.4: Capture Placeholder Analysis

## Overview

Enhance the Capture extractor with detailed placeholder analysis. While `find_placeholders/1` already provides basic position detection, this task adds:

1. Location tracking for each placeholder usage
2. A `CapturePlaceholder` struct for rich placeholder data
3. Gap detection in placeholder numbering
4. Usage count tracking for each placeholder

## Current State (from 18.1.3)

The `Capture` module has:
- `find_placeholders/1` - Returns sorted list of unique placeholder positions
- `placeholder?/1` - Predicate for `{:&, [], [n]}` nodes
- Shorthand captures store `placeholders: [pos_integer()]` list

## Planned Enhancements

### 1. CapturePlaceholder Struct

```elixir
defmodule CapturePlaceholder do
  @type t :: %__MODULE__{
    position: pos_integer(),        # The &N number (1, 2, 3...)
    usage_count: pos_integer(),     # How many times used in expression
    locations: [SourceLocation.t()], # All usage locations
    metadata: map()
  }
end
```

### 2. PlaceholderAnalysis Struct

```elixir
defmodule PlaceholderAnalysis do
  @type t :: %__MODULE__{
    placeholders: [CapturePlaceholder.t()],  # All placeholders with details
    highest: pos_integer() | nil,             # Highest placeholder number
    arity: non_neg_integer(),                 # Derived arity
    gaps: [pos_integer()],                    # Missing placeholder numbers
    has_gaps: boolean(),
    metadata: map()
  }
end
```

### 3. New Functions

- `extract_capture_placeholders/1` - Extract all placeholders with locations
- `analyze_placeholders/1` - Full analysis including gaps, arity

## Implementation Steps

### Step 1: Define CapturePlaceholder struct
- [ ] Add nested module in Capture
- [ ] Define struct with position, usage_count, locations, metadata

### Step 2: Define PlaceholderAnalysis struct
- [ ] Add nested module in Capture
- [ ] Define struct with placeholders, highest, arity, gaps, has_gaps

### Step 3: Implement extract_capture_placeholders/1
- [ ] Traverse AST finding all `{:&, meta, [n]}` nodes
- [ ] Extract location from metadata for each
- [ ] Group by position, count usages, collect locations

### Step 4: Implement analyze_placeholders/1
- [ ] Use extract_capture_placeholders/1 for data
- [ ] Calculate highest placeholder number
- [ ] Detect gaps (e.g., &1, &3 without &2)
- [ ] Calculate arity from highest

### Step 5: Add comprehensive tests

## Success Criteria

1. `CapturePlaceholder` struct captures position, count, and locations
2. `analyze_placeholders/1` returns complete analysis with gap detection
3. Location tracking works for each placeholder usage
4. All tests pass

## Files to Modify

- `lib/elixir_ontologies/extractors/capture.ex` - Add new structs and functions
- `test/elixir_ontologies/extractors/capture_test.exs` - Add placeholder analysis tests
