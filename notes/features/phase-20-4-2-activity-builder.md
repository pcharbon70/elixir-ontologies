# Phase 20.4.2: Activity Builder

## Overview

Generate RDF triples for development activities using PROV-O Activity class. This builder transforms `ActivityModel` extractor results into RDF triples following the elixir-evolution.ttl ontology.

## Requirements

From phase-20.md task 20.4.2:

- [ ] 20.4.2.1 Create `lib/elixir_ontologies/builders/evolution/activity_builder.ex`
- [ ] 20.4.2.2 Implement `build_activity/3` generating activity IRI
- [ ] 20.4.2.3 Generate `rdf:type prov:Activity` and subclass triple
- [ ] 20.4.2.4 Generate `prov:startedAtTime` and `prov:endedAtTime`
- [ ] 20.4.2.5 Generate `prov:used` and `prov:generated` relationships
- [ ] 20.4.2.6 Add activity builder tests

## Design

### Source Struct: ActivityModel

From `ElixirOntologies.Extractors.Evolution.ActivityModel.ActivityModel`:

```elixir
%ActivityModel{
  activity_id: "activity:abc123d",
  activity_type: :feature | :bugfix | :refactor | :docs | :test | :chore | :unknown,
  commit_sha: "abc123...",
  short_sha: "abc123d",
  started_at: DateTime.t() | nil,
  ended_at: DateTime.t() | nil,
  used_entities: ["MyApp.User@def456e", ...],
  generated_entities: ["MyApp.User@abc123d", ...],
  invalidated_entities: [...],
  informed_by: ["activity:def456e", ...],
  informs: [...],
  associated_agents: ["agent:xyz123", ...],
  metadata: %{}
}
```

### Evolution Ontology Classes

Activity types map to ontology classes:
- `:feature` → `evolution:FeatureAddition`
- `:bugfix` → `evolution:BugFix`
- `:refactor` → `evolution:Refactoring`
- `:docs` → `evolution:DevelopmentActivity`
- `:test` → `evolution:DevelopmentActivity`
- `:chore` → `evolution:DevelopmentActivity`
- `:unknown` → `evolution:DevelopmentActivity`

All are subclasses of `prov:Activity`.

### RDF Triples Generated

For an activity:

```turtle
activity:abc123d a evo:FeatureAddition, prov:Activity ;
    prov:startedAtTime "2025-01-15T10:30:00Z"^^xsd:dateTime ;
    prov:endedAtTime "2025-01-15T10:35:00Z"^^xsd:dateTime ;
    prov:used <entity:MyApp.User@def456e> ;
    prov:generated <entity:MyApp.User@abc123d> ;
    prov:wasInformedBy activity:def456e ;
    prov:wasAssociatedWith agent:xyz123 .
```

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/builders/evolution/activity_builder.ex`
- [x] Add module doc and type specs
- [x] Import necessary modules

### Step 2: Implement build/2
- [x] Generate activity IRI from activity_id
- [x] Build type triples (prov:Activity + subclass)
- [x] Build timestamp triples (startedAtTime, endedAtTime)
- [x] Build usage triples (prov:used)
- [x] Build generation triples (prov:generated)
- [x] Build communication triples (prov:wasInformedBy)
- [x] Build agent association triples (prov:wasAssociatedWith)
- [x] Return {activity_iri, triples}

### Step 3: Add Helper Functions
- [x] `activity_type_to_class/1` - Map activity type to ontology class
- [x] `build_type_triples/2` - Generate rdf:type triples
- [x] `build_timestamp_triples/2` - Generate prov:startedAtTime/endedAtTime
- [x] `build_usage_triples/3` - Generate prov:used relationships
- [x] `build_generation_triples/3` - Generate prov:generated relationships
- [x] `build_communication_triples/3` - Generate prov:wasInformedBy
- [x] `build_agent_triples/3` - Generate prov:wasAssociatedWith

### Step 4: Testing (44 tests)
- [x] Test basic activity building
- [x] Test type mapping for all activity types
- [x] Test timestamp generation
- [x] Test used/generated relationships
- [x] Test communication relationships
- [x] Test agent associations
- [x] Test empty lists handling
- [x] Test IRI stability
- [x] Test build_all and build_all_triples
- [x] Test edge cases (minimal activity, all fields)
- [x] Test integration with real commit extraction

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/builders/evolution/activity_builder.ex`
- `test/elixir_ontologies/builders/evolution/activity_builder_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)

## Success Criteria

1. All 6 subtasks completed
2. `build/2` generates proper RDF triples
3. Activity types correctly mapped to ontology classes
4. PROV-O relationships properly generated
5. All tests passing
