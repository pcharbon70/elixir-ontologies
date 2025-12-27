# Phase 19.4.1: Child Spec Builder

## Overview

Implement `build_child_spec/3` function in SupervisorBuilder to generate RDF triples for child specifications extracted from supervisors.

## Task Requirements (from phase-19.md)

- [ ] 19.4.1.1 Update `lib/elixir_ontologies/builders/otp/supervisor_builder.ex`
- [ ] 19.4.1.2 Implement `build_child_spec/3` generating child spec IRI
- [ ] 19.4.1.3 Generate `rdf:type otp:ChildSpec` triple
- [ ] 19.4.1.4 Generate `otp:hasChildId` with id value
- [ ] 19.4.1.5 Generate `otp:hasStartFunction` linking to start spec
- [ ] 19.4.1.6 Add child spec builder tests

## Ontology Properties Available (from elixir-otp.ttl)

### Classes
- `otp:ChildSpec` - Child specification class
- `otp:RestartStrategy` - Restart strategy (Permanent, Temporary, Transient)
- `otp:ChildType` - Child type (WorkerType, SupervisorType)
- `otp:ShutdownStrategy` - Shutdown strategy

### Object Properties
- `otp:hasChildSpec` - Links Supervisor to ChildSpec
- `otp:hasRestartStrategy` - Links ChildSpec to restart strategy
- `otp:hasChildType` - Links ChildSpec to child type
- `otp:hasShutdownStrategy` - Links ChildSpec to shutdown strategy

### Data Properties
- `otp:childId` - Child ID string
- `otp:startModule` - Start module name string
- `otp:startFunction` - Start function name string

### Predefined Individuals
- `otp:Permanent`, `otp:Temporary`, `otp:Transient` - Restart strategies
- `otp:WorkerType`, `otp:SupervisorType` - Child types

## Implementation Plan

### Step 1: Add IRI Generation for Child Specs

Add `for_child_spec/3` function to IRI module:
```elixir
def for_child_spec(supervisor_iri, child_id, index)
```

### Step 2: Implement build_child_spec/3

Main function signature:
```elixir
@spec build_child_spec(ChildSpec.t(), RDF.IRI.t(), Context.t(), non_neg_integer()) ::
        {RDF.IRI.t(), [RDF.Triple.t()]}
def build_child_spec(child_spec, supervisor_iri, context, index \\ 0)
```

### Step 3: Generate Core Triples

1. Type triple: `{child_spec_iri, rdf:type, otp:ChildSpec}`
2. Link to supervisor: `{supervisor_iri, otp:hasChildSpec, child_spec_iri}`
3. Child ID: `{child_spec_iri, otp:childId, id_string}`

### Step 4: Generate Start Function Triples

1. Start module: `{child_spec_iri, otp:startModule, module_string}`
2. Start function: `{child_spec_iri, otp:startFunction, function_string}`

### Step 5: Generate Restart Strategy Triples

Map restart type to predefined individual:
- `:permanent` -> `otp:Permanent`
- `:temporary` -> `otp:Temporary`
- `:transient` -> `otp:Transient`

Triple: `{child_spec_iri, otp:hasRestartStrategy, restart_iri}`

### Step 6: Generate Child Type Triples

Map child type to predefined individual:
- `:worker` -> `otp:WorkerType`
- `:supervisor` -> `otp:SupervisorType`

Triple: `{child_spec_iri, otp:hasChildType, type_iri}`

### Step 7: Add Comprehensive Tests

- Test basic child spec building
- Test start function generation
- Test restart strategy mapping
- Test child type mapping
- Test integration with supervisor builder

## Files to Modify

1. `lib/elixir_ontologies/iri.ex`
   - Add `for_child_spec/3`

2. `lib/elixir_ontologies/builders/otp/supervisor_builder.ex`
   - Add `build_child_spec/4`
   - Add helper functions for restart/type mapping

3. `test/elixir_ontologies/builders/otp/supervisor_builder_test.exs`
   - Add child spec builder tests

## Success Criteria

1. All existing tests continue to pass
2. Child spec RDF generation works correctly
3. Restart strategy mapping works
4. Child type mapping works
5. Integration with supervisor builder works
6. Code compiles without warnings

## Progress

- [x] Step 1: Add IRI generation (`for_child_spec/3` in IRI module)
- [x] Step 2: Implement build_child_spec/4 (with index parameter)
- [x] Step 3: Generate core triples (type, hasChildSpec, childId)
- [x] Step 4: Generate start function triples (startModule, startFunction)
- [x] Step 5: Generate restart strategy triples (hasRestartStrategy)
- [x] Step 6: Generate child type triples (hasChildType)
- [x] Step 7: Add comprehensive tests (16 tests)
- [x] Quality checks pass (all tests pass, no warnings)
