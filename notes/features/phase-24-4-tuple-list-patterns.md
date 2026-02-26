# Phase 24.4: Tuple and List Pattern Extraction

**Status:** Planning
**Branch:** `feature/phase-24-4-tuple-list-patterns`
**Created:** 2026-01-12
**Target:** Implement tuple and list pattern extraction for Phase 24.4

## 1. Problem Statement

Section 24.4 of Phase 24 implements two complex pattern builders: `build_tuple_pattern/3` and `build_list_pattern/3`. These handle destructuring patterns for tuples and lists, which can contain nested patterns of any type.

**Current State:**
- `detect_pattern_type/1` correctly identifies `:tuple_pattern` (`{:{}, _, _}` or `{left, right}`) and `:list_pattern` (flat or nested lists)
- `build_pattern/3` dispatches to placeholder functions
- `build_tuple_pattern/3` (line 1333-1335) returns only type triple: `[Core.TuplePattern]`
- `build_list_pattern/3` (line 1338-1340) returns only type triple: `[Core.ListPattern]`

**What's Missing:**
1. Tuple patterns should capture nested child patterns within the tuple structure
2. List patterns should capture nested child patterns
3. List patterns need special handling for cons cells (`[head | tail]`)
4. Tuple patterns should capture element count (arity)
5. No test coverage for tuple pattern nested extraction
6. No test coverage for list pattern nested extraction
7. No test coverage for cons pattern extraction
8. No test coverage for mixed nested patterns (tuple in list, list in tuple)

## 2. Solution Overview

### 2.1 Tuple Pattern Extraction

Tuple patterns match against tuple structures, destructuring them into nested patterns.

| Pattern | AST | Ontology Type | Properties |
|---------|-----|---------------|------------|
| Empty tuple | `{:{}, [], []}` | `Core.TuplePattern` | Type only |
| 2-tuple | `{left, right}` | `Core.TuplePattern` | Nested child patterns |
| n-tuple | `{:{}, _, [a, b, c]}` | `Core.TuplePattern` | Nested child patterns |

**Design Decision:** Similar to `build_tuple_literal/3` (line 761-770), tuple pattern extraction should:
1. Create the `Core.TuplePattern` type triple
2. Use recursive building to create nested child patterns
3. NOT explicitly store arity - it can be inferred from child count

**Key Difference from TupleLiteral:** Tuple patterns use `Core.TuplePattern` instead of `Core.TupleLiteral`. Child elements are patterns, not expressions.

### 2.2 List Pattern Extraction

List patterns match against list structures, with support for cons cell decomposition.

| Pattern | AST | Ontology Type | Properties |
|---------|-----|---------------|------------|
| Empty list | `[]` | `Core.ListPattern` | Type only |
| Flat list | `[a, b, c]` | `Core.ListPattern` | Nested child patterns |
| Cons cell | `[{:|, _, [head, tail]}]` | `Core.ListPattern` | Head and tail patterns |

**Design Decision:** List pattern extraction should:
1. Check for cons pattern using existing `cons_pattern?/1` helper
2. For cons cells: Build head and tail as separate child patterns
3. For flat lists: Build all elements as nested patterns

**Note:** The `build_cons_list/3` function (line 732-745) already handles cons cells for literal expressions. A similar approach can be used for patterns.

### 2.3 Nested Pattern Handling

Both tuple and list patterns can contain any nested pattern type:
- Literal patterns: `{1, :ok}` - tuple with literal patterns
- Variable patterns: `{x, y}` - tuple with variable patterns
- Wildcard patterns: `{x, _}` - tuple with wildcard
- Pin patterns: `{^x, y}` - tuple with pin pattern
- Nested tuples: `{{a, b}, c}` - tuple within tuple
- Nested lists: `{[a, b], c}` - list within tuple

## 3. Implementation Plan

### Step 1: Implement `build_tuple_pattern/3`

**File:** `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`

**Current implementation (line 1333-1335):**
```elixir
defp build_tuple_pattern(_ast, expr_iri, _context) do
  [Helpers.type_triple(expr_iri, Core.TuplePattern)]
end
```

