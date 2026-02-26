# Feature: Phase 21.1 - Configuration Extension for Expression Extraction

## Status: ✅ Complete

**Started:** 2025-01-09
**Completed:** 2025-01-09
**Branch:** `feature/phase-21-1-configuration-extension`
**Target:** `expressions` branch (to be created)

## Problem Statement

The elixir-ontologies project currently extracts structural metadata (module/function names, arities) but not the actual expression trees for guards, conditions, function bodies, and other code constructs. We need to add optional expression extraction that:

1. Is opt-in to maintain backward compatibility and low storage overhead
2. Applies only to project code, not dependencies (for storage efficiency)
3. Integrates cleanly with the existing Config and Context modules

## Solution Overview

Add `include_expressions` boolean configuration option to the Config struct with:
- Default value of `false` (light mode - backward compatible)
- Project file detection (`project_file?/1`) to distinguish project code from dependencies
- Helper functions (`should_extract_full?/2`, `full_mode_for_file?/2`) for easy checking
- Proper validation and documentation

## Technical Details

### Files Modified

**Primary:**
- `lib/elixir_ontologies/config.ex` - Added `include_expressions` field and helpers
- `lib/elixir_ontologies/builders/context.ex` - Added expression mode helpers

**Tests:**
- `test/elixir_ontologies/config_test.exs` - Added 36 new tests
- `test/elixir_ontologies/builders/context_test.exs` - Added 18 new tests

### Configuration Field Added

```elixir
defstruct base_iri: @default_base_iri,
          include_source_text: false,
          include_git_info: true,
          output_format: :turtle,
          include_expressions: false  # NEW
```

### Helper Functions Added

**Config module:**
- `project_file?(path)` - Detects if path is project code (not in `deps/`)
- `should_extract_full?(path, config)` - Combines config check with project file check

**Context module:**
- `full_mode?(context)` - Returns true if `include_expressions: true`
- `full_mode_for_file?(context, file_path)` - Returns true if full mode enabled AND project file
- `light_mode?(context)` - Returns true if NOT full mode

## Success Criteria - All Met

- [x] Config struct has `include_expressions: false` field
- [x] Type spec updated with `include_expressions: boolean()`
- [x] `merge/2` accepts `:include_expressions` option
- [x] `validate/1` validates `include_expressions` is boolean
- [x] Documentation updated with storage vs detail trade-offs
- [x] `project_file?/1` helper correctly identifies project vs dependency files
- [x] `should_extract_full?/2` helper combines both checks correctly
- [x] Context helpers (`full_mode?/1`, `full_mode_for_file?/2`, `light_mode?/1`) work correctly
- [x] All tests pass (68 tests for Config and Context)
- [x] No breaking changes to existing API

## Test Results

```
Finished in 0.08 seconds (0.08s async, 0.00s sync)
26 doctests, 68 tests, 0 failures
```

All tests for Config and Context modules pass.

## Files Changed

### Modified Files:
- `lib/elixir_ontologies/config.ex` (+95 lines)
- `lib/elixir_ontologies/builders/context.ex` (+108 lines)
- `test/elixir_ontologies/config_test.exs` (+110 lines)
- `test/elixir_ontologies/builders/context_test.exs` (+119 lines)

### New Files:
- `notes/features/phase-21-1-configuration-extension.md` (this file)
- `notes/planning/expressions/` (entire directory)

## Notes/Considerations

1. **Storage Impact**: Dependencies are always light mode. A project with 15k hex packages at ~750MB would balloon to ~7.5-30GB if all dependencies used full mode.

2. **Future Integration**: This config option will be used by ExpressionBuilder in Phase 21.2+ to conditionally extract full ASTs.

3. **Backward Compatibility**: Default value of `false` ensures existing code and tests continue to work without changes.

4. **Path Detection**: `project_file?/1` checks for `/deps/` or `deps/` in path, plus Windows paths with `\deps\`. This works for standard Mix projects.

## Next Steps

- [ ] Create summary document in notes/summaries/
- [ ] Mark tasks as completed in phase-21.md planning document
- [ ] Ask for permission to commit
- [ ] Commit changes
- [ ] Ask for permission to merge to expressions branch (or create it)
