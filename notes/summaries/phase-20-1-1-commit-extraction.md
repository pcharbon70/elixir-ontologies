# Phase 20.1.1: Commit Information Extraction Summary

## Overview

Implemented the first task of Phase 20 (Evolution & Provenance with PROV-O), creating a commit extractor that extracts detailed Git commit metadata for code provenance tracking.

## What Was Implemented

### New Module: `lib/elixir_ontologies/extractors/evolution/commit.ex`

A comprehensive Git commit extractor that builds on the existing `ElixirOntologies.Analyzer.Git` infrastructure.

### Commit Struct

```elixir
defstruct [
  :sha,             # Full 40-character SHA hash
  :short_sha,       # 7-character abbreviated SHA
  :message,         # Full commit message (subject + body)
  :subject,         # First line of message
  :body,            # Message body (after blank line)
  :author_name,     # Author name
  :author_email,    # Author email
  :author_date,     # Author timestamp (DateTime)
  :committer_name,  # Committer name (may differ from author)
  :committer_email, # Committer email
  :commit_date,     # Commit timestamp (DateTime)
  :parents,         # List of parent SHAs
  :is_merge,        # True if >1 parent
  :tree_sha,        # Tree object SHA
  metadata: %{}
]
```

### Key Functions

| Function | Description |
|----------|-------------|
| `extract_commit/2` | Extract commit by SHA or "HEAD" |
| `extract_commit!/2` | Raising version of extract_commit |
| `extract_commits/2` | Extract multiple commits with limit/offset |
| `valid_sha?/1` | Validate full 40-character SHA |
| `valid_short_sha?/1` | Validate abbreviated SHA (7-40 chars) |
| `merge_commit?/1` | Check if commit has multiple parents |
| `initial_commit?/1` | Check if commit has no parents |
| `extract_subject/1` | Parse subject from message |
| `extract_body/1` | Parse body from message |

### Technical Approach

**Git Log Format String:**
Uses a custom format with unit separator (`\x1f`) as delimiter:
```
%H%x1f%h%x1f%an%x1f%ae%x1f%aI%x1f%cn%x1f%ce%x1f%cI%x1f%P%x1f%T%x1f%B
```

The message (`%B`) is placed last because it can contain any characters including the delimiter. The parser splits on the first 10 delimiters, leaving the message intact.

**Author vs Committer:**
The extractor properly distinguishes between:
- **Author**: Who wrote the code originally
- **Committer**: Who created the commit (differs in rebase, cherry-pick, patches)

### Test Coverage

46 tests covering:
- SHA validation (full and short)
- Message parsing (subject/body extraction)
- Author and committer extraction
- DateTime parsing for timestamps
- Parent commit extraction
- Merge commit detection
- Initial commit detection
- Error handling (invalid ref, non-existent repo)
- Multiple commit extraction

## Files Created

1. `lib/elixir_ontologies/extractors/evolution/commit.ex` - Main extractor module
2. `test/elixir_ontologies/extractors/evolution/commit_test.exs` - Test suite
3. `notes/features/phase-20-1-1-commit-extraction.md` - Planning document

## Differences from Existing Git.CommitRef

| Feature | Git.CommitRef | Evolution.Commit |
|---------|---------------|------------------|
| Purpose | Source URL generation | Provenance tracking |
| Scope | HEAD only | Any commit |
| Author info | Name only | Name + email + date |
| Committer | Not tracked | Full info |
| Parents | Not tracked | List of SHAs |
| Message | Subject only | Subject + body |
| Tree SHA | Not tracked | Tracked |

## Integration Points

- Builds on `ElixirOntologies.Analyzer.Git.detect_repo/1`
- Uses same git command execution pattern
- Ready for PROV-O builder integration in Phase 20.4

## Test Results

- 46 tests, 0 failures
- All doctests pass
- No regressions in existing tests

## Next Task

**Task 20.1.2: Author and Committer Extraction**
- Define `%Developer{name: ..., email: ..., commits: [...]}` struct
- Extract commit author (name and email)
- Extract commit committer (may differ from author)
- Track author timestamps
- Build developer identity across commits
