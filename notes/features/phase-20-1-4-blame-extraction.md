# Phase 20.1.4: Blame Information Extraction

## Overview

Extract line-level attribution using git blame, enabling tracking of which commit and author last modified each line of a file.

## Problem Statement

For fine-grained code provenance, we need to understand:
1. Which commit last modified each line
2. Who authored each line and when
3. How old each line is (time since last change)
4. Handle uncommitted changes (working copy modifications)

## Design Decisions

1. **Use porcelain format**: `git blame --porcelain` provides machine-readable output
2. **Integration with Commit extractor**: Reference existing Commit structs where possible
3. **Line age calculation**: Calculate time difference from blame timestamp to now
4. **Uncommitted handling**: Detect boundary commits (all zeros) for uncommitted lines

## Technical Details

### New Files
- `lib/elixir_ontologies/extractors/evolution/blame.ex` - Blame extractor
- `test/elixir_ontologies/extractors/evolution/blame_test.exs` - Tests

### Structs

```elixir
# Represents blame information for a single line
defmodule BlameInfo do
  defstruct [
    :line_number,      # 1-based line number
    :content,          # Line content
    :commit_sha,       # SHA of the last commit to modify this line
    :author_name,      # Author who last modified the line
    :author_email,     # Author's email
    :author_time,      # Unix timestamp when authored
    :author_date,      # DateTime when authored
    :committer_name,   # Committer name
    :committer_email,  # Committer email
    :committer_time,   # Unix timestamp when committed
    :commit_date,      # DateTime when committed
    :summary,          # Commit message summary
    :filename,         # Current filename
    :previous,         # Previous commit SHA (if line existed before)
    :line_age_seconds, # Age of line in seconds
    :is_uncommitted    # True if line is not yet committed
  ]
end

# Represents blame for entire file
defmodule FileBlame do
  defstruct [
    :path,             # File path
    :lines,            # List of BlameInfo structs
    :line_count,       # Total number of lines
    :commit_count,     # Number of unique commits
    :author_count,     # Number of unique authors
    :oldest_line,      # BlameInfo of oldest line
    :newest_line,      # BlameInfo of newest line
    :has_uncommitted,  # True if any uncommitted lines
    metadata: %{}
  ]
end
```

### Key Functions
- `extract_blame/2` - Extract blame for a file
- `extract_blame!/2` - Raising version
- `line_age/1` - Get age of a BlameInfo in seconds
- `is_uncommitted?/1` - Check if line is uncommitted
- `commits_in_blame/1` - Get unique commits from FileBlame
- `authors_in_blame/1` - Get unique authors from FileBlame
- `lines_by_commit/1` - Group lines by commit
- `lines_by_author/1` - Group lines by author

### Git Commands

```bash
# Get blame in porcelain format
git blame --porcelain <file>

# Get blame for specific lines
git blame --porcelain -L 10,20 <file>

# Get blame at a specific commit
git blame --porcelain <commit> -- <file>
```

### Porcelain Format

The porcelain format outputs:
1. First line: `<SHA> <original_line> <final_line> [<num_lines>]`
2. Header lines (only on first occurrence of commit):
   - `author <name>`
   - `author-mail <email>`
   - `author-time <timestamp>`
   - `author-tz <timezone>`
   - `committer <name>`
   - `committer-mail <email>`
   - `committer-time <timestamp>`
   - `committer-tz <timezone>`
   - `summary <commit summary>`
   - `previous <SHA> <filename>` (if line existed before)
   - `filename <current filename>`
3. Content line: `\t<content>`

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/blame.ex`
- [x] Define `BlameInfo` struct
- [x] Define `FileBlame` struct (named `Blame` as top-level module)
- [x] Add module documentation

### Step 2: Implement Core Parsing
- [x] Parse porcelain format output
- [x] Build commit info cache (commits appear once, then abbreviated)
- [x] Handle line content extraction

### Step 3: Implement Extraction Functions
- [x] `extract_blame/2` using git blame --porcelain
- [x] `extract_blame!/2` raising version
- [x] Handle errors (file not found, not tracked, etc.)

### Step 4: Add Line Age Calculation
- [x] Calculate age from author_time to now
- [x] Find oldest and newest lines in file
- [x] Handle uncommitted lines (no valid timestamp)

### Step 5: Add Query Functions
- [x] `is_uncommitted?/1` - check if line is uncommitted
- [x] `line_age/1` - get line age in seconds
- [x] `commits_in_blame/1` - unique commits
- [x] `authors_in_blame/1` - unique authors
- [x] `lines_by_commit/1` - group lines by commit
- [x] `lines_by_author/1` - group lines by author
- [x] `oldest_line/1` - get oldest line
- [x] `newest_line/1` - get newest line
- [x] `line_count_for_commit/2` - count lines for a commit
- [x] `line_count_for_author/2` - count lines for an author

### Step 6: Write Tests
- [x] Test blame extraction (34 tests)
- [x] Test porcelain parsing
- [x] Test line age calculation
- [x] Test uncommitted detection
- [x] Test query functions
- [x] Test with non-existent files
- [x] Test integration with repository

## Success Criteria

1. All subtasks in 20.1.4 marked complete
2. Comprehensive test coverage
3. Proper handling of uncommitted changes
4. Integration with existing evolution extractors

## Dependencies

- `ElixirOntologies.Analyzer.Git` - repository detection
- Integration patterns from Commit and FileHistory extractors
