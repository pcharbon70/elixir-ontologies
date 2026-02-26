# Phase 25.6: Try Expression Integration

**Feature Branch:** `feature/phase-25-6-try-expression-integration`
**Created:** 2026-01-14
**Based On:** Section 25.6 of notes/planning/expressions/phase-25.md

---

## Problem Statement

Section 25.6 of the expressions plan calls for implementing extraction for try/rescue/catch/after expressions with full pattern matching for exceptions.

Currently, there is NO `build_try/3` function in ControlFlowBuilder at all. The full implementation needs to be created from scratch, including:
1. Try body expression extraction
2. Rescue clause pattern extraction
3. Catch clause pattern extraction
4. After block expression extraction
5. Else clause extraction (if applicable)

---

## Current Implementation Analysis

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex`

**Status:** `build_try/3` does NOT exist. This is a new implementation.

### Exception Structure (from Extractors.Exception)

```elixir
%ElixirOntologies.Extractors.Exception{
  body: <AST>,                           # Try body expression
  rescue_clauses: [%RescueClause{
    exceptions: [...],                    # Exception types to catch
    variable: <AST> | nil,               # Variable binding
    body: <AST>,                         # Rescue body
    is_catch_all: boolean,
    location: %{}
  }],
  catch_clauses: [%CatchClause{
    kind: :throw | :exit | :error | nil,
    pattern: <AST>,                      # Pattern to match
    body: <AST>,                         # Catch body
    location: %{}
  }],
  else_clauses: [%ElseClause{
    pattern: <AST>,                      # Pattern for successful result
    guard: <AST> | nil,
    body: <AST>,
    location: %{}
  }],
  after_body: <AST> | nil,              # After block expression
  has_rescue: boolean(),
  has_catch: boolean(),
  has_else: boolean(),
  has_after: boolean(),
  location: %{},
  metadata: %{}
}
```

---

## Solution Overview

Create `build_try/3` in ControlFlowBuilder to support full expression extraction for try expressions.

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Use `hasBody` for try body | Existing ontology property in Structure namespace |
| Use `hasRescueClause` for rescue clauses | Existing ontology property |
| Use `hasCatchClause` for catch clauses | Existing ontology property |
| Use `hasAfterClause` for after block | Existing ontology property |
| Extract exception types as atoms | Rescue clause exceptions are already atoms in struct |
| Use `hasPattern` for rescue/catch patterns | Consistent with other pattern extraction |
| Keep light mode unchanged | Boolean flag approach for backward compatibility |

---

## Implementation Plan

### Step 1: Implement build_try/3

**Location:** `lib/elixir_ontologies/builders/control_flow_builder.ex`

**New function** to build try expression triples

```elixir
@doc """
Builds RDF triples for a try expression.

## Parameters

- `try_expr` - Exception extraction result (try expression)
- `context` - Builder context with base IRI
- `opts` - Options:
  - `:containing_function` - IRI fragment of containing function
  - `:index` - Expression index within the function (default: 0)
  - `:expression_builder` - Expression builder for full mode

## Returns

A tuple `{expr_iri, triples}`.
"""
@spec build_try(Exception.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
def build_try(%Exception{} = try_expr, %Context{} = context, opts \\ []) do
  containing_function = Keyword.get(opts, :containing_function, "unknown/0")
  index = Keyword.get(opts, :index, 0)
  expression_builder = Keyword.get(opts, :expression_builder)

  expr_iri = try_iri(context.base_iri, containing_function, index)

  # Check if we should build full expressions
  build_expressions? =
    expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

  triples =
    []
    |> add_type_triple(expr_iri, Core.TryExpression)
    |> add_try_body_triple(expr_iri, try_expr.body, expression_builder, build_expressions?, context)
    |> add_rescue_clause_triples(expr_iri, try_expr.rescue_clauses, expression_builder, build_expressions?, context)
    |> add_catch_clause_triples(expr_iri, try_expr.catch_clauses, expression_builder, build_expressions?, context)
    |> add_else_clause_triples(expr_iri, try_expr.else_clauses, expression_builder, build_expressions?, context)
    |> add_try_after_triple(expr_iri, try_expr.after_body, expression_builder, build_expressions?, context)
    |> add_location_triple(expr_iri, try_expr.location)

  {expr_iri, triples}
end
```

### Step 2: Implement try_iri/3

**New function** to generate try expression IRI

```elixir
@doc """
Generates an IRI for a try expression.

## Examples

    iex> ControlFlowBuilder.try_iri("https://example.org/code#", "MyApp/foo/1", 0)
    ~I<https://example.org/code#try/MyApp/foo/1/0>
"""
@spec try_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
def try_iri(base_iri, containing_function, index) when is_binary(base_iri) do
  RDF.iri("#{base_iri}try/#{containing_function}/#{index}")
end

def try_iri(%RDF.IRI{value: base}, containing_function, index) do
  try_iri(base, containing_function, index)
end
```

### Step 3: Implement helper functions

```elixir
# Extract try body expression
defp add_try_body_triple(triples, expr_iri, body, expression_builder, build_expressions?, context) do
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

# Extract rescue clauses
defp add_rescue_clause_triples(triples, expr_iri, clauses, expression_builder, build_expressions?, context)
     when is_list(clauses) and clauses != [] do
  if build_expressions? do
    Enum.reduce(clauses, triples, fn clause, acc ->
      add_rescue_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
    end)
  else
    triple = Helpers.datatype_property(expr_iri, Core.hasRescueClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end
end

defp add_rescue_clause_triples(triples, _expr_iri, _clauses, _expression_builder, _build_expressions?, _context),
  do: triples

# Extract catch clauses
defp add_catch_clause_triples(triples, expr_iri, clauses, expression_builder, build_expressions?, context)
     when is_list(clauses) and clauses != [] do
  if build_expressions? do
    Enum.reduce(clauses, triples, fn clause, acc ->
      add_catch_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
    end)
  else
    triple = Helpers.datatype_property(expr_iri, Core.hasCatchClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end
end

defp add_catch_clause_triples(triples, _expr_iri, _clauses, _expression_builder, _build_expressions?, _context),
  do: triples

# Extract else clauses
defp add_else_clause_triples(triples, expr_iri, clauses, expression_builder, build_expressions?, context)
     when is_list(clauses) and clauses != [] do
  if build_expressions? do
    # Else clauses are similar to case clauses
    Enum.reduce(clauses, triples, fn clause, acc ->
      add_try_else_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
    end)
  else
    triples
  end
end

defp add_else_clause_triples(triples, _expr_iri, _clauses, _expression_builder, _build_expressions?, _context),
  do: triples

# Extract after block
defp add_try_after_triple(triples, expr_iri, after_body, expression_builder, build_expressions?, context) do
  if build_expressions? and not is_nil(after_body) do
    case expression_builder.build(after_body, context, suffix: "after") do
      {:ok, {after_iri, after_triples}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasAfterClause(), after_iri)
        after_triples ++ [link_triple | triples]

      {:ok, {after_iri, after_triples, _updated_context}} ->
        link_triple = Helpers.object_property(expr_iri, Core.hasAfterClause(), after_iri)
        after_triples ++ [link_triple | triples]

      :skip ->
        triples
    end
  else
    triples
  end
end
```

### Step 4: Implement clause expression extraction functions

```elixir
# Rescue clause expression extraction
defp add_rescue_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
  # Rescue clauses have exceptions list (atoms) and optional variable binding
  # We'll create a simple link for now since rescue patterns are complex
  clause_iri = RDF.iri("#{expr_iri}/rescue/#{:erlang.unique_integer([:positive, :monotonic])}")

  # Build rescue body
  body_triples_with_link =
    case expression_builder.build(clause.body, context, suffix: "rescue_body") do
      {:ok, {body_iri, body_triples}} ->
        link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
        body_triples ++ [link_triple]

      {:ok, {body_iri, body_triples, _updated_context}} ->
        link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
        body_triples ++ [link_triple]

      :skip ->
        []
    end

  # Link to clause via hasRescueClause
  clause_link_triple = Helpers.object_property(expr_iri, Core.hasRescueClause(), clause_iri)

  body_triples_with_link ++ [clause_link_triple] ++ triples
end

# Catch clause expression extraction
defp add_catch_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
  # Build pattern for catch
  pattern_iri = RDF.iri("#{expr_iri}/catch/#{:erlang.unique_integer([:positive, :monotonic])}")
  pattern_triples = ExpressionBuilder.build_pattern(clause.pattern, pattern_iri, context)
  pattern_link_triple = Helpers.object_property(expr_iri, Core.hasPattern(), pattern_iri)

  # Build catch body
  body_triples_with_link =
    case expression_builder.build(clause.body, context, suffix: "catch_body") do
      {:ok, {body_iri, body_triples}} ->
        link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
        body_triples ++ [link_triple]

      {:ok, {body_iri, body_triples, _updated_context}} ->
        link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
        body_triples ++ [link_triple]

      :skip ->
        []
    end

  # Link to clause via hasCatchClause
  clause_link_triple = Helpers.object_property(expr_iri, Core.hasCatchClause(), pattern_iri)

  pattern_triples ++ [pattern_link_triple] ++ body_triples_with_link ++ [clause_link_triple] ++ triples
end

# Else clause expression extraction (similar to case else clauses)
defp add_try_else_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
  # Build pattern
  pattern_iri = RDF.iri("#{expr_iri}/else/#{:erlang.unique_integer([:positive, :monotonic])}/pattern")
  pattern_triples = ExpressionBuilder.build_pattern(clause.pattern, pattern_iri, context)
  pattern_link_triple = Helpers.object_property(expr_iri, Core.hasPattern(), pattern_iri)

  # Build guard if present
  guard_triples =
    if clause.guard != nil do
      case expression_builder.build(clause.guard, context, suffix: "else_guard") do
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
    case expression_builder.build(clause.body, context, suffix: "else_body") do
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

---

## Success Criteria

- [ ] 25.6.1.1: Implement `build_try/3` in ControlFlowBuilder
- [ ] 25.6.1.2: Match try AST from Exception struct
- [ ] 25.6.1.3: Extract try body expression
- [ ] 25.6.1.4: Extract rescue clauses with patterns
- [ ] 25.6.1.5: Extract catch clauses with patterns
- [ ] 25.6.1.6: Extract after block if present
- [ ] 25.6.1.7: Create type triple for TryExpression
- [ ] 25.6.1.8: Support simple try (try do expr end)
- [ ] 25.6.2.1: Extract rescue clause exception patterns
- [ ] 25.6.2.2: Match exception patterns from RescueClause struct
- [ ] 25.6.2.3: Use pattern extraction from ExpressionBuilder
- [ ] 25.6.2.4: Link via `hasRescueClause` property
- [ ] 25.6.2.5: Extract catch clause patterns
- [ ] 25.6.2.6: Match catch patterns from CatchClause struct
- [ ] 25.6.2.7: Link via `hasCatchClause` property
- [ ] 25.6.2.8: Extract body expressions for each clause
- [ ] 25.6.3.1: Extract after block expression
- [ ] 25.6.3.2: Create after IRI
- [ ] 25.6.3.3: Call `ExpressionBuilder.build/3`
- [ ] 25.6.3.4: Link via `hasAfterClause` property
- [ ] All 7 unit tests pass

---

## Test Coverage

New tests needed:
1. Test try expression extraction for try body
2. Test try expression rescue pattern extraction
3. Test try expression catch pattern extraction
4. Test try expression after block extraction
5. Test try expression extraction handles multiple rescue clauses
6. Test try expression extraction handles wildcard rescue
7. Test try expression extraction for simple try (no rescue/catch/after)

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/control_flow_builder.ex` | Add `build_try/3`, `try_iri/3`, and helper functions |
| `test/elixir_ontologies/builders/control_flow_builder_test.exs` | Add 7 new tests for try expression integration |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| New implementation from scratch | Follow patterns from case/with/receive implementations |
| Rescue clause complexity | Use simpler approach - link to clause IRI rather than complex pattern |
| Multiple clause types | Separate functions for rescue, catch, and else clauses |
| Else clause similar to case | Reuse pattern from case else clauses |
| Breaking existing tests | All new tests, existing tests unchanged |

---

## Implementation Status

- [x] Planning document complete
- [x] Implementation complete
- [x] Tests passing (7 new tests, all passing)
- [x] Documentation updated
- [x] Summary written

---

*Last Updated:* 2026-01-14
*Branch:* feature/phase-25-6-try-expression-integration
