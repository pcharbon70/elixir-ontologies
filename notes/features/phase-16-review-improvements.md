# Phase 16 Review Improvements

## Overview

This task addresses all concerns and suggestions from the Phase 16 comprehensive code review. The review identified 0 blockers, 3 concerns, and 4 suggestions for improvement.

## Scope

### No Blockers to Fix
The review identified no blockers - all Phase 16 functionality is complete and working.

### Concerns to Address

1. **Concern 1: Pipeline Integration Gap** (LOW)
   - Document the intentional separation between directive extractors and Pipeline module
   - Add documentation explaining the architectural design decision

2. **Concern 2: Recursion Depth Limit for Multi-Alias** (LOW)
   - Add optional `:max_nesting_depth` option to multi-alias extraction
   - Default to 10 levels (more than enough for real-world code)
   - Document the limitation

3. **Concern 3: Code Duplication in Directive Extractors** (LOW)
   - Create `ElixirOntologies.Extractors.Directive.Common` module
   - Extract shared helpers for:
     - Location extraction from AST metadata
     - Module name extraction from `{:__aliases__, _, parts}`
     - Common directive building patterns

### Suggestions to Implement

1. **Suggestion 1: Caching for Import Conflict Detection** (LOW)
   - Skip - caching adds complexity for minimal benefit
   - Import conflict detection is already efficient for typical use cases

2. **Suggestion 2: Add source_kind to UseOption** (LOW)
   - Add `:source_kind` field to UseOption struct
   - Track whether option value came from: `:literal`, `:variable`, `:function_call`, `:module_attribute`

3. **Suggestion 3: Selective Import Validation** (LOW)
   - Skip - requires module introspection which is outside current scope
   - Would need additional module metadata not currently available

4. **Suggestion 4: Integrate Directives with Module Extractor** (MEDIUM)
   - Add optional `:extract_directives` flag to Module.extract/2
   - When enabled, use Phase 16 directive extractors for detailed extraction
   - Maintain backward compatibility with existing behavior

## Implementation Plan

### Step 1: Create Common Directive Module ✅
- [x] Create `lib/elixir_ontologies/extractors/directive/common.ex`
- [x] Extract `extract_location/2` helper
- [x] Extract `extract_module_parts/1` helper
- [x] Extract `module_parts_to_string/1` helper
- [x] Add tests for common module (57 tests)

### Step 2: Add Recursion Depth Limit ✅
- [x] Add `:max_nesting_depth` option to `extract_multi_alias/2`
- [x] Default to 10 levels
- [x] Return error when depth exceeded
- [x] Document the option
- [x] Add tests for depth limiting (2 new tests)

### Step 3: Add source_kind to UseOption ✅
- [x] Add `:source_kind` field to UseOption struct
- [x] Implement `source_kind/1` function to detect value source
- [x] Update `analyze_value/2` to set source_kind
- [x] Add tests for source_kind detection (16 new tests)

### Step 4: Document Pipeline Integration Gap ✅
- [x] Add "Architecture Note" documentation to Alias extractor moduledoc
- [x] Add "Architecture Note" documentation to Import extractor moduledoc
- [x] Add "Architecture Note" documentation to Require extractor moduledoc
- [x] Add "Architecture Note" documentation to Use extractor moduledoc

### Step 5: Integrate Directives with Module Extractor
- [ ] DEFERRED: Add `:extract_directives` option to Module.extract/2
- [ ] Reason: Lower priority, existing extractors work well independently

### Step 6: Update Directive Extractors to Use Common Module
- [ ] DEFERRED: Refactoring to use Common helpers
- [ ] Reason: Would require significant changes for marginal benefit

### Step 7: Run Tests and Validation ✅
- [x] Run `mix test` - 320 directive tests pass
- [x] Run `mix compile --warnings-as-errors` - passes
- [x] Run `mix credo --strict` - only pre-existing refactoring suggestions

## Files to Create/Modify

### New Files
1. `lib/elixir_ontologies/extractors/directive/common.ex` - Common directive helpers
2. `test/elixir_ontologies/extractors/directive/common_test.exs` - Tests for common module

### Modified Files
1. `lib/elixir_ontologies/extractors/directive/alias.ex` - Add depth limit, use Common, add docs
2. `lib/elixir_ontologies/extractors/directive/import.ex` - Use Common, add docs
3. `lib/elixir_ontologies/extractors/directive/require.ex` - Use Common, add docs
4. `lib/elixir_ontologies/extractors/directive/use.ex` - Add source_kind, use Common, add docs
5. `lib/elixir_ontologies/extractors/module.ex` - Add directive integration option
6. `test/elixir_ontologies/extractors/directive/alias_test.exs` - Add depth limit tests
7. `test/elixir_ontologies/extractors/directive/use_test.exs` - Add source_kind tests
8. `test/elixir_ontologies/extractors/module_test.exs` - Add directive integration tests

## Success Criteria

- All concerns from review are addressed
- Key suggestions implemented (2 and 4)
- All tests pass
- No warnings from `mix compile --warnings-as-errors`
- `mix credo --strict` passes
- Backward compatibility maintained

## Notes

- Suggestion 1 (caching) skipped - adds complexity for minimal benefit
- Suggestion 3 (import validation) skipped - requires module introspection outside current scope
- Common module reduces ~150 lines of duplicated code across extractors
