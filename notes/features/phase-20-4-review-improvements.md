# Phase 20.4 Review Improvements

## Overview

Address concerns and implement improvements from the Phase 20.4 Evolution Builders review. This task focuses on code quality, consistency, and reducing duplication.

## Source

Review document: `notes/reviews/phase-20-4-evolution-builders-review.md`

## Issues to Address

### High Priority

1. **Add `Helpers.finalize_triples/1`** - Centralize triple post-processing (flatten + filter nils)
2. **Standardize triple processing** - Include both nil filtering and deduplication
3. **Add `Helpers.dual_type_triples/3`** - For PROV-O + Evolution type pairs

### Medium Priority

4. **Add `Helpers.optional_datetime_property/4`** - For optional datetime fields
5. **Refactor CommitBuilder** - Use data-driven approach for timestamps/messages
6. **Refactor ActivityBuilder** - Use new helpers, standardize patterns
7. **Add guard clauses** - To catch-all type mapping functions

### Low Priority (deferred)

- IRI generation centralization (larger refactor for future)
- Email anonymization option (requires ontology check)
- EvolutionBuilder behaviour (future consideration)

## Implementation Plan

### Step 1: Add New Helper Functions
- [x] Add `finalize_triples/1` to Helpers
- [x] Add `dual_type_triples/3` to Helpers
- [x] Add `optional_datetime_property/3` to Helpers
- [x] Add `optional_string_property/3` to Helpers
- [x] Doctests pass for new helpers

### Step 2: Refactor CommitBuilder
- [x] Refactor `build_message_triples/2` using data-driven approach with `optional_string_property`
- [x] Refactor `build_timestamp_triples/2` using data-driven approach with `optional_datetime_property`
- [x] Use `finalize_triples/1` instead of inline flatten/reject
- [x] All 31 tests pass

### Step 3: Refactor ActivityBuilder
- [x] Use `dual_type_triples/3` for type generation
- [x] Use `optional_datetime_property/3` for timestamps
- [x] Use `finalize_triples/1` for post-processing
- [x] Add guard clause to `activity_type_to_class/1`
- [x] All 44 tests pass

### Step 4: Refactor AgentBuilder
- [x] Use `dual_type_triples/3` for type generation
- [x] Use `finalize_triples/1` for post-processing
- [x] Add guard clause to `agent_type_to_class/1`
- [x] All 32 tests pass

### Step 5: Refactor VersionBuilder
- [x] Use `dual_type_triples/3` for type generation
- [x] Use `optional_datetime_property/3` for timestamps
- [x] Use `finalize_triples/1` for post-processing
- [x] Add guard clause to `version_type_to_class/1`
- [x] All 30 tests pass

### Step 6: Final Verification
- [x] Run all evolution builder tests (137 tests, 0 failures)
- [x] Run mix compile (success)
- [x] Run mix credo (no issues)

## Success Criteria

1. All 137 existing tests still pass
2. No code duplication warnings from Credo
3. Helper functions properly documented and tested
4. Data-driven approach simplifies timestamp/message triple generation
5. Consistent patterns across all four evolution builders

## Files to Modify

- `lib/elixir_ontologies/builders/helpers.ex`
- `lib/elixir_ontologies/builders/evolution/commit_builder.ex`
- `lib/elixir_ontologies/builders/evolution/activity_builder.ex`
- `lib/elixir_ontologies/builders/evolution/agent_builder.ex`
- `lib/elixir_ontologies/builders/evolution/version_builder.ex`
- `test/elixir_ontologies/builders/helpers_test.exs` (if exists, or create)
