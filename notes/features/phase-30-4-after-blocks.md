# Phase 30.4: After Block Expression Extraction

**Feature Branch:** `feature/phase-30-4-after-blocks`
**Created:** 2026-01-18
**Based On:** Phase 30 Expressions Plan (`notes/planning/expressions/phase-30.md`)

---

## Problem Statement

Phase 30.4 implements extraction for after blocks in try expressions. After blocks contain code that always executes regardless of whether an exception occurred, making them critical for cleanup and resource management.

### Current State
- Phase 30.1 implemented basic try expression structure with `hasTryBody`
- Phase 30.2 implemented rescue clause extraction
- Phase 30.3 implemented catch clause extraction
- The `hasAfterClause` property exists in ontology but is a boolean flag
- After blocks are detected but not extracted yet

### Requirements
1. Extract after block expression from try expressions
2. The after block always executes (even when exceptions occur)
3. Handle single-expression after blocks
4. Handle multi-expression after blocks (wrapped in do block)
5. Link via `hasAfterClause` object property (already exists)

---

## Solution Overview

Implement after block extraction in ExpressionBuilder:

### After Block Structure
- The after block is a single expression (or block for multiple expressions)
- Linked via `hasAfterClause` functional property (one-to-one)
- No ordering needed (only one after block per try)

### IRI Structure
- After block: `{try_iri}/after`

---

## Technical Details

### Files to Modify

| File | Changes | Purpose |
|------|---------|---------|
| `lib/elixir_ontologies/builders/expression_builder.ex` | Implement after block extraction | Core functionality |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add after block tests | Test coverage |

Note: The ontology already has `hasAfterClause` property defined. We just need to use it.

### AST Pattern for After Blocks

```elixir
# After block format in try AST
{:try, [],
 [[
   do: :body,
   after: :single_expression
 ]]}

# Multiple expressions:
{:try, [],
 [[
   do: :body,
   after: {:__block__, [], [:expr1, :expr2]}
 ]]}
```

### After Block Examples

```elixir
# Single expression after
try do
  risky()
after
  cleanup()
end

# Multiple expressions after
try do
  risky()
after
  cleanup1()
  cleanup2()
end

# Empty after block (rare but valid)
try do
  risky()
after
end
```

---

## Implementation Plan

### 1.0 After Block Detection
- [x] 1.1 Create feature branch `feature/phase-30-4-after-blocks`
- [x] 1.2 Create planning document
- [x] 1.3 Update `detect_optional_blocks/3` to call after extraction
- [x] 1.4 Implement `build_after_blocks/3` function
- [x] 1.5 Extract after from try blocks: `Keyword.get(blocks, :after)`
- [x] 1.6 Handle nil after (no after block)

### 2.0 After Block Builder
- [x] 2.1 Implement `build_after_block/4` function
- [x] 2.2 Generate after IRI: `fresh_iri(try_iri, "after")`
- [x] 2.3 Extract after block expression via `build_expression_triples/3`
- [x] 2.4 Link via `hasAfterClause` property
- [x] 2.5 Handle single expression after
- [x] 2.6 Handle multi-expression after (already wrapped in block by compiler)

### 3.0 Unit Tests
- [x] 3.1 Test after block extraction for single expression
- [x] 3.2 Test after block extraction for multiple expressions
- [x] 3.3 Test after block creates correct structure
- [x] 3.4 Test try without after block

### 4.0 Final Verification
- [x] 4.1 Run all tests
- [x] 4.2 Verify no regressions
- [x] 4.3 Create summary document
- [x] 4.4 Mark tasks complete in plan
- [ ] 4.5 Ask for commit and merge permission

---

## Success Criteria

1. **After block detection** - Correctly identify and extract after blocks
2. **Expression extraction** - Extract after block expressions
3. **Multi-expression support** - Handle multiple expressions (compiler wraps in block)
4. **Property linking** - Link via `hasAfterClause` object property
5. **Test coverage** - 4+ unit tests covering all scenarios
6. **Integration** - Works with existing try expression structure

---

## Notes and Considerations

### After Block Semantics
- After blocks ALWAYS execute, even when:
  - No exception occurs
  - An exception is raised
  - A value is thrown
  - An error is caught
- This makes them ideal for cleanup (closing files, releasing resources, etc.)

### AST Structure
- The Elixir compiler automatically wraps multiple expressions in a `{:__block__, [], [...]}` tuple
- We can use `build_expression_triples/3` directly on the after AST
- No special handling needed for multi-expression cases

### Property Type
- `hasAfterClause` is a FunctionalProperty (only one after per try)
- It's an ObjectProperty (links to a Block or other expression)

### Integration Point
- After extraction goes in `detect_optional_blocks/3` alongside rescue and catch
- Order: rescue, catch, after (future: else)

---

## Current Status

**Status:** ✅ COMPLETE - Ready for commit and merge

**What Works:**
- After block extraction fully implemented
- `build_after_block/3` function handles single and multi-expression after blocks
- After blocks are linked via `hasAfterClause` object property
- Multi-expression after blocks automatically wrapped in DoBlock by compiler
- 4 unit tests covering all after block scenarios (all passing)
- Proper IRI structure: `{try_iri}/after`

**Test Results:**
- 429 tests total (added 4 after block tests)
- 4 after block tests: all passing
- 1 pre-existing test failure (unrelated to Phase 30.4)

**Decisions Made:**
- Reuse existing `hasAfterClause` property (no ontology changes needed)
- After block is a single expression (compiler wraps multiple in block)
- Simple implementation using existing `build_expression_triples/3`

---

*Last Updated:* 2026-01-18
*Branch:* feature/phase-30-4-after-blocks
*Status:* COMPLETE
