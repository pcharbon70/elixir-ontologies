# Phase 18.3.2: Closure Builder

## Overview

Implement RDF builder for closure semantics. The builder adds closure-specific triples to anonymous functions that capture variables from their enclosing scope, using the `core:Closure` class and `core:capturesVariable` property.

## Current State

From Phase 18.3.1:
- `AnonymousFunctionBuilder.build/3` generates basic anonymous function triples
- IRI generation via `for_anonymous_function/2` and `for_anonymous_clause/2`
- Generates type, arity, hasClause triples

From Phase 18.2:
- `Closure.analyze_closure/1` detects free variables
- `FreeVariable` struct tracks name, reference_count, locations
- `ScopeAnalysis` tracks variable source scopes

## Problem Statement

When an anonymous function captures variables from its enclosing scope, we need additional RDF triples to represent:
1. That it's a Closure (not just an AnonymousFunction)
2. Which variables it captures
3. Optionally, where those variables come from

## Ontology Classes & Properties

From `elixir-core.ttl`:
- `core:Closure` - Subclass of FnBlock, represents closures
- `core:capturesVariable` - Links Closure to captured Variable
- `core:Variable` - Class for variable references

From `elixir-structure.ttl`:
- `struct:AnonymousFunction` - Already subclass of core:Closure

Note: `capturedFrom` and `captureBindingLocation` properties don't exist in the ontology. We'll use `capturesVariable` and generate variable IRIs that can be linked to their source context.

## Implementation Approach

### Integration with AnonymousFunctionBuilder

The ClosureBuilder will work as an extension to AnonymousFunctionBuilder:
1. First check if the anonymous function has free variables
2. If yes, add closure-specific triples
3. Generate variable IRIs for each captured variable
4. Link closure to captured variables via `capturesVariable`

### IRI Strategy

For captured variables:
- Pattern: `{anon_iri}/capture/{variable_name}`
- Example: `#MyApp/anon/0/capture/x`

## Implementation Steps

### Step 1: Create closure_builder.ex
- [ ] Create module with moduledoc
- [ ] Import required aliases
- [ ] Define build_closure/3 spec

### Step 2: Implement build_closure/3
- [ ] Accept AnonymousFunction struct and context
- [ ] Call Closure.analyze_closure/1 to detect free variables
- [ ] If has_captures, generate closure triples
- [ ] Return additional triples to add to anonymous function

### Step 3: Implement capture triples
- [ ] Generate variable IRI for each free variable
- [ ] Generate capturesVariable triple for each
- [ ] Optionally generate variable type/name triples

### Step 4: Add IRI generation for captured variables
- [ ] Add for_captured_variable/2 to IRI module

### Step 5: Add comprehensive tests
- [ ] Test closure with single captured variable
- [ ] Test closure with multiple captured variables
- [ ] Test closure with no captures (should return empty)
- [ ] Test capture variable IRI generation

## Success Criteria

1. `build_closure/3` returns additional closure triples
2. `capturesVariable` triples generated for each free variable
3. Variable IRIs are unique and stable
4. Tests verify all triple generation
5. All tests pass

## Files to Create/Modify

- `lib/elixir_ontologies/builders/closure_builder.ex` - New builder
- `lib/elixir_ontologies/iri.ex` - Add for_captured_variable/2
- `test/elixir_ontologies/builders/closure_builder_test.exs` - New tests
- `notes/planning/extractors/phase-18.md` - Mark complete

## Example Output

For `fn -> x + y end` where x and y are free variables:

```turtle
<#MyApp/anon/0> a struct:AnonymousFunction, core:Closure ;
    core:capturesVariable <#MyApp/anon/0/capture/x> ;
    core:capturesVariable <#MyApp/anon/0/capture/y> .

<#MyApp/anon/0/capture/x> a core:Variable ;
    core:variableName "x" .

<#MyApp/anon/0/capture/y> a core:Variable ;
    core:variableName "y" .
```
