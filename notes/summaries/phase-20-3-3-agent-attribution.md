# Phase 20.3.3 Summary: Agent Attribution

## Overview

Implemented PROV-O Agent modeling for developers, bots, CI systems, and LLM tools. This module represents all participants in development activities using the W3C PROV-O ontology pattern, with automatic agent type detection and attribution tracking.

## Implementation

### New Module: `Agent`

Created `lib/elixir_ontologies/extractors/evolution/agent.ex` with:

**Structs:**
- `Agent` - Core PROV-O Agent representation with:
  - `agent_id` - Unique identifier (`agent:{sha256(email)[0..11]}`)
  - `agent_type` - Classification (`:developer`, `:bot`, `:ci`, `:llm`)
  - `name` / `email` - Identity information
  - `associated_activities` - Activity IDs (wasAssociatedWith)
  - `attributed_entities` - Entity IDs (wasAttributedTo)
  - `first_seen` / `last_seen` - Temporal bounds

- `Association` - Tracks `prov:wasAssociatedWith` relationships:
  - `activity_id`, `agent_id`, `role`, `timestamp`, `metadata`

- `Attribution` - Tracks `prov:wasAttributedTo` relationships:
  - `entity_id`, `agent_id`, `role`, `timestamp`, `metadata`

**Agent Type Detection:**

Detects agent types from email patterns:
- `:bot` - dependabot, renovate, greenkeeper, snyk-bot, semantic-release-bot, mergify, etc.
- `:ci` - GitHub Actions, GitLab CI, Jenkins, Travis, CircleCI, Azure Pipelines
- `:llm` - Copilot, Cursor, Codeium, Tabnine (also via commit message patterns)
- `:developer` - Default for human developers

**Key Functions:**
- `detect_type/1` - Detect agent type from email
- `detect_type_with_context/2` - Detect with commit message (for LLM co-author detection)
- `extract_agents/3` - Extract agents from commit
- `extract_agents_from_commits/3` - Batch extraction with aggregation
- `extract_associations/3` - Extract wasAssociatedWith relationships
- `extract_attributions/3` - Extract wasAttributedTo relationships
- `from_developer/1` - Convert Developer to Agent
- `bot?/1`, `ci?/1`, `llm?/1`, `developer?/1` - Type predicates
- `automated?/1` - Check if agent is non-human

### Bot Detection Patterns

Comprehensive regex patterns for common bots:
- `dependabot[bot]@users.noreply.github.com`
- `renovate[bot]@users.noreply.github.com`
- `*[bot]@*` generic pattern
- Various CI system patterns

### LLM Detection

Two detection methods:
1. Email patterns: copilot, cursor, codeium, tabnine
2. Commit message patterns: "Co-authored-by: github-copilot", "AI-assisted", etc.

## Test Coverage

70 tests covering:
- Struct creation and default values
- Agent ID building and parsing
- Agent type detection (developer, bot, CI, LLM)
- LLM detection from commit messages
- Agent extraction from commits
- Association extraction (wasAssociatedWith)
- Attribution extraction (wasAttributedTo)
- Type predicates and query functions
- Developer conversion
- Edge cases (missing emails)
- Integration tests

## PROV-O Alignment

The implementation aligns with W3C PROV-O:
- `prov:Agent` → `Agent` struct
- `prov:wasAssociatedWith` → `Association` struct and `associated_activities`
- `prov:wasAttributedTo` → `Attribution` struct and `attributed_entities`
- Agent types map to ontology subclasses

## Files Created/Modified

- `lib/elixir_ontologies/extractors/evolution/agent.ex` (new)
- `test/elixir_ontologies/extractors/evolution/agent_test.exs` (new)
- `notes/planning/extractors/phase-20.md` (updated task status)
- `notes/features/phase-20-3-3-agent-attribution.md` (updated step status)

## Next Task

The next task in Phase 20 is **20.3.4 Delegation and Responsibility** - modeling delegation relationships between agents (team leads, code owners) with `actedOnBehalfOf` relationships and CODEOWNERS file parsing.
