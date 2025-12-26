# Phase 20.4.1: Commit Builder

## Overview

Generate RDF triples for Git commits and their metadata. This is the first builder in the Evolution Builder section, transforming `Commit` extractor results into RDF triples following the elixir-evolution.ttl ontology.

## Requirements

From phase-20.md task 20.4.1:

- [x] 20.4.1.1 Create `lib/elixir_ontologies/builders/evolution/commit_builder.ex`
- [x] 20.4.1.2 Implement `build_commit/3` generating commit IRI
- [x] 20.4.1.3 Generate `rdf:type evolution:Commit` triple
- [x] 20.4.1.4 Generate `evolution:commitHash` with SHA
- [x] 20.4.1.5 Generate `evolution:commitMessage` with message
- [x] 20.4.1.6 Add commit builder tests (31 tests)

## Design

### Module Structure

Following existing builder patterns (e.g., `ModuleBuilder`):

```elixir
defmodule ElixirOntologies.Builders.Evolution.CommitBuilder do
  @moduledoc """
  Builds RDF triples for Git commits.
  """

  @spec build(Commit.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(commit, context) do
    # Generate commit IRI
    # Build all triples
    # Return {commit_iri, triples}
  end
end
```

### IRI Generation

The `IRI` module already has `for_commit/2`:
```elixir
IRI.for_commit(repo_iri, commit.sha)
# => ~I<https://example.org/code#repo/a1b2c3d4/commit/abc123def456>
```

We need to also support generating a commit IRI without requiring a repo IRI:
```elixir
IRI.for_standalone_commit(base_iri, commit.sha)
# => ~I<https://example.org/code#commit/abc123def456>
```

### Evolution Ontology Properties

From elixir-evolution.ttl:

**Classes:**
- `evolution:Commit` - A version control commit
- `evolution:MergeCommit` - A commit merging branches (subclass of Commit)

**Data Properties:**
- `evolution:commitHash` (xsd:string) - Full 40-char SHA
- `evolution:shortHash` (xsd:string) - 7-char abbreviated SHA
- `evolution:commitMessage` (xsd:string) - Full commit message
- `evolution:commitSubject` (xsd:string) - First line of message
- `evolution:commitBody` (xsd:string) - Body after first line
- `evolution:authoredAt` (xsd:dateTime) - Author timestamp
- `evolution:committedAt` (xsd:dateTime) - Commit timestamp

**Object Properties:**
- `evolution:parentCommit` - Link to parent commits
- `evolution:inRepository` - Link to repository
- `prov:wasAssociatedWith` - Link to agents (author/committer)

### RDF Triples Generated

For a typical commit:

```turtle
commit:abc123 a evo:Commit ;
    evo:commitHash "abc123def456789..." ;
    evo:shortHash "abc123d" ;
    evo:commitMessage "Fix bug in user authentication" ;
    evo:commitSubject "Fix bug in user authentication" ;
    evo:authoredAt "2025-01-15T10:30:00Z"^^xsd:dateTime ;
    evo:committedAt "2025-01-15T10:30:00Z"^^xsd:dateTime ;
    evo:parentCommit commit:def456 ;
    prov:wasAssociatedWith agent:author-hash .
```

For a merge commit:

```turtle
commit:abc123 a evo:MergeCommit ;
    evo:commitHash "abc123..." ;
    evo:parentCommit commit:parent1 ;
    evo:parentCommit commit:parent2 .
```

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/builders/evolution/commit_builder.ex`
- [x] Add module doc and type specs
- [x] Import necessary modules (Helpers, Context, NS, IRI)

### Step 2: Implement build/2
- [x] Generate commit IRI using IRI.for_standalone_commit or similar
- [x] Build type triple (Commit or MergeCommit)
- [x] Build hash triples (commitHash, shortHash)
- [x] Build message triples (commitMessage, commitSubject, commitBody)
- [x] Build timestamp triples (authoredAt, committedAt)
- [x] Build parent commit relationships
- [x] Return {commit_iri, triples}

### Step 3: Add Helper Functions
- [x] `build_type_triple/2` - Commit vs MergeCommit
- [x] `build_hash_triples/2` - commitHash, shortHash
- [x] `build_message_triples/2` - message, subject, body
- [x] `build_timestamp_triples/2` - authoredAt, committedAt
- [x] `build_parent_triples/3` - parentCommit relationships

### Step 4: Testing
- [x] Test basic commit building
- [x] Test merge commit (uses MergeCommit type)
- [x] Test all data properties populated
- [x] Test parent commit relationships
- [x] Test nil field handling
- [x] Test IRI stability (same commit = same IRI)

## Files to Create/Modify

### New Files
- `lib/elixir_ontologies/builders/evolution/commit_builder.ex`
- `test/elixir_ontologies/builders/evolution/commit_builder_test.exs`

### Modified Files
- `notes/planning/extractors/phase-20.md` (mark task complete)

## Success Criteria

1. All 6 subtasks completed
2. `build/2` generates proper RDF triples
3. Type correctly set to Commit or MergeCommit
4. All commit properties serialized
5. Parent relationships properly linked
6. All tests passing
