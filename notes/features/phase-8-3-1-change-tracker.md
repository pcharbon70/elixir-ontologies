# Feature: Phase 8.3.1 - Change Tracker

## Problem Statement

Implement a Change Tracker module that detects file modifications, additions, and deletions to enable efficient incremental analysis. This allows the system to avoid re-analyzing unchanged files, significantly improving performance for large projects.

The tracker must:
- Track file modification times and checksums
- Detect changed files (modified since last analysis)
- Detect new files (added since last analysis)
- Detect deleted files (removed since last analysis)
- Store analysis state for comparison
- Provide simple API for change detection

## Solution Overview

Create `lib/elixir_ontologies/analyzer/change_tracker.ex` that:

1. **State Storage**: Store file metadata (path, mtime, size, checksum) in a structured format
2. **Change Detection**: Compare current file system state with stored state
3. **Simple API**: Provide functions to detect changed, new, and deleted files
4. **Persistence**: Support serialization to/from files or maps
5. **Integration**: Work seamlessly with ProjectAnalyzer

## Technical Details

### State Structure

```elixir
defmodule ChangeTracker.State do
  @enforce_keys [:files, :timestamp]
  defstruct [
    :files,          # Map of file_path => FileInfo
    :timestamp,      # When state was captured
    metadata: %{}    # Additional metadata
  ]
end

defmodule ChangeTracker.FileInfo do
  @enforce_keys [:path, :mtime, :size]
  defstruct [
    :path,           # Absolute file path
    :mtime,          # File modification time (Unix timestamp)
    :size,           # File size in bytes
    checksum: nil    # Optional: MD5/SHA checksum
  ]
end
```

### API Design

```elixir
# Create state from current files
@spec capture_state([String.t()]) :: State.t()
def capture_state(file_paths)

# Detect changes between states
@spec changed_files(State.t(), State.t()) :: [String.t()]
def changed_files(old_state, new_state)

# Detect new files
@spec new_files(State.t(), State.t()) :: [String.t()]
def new_files(old_state, new_state)

# Detect deleted files
@spec deleted_files(State.t(), State.t()) :: [String.t()]
def deleted_files(old_state, new_state)

# Get all changes
@spec detect_changes(State.t(), State.t()) :: Changes.t()
def detect_changes(old_state, new_state)
```

## Implementation Plan

### Step 1: Define State Structs
- [x] Create ChangeTracker.State struct
- [x] Create ChangeTracker.FileInfo struct
- [x] Create ChangeTracker.Changes struct
- [x] Add @enforce_keys and types

### Step 2: Implement State Capture
- [x] Implement capture_state/1
- [x] Get file stats for each path
- [x] Create FileInfo for each file
- [x] Return State struct

### Step 3: Implement Change Detection
- [x] Implement changed_files/2
- [x] Compare mtime and size
- [x] Return list of changed paths

### Step 4: Implement New File Detection
- [x] Implement new_files/2
- [x] Find files in new but not in old
- [x] Return list of new paths

### Step 5: Implement Deleted File Detection
- [x] Implement deleted_files/2
- [x] Find files in old but not in new
- [x] Return list of deleted paths

### Step 6: Implement Unified Change Detection
- [x] Implement detect_changes/2
- [x] Call all detection functions
- [x] Return Changes struct

### Step 7: Write Comprehensive Tests
- [x] Test state capture
- [x] Test changed file detection
- [x] Test new file detection
- [x] Test deleted file detection
- [x] Test detect_changes/2
- [x] Test edge cases

## Current Status

✅ **COMPLETE** - All implementation tasks finished and tested

- **What works:**
  - State capture from file list
  - Change detection (modified files)
  - New file detection (added files)
  - Deleted file detection (removed files)
  - Unified change detection API
  - 10 comprehensive tests
  - All tests passing (911 doctests, 29 properties, 2486 tests, 0 failures)
  - Credo clean (1995 mods/funs, no issues)

- **What's implemented:**
  - ✅ State and FileInfo structs
  - ✅ Changes struct for results
  - ✅ capture_state/1 function
  - ✅ changed_files/2 detection
  - ✅ new_files/2 detection
  - ✅ deleted_files/2 detection
  - ✅ detect_changes/2 unified API
  - ✅ 10 comprehensive tests

- **How to run:** `mix test test/elixir_ontologies/analyzer/change_tracker_test.exs`

## Implementation Summary

**Files created:**
- `lib/elixir_ontologies/analyzer/change_tracker.ex` (219 lines)
- `test/elixir_ontologies/analyzer/change_tracker_test.exs` (228 lines)

**Test coverage:**
- 10 tests across 5 categories
- State capture (1 test)
- Changed file detection (2 tests)
- New file detection (2 tests)
- Deleted file detection (2 tests)
- Unified change detection (2 tests)
- Edge cases (1 test)

**Key features:**
1. Captures file metadata (path, mtime, size) efficiently
2. Detects modified files by comparing mtime and size
3. Detects newly added files
4. Detects deleted files
5. Returns structured Changes result
6. Simple, focused API
7. No external dependencies

**Design decisions:**
- Uses mtime + size for change detection (fast, reliable)
- No checksums by default (avoid I/O overhead)
- State is immutable (functional approach)
- Simple Map-based storage (easy to serialize)
- Unix timestamp for mtime (standard, portable)
