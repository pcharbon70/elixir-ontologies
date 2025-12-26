# Phase 20.2.2: Refactoring Detection - Summary

## Overview

Implemented refactoring detection module that analyzes git diffs to identify common refactoring patterns in Elixir code.

## Implementation

### Module: `ElixirOntologies.Extractors.Evolution.Refactoring`

Created `lib/elixir_ontologies/extractors/evolution/refactoring.ex` with the following components:

#### Nested Structs

1. **`Refactoring.Source`** - Source location of refactoring:
   - `file` - Source file path
   - `module` - Module name
   - `function` - Function name and arity tuple
   - `line_range` - Start and end lines
   - `code` - Source code snippet

2. **`Refactoring.Target`** - Target location of refactoring:
   - Same fields as Source

3. **`Refactoring.DiffHunk`** - Parsed diff information:
   - `file` - File path
   - `old_file` - Original file path (for renames)
   - `status` - `:added`, `:deleted`, `:modified`, `:renamed`
   - `additions` - List of `{line_num, content}` tuples
   - `deletions` - List of `{line_num, content}` tuples
   - `similarity` - Rename similarity percentage

4. **`Refactoring`** (main struct):
   - `type` - Refactoring type atom
   - `source` - Source location
   - `target` - Target location
   - `commit` - Associated Commit struct
   - `confidence` - `:high`, `:medium`, or `:low`
   - `metadata` - Additional information

#### Refactoring Types

| Type | Description |
|------|-------------|
| `:extract_function` | Code moved to new function |
| `:extract_module` | Code moved to new module |
| `:rename_function` | Function name changed |
| `:rename_module` | Module name changed |
| `:rename_variable` | Variable name changed (not implemented) |
| `:inline_function` | Function body inlined at call sites |
| `:move_function` | Function moved between modules |

#### Key Functions

- `detect_refactorings/3` - Main detection function, combines all strategies
- `detect_refactorings!/3` - Bang variant
- `detect_refactorings_in_commits/3` - Batch detection across commits
- `get_commit_diff/2` - Extract structured diff from commit
- `detect_function_extractions/3` - Detect extracted functions
- `detect_module_extractions/3` - Detect extracted modules
- `detect_function_renames/3` - Detect renamed functions
- `detect_module_renames/3` - Detect renamed modules
- `detect_function_inlines/3` - Detect inlined functions
- `detect_function_moves/3` - Detect moved functions

#### Detection Strategies

1. **Function Extraction** (high confidence)
   - Finds new function definitions in additions
   - Checks for calls to new function where code was removed
   - Uses code similarity matching between deleted and new code

2. **Module Extraction** (high confidence)
   - Detects new module files
   - Matches function signatures between deleted and new module
   - High confidence when matching functions found

3. **Function Rename** (high confidence)
   - Different name, same arity
   - Body similarity > 70% using Jaccard similarity on tokens
   - Excludes common keywords from similarity

4. **Module Rename** (high/medium confidence)
   - Uses git's -M flag for rename detection
   - High confidence for >= 90% similarity

5. **Function Inline** (medium confidence)
   - Function definition deleted
   - Function body tokens appear in additions

6. **Function Move** (high confidence)
   - Same name and arity in different files
   - Body similarity > 70%

### Test File

Created `test/elixir_ontologies/extractors/evolution/refactoring_test.exs` with 25 tests covering:

- Refactoring types enumeration
- Struct defaults (Source, Target, DiffHunk, Refactoring)
- Function extraction detection
- Module extraction detection
- Function rename detection
- Module rename detection
- Inline detection
- Move detection
- Integration tests with real commits
- Edge cases

## Design Decisions

1. **Confidence Levels**: Each detection strategy assigns confidence based on strength of evidence (matching calls, high similarity, etc.)

2. **Code Similarity**: Uses Jaccard similarity on tokenized code, excluding common keywords like `def`, `do`, `end`.

3. **Diff Parsing**: Parses git diff output directly, handling additions/deletions with line numbers and file status.

4. **Variable Rename**: Not implemented in this phase as it requires more sophisticated lexical analysis.

## Files Changed

### New Files
- `lib/elixir_ontologies/extractors/evolution/refactoring.ex`
- `test/elixir_ontologies/extractors/evolution/refactoring_test.exs`
- `notes/features/phase-20-2-2-refactoring-detection.md`
- `notes/summaries/phase-20-2-2-refactoring-detection.md`

### Modified Files
- `notes/planning/extractors/phase-20.md` - Marked task 20.2.2 as complete

## Test Results

All 25 refactoring tests pass. The full evolution test suite (289 tests) passes.

## Next Task

The next logical task is **20.2.3 Deprecation Tracking**, which will:
- Define `%Deprecation{element: ..., deprecated_in: ..., removed_in: ..., replacement: ...}` struct
- Detect @deprecated attribute additions
- Track deprecation announcement commits
- Track removal commits
- Extract suggested replacement from deprecation message
