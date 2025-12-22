# Phase 17: Receive and Comprehension Builders

## Problem Statement

The ControlFlowBuilder is missing `build_receive/3` and `build_comprehension/3` functions. The extractors already support `ReceiveExpression` and `Comprehension` structs, but:

1. `build_receive/3` is not implemented in ControlFlowBuilder
2. `build_comprehension/3` is not implemented in ControlFlowBuilder
3. Orchestrator has a comment noting receives and comprehensions are extracted but not built to RDF

This creates an incomplete control flow pipeline where receive and comprehension expressions are extracted but never converted to RDF.

## Solution Overview

1. Implement `build_receive/3` in ControlFlowBuilder following existing patterns
2. Implement `build_comprehension/3` in ControlFlowBuilder
3. Add helper functions for `receive_iri/3` and `comprehension_iri/3`
4. Update Orchestrator to call the new builders
5. Add comprehensive tests

## Existing Classes in Ontology

From `elixir-core.ttl`:
- `:ReceiveExpression` - with `hasAfterTimeout` property
- `:ForComprehension` - with `hasGenerator`, `hasFilter`, `hasIntoOption` properties

## Implementation Plan

### Step 1: Add build_receive/3 to ControlFlowBuilder
- [ ] Add alias for ReceiveExpression
- [ ] Implement `build_receive/3` function
- [ ] Implement `receive_iri/3` helper function
- [ ] Add triples for:
  - `rdf:type core:ReceiveExpression`
  - `core:hasClause` (if clauses present)
  - `core:hasAfterTimeout` (if after block present)
  - `core:startLine` (if location available)

### Step 2: Add build_comprehension/3 to ControlFlowBuilder
- [ ] Add alias for Comprehension
- [ ] Implement `build_comprehension/3` function
- [ ] Implement `comprehension_iri/3` helper function
- [ ] Add triples for:
  - `rdf:type core:ForComprehension`
  - `core:hasGenerator` (if generators present)
  - `core:hasFilter` (if filters present)
  - `core:hasIntoOption` (if into option present)
  - `core:hasReduceOption` (if reduce option present)
  - `core:startLine` (if location available)

### Step 3: Update Orchestrator
- [ ] Add `build_receives/3` helper function
- [ ] Add `build_comprehensions/3` helper function
- [ ] Update `build_control_flow/3` to call the new builders
- [ ] Remove TODO comment about missing builders

### Step 4: Add Tests
- [ ] Add unit tests for `build_receive/3` in control_flow_builder_test.exs
- [ ] Add unit tests for `build_comprehension/3`
- [ ] Add unit tests for IRI generation functions
- [ ] Add integration tests

### Step 5: Quality Checks
- [ ] `mix compile --warnings-as-errors`
- [ ] `mix credo --strict`
- [ ] `mix test`

## Files to Modify

1. `lib/elixir_ontologies/builders/control_flow_builder.ex` - Add build_receive/3, build_comprehension/3
2. `lib/elixir_ontologies/builders/orchestrator.ex` - Add build_receives/3, build_comprehensions/3
3. `test/elixir_ontologies/builders/control_flow_builder_test.exs` - Add tests

## Success Criteria

- `build_receive/3` generates valid RDF triples for receive expressions
- `build_comprehension/3` generates valid RDF triples for comprehensions
- Orchestrator builds receive and comprehension expressions to RDF
- All tests pass
- Quality checks pass

## Current Status

- [x] Step 1: Add build_receive/3
- [x] Step 2: Add build_comprehension/3
- [x] Step 3: Update Orchestrator
- [x] Step 4: Add Tests
- [x] Step 5: Quality Checks

## Implementation Notes

### Ontology Updates

Added the following properties to `priv/ontologies/elixir-core.ttl`:
- `hasIntoOption` - Boolean property for comprehension into option
- `hasReduceOption` - Boolean property for comprehension reduce option
- `hasUniqOption` - Boolean property for comprehension uniq option
- `hasAfterTimeout` - Boolean property for receive after timeout block

### Files Modified

1. `priv/ontologies/elixir-core.ttl` - Added 4 new datatype properties
2. `lib/elixir_ontologies/builders/control_flow_builder.ex` - Added build_receive/3, build_comprehension/3, and helper functions
3. `lib/elixir_ontologies/builders/orchestrator.ex` - Added build_receives/3, build_comprehensions/3 and updated build_control_flow/3
4. `test/elixir_ontologies/builders/control_flow_builder_test.exs` - Added 19 new tests for receive and comprehension builders
