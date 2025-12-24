# Phase 18.3.1: Anonymous Function Builder

## Overview

Implement RDF builder for anonymous function definitions extracted by `AnonymousFunction` extractor. The builder generates triples following the elixir-structure ontology for `AnonymousFunction` class.

## Current State

From Phase 18.1.1-18.1.2:
- `AnonymousFunction` extractor extracts `fn -> end` syntax
- `AnonymousFunction.Clause` struct captures parameters, guard, body, order
- Struct fields: `clauses`, `arity`, `location`, `metadata`

## Problem Statement

Need to generate RDF triples for anonymous functions including:
1. Type triple (rdf:type struct:AnonymousFunction)
2. Arity property (struct:arity)
3. Clause references (struct:hasClause)
4. Source location (core:hasSourceLocation)

## Ontology Classes & Properties

From `elixir-structure.ttl`:
- `:AnonymousFunction` - subclass of `core:Closure`
- `:arity` - xsd:nonNegativeInteger
- `:hasClause` - links to FunctionClause (or anonymous function clause)
- `:hasClauses` - links to rdf:List of clauses

From `elixir-core.ttl`:
- `:hasSourceLocation` - links to source location

## Implementation Approach

### IRI Generation

Anonymous functions don't have names, so we need a context-based IRI strategy:
- Use containing function context + index if available
- Use file + line number as fallback
- Pattern: `{base}anon/{context}/L{line}` or `{function_iri}/anon/{index}`

### Builder Functions

1. `build/2` - Main entry point (like FunctionBuilder)
2. `build_anonymous_function/3` - Core triple generation
3. `build_clause_triples/3` - Generate triples for each clause

## Implementation Steps

### Step 1: Create anonymous_function_builder.ex
- [ ] Create module with moduledoc
- [ ] Import required aliases (Helpers, Context, IRI, NS)
- [ ] Define @spec for build/2

### Step 2: Implement IRI generation
- [ ] Add `generate_anonymous_iri/2` helper
- [ ] Handle context from metadata (containing function, line number)
- [ ] Ensure unique, stable IRIs

### Step 3: Implement build/2
- [ ] Generate anonymous function IRI
- [ ] Build type triple (AnonymousFunction)
- [ ] Build arity triple
- [ ] Build clause triples
- [ ] Build location triple (if available)

### Step 4: Implement clause building
- [ ] Generate clause IRIs (anon_iri/clause/N)
- [ ] Build clause type triples (FunctionClause)
- [ ] Build clause order triples
- [ ] Build parameter triples (optional)

### Step 5: Add comprehensive tests
- [ ] Test basic anonymous function building
- [ ] Test multi-clause anonymous function
- [ ] Test arity extraction
- [ ] Test clause ordering
- [ ] Test location linking

## Success Criteria

1. `build/2` returns `{anonymous_iri, triples}` tuple
2. Generated triples include type, arity, clauses
3. Clause order preserved via clause IRI numbering
4. Tests verify all triple generation
5. All tests pass

## Files to Create/Modify

- `lib/elixir_ontologies/builders/anonymous_function_builder.ex` - New builder
- `test/elixir_ontologies/builders/anonymous_function_builder_test.exs` - New tests
- `notes/planning/extractors/phase-18.md` - Mark complete

## Example Output

For `fn x -> x + 1 end`:

```turtle
<#anon/file/lib/example.ex/L10> a struct:AnonymousFunction ;
    struct:arity 1 ;
    struct:hasClause <#anon/file/lib/example.ex/L10/clause/0> .

<#anon/file/lib/example.ex/L10/clause/0> a struct:FunctionClause ;
    struct:clauseOrder 1 .
```
