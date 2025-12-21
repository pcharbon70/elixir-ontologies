# Phase 17.4.1: Function Call Builder - Summary

## Task Completed

Implemented the CallGraphBuilder module for generating RDF triples from function call extraction results. This builder transforms `FunctionCall` structs into RDF representation following the ontology patterns.

## Implementation

### New Module

Created `lib/elixir_ontologies/builders/call_graph_builder.ex` with:

**Public API**
- `build/3` - Build RDF triples for a single function call
- `build_all/3` - Build triples for multiple calls with sequential indices
- `call_iri/3` - Generate unique IRI for a function call

**IRI Pattern**
```
{base}call/{caller_function}/{index}
```
Example: `https://example.org/code#call/MyApp/process/1/0`

### RDF Triples Generated

For each function call, the builder generates:

1. **Type triple** - `rdf:type` with:
   - `core:LocalCall` for local function calls
   - `core:RemoteCall` for remote (Module.function) calls
   - `core:LocalCall` for dynamic calls (fallback)

2. **Function name** - `structure:functionName` with the called function name

3. **Arity** - `structure:arity` with the call arity

4. **Module name** (remote calls only) - `structure:moduleName` with target module

5. **Caller link** - `structure:belongsTo` linking call to containing function

6. **Target link** (when resolvable) - `structure:callsFunction` linking to target function IRI

7. **Location** (when present) - `core:startLine` with source line number

### Design Decisions

- Used existing ontology classes (`core:LocalCall`, `core:RemoteCall`) instead of creating new `FunctionCall` class
- Reused `structure:functionName`, `structure:arity`, `structure:moduleName` properties for call metadata
- Used `structure:belongsTo` to link calls to containing functions
- Used `structure:callsFunction` for target function linking
- Call IRIs include index to ensure uniqueness for multiple calls within same function

### Files Created

- `lib/elixir_ontologies/builders/call_graph_builder.ex` - Builder module (~310 lines)
- `test/elixir_ontologies/builders/call_graph_builder_test.exs` - Test suite (23 tests)

### Test Coverage

23 tests covering:
- IRI generation (3 tests)
- Local call building (5 tests)
- Remote call building (5 tests)
- Dynamic call building (2 tests)
- Location handling (2 tests)
- Bulk building (3 tests)
- Edge cases (3 tests)

## Verification

```
mix compile --warnings-as-errors  # Passes
mix credo --strict                # Passes (only pre-existing suggestions)
mix test                          # 23 tests, 0 failures
```

## Next Task

**17.4.2 Control Flow Builder** - Generate RDF triples for control flow structures (if/unless/cond, case/with expressions).
