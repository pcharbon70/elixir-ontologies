# Phase 25.3: Case Expression Integration

**Feature Branch:** `feature/phase-25-3-case-expression-integration`
**Created:** 2026-01-14
**Based On:** Section 25.3 of notes/planning/expressions/phase-25.md

---

## Problem Statement

Section 25.3 of the expressions plan calls for updating case expression extraction to include:
1. The subject expression (what's being matched against)
2. Full clause patterns for each clause
3. Guard expressions for guarded clauses
4. Clause body expressions

Currently, `build_case/3` only creates type triples and boolean flags for clauses. The full expression extraction needs to be implemented.

---

## Current Implementation Analysis

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex:220-233`

The current implementation:
- ✅ Creates type triple for `CaseExpression`
- ❌ Does NOT extract subject expression
- ❌ Does NOT extract clause patterns
- ❌ Does NOT extract guard expressions
- ❌ Does NOT extract clause body expressions
- ✅ Creates boolean flags for `hasClause` and `hasGuard`

### CaseExpression Structure
```elixir
%CaseExpression{
  subject: <AST>,       # Expression being matched
  clauses: [%CaseClause{
    index: 0,
    pattern: <AST>,     # Pattern to match
    guard: <AST> | nil, # Optional guard
    body: <AST>,        # Clause body
    has_guard: boolean,
    location: %{}
  }],
  location: %{},
  metadata: %{}
}
```

---

## Solution Overview

Update `build_case/3` to accept `expression_builder` option and implement full expression extraction similar to the cond implementation.

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Use `hasCondition` for subject expression | Subject is what's being matched (similar to cond) |
| Use `hasPattern` for clause patterns | Ontology has `hasPattern` property for patterns |
| Use `hasGuard` for guard expressions | Already exists in ontology |
| Use `hasThenBranch` for clause bodies | Consistent with if/cond implementations |
| Use suffix-based IRIs for clauses | `case_{index}_pattern`, `case_{index}_body` |
| Keep light mode unchanged | Boolean flag approach for backward compatibility |

---

## Implementation Plan

### Step 1: Update build_case/3 Signature

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex:220-233`

**Changes:**
1. Add `expression_builder` option parameter
2. Add `build_expressions?` check
3. Pass parameters to `add_case_clause_triples`

```elixir
def build_case(%CaseExpression{} = case_expr, %Context{} = context, opts \\ []) do
  containing_function = Keyword.get(opts, :containing_function, "unknown/0")
  index = Keyword.get(opts, :index, 0)
  expression_builder = Keyword.get(opts, :expression_builder)

  expr_iri = case_iri(context.base_iri, containing_function, index)

  # Check if we should build full expressions
  build_expressions? =
    expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

  triples =
    []
    |> add_type_triple(expr_iri, Core.CaseExpression)
    |> add_case_subject_triple(expr_iri, case_expr.subject, expression_builder, build_expressions?, context)
    |> add_case_clause_triples(expr_iri, case_expr.clauses, expression_builder, build_expressions?, context)
    |> add_location_triple(expr_iri, case_expr.location)

  {expr_iri, triples}
end
```

### Step 2: Implement add_case_subject_triple/6

**New function** to extract subject expression

```elixir
defp add_case_subject_triple(triples, expr_iri, subject, expression_builder, build_expressions?, context) do
  if build_expressions? and not is_nil(subject) do
    case expression_builder.build(subject, context, suffix: "subject") do
      {:ok, {subject_iri, subject_triples}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), subject_iri)
        subject_triples ++ [link_triple | triples]

      {:ok, {subject_iri, subject_triples, _updated_context}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), subject_iri)
        subject_triples ++ [link_triple | triples]

      :skip ->
        triples
    end
  else
    triples
  end
end
```

### Step 3: Update add_case_clause_triples/6

**Location:** Replace current `add_case_clause_triples/3` with new version

```elixir
defp add_case_clause_triples(triples, expr_iri, clauses, expression_builder, build_expressions?, context)
     when is_list(clauses) and clauses != [] do
  if build_expressions? do
    # Build full expression triples for each clause
    clauses
    |> Enum.reduce(triples, fn clause, acc ->
      add_case_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
    end)
  else
    # Light mode: store boolean flags only
    clause_triple = Helpers.datatype_property(expr_iri, Core.hasClause(), true, RDF.XSD.Boolean)

    has_guards = Enum.any?(clauses, & &1.has_guard)

    if has_guards do
      guard_triple = Helpers.datatype_property(expr_iri, Core.hasGuard(), true, RDF.XSD.Boolean)
      [guard_triple, clause_triple | triples]
    else
      [clause_triple | triples]
    end
  end
end

defp add_case_clause_triples(triples, _expr_iri, _clauses, _expression_builder, _build_expressions?, _context),
  do: triples
```

### Step 4: Implement add_case_clause_expression_triples/5

**New function** to extract pattern, guard, and body for each clause

```elixir
defp add_case_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
  # 1. Build pattern triples
  pattern_triples =
    ExpressionBuilder.build_pattern(clause.pattern, expr_iri, context)

  # 2. Build guard expression if present
  guard_triples =
    if clause.guard != nil do
      case expression_builder.build(clause.guard, context, suffix: "case_#{clause.index}_guard") do
        {:ok, {guard_iri, guard_expr_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasGuard(), guard_iri)
          guard_expr_triples ++ [link_triple]

        {:ok, {guard_iri, guard_expr_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasGuard(), guard_iri)
          guard_expr_triples ++ [link_triple]

        :skip ->
          []
      end
    else
      []
    end

  # 3. Build body expression
  body_triples_with_link =
    case expression_builder.build(clause.body, context, suffix: "case_#{clause.index}_body") do
      {:ok, {body_iri, body_expr_triples}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
        body_expr_triples ++ [link_triple]

      {:ok, {body_iri, body_expr_triples, _updated_context}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
        body_expr_triples ++ [link_triple]

      :skip ->
        []
    end

  pattern_triples ++ guard_triples ++ body_triples_with_link ++ triples
end
```

---

## Success Criteria

- [ ] 25.3.1.1: Update `build_case/3` to extract subject expression when full mode
- [ ] 25.3.1.2: Match subject AST from `CaseExpression` struct
- [ ] 25.3.1.3: Create `hasCondition` property for case subject
- [ ] 25.3.1.4: Call `ExpressionBuilder.build/3` for subject AST
- [ ] 25.3.1.5: Generate child IRI: `{case_iri}/subject`
- [ ] 25.3.1.6: Link via `hasCondition` object property
- [ ] 25.3.2.1: Update `add_case_clause_triples` to accept context
- [ ] 25.3.2.2: For each clause: create clause IRIs via suffix
- [ ] 25.3.2.3: Extract pattern via `ExpressionBuilder.build_pattern/3`
- [ ] 25.3.2.4: Link pattern via `hasPattern` property
- [ ] 25.3.2.5: Extract guard expression if present
- [ ] 25.3.2.6: Link guard via `hasGuard` property
- [ ] 25.3.2.7: Extract body expression for each clause
- [ ] 25.3.2.8: Link body via `hasThenBranch` property
- [ ] 25.3.2.9: Light mode uses boolean flags
- [ ] All 7 unit tests pass

---

## Test Coverage

### Before This Change

Current tests for case:
- `test build_case/3 generates type triple for case expression`
- `test build_case/3 generates hasClause triple for case with clauses`
- `test build_case/3 generates hasGuard triple when clauses have guards`

### After This Change

New tests needed:
1. Test case subject expression extraction in full mode
2. Test case clause pattern extraction in full mode
3. Test case clause guard extraction in full mode
4. Test case clause body extraction in full mode
5. Test case extraction with multiple clauses
6. Test case extraction with guarded clauses
7. Test case extraction preserves clause order

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/control_flow_builder.ex` | Update `build_case/3`, add `add_case_subject_triple/6`, update `add_case_clause_triples/5`, add `add_case_clause_expression_triples/5` |
| `test/elixir_ontologies/builders/control_flow_builder_test.exs` | Add 7 new tests for case expression integration |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Pattern extraction complexity | Use existing `ExpressionBuilder.build_pattern/3` |
| Multiple hasThenBranch links | This is correct for case - each clause has a body |
| Guard expression nil handling | Explicit nil check before building |
| Breaking existing tests | All new tests, existing light mode tests unchanged |

---

## Implementation Status

- [x] Planning document complete
- [x] Implementation complete
- [x] Tests passing (7 new tests, all passing)
- [x] Documentation updated
- [x] Summary written

---

## Current Status

**Status:** COMPLETE ✅

**Tests:** 73 tests total
- 66 existing tests (unchanged)
- 7 new tests for case expression integration (all passing)
- 5 pre-existing failures (unrelated ontology properties)

**Files Modified:**
- `lib/elixir_ontologies/builders/control_flow_builder.ex`
  - Updated `build_case/3` with expression_builder support
  - Added `add_case_subject_triple/6`
  - Updated `add_case_clause_triples/5` with full mode support
  - Added `add_case_clause_expression_triples/5`
  - Added ExpressionBuilder alias
- `test/elixir_ontologies/builders/control_flow_builder_test.exs`
  - Added 7 new tests for case expression integration

*Last Updated:* 2026-01-14
*Branch:* feature/phase-25-3-case-expression-integration
