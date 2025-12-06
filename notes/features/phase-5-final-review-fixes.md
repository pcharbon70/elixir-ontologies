# Feature: Phase 5 Final Review Fixes

## Problem Statement

Address all concerns and suggestions from the comprehensive Phase 5 code review to improve code quality, reduce duplication, and enhance test coverage.

## Review Findings to Address

### Concerns (Must Fix)

1. **Function signature extraction duplicated** - Similar logic in `protocol.ex`, `behaviour.ex` for extracting function name/arity from AST
2. **@derive extraction cross-dependency** - `Struct` depends on `Protocol.extract_derives/1`
3. **Location extraction boilerplate** - Same pattern repeated 5+ times
4. **Metadata field not populated** - Phase 5 extractors always set `metadata: %{}`
5. **Missing 5.1.1 documentation** - Combined with 5.1.2 but no separate docs

### Suggestions (Should Implement)

1. Add tests for protocol functions with guard clauses
2. Test `@enforce_keys` referencing non-existent fields
3. Add integration test for exception implementing behaviour
4. Test callback with complex union return types
5. Use `Enum.flat_map/2` in `extract_optional_callbacks_list/1`

## Implementation Plan

### Phase 1: Extract Shared Helpers

- [ ] Add `extract_function_signature/1` to Helpers
- [ ] Add `compute_arity/1` to Helpers
- [ ] Add `extract_parameter_names/1` to Helpers
- [ ] Add `extract_location_if/2` to Helpers
- [ ] Move `extract_derives/1` and `DeriveInfo` to Helpers

### Phase 2: Update Extractors to Use New Helpers

- [ ] Update `protocol.ex` to use shared helpers
- [ ] Update `behaviour.ex` to use shared helpers
- [ ] Update `struct.ex` to use shared helpers

### Phase 3: Populate Metadata Fields

- [ ] Add meaningful metadata to Protocol extractor
- [ ] Add meaningful metadata to Behaviour extractor
- [ ] Add meaningful metadata to Struct extractor

### Phase 4: Add Missing Documentation

- [ ] Create `notes/features/5.1.1-protocol-definition-extractor.md`
- [ ] Create `notes/summaries/5.1.1-protocol-definition-extractor-summary.md`

### Phase 5: Test Improvements

- [ ] Add test for protocol function with guard clause
- [ ] Add test for @enforce_keys with non-existent field
- [ ] Add test for exception implementing behaviour
- [ ] Add test for callback with complex union return type
- [ ] Refactor `extract_optional_callbacks_list/1` to use `Enum.flat_map/2`

### Phase 6: Verification

- [ ] Run full test suite
- [ ] Run dialyzer
- [ ] Update phase plan
- [ ] Write summary

## Success Criteria

- [ ] All duplicated code extracted to Helpers
- [ ] Metadata fields populated with useful information
- [ ] Missing documentation added
- [ ] All suggested tests added
- [ ] All tests pass
- [ ] Dialyzer clean

## Status

- **Current Step:** Creating planning document
- **Branch:** `feature/phase-5-final-review-fixes`
