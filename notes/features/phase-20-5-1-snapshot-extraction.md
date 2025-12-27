# Phase 20.5.1: Snapshot Extraction

## Overview

Extract codebase snapshot information at specific points in time. A snapshot represents the state of a codebase at a particular commit, including module lists and statistics.

## Requirements

From phase-20.md task 20.5.1:

- [x] 20.5.1.1 Create `lib/elixir_ontologies/extractors/evolution/snapshot.ex`
- [x] 20.5.1.2 Define `%CodebaseSnapshot{commit: ..., timestamp: ..., modules: [...], stats: ...}` struct
- [x] 20.5.1.3 Implement `extract_snapshot/1` for current HEAD
- [x] 20.5.1.4 Calculate codebase statistics (module count, function count, LOC)
- [x] 20.5.1.5 Track snapshot as point-in-time state
- [x] 20.5.1.6 Add snapshot extraction tests

## Design

### CodebaseSnapshot Struct

```elixir
%CodebaseSnapshot{
  snapshot_id: "snapshot:abc123d",     # Unique ID based on commit
  commit_sha: "abc123...",             # Full 40-char SHA
  short_sha: "abc123d",                # Short SHA
  timestamp: ~U[2025-01-15 10:30:00Z], # Commit timestamp
  project_name: "elixir_ontologies",   # From mix.exs
  project_version: "0.1.0",            # From mix.exs
  modules: ["MyApp.User", ...],        # List of module names
  files: ["lib/my_app/user.ex", ...],  # List of source files
  stats: %{
    module_count: 42,
    function_count: 156,
    macro_count: 5,
    protocol_count: 2,
    behaviour_count: 3,
    line_count: 5234,
    file_count: 42
  },
  metadata: %{}
}
```

### Implementation Approach

1. Use `GitUtils.run_git_command/3` for git operations
2. Use `git ls-tree` to list files at specific commit
3. Use `git show` to read file contents at specific commit
4. Parse Elixir files to extract module/function info
5. Count lines for LOC statistics

### Key Functions

- `extract_snapshot/2` - Extract snapshot at a specific commit ref
- `extract_snapshot!/2` - Bang variant
- `extract_current_snapshot/1` - Convenience for HEAD
- `list_files_at_commit/2` - Get Elixir files at a commit
- `count_lines_at_commit/2` - Count lines of code
- `extract_modules_at_commit/2` - Extract module names from files

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/snapshot.ex`
- [x] Add module doc and type specs
- [x] Import necessary modules (GitUtils, Commit)

### Step 2: Define CodebaseSnapshot Struct
- [x] Define struct with all fields
- [x] Add @type definition
- [x] Add field documentation

### Step 3: Implement File Listing
- [x] `list_elixir_files_at_commit/2` - Use git ls-tree to list .ex/.exs files
- [x] Filter for lib/ directory files
- [x] Handle both regular and umbrella projects

### Step 4: Implement Line Counting
- [x] `count_lines_at_commit/2` - Count total lines in Elixir files
- [x] Use git show to read file contents
- [x] Sum lines across all files

### Step 5: Implement Module Extraction
- [x] `extract_module_names_at_commit/2` - Parse files to find module names
- [x] Use Code.string_to_quoted for safe parsing
- [x] Handle parse errors gracefully

### Step 6: Implement Main Extraction
- [x] `extract_snapshot/2` - Main entry point
- [x] Get commit info using Commit.extract_commit
- [x] Get project info using Project.detect
- [x] Combine all statistics
- [x] Return {:ok, snapshot} or {:error, reason}

### Step 7: Testing
- [x] Test basic snapshot extraction
- [x] Test statistics calculation
- [x] Test module extraction
- [x] Test file listing
- [x] Test error handling
- [x] Test integration with real repository

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/extractors/evolution/snapshot.ex`
- `test/elixir_ontologies/extractors/evolution/snapshot_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)

## Success Criteria

1. All 6 subtasks completed
2. `extract_snapshot/2` works for HEAD and specific commits
3. Statistics accurately reflect codebase state
4. Module names correctly extracted from source files
5. All tests passing
