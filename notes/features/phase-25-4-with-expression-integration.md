# Phase 25.4: With Expression Integration

**Feature Branch:** `feature/phase-25-4-with-expression-integration`
**Created:** 2026-01-14
**Based On:** Section 25.4 of notes/planning/expressions/phase-25.md

---

## Problem Statement

Section 25.4 of the expressions plan calls for updating with expression extraction to include:
1. Match patterns for each with clause (`pattern <- expression`)
2. The expression being matched for each clause
3. The do block body expression
4. Optional else clause expressions

Currently, `build_with/3` only creates type triples and boolean flags for clauses. The full expression extraction needs to be implemented.

---

## Current Implementation Analysis

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex:288-302`

The current implementation:
- ✅ Creates type triple for `WithExpression`
- ❌ Does NOT extract with clause patterns
- ❌ Does NOT extract with clause expressions
- ❌ Does NOT extract body expression
- ❌ Does NOT extract else clause expressions
- ✅ Creates boolean flags for `hasClause` and `hasElseClause`

### WithExpression Structure
```elixir
%WithExpression{
  clauses: [
    %WithClause{
      index: 0,
      type: :match,         # or :bare_match
      pattern: <AST>,       # Pattern to match (e.g., {:x, [], Elixir})
      expression: <AST>,    # Expression being matched
      location: %{}
    }
  ],
  body: <AST>,             # Do block body
  else_clauses: [%CaseClause{}],  # Optional else clauses
  has_else: boolean,
  location: %{},
  metadata: %{}
}
```

---

## Solution Overview

Update `build_with/3` to accept `expression_builder` option and implement full expression extraction similar to case expressions.

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Use `hasPattern` for clause patterns | Ontology has `hasPattern` property |
| Use `hasCondition` for matched expressions | Links the expression being matched (hasCondition is the standard property for conditions) |
| Use `hasBody` for do block body | Existing ontology property in Structure namespace |
| Use `hasElseClause` linking to else IRIs | Already exists, create else expression IRIs |
| Use suffix-based IRIs for clauses | `with_{index}_expression` for expressions |
| Keep light mode unchanged | Boolean flag approach for backward compatibility |

**Note:** `hasExpression` property does not exist in the ontology. Using `hasCondition` instead to link the expressions being matched.

---

## Implementation Plan

### Step 1: Update build_with/3 Signature

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex:288-302`

**Changes:**
1. Add `expression_builder` option parameter
2. Add `build_expressions?` check
3. Pass parameters to `add_with_clause_triples`
4. Pass parameters to new `add_with_body_triple`
5. Pass parameters to new `add_with_else_triples`

```elixir
def build_with(%WithExpression{} = with_expr, %Context{} = context, opts \\ []) do
  containing_function = Keyword.get(opts, :containing_function, "unknown/0")
  index = Keyword.get(opts, :index, 0)
  expression_builder = Keyword.get(opts, :expression_builder)

  expr_iri = with_iri(context.base_iri, containing_function, index)

  # Check if we should build full expressions
  build_expressions? =
    expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

  triples =
    []
    |> add_type_triple(expr_iri, Core.WithExpression)
    |> add_with_clause_triples(expr_iri, with_expr.clauses, expression_builder, build_expressions?, context)
    |> add_with_body_triple(expr_iri, with_expr.body, expression_builder, build_expressions?, context)
    |> add_with_else_triples(expr_iri, with_expr.else_clauses, expression_builder, build_expressions?, context)
    |> add_location_triple(expr_iri, with_expr.location)

  {expr_iri, triples}
end
```

### Step 2: Implement add_with_clause_triples/6

**Location:** Replace current `add_with_clause_triples/3` with new version

```elixir
defp add_with_clause_triples(triples, expr_iri, clauses, expression_builder, build_expressions?, context)
     when is_list(clauses) and clauses != [] do
  if build_expressions? do
    # Build full expression triples for each clause
    clauses
    |> Enum.reduce(triples, fn clause, acc ->
      add_with_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
    end)
  else
    # Light mode: store boolean flag only
    triple = Helpers.datatype_property(expr_iri, Core.hasClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end
end

defp add_with_clause_triples(triples, _expr_iri, _clauses, _expression_builder, _build_expressions?, _context),
  do: triples
```

### Step 3: Implement add_with_clause_expression_triples/5

**New function** to extract pattern and expression for each with clause

```elixir
defp add_with_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
  # 1. Build pattern triples
  pattern_iri = RDF.iri("#{expr_iri}/pattern/#{clause.index}")
  pattern_triples = ExpressionBuilder.build_pattern(clause.pattern, pattern_iri, context)
  pattern_link_triple = Helpers.object_property(expr_iri, Core.hasPattern(), pattern_iri)

  # 2. Build expression being matched
  expression_triples_with_link =
    case expression_builder.build(clause.expression, context, suffix: "with_#{clause.index}_expression") do
      {:ok, {expr_ast_iri, expr_ast_triples}} ->
        # Create hasExpression link from pattern to the expression being matched
        link_triple = Helpers.object_property(pattern_iri, Core.hasExpression(), expr_ast_iri)
        expr_ast_triples ++ [link_triple]

      {:ok, {expr_ast_iri, expr_ast_triples, _updated_context}} ->
        link_triple = Helpers.object_property(pattern_iri, Core.hasExpression(), expr_ast_iri)
        expr_ast_triples ++ [link_triple]

      :skip ->
        []
    end

  pattern_triples ++ [pattern_link_triple] ++ expression_triples_with_link ++ triples
end
```

