# Phase 17.4.3: Exception Builder

## Overview

This task implements the RDF builder for exception handling structures. The builder transforms extracted try/rescue/catch/after expressions into RDF triples following the ontology patterns.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.4.3.1 Implement `build_try_expression/3` generating try IRI
- 17.4.3.2 Generate `rdf:type core:TryExpression` triple
- 17.4.3.3 Generate `core:hasRescueClause` for rescue clauses
- 17.4.3.4 Generate `core:hasCatchClause` for catch clauses
- 17.4.3.5 Generate `core:hasAfterClause` for after block
- 17.4.3.6 Add exception builder tests

## Research Findings

### Existing Ontology Classes

From `elixir-core.ttl`:
- `core:TryExpression` - Exception handling with rescue, catch, and after clauses
- `core:RaiseExpression` - Raises an exception
- `core:ThrowExpression` - Throws a value to be caught by a catch clause

### Existing Properties

From `elixir-core.ttl`:
- `core:hasRescueClause` - Links TryExpression to rescue clauses
- `core:hasCatchClause` - Links TryExpression to catch clauses
- `core:hasAfterClause` - Links TryExpression to after block (functional property)
- `core:hasElseClause` - Links to else clauses
- `core:startLine` - Source location

### Extractor Structs

From `lib/elixir_ontologies/extractors/exception.ex`:
```elixir
%Exception{
  body: Macro.t(),
  rescue_clauses: [RescueClause.t()],
  catch_clauses: [CatchClause.t()],
  else_clauses: [ElseClause.t()],
  after_body: Macro.t() | nil,
  has_rescue: boolean(),
  has_catch: boolean(),
  has_else: boolean(),
  has_after: boolean(),
  location: SourceLocation.t() | nil,
  metadata: map()
}

%RescueClause{exceptions: [...], variable: ..., body: ..., is_catch_all: boolean()}
%CatchClause{kind: :throw | :exit | :error | nil, pattern: ..., body: ...}
%ElseClause{pattern: ..., guard: ..., body: ...}

%RaiseExpression{exception: ..., message: ..., is_reraise: boolean(), stacktrace: ...}
%ThrowExpression{value: Macro.t()}
%ExitExpression{reason: Macro.t()}
```

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/builders/exception_builder.ex`
- [x] Add module documentation
- [x] Import required namespaces and helpers

### Step 2: Implement Try Expression Builder
- [x] `build_try/3` - Build try expressions
- [x] Generate `rdf:type core:TryExpression`
- [x] Generate `hasRescueClause` boolean when rescue clauses present
- [x] Generate `hasCatchClause` boolean when catch clauses present
- [x] Generate `hasAfterClause` boolean when after block present
- [x] Generate `hasElseClause` boolean when else clauses present

### Step 3: Implement Raise Expression Builder
- [x] `build_raise/3` - Build raise/reraise expressions
- [x] Generate `rdf:type core:RaiseExpression`

### Step 4: Implement Throw Expression Builder
- [x] `build_throw/3` - Build throw expressions
- [x] Generate `rdf:type core:ThrowExpression`

### Step 5: IRI Generation
- [x] `try_iri/3` - IRI for try expressions
- [x] `raise_iri/3` - IRI for raise expressions
- [x] `throw_iri/3` - IRI for throw expressions

### Step 6: Add Tests
- [x] Test try expression building
- [x] Test rescue clause detection
- [x] Test catch clause detection
- [x] Test after block detection
- [x] Test else clause detection
- [x] Test raise expression building
- [x] Test throw expression building
- [x] Test IRI generation
- [x] Test location handling

### Step 7: Quality Checks
- [x] `mix compile --warnings-as-errors`
- [x] `mix credo --strict`
- [x] `mix test`

### Step 8: Complete
- [x] Update phase plan
- [x] Write summary

## Success Criteria

- [x] ExceptionBuilder module created
- [x] Try expressions generate correct type triples
- [x] Rescue/catch/after/else clauses properly indicated
- [x] Raise and throw expressions supported
- [x] All tests pass (30 tests)
- [x] Quality checks pass
