# Phase 20.1.2: Author and Committer Extraction

## Overview

Extract author and committer information from commits and build developer identity across multiple commits. This builds on the Commit extractor from Phase 20.1.1.

## Problem Statement

While individual commits contain author/committer info, we need a way to:
1. Represent developers as first-class entities
2. Aggregate developer activity across commits
3. Track both authoring and committing roles
4. Handle identity across different name/email combinations

## Existing Infrastructure

From Phase 20.1.1, the `Commit` struct already contains:
- `author_name`, `author_email`, `author_date`
- `committer_name`, `committer_email`, `commit_date`

This task creates a new `Developer` module that aggregates this information.

## Design Decisions

1. **Separate Module** - Create `developer.ex` alongside `commit.ex`
2. **Email as Primary Identity** - Use email as the primary identifier for developers
3. **Track Both Roles** - Distinguish between authored commits and committed commits
4. **Timestamp Tracking** - Track first/last activity dates

## Technical Details

### New Files
- `lib/elixir_ontologies/extractors/evolution/developer.ex` - Developer extractor
- `test/elixir_ontologies/extractors/evolution/developer_test.exs` - Tests

### Struct Definition
```elixir
defmodule ElixirOntologies.Extractors.Evolution.Developer do
  defstruct [
    :email,              # Primary identifier
    :name,               # Display name (may vary across commits)
    :names,              # All names used with this email
    :authored_commits,   # List of commit SHAs authored
    :committed_commits,  # List of commit SHAs committed
    :first_authored,     # First author date
    :last_authored,      # Last author date
    :first_committed,    # First commit date
    :last_committed,     # Last commit date
    :commit_count,       # Total unique commits (author or committer)
    metadata: %{}
  ]
end
```

### Key Functions
- `extract_developers/2` - Extract all developers from repository
- `extract_developer/2` - Extract single developer by email
- `from_commit/1` - Extract developer info from a Commit struct
- `from_commits/1` - Aggregate developers from multiple commits
- `merge_developers/2` - Merge two developer records (same email)
- `author_from_commit/1` - Get author Developer from commit
- `committer_from_commit/1` - Get committer Developer from commit

## Implementation Plan

### Step 1: Create Module Structure ✅
- [x] Create `lib/elixir_ontologies/extractors/evolution/developer.ex`
- [x] Define the `Developer` struct with all fields
- [x] Add module documentation

### Step 2: Implement Single Commit Extraction ✅
- [x] `author_from_commit/1` - extract author as Developer
- [x] `committer_from_commit/1` - extract committer as Developer
- [x] `from_commit/1` - handle case where author == committer

### Step 3: Implement Aggregation ✅
- [x] `from_commits/1` - aggregate developers from commit list
- [x] `merge_developers/2` - merge two Developer structs by email
- [x] Track all names used by a developer (MapSet)

### Step 4: Implement Repository-Level Extraction ✅
- [x] `extract_developers/2` - extract all developers from repo
- [x] `extract_developer/3` - extract specific developer by email
- [x] Support limit/from options

### Step 5: Write Tests ✅
- [x] Test author extraction from single commit
- [x] Test committer extraction from single commit
- [x] Test aggregation across multiple commits
- [x] Test name variation tracking
- [x] Test timestamp tracking (first/last authored/committed)
- [x] Test repository-level extraction
- [x] 32 tests total, all passing

## Success Criteria

1. All subtasks in 20.1.2 marked complete
2. Comprehensive test coverage
3. Integration with existing Commit extractor
4. Clean API for developer identity tracking

## Dependencies

- `ElixirOntologies.Extractors.Evolution.Commit` - commit extraction
- `ElixirOntologies.Analyzer.Git` - repository detection
