# Phase 20.4.1 Summary: Commit Builder

## Overview

Implemented RDF triple generation for Git commits. This is the first builder in the Evolution Builder section (Section 20.4), transforming `Commit` extractor results into RDF triples following the elixir-evolution.ttl ontology.

## Implementation

### New Module: `CommitBuilder`

Created `lib/elixir_ontologies/builders/evolution/commit_builder.ex` with:

**Public Functions:**
- `build/2` - Build RDF triples for a single commit
- `build_all/2` - Build triples for multiple commits, returns list of `{iri, triples}`
- `build_all_triples/2` - Build and flatten all triples from multiple commits

**RDF Triples Generated:**

For each commit:
- `rdf:type` → `evolution:Commit` or `evolution:MergeCommit`
- `evolution:commitHash` → Full 40-char SHA
- `evolution:shortHash` → 7-char abbreviated SHA
- `evolution:commitMessage` → Full commit message (if present)
- `evolution:commitSubject` → First line of message (if present)
- `evolution:commitBody` → Message body after subject (if present)
- `evolution:authoredAt` → Author timestamp (xsd:dateTime)
- `evolution:committedAt` → Commit timestamp (xsd:dateTime)
- `prov:startedAtTime` → PROV-O start time (same as authoredAt)
- `prov:endedAtTime` → PROV-O end time (same as committedAt)
- `evolution:parentCommit` → Link to parent commit(s)

**IRI Generation:**
- Standalone: `{base_iri}commit/{sha}`
- With repo context: `{repo_iri}/commit/{sha}`

### Context Options

The builder accepts a `Context` struct with optional `repo_iri` in metadata to generate repository-scoped commit IRIs.

```elixir
# Standalone commit IRI
context = Context.new(base_iri: "https://example.org/code#")
# => https://example.org/code#commit/abc123...

# Repo-scoped commit IRI
context = Context.new(
  base_iri: "https://example.org/code#",
  metadata: %{repo_iri: RDF.iri("https://example.org/code#repo/xyz")}
)
# => https://example.org/code#repo/xyz/commit/abc123...
```

## Test Coverage

31 tests covering:
- Basic build functionality
- Type triple generation (Commit vs MergeCommit)
- Hash triple generation (commitHash, shortHash)
- Message triple generation (message, subject, body)
- Timestamp triple generation (authoredAt, committedAt, PROV-O times)
- Parent commit relationships
- Context options (repo_iri)
- Batch operations (build_all, build_all_triples)
- Edge cases (minimal commit, special characters, unicode)
- Integration with real repository

## Files Created/Modified

### New Files
- `lib/elixir_ontologies/builders/evolution/commit_builder.ex`
- `test/elixir_ontologies/builders/evolution/commit_builder_test.exs`
- `notes/features/phase-20-4-1-commit-builder.md`
- `notes/summaries/phase-20-4-1-commit-builder.md`

### Modified Files
- `notes/planning/extractors/phase-20.md` (marked task complete)

## Next Task

The next task in Phase 20 is **20.4.2 Activity Builder** - generating RDF triples for development activities using PROV-O Activity class.
