# Phase 18.3.3: Capture Builder

## Overview

Implement RDF builder for capture operator expressions (`&`). The builder generates triples for named function captures (`&Module.func/arity`) and shorthand captures (`&(&1 + &2)`).

## Current State

From Phase 18.1.3-18.1.4:
- `Capture` extractor handles all capture types
- `Capture.extract/1` returns capture type, module, function, arity, placeholders
- `PlaceholderAnalysis` tracks shorthand capture arity

## Problem Statement

Need to generate RDF triples for capture operator expressions:
1. Type triple (CapturedFunction or PartialApplication)
2. For named captures: link to referenced function
3. For shorthand captures: derived arity information
4. Source location

## Ontology Classes & Properties

From `elixir-structure.ttl`:
- `struct:CapturedFunction` - For named function captures
- `struct:PartialApplication` - For shorthand captures (subclass of CapturedFunction)

From `elixir-core.ttl`:
- `core:refersToFunction` - Links capture to referenced function
- `core:refersToModule` - Links to module

From `elixir-structure.ttl`:
- `struct:arity` - Derived arity for shorthand captures

Note: `capturesFunction` and `hasExpression` don't exist in the ontology. We'll use `refersToFunction` and the existing arity property.

## Implementation Approach

### Capture Type Mapping

| Capture Type | RDF Class | Properties |
|--------------|-----------|------------|
| `:named_local` | `CapturedFunction` | refersToFunction |
| `:named_remote` | `CapturedFunction` | refersToFunction, refersToModule |
| `:shorthand` | `PartialApplication` | arity |

### IRI Strategy

For captures:
- Pattern: `{context_iri}/capture/{index}`
- Example: `#MyApp/anon/0/capture/0` or `#MyApp/capture/0`

## Implementation Steps

### Step 1: Create capture_builder.ex
- [ ] Create module with moduledoc
- [ ] Import required aliases
- [ ] Define build/3 spec

### Step 2: Implement build/3
- [ ] Accept Capture struct, Context, and index
- [ ] Generate capture IRI
- [ ] Dispatch to type-specific builders

### Step 3: Implement named capture triples
- [ ] Generate CapturedFunction type
- [ ] Generate refersToFunction triple
- [ ] For remote: generate module reference

### Step 4: Implement shorthand capture triples
- [ ] Generate PartialApplication type
- [ ] Generate arity triple

### Step 5: Add IRI generation
- [ ] Add for_capture/2 to IRI module

### Step 6: Add comprehensive tests
- [ ] Test named local capture
- [ ] Test named remote capture
- [ ] Test shorthand capture
- [ ] Test arity generation

## Success Criteria

1. `build/3` returns `{capture_iri, triples}` tuple
2. Named captures link to function via refersToFunction
3. Shorthand captures have PartialApplication type and arity
4. Tests verify all triple generation
5. All tests pass

## Files to Create/Modify

- `lib/elixir_ontologies/builders/capture_builder.ex` - New builder
- `lib/elixir_ontologies/iri.ex` - Add for_capture/2
- `test/elixir_ontologies/builders/capture_builder_test.exs` - New tests
- `notes/planning/extractors/phase-18.md` - Mark complete

## Example Output

For `&String.upcase/1`:

```turtle
<#MyApp/capture/0> a struct:CapturedFunction ;
    core:refersToFunction <#String/upcase/1> ;
    struct:arity 1 .
```

For `&(&1 + 1)`:

```turtle
<#MyApp/capture/0> a struct:PartialApplication ;
    struct:arity 1 .
```
