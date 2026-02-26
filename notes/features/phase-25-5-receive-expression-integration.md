# Phase 25.5: Receive Expression Integration

**Feature Branch:** `feature/phase-25-5-receive-expression-integration`
**Created:** 2026-01-14
**Based On:** Section 25.5 of notes/planning/expressions/phase-25.md

---

## Problem Statement

Section 25.5 of the expressions plan calls for updating receive expression extraction to include:
1. Message patterns for each receive clause
2. Guard expressions for guarded clauses
3. Body expressions for message handlers
4. Timeout expression (not just integer, could be an expression)
5. After block body expression

Currently, `build_receive/3` only creates type triples and boolean flags for clauses and after blocks. The full expression extraction needs to be implemented.

---

## Current Implementation Analysis

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex:358-372`

The current implementation:
- ✅ Creates type triple for `ReceiveExpression`
- ❌ Does NOT extract receive clause patterns
- ❌ Does NOT extract guard expressions
- ❌ Does NOT extract clause body expressions
- ❌ Does NOT extract timeout expression (only boolean flag)
- ❌ Does NOT extract after block expression
- ✅ Creates boolean flags for `hasClause` and `hasAfterTimeout`

### ReceiveExpression Structure

```elixir
%ReceiveExpression{
  clauses: [%CaseClause{
    index: 0,
    pattern: <AST>,     # Message pattern to match
    guard: <AST> | nil, # Optional guard
    body: <AST>,        # Clause body
    has_guard: boolean,
    location: %{}
  }],
  after_clause: %AfterClause{
    timeout: <AST>,     # Timeout expression (could be literal or expression)
    body: <AST>,        # After block body
    is_immediate: boolean,
    location: %{}
  } | nil,
  has_after: boolean,
  location: %{},
  metadata: %{}
}
```

### AfterClause Structure

```elixir
%AfterClause{
  timeout: <AST>,  # Timeout value/expression
  body: <AST>,     # After block body
  is_immediate: boolean,
  location: %{}
}
```

---

## Solution Overview

Update `build_receive/3` to accept `expression_builder` option and implement full expression extraction similar to case and with expressions.

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Use `hasPattern` for message patterns | Ontology has `hasPattern` property |
| Use `hasGuard` for guard expressions | Already exists in ontology |
| Use `hasBody` for message handler bodies | Existing ontology property |
| Use suffix-based IRIs for clauses | `receive_{index}_pattern`, `receive_{index}_body` |
| Extract timeout as expression | Timeout can be an expression, not just literal |
| Use `hasAfterClause` for after block body | Link to after body expression |
| Keep light mode unchanged | Boolean flag approach for backward compatibility |

---

## Implementation Plan

### Step 1: Update build_receive/3 Signature

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex:358-372`

**Changes:**
1. Add `expression_builder` option parameter
2. Add `build_expressions?` check
3. Pass parameters to `add_receive_clause_triples`
4. Pass parameters to new `add_receive_after_triples`

```elixir
def build_receive(%ReceiveExpression{} = receive_expr, %Context{} = context, opts \\ []) do
  containing_function = Keyword.get(opts, :containing_function, "unknown/0")
  index = Keyword.get(opts, :index, 0)
  expression_builder = Keyword.get(opts, :expression_builder)

  expr_iri = receive_iri(context.base_iri, containing_function, index)

  # Check if we should build full expressions
  build_expressions? =
    expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

  triples =
    []
    |> add_type_triple(expr_iri, Core.ReceiveExpression)
    |> add_receive_clause_triples(expr_iri, receive_expr.clauses, expression_builder, build_expressions?, context)
    |> add_receive_after_triples(expr_iri, receive_expr.after_clause, expression_builder, build_expressions?, context)
    |> add_location_triple(expr_iri, receive_expr.location)

  {expr_iri, triples}
end
```

### Step 2: Update add_receive_clause_triples/6

**Location:** Replace current `add_receive_clause_triples/3` with new version

```elixir
defp add_receive_clause_triples(triples, expr_iri, clauses, expression_builder, build_expressions?, context)
     when is_list(clauses) and clauses != [] do
  if build_expressions? do
    # Build full expression triples for each clause
    clauses
    |> Enum.reduce(triples, fn clause, acc ->
      add_receive_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
    end)
  else
    # Light mode: store boolean flag only
    triple = Helpers.datatype_property(expr_iri, Core.hasClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end
end

defp add_receive_clause_triples(triples, _expr_iri, _clauses, _expression_builder, _build_expressions?, _context),
  do: triples
```

### Step 3: Implement add_receive_clause_expression_triples/5

**New function** to extract pattern, guard, and body for each receive clause

