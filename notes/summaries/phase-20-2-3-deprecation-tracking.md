# Phase 20.2.3: Deprecation Tracking - Summary

## Overview

Implemented deprecation tracking module that detects `@deprecated` attributes in Elixir code and tracks when functions/modules are deprecated and eventually removed.

## Implementation

### Module: `ElixirOntologies.Extractors.Evolution.Deprecation`

Created `lib/elixir_ontologies/extractors/evolution/deprecation.ex` with the following components:

#### Nested Structs

1. **`DeprecationEvent`** - When and where a deprecation was announced:
   - `commit` - The commit that added the deprecation
   - `file` - File path
   - `line` - Line number

2. **`RemovalEvent`** - When and where a deprecated element was removed:
   - `commit` - The commit that removed the element
   - `file` - File path

3. **`Replacement`** - Suggested replacement for deprecated element:
   - `text` - Original deprecation message
   - `function` - Extracted function reference `{name, arity}`
   - `module` - Extracted module name

4. **`Deprecation`** (main struct):
   - `element_type` - `:function`, `:module`, `:macro`, `:callback`, or `:type`
   - `element_name` - Name of deprecated element
   - `module` - Module containing the element
   - `function` - Function tuple if applicable
   - `deprecated_in` - DeprecationEvent when added
   - `removed_in` - RemovalEvent when removed
   - `replacement` - Parsed replacement info
   - `message` - Original deprecation message
   - `metadata` - Additional information

#### Key Functions

- `detect_deprecations/2` - Detect deprecations added in a commit
- `detect_deprecations!/2` - Bang variant
- `detect_removals/2` - Detect removed deprecated elements
- `track_deprecations/3` - Track deprecation history for a file
- `find_deprecation_commits/2` - Find commits with @deprecated additions
- `parse_replacement/1` - Parse deprecation message for replacement info
- `has_replacement?/1` - Check if deprecation has known replacement
- `removed?/1` - Check if deprecated element was removed

#### Replacement Parsing

Extracts function/module references from deprecation messages:

| Pattern | Example | Extracted |
|---------|---------|-----------|
| `func/arity` | "Use new_func/2" | `{:new_func, 2}` |
| `Module.func/arity` | "See MyModule.other/1" | `module: "MyModule", function: {:other, 1}` |
| `Module.func` | "Replaced by New.func" | `module: "New", function: {:func, 0}` |

#### @deprecated Pattern Detection

Supports multiple deprecation formats:
- Double-quoted: `@deprecated "message"`
- Single-quoted: `@deprecated 'message'`
- Sigils: `@deprecated ~s/message/`
- Boolean: `@deprecated true`

### Test File

Created `test/elixir_ontologies/extractors/evolution/deprecation_test.exs` with 29 tests covering:

- Element types enumeration
- Struct defaults (DeprecationEvent, RemovalEvent, Replacement, Deprecation)
- Replacement parsing with various patterns
- Query functions (has_replacement?, removed?)
- Integration tests with real repository
- Edge cases (special characters, high arity, etc.)

## Design Decisions

1. **Element Types**: Support for functions, modules, macros, callbacks, and types - all elements that can be deprecated.

2. **Replacement Parsing**: Smart extraction using ordered pattern matching - checks for Module.func/arity before func/arity to correctly parse module references.

3. **Commit Tracking**: Uses `git log -S @deprecated` to find commits that add or remove deprecation annotations.

4. **Removal Detection**: Identifies when a deprecated function (with @deprecated before def) is deleted from code.

## Files Changed

### New Files
- `lib/elixir_ontologies/extractors/evolution/deprecation.ex`
- `test/elixir_ontologies/extractors/evolution/deprecation_test.exs`
- `notes/features/phase-20-2-3-deprecation-tracking.md`
- `notes/summaries/phase-20-2-3-deprecation-tracking.md`

### Modified Files
- `notes/planning/extractors/phase-20.md` - Marked task 20.2.3 as complete

## Test Results

All 29 deprecation tests pass. The full evolution test suite (318 tests) passes.

## Next Task

The next logical task is **20.2.4 Feature and Bug Fix Tracking**, which will:
- Define `%FeatureAddition{name: ..., commit: ..., modules: [...]}` struct
- Define `%BugFix{description: ..., commit: ..., affected_functions: [...]}` struct
- Parse issue references from commit messages (#123, GH-456)
- Link activities to external issue trackers
- Track scope of changes per activity
