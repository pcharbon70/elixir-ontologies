# Phase 17.4.1: Function Call Builder

## Overview

This task implements the RDF builder for function calls. The builder transforms `FunctionCall` extraction results into RDF triples following the ontology patterns established by existing builders.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.4.1.1 Create `lib/elixir_ontologies/builders/call_graph_builder.ex`
- 17.4.1.2 Implement `build_function_call/3` generating call IRI
- 17.4.1.3 Generate `rdf:type core:FunctionCall` triple
- 17.4.1.4 Generate `core:callsFunction` linking to target function
- 17.4.1.5 Generate `core:calledFrom` linking to calling function
- 17.4.1.6 Add function call builder tests

## Research Findings

### Existing Ontology Classes

From `elixir-core.ttl`:
- `core:LocalCall` - A function call within the current module scope
- `core:RemoteCall` - A function call with explicit module: Module.function(args)

From `elixir-structure.ttl`:
- `structure:callsFunction` - Object property linking functions to called functions
- `structure:callsMacro` - Object property for macro calls

### FunctionCall Extractor Structure

From `lib/elixir_ontologies/extractors/call.ex`:
```elixir
%FunctionCall{
  type: :local | :remote | :dynamic,
  name: atom(),
  arity: non_neg_integer(),
  module: [atom()] | atom() | nil,
  arguments: [Macro.t()],
  location: SourceLocation.t() | nil,
  metadata: map()
}
```

### Builder Pattern (from FunctionBuilder)

```elixir
def build(function_info, context) do
  {function_iri, triples} = ...
end
```
- Takes extraction result and Context
- Returns tuple of `{iri, triples}`
- Uses Helpers module for triple generation

## Design Decisions

1. **Call IRI Format**: `{base}#call/{caller_function_iri_fragment}/{index}`
   - Unique per call site within a function
   - Index ensures multiple calls to same target are distinct

2. **RDF Type Based on Call Type**:
   - `:local` → `core:LocalCall`
   - `:remote` → `core:RemoteCall`
   - `:dynamic` → Need to add `core:DynamicCall` class or use generic

3. **Properties to Generate**:
   - `rdf:type` - Call type class
   - `core:callsFunction` or `structure:callsFunction` - Target function IRI
   - `core:calledFromFunction` - Calling function IRI (new property needed or use inverse)
   - `core:callArity` - Arity of the call
   - `core:callModule` - Target module for remote calls
   - `core:callName` - Function name being called
   - `core:hasLocation` - Source location

4. **Note**: The phase plan mentions `core:FunctionCall` but the ontology has `core:LocalCall` and `core:RemoteCall`. We'll use the existing classes.

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/builders/call_graph_builder.ex`
- [x] Add module documentation
- [x] Import required namespaces and helpers

### Step 2: Implement IRI Generation
- [x] `call_iri/3` - Generate unique IRI for a function call
- [x] Format: `{base}#call/{caller_function}/{call_index}`

### Step 3: Implement build/3
- [x] Accept FunctionCall struct and Context
- [x] Generate type triple based on call type (:local/:remote/:dynamic)
- [x] Generate callsFunction triple with target function IRI
- [x] Generate call metadata (name, arity, module)
- [x] Generate location triple if present

### Step 4: Implement build_all/3
- [x] Bulk builder for multiple calls
- [x] Track call indices for unique IRIs

### Step 5: Add Tests
- [x] Test local call building
- [x] Test remote call building
- [x] Test dynamic call building
- [x] Test IRI generation
- [x] Test multiple calls with indexing
- [x] Test location handling

### Step 6: Quality Checks
- [x] `mix compile --warnings-as-errors`
- [x] `mix credo --strict`
- [x] `mix test`

### Step 7: Complete
- [x] Update phase plan
- [x] Write summary

## Success Criteria

- [x] CallGraphBuilder module created
- [x] build/3 generates correct triples
- [x] Local/remote/dynamic calls use appropriate classes
- [x] Target function IRI correctly linked
- [x] Call metadata captured in triples
- [x] All tests pass
- [x] Quality checks pass
