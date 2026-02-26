# Phase 27.5: Block Return Values and Side Effects

**Feature Branch:** `feature/phase-27-5-block-return-values`
**Created:** 2026-01-15
**Based On:** Phase 27 Expressions Plan (Section 27.5)

---

## Problem Statement

The ExpressionBuilder currently extracts block expressions (do blocks, fn blocks) but does not explicitly identify which expression is the return value. In Elixir, the last expression in a block is its implicit return value, but this relationship is not captured in the RDF graph. Additionally, early exit expressions (throw, raise) can change the actual return value.

Without explicit return value tracking, we cannot:
- Query for what value a block returns
- Distinguish between side-effecting expressions and the return value
- Analyze data flow from block return values
- Handle early exit expressions correctly

---

## Solution Overview

Add explicit return value tracking for block expressions:

1. **Add `Core.hasReturnExpression` property** to the ontology
2. **Modify `build_do_block/5`** to link the last expression as return value
3. **Modify `build_fn_clause/5`** to link the body's return value
4. **Handle early exit detection** - if throw/raise is detected, that becomes the return expression
5. **Add unit tests** for return value extraction

---

## Technical Details

### Ontology Addition

Add to `ontology/elixir-core.ttl` in the "Block and scope properties" section (after line 687):

```turtle
:hasReturnExpression a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:label "has return expression"@en ;
    rdfs:comment "Links a block to the expression that provides its return value. Typically the last expression, but may be an early exit expression (throw/raise)."@en ;
    rdfs:subPropertyOf :hasChild ;
    rdfs:domain :Block ;
    rdfs:range :Expression .
```

### ExpressionBuilder Changes

**File:** `lib/elixir_ontologies/builders/expression_builder.ex`

#### 1. Modify `build_do_block/5`

After building child triples, identify the last expression and add a `hasReturnExpression` link:

```elixir
defp build_do_block(expressions, block_iri, context, _depth, _max_depth) do
  type_triple = Helpers.type_triple(block_iri, Core.DoBlock)

  # ... build child triples ...

  # Add return expression link (last child)
  return_triple =
    if length(expressions) > 0 do
      last_child_iri = fresh_iri(block_iri, "child/#{length(expressions) - 1}")
      Helpers.object_property(block_iri, Core.hasReturnExpression(), last_child_iri)
    else
      []
    end

  [type_triple | child_triples] ++ [return_triple]
end
```

#### 2. Modify `build_fn_clause/5`

For fn blocks, the body IRI is already being generated. We need to check if the body is a block and preserve its return expression link, or link the body itself as the return value.

The current implementation already creates a `body_iri`. We need to add a return expression link to it.

#### 3. Early Exit Detection (Optional/Advanced)

Detect early exit expressions by checking for:
- `:throw` calls
- `:raise` calls
- `:exit` calls

If any of these are found in the expression list, they become the return expression instead of the last expression.

### IRI Generation Pattern

For a do block at `https://example.org/code#expr/0`:
- Do block IRI: `https://example.org/code#expr/0`
- Child IRIs: `expr/0/child/0`, `expr/0/child/1`, etc.
- Return expression: `expr/0/child/1` (last child)

### Files to Modify

| File | Changes |
|------|---------|
| `ontology/elixir-core.ttl` | Add `hasReturnExpression` property |
| `lib/elixir_ontologies/builders/expression_builder.ex` | Modify `build_do_block/5` and `build_fn_clause/5` |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add return value tests |

---

## Implementation Plan

### Step 1: Add Ontology Property

1. Add `hasReturnExpression` to `ontology/elixir-core.ttl`
2. Verify the ontology is valid (mix compile)

### Step 2: Modify `build_do_block/5`

1. Add logic to identify the last child IRI
2. Add `hasReturnExpression` triple
3. Handle empty blocks (no return expression)
4. Run tests to verify

### Step 3: Modify `build_fn_clause/5`

1. The body is already linked via `hasChild`
2. Add explicit `hasReturnExpression` link to the body IRI
3. Run tests to verify

### Step 4: Add Unit Tests

**Tests to add:**
1. Test do block with single expression - that expression is the return value
2. Test do block with multiple expressions - last expression is return value
3. Test do block with empty block - no return expression
4. Test fn block body - body is linked as return value
5. Test nested blocks - inner block has its own return expression

### Step 5: Early Exit Detection (Optional)

1. Detect `throw`, `raise`, `exit` calls
2. If found, that becomes the return expression
3. Add tests for early exit scenarios

---

## Success Criteria

- [x] `hasReturnExpression` property added to ontology
- [x] `build_do_block/5` links last expression as return value
- [x] `build_fn_clause/5` links body as return value
- [x] Empty blocks have no return expression link
- [x] Unit tests added and passing
- [ ] Early exit expressions detected (optional - not implemented)
- [x] All expression builder tests passing

---

## Current Status

**Status:** ✅ COMPLETE

**What was done:**
1. Added `hasReturnExpression` property to `ontology/elixir-core.ttl` (line 693-698)
2. Copied ontology to `priv/ontologies/` for namespace generation
3. Modified `build_do_block/5` to link last expression via `hasReturnExpression`
4. Modified `build_fn_clause/5` to link body via `hasReturnExpression`
5. Added unit tests:
   - "do block extraction identifies return expression (last one)"
   - "do block extraction with single expression has return expression"
   - "do block extraction for empty block has no return expression"
   - "fn block extraction has return expression link to body"
   - "fn block extraction with multiple clauses each has return expression"
   - "fn block extraction with guard has return expression"
6. Added `find_object/3` helper function to test module
7. Fixed regex delimiter issues (changed `~r"/body$/` to `~r|/body$|`)

**Test Results:**
```
9 doctests, 363 tests, 0 failures
```
- Previous test count: 358 tests (9 doctests)
- New test count: 363 tests (9 doctests)
- Tests added: 5 (2 do block, 3 fn block)
- All expression builder tests passing

**How to run tests:**
```bash
# Run expression builder tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs

# Run only do block tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs --only do_blocks

# Run only fn block tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs --only fn_blocks
```

---

## Notes

1. **Functional Property:** `hasReturnExpression` is marked as `owl:FunctionalProperty` because a block can only have one return expression.

2. **SubProperty of hasChild:** Since the return expression is already a child, `hasReturnExpression` is a sub-property of `hasChild` for semantic clarity.

3. **Empty Blocks:** Empty blocks return `nil` in Elixir, but we won't create a return expression link for empty blocks - the absence of the property indicates no explicit return value.

4. **Early Exit:** Early exit expressions (`throw`, `raise`, `exit`) are implemented as function calls in the AST. Detecting them requires pattern matching on the expression AST.

5. **Fn Block Bodies:** The body of an fn clause can be a single expression or a block. If it's a block, it will have its own return expression. We should link the body itself as the return expression of the clause.

---

*Last Updated:* 2026-01-15
*Branch:* feature/phase-27-5-block-return-values
