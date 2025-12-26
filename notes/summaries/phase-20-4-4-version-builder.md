# Phase 20.4.4 Summary: Version Builder

## Overview

Implemented RDF triple generation for code version relationships. This is the fourth and final builder in the Evolution Builder section (Section 20.4), transforming `EntityVersion` extractor results (ModuleVersion, FunctionVersion) into RDF triples following the elixir-evolution.ttl ontology.

## Implementation

### New Module: `VersionBuilder`

Created `lib/elixir_ontologies/builders/evolution/version_builder.ex` with:

**Public Functions:**
- `build/2` - Build RDF triples for a single version (ModuleVersion or FunctionVersion)
- `build_all/2` - Build triples for multiple versions, returns list of `{iri, triples}`
- `build_all_triples/2` - Build and flatten all triples from multiple versions
- `version_type_to_class/1` - Map version type atom to ontology class IRI

**RDF Triples Generated:**

For each version:
- `rdf:type` → `prov:Entity` (base type)
- `rdf:type` → Version subclass based on type (see mapping below)
- `evolution:versionString` → Version identifier string
- `evolution:hasPreviousVersion` → Link to previous version (if exists)
- `prov:generatedAtTime` → Timestamp (if present)

**Version Type Mapping:**

| Struct | Ontology Class |
|--------|----------------|
| `ModuleVersion` | `evolution:ModuleVersion` |
| `FunctionVersion` | `evolution:FunctionVersion` |
| `:type` | `evolution:TypeVersion` |
| unknown | `evolution:CodeVersion` |

**IRI Generation:**
- Version IRI: `{base_iri}version/{url_encoded_version_id}`
- URL encoding ensures special characters (@ / etc.) are properly escaped

## Design Decisions

1. **URL Encoding**: Version IDs contain `@` and `/` characters (e.g., `MyApp.User@abc123d`, `MyApp.User.create/1@abc123d`). These are URL-encoded in IRIs to ensure valid URIs.

2. **Previous Version Linking**: Uses `evolution:hasPreviousVersion` (a functional property and subproperty of `evolution:wasRevisionOf`) to link version chains.

3. **Timestamp**: Uses `prov:generatedAtTime` when a timestamp is available, following PROV-O semantics for entity generation time.

4. **Polymorphic Build**: The `build/2` function pattern matches on both `ModuleVersion` and `FunctionVersion` structs, generating appropriate type triples for each.

## Test Coverage

30 tests covering:
- Basic module version building
- Basic function version building
- Version string generation
- Previous version linking (hasPreviousVersion)
- Nil previous version handling
- IRI stability and URL encoding
- Batch operations (build_all, build_all_triples)
- Edge cases (minimal structs, all fields, special characters, unicode, high arity)
- Integration with real version extraction

## Files Created/Modified

### New Files
- `lib/elixir_ontologies/builders/evolution/version_builder.ex`
- `test/elixir_ontologies/builders/evolution/version_builder_test.exs`
- `notes/features/phase-20-4-4-version-builder.md`
- `notes/summaries/phase-20-4-4-version-builder.md`

### Modified Files
- `notes/planning/extractors/phase-20.md` (marked task complete)

## Section 20.4 Complete

With this task, **Section 20.4 Evolution Builder** is now complete:

| Task | Description | Tests |
|------|-------------|-------|
| 20.4.1 | Commit Builder | 31 tests |
| 20.4.2 | Activity Builder | 44 tests |
| 20.4.3 | Agent Builder | 32 tests |
| 20.4.4 | Version Builder | 30 tests |

Total: 137 tests for Evolution Builders.

## Next Task

The next section in Phase 20 is **20.5 Codebase Snapshot and Release Tracking**:
- 20.5.1 Snapshot Extraction
- 20.5.2 Release Extraction
- 20.5.3 Snapshot and Release Builder
