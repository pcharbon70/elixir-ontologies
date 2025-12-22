# Phase 17.4.3: Exit Builder Implementation

## Problem Statement

The ExceptionBuilder is missing `build_exit/3` function to generate RDF triples for exit expressions. The extractor already supports `ExitExpression` struct, but:

1. `ExitExpression` class is not defined in the ontology (`elixir-core.ttl`)
2. `build_exit/3` function is not implemented in ExceptionBuilder
3. Orchestrator has a comment noting exits are extracted but not built to RDF

This creates an incomplete exception handling pipeline where exit expressions are extracted but never converted to RDF.

## Solution Overview

1. Add `ExitExpression` class to `elixir-core.ttl` ontology
2. Implement `build_exit/3` in ExceptionBuilder following the pattern of `build_raise/3` and `build_throw/3`
3. Add `build_exits/3` helper to Orchestrator
4. Add tests for the new functionality

## Implementation Plan

### Step 1: Add ExitExpression to Ontology
- [ ] Add `:ExitExpression` class to `priv/ontologies/elixir-core.ttl`
- [ ] Place it alongside ThrowExpression as a subclass of ControlFlowExpression

### Step 2: Implement build_exit/3 in ExceptionBuilder
- [ ] Add import for `ExitExpression` struct
- [ ] Implement `build_exit/3` function
- [ ] Implement `exit_iri/3` helper function
- [ ] Add docstrings with examples

### Step 3: Update Orchestrator
- [ ] Implement `build_exits/3` helper function
- [ ] Call `build_exits/3` from `build_exceptions/3`
- [ ] Remove TODO comments about missing `build_exit`

### Step 4: Add Tests
- [ ] Add unit tests for `build_exit/3` in exception_builder_test.exs
- [ ] Add unit test for `exit_iri/3`
- [ ] Add integration test in phase17_integration_test.exs

### Step 5: Quality Checks
- [ ] `mix compile --warnings-as-errors`
- [ ] `mix credo --strict`
- [ ] `mix test`

## Files to Modify

1. `priv/ontologies/elixir-core.ttl` - Add ExitExpression class
2. `lib/elixir_ontologies/builders/exception_builder.ex` - Add build_exit/3
3. `lib/elixir_ontologies/builders/orchestrator.ex` - Add build_exits/3
4. `test/elixir_ontologies/builders/exception_builder_test.exs` - Add tests
5. `test/elixir_ontologies/phase17_integration_test.exs` - Add integration test

## Success Criteria

- ExitExpression class defined in ontology
- `build_exit/3` generates valid RDF triples with:
  - `rdf:type core:ExitExpression`
  - `core:startLine` for location
- Orchestrator builds exit expressions to RDF
- All tests pass
- Quality checks pass

## Current Status

- [x] Step 1: Add ExitExpression to Ontology
- [x] Step 2: Implement build_exit/3
- [x] Step 3: Update Orchestrator
- [x] Step 4: Add Tests
- [x] Step 5: Quality Checks
