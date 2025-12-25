# Phase 20.1.3: File History Extraction

## Overview

Extract the history of changes to individual files, including tracking commits that modified each file, file renames/moves, and building a chronological change list.

## Problem Statement

For code provenance tracking, we need to understand:
1. Which commits have modified a specific file
2. When a file was renamed or moved
3. The chronological sequence of changes
4. Who made changes and when

## Design Decisions

1. **Integration with Commit extractor**: Use existing Commit struct for commit details
2. **Rename tracking**: Use `git log --follow` to track file history across renames
3. **Rename detection**: Use `git log --name-status` to detect rename operations
4. **Chronological order**: Return commits in reverse chronological order (newest first)

## Technical Details

### New Files
- `lib/elixir_ontologies/extractors/evolution/file_history.ex` - File history extractor
- `test/elixir_ontologies/extractors/evolution/file_history_test.exs` - Tests

### Structs

```elixir
# Represents a file rename/move operation
defmodule Rename do
  defstruct [
    :from_path,      # Original path
    :to_path,        # New path
    :commit_sha,     # Commit where rename occurred
    :similarity      # Similarity percentage (if available)
  ]
end

# Represents the complete history of a file
defmodule FileHistory do
  defstruct [
    :path,           # Current file path
    :original_path,  # Original path (if renamed)
    :commits,        # List of commit SHAs that modified this file
    :renames,        # List of Rename structs
    :first_commit,   # First commit that created the file
    :last_commit,    # Most recent commit
    :commit_count,   # Total number of commits
    metadata: %{}
  ]
end
```

### Key Functions
- `extract_file_history/2` - Extract history for a file
- `extract_file_history!/2` - Raising version
- `extract_commits_for_file/2` - Get commits that modified a file
- `extract_renames/2` - Get rename history for a file
- `file_exists_in_history?/2` - Check if file has git history

### Git Commands

```bash
# Get commits that modified a file (following renames)
git log --format="%H" --follow -- <file>

# Get commits with rename detection
git log --format="%H" --name-status --follow -- <file>

# Detect renames specifically
git log --diff-filter=R --format="%H" --name-status --follow -- <file>
```

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/file_history.ex`
- [x] Define `Rename` struct
- [x] Define `FileHistory` struct
- [x] Add module documentation

### Step 2: Implement Core Extraction
- [x] `extract_file_history/2` using git log --follow
- [x] Parse commit SHAs from output
- [x] Track first and last commits

### Step 3: Implement Rename Detection
- [x] `extract_renames/2` to detect file renames
- [x] Parse git log --name-status output
- [x] Build list of Rename structs

### Step 4: Add Helper Functions
- [x] `file_exists_in_history?/2` - check if file is tracked
- [x] `renamed?/1` - check if file was renamed
- [x] `original_path/1` - get original path if renamed
- [x] `rename_count/1` - count of renames
- [x] `path_at_commit/2` - get path at specific commit

### Step 5: Write Tests
- [x] Test file history extraction
- [x] Test commit tracking
- [x] Test rename detection
- [x] Test with non-existent files
- [x] Test with files outside repository
- [x] Test integration with repository

## Success Criteria

1. All subtasks in 20.1.3 marked complete
2. Comprehensive test coverage
3. Integration with existing Commit/Developer extractors
4. Proper handling of file renames

## Dependencies

- `ElixirOntologies.Extractors.Evolution.Commit` - commit details
- `ElixirOntologies.Analyzer.Git` - repository detection
