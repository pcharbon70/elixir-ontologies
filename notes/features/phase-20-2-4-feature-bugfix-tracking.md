# Phase 20.2.4: Feature and Bug Fix Tracking

## Overview

Track feature additions and bug fixes as distinct activities. This module parses commit messages to identify features and bug fixes, extracts issue references, and tracks the scope of changes.

## Requirements

From phase-20.md task 20.2.4:

- [x] 20.2.4.1 Define `%FeatureAddition{name: ..., commit: ..., modules: [...]}` struct
- [x] 20.2.4.2 Define `%BugFix{description: ..., commit: ..., affected_functions: [...]}` struct
- [x] 20.2.4.3 Parse issue references from commit messages (#123, GH-456)
- [x] 20.2.4.4 Link activities to external issue trackers
- [x] 20.2.4.5 Track scope of changes per activity
- [x] 20.2.4.6 Add feature/bug fix tracking tests (40 tests)

## Design

### Issue Reference Patterns

Common patterns for issue references in commit messages:

| Pattern | Example | Tracker |
|---------|---------|---------|
| `#N` | `#123` | GitHub/GitLab default |
| `GH-N` | `GH-456` | GitHub |
| `GL-N` | `GL-789` | GitLab |
| `JIRA-N` | `PROJ-123` | Jira |
| `fixes #N` | `fixes #42` | GitHub closing keyword |
| `closes #N` | `closes #99` | GitHub closing keyword |
| `resolves #N` | `resolves #10` | GitHub closing keyword |

### Struct Design

```elixir
defmodule FeatureAddition do
  @type t :: %__MODULE__{
    name: String.t(),
    description: String.t() | nil,
    commit: Commit.t(),
    modules: [String.t()],
    functions: [{atom(), non_neg_integer()}],
    issue_refs: [IssueReference.t()],
    scope: Scope.t(),
    metadata: map()
  }
end

defmodule BugFix do
  @type t :: %__MODULE__{
    description: String.t(),
    commit: Commit.t(),
    affected_modules: [String.t()],
    affected_functions: [{atom(), non_neg_integer()}],
    issue_refs: [IssueReference.t()],
    scope: Scope.t(),
    metadata: map()
  }
end

defmodule IssueReference do
  @type tracker :: :github | :gitlab | :jira | :generic
  @type action :: :mentions | :fixes | :closes | :resolves | :relates

  @type t :: %__MODULE__{
    tracker: tracker(),
    number: pos_integer() | String.t(),
    project: String.t() | nil,
    action: action(),
    url: String.t() | nil
  }
end

defmodule Scope do
  @type t :: %__MODULE__{
    files_changed: [String.t()],
    modules_affected: [String.t()],
    functions_affected: [{atom(), non_neg_integer()}],
    lines_added: non_neg_integer(),
    lines_deleted: non_neg_integer()
  }
end
```

### Integration with Activity Module

This module builds on the existing Activity module:
- Activity classification identifies features and bug fixes
- This module provides detailed tracking for those activity types
- Reuses Scope struct from Activity module

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/feature_tracking.ex`
- [x] Define IssueReference struct
- [x] Define FeatureAddition struct
- [x] Define BugFix struct
- [x] Add type specs and moduledoc

### Step 2: Issue Reference Parsing
- [x] Implement `parse_issue_references/1`
- [x] Handle #N pattern
- [x] Handle GH-N and GL-N patterns
- [x] Handle JIRA-style patterns (PROJ-N)
- [x] Handle closing keywords (fixes, closes, resolves)

### Step 3: Issue Tracker Linking
- [x] Implement `build_issue_url/2`
- [x] Support GitHub URL generation
- [x] Support GitLab URL generation
- [x] Support configurable base URLs

### Step 4: Feature Detection
- [x] Implement `detect_features/2`
- [x] Extract feature name from commit message
- [x] Track affected modules from diff
- [x] Build FeatureAddition struct

### Step 5: Bug Fix Detection
- [x] Implement `detect_bugfixes/2`
- [x] Extract bug description from commit message
- [x] Track affected functions from diff
- [x] Build BugFix struct

### Step 6: Scope Tracking
- [x] Reuse Activity.extract_scope/2
- [x] Add function-level tracking
- [x] Calculate impact metrics

### Step 7: Testing
- [x] Add issue reference parsing tests
- [x] Add feature detection tests
- [x] Add bug fix detection tests
- [x] Add scope tracking tests
- [x] Add integration tests

## Success Criteria

1. All 6 subtasks completed
2. Issue reference parsing works for all patterns
3. Feature detection works
4. Bug fix detection works
5. Scope tracking works
6. All tests passing

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/extractors/evolution/feature_tracking.ex`
- `test/elixir_ontologies/extractors/evolution/feature_tracking_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)