```elixir
defp add_receive_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
  # 1. Build pattern triples
  pattern_iri = RDF.iri("#{expr_iri}/pattern/#{clause.index}")
  pattern_triples = ExpressionBuilder.build_pattern(clause.pattern, pattern_iri, context)
  pattern_link_triple = Helpers.object_property(expr_iri, Core.hasPattern(), pattern_iri)

  # 2. Build guard expression if present
  guard_triples =
    if clause.guard != nil do
      case expression_builder.build(clause.guard, context, suffix: "receive_#{clause.index}_guard") do
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
    case expression_builder.build(clause.body, context, suffix: "receive_#{clause.index}_body") do
      {:ok, {body_iri, body_expr_triples}} ->
        link_triple = Helpers.object_property(expr_iri, ElixirOntologies.NS.Structure.hasBody(), body_iri)
        body_expr_triples ++ [link_triple]

      {:ok, {body_iri, body_expr_triples, _updated_context}} ->
        link_triple = Helpers.object_property(expr_iri, ElixirOntologies.NS.Structure.hasBody(), body_iri)
        body_expr_triples ++ [link_triple]

      :skip ->
        []
    end

  pattern_triples ++ [pattern_link_triple] ++ guard_triples ++ body_triples_with_link ++ triples
end
```

### Step 4: Implement add_receive_after_triples/6

**Location:** Replace current `add_after_timeout_triple/3` with new version

```elixir
defp add_receive_after_triples(triples, expr_iri, after_clause, expression_builder, build_expressions?, context)
     when not is_nil(after_clause) do
  if build_expressions? do
    # Build full expression triples for after clause
    # Extract timeout expression
    timeout_triples =
      case expression_builder.build(after_clause.timeout, context, suffix: "timeout") do
        {:ok, {timeout_iri, timeout_expr_triples}} ->
          # Note: hasTimeout property doesn't exist in ontology, using hasCondition
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), timeout_iri)
          timeout_expr_triples ++ [link_triple]

        {:ok, {timeout_iri, timeout_expr_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), timeout_iri)
          timeout_expr_triples ++ [link_triple]

        :skip ->
          []
      end

    # Extract after body
    body_triples_with_link =
      case expression_builder.build(after_clause.body, context, suffix: "after_body") do
        {:ok, {body_iri, body_expr_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasAfterClause(), body_iri)
          body_expr_triples ++ [link_triple]

        {:ok, {body_iri, body_expr_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasAfterClause(), body_iri)
          body_expr_triples ++ [link_triple]

        :skip ->
          []
      end

    timeout_triples ++ body_triples_with_link ++ triples
  else
    # Light mode: store boolean flag only
    triple = Helpers.datatype_property(expr_iri, Core.hasAfterTimeout(), true, RDF.XSD.Boolean)
    [triple | triples]
  end
end

defp add_receive_after_triples(triples, _expr_iri, _after_clause, _expression_builder, _build_expressions?, _context),
  do: triples
```

---

## Success Criteria

- [ ] 25.5.1.1: Update `add_receive_clause_triples` for full mode
- [ ] 25.5.1.2: Create clause IRIs via suffix
- [ ] 25.5.1.3: Extract pattern via ExpressionBuilder
- [ ] 25.5.1.4: Link pattern via `hasPattern`
- [ ] 25.5.1.5: Extract guard expression if present
- [ ] 25.5.1.6: Link guard via `hasGuard`
- [ ] 25.5.1.7: Extract body expression for message handler
- [ ] 25.5.1.8: Link body via `hasBody`
- [ ] 25.5.2.1: Extract timeout expression
- [ ] 25.5.2.2: Create timeout IRI
- [ ] 25.5.2.3: Call `ExpressionBuilder.build/3`
- [ ] 25.5.2.4: Link via `hasCondition` (hasTimeout doesn't exist)
- [ ] 25.5.2.5: Extract after block if present
- [ ] 25.5.2.6: Create after IRI
- [ ] 25.5.2.7: Extract after block expression
- [ ] 25.5.2.8: Link via `hasAfterClause`
- [ ] 25.5.2.9: Light mode boolean flags
- [ ] All 6 unit tests pass

---

## Test Coverage

### Before This Change

Current tests for receive:
- `test build_receive/3 generates type triple for receive expression`
- `test build_receive/3 generates hasClause triple for receive with clauses`
- `test build_receive/3 generates hasAfterTimeout triple for receive with after block`
- `test build_receive/3 does not generate hasAfterTimeout when no after block`
- `test build_receive/3 generates startLine triple for receive with location`

### After This Change

New tests needed:
1. Test receive clause pattern extraction in full mode
2. Test receive clause guard extraction in full mode
3. Test receive clause body extraction in full mode
4. Test receive timeout expression extraction
5. Test receive after block extraction
6. Test receive extraction for multiple clauses

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/control_flow_builder.ex` | Update `build_receive/3`, add functions |
| `test/elixir_ontologies/builders/control_flow_builder_test.exs` | Add 6 new tests for receive expression integration |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Pattern extraction complexity | Use existing `ExpressionBuilder.build_pattern/3` |
| AfterClause struct access | Need to access timeout and body fields from AfterClause |
| hasTimeout property missing | Use `hasCondition` instead for timeout |
| Breaking existing tests | All new tests, existing light mode tests unchanged |

---

## Implementation Status

- [x] Planning document complete
- [x] Implementation complete
- [x] Tests passing (6 new tests, all passing)
- [x] Documentation updated
- [x] Summary written

---

*Last Updated:* 2026-01-14
*Branch:* feature/phase-25-5-receive-expression-integration