**New implementation:**
```elixir
@doc """
Builds RDF triples for a tuple pattern.

Tuple patterns destructuring tuple values into nested patterns.

## Parameters

- `ast` - The tuple pattern AST: {:{}, _, elements} or {left, right}
- `expr_iri` - The IRI for this pattern expression
- `context` - The builder context

## Returns

A list of RDF triples with:
- Core.TuplePattern type triple
- Nested pattern triples for each element

## Examples

  iex> # 2-tuple: {x, y}
  iex> ast = {{:x, [], Elixir}, {:y, [], Elixir}}
  iex> build_tuple_pattern(ast, expr_iri, context)
  # Creates TuplePattern with nested VariablePatterns

  iex> # n-tuple: {1, :ok, x}
  iex> ast = {:{}, [], [1, {:ok, [], nil}, {:x, [], Elixir}]}
  iex> build_tuple_pattern(ast, expr_iri, context)
  # Creates TuplePattern with nested patterns

"""
defp build_tuple_pattern(ast, expr_iri, context) do
  # Extract elements from tuple AST
  elements = extract_tuple_elements(ast)

  # Create the TuplePattern type triple
  type_triple = Helpers.type_triple(expr_iri, Core.TuplePattern)

  # Build child patterns for each element
  # Note: We use build_pattern/3 recursively for nested patterns
  {child_triples, _final_context} = build_child_patterns(elements, expr_iri, context)

  # Include type triple and all child pattern triples
  [type_triple | child_triples]
end

# Helper to extract elements from tuple AST
# Handles both {:{}, _, elements} and {left, right} forms
defp extract_tuple_elements({:{}, _meta, elements}), do: elements
defp extract_tuple_elements({left, right}), do: [left, right]

# Helper to build child patterns from a collection
# Similar to build_child_expressions but uses build_pattern/3
# Returns {flat_triples_list, final_context}
defp build_child_patterns(items, parent_iri, context) do
  {triples_list, final_ctx} =
    Enum.map_reduce(items, context, fn item, ctx ->
      # Use build/3 to get IRI, then build_pattern/3 for pattern context
      {:ok, {child_iri, _expression_triples, new_ctx}} = build(item, ctx, [])
      pattern_triples = build_pattern(item, child_iri, ctx)
      {pattern_triples, new_ctx}
    end)

  {List.flatten(triples_list), final_ctx}
end
```

### Step 2: Implement `build_list_pattern/3`

**File:** `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`

**Current implementation (line 1338-1340):**
```elixir
defp build_list_pattern(_ast, expr_iri, _context) do
  [Helpers.type_triple(expr_iri, Core.ListPattern)]
end
```

**New implementation:**
```elixir
@doc """
Builds RDF triples for a list pattern.

List patterns destructuring list values, including head|tail cons patterns.

## Parameters

- `ast` - The list pattern AST: [elements] or [{:|, _, [head, tail]}]
- `expr_iri` - The IRI for this pattern expression
- `context` - The builder context

## Returns

A list of RDF triples with:
- Core.ListPattern type triple
- Nested pattern triples for elements

## Examples

  iex> # Flat list: [x, y, z]
  iex> ast = [{:x, [], Elixir}, {:y, [], Elixir}, {:z, [], Elixir}]
  iex> build_list_pattern(ast, expr_iri, context)
  # Creates ListPattern with nested VariablePatterns

  iex> # Cons pattern: [head | tail]
  iex> ast = [{:|, [], [{:head, [], Elixir}, {:tail, [], Elixir}]}]
  iex> build_list_pattern(ast, expr_iri, context)
  # Creates ListPattern with head and tail patterns

"""
defp build_list_pattern(ast, expr_iri, context) do
  # Create the ListPattern type triple
  type_triple = Helpers.type_triple(expr_iri, Core.ListPattern)

  # Check for cons pattern vs flat list
  child_triples =
    if cons_pattern?(ast) do
      build_cons_list_pattern(ast, context)
    else
      {triples, _ctx} = build_child_patterns(ast, expr_iri, context)
      triples
    end

  # Include type triple and all child pattern triples
  [type_triple | child_triples]
end

# Helper to build cons pattern [head | tail]
# Builds head and tail as separate child patterns
defp build_cons_list_pattern([{:|, _, [head, tail]}], context) do
  # Build head pattern
  {:ok, {_head_iri, _head_expr_triples, context_after_head}} = build(head, context, [])
  head_triples = build_pattern(head, _head_iri, context_after_head)

  # Build tail pattern
  {:ok, {_tail_iri, _tail_expr_triples, context_after_tail}} = build(tail, context_after_head, [])
  tail_triples = build_pattern(tail, _tail_iri, context_after_tail)

  # Combine head and tail pattern triples
  head_triples ++ tail_triples
end
```