### Step 4: Implement add_with_body_triple/6

**New function** to extract do block body expression

```elixir
defp add_with_body_triple(triples, expr_iri, body, expression_builder, build_expressions?, context) do
  if build_expressions? and not is_nil(body) do
    case expression_builder.build(body, context, suffix: "body") do
      {:ok, {body_iri, body_triples}} ->
        link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
        body_triples ++ [link_triple | triples]

      {:ok, {body_iri, body_triples, _updated_context}} ->
        link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
        body_triples ++ [link_triple | triples]

      :skip ->
        triples
    end
  else
    triples
  end
end
```

### Step 5: Implement add_with_else_triples/6

**Location:** Replace current `add_has_else_triple/3` with new version

```elixir
defp add_with_else_triples(triples, expr_iri, else_clauses, expression_builder, build_expressions?, context)
     when is_list(else_clauses) and else_clauses != [] do
  if build_expressions? do
    # Build expression triples for else clauses
    # For with, else clauses are CaseClause structs (same as case expression)
    else_clauses
    |> Enum.reduce(triples, fn clause, acc ->
      add_else_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
    end)
  else
    # Light mode: store boolean flag only
    triple = Helpers.datatype_property(expr_iri, Core.hasElseClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end
end

defp add_with_else_triples(triples, _expr_iri, _else_clauses, _expression_builder, _build_expressions?, _context),
  do: triples

# Build expression triples for an else clause (similar to case clauses)
defp add_else_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
  # Build pattern
  pattern_iri = RDF.iri("#{expr_iri}/else/#{clause.index}/pattern")
  pattern_triples = ExpressionBuilder.build_pattern(clause.pattern, pattern_iri, context)
  pattern_link_triple = Helpers.object_property(expr_iri, Core.hasPattern(), pattern_iri)

  # Build guard if present
  guard_triples =
    if clause.guard != nil do
      case expression_builder.build(clause.guard, context, suffix: "else_#{clause.index}_guard") do
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

  # Build body
  body_triples_with_link =
    case expression_builder.build(clause.body, context, suffix: "else_#{clause.index}_body") do
      {:ok, {body_iri, body_expr_triples}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
        body_expr_triples ++ [link_triple]

      {:ok, {body_iri, body_expr_triples, _updated_context}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
        body_expr_triples ++ [link_triple]

      :skip ->
        []
    end

  pattern_triples ++ [pattern_link_triple] ++ guard_triples ++ body_triples_with_link ++ triples
end
```

### Step 6: Add Structure alias

**Location:** Module aliases section

Add `Structure` to the aliases for `hasBody` property.

---

## Success Criteria

- [ ] 25.4.1.1: Update `add_with_clause_triples` for full mode
- [ ] 25.4.1.2: Create clause IRIs via suffix
- [ ] 25.4.1.3: Extract pattern via ExpressionBuilder
- [ ] 25.4.1.4: Extract expression from right side
- [ ] 25.4.1.5: Link pattern via `hasPattern`
- [ ] 25.4.1.6: Link expression via `hasExpression`
- [ ] 25.4.1.7: Handle `:match` type clauses
- [ ] 25.4.1.8: Handle `:else` type clauses
- [ ] 25.4.2.1: Extract with body expression
- [ ] 25.4.2.2: Create body IRI
- [ ] 25.4.2.3: Call `ExpressionBuilder.build/3`
- [ ] 25.4.2.4: Link via `hasBody`
- [ ] 25.4.2.5: Extract else clauses
- [ ] 25.4.2.6: Create `hasElseClause` linking
- [ ] 25.4.2.7: Light mode boolean flags
- [ ] All 6 unit tests pass

---

## Test Coverage

### Before This Change

Current tests for with:
- `test build_with/3 generates type triple for with expression`
- `test build_with/3 generates hasClause triple for with with clauses`
- `test build_with/3 generates hasElseClause triple when else clauses present`
- `test build_with/3 does not generate hasElseClause when no else clauses`

### After This Change

New tests needed:
1. Test with clause pattern extraction in full mode
2. Test with clause expression extraction in full mode
3. Test with body extraction in full mode
4. Test with else clause extraction in full mode
5. Test with extraction for multiple clauses
6. Test with extraction handles nested matches

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/control_flow_builder.ex` | Update `build_with/3`, add functions, add Structure alias |
| `test/elixir_ontologies/builders/control_flow_builder_test.exs` | Add 6 new tests for with expression integration |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Pattern extraction complexity | Use existing `ExpressionBuilder.build_pattern/3` |
| Else clause handling | Reuse case clause logic (both are CaseClause) |
| Breaking existing tests | All new tests, existing light mode tests unchanged |
| Missing `hasExpression` property | Use `hasCondition` instead (existing property) |

---

## Implementation Status

- [x] Planning document complete
- [x] Implementation complete
- [x] Tests passing (6 new tests, all passing)
- [x] Documentation updated
- [x] Summary written

---

*Last Updated:* 2026-01-14
*Branch:* feature/phase-25-4-with-expression-integration
