# Phase 27.2: Do Block Expression Extraction

**Feature Branch:** `feature/phase-27-2-do-block-extraction`
**Created:** 2026-01-15
**Based On:** Phase 27 Expressions Plan (Section 27.2)

---

## Problem Statement

The ExpressionBuilder currently can detect block types (Phase 27.1) but cannot extract RDF triples for do blocks. Do blocks are fundamental to Elixir code structure - they appear in:
- Function bodies (multi-statement functions)
- Control flow constructs (if, case, cond, for, etc.)
- Anonymous function bodies
- Various macro expansions

Without do block extraction, we cannot represent:
- Multi-statement function bodies
- Expression sequences with side effects
- Control flow structures with multiple branches
- Block-level return values

---

## Solution Overview

Implement RDF triple extraction for do blocks (`{:__block__, _, expressions}`):

1. **Add `build_do_block/4`** - Extract do blocks as `Core.DoBlock`
2. **Use existing `hasChild` property** - Link child expressions (no new ontology properties needed)
3. **Mark return expression** - Use position index to identify final expression
4. **Preserve expression order** - Use index-based IRIs for ordering

---

## Technical Details

### Ontology Usage

- **Type:** `Core.DoBlock` (already exists in elixir-core.ttl)
- **Child linking:** `Core.hasChild` (already exists)
- **Return detection:** Last expression (highest index) is the return value

### IRI Generation Pattern

For a block at `https://example.org/code#expr/0`:
- Block IRI: `https://example.org/code#expr/0`
- Child expression IRIs: `expr/0/expr/0`, `expr/0/expr/1`, etc.
- Or simpler: `expr/0/child/0`, `expr/0/child/1`, etc.

### Expression Sequence Handling

Single-expression block:
```elixir
# do
#   x + 1
# end
{:__block__, [], [{:+, [], [{:x, [], nil}, 1]}]}
```

Multi-expression block:
```elixir
# do
#   x = 1
#   x + 2
# end
{:__block__, [], [{:=, [], [{:x, [], nil}, 1]}, {:+, [], [{:x, [], nil}, 2]}]}
```

Empty block:
```elixir
# do
# end
{:__block__, [], []}
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/elixir_ontologies/builders/expression_builder.ex` | Add do block builder and dispatch |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add do block extraction tests |

---

## Implementation Plan

### Step 1: Add `build_do_block/5` Helper

**Location:** `lib/elixir_ontologies/builders/expression_builder.ex`

**Signature:**
```elixir
@spec build_do_block(list(), RDF.IRI.t(), Context.t(), non_neg_integer() | nil, non_neg_integer()) :: list()
defp build_do_block(expressions, block_iri, context, depth \\ 0, max_depth \\ @max_pattern_depth)
```

**Implementation:**
1. Check depth limit for nested blocks
2. Create type triple: `block_iri a Core.DoBlock`
3. For each expression, generate child IRI and extract recursively
4. Link child expressions via `Core.hasChild`
5. Return all triples

### Step 2: Add `{:__block__, _, _}` Dispatch

**Location:** In `build_expression_triples/3`

Add pattern match before the catch-all clause:
```elixir
def build_expression_triples({:__block__, _, expressions} = ast, expr_iri, context) do
  build_do_block(expressions, expr_iri, context)
end
```

### Step 3: Add Unit Tests

**Tests to add:**
1. Test do block extraction for single expression
2. Test do block extraction for multiple expressions
3. Test do block extraction preserves expression order
4. Test do block extraction identifies return expression (last one)
5. Test do block extraction handles empty blocks
6. Test do block extraction handles nested blocks

---

## Success Criteria

- [x] `build_do_block/5` extracts do blocks as `Core.DoBlock`
- [x] Child expressions linked via `Core.hasChild`
- [x] Expression order preserved via index-based IRIs
- [x] Last expression identifiable as return value
- [x] Empty blocks handled gracefully
- [x] Nested blocks handled (with depth limit)
- [x] All unit tests passing

---

## Current Status

**Status:** ✅ COMPLETE

**What was done:**
1. Added `build_do_block/5` helper function (lines 320-354)
   - Three clauses: depth limit check, empty block check, and main implementation
   - Creates `Core.DoBlock` type triple
   - Generates child IRIs using `fresh_iri(block_iri, "child/#{index}")` pattern
   - Recursively builds child expressions using `build_expression_triples/3`
   - Links children via `Core.hasChild()` property

2. Added `{:__block__, _, _}` dispatch to `build_expression_triples/3` (lines 630-635)
   - Placed **before** the local call handler to avoid being matched as `:__block__` function call
   - Pattern: `{:__block__, _meta, expressions}`

3. Added 6 unit tests for do block extraction (lines 4715-4889)
   - Single expression do block
   - Multiple expressions do block
   - Expression order preservation
   - Return expression identification (last child)
   - Empty block handling
   - Nested block handling

4. Added `find_all_objects/3` helper function to test file

**Test Results:**
```
9 doctests, 350 tests, 0 failures
```
- Previous test count: 344 tests (9 doctests)
- New test count: 350 tests (9 doctests)
- Tests added: 6
- All expression builder tests passing

**How to run tests:**
```bash
# Run expression builder tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs

# Run only do block tests
mix test test/elixir_ontologies/builders/expression_builder_test.exs --only do_blocks
```

---

## Design Notes

1. **Placement before local call handler:** The `{:__block__, _, _}` pattern must come before the local call handler (`{function, meta, args}`) because `{:__block__, [], expressions}` also matches the pattern `{function, meta, args}` where `function = :__block__`, `meta = []`, and `args = [expressions]`.

2. **Index-based IRI pattern:** Child IRIs use the pattern `block_iri/child/{index}` where `index` starts at 0. This preserves expression order and allows identification of the return value (highest index).

3. **Depth limiting:** The function accepts optional `depth` and `max_depth` parameters (defaulting to 0 and 100 respectively) to prevent infinite recursion in deeply nested blocks.

4. **Empty blocks:** An empty block `{:__block__, [], []}` is still a valid `DoBlock` with no children.

---

*Last Updated:* 2026-01-15
*Branch:* feature/phase-27-2-do-block-extraction
