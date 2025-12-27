# Phase 20.5.2: Release Extraction

## Overview

Extract release information from git tags and mix.exs versions. This complements snapshot extraction by tracking formal release points and version progression over time.

## Requirements

From phase-20.md task 20.5.2:

- [x] 20.5.2.1 Define `%Release{version: ..., tag: ..., commit: ..., timestamp: ...}` struct
- [x] 20.5.2.2 Extract version from mix.exs
- [x] 20.5.2.3 Extract git tags as release markers
- [x] 20.5.2.4 Parse semantic versioning
- [x] 20.5.2.5 Track release progression
- [x] 20.5.2.6 Add release extraction tests (41 tests)

## Design

### Release Struct

```elixir
%Release{
  release_id: "release:v1.2.3",        # Unique ID based on version
  version: "1.2.3",                    # Version string
  tag: "v1.2.3",                       # Git tag name (may be nil)
  commit_sha: "abc123...",             # Full 40-char SHA
  short_sha: "abc123d",                # Short SHA
  timestamp: ~U[2025-01-15 10:30:00Z], # Tag/commit timestamp
  semver: %{                           # Parsed semantic version
    major: 1,
    minor: 2,
    patch: 3,
    pre_release: nil,                  # e.g., "alpha.1", "rc.2"
    build: nil                         # e.g., "build.123"
  },
  previous_version: "1.2.2",           # Previous release version
  project_name: :elixir_ontologies,    # From mix.exs
  metadata: %{}
}
```

### Implementation Approach

1. Use `git tag --list` to enumerate tags
2. Use `git show` to get tag commit and timestamp
3. Parse mix.exs at each tagged commit for version
4. Implement semver parsing following https://semver.org/
5. Sort releases by semver to track progression

### Key Functions

- `extract_releases/1` - Extract all releases from repository
- `extract_release/2` - Extract single release by tag name
- `extract_current_version/1` - Get version from current mix.exs
- `list_tags/1` - List all git tags
- `parse_semver/1` - Parse semantic version string
- `compare_versions/2` - Compare two version strings
- `release_progression/1` - Get ordered list of releases

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/release.ex`
- [x] Add module doc and type specs
- [x] Import necessary modules (GitUtils, Commit)

### Step 2: Define Release Struct
- [x] Define struct with all fields
- [x] Add @type definition
- [x] Add field documentation

### Step 3: Implement Semantic Version Parsing
- [x] `parse_semver/1` - Parse "1.2.3" into components
- [x] Handle pre-release versions (e.g., "1.0.0-alpha.1")
- [x] Handle build metadata (e.g., "1.0.0+build.123")
- [x] `compare_versions/2` - Compare two semver strings

### Step 4: Implement Tag Extraction
- [x] `list_tags/1` - List all git tags using git tag --list
- [x] `extract_tag_info/2` - Get commit SHA and timestamp for tag
- [x] Filter for version-like tags (v1.2.3, 1.2.3, etc.)

### Step 5: Implement Version Extraction from mix.exs
- [x] `extract_version_at_commit/2` - Read mix.exs at specific commit
- [x] Parse version from mix.exs AST
- [x] Handle @version module attributes

### Step 6: Implement Main Extraction
- [x] `extract_releases/1` - Extract all releases from tags
- [x] `extract_release/2` - Extract single release by tag
- [x] `extract_current_version/1` - Get current version
- [x] `release_progression/1` - Order releases by version

### Step 7: Testing
- [x] Test semver parsing (various formats)
- [x] Test tag listing
- [x] Test version extraction from mix.exs
- [x] Test release progression ordering
- [x] Test error handling
- [x] Test with real repository

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/extractors/evolution/release.ex`
- `test/elixir_ontologies/extractors/evolution/release_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)

## Success Criteria

1. All 6 subtasks completed
2. `extract_releases/1` returns ordered list of releases
3. Semantic version parsing handles all valid formats
4. Tag extraction works with various tag naming conventions
5. All tests passing
