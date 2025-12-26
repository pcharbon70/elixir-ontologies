# Phase 20.3.3: Agent Attribution

## Overview

Model developers, bots, and CI systems as PROV-O agents. This extends the existing Developer module to support PROV-O agent types and attribution relationships.

## Requirements

From phase-20.md task 20.3.3:

- [ ] 20.3.3.1 Create `lib/elixir_ontologies/extractors/evolution/agent.ex`
- [ ] 20.3.3.2 Define `%Agent{type: :developer|:bot|:ci|:llm, identity: ...}` struct
- [ ] 20.3.3.3 Implement `prov:wasAssociatedWith` for activity-agent links
- [ ] 20.3.3.4 Implement `prov:wasAttributedTo` for entity-agent links
- [ ] 20.3.3.5 Detect bot commits (dependabot, renovate, etc.)
- [ ] 20.3.3.6 Add agent attribution tests

## Design

### PROV-O Agent Model

The elixir-evolution.ttl ontology defines:

- `prov:Agent` - Base agent class
- `prov:wasAssociatedWith` - Links activity to agent
- `prov:wasAttributedTo` - Links entity to agent
- `prov:actedOnBehalfOf` - Delegation (deferred to 20.3.4)

### Agent Types

- `:developer` - Human developer
- `:bot` - Automated dependency bots (dependabot, renovate, greenkeeper)
- `:ci` - CI/CD systems (GitHub Actions, GitLab CI)
- `:llm` - LLM-assisted commits (copilot, claude, cursor)

### Struct Design

```elixir
defmodule Agent do
  @type agent_type :: :developer | :bot | :ci | :llm

  @type t :: %__MODULE__{
    agent_id: String.t(),
    agent_type: agent_type(),
    name: String.t() | nil,
    email: String.t(),
    identity: String.t(),  # Canonical identifier
    associated_activities: [String.t()],  # Activity IDs
    attributed_entities: [String.t()],    # Entity version IDs
    first_seen: DateTime.t() | nil,
    last_seen: DateTime.t() | nil,
    metadata: map()
  }
end

defmodule Association do
  @type t :: %__MODULE__{
    activity_id: String.t(),
    agent_id: String.t(),
    role: atom() | nil,  # :author | :committer
    timestamp: DateTime.t() | nil,
    metadata: map()
  }
end

defmodule Attribution do
  @type t :: %__MODULE__{
    entity_id: String.t(),
    agent_id: String.t(),
    role: atom() | nil,
    timestamp: DateTime.t() | nil,
    metadata: map()
  }
end
```

### Agent Identification

Agent IDs follow the pattern: `agent:{sha256(email)[0..11]}`

For example: `agent:a1b2c3d4e5f6`

This provides stable, privacy-preserving IDs while maintaining uniqueness.

### Bot Detection Patterns

Common bot patterns:
- `dependabot[bot]@users.noreply.github.com`
- `renovate[bot]@users.noreply.github.com`
- `greenkeeper[bot]@users.noreply.github.com`
- `*[bot]@*` pattern
- `noreply@github.com` with bot names
- `action@github.com`
- `gitlab-ci@*`

### LLM Detection Patterns

- Commit message patterns: "Co-authored-by: github-copilot"
- Email patterns containing "copilot", "claude", "cursor"
- Trailer detection for AI attribution

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/agent.ex`
- [x] Define Agent struct with type field
- [x] Define Association struct for wasAssociatedWith
- [x] Define Attribution struct for wasAttributedTo
- [x] Add type specs and moduledoc

### Step 2: Agent Type Detection
- [x] Implement `detect_agent_type/1` from email/name
- [x] Add bot detection patterns
- [x] Add CI detection patterns
- [x] Add LLM detection patterns
- [x] Fallback to :developer

### Step 3: Agent Extraction
- [x] Implement `extract_agent/2` from commit
- [x] Generate agent IDs from email
- [x] Build agents from Developer records
- [x] Handle author and committer as separate agents

### Step 4: Activity Association
- [x] Implement `extract_associations/2`
- [x] Link activities to agents (wasAssociatedWith)
- [x] Track author and committer roles
- [x] Build Association structs

### Step 5: Entity Attribution
- [x] Implement `extract_attributions/2`
- [x] Link entities to agents (wasAttributedTo)
- [x] Track file authors via blame
- [x] Build Attribution structs

### Step 6: Testing
- [x] Add agent type detection tests
- [x] Add bot detection tests
- [x] Add CI detection tests
- [x] Add LLM detection tests
- [x] Add association extraction tests
- [x] Add attribution extraction tests
- [x] Add integration tests

## Success Criteria

1. All 6 subtasks completed
2. Can detect developer, bot, CI, and LLM agents
3. Activity-agent associations tracked
4. Entity-agent attributions tracked
5. All tests passing

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/extractors/evolution/agent.ex`
- `test/elixir_ontologies/extractors/evolution/agent_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)
