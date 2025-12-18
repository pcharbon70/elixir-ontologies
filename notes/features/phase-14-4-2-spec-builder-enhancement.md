# Phase 14.4.2: Spec Builder Enhancement

## Problem Statement

The current `build_function_spec/3` in TypeSystemBuilder always generates `rdf:type structure:FunctionSpec`. With the addition of `spec_type` field in Phase 14.4.1, we need to generate the correct RDF class based on the spec type:

- `@spec` → `structure:FunctionSpec`
- `@callback` → `structure:CallbackSpec`
- `@macrocallback` → `structure:MacroCallbackSpec`

Additionally, optional callbacks need special handling when marked via `@optional_callbacks`.

## Analysis

### Ontology Support

The `elixir-structure.ttl` ontology provides (lines 186-199):

| Class | Description |
|-------|-------------|
| `FunctionSpec` | Type specification for a function (rdfs:subClassOf ModuleAttribute) |
| `CallbackSpec` | Behaviour callback specification (rdfs:subClassOf ModuleAttribute) |
| `OptionalCallbackSpec` | Optional callback (rdfs:subClassOf CallbackSpec) |
| `MacroCallbackSpec` | Macro callback specification (rdfs:subClassOf CallbackSpec) |

Note: The ontology does NOT define a `definedBy` property linking callbacks to behaviours.

### Current Implementation

`build_function_spec/3` (line 198) calls `build_spec_class_triple/1` which always returns:
```elixir
Helpers.type_triple(spec_iri, Structure.FunctionSpec)
```

### FunctionSpec Struct

After Phase 14.4.1, `FunctionSpec` has:
- `spec_type` - `:spec`, `:callback`, or `:macrocallback`

## Solution

Modify `build_spec_class_triple/1` to accept the `FunctionSpec` struct and generate the appropriate class based on `spec_type`:

```elixir
defp build_spec_class_triple(spec_iri, %FunctionSpec{spec_type: :spec}),
  do: Helpers.type_triple(spec_iri, Structure.FunctionSpec)

defp build_spec_class_triple(spec_iri, %FunctionSpec{spec_type: :callback}),
  do: Helpers.type_triple(spec_iri, Structure.CallbackSpec)

defp build_spec_class_triple(spec_iri, %FunctionSpec{spec_type: :macrocallback}),
  do: Helpers.type_triple(spec_iri, Structure.MacroCallbackSpec)
```

For optional callbacks, we add a new function that can mark a callback as optional:
```elixir
def build_optional_callback_triple(callback_iri),
  do: Helpers.type_triple(callback_iri, Structure.OptionalCallbackSpec)
```

## Implementation Plan

### Step 1: Update build_spec_class_triple
- [x] Accept FunctionSpec struct as second parameter
- [x] Pattern match on spec_type to generate correct class

### Step 2: Update build_function_spec
- [x] Pass func_spec to build_spec_class_triple

### Step 3: Add optional callback marking function
- [x] Add build_optional_callback_triple/1 for marking callbacks as optional

### Step 4: Add tests
- [x] Test @spec generates FunctionSpec class
- [x] Test @callback generates CallbackSpec class
- [x] Test @macrocallback generates MacroCallbackSpec class
- [x] Test optional callback marking

### Step 5: Documentation
- [x] Update phase-14.md
- [x] Create summary document

## Success Criteria

- [x] `@spec` generates `rdf:type structure:FunctionSpec`
- [x] `@callback` generates `rdf:type structure:CallbackSpec`
- [x] `@macrocallback` generates `rdf:type structure:MacroCallbackSpec`
- [x] Optional callbacks can be marked with `OptionalCallbackSpec`
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes

## Notes/Considerations

- The `definedBy` property to link callbacks to behaviours does not exist in the ontology (subtask 14.4.2.5 is N/A)
- Optional callback marking is separate from extraction - requires knowing which callbacks are in `@optional_callbacks` list
- The ontology has `OptionalCallbackSpec` as a subclass of `CallbackSpec`, so both types can be added
