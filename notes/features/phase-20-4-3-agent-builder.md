# Phase 20.4.3: Agent Builder

## Overview

Generate RDF triples for development agents using PROV-O Agent class. This builder transforms `Agent` extractor results into RDF triples following the elixir-evolution.ttl ontology.

## Requirements

From phase-20.md task 20.4.3:

- [ ] 20.4.3.1 Create `lib/elixir_ontologies/builders/evolution/agent_builder.ex`
- [ ] 20.4.3.2 Implement `build_agent/3` generating agent IRI
- [ ] 20.4.3.3 Generate `rdf:type prov:Agent` and subclass triple
- [ ] 20.4.3.4 Generate `evolution:agentName` and `evolution:agentEmail`
- [ ] 20.4.3.5 Generate `prov:wasAssociatedWith` and `prov:wasAttributedTo`
- [ ] 20.4.3.6 Add agent builder tests

## Design

### Source Struct: Agent

From `ElixirOntologies.Extractors.Evolution.Agent`:

```elixir
%Agent{
  agent_id: "agent:abc123",
  agent_type: :developer | :bot | :ci | :llm,
  name: "Jane Doe",
  email: "jane@example.com",
  identity: "jane@example.com",
  associated_activities: ["activity:abc123d", ...],
  attributed_entities: ["entity:MyApp.User@abc123d", ...],
  first_seen: DateTime.t() | nil,
  last_seen: DateTime.t() | nil,
  metadata: %{}
}
```

### Evolution Ontology Classes

Agent types map to ontology classes:
- `:developer` → `evolution:Developer`
- `:bot` → `evolution:Bot`
- `:ci` → `evolution:CISystem` (subclass of Bot)
- `:llm` → `evolution:LLMAgent` (subclass of Bot)

All are subclasses of `prov:Agent` via `evolution:DevelopmentAgent`.

### RDF Properties

Agent properties from the ontology:
- `evolution:developerName` - Name (for Developer)
- `evolution:developerEmail` - Email (for Developer)
- `evolution:botName` - Name (for Bot)
- `evolution:llmModel` - Model name (for LLMAgent)

### RDF Triples Generated

For an agent:

```turtle
agent:abc123 a evo:Developer, prov:Agent ;
    evo:developerName "Jane Doe" ;
    evo:developerEmail "jane@example.com" ;
    prov:wasAssociatedWith activity:xyz789 ;
    prov:wasAttributedTo entity:MyApp.User@abc123d .
```

Note: The `prov:wasAssociatedWith` and `prov:wasAttributedTo` relationships are expressed from the activity/entity perspectives in the ActivityBuilder. Here we can optionally generate them from the agent perspective as well for querying convenience.

## Implementation Plan

### Step 1: Create Module Structure
- [ ] Create `lib/elixir_ontologies/builders/evolution/agent_builder.ex`
- [ ] Add module doc and type specs
- [ ] Import necessary modules (Context, Helpers, PROV, Evolution)

### Step 2: Implement build/2
- [ ] Generate agent IRI from agent_id
- [ ] Build type triples (prov:Agent + subclass)
- [ ] Build name property triple (developerName or botName)
- [ ] Build email property triple (developerEmail)
- [ ] Build timestamp triples (first_seen, last_seen)
- [ ] Return {agent_iri, triples}

### Step 3: Add Helper Functions
- [ ] `agent_type_to_class/1` - Map agent type to ontology class
- [ ] `build_type_triples/2` - Generate rdf:type triples
- [ ] `build_name_triple/2` - Generate name property based on type
- [ ] `build_email_triple/2` - Generate email property (if Developer)
- [ ] `build_timestamp_triples/2` - Generate first_seen/last_seen

### Step 4: Add Association Builders (Optional)
- [ ] `build_association_triples/3` - Generate prov:wasAssociatedWith from agent
- [ ] `build_attribution_triples/3` - Generate prov:wasAttributedTo from agent

### Step 5: Testing (32 tests)
- [x] Test basic agent building
- [x] Test type mapping for all agent types (developer, bot, ci, llm)
- [x] Test name property generation (developerName vs botName)
- [x] Test email property generation
- [x] Test IRI stability
- [x] Test build_all and build_all_triples
- [x] Test edge cases (minimal agent, all fields, special characters, unicode)
- [x] Test integration with real commit extraction

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/builders/evolution/agent_builder.ex`
- `test/elixir_ontologies/builders/evolution/agent_builder_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)

## Success Criteria

1. All 6 subtasks completed
2. `build/2` generates proper RDF triples
3. Agent types correctly mapped to ontology classes
4. PROV-O relationships properly generated
5. All tests passing
