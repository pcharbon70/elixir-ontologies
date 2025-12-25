# Phase 20.1.1: Commit Information Extraction

## Overview

Extract commit metadata from Git for code provenance. This is the first task in Phase 20 (Evolution & Provenance with PROV-O), establishing the foundation for tracking code changes over time.

## Problem Statement

The ontology needs to model code provenance - how code evolves over time and who is responsible for changes. Git commits are the fundamental unit of change tracking, and we need a structured way to extract and represent commit information.

## Existing Infrastructure

The project already has substantial git infrastructure in `lib/elixir_ontologies/analyzer/git.ex`:

- `Git.Repository` struct - repository metadata
- `Git.CommitRef` struct - basic commit reference (sha, short_sha, message, tags, timestamp, author)
- `Git.commit_ref/1` - extract current commit info
- `Git.current_commit/1` - get full SHA
- `Git.commit_message/1` / `Git.commit_message_full/1` - get messages
- `Git.Adapter` - abstraction for git command execution

The new `evolution/commit.ex` extractor will build on this to provide:
- Richer commit metadata (parent commits, committer distinct from author)
- Support for extracting any commit (not just HEAD)
- Integration with PROV-O concepts

## Design Decisions

1. **Reuse existing Git module** - Build on `Git.Adapter` for command execution
2. **Separate from Git.CommitRef** - New struct focused on PROV-O integration
3. **Evolution namespace** - Place in `extractors/evolution/` to mirror ontology layer
4. **Parent tracking** - Track parent commits for merge detection and history traversal

## Technical Details

### New Files
- `lib/elixir_ontologies/extractors/evolution/commit.ex` - Main extractor
- `test/elixir_ontologies/extractors/evolution/commit_test.exs` - Tests

### Struct Definition
```elixir
defmodule ElixirOntologies.Extractors.Evolution.Commit do
  defstruct [
    :sha,           # Full 40-character SHA
    :short_sha,     # 7-character abbreviated SHA
    :message,       # Full commit message (subject + body)
    :subject,       # First line of message
    :body,          # Message body (after blank line)
    :author_name,   # Author name
    :author_email,  # Author email
    :author_date,   # Author timestamp (DateTime)
    :committer_name,  # Committer name (may differ from author)
    :committer_email, # Committer email
    :commit_date,   # Commit timestamp (DateTime)
    :parents,       # List of parent SHAs
    :is_merge,      # True if >1 parent
    :tree_sha,      # Tree object SHA
    metadata: %{}   # Additional metadata
  ]
end
```

### Key Functions
- `extract_commit/2` - Extract commit by SHA (or "HEAD")
- `extract_commits/3` - Extract multiple commits with limit/offset
- `extract_commit!/2` - Raising version
- `commit?/1` - Validate SHA format
- `merge_commit?/1` - Check if commit is a merge

### Git Commands
```bash
# Full commit info using custom format
git log -1 --format="%H%n%h%n%s%n%b%n%an%n%ae%n%aI%n%cn%n%ce%n%cI%n%P%n%T" <sha>
```

Format explanation:
- `%H` - full hash
- `%h` - abbreviated hash
- `%s` - subject (first line)
- `%b` - body
- `%an` - author name
- `%ae` - author email
- `%aI` - author date (ISO 8601)
- `%cn` - committer name
- `%ce` - committer email
- `%cI` - committer date (ISO 8601)
- `%P` - parent hashes
- `%T` - tree hash

## Implementation Plan

### Step 1: Create Module Structure ✅
- [x] Create `lib/elixir_ontologies/extractors/evolution/commit.ex`
- [x] Define the `Commit` struct with all fields
- [x] Add module documentation

### Step 2: Implement Core Extraction ✅
- [x] Implement `extract_commit/2` using git log with format string
- [x] Parse the git output into struct fields
- [x] Handle datetime parsing for author_date and commit_date
- [x] Parse parent SHA list
- [x] Calculate is_merge from parent count

### Step 3: Add Helper Functions ✅
- [x] `valid_sha?/1` - validate SHA format (40 hex chars)
- [x] `valid_short_sha?/1` - validate short SHA format (7-40 hex chars)
- [x] `merge_commit?/1` - check parent count > 1
- [x] `initial_commit?/1` - check for no parents
- [x] `extract_subject/1` and `extract_body/1` - message parsing

### Step 4: Add Multiple Commit Extraction ✅
- [x] `extract_commits/2` - extract range of commits
- [x] Support limit and offset options
- [x] Handle commit reference (from option)

### Step 5: Write Tests ✅
- [x] Test SHA extraction (full and short)
- [x] Test message parsing (subject/body split)
- [x] Test author/committer extraction
- [x] Test datetime parsing
- [x] Test parent extraction
- [x] Test merge commit detection
- [x] Test invalid SHA handling
- [x] Test repository not found handling
- [x] 46 tests total, all passing

## Success Criteria

1. All subtasks in 20.1.1 marked complete
2. Comprehensive test coverage
3. Integration with existing Git infrastructure
4. Clean separation from existing CommitRef

## Dependencies

- `ElixirOntologies.Analyzer.Git` - repository detection
- `ElixirOntologies.Analyzer.Git.Adapter` - git command execution

## Notes

- Author vs Committer: In Git, the author is who wrote the code, the committer is who committed it. They differ in scenarios like rebasing, cherry-picking, or applying patches.
- The existing `Git.CommitRef` is focused on current HEAD for source URLs; the new `Commit` struct is for full provenance tracking of any commit.