### Step 3: Add Unit Tests

**File:** `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`

Add tests in a new `describe "tuple pattern extraction"` block:

```elixir
describe "tuple pattern extraction" do
  test "builds TuplePattern for empty tuple" do
    context = full_mode_context()
    # Empty tuple AST: {:{}, [], []}
    ast = {:{}, [], []}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have TuplePattern type
    assert has_type?(pattern_triples, Core.TuplePattern)

    # Empty tuple has only type triple (no child patterns)
    assert length(pattern_triples) == 1
  end

  test "builds TuplePattern for 2-tuple with variables" do
    context = full_mode_context()
    # 2-tuple AST: {x, y}
    ast = {{:x, [], Elixir}, {:y, [], Elixir}}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have TuplePattern type
    assert has_type?(pattern_triples, Core.TuplePattern)

    # Should have nested VariablePatterns
    assert has_type?(pattern_triples, Core.VariablePattern)
  end

  test "builds TuplePattern for n-tuple with literals" do
    context = full_mode_context()
    # n-tuple AST: {1, :ok, "hello"}
    ast = {:{}, [], [1, {:ok, [], nil}, "hello"]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have TuplePattern type
    assert has_type?(pattern_triples, Core.TuplePattern)

    # Should have nested LiteralPatterns
    assert has_type?(pattern_triples, Core.LiteralPattern)
  end

  test "builds TuplePattern with wildcard" do
    context = full_mode_context()
    # Tuple with wildcard: {:ok, _}
    ast = {:{}, [], [{:ok, [], nil}, {:_}]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have TuplePattern type
    assert has_type?(pattern_triples, Core.TuplePattern)

    # Should have WildcardPattern
    assert has_type?(pattern_triples, Core.WildcardPattern)
  end

  test "builds TuplePattern with pin pattern" do
    context = full_mode_context()
    # Tuple with pin: {^x, y}
    ast = {:{}, [], [{:^, [], [{:x, [], Elixir}]}, {:y, [], Elixir}]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have TuplePattern type
    assert has_type?(pattern_triples, Core.TuplePattern)

    # Should have PinPattern
    assert has_type?(pattern_triples, Core.PinPattern)
  end

  test "builds nested tuple patterns" do
    context = full_mode_context()
    # Nested tuple: {{a, b}, c}
    inner_tuple = {:{}, [], [{:a, [], Elixir}, {:b, [], Elixir}]}
    ast = {:{}, [], [inner_tuple, {:c, [], Elixir}]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have TuplePattern type
    assert has_type?(pattern_triples, Core.TuplePattern)
    # Nested tuples should create multiple TuplePattern instances
    tuple_pattern_count = Enum.count(pattern_triples, fn {_s, p, o} ->
      p == RDF.type() and o == Core.TuplePattern
    end)
    assert tuple_pattern_count >= 2
  end
end
```

Add tests in a new `describe "list pattern extraction"` block:

