# Phase 20.4.4: Version Builder

## Overview

Generate RDF triples for code version relationships. This builder transforms `EntityVersion` extractor results (ModuleVersion, FunctionVersion) into RDF triples following the elixir-evolution.ttl ontology.

## Requirements

From phase-20.md task 20.4.4:

- [ ] 20.4.4.1 Create `lib/elixir_ontologies/builders/evolution/version_builder.ex`
- [ ] 20.4.4.2 Implement `build_version/3` generating version IRI
- [ ] 20.4.4.3 Generate `rdf:type evolution:CodeVersion` and subclass triple
- [ ] 20.4.4.4 Generate `prov:wasDerivedFrom` linking versions
- [ ] 20.4.4.5 Generate `evolution:versionedEntity` linking to code element
- [ ] 20.4.4.6 Add version builder tests

## Design

### Source Structs

From `ElixirOntologies.Extractors.Evolution.EntityVersion`:

**ModuleVersion:**
```elixir
%ModuleVersion{
  module_name: "MyApp.UserController",
  version_id: "MyApp.UserController@abc123d",
  commit_sha: "abc123...",
  short_sha: "abc123d",
  previous_version: "MyApp.UserController@def456e" | nil,
  file_path: "lib/my_app/user_controller.ex",
  content_hash: "sha256:...",
  functions: ["create/1", "update/2"],
  line_count: 150,
  timestamp: DateTime.t() | nil,
  metadata: %{}
}
```

**FunctionVersion:**
```elixir
%FunctionVersion{
  module_name: "MyApp.UserController",
  function_name: :create,
  arity: 1,
  version_id: "MyApp.UserController.create/1@abc123d",
  commit_sha: "abc123...",
  short_sha: "abc123d",
  previous_version: "MyApp.UserController.create/1@def456e" | nil,
  content_hash: "sha256:...",
  line_range: {10, 25},
  clause_count: 2,
  timestamp: DateTime.t() | nil,
  metadata: %{}
}
```

### Evolution Ontology Classes

- `evolution:CodeVersion` - Base class for all versioned code
- `evolution:ModuleVersion` - Subclass for module versions
- `evolution:FunctionVersion` - Subclass for function versions
- `evolution:TypeVersion` - Subclass for type specification versions

### RDF Properties

From the ontology:
- `evolution:versionString` - Version identifier string
- `evolution:wasRevisionOf` - Links to previous version (subproperty of prov:wasRevisionOf)
- `evolution:hasPreviousVersion` - Functional property linking to previous version
- `prov:wasGeneratedBy` - Links version to generating activity
- `prov:wasAttributedTo` - Links version to agent

### RDF Triples Generated

For a module version:

```turtle
version:MyApp.UserController@abc123d a evo:ModuleVersion, prov:Entity ;
    evo:versionString "MyApp.UserController@abc123d" ;
    evo:hasPreviousVersion version:MyApp.UserController@def456e ;
    prov:wasGeneratedBy activity:abc123d .
```

For a function version:

```turtle
version:MyApp.UserController.create%2F1@abc123d a evo:FunctionVersion, prov:Entity ;
    evo:versionString "MyApp.UserController.create/1@abc123d" ;
    evo:hasPreviousVersion version:MyApp.UserController.create%2F1@def456e .
```

## Implementation Plan

### Step 1: Create Module Structure
- [ ] Create `lib/elixir_ontologies/builders/evolution/version_builder.ex`
- [ ] Add module doc and type specs
- [ ] Import necessary modules (Context, Helpers, PROV, Evolution)

### Step 2: Implement build/2 for ModuleVersion
- [ ] Generate version IRI from version_id
- [ ] Build type triples (prov:Entity + ModuleVersion)
- [ ] Build version string triple
- [ ] Build previous version triple (hasPreviousVersion)
- [ ] Build timestamp triple (if present)
- [ ] Return {version_iri, triples}

### Step 3: Implement build/2 for FunctionVersion
- [ ] Generate version IRI from version_id (with URL encoding)
- [ ] Build type triples (prov:Entity + FunctionVersion)
- [ ] Build version string triple
- [ ] Build previous version triple (hasPreviousVersion)
- [ ] Return {version_iri, triples}

### Step 4: Add Helper Functions
- [ ] `version_type_to_class/1` - Map version type to ontology class
- [ ] `build_type_triples/2` - Generate rdf:type triples
- [ ] `build_version_string_triple/2` - Generate versionString triple
- [ ] `build_previous_version_triple/3` - Generate hasPreviousVersion triple
- [ ] `build_timestamp_triple/2` - Generate timestamp if present

### Step 5: Testing (30 tests)
- [x] Test basic module version building
- [x] Test basic function version building
- [x] Test version string generation
- [x] Test previous version linking
- [x] Test nil previous version handling
- [x] Test IRI stability and URL encoding
- [x] Test build_all and build_all_triples
- [x] Test edge cases (special characters, unicode, high arity)
- [x] Test integration with real version extraction

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/builders/evolution/version_builder.ex`
- `test/elixir_ontologies/builders/evolution/version_builder_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)

## Success Criteria

1. All 6 subtasks completed
2. `build/2` generates proper RDF triples for both ModuleVersion and FunctionVersion
3. Version types correctly mapped to ontology classes
4. PROV-O relationships properly generated
5. All tests passing
