# Phase 27.6: Block Nesting and Scope

**Feature Branch:** `feature/phase-27-6-block-nesting-scope`
**Created:** 2026-01-15
**Based On:** Phase 27 Expressions Plan (Section 27.6)

---

## Problem Statement

The ExpressionBuilder currently extracts block expressions (do blocks, fn blocks) with nested blocks working through recursive `build_expression_triples/3` calls. However, we need to:

1. **Verify nested block handling is complete** - Ensure all nesting scenarios work correctly
2. **Verify IRI hierarchy follows nesting structure** - Parent-child relationships must be preserved
3. **Document scope boundaries** - Blocks create lexical scope boundaries for future variable extraction
4. **Track nesting depth** - For potential analysis and validation

The current implementation already handles basic nesting recursively, but we need comprehensive test coverage and documentation.

---

## Solution Overview

Phase 27.6 is primarily about **verification and documentation** rather than new implementation:

1. **Add comprehensive nested block tests** - Cover all nesting scenarios
2. **Verify IRI hierarchy** - Ensure parent-child relationships are correct
3. **Document scope boundaries** - Add comments about lexical scope
4. **Track nesting depth** - Add depth tracking to block builders for future analysis

---

## Technical Details

### Existing Implementation

The current `build_expression_triples/3` function already handles nesting recursively:

```elixir
# From build_do_block/5
child_triples =
  expressions
  |> Enum.with_index()
  |> Enum.flat_map(fn {expr_ast, index} ->
    child_iri = fresh_iri(block_iri, "child/#{index}")
    expr_triples = build_expression_triples(expr_ast, child_iri, context)  # Recursive call
    # ...
  end)
```

This means:
- Nested `{:__block__, _, _}` nodes are handled by the `{:fn, _, _}` dispatch
- Nested `{:fn, _, _}` nodes are handled recursively
- IRI hierarchy is automatically maintained via `fresh_iri/2` with relative paths

### IRI Hierarchy Pattern

For nested blocks:
```
expr/0                    - Outer DoBlock
  child/0                 - Nested DoBlock
    child/0               - Atom :a
  child/1                 - Atom :b
```

### Nesting Scenarios to Test

1. **Do within Do** - Nested do blocks
2. **Fn within Do** - Anonymous function inside do block
3. **Do within Fn** - Do block as fn body
4. **Fn within Fn** - Nested anonymous functions (closures)
5. **Mixed control flow** - Blocks within if/case/cond/receive

### Scope Boundaries

Elixir blocks create lexical scope boundaries:
- Variables defined in outer blocks are visible in inner blocks
- Variables defined in inner blocks shadow outer variables
- Fn blocks capture variables from outer scope (closures)

**Note:** Actual variable extraction is planned for a future phase. This phase only documents the scope structure.

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/expression_builder.ex` | Add nesting depth tracking |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add comprehensive nested block tests |

---

## Implementation Plan

### Step 1: Add Nesting Depth Tracking (Optional)

Add depth tracking to `build_do_block/5` and `build_fn_block/5`:

```elixir
defp build_do_block(expressions, block_iri, context, depth \\ 0, max_depth \\ 100) do
  # Add depth metadata
  depth_triple = Helpers.datatype_property(block_iri, Core.nestingDepth(), depth, RDF.XSD.Integer)

  # ... existing code ...

  [depth_triple | existing_triples]
end
```

**Decision:** Check if `Core.nestingDepth()` property exists in ontology first.

### Step 2: Add Comprehensive Nested Block Tests

**Tests to add:**

1. **"do block extraction handles deeply nested do blocks"**
   - 3 levels of nesting
   - Verify IRI hierarchy

2. **"do block extraction handles fn within do"**
   - Outer: do block, Inner: fn block
   - Verify both blocks have correct types

3. **"fn block extraction handles do block as body"**
   - Fn with multi-expression body (do block)
   - Verify body is DoBlock with return expression

4. **"fn block extraction handles nested fn (closures)"**
   - Outer fn, inner fn
   - Verify both are FnBlock type

5. **"mixed nesting preserves IRI hierarchy"**
   - Complex nesting scenario
   - Verify complete IRI path

### Step 3: Verify Existing Tests

Run existing nested block tests to ensure they still pass:
- "do block extraction handles nested blocks"
- "fn block extraction handles nested fn blocks"

### Step 4: Document Scope Boundaries

Add module documentation or comments about:
- Blocks create lexical scope boundaries
- Variable extraction is planned for future phase
- IRI hierarchy preserves nesting structure

---

## Success Criteria

- [x] Nesting depth tracking added (if ontology property exists)
- [x] Comprehensive nested block tests added
- [x] All nested block tests passing
- [x] IRI hierarchy verified for all nesting scenarios
- [x] Scope boundaries documented
- [x] All expression builder tests passing

---

## Current Status

**Status:** ✅ COMPLETE

**What was done:**
1. Created feature branch `feature/phase-27-6-block-nesting-scope`
2. Checked for `nestingDepth` property - not in ontology, skipped depth tracking
3. Added 6 comprehensive nested block tests
4. Verified IRI hierarchy for all nesting scenarios
5. Documented scope boundaries in planning document

**Test Results:**
```
9 doctests, 369 tests, 0 failures
```
- Previous test count: 363 tests (9 doctests)
- New test count: 369 tests (9 doctests)
- Tests added: 6
- All expression builder tests passing

**Tests Added:**
1. "do block extraction handles deeply nested do blocks (3 levels)"
2. "do block extraction handles fn within do"
3. "fn block extraction handles do block as body"
4. "fn block extraction handles nested fn (closures)"
5. "mixed nesting preserves IRI hierarchy"
6. "nested blocks each have their own return expression"

**How to run tests:**
```bash
# Run expression builder tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs

# Run only nested block tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs --only nested_blocks
```

---

## Notes

1. **Recursive Implementation:** The existing implementation already handles nesting correctly through recursive `build_expression_triples/3` calls.

2. **IRI Hierarchy:** The `fresh_iri/2` function with relative paths (`child/{index}`, `body`) automatically creates hierarchical IRIs.

3. **Depth Limiting:** Both `build_do_block/5` and `build_fn_block/5` already have depth limiting (default max_depth: 100).

4. **Future Variable Extraction:** Actual variable scope extraction is planned for a future phase. This phase focuses on structure and hierarchy.

5. **Test Coverage:** Existing tests cover basic nesting but not all scenarios like deeply nested blocks or mixed block types.

---

*Last Updated:* 2026-01-15
*Branch:* feature/phase-27-6-block-nesting-scope
