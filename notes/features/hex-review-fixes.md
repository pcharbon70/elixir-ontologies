# Feature: Hex Batch Analyzer Review Fixes

**Branch:** feature/hex-review-fixes
**Date:** 2025-12-28
**Status:** In Progress

## Problem Statement

The comprehensive review of Hex.1-8 phases identified:
- 1 critical blocker (path traversal vulnerability)
- 5 concerns requiring attention
- Multiple suggestions for improvement

These issues need to be addressed before the Hex batch analyzer is production-ready.

## Findings to Address

### 🚨 Blockers (Must Fix)

| ID | Issue | Location | Fix |
|----|-------|----------|-----|
| C1 | Path traversal in tar extraction | extractor.ex:37,87 | Validate paths stay within target |

### ⚠️ Concerns (Should Address)

| ID | Issue | Location | Fix |
|----|-------|----------|-----|
| M5 | Atom table exhaustion | progress_store.ex | Use strings instead of atoms |
| A1 | Context path reference | batch_processor.ex:378 | Fix to use correct field |
| E1 | High cyclomatic complexity | failure_tracker.ex | Refactor classify_error/1 |
| M2 | Symlink extraction | extractor.ex | Validate symlinks |
| M4 | No checksum verification | downloader.ex | Add SHA256 verification |

### 💡 Suggestions (Nice to Have)

| ID | Issue | Location | Fix |
|----|-------|----------|-----|
| S1 | Code duplication | multiple files | Create Utils module |
| S2 | Missing test | analyzer_adapter_test.exs | Add analyze_package test |
| S3 | Duplicate tarball_url | api.ex, downloader.ex | Consolidate |
| S4 | Duplicate parse_datetime | api.ex, progress_store.ex | Extract to Utils |

## Implementation Plan

### Step 1: Fix Path Traversal (Blocker C1) ✅
- [x] Add path validation function to extractor.ex
- [x] Validate each file path before extraction
- [x] Add tests for path traversal attempts
- [x] Verify fix with malicious path tests

### Step 2: Fix Symlink Extraction (Concern M2) ✅
- [x] Add symlink detection during extraction
- [x] Skip or error on symlinks outside target
- [x] Add tests for symlink handling

### Step 3: Fix Atom Table Exhaustion (Concern M5) ✅
- [x] Change progress_store.ex to use string keys
- [x] Remove String.to_atom/1 usage
- [x] Verify JSON roundtrip still works

### Step 4: Fix Context Path Reference (Concern A1) ✅
- [x] Review batch_processor.ex line 378
- [x] Verify correct field is being used
- [x] Add test if needed

### Step 5: Reduce FailureTracker Complexity (Concern E1) ✅
- [x] Split classify_error/1 into smaller functions
- [x] Group related error patterns
- [x] Reduce cyclomatic complexity below 15
- [x] Maintain same behavior

### Step 6: Add Checksum Verification (Concern M4) ✅
- [x] Add SHA256 checksum fetching from API
- [x] Verify downloaded tarball matches checksum
- [x] Add tests for verification

### Step 7: Create Utils Module (Suggestion S1) ✅
- [x] Create lib/elixir_ontologies/hex/utils.ex
- [x] Move parse_datetime/1 to Utils
- [x] Move format_duration/1 to Utils
- [x] Update all callers

### Step 8: Consolidate Duplicates (Suggestions S3, S4) ✅
- [x] Remove duplicate tarball_url from api.ex (keep in downloader.ex)
- [x] Update any callers of Api.tarball_url

### Step 9: Add Missing Test (Suggestion S2) ✅
- [x] Add direct test for analyze_package/3
- [x] Use test fixtures or mocking

### Step 10: Final Verification ✅
- [x] Run all tests
- [x] Run mix credo
- [x] Verify no regressions

## Current Status

**Completed:** All 10 steps
**Working:** All fixes implemented and tested
**Next:** Write summary, get permission to commit

## Success Criteria

- [ ] All tests pass (338+ tests)
- [ ] No Credo warnings for Hex modules
- [ ] Path traversal vulnerability fixed
- [ ] All concerns addressed
- [ ] Code duplication reduced

## Notes

- The checksum verification is optional (graceful degradation if API doesn't provide it)
- Utils module improves code reuse across Hex modules
- All changes are backward compatible