```elixir
describe "list pattern extraction" do
  test "builds ListPattern for empty list" do
    context = full_mode_context()
    # Empty list AST: []
    ast = []
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have ListPattern type
    assert has_type?(pattern_triples, Core.ListPattern)

    # Empty list has only type triple (no child patterns)
    assert length(pattern_triples) == 1
  end

  test "builds ListPattern for flat list with variables" do
    context = full_mode_context()
    # Flat list AST: [x, y, z]
    ast = [{:x, [], Elixir}, {:y, [], Elixir}, {:z, [], Elixir}]
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have ListPattern type
    assert has_type?(pattern_triples, Core.ListPattern)

    # Should have nested VariablePatterns
    assert has_type?(pattern_triples, Core.VariablePattern)
  end

  test "builds ListPattern for list with literals" do
    context = full_mode_context()
    # List with literals: [1, 2, 3]
    ast = [1, 2, 3]
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have ListPattern type
    assert has_type?(pattern_triples, Core.ListPattern)

    # Should have nested LiteralPatterns
    assert has_type?(pattern_triples, Core.LiteralPattern)
  end

  test "builds ListPattern with cons pattern" do
    context = full_mode_context()
    # Cons pattern: [head | tail]
    # AST: [{:|, [], [{:head, [], Elixir}, {:tail, [], Elixir}]}]
    ast = [{:|, [], [{:head, [], Elixir}, {:tail, [], Elixir}]}]
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have ListPattern type
    assert has_type?(pattern_triples, Core.ListPattern)

    # Should have VariablePatterns for head and tail
    assert has_type?(pattern_triples, Core.VariablePattern)
  end

  test "builds ListPattern with wildcard in cons" do
    context = full_mode_context()
    # Cons with wildcard: [_ | tail]
    ast = [{:|, [], [{:_}, {:tail, [], Elixir}]}]
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have ListPattern type
    assert has_type?(pattern_triples, Core.ListPattern)

    # Should have WildcardPattern
    assert has_type?(pattern_triples, Core.WildcardPattern)
  end

  test "builds nested list patterns" do
    context = full_mode_context()
    # Nested list: [[a, b], [c, d]]
    inner_list_1 = [{:a, [], Elixir}, {:b, [], Elixir}]
    inner_list_2 = [{:c, [], Elixir}, {:d, [], Elixir}]
    ast = [inner_list_1, inner_list_2]
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have ListPattern type
    assert has_type?(pattern_triples, Core.ListPattern)
    # Nested lists should create multiple ListPattern instances
    list_pattern_count = Enum.count(pattern_triples, fn {_s, p, o} ->
      p == RDF.type() and o == Core.ListPattern
    end)
    assert list_pattern_count >= 2
  end
end
```

Add tests for mixed nested patterns:

```elixir
describe "mixed nested pattern extraction" do
  test "builds tuple within list pattern" do
    context = full_mode_context()
    # List containing tuple: [{x, y}, z]
    tuple_pattern = {{:x, [], Elixir}, {:y, [], Elixir}}
    ast = [tuple_pattern, {:z, [], Elixir}]
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have ListPattern (outer)
    assert has_type?(pattern_triples, Core.ListPattern)
    # Should have TuplePattern (nested)
    assert has_type?(pattern_triples, Core.TuplePattern)
  end

  test "builds list within tuple pattern" do
    context = full_mode_context()
    # Tuple containing list: {[x, y], z}
    list_pattern = [{:x, [], Elixir}, {:y, [], Elixir}]
    ast = {:{}, [], [list_pattern, {:z, [], Elixir}]}
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have TuplePattern (outer)
    assert has_type?(pattern_triples, Core.TuplePattern)
    # Should have ListPattern (nested)
    assert has_type?(pattern_triples, Core.ListPattern)
  end

  test "builds deeply nested pattern structures" do
    context = full_mode_context()
    # Complex nested: [{a, [b, c]}, {d, [e, f]}]
    inner_list_1 = [{:b, [], Elixir}, {:c, [], Elixir}]
    inner_list_2 = [{:e, [], Elixir}, {:f, [], Elixir}]
    tuple_1 = {{:a, [], Elixir}, inner_list_1}
    tuple_2 = {{:d, [], Elixir}, inner_list_2}
    ast = [tuple_1, tuple_2]
    {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(ast, context, [])

    pattern_triples = ExpressionBuilder.build_pattern(ast, expr_iri, context)

    # Should have both ListPattern and TuplePattern
    assert has_type?(pattern_triples, Core.ListPattern)
    assert has_type?(pattern_triples, Core.TuplePattern)
  end
end
```

### Step 4: Run Verification

4.1 Run `mix test test/elixir_ontologies/builders/expression_builder_test.exs`
4.2 Verify new pattern extraction tests pass
4.3 Verify no regressions in existing tests

## 4. Technical Details

### File Locations

**Implementation:**
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex`
  - Replace `build_tuple_pattern/3` at lines 1333-1335
  - Replace `build_list_pattern/3` at lines 1338-1340
  - Add `extract_tuple_elements/1` helper function
  - Add `build_child_patterns/1` helper function
  - Add `build_cons_list_pattern/2` helper function

**Tests:**
- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs`
  - Add `describe "tuple pattern extraction"` block after existing pattern tests (around line 3220)
  - Add `describe "list pattern extraction"` block
  - Add `describe "mixed nested pattern extraction"` block

