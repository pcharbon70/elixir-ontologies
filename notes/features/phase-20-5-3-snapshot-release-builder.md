# Phase 20.5.3: Snapshot and Release Builder

## Overview

Generate RDF triples for codebase snapshots and releases. This completes the evolution layer by providing RDF builders for the Snapshot and Release extractors from 20.5.1 and 20.5.2.

## Requirements

From phase-20.md task 20.5.3:

- [x] 20.5.3.1 Implement `build_snapshot/3` generating snapshot IRI
- [x] 20.5.3.2 Generate `rdf:type evolution:CodebaseSnapshot` triple
- [x] 20.5.3.3 Implement `build_release/3` generating release IRI
- [x] 20.5.3.4 Generate `rdf:type evolution:Release` triple
- [x] 20.5.3.5 Generate `evolution:hasSemanticVersion` with version info
- [x] 20.5.3.6 Add snapshot/release builder tests (39 tests)

## Design

### Snapshot RDF Output

```turtle
snapshot:abc123d a evo:CodebaseSnapshot, prov:Entity ;
    evo:snapshotId "snapshot:abc123d" ;
    evo:commitHash "abc123def456..." ;
    evo:shortHash "abc123d" ;
    evo:projectName "elixir_ontologies" ;
    evo:projectVersion "0.1.0" ;
    evo:moduleCount 42 ;
    evo:functionCount 156 ;
    evo:macroCount 5 ;
    evo:protocolCount 2 ;
    evo:behaviourCount 3 ;
    evo:lineCount 5234 ;
    evo:fileCount 42 ;
    prov:generatedAtTime "2025-01-15T10:30:00Z"^^xsd:dateTime .
```

### Release RDF Output

```turtle
release:v1.2.3 a evo:Release, prov:Entity ;
    evo:releaseId "release:v1.2.3" ;
    evo:releaseVersion "1.2.3" ;
    evo:releaseTag "v1.2.3" ;
    evo:commitHash "abc123def456..." ;
    evo:projectName "elixir_ontologies" ;
    evo:hasPreviousRelease release:v1.2.2 ;
    evo:hasSemanticVersion [
        a evo:SemanticVersion ;
        evo:majorVersion 1 ;
        evo:minorVersion 2 ;
        evo:patchVersion 3
    ] ;
    prov:generatedAtTime "2025-01-15T10:30:00Z"^^xsd:dateTime .
```

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/builders/evolution/snapshot_release_builder.ex`
- [x] Add module doc and type specs
- [x] Import Helpers, Context, Evolution, PROV namespaces

### Step 2: Implement Snapshot Builder
- [x] `build/2` for Snapshot struct
- [x] Generate snapshot IRI
- [x] Generate type triples (CodebaseSnapshot + prov:Entity)
- [x] Generate ID and hash triples
- [x] Generate project info triples
- [x] Generate statistics triples
- [x] Generate timestamp triple

### Step 3: Implement Release Builder
- [x] `build/2` for Release struct
- [x] Generate release IRI
- [x] Generate type triples (Release + prov:Entity)
- [x] Generate ID and version triples
- [x] Generate tag triple
- [x] Generate semantic version blank node
- [x] Generate previous release link
- [x] Generate timestamp triple

### Step 4: Batch Operations
- [x] `build_all/2` for multiple structs
- [x] `build_all_triples/2` for flat triple list

### Step 5: Testing
- [x] Test snapshot build
- [x] Test snapshot statistics triples
- [x] Test release build
- [x] Test semantic version triples
- [x] Test previous release linking
- [x] Test batch operations

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/builders/evolution/snapshot_release_builder.ex`
- `test/elixir_ontologies/builders/evolution/snapshot_release_builder_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)

## Success Criteria

1. All 6 subtasks completed
2. Snapshot and Release structs properly converted to RDF
3. Semantic version information captured as structured data
4. Previous release linking works correctly
5. All tests passing
