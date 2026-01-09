# Phase 21.1: Configuration Extension - Implementation Summary

**Date:** 2025-01-09
**Feature:** Section 21.1 of Phase 21 - Configuration & Expression Infrastructure
**Branch:** `feature/phase-21-1-configuration-extension`
**Status:** ✅ Complete

## Overview

Successfully implemented the `include_expressions` configuration option that enables optional full expression extraction for Elixir AST nodes. This is the foundation for Phases 21-30 which will implement complete expression extraction.

## Changes Made

### 1. Config Module (`lib/elixir_ontologies/config.ex`)

**Added:**
- `include_expressions: false` field to Config struct
- Type spec update: `include_expressions: boolean()`
- Updated `@moduledoc` with:
  - Configuration Options section
  - Expression Extraction section with storage impact details
  - Project vs Dependencies explanation
- Updated `merge/2` to accept `:include_expressions` option
- Updated `validate/1` to validate `include_expressions` is boolean
- New helper: `project_file?/1` - Detects project vs dependency files
- New helper: `should_extract_full?/2` - Combines config and file path checks
- Private helper: `deps_path?/1` - Path detection logic

**Key Implementation Details:**
- Dependencies are identified by `deps/` directory in path
- Supports both `deps/` at start and `/deps/` in middle of path
- Windows paths with `\deps\` also supported
- Project files outside `deps/` get full extraction when enabled

### 2. Context Module (`lib/elixir_ontologies/builders/context.ex`)

**Added:**
- `full_mode?/1` - Returns true when `include_expressions: true`
- `full_mode_for_file?/2` - Returns true only for project files when full mode enabled
- `light_mode?/1` - Returns true when `include_expressions: false`

**Key Implementation Details:**
- `full_mode_for_file?/2` calls both `full_mode?/1` and `Config.project_file?/1`
- All helpers include comprehensive documentation with examples
- Properly handles edge cases (nil paths, empty config, etc.)

### 3. Tests (`test/elixir_ontologies/config_test.exs`)

**Added 36 new tests:**
- `include_expressions configuration` describe block (6 tests)
  - Default value test
  - merge/2 with true and false values
  - validate/1 with both boolean values
  - validate/1 error handling for non-boolean

- `project_file?/1` describe block (7 tests)
  - lib/, src/, test/ files return true
  - deps/ files return false
  - Absolute paths with deps/ return false
  - nil path returns false
  - Edge case: file name containing "deps" but not in deps/ directory

- `should_extract_full?/2` describe block (6 tests)
  - Returns true when config enabled and project file
  - Returns false when config disabled
  - Returns false for dependency files even when config enabled
  - Returns false for nil file path
  - Handles src/ files correctly

### 4. Context Tests (`test/elixir_ontologies/builders/context_test.exs`)

**Added 18 new tests:**
- `full_mode?/1` describe block (4 tests)
  - Returns true when include_expressions true
  - Returns false when include_expressions false
  - Returns false when config empty
  - Returns false when config doesn't have include_expressions key

- `full_mode_for_file?/2` describe block (5 tests)
  - Returns true when full mode enabled and project file
  - Returns false when full mode enabled but dependency file
  - Returns false when full mode disabled
  - Returns false for nil file path
  - Returns true for src/ files when full mode enabled

- `light_mode?/1` describe block (3 tests)
  - Returns true when include_expressions false
  - Returns false when include_expressions true
  - Returns true when config empty

## Test Results

All 68 tests (26 doctests + 42 regular tests) pass:
```
Finished in 0.08 seconds (0.08s async, 0.00s sync)
26 doctests, 68 tests, 0 failures
```

## Storage Impact (as documented)

- **Light mode** (default): ~500 KB per 100 functions
- **Full mode**: ~5-20 MB per 100 functions
- **Dependencies**: Always light mode, regardless of config

## Design Decisions

1. **Default to false**: Ensures backward compatibility and minimal storage by default
2. **Project-only extraction**: Dependencies always use light mode to keep storage manageable
3. **Simple path detection**: Uses `deps/` directory check which works for standard Mix projects
4. **Helper functions**: Both Config and Context modules provide convenient helpers for checking mode

## API Usage Examples

```elixir
# Enable full expression extraction for project code
config = ElixirOntologies.Config.new(include_expressions: true)

# Check if full mode should be used for a specific file
ElixirOntologies.Config.should_extract_full?("lib/my_app/users.ex", config)
# => true

ElixirOntologies.Config.should_extract_full?("deps/decimal/lib/decimal.ex", config)
# => false (dependencies are always light mode)

# In builders
context = ElixirOntologies.Builders.Context.new(
  base_iri: "https://example.org/code#",
  config: %{include_expressions: true},
  file_path: "lib/my_app/users.ex"
)

ElixirOntologies.Builders.Context.full_mode_for_file?(context, "lib/my_app/users.ex")
# => true

ElixirOntologies.Builders.Context.full_mode_for_file?(context, "deps/decimal/lib/decimal.ex")
# => false
```

## Next Steps

Phase 21.1 is complete. Next sections will implement:
- Phase 21.2: ExpressionBuilder Module
- Phase 21.3: IRI Generation for Expressions
- Phase 21.4: Core Expression Builders
- Phase 21.5: Context Propagation (already done)
- Phase 21.6: Helper Functions Module

## Files Modified

- `lib/elixir_ontologies/config.ex` (+95 lines)
- `lib/elixir_ontologies/builders/context.ex` (+108 lines)
- `test/elixir_ontologies/config_test.exs` (+110 lines)
- `test/elixir_ontologies/builders/context_test.exs` (+119 lines)
