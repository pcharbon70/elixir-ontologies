# Phase 19.4.1: Child Spec Builder - Summary

## Overview

Implemented `build_child_spec/4` and `build_child_specs/3` functions in SupervisorBuilder to generate RDF triples for child specifications extracted from supervisors.

## Changes Made

### IRI Module Enhancement

Added `for_child_spec/3` function to generate unique IRIs for child specs:
- Pattern: `{supervisor_iri}/child/{child_id}/{index}`
- Handles atom and arbitrary term IDs
- Uses index for uniqueness when same child ID appears multiple times

### SupervisorBuilder Functions

| Function | Description |
|----------|-------------|
| `build_child_spec/4` | Builds RDF triples for a single child spec |
| `build_child_specs/3` | Builds triples for multiple child specs with indexing |

### RDF Triples Generated

For each child spec, the builder generates:

| Triple | Description |
|--------|-------------|
| `{child_spec_iri, rdf:type, otp:ChildSpec}` | Type assertion |
| `{supervisor_iri, otp:hasChildSpec, child_spec_iri}` | Links supervisor to child |
| `{child_spec_iri, otp:childId, "id_string"}` | Child identifier |
| `{child_spec_iri, otp:startModule, "module_string"}` | Start module name |
| `{child_spec_iri, otp:startFunction, "function_string"}` | Start function name |
| `{child_spec_iri, otp:hasRestartStrategy, otp:Permanent/Temporary/Transient}` | Restart strategy |
| `{child_spec_iri, otp:hasChildType, otp:WorkerType/SupervisorType}` | Child type |

### Ontology Mapping

Restart strategies map to predefined individuals:
- `:permanent` → `otp:Permanent`
- `:temporary` → `otp:Temporary`
- `:transient` → `otp:Transient`

Child types map to predefined individuals:
- `:worker` → `otp:WorkerType`
- `:supervisor` → `otp:SupervisorType`

### Files Modified

1. `lib/elixir_ontologies/iri.ex`
   - Added `for_child_spec/3`
   - Added `format_child_id/1` helper

2. `lib/elixir_ontologies/builders/otp/supervisor_builder.ex`
   - Added `build_child_spec/4`
   - Added `build_child_specs/3`
   - Added helper functions for triple generation

3. `test/elixir_ontologies/builders/otp/supervisor_builder_test.exs`
   - Added 16 new tests for child spec builder

4. `notes/features/phase-19-4-1-child-spec-builder.md`
   - Planning document

5. `notes/planning/extractors/phase-19.md`
   - Updated task status to complete

## Test Results

- All 35 SupervisorBuilder tests pass (4 doctests, 31 tests)
- All 138 IRI tests pass (4 doctests, 134 tests)
- Code compiles without warnings

## Usage Example

```elixir
alias ElixirOntologies.Builders.OTP.SupervisorBuilder
alias ElixirOntologies.Builders.Context
alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec

child_spec = %ChildSpec{
  id: :worker1,
  module: MyWorker,
  restart: :permanent,
  type: :worker,
  start: %{module: MyWorker, function: :start_link, args: []}
}

supervisor_iri = RDF.iri("https://example.org/code#MySupervisor")
context = Context.new(base_iri: "https://example.org/code#")

{child_spec_iri, triples} = SupervisorBuilder.build_child_spec(
  child_spec, supervisor_iri, context, 0
)

# child_spec_iri => ~I<https://example.org/code#MySupervisor/child/worker1/0>
# triples contains type, id, start function, restart strategy, and child type triples
```

## Next Steps

The next logical task is **Phase 19.4.2: Strategy Builder** which will generate RDF triples for supervision strategies (one_for_one, one_for_all, rest_for_one).
