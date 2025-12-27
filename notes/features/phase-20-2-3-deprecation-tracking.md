# Phase 20.2.3: Deprecation Tracking

## Overview

Track deprecation activities and their timeline. This module detects `@deprecated` attributes in Elixir code and tracks when functions/modules are deprecated and eventually removed.

## Requirements

From phase-20.md task 20.2.3:

- [x] 20.2.3.1 Define `%Deprecation{element: ..., deprecated_in: ..., removed_in: ..., replacement: ...}` struct
- [x] 20.2.3.2 Detect @deprecated attribute additions
- [x] 20.2.3.3 Track deprecation announcement commits
- [x] 20.2.3.4 Track removal commits
- [x] 20.2.3.5 Extract suggested replacement from deprecation message
- [x] 20.2.3.6 Add deprecation tracking tests (29 tests)

## Design

### Elixir Deprecation Patterns

Elixir uses `@deprecated` module attribute to mark deprecated functions:

```elixir
@deprecated "Use new_function/1 instead"
def old_function(arg), do: ...

@deprecated "This module will be removed in v2.0"
defmodule OldModule do
  ...
end
```

### Struct Design

```elixir
defmodule Deprecation do
  @type element_type :: :function | :module | :macro | :callback

  @type t :: %__MODULE__{
    element_type: element_type(),
    element_name: String.t(),
    module: String.t(),
    function: {atom(), non_neg_integer()} | nil,
    deprecated_in: DeprecationEvent.t() | nil,
    removed_in: RemovalEvent.t() | nil,
    replacement: Replacement.t() | nil,
    message: String.t(),
    metadata: map()
  }
end

defmodule DeprecationEvent do
  @type t :: %__MODULE__{
    commit: Commit.t(),
    file: String.t(),
    line: pos_integer()
  }
end

defmodule RemovalEvent do
  @type t :: %__MODULE__{
    commit: Commit.t(),
    file: String.t()
  }
end

defmodule Replacement do
  @type t :: %__MODULE__{
    text: String.t(),
    function: {atom(), non_neg_integer()} | nil,
    module: String.t() | nil
  }
end
```

### Detection Strategies

1. **@deprecated Attribute Detection**
   - Parse diff additions for `@deprecated` patterns
   - Extract deprecation message
   - Associate with following function/macro definition

2. **Deprecation Commit Tracking**
   - Find commits that add `@deprecated` attributes
   - Link to specific file and line

3. **Removal Tracking**
   - Detect when deprecated function is removed
   - Match removed function with previous deprecation

4. **Replacement Extraction**
   - Parse deprecation message for replacement hints
   - Common patterns: "Use X instead", "See Y", "Replaced by Z"

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/deprecation.ex`
- [x] Define Deprecation struct
- [x] Define DeprecationEvent struct
- [x] Define RemovalEvent struct
- [x] Define Replacement struct
- [x] Add type specs and moduledoc

### Step 2: Deprecation Detection
- [x] Implement `detect_deprecations/2` from diff
- [x] Parse @deprecated attribute pattern
- [x] Extract deprecation message
- [x] Associate with function/macro definition

### Step 3: Replacement Parsing
- [x] Implement `parse_replacement/1`
- [x] Handle "Use X instead" pattern
- [x] Handle "See X" pattern
- [x] Handle "Replaced by X" pattern
- [x] Extract function/module references

### Step 4: Commit Tracking
- [x] Implement `find_deprecation_commits/2`
- [x] Search history for @deprecated additions
- [x] Build deprecation timeline

### Step 5: Removal Detection
- [x] Implement `detect_removals/2`
- [x] Find removed functions that were deprecated
- [x] Match with deprecation records

### Step 6: Main API
- [x] Implement `track_deprecations/3`
- [x] Combine detection and tracking
- [x] Return list of Deprecation structs

### Step 7: Testing
- [x] Add deprecation detection tests
- [x] Add replacement parsing tests
- [x] Add commit tracking tests
- [x] Add removal detection tests
- [x] Add integration tests
- [x] All 29 tests passing

## Success Criteria

1. All 6 subtasks completed
2. @deprecated detection works
3. Replacement extraction works
4. Deprecation timeline tracking works
5. Removal detection works
6. All tests passing

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/extractors/evolution/deprecation.ex`
- `test/elixir_ontologies/extractors/evolution/deprecation_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)
