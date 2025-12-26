# Phase 20.2.2: Refactoring Detection

## Overview

Detect and classify refactoring activities from code changes. This module analyzes git diffs to identify common refactoring patterns like function extraction, module extraction, renames, and inlining.

## Requirements

From phase-20.md task 20.2.2:

- [x] 20.2.2.1 Define `%Refactoring{type: ..., source: ..., target: ..., commit: ...}` struct
- [x] 20.2.2.2 Detect function extraction refactoring
- [x] 20.2.2.3 Detect module extraction refactoring
- [x] 20.2.2.4 Detect rename refactoring (function, module, variable)
- [x] 20.2.2.5 Detect inline refactoring
- [x] 20.2.2.6 Add refactoring detection tests (25 tests)

## Design

### Refactoring Types

| Type | Description | Detection Method |
|------|-------------|------------------|
| `:extract_function` | Code moved to new function | New function + deleted code block |
| `:extract_module` | Code moved to new module | New module file + code removed from source |
| `:rename_function` | Function name changed | Same body, different name |
| `:rename_module` | Module name changed | File rename or module declaration change |
| `:rename_variable` | Variable name changed | Pattern substitution in scope |
| `:inline_function` | Function body inlined at call sites | Function removed + body appears at call sites |
| `:move_function` | Function moved between modules | Function deleted in one, added in another |

### Struct Design

```elixir
defmodule Refactoring do
  @type refactoring_type ::
    :extract_function | :extract_module | :rename_function |
    :rename_module | :rename_variable | :inline_function | :move_function

  @type t :: %__MODULE__{
    type: refactoring_type(),
    source: Source.t(),
    target: Target.t(),
    commit: Commit.t(),
    confidence: :high | :medium | :low,
    metadata: map()
  }
end

defmodule Source do
  @type t :: %__MODULE__{
    file: String.t(),
    module: String.t() | nil,
    function: {atom(), non_neg_integer()} | nil,
    line_range: {pos_integer(), pos_integer()} | nil
  }
end

defmodule Target do
  @type t :: %__MODULE__{
    file: String.t(),
    module: String.t() | nil,
    function: {atom(), non_neg_integer()} | nil,
    line_range: {pos_integer(), pos_integer()} | nil
  }
end
```

### Detection Strategies

1. **Function Extraction Detection**
   - Analyze diff for new function definitions
   - Check if code was removed from another location
   - Match code similarity between removed and new function body
   - High confidence if call to new function appears where code was removed

2. **Module Extraction Detection**
   - Detect new module file creation
   - Check for code deletion in existing modules
   - Match function signatures between deleted and new module
   - Track `alias`/`import` additions pointing to new module

3. **Rename Detection**
   - Function: Same arity, similar body, different name
   - Module: File renamed or `defmodule` name changed
   - Variable: Lexical scope analysis with substitution pattern

4. **Inline Detection**
   - Function definition removed
   - Function body appears at former call sites
   - Call sites replaced with inlined code

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/refactoring.ex`
- [x] Define Refactoring struct with type, source, target, commit, confidence
- [x] Define Source struct
- [x] Define Target struct
- [x] Add type specs and moduledoc

### Step 2: Diff Analysis Infrastructure
- [x] Implement `get_commit_diff/2` to extract structured diff
- [x] Parse diff into additions/deletions per file
- [x] Extract function definitions from diff hunks
- [x] Track file renames from git

### Step 3: Function Extraction Detection
- [x] Implement `detect_function_extractions/3`
- [x] Find new function definitions in diff
- [x] Find deleted code blocks
- [x] Match extracted code to new function body
- [x] Check for new function calls at deletion site

### Step 4: Module Extraction Detection
- [x] Implement `detect_module_extractions/3`
- [x] Identify new module files
- [x] Find deleted code in existing modules
- [x] Match function signatures

### Step 5: Rename Detection
- [x] Implement `detect_function_renames/3`
- [x] Implement `detect_module_renames/3`
- [x] Use git's rename detection (-M flag)
- [x] Parse function definition changes
- [x] Compare function bodies for similarity

### Step 6: Inline Detection
- [x] Implement `detect_function_inlines/3`
- [x] Find deleted function definitions
- [x] Search for function body at call sites
- [x] Match inlined code patterns

### Step 7: Main Detection Function
- [x] Implement `detect_refactorings/3`
- [x] Combine all detection strategies
- [x] Rank by confidence
- [x] Return list of Refactoring structs

### Step 8: Testing
- [x] Add function extraction tests
- [x] Add module extraction tests
- [x] Add rename detection tests
- [x] Add inline detection tests
- [x] Add integration tests with real commits
- [x] All 25 tests passing

## Success Criteria

1. All 6 subtasks completed
2. Function extraction detection works
3. Module extraction detection works
4. Rename detection works (function, module, variable)
5. Inline detection works
6. All tests passing
7. Integrates with existing Activity module

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/extractors/evolution/refactoring.ex`
- `test/elixir_ontologies/extractors/evolution/refactoring_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)