**Ontology Reference:**
- `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl`
  - `Core.TuplePattern` at lines 369-372
  - `Core.ListPattern` at lines 374-378

### Ontology Classes and Properties

**Existing Classes:**
- `Core.TuplePattern` (line 369-372) - A pattern matching a tuple structure with nested patterns
- `Core.ListPattern` (line 374-378) - A pattern matching list structure, including head|tail decomposition patterns

**Existing Properties:**
- `Core.hasChild` (line 544-548) - Links a node to its children in the AST (implicit via child expression IRIs)
- `Core.hasHead`, `Core.hasTail` - NOT currently defined in ontology (for future cons pattern property support)

**Note:** The current implementation does NOT explicitly add `hasHead` or `hasTail` properties for cons patterns. This is consistent with the existing `build_cons_list/3` function which notes these properties would need to be added to the ontology. Child patterns are implicitly linked via their IRIs.

### AST Structure Reference

| Pattern Type | AST Form | Example |
|--------------|----------|---------|
| Empty tuple | `{:{}, [], []}` | `{}` |
| 2-tuple | `{left, right}` | `{1, 2}` |
| n-tuple (n >= 3) | `{:{}, _, elements}` | `{1, 2, 3}` |
| Empty list | `[]` | `[]` |
| Flat list | `[elements]` | `[1, 2, 3]` |
| Cons pattern | `[{:|, _, [head, tail]}]` | `[h | t]` |

### Helper Functions

**Existing from `ExpressionBuilder`:**
- `build_child_expressions/3` (line 709-717) - For building child expressions (NOT patterns)
- `cons_pattern?/1` (line 703-704) - Checks if list is a cons pattern
- `build/3` - For generating IRIs and building expressions
- `build_pattern/3` - For building patterns (to be used recursively)

**New Helpers to Add:**
- `extract_tuple_elements/1` - Extracts elements from tuple AST (handles 2-tuple and n-tuple)
- `build_child_patterns/1` - Builds child patterns using recursive `build_pattern/3` calls
- `build_cons_list_pattern/2` - Builds cons pattern head and tail separately

## 5. Success Criteria

1. **Tuple pattern extraction:**
   - Empty tuple `{}` creates `Core.TuplePattern` with only type triple
   - 2-tuple `{x, y}` creates `Core.TuplePattern` with nested `VariablePattern` children
   - n-tuple `{1, :ok, x}` creates `Core.TuplePattern` with mixed nested patterns
   - Tuples with wildcards `{x, _}` handled correctly
   - Tuples with pin patterns `{^x, y}` handled correctly

2. **List pattern extraction:**
   - Empty list `[]` creates `Core.ListPattern` with only type triple
   - Flat list `[x, y, z]` creates `Core.ListPattern` with nested patterns
   - Cons pattern `[h | t]` creates `Core.ListPattern` with head and tail patterns
   - Cons with wildcard `[_ | t]` handled correctly

3. **Nested patterns:**
   - Tuple within tuple `{{a, b}, c}` creates nested `TuplePattern` instances
   - List within list `[[a, b], [c, d]]` creates nested `ListPattern` instances
   - Tuple in list `[{x, y}, z]` creates both `ListPattern` and `TuplePattern`
   - List in tuple `{[x, y], z}` creates both `TuplePattern` and `ListPattern`

4. **Tests pass:**
   - All new tuple pattern tests pass (6 tests)
   - All new list pattern tests pass (6 tests)
   - All mixed nested pattern tests pass (3 tests)
   - No regressions in existing tests (264+ tests)

5. **Code quality:**
   - Functions follow existing code style
   - Proper documentation added with @doc and examples
   - DRY principle followed (reuse `cons_pattern?/1`, create reusable helpers)
   - Context threading handled correctly

## 6. Notes and Considerations

### 6.1 Pattern vs Expression Context

The same AST structure can represent either an expression or a pattern:
- `{:{}, [], [1, 2]}` - `TupleLiteral` in expression context, `TuplePattern` in pattern context
- `[1, 2, 3]` - `ListLiteral` in expression context, `ListPattern` in pattern context

The `build_pattern/3` function assumes the caller knows this is a pattern context. The implementation uses `build/3` to get IRIs for child elements, then calls `build_pattern/3` recursively to ensure pattern context is maintained.

