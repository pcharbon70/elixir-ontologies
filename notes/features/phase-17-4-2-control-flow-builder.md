# Phase 17.4.2: Control Flow Builder

## Overview

This task implements the RDF builder for control flow structures. The builder transforms extracted conditional and case/with expressions into RDF triples following the ontology patterns.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:
- 17.4.2.1 Implement `build_conditional/3` for if/unless/cond
- 17.4.2.2 Generate `rdf:type core:ConditionalExpression` triple
- 17.4.2.3 Generate `core:hasCondition` linking to condition expression
- 17.4.2.4 Generate `core:hasBranch` for each branch
- 17.4.2.5 Implement `build_case_expression/3` for case/with
- 17.4.2.6 Add control flow builder tests

## Research Findings

### Existing Ontology Classes

From `elixir-core.ttl`:
- `core:IfExpression` - Conditional branching with if/else
- `core:UnlessExpression` - Negated conditional
- `core:CondExpression` - Multi-branch conditional
- `core:CaseExpression` - Pattern matching control flow
- `core:WithExpression` - Monadic binding for sequential pattern matching

### Existing Properties

From `elixir-core.ttl`:
- `core:hasCondition` - Links to condition expression
- `core:hasThenBranch` - Links to then branch
- `core:hasElseBranch` - Links to else branch
- `core:hasClause` - Links to clauses

### Extractor Structs

From `lib/elixir_ontologies/extractors/conditional.ex`:
```elixir
%Conditional{
  type: :if | :unless | :cond,
  condition: Macro.t() | nil,
  branches: [Branch.t()],  # for if/unless
  clauses: [CondClause.t()],  # for cond
  location: SourceLocation.t() | nil,
  metadata: map()
}

%Branch{type: :then | :else, body: Macro.t(), location: ...}
%CondClause{index: integer(), condition: ..., body: ..., is_catch_all: boolean()}
```

From `lib/elixir_ontologies/extractors/case_with.ex`:
```elixir
%CaseExpression{
  subject: Macro.t(),
  clauses: [CaseClause.t()],
  location: SourceLocation.t() | nil,
  metadata: map()
}

%CaseClause{index: integer(), pattern: ..., guard: ..., body: ..., has_guard: boolean()}

%WithExpression{
  clauses: [WithClause.t()],
  body: Macro.t(),
  else_clauses: [ElseClause.t()],
  location: SourceLocation.t() | nil,
  metadata: map()
}
```

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/elixir_ontologies/builders/control_flow_builder.ex`
- [x] Add module documentation
- [x] Import required namespaces and helpers

### Step 2: Implement Conditional Builder
- [x] `build_conditional/3` - Build if/unless/cond expressions
- [x] Map `:if` → `core:IfExpression`
- [x] Map `:unless` → `core:UnlessExpression`
- [x] Map `:cond` → `core:CondExpression`
- [x] Generate `hasCondition` triple for if/unless
- [x] Generate `hasThenBranch` and `hasElseBranch` triples
- [x] Generate `hasClause` triples for cond

### Step 3: Implement Case Builder
- [x] `build_case/3` - Build case expressions
- [x] Generate `rdf:type core:CaseExpression`
- [x] Generate `hasClause` for each case clause
- [x] Generate `hasGuard` when clauses have guards

### Step 4: Implement With Builder
- [x] `build_with/3` - Build with expressions
- [x] Generate `rdf:type core:WithExpression`
- [x] Generate `hasClause` for each with clause
- [x] Generate `hasElseClause` for else clauses

### Step 5: IRI Generation
- [x] `conditional_iri/3` - IRI for if/unless/cond
- [x] `case_iri/3` - IRI for case expressions
- [x] `with_iri/3` - IRI for with expressions

### Step 6: Add Tests
- [x] Test if expression building
- [x] Test unless expression building
- [x] Test cond expression building
- [x] Test case expression building
- [x] Test with expression building
- [x] Test IRI generation
- [x] Test location handling

### Step 7: Quality Checks
- [x] `mix compile --warnings-as-errors`
- [x] `mix credo --strict`
- [x] `mix test`

### Step 8: Complete
- [x] Update phase plan
- [x] Write summary

## Success Criteria

- [x] ControlFlowBuilder module created
- [x] All conditional types mapped to correct ontology classes
- [x] Condition and branch properties correctly linked
- [x] Case/with clauses properly represented
- [x] All tests pass (33 tests)
- [x] Quality checks pass
