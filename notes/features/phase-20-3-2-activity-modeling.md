# Phase 20.3.2: Activity Modeling

## Overview

Model development activities using PROV-O Activity class. This extends the existing Activity module to track temporal relationships, entity usage/generation, and activity chains.

## Requirements

From phase-20.md task 20.3.2:

- [ ] 20.3.2.1 Implement `prov:Activity` for commits and development activities
- [ ] 20.3.2.2 Track `prov:startedAtTime` and `prov:endedAtTime`
- [ ] 20.3.2.3 Implement `prov:used` for entities read by activity
- [ ] 20.3.2.4 Implement `prov:generated` for entities created by activity
- [ ] 20.3.2.5 Implement `prov:wasInformedBy` for activity chains
- [ ] 20.3.2.6 Add activity modeling tests

## Design

### PROV-O Activity Model

The elixir-evolution.ttl ontology defines:

- `evolution:DevelopmentActivity` - subclass of `prov:Activity`
- `evolution:Commit` - subclass of `DevelopmentActivity`
- `prov:used` - entities consumed by activity
- `prov:generated` - entities produced by activity (via `wasGeneratedBy` inverse)
- `prov:wasInformedBy` - activity informed by another activity
- `prov:startedAtTime` / `prov:endedAtTime` - temporal bounds

### Struct Design

```elixir
defmodule ActivityModel do
  @type t :: %__MODULE__{
    activity_id: String.t(),
    activity_type: atom(),
    commit: Commit.t(),
    started_at: DateTime.t(),
    ended_at: DateTime.t(),
    used_entities: [String.t()],       # Entity version IDs
    generated_entities: [String.t()],  # Entity version IDs
    informed_by: [String.t()],         # Activity IDs
    informs: [String.t()],             # Activity IDs
    metadata: map()
  }
end

defmodule Usage do
  @type t :: %__MODULE__{
    activity_id: String.t(),
    entity_id: String.t(),
    role: atom() | nil,
    timestamp: DateTime.t() | nil
  }
end

defmodule Generation do
  @type t :: %__MODULE__{
    entity_id: String.t(),
    activity_id: String.t(),
    timestamp: DateTime.t() | nil
  }
end

defmodule Communication do
  @type t :: %__MODULE__{
    informed_activity: String.t(),
    informing_activity: String.t()
  }
end
```

### Activity Identification

Activity IDs follow the pattern: `activity:{commit_sha[0..6]}`

For example: `activity:abc123d`

### Entity Usage and Generation

For a commit activity:
- **Used entities**: Previous versions of modified files (read before modification)
- **Generated entities**: New versions of modified/added files

### Activity Communication (wasInformedBy)

Activities are linked when:
- A commit builds on changes from a previous commit
- Parent-child commit relationships
- Sequential commits touching the same files

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/activity_model.ex`
- [x] Define ActivityModel struct
- [x] Define Usage struct
- [x] Define Generation struct
- [x] Define Communication struct
- [x] Add type specs and moduledoc

### Step 2: Activity Extraction
- [x] Implement `extract_activity/3` from commit
- [x] Generate activity IDs
- [x] Track started_at and ended_at times (author/commit dates)

### Step 3: Entity Usage Tracking
- [x] Implement `extract_used_entities/3`
- [x] Track entities read by activity (previous versions)
- [x] Build Usage structs

### Step 4: Entity Generation Tracking
- [x] Implement `extract_generated_entities/3`
- [x] Track entities created/modified by activity
- [x] Build Generation structs

### Step 5: Activity Communication
- [x] Implement `extract_communications/3`
- [x] Track wasInformedBy from parent commits
- [x] Track wasInformedBy from file-based relationships

### Step 6: Testing
- [x] Add activity extraction tests
- [x] Add usage tracking tests
- [x] Add generation tracking tests
- [x] Add communication tests
- [x] Add integration tests

## Success Criteria

1. All 6 subtasks completed
2. Can extract PROV-O activity model from commits
3. Entity usage properly tracked
4. Entity generation properly tracked
5. Activity chains linked
6. All tests passing

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/extractors/evolution/activity_model.ex`
- `test/elixir_ontologies/extractors/evolution/activity_model_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)
