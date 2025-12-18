# Phase 14.3.3: Remote Type Builder

## Problem Statement

Task 14.3.3 was to generate RDF triples for remote type references (like `String.t()`, `Enum.t()`) linking to external modules. The task subtasks referenced ontology elements that do not exist.

## Analysis

### Ontology Review

The `elixir-structure.ttl` ontology defines:
- `TypeExpression` as base class for type expressions
- `BasicType` for basic types like `atom()`, `integer()`
- `ParameterizedType` for types with parameters like `list(integer())`
- `referencesType` property (domain: TypeExpression, range: TypeSpec)

The ontology does **NOT** define:
- `RemoteType` class
- `referencesModule` property

### Existing Implementation

From Phase 14.3.1, `build_remote_type/3` already exists (lines 629-646):

```elixir
defp build_remote_type(%TypeExpression{kind: :remote, module: module, name: name}, _context) do
  node = RDF.BlankNode.new()

  # Use BasicType for now
  type_triple = Helpers.type_triple(node, Structure.BasicType)

  # Format module.type name
  module_str = if module, do: Enum.map_join(module, ".", &Atom.to_string/1), else: ""
  name_str = if name, do: Atom.to_string(name), else: "t"
  full_name = "#{module_str}.#{name_str}"

  name_triple = Helpers.datatype_property(node, Structure.typeName(), full_name, RDF.XSD.String)

  {node, [type_triple, name_triple]}
end
```

### Task Subtask Analysis

| Subtask | Status | Resolution |
|---------|--------|------------|
| 14.3.3.1 Implement `build_remote_type/3` | **Done** | Already exists from 14.3.1 |
| 14.3.3.2 Generate `rdf:type structure:RemoteType` | **N/A** | Class doesn't exist; using `BasicType` |
| 14.3.3.3 Generate `structure:referencesModule` | **N/A** | Property doesn't exist |
| 14.3.3.4 Generate `structure:referencesType` | **Partial** | Property exists but for TypeSpec linking |
| 14.3.3.5 Handle remote types not in scope | **Done** | Uses qualified name string |
| 14.3.3.6 Add remote type builder tests | **Needed** | No dedicated tests exist |

## Solution

Since the ontology doesn't have RemoteType, the current approach using `BasicType` with qualified name is appropriate. The implementation needs:

1. **Add dedicated tests** for remote type building
2. **Verify parameterized remote types** work correctly (e.g., `GenServer.on_start()`)
3. **Document the ontology gap** for future enhancement

### Possible Enhancement (Not Required)

The existing `referencesType` property could be used to link remote type references to their type definitions when they're within the analysis scope. However, this requires:
- Knowing if the referenced type exists in the current analysis
- Having the type definition IRI available

This is beyond the current task scope and would be better addressed in Phase 14.4.

## Implementation Plan

### Step 1: Add remote type builder tests
- [x] Test simple remote type `String.t()`
- [x] Test remote type with parameters (if applicable)
- [x] Test remote type name formatting
- [x] Test remote type with nested modules `MyApp.Users.t()`

### Step 2: Verify existing implementation
- [x] Confirm remote types are routed to `build_remote_type/3`
- [x] Verify output matches expected RDF structure

### Step 3: Documentation
- [x] Update phase-14.md
- [x] Create summary document

## Success Criteria

- [x] Remote type tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
- [x] Documentation updated

## Notes/Considerations

- The ontology may need enhancement in a future phase to properly represent remote types
- Current approach encodes full qualified name which is queryable but loses structure
- If module IRIs become available, `referencesType` could link to actual type definitions
