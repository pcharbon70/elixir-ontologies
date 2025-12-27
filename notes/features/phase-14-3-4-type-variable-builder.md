# Phase 14.3.4: Type Variable Builder

## Problem Statement

Task 14.3.4 was to generate RDF triples for type variables and their constraints. The task subtasks referenced ontology properties that do not exist.

## Analysis

### Ontology Review

The `elixir-structure.ttl` ontology defines:
- `TypeVariable` class (line 241): "A type variable used in polymorphic type definitions."
- `WhenClauseType` class (line 246): "A type constraint in a when clause of a spec."
- `hasTypeVariable` property (line 601): Links TypeSpec to TypeVariable

The ontology does **NOT** define:
- `variableName` property (task 14.3.4.3)
- `hasConstraint` property (task 14.3.4.4)

### Existing Implementation

From Phase 14.3.1, `build_variable_type/3` already exists (lines 669-682):

```elixir
defp build_variable_type(%TypeExpression{kind: :variable, name: name}, _context) do
  node = RDF.BlankNode.new()

  type_triple = Helpers.type_triple(node, Structure.TypeVariable)
  name_str = if name, do: Atom.to_string(name), else: "var"
  # Using typeName for variable name since variableName doesn't exist in ontology
  name_triple = Helpers.datatype_property(node, Structure.typeName(), name_str, RDF.XSD.String)

  {node, [type_triple, name_triple]}
end
```

### Existing Test

One test exists in `type_system_builder_test.exs` (line 756):
- Tests simple type variable `t` generates TypeVariable class and typeName

### Task Subtask Analysis

| Subtask | Status | Resolution |
|---------|--------|------------|
| 14.3.4.1 Implement `build_type_variable/3` | **Done** | `build_variable_type/3` exists from 14.3.1 |
| 14.3.4.2 Generate `rdf:type structure:TypeVariable` | **Done** | Line 676 |
| 14.3.4.3 Generate `structure:variableName` | **N/A** | Property doesn't exist; using `typeName` |
| 14.3.4.4 Generate `structure:hasConstraint` triples | **N/A** | Property doesn't exist |
| 14.3.4.5 Link constraints to type expressions | **N/A** | No constraint property available |
| 14.3.4.6 Add type variable builder tests | **Needed** | Only 1 test exists |

## Solution

Since the ontology doesn't have constraint properties, the current approach is sufficient. The implementation needs:

1. **Add more tests** for type variable building
2. **Document the ontology gap** for constraint handling

### Constraint Handling Note

Type variable constraints (from `when` clauses like `@spec foo(a) :: a when a: integer()`) are parsed by the TypeExpression extractor but cannot be represented in RDF without ontology enhancement. The `WhenClauseType` class exists but has no linking property.

## Implementation Plan

### Step 1: Add type variable builder tests
- [x] Test type variable with different names
- [x] Test type variable in union type
- [x] Test type variable in function type (as parameter/return)
- [x] Test multiple type variables

### Step 2: Verify existing implementation
- [x] Confirm variable types are routed correctly
- [x] Verify output matches expected RDF structure

### Step 3: Documentation
- [x] Update phase-14.md
- [x] Create summary document

## Success Criteria

- [x] Type variable tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
- [x] Documentation updated

## Notes/Considerations

- Constraint handling requires ontology enhancement (future phase)
- Current implementation captures variable name via `typeName` property
- `WhenClauseType` class exists but cannot be linked to variables
