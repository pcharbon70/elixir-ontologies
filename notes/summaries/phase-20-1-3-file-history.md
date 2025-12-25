# Phase 20.1.3: File History Extraction Summary

## Overview

Implemented the third task of Phase 20 (Evolution & Provenance), creating a FileHistory extractor that tracks the complete history of individual files including commit modifications and rename detection.

## What Was Implemented

### New Module: `lib/elixir_ontologies/extractors/evolution/file_history.ex`

A file history extraction module that tracks commits, renames, and provides query functions for file evolution.

### Rename Struct

```elixir
defstruct [
  :from_path,      # Original path before rename
  :to_path,        # New path after rename
  :commit_sha,     # Commit where rename occurred
  :similarity      # Similarity percentage (if available)
]
```

### FileHistory Struct

```elixir
defstruct [
  :path,           # Current file path
  :original_path,  # Original path (if file was renamed)
  :first_commit,   # SHA of first commit that created the file
  :last_commit,    # SHA of most recent commit
  commits: [],     # List of commit SHAs (newest first)
  renames: [],     # List of Rename structs (oldest first)
  commit_count: 0, # Total number of commits
  metadata: %{}
]
```

### Key Functions

| Function | Description |
|----------|-------------|
| `extract_file_history/3` | Extract complete file history with options |
| `extract_file_history!/3` | Raising version |
| `extract_commits_for_file/4` | Get commits that modified a file |
| `extract_renames/2` | Get rename history for a file |
| `file_exists_in_history?/2` | Check if file has git history |
| `renamed?/1` | Check if file was ever renamed |
| `original_path/1` | Get original path if renamed |
| `rename_count/1` | Count of rename operations |
| `path_at_commit/2` | Get the path at a specific commit |

### Design Decisions

1. **Follow Renames**: Uses `git log --follow` to track history across renames
2. **Reverse Chronological Order**: Commits are returned newest first
3. **Rename Detection**: Uses `git log --name-status --diff-filter=R` to detect renames
4. **Similarity Tracking**: Captures git's similarity score when available
5. **Path Normalization**: Handles both absolute and relative paths

### Features

- **Commit Tracking**: Track all commits that modified a file
- **Rename Detection**: Detect and track file renames with similarity scores
- **Original Path Discovery**: Find the original path of renamed files
- **Path History**: Query the path at any point in history
- **Options Support**: Limit commits, enable/disable follow

## Git Commands Used

```bash
# Get commits for a file (following renames)
git log --format=%H --follow -- <file>

# Detect renames with similarity scores
git log --format=%H --name-status --follow --diff-filter=R -- <file>
```

## Files Created

1. `lib/elixir_ontologies/extractors/evolution/file_history.ex` - FileHistory extractor module
2. `test/elixir_ontologies/extractors/evolution/file_history_test.exs` - Test suite
3. `notes/features/phase-20-1-3-file-history.md` - Planning document

## Test Results

- 30 tests for FileHistory, 0 failures
- Combined evolution tests: 108 tests total, all passing

## Integration

Works with existing Commit and Developer extractors:

```elixir
alias ElixirOntologies.Extractors.Evolution.FileHistory

# Extract file history
{:ok, history} = FileHistory.extract_file_history(".", "lib/my_module.ex")

# Check if file was renamed
if FileHistory.renamed?(history) do
  IO.puts("Original path: #{FileHistory.original_path(history)}")
end

# Get specific commit information
path_then = FileHistory.path_at_commit(history, some_commit_sha)
```

## Next Task

**Task 20.1.4: Blame Information Extraction**
- Implement `extract_blame/1` using git blame
- Define `%BlameInfo{line: ..., commit: ..., author: ..., timestamp: ...}` struct
- Extract commit attribution for each line
- Track line age (time since last change)
- Handle lines not yet committed (working copy)
- Add blame extraction tests
