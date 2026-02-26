# Feature: Add --include-expressions Flag to Hex Batch Processor

## Status: Completed ✅

**Created:** 2026-01-29
**Branch:** `feature/include-expressions-flag`

---

## Problem Statement

Currently, the hex batch processor (`mix elixir_ontologies.hex_batch`) does not support the `include_expressions` configuration option. This means:

1. Users cannot extract full expression ASTs when analyzing hex.pm packages
2. The batch processor is locked into "light mode" extraction (modules, functions, clauses only)
3. Full expression extraction (guards, conditions, function bodies, etc.) is unavailable for batch processing

The `ElixirOntologies.Config` module already has `include_expressions` support, but it's not exposed in the hex batch workflow.

---

## Solution Overview

Add a `--include-expressions` flag to the hex batch processor that:

1. Adds the flag to `Mix.Tasks.ElixirOntologies.HexBatch` switches
2. Passes the option through `BatchProcessor.Config`
3. Forwards the option to `AnalyzerAdapter.analyze_package/3`
4. Ensures `ProjectAnalyzer` receives the `include_expressions: true` option via `Config` struct

**Key Design Decision:**
- Default behavior remains unchanged (light mode extraction)
- Users must explicitly opt-in with `--include-expressions`

---

## Technical Details

### Files Modified

1. **`lib/mix/tasks/elixir_ontologies.hex_batch.ex`**
   - Added `include_expressions: :boolean` to `@switches`
   - Added option documentation to `@moduledoc`
   - Pass `include_expressions` to `build_config/2`

2. **`lib/elixir_ontologies/hex/batch_processor.ex`**
   - Added `include_expressions` to `Config` struct
   - Added `include_expressions` to `Config.t()` type
   - Documented in `Config.new/1` options
   - Pass through to analyzer config
   - **FIX:** Changed base_iri_template from `...:version/` to `...:version#` (fragment-based IRI)

3. **`lib/elixir_ontologies/hex/analyzer_adapter.ex`**
   - Accept `include_expressions` in config map
   - Pass `include_expressions` to `ProjectAnalyzer.analyze/2` opts
   - Updated function documentation

4. **`lib/elixir_ontologies/analyzer/project_analyzer.ex`**
   - Added `get_or_build_config/1` helper function
   - Builds `Config` struct from individual options when `config:` is not provided
   - Properly handles `include_expressions`, `include_git_info`, `include_source_text`, etc.

5. **`lib/elixir_ontologies/pipeline.ex`**
   - Updated `build_context/2` to pass `include_expressions` to Context

### Bug Fixes During Implementation

1. **IRI Format Bug:** The hex batch was using path-based IRIs (`...:version/`) but the IRI module expects fragment-based IRIs (`...:version#`). Fixed by updating the default `base_iri_template`.

2. **Config Building:** Individual options like `include_expressions` weren't being used because ProjectAnalyzer only used `opts[:config]`. Fixed by adding `get_or_build_config/1` that builds a Config struct from individual options.

---

## Success Criteria

1. ✅ Flag is accepted by mix task without errors
2. ✅ Flag value is properly propagated through the call chain
3. ✅ Config struct is built with correct `include_expressions` value
4. ✅ Documentation is updated with the new option

### Verification

```bash
# Light mode (default)
mix elixir_ontologies.hex_batch --package jason

# Full mode
mix elixir_ontologies.hex_batch --package jason --include-expressions

# Verify config value
iex> c = ElixirOntologies.Config.new(include_expressions: true)
iex> c.include_expressions
true
```

---

## Implementation Plan - Completed

### Step 1: Add flag to Mix task ✅
- [x] Add `include_expressions: :boolean` to `@switches`
- [x] Add documentation to `@moduledoc` options section
- [x] Pass option to `build_config/2`

### Step 2: Update BatchProcessor.Config ✅
- [x] Add `include_expressions` field to struct
- [x] Add `include_expressions` to `@type t()` definition
- [x] Document in `Config.new/1` docstring
- [x] Set default value to `false` in `Config.new/1`

### Step 3: Update AnalyzerAdapter ✅
- [x] Accept `include_expressions` from config map
- [x] Pass to `ProjectAnalyzer.analyze/2` opts
- [x] Update function documentation

### Step 4: Update ProjectAnalyzer ✅
- [x] Add `get_or_build_config/1` to handle individual options
- [x] Build Config struct from individual options when `config:` not provided

### Step 5: Update Pipeline ✅
- [x] Pass `include_expressions` to Context in `build_context/2`

### Step 6: Fix IRI Format ✅
- [x] Changed `base_iri_template` from `...:version/` to `...:version#`

### Step 7: Testing ✅
- [x] Test without flag (default behavior)
- [x] Test with flag (verify Config is built correctly)
- [x] Verify compilation succeeds
- [x] Check documentation renders correctly

---

## Notes/Considerations

### Storage Impact

From `Config` module documentation:
- Light mode (default): ~500 KB per 100 functions
- Full mode: ~5-20 MB per 100 functions

This is a **10-40x increase** in output size. Users should be aware of this.

### Testing Results

The implementation is technically complete and the `include_expressions` flag is correctly propagated through all components. Testing with simple packages (mime, jason) shows minimal difference because:

1. These packages use struct-based definitions and macros
2. Many functions are bodyless or have very simple implementations
3. Expression extraction primarily benefits packages with complex guard clauses, pattern matching, and function bodies

For comprehensive testing, packages with more complex function bodies would show a more significant difference.

### Usage Examples

```bash
# Light mode (default)
mix elixir_ontologies.hex_batch --limit 100

# Full mode with expressions
mix elixir_ontologies.hex_batch --limit 100 --include-expressions

# With other options
mix elixir_ontologies.hex_batch --package phoenix --include-expressions --verbose

# Combine with halt-on-warning
mix elixir_ontologies.hex_batch --limit 50 --include-expressions --halt-on-warning
```

---

## Current Status

### What Works
- ✅ `--include-expressions` flag is accepted and parsed correctly
- ✅ Flag value is properly propagated through BatchProcessor → AnalyzerAdapter → ProjectAnalyzer → Pipeline → Context
- ✅ Config struct is built with `include_expressions: true` when flag is set
- ✅ IRI format bug fixed (now uses fragment-based IRIs)
- ✅ ProjectAnalyzer now handles individual options correctly

### What's Next
- Feature is complete and ready for commit/merge
- Future enhancement: Consider adding `--include-expressions` to `mix elixir_ontologies.analyze` task for consistency

### How to Use
```bash
git checkout feature/include-expressions-flag
mix elixir_ontologies.hex_batch --include-expressions
```