### 6.2 Cons Pattern Handling

The cons pattern `[h | t]` is represented as `[{:|, _, [h, t]}]` - a list containing a single 3-tuple with the `:|` atom. The existing `cons_pattern?/1` helper correctly identifies this.

**Note:** The ontology does NOT currently define `hasHead` or `hasTail` properties for cons patterns. The implementation creates child patterns but does not explicitly link them with these properties. This is consistent with the existing `build_cons_list/3` approach.

### 6.3 2-Tuple Special Case

The 2-tuple `{left, right}` is a direct 2-element tuple, not a 3-tuple AST form. The `extract_tuple_elements/1` helper handles both forms:
- `{:{}, _, elements}` for n >= 3 (and empty tuple)
- `{left, right}` for n = 2

### 6.4 Child Pattern Building

The new `build_child_patterns/1` helper differs from `build_child_expressions/3`:
- `build_child_expressions/3` uses `build/3` for expression context
- `build_child_patterns/1` uses `build/3` for IRI generation, then `build_pattern/3` for pattern context

This ensures that nested elements are correctly represented as patterns, not expressions.

### 6.5 Future Integration Points

These pattern builders will be used by:
- Function clause parameter extractors
- Case expression clause extractors
- Match expression handlers
- For comprehension generators
- Receive pattern matching

## 7. Progress Tracking

- [x] 7.1 Create feature branch `feature/phase-24-4-tuple-list-patterns`
- [x] 7.2 Create planning document
- [x] 7.3 Implement `build_tuple_pattern/3` with nested pattern support
- [x] 7.4 Implement `build_list_pattern/3` with nested pattern support
- [x] 7.5 Add `extract_tuple_elements/1` helper function
- [x] 7.6 Add `build_child_patterns/1` helper function
- [x] 7.7 Add `build_cons_list_pattern/2` helper function
- [x] 7.8 Add tuple pattern extraction tests (6 tests)
- [x] 7.9 Add list pattern extraction tests (6 tests)
- [x] 7.10 Add mixed nested pattern tests (3 tests)
- [x] 7.11 Run verification
- [x] 7.12 Write summary document
- [ ] 7.13 Ask for permission to commit and merge

## 8. Status Log

### 2026-01-12 - Initial Planning
- Analyzed Phase 24.4 requirements
- Studied existing `build_tuple_literal/3` and `build_list_literal/3` implementations
- Reviewed `build_cons_list/3` for cons pattern handling
- Examined `build_child_expressions/3` for child building patterns
- Reviewed `cons_pattern?/1` helper function
- Checked ontology for `TuplePattern` and `ListPattern` definitions
- Reviewed existing test patterns from Phase 24.1-24.3
- Created planning document

### 2026-01-12 - Implementation Complete
- Implemented `build_tuple_pattern/3` with full nested pattern support
- Implemented `build_list_pattern/3` with cons pattern and nested pattern support
- Added `extract_tuple_elements/1` helper for both 2-tuple and n-tuple forms
- Added `build_child_patterns/2` helper for recursive pattern building
- Added `build_cons_list_pattern/2` helper for cons cell handling
- Fixed bug in `detect_pattern_type/1` for 2-tuple detection with variable elements
- Added 15 new tests (6 tuple, 6 list, 3 mixed nested)
- Total: 279 tests, 0 failures
- Summary document created at `notes/summaries/phase-24-4-tuple-list-patterns.md`

---

### Critical Files for Implementation

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/expression_builder.ex` - Main implementation file; replace `build_tuple_pattern/3` (lines 1333-1335), replace `build_list_pattern/3` (lines 1338-1340), add helper functions `extract_tuple_elements/1`, `build_child_patterns/1`, `build_cons_list_pattern/2`

- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/expression_builder_test.exs` - Test file; add new describe blocks after existing pattern tests (around line 3220)

- `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl` - Reference for pattern classes; `TuplePattern` at lines 369-372, `ListPattern` at lines 374-378

- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex` - Helper functions for RDF triple creation; `type_triple/2`, `datatype_property/4`

- `/home/ducky/code/elixir-ontologies/notes/features/phase-24-2-literal-variable-patterns.md` - Reference for test helper functions and patterns
