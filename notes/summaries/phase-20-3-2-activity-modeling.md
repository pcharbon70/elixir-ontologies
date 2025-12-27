# Phase 20.3.2 Summary: Activity Modeling

## Overview

Implemented PROV-O Activity modeling for development activities. This module represents commits and development activities using the W3C PROV-O ontology pattern, tracking temporal bounds, entity usage/generation, and activity communication chains.

## Implementation

### New Module: `ActivityModel`

Created `lib/elixir_ontologies/extractors/evolution/activity_model.ex` with:

**Structs:**
- `ActivityModel` - Core PROV-O Activity representation with:
  - `activity_id` - Unique identifier (`activity:{short_sha}`)
  - `activity_type` - Classification (`:feature`, `:bugfix`, `:refactor`, `:docs`, `:test`, `:chore`, `:merge`, `:commit`)
  - `commit_sha` / `short_sha` - Git commit references
  - `started_at` / `ended_at` - Temporal bounds (from author/commit dates)
  - `used_entities` - Entity IDs consumed by activity (previous file versions)
  - `generated_entities` - Entity IDs produced by activity (new file versions)
  - `invalidated_entities` - Entity IDs invalidated by activity
  - `informed_by` / `informs` - Activity chain relationships
  - `associated_agents` - Agent IDs (authors/committers)

- `Usage` - Tracks `prov:used` relationships:
  - `activity_id`, `entity_id`, `role`, `timestamp`, `metadata`

- `Generation` - Tracks `prov:wasGeneratedBy` relationships:
  - `entity_id`, `activity_id`, `timestamp`, `metadata`

- `Communication` - Tracks `prov:wasInformedBy` relationships:
  - `informed_activity`, `informing_activity`, `metadata`

**Key Functions:**
- `extract_activity/3` - Extract activity model from commit
- `extract_activity!/3` - Bang version
- `extract_activities/3` - Batch extraction with optional `link_informs`
- `extract_usages/2` / `extract_usages!/2` - Extract entity usages
- `extract_generations/2` / `extract_generations!/2` - Extract entity generations
- `extract_communications/2` - Extract activity communications
- `build_activity_id/1` / `parse_activity_id/1` - Activity ID utilities
- `generated?/2`, `used?/2`, `informed_by?/2` - Query functions
- `duration/1` - Calculate activity duration in seconds

### Activity Type Detection

Activity types are determined using the existing `Activity.classify_commit/3` function which:
1. Parses conventional commit prefixes (feat:, fix:, etc.)
2. Uses keyword detection
3. Applies file-based heuristics

### Entity Usage and Generation

For each commit:
- **Used entities**: Previous versions of modified/deleted files (from parent commit)
- **Generated entities**: New versions of added/modified files (at current commit)

Entity IDs follow the pattern: `{path}@{short_sha}`

### Activity Communication

`wasInformedBy` relationships are established based on:
- Parent commit relationships (each parent becomes an informing activity)
- The activity chain reflects Git's commit graph

## Test Coverage

43 tests covering:
- Struct creation and default values
- Activity ID building and parsing
- Activity extraction from commits
- Temporal information tracking
- Entity usage and generation extraction
- Communication extraction
- Query functions (generated?, used?, informed_by?, duration)
- Activity type detection (feature, bugfix, refactor, docs, merge)
- Edge cases (initial commit, merge commits)
- Full workflow integration

## PROV-O Alignment

The implementation aligns with W3C PROV-O:
- `prov:Activity` → `ActivityModel` struct
- `prov:used` → `used_entities` list and `Usage` struct
- `prov:wasGeneratedBy` → `generated_entities` list and `Generation` struct
- `prov:wasInformedBy` → `informed_by` list and `Communication` struct
- `prov:startedAtTime` → `started_at` DateTime
- `prov:endedAtTime` → `ended_at` DateTime
- `prov:wasAssociatedWith` → `associated_agents` list

## Files Created/Modified

- `lib/elixir_ontologies/extractors/evolution/activity_model.ex` (new)
- `test/elixir_ontologies/extractors/evolution/activity_model_test.exs` (new)
- `notes/planning/extractors/phase-20.md` (updated task status)
- `notes/features/phase-20-3-2-activity-modeling.md` (updated step status)

## Next Task

The next task in Phase 20 is **20.3.3 Agent Attribution** - modeling developers, bots, and CI systems as PROV-O agents with `wasAssociatedWith` and `wasAttributedTo` relationships.
