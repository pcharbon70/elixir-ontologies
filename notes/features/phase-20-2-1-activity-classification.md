# Phase 20.2.1: Activity Classification

## Overview

Implement classification of commits into development activity types based on commit messages and changes. This enables tracking development activities as PROV-O activities, connecting code changes to their context.

## Requirements

From phase-20.md task 20.2.1:

- [ ] 20.2.1.1 Create `lib/elixir_ontologies/extractors/evolution/activity.ex`
- [ ] 20.2.1.2 Define `%DevelopmentActivity{type: ..., commit: ..., entities: [...], agents: [...]}` struct
- [ ] 20.2.1.3 Implement heuristic classification (bug fix, feature, refactor, etc.)
- [ ] 20.2.1.4 Parse conventional commit format (feat:, fix:, refactor:, etc.)
- [ ] 20.2.1.5 Track activity scope (files and modules affected)
- [ ] 20.2.1.6 Add activity classification tests

## Design

### Activity Types

Based on common development activities and conventional commits:

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

### Struct Design

```elixir
defmodule DevelopmentActivity do
  @type activity_type ::
    :feature | :bugfix | :refactor | :docs | :test | :chore |
    :style | :perf | :ci | :revert | :deps | :release | :wip | :unknown

  @type t :: %__MODULE__{
    type: activity_type(),
    commit: Commit.t(),
    scope: Scope.t(),
    classification: Classification.t(),
    metadata: map()
  }
end

defmodule Scope do
  @type t :: %__MODULE__{
    files_changed: [String.t()],
    modules_affected: [String.t()],
    lines_added: non_neg_integer(),
    lines_deleted: non_neg_integer()
  }
end

defmodule Classification do
  @type t :: %__MODULE__{
    method: :conventional_commit | :heuristic | :keyword,
    confidence: :high | :medium | :low,
    raw_type: String.t() | nil,
    breaking: boolean()
  }
end
```

### Classification Methods

1. **Conventional Commit Parsing** (high confidence)
   - Pattern: `type(scope)!?: description`
   - Examples: `feat(auth): add login`, `fix!: critical bug`

2. **Keyword Heuristics** (medium confidence)
   - Subject keywords: "add", "fix", "refactor", "update docs"
   - Body patterns: "Fixes #123", "BREAKING CHANGE"

3. **File-Based Heuristics** (low confidence)
   - Only test files changed → `:test`
   - Only markdown files → `:docs`
   - mix.exs with deps → `:deps`

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/activity.ex`
- [x] Define DevelopmentActivity struct
- [x] Define Scope struct
- [x] Define Classification struct
- [x] Add type specs and moduledoc

### Step 2: Conventional Commit Parsing
- [x] Implement `parse_conventional_commit/1`
- [x] Handle type extraction (feat, fix, etc.)
- [x] Handle optional scope in parentheses
- [x] Handle breaking change indicator (!)
- [x] Handle multi-word types with hyphens

### Step 3: Heuristic Classification
- [x] Implement `classify_by_keywords/1`
- [x] Implement `classify_by_files/1`
- [x] Define keyword patterns for each type
- [x] Combine heuristics with confidence levels

### Step 4: Scope Extraction
- [x] Implement `extract_scope/2` using git diff-tree
- [x] Track files changed
- [x] Track lines added/deleted
- [x] Extract module names from Elixir files

### Step 5: Main Classification Function
- [x] Implement `classify_commit/2`
- [x] Implement `classify_commits/2` for batch processing
- [x] Add bang variants

### Step 6: Testing
- [x] Add conventional commit parsing tests
- [x] Add keyword heuristic tests
- [x] Add file-based heuristic tests
- [x] Add scope extraction tests
- [x] Add integration tests with real commits
- [x] All 45 tests passing

## Success Criteria

1. All 6 subtasks completed
2. Classification works for conventional commits
3. Heuristic fallback for non-conventional messages
4. Scope extraction captures affected files/modules
5. All tests passing
6. Integrates with existing Commit module

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/extractors/evolution/activity.ex`
- `test/elixir_ontologies/extractors/evolution/activity_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)
