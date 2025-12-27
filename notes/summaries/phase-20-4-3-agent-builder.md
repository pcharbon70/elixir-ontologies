# Phase 20.4.3 Summary: Agent Builder

## Overview

Implemented RDF triple generation for development agents using PROV-O Agent class. This is the third builder in the Evolution Builder section (Section 20.4), transforming `Agent` extractor results into RDF triples following the elixir-evolution.ttl ontology.

## Implementation

### New Module: `AgentBuilder`

Created `lib/elixir_ontologies/builders/evolution/agent_builder.ex` with:

**Public Functions:**
- `build/2` - Build RDF triples for a single agent
- `build_all/2` - Build triples for multiple agents, returns list of `{iri, triples}`
- `build_all_triples/2` - Build and flatten all triples from multiple agents
- `agent_type_to_class/1` - Map agent type atom to ontology class IRI

**RDF Triples Generated:**

For each agent:
- `rdf:type` → `prov:Agent` (base type)
- `rdf:type` → Agent subclass based on type (see mapping below)
- `evolution:developerName` → Name (for Developer agents)
- `evolution:botName` → Name (for Bot, CISystem, LLMAgent)
- `evolution:developerEmail` → Email (for Developer agents only)

**Agent Type Mapping:**

| Agent Type | Ontology Class |
|------------|----------------|
| `:developer` | `evolution:Developer` |
| `:bot` | `evolution:Bot` |
| `:ci` | `evolution:CISystem` |
| `:llm` | `evolution:LLMAgent` |
| unknown | `evolution:DevelopmentAgent` |

**IRI Generation:**
- Agent IRI: `{base_iri}agent/{id}` where id is extracted from agent_id

## Design Decisions

1. **Name Properties**: Developers use `developerName`, while bots and their subclasses (CISystem, LLMAgent) use `botName` as defined in the ontology.

2. **Email Properties**: Only developers have email addresses in the ontology schema, so `developerEmail` is only generated for developer agents.

3. **Timestamp Properties**: The `first_seen` and `last_seen` fields from the Agent struct are not serialized to RDF as the ontology doesn't define temporal properties for agents. Activity timestamps are tracked via PROV-O on activities instead.

4. **Association/Attribution Relationships**: The `prov:wasAssociatedWith` and `prov:wasAttributedTo` relationships are generated from the activity/entity perspective in ActivityBuilder, not from the agent perspective, to avoid duplicate triples.

## Test Coverage

32 tests covering:
- Basic build functionality
- Agent type mapping for all 5 types (developer, bot, ci, llm, unknown)
- Name property generation (developerName vs botName)
- Email property generation (developer only)
- IRI stability (same agent produces same IRI)
- Batch operations (build_all, build_all_triples)
- Edge cases (minimal agent, all fields populated, special characters, unicode)
- Integration with real repository agent extraction

## Files Created/Modified

### New Files
- `lib/elixir_ontologies/builders/evolution/agent_builder.ex`
- `test/elixir_ontologies/builders/evolution/agent_builder_test.exs`
- `notes/features/phase-20-4-3-agent-builder.md`
- `notes/summaries/phase-20-4-3-agent-builder.md`

### Modified Files
- `notes/planning/extractors/phase-20.md` (marked task complete)

## Next Task

The next task in Phase 20 is **20.4.4 Version Builder** - generating RDF triples for code version relationships using `prov:wasDerivedFrom` and `evolution:CodeVersion`.
