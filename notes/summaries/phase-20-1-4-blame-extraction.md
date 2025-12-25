# Phase 20.1.4: Blame Information Extraction Summary

## Overview

Implemented the fourth task of Phase 20 (Evolution & Provenance), creating a Blame extractor that tracks line-level attribution using git blame. This enables fine-grained provenance tracking to understand which commit and author last modified each line of a file.

## What Was Implemented

### New Module: `lib/elixir_ontologies/extractors/evolution/blame.ex`

A blame extraction module using `git blame --porcelain` for machine-readable output.

### BlameInfo Struct

```elixir
defstruct [
  :line_number,      # 1-based line number
  :content,          # Line content
  :commit_sha,       # SHA of last modifying commit
  :author_name,      # Author who last modified
  :author_email,     # Author's email
  :author_time,      # Unix timestamp when authored
  :author_date,      # DateTime when authored
  :committer_name,   # Committer name
  :committer_email,  # Committer email
  :committer_time,   # Unix timestamp when committed
  :commit_date,      # DateTime when committed
  :summary,          # Commit message summary
  :filename,         # Current filename
  :previous,         # Previous commit SHA
  :line_age_seconds, # Age of line in seconds
  :is_uncommitted    # True if not yet committed
]
```

### FileBlame Struct (Blame module)

```elixir
defstruct [
  :path,             # File path
  :oldest_line,      # BlameInfo of oldest line
  :newest_line,      # BlameInfo of newest line
  lines: [],         # List of BlameInfo structs
  line_count: 0,     # Total number of lines
  commit_count: 0,   # Number of unique commits
  author_count: 0,   # Number of unique authors
  has_uncommitted: false,
  metadata: %{}
]
```

### Key Functions

| Function | Description |
|----------|-------------|
| `extract_blame/3` | Extract blame for a file with options |
| `extract_blame!/3` | Raising version |
| `is_uncommitted?/1` | Check if line is uncommitted |
| `line_age/1` | Get line age in seconds |
| `commits_in_blame/1` | Get unique commits |
| `authors_in_blame/1` | Get unique authors as `{name, email}` tuples |
| `lines_by_commit/1` | Group lines by commit SHA |
| `lines_by_author/1` | Group lines by author email |
| `oldest_line/1` | Get the oldest line |
| `newest_line/1` | Get the newest line |
| `line_count_for_commit/2` | Count lines for a commit |
| `line_count_for_author/2` | Count lines for an author |

### Design Decisions

1. **Porcelain Format**: Uses `git blame --porcelain` for machine-readable output
2. **Commit Cache**: Caches commit info since Git only outputs it once per commit
3. **Line Age Calculation**: Calculates age from author_time to current time
4. **Uncommitted Detection**: Detects all-zero SHA for uncommitted lines
5. **DateTime Conversion**: Converts Unix timestamps to Elixir DateTime

### Features

- **Line-Level Attribution**: Track which commit/author last modified each line
- **Age Tracking**: Calculate how old each line is in seconds
- **Uncommitted Handling**: Detect and mark uncommitted changes
- **Grouping**: Group lines by commit or author for analysis
- **Statistics**: Track unique commits, authors, oldest/newest lines

## Git Command Used

```bash
git blame --porcelain [<revision>] [--] <file>
```

## Files Created

1. `lib/elixir_ontologies/extractors/evolution/blame.ex` - Blame extractor module
2. `test/elixir_ontologies/extractors/evolution/blame_test.exs` - Test suite
3. `notes/features/phase-20-1-4-blame-extraction.md` - Planning document

## Test Results

- 34 tests for Blame, 0 failures
- Combined evolution tests: 142 tests total, all passing

## Integration

Works with existing evolution extractors:

```elixir
alias ElixirOntologies.Extractors.Evolution.Blame

# Extract blame for a file
{:ok, blame} = Blame.extract_blame(".", "lib/my_module.ex")

# Get line attribution
line = List.first(blame.lines)
IO.puts("Line 1 was last modified by #{line.author_name}")
IO.puts("Age: #{Blame.line_age(line)} seconds")

# Get unique authors
authors = Blame.authors_in_blame(blame)
# => [{"Developer Name", "dev@example.com"}, ...]

# Group lines by commit
by_commit = Blame.lines_by_commit(blame)
```

## Section 20.1 Complete

With this task, Section 20.1 (Version Control Integration) is now complete:

- [x] 20.1.1 Commit Information Extraction (46 tests)
- [x] 20.1.2 Author and Committer Extraction (32 tests)
- [x] 20.1.3 File History Extraction (30 tests)
- [x] 20.1.4 Blame Information Extraction (34 tests)

## Next Task

**Task 20.2.1: Activity Classification**
- Create `lib/elixir_ontologies/extractors/evolution/activity.ex`
- Define `%DevelopmentActivity{type: ..., commit: ..., entities: [...], agents: [...]}` struct
- Implement heuristic classification (bug fix, feature, refactor, etc.)
- Parse conventional commit format (feat:, fix:, refactor:, etc.)
- Track activity scope (files and modules affected)
- Add activity classification tests
