# Phase 20.3.4: Delegation and Responsibility

## Overview

Model delegation relationships between agents (team leads, code owners). This implements PROV-O's `actedOnBehalfOf` relationship to track responsibility chains in development activities.

## Requirements

From phase-20.md task 20.3.4:

- [ ] 20.3.4.1 Define `%Delegation{delegator: ..., delegate: ..., activity: ...}` struct
- [ ] 20.3.4.2 Implement `prov:actedOnBehalfOf` relationships
- [ ] 20.3.4.3 Track code ownership from CODEOWNERS file
- [ ] 20.3.4.4 Model team membership if available
- [ ] 20.3.4.5 Track review approval chains
- [ ] 20.3.4.6 Add delegation tests

## Design

### PROV-O Delegation Model

The W3C PROV-O defines:

- `prov:actedOnBehalfOf` - Agent acted on behalf of another agent
- `prov:Delegation` - A ternary relationship with activity context

### Delegation Scenarios

1. **Code Ownership**: Contributors act on behalf of code owners
2. **Team Membership**: Team members act on behalf of team leads
3. **Review Approval**: Approvers grant authority to merge
4. **Bot Delegation**: Bots act on behalf of their configuring user/org

### Struct Design

```elixir
defmodule Delegation do
  @type t :: %__MODULE__{
    delegation_id: String.t(),
    delegate: String.t(),      # Agent ID doing the work
    delegator: String.t(),     # Agent ID on whose behalf
    activity: String.t() | nil,  # Activity context (optional)
    reason: atom() | nil,      # :code_ownership | :team_membership | :review_approval | :bot_config
    scope: [String.t()],       # File patterns (for code ownership)
    metadata: map()
  }
end

defmodule CodeOwner do
  @type t :: %__MODULE__{
    pattern: String.t(),       # File pattern (e.g., "lib/**/*.ex")
    owners: [String.t()],      # Agent IDs or team names
    source: String.t(),        # "CODEOWNERS" file path
    line_number: integer()
  }
end

defmodule Team do
  @type t :: %__MODULE__{
    team_id: String.t(),
    name: String.t(),
    members: [String.t()],     # Agent IDs
    leads: [String.t()],       # Agent IDs of team leads
    metadata: map()
  }
end

defmodule ReviewApproval do
  @type t :: %__MODULE__{
    approval_id: String.t(),
    reviewer: String.t(),      # Agent ID
    activity: String.t(),      # Activity (PR/commit) being approved
    approved_at: DateTime.t(),
    metadata: map()
  }
end
```

### CODEOWNERS Parsing

GitHub/GitLab CODEOWNERS format:
```
# Comment
*.ex @elixir-team
lib/core/** @alice @bob
docs/ @docs-team
```

Patterns:
- `*` matches any file
- `**` matches directories recursively
- `@username` for individual users
- `@org/team-name` for teams

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/extractors/evolution/delegation.ex`
- [x] Define Delegation struct
- [x] Define CodeOwner struct
- [x] Define Team struct
- [x] Define ReviewApproval struct
- [x] Add type specs and moduledoc

### Step 2: CODEOWNERS Parsing
- [x] Implement `parse_codeowners/1` from file content
- [x] Handle comment lines
- [x] Parse file patterns
- [x] Parse owner lists (users and teams)
- [x] Build CodeOwner structs

### Step 3: Code Ownership Lookup
- [x] Implement `find_owners/2` for a file path
- [x] Match patterns against paths
- [x] Return matching owners with priority (last match wins)
- [x] Build delegation relationships

### Step 4: actedOnBehalfOf Implementation
- [x] Implement `extract_delegations/2` from commit
- [x] Link committer to code owners
- [x] Link bot to configuring organization
- [x] Build Delegation structs

### Step 5: Team Membership (Optional)
- [x] Implement `parse_team_file/1` if team file exists
- [x] Build Team structs
- [x] Link team members to leads

### Step 6: Review Approvals
- [x] Implement `extract_review_approvals/2` from commit trailers
- [x] Parse "Reviewed-by:" and "Approved-by:" trailers
- [x] Build ReviewApproval structs

### Step 7: Testing
- [x] Add CODEOWNERS parsing tests
- [x] Add pattern matching tests
- [x] Add delegation extraction tests
- [x] Add review approval tests
- [x] Add integration tests

## Success Criteria

1. All 6 subtasks completed
2. CODEOWNERS file properly parsed
3. Code ownership delegations tracked
4. Review approvals extracted
5. All tests passing

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/extractors/evolution/delegation.ex`
- `test/elixir_ontologies/extractors/evolution/delegation_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)
