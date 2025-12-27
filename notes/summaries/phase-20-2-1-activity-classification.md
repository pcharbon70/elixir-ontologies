# Phase 20.2.1: Activity Classification - Summary

## Overview

Implemented activity classification for commits, enabling categorization of development activities based on commit messages and file changes. This module supports conventional commit parsing and heuristic classification, integrating with the PROV-O provenance model.

## Implementation

### Module: `ElixirOntologies.Extractors.Evolution.Activity`

Created `lib/elixir_ontologies/extractors/evolution/activity.ex` with the following components:

#### Nested Structs

1. **`Activity.Scope`** - Tracks the scope of changes:
   - `files_changed` - List of modified files
   - `modules_affected` - Elixir modules affected
   - `lines_added` / `lines_deleted` - Change statistics

2. **`Classification`** - Records how the type was determined:
   - `method` - `:conventional_commit`, `:keyword`, or `:file_based`
   - `confidence` - `:high`, `:medium`, or `:low`
   - `breaking` - Whether this is a breaking change
   - `scope_hint` - Conventional commit scope (e.g., "auth" from `feat(auth):`)

3. **`Activity`** (main struct):
   - `type` - Activity type atom (`:feature`, `:bugfix`, `:refactor`, etc.)
   - `commit` - Associated `Commit` struct
   - `scope` - Changes scope
   - `classification` - Classification metadata

#### Activity Types

| Type | Description | Conventional Prefix |
|------|-------------|---------------------|
| `:feature` | New functionality | `feat:`, `feature:` |
| `:bugfix` | Bug fix | `fix:`, `bugfix:` |
| `:refactor` | Code restructuring | `refactor:` |
| `:docs` | Documentation | `docs:` |
| `:test` | Test changes | `test:` |
| `:chore` | Build/tooling | `chore:`, `build:` |
| `:style` | Formatting | `style:` |
| `:perf` | Performance | `perf:` |
| `:ci` | CI/CD changes | `ci:` |
| `:revert` | Revert commit | `revert:` |
| `:deps` | Dependency updates | `deps:` |
| `:release` | Version release | `release:` |
| `:wip` | Work in progress | `wip:` |
| `:unknown` | Cannot classify | (fallback) |

#### Classification Methods

1. **Conventional Commit Parsing** (high confidence)
   - Pattern: `type(scope)!: description`
   - Handles breaking change indicator (`!`)
   - Extracts optional scope from parentheses

2. **Keyword Heuristics** (medium confidence)
   - Ordered pattern matching for accurate classification
   - Specific patterns (docs, test, perf) checked before generic (feature)
   - Detects breaking change keywords in message

3. **File-Based Heuristics** (low confidence)
   - All test files → `:test`
   - All markdown files → `:docs`
   - Only mix.exs/mix.lock → `:deps`
   - CI config files → `:ci`

#### Key Functions

- `classify_commit/3` - Classify a single commit
- `classify_commits/3` - Batch classification
- `parse_conventional_commit/1` - Parse conventional commit format
- `extract_scope/2` - Extract changed files and modules via `git diff-tree`
- `type_from_string/1` - Convert type string to atom
- `activity_types/0` - List all supported types
- `breaking_change?/1` - Check if activity is breaking
- `classification_confidence/1` - Get classification confidence

### Test File

Created `test/elixir_ontologies/extractors/evolution/activity_test.exs` with 45 tests covering:

- Conventional commit parsing (various formats, edge cases)
- Type conversion
- Commit classification with conventional commits
- Keyword heuristic classification
- Breaking change detection
- Batch classification
- Edge cases (nil, empty, long subjects, special characters)
- Integration tests with real repository

## Design Decisions

1. **Pattern Order Matters**: Keyword patterns are ordered so specific patterns (docs, test, perf) are checked before generic patterns (feature with "add"). This prevents "Add tests" from being classified as `:feature`.

2. **Tuple Returns for File Classification**: The `classify_by_files` function returns `{type, classification}` tuples for consistency with other classification methods.

3. **Empty Scope Handling**: The regex allows empty parentheses `feat(): description` to handle edge cases gracefully.

4. **Scope Extraction**: Uses `git diff-tree --numstat` to extract file changes and line statistics without checking out files.

5. **Module Path Extraction**: Converts file paths like `lib/foo/bar.ex` to module names like `Foo.Bar`.

## Files Changed

### New Files
- `lib/elixir_ontologies/extractors/evolution/activity.ex`
- `test/elixir_ontologies/extractors/evolution/activity_test.exs`
- `notes/features/phase-20-2-1-activity-classification.md`
- `notes/summaries/phase-20-2-1-activity-classification.md`

### Modified Files
- `notes/planning/extractors/phase-20.md` - Marked task 20.2.1 as complete

## Test Results

All 45 activity tests pass. The full evolution test suite (264 tests) passes.

## Next Task

The next logical task is **20.2.2 Refactoring Detection**, which will:
- Define `%Refactoring{type: ..., source: ..., target: ..., commit: ...}` struct
- Detect function extraction refactoring
- Detect module extraction refactoring
- Detect rename refactoring (function, module, variable)
- Detect inline refactoring
