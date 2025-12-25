# Phase 20.1 Review Fixes

## Overview

Address all blockers, concerns, and suggestions from the Phase 20.1 comprehensive review.

## Blockers to Fix

### 1. Logic Error in `trace_path_at_index/4`
- [ ] Fix file_history.ex:478-479 where both branches return same value
- [ ] Add tests for complex rename scenarios

### 2. Command Injection Risk
- [ ] Add SHA validation before git commands
- [ ] Add ref validation (HEAD, branch names, tags)
- [ ] Validate file paths don't contain dangerous characters

### 3. Path Traversal Vulnerability
- [ ] Validate relative paths don't contain `..`
- [ ] Canonicalize paths before use
- [ ] Add path validation tests

## Concerns to Address

### 1. Developer Email Fallback
- [ ] Change fallback from "unknown" to "unknown-#{commit.sha}"
- [ ] Update tests

### 2. Git Command Execution Duplication
- [ ] Create GitUtils module with shared functions
- [ ] Update all modules to use GitUtils

### 3. Path Normalization Duplication
- [ ] Move to GitUtils module
- [ ] Remove duplicates from file_history.ex and blame.ex

### 4. Silent Error Masking
- [ ] Preserve errors in file_history.ex extract_commits_for_file/4
- [ ] Add error logging where appropriate

### 5. Unbounded Resource Consumption
- [ ] Add @max_commits constant (default 10000)
- [ ] Add command timeout (30 seconds)
- [ ] Document limits

### 6. Missing Bang Variant
- [ ] Add extract_commits!/2 to commit.ex
- [ ] Add tests

### 7. Recursive Parsing Risk
- [ ] Convert parse_lines/4 to use Enum.reduce
- [ ] Convert collect_info_lines/2 to iterative
- [ ] Verify tests still pass

### 8. Email Anonymization
- [ ] Add :anonymize_emails option to extraction functions
- [ ] Implement SHA256 hashing for emails when enabled
- [ ] Add tests

## Suggestions to Implement

### 1. Create GitUtils Module
```elixir
defmodule ElixirOntologies.Extractors.Evolution.GitUtils do
  # Git command execution with timeout
  def run_git_command(repo_path, args, opts \\ [])

  # SHA validation
  def valid_sha?(sha)
  def valid_short_sha?(sha)
  def uncommitted_sha?(sha)

  # Ref validation
  def valid_ref?(ref)

  # Path validation
  def safe_path?(path)
  def normalize_file_path(file_path, repo_root)

  # DateTime parsing
  def parse_iso8601_datetime(date_str)
  def parse_unix_timestamp(timestamp)

  # String utilities
  def empty_to_nil(str)

  # Email anonymization
  def anonymize_email(email)
end
```

### 2. Add Integration Tests
- [ ] Test blame + commit correlation
- [ ] Test developer aggregation from blame
- [ ] Test file history with actual renames

### 3. Test Optional Parameters
- [ ] Test blame :line_range option
- [ ] Test blame :revision option
- [ ] Test extract_developer/3 success case

### 4. Standardize Error Atoms
Define standard errors:
- `:repo_not_found` - Repository path doesn't exist
- `:invalid_ref` - Invalid git reference
- `:invalid_path` - Invalid or unsafe file path
- `:file_not_found` - File doesn't exist
- `:file_not_tracked` - File not in git history
- `:command_failed` - Git command failed
- `:parse_error` - Failed to parse git output
- `:timeout` - Command timed out

## Implementation Plan

### Step 1: Create GitUtils Module
- [x] Create lib/elixir_ontologies/extractors/evolution/git_utils.ex
- [x] Implement run_git_command with timeout
- [x] Implement validation functions
- [x] Implement parsing utilities
- [x] Add tests

### Step 2: Fix Blockers
- [x] Fix trace_path_at_index logic
- [x] Add input validation to all modules
- [x] Add path safety checks

### Step 3: Address Concerns
- [x] Fix email fallback
- [x] Update modules to use GitUtils
- [x] Fix error masking
- [x] Add limits and timeouts
- [x] Add bang variant
- [x] Convert recursive parsing
- [x] Add email anonymization

### Step 4: Implement Suggestions
- [x] Add integration tests
- [x] Test optional parameters
- [x] Standardize error atoms

### Step 5: Verify
- [x] Run all tests
- [x] Verify no regressions

## Completion Status

**All tasks completed successfully on 2025-12-25**

- 219 tests passing (was 142)
- 77 new tests added (55 GitUtils + 22 integration)
- All blockers fixed
- All concerns addressed
- All suggestions implemented

## Success Criteria

1. [x] All blockers fixed
2. [x] All concerns addressed
3. [x] All suggestions implemented
4. [x] All 219 tests passing
5. [x] New tests for fixes added
