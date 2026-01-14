# Phase 25.2: Cond Expression Integration

**Feature Branch:** `feature/phase-25-2-cond-expression-integration`
**Created:** 2026-01-14
**Based On:** Section 25.2 of notes/planning/expressions/phase-25.md

---

## Problem Statement

Section 25.2 of the expressions plan calls for updating cond expression extraction to include full condition and body expressions for each clause when `include_expressions: true`. The current implementation has partial support but is missing proper links for body expressions.

---

## Current Implementation Analysis

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex:565-614`

The current implementation:
- ✅ Builds condition expressions for each clause
- ✅ Builds body expressions for each clause
- ✅ Links conditions via `hasCondition` property
- ❌ **Missing:** Does NOT link body expressions (no `hasThenBranch` or `hasBody` property)
- ✅ Falls back to boolean flag in light mode

### Key Issues

1. **No body expression links:** The `add_cond_clause_expression_triples/5` function builds body expression triples but doesn't create any RDF triple linking the body to the cond expression or clause.

2. **Body triples orphaned:** The body triples are added to the result list but there's no `hasThenBranch` or `hasBody` property to link them.

---

## Solution Overview

Update `add_cond_clause_expression_triples/5` to:
1. Save the body IRI from ExpressionBuilder
2. Create a `hasThenBranch` object property linking to the body IRI
3. Link from the cond expression IRI (not from individual clause IRIs, since CondClause class doesn't exist in ontology)

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Use `hasThenBranch` for body links | Matches ontology definition and if/unless pattern |
| Link bodies to cond expression IRI | No CondClause class exists in ontology |
| Keep clause order via expression IRI suffixes | `cond_{index}_condition` and `cond_{index}_body` maintain order |
| Keep light mode unchanged | Boolean flag approach for backward compatibility |

---

## Implementation Plan

### Step 1: Fix Body Expression Linking

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex:583-614`

**Change:** Update `add_cond_clause_expression_triples/5` to link body expressions:

```elixir
# Build expression triples for a single cond clause
defp add_cond_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
  # Build condition expression
  {condition_iri, cond_triples} =
    case expression_builder.build(clause.condition, context, suffix: "cond_#{clause.index}_condition") do
      {:ok, {condition_iri, condition_expr_triples}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), condition_iri)
        {condition_iri, condition_expr_triples ++ [link_triple]}

      {:ok, {condition_iri, condition_expr_triples, _updated_context}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), condition_iri)
        {condition_iri, condition_expr_triples ++ [link_triple]}

      :skip ->
        {nil, []}
    end

  # Build body expression and link it
  body_triples_with_link =
    case expression_builder.build(clause.body, context, suffix: "cond_#{clause.index}_body") do
      {:ok, {body_iri, body_expr_triples}} ->
        # Create hasThenBranch link from cond expression to body
        link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
        body_expr_triples ++ [link_triple]

      {:ok, {body_iri, body_expr_triples, _updated_context}} ->
        # Create hasThenBranch link from cond expression to body
        link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
        body_expr_triples ++ [link_triple]

      :skip ->
        []
    end

  cond_triples ++ body_triples_with_link ++ triples
end
```

### Step 2: Add Unit Tests

**Location:** `test/elixir_ontologies/builders/control_flow_builder_test.exs`

Add tests for:
1. Cond clause extraction in light mode (boolean flag)
2. Cond clause extraction in full mode (expression trees)
3. Cond clause extraction captures condition expression
4. Cond clause extraction captures body expression
5. Cond clause extraction handles multiple clauses
6. Cond clause extraction handles catch-all clause
7. Cond clause extraction preserves clause order

---

## Success Criteria

- [ ] 25.2.1.1: Identify cond clauses in `add_cond_clause_triples/4` ✅ (already exists)
- [ ] 25.2.1.2: When `include_expressions: true`: extract each clause separately ✅ (already exists)
- [ ] 25.2.1.3: Create clause IRIs: `{cond_iri}/clause/{index}` ✅ (via suffix approach)
- [ ] 25.2.1.4: Extract condition expression for each clause ✅ (already exists)
- [ ] 25.2.1.5: Create `hasCondition` object property for each clause ✅ (already exists)
- [ ] 25.2.1.6: Extract body expression for each clause ✅ (already exists)
- [ ] 25.2.1.7: Create `hasThenBranch` or `hasBody` property ❌ (needs implementation)
- [ ] 25.2.1.8: In light mode: use existing boolean flag approach ✅ (already exists)
- [ ] 25.2.1.9: Handle final catch-all clause (condition: `true`) ✅ (no special handling needed)
- [ ] All 7 unit tests pass

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/control_flow_builder.ex` | Update `add_cond_clause_expression_triples/5` to link body expressions |
| `test/elixir_ontologies/builders/control_flow_builder_test.exs` | Add 7 new tests for cond clause expression extraction |

---

## Test Coverage

### Before This Change

Current tests for cond (light mode only):
- `test build_conditional/3 with cond generates type triple for cond expression`
- `test build_conditional/3 with cond generates hasClause triple for cond with clauses`
- `test build_conditional/3 with cond does not generate hasCondition for cond`

### After This Change

New tests needed:
- Cond clause extraction in light mode (boolean flag)
- Cond clause extraction in full mode (expression trees)
- Cond clause extraction captures condition expression
- Cond clause extraction captures body expression
- Cond clause extraction handles multiple clauses
- Cond clause extraction handles catch-all clause
- Cond clause extraction preserves clause order

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking existing tests | All new tests, existing light mode tests unchanged |
| Multiple hasThenBranch links | This is correct for cond - each clause has a body |
| Clause ordering lost | Suffix-based IRI generation preserves order |

---

## Implementation Status

- [ ] Planning document complete
- [ ] Implementation complete
- [ ] Tests passing
- [ ] Documentation updated
- [ ] Summary written

---

*Last Updated:* 2026-01-14
*Branch:* feature/phase-25-2-cond-expression-integration
