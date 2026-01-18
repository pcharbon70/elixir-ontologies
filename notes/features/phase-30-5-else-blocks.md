# Phase 30.5: Else Block Expression Extraction

**Feature Branch:** `feature/phase-30-5-else-blocks`
**Created:** 2026-01-18
**Based On:** Phase 30 Expressions Plan (`notes/planning/expressions/phase-30.md`)

---

## Problem Statement

Phase 30.5 implements extraction for else blocks in try expressions (Elixir 1.11+). Else blocks contain code that executes only when no exception occurs, providing an explicit success path separate from the try body.

### Current State
- Phase 30.1 implemented basic try expression structure with `hasTryBody`
- Phase 30.2 implemented rescue clause extraction
- Phase 30.3 implemented catch clause extraction
- Phase 30.4 implemented after block extraction
- The `hasElseClause` property exists in ontology but was incomplete (missing domain, range)

### Requirements
1. Complete the `hasElseClause` property definition in ontology
2. Extract else block expression from try expressions
3. The else block only executes when no exception occurs
4. Handle single-expression else blocks
5. Handle multi-expression else blocks (wrapped in do block by compiler)

---

## Solution Overview

Implement else block extraction in ExpressionBuilder:

### Else Block Structure
- The else block is a single expression (or block for multiple expressions)
- Linked via `hasElseClause` functional property (one-to-one)
- No ordering needed (only one else block per try)
- Executes only when no exception is raised

### IRI Structure
- Else block: `{try_iri}/else`

---

## Technical Details

### Files to Modify

| File | Changes | Purpose |
|------|---------|---------|
| `priv/ontologies/elixir-core.ttl` | Complete hasElseClause property definition | Ontology update |
| `lib/elixir_ontologies/builders/expression_builder.ex` | Implement else block extraction | Core functionality |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add else block tests | Test coverage |

### AST Pattern for Else Blocks

```elixir
# Else block format in try AST
{:try, [],
 [[
   do: :body,
   else: :single_expression
 ]]}

# Multiple expressions:
{:try, [],
 [[
   do: :body,
   else: {:__block__, [], [:expr1, :expr2]}
 ]]}
```

### Else Block Examples

```elixir
# Single expression else
try do
  result = risky()
else
  result
end

# Multiple expressions else
try do
  result = risky()
else
  log_success(result)
  result
end

# Else with pattern matching (rare but valid)
try do
  {:ok, value} = operation()
else
  {:error, _reason} -> :error
end
```

---

## Implementation Plan

### 1.0 Ontology Updates
- [x] 1.1 Create feature branch `feature/phase-30-5-else-blocks`
- [x] 1.2 Create planning document
- [x] 1.3 Complete hasElseClause property (add domain, range, FunctionalProperty)
- [x] 1.4 Add comment explaining else block semantics

### 2.0 Else Block Detection
- [x] 2.1 Update `detect_optional_blocks/3` to call else extraction
- [x] 2.2 Implement `build_else_blocks/3` function
- [x] 2.3 Extract else from try blocks: `Keyword.get(blocks, :else)`
- [x] 2.4 Handle nil else (no else block)

### 3.0 Else Block Builder
- [x] 3.1 Implement `build_else_block/4` function
- [x] 3.2 Generate else IRI: `fresh_iri(try_iri, "else")`
- [x] 3.3 Extract else block expression via `build_expression_triples/3`
- [x] 3.4 Link via `hasElseClause` property
- [x] 3.5 Handle single expression else
- [x] 3.6 Handle multi-expression else (already wrapped in block by compiler)

### 4.0 Unit Tests
- [x] 4.1 Test else block extraction for single expression
- [x] 4.2 Test else block extraction for multiple expressions
- [x] 4.3 Test try without else block
- [x] 4.4 Test else block with pattern matching

### 5.0 Final Verification
- [x] 5.1 Run all tests
- [x] 5.2 Verify no regressions
- [x] 5.3 Create summary document
- [x] 5.4 Mark tasks complete in plan
- [ ] 5.5 Ask for commit and merge permission

---

## Success Criteria

1. **Ontology completion** - hasElseClause property properly defined
2. **Else block detection** - Correctly identify and extract else blocks
3. **Expression extraction** - Extract else block expressions
4. **Multi-expression support** - Handle multiple expressions (compiler wraps in block)
5. **Property linking** - Link via `hasElseClause` object property
6. **Test coverage** - 4+ unit tests covering all scenarios
7. **Integration** - Works with existing try expression structure

---

## Notes and Considerations

### Else Block Semantics
- Else blocks ONLY execute when no exception occurs
- If an exception is raised and not caught, else is not executed
- If an exception is caught by rescue/catch, else is not executed
- After block ALWAYS executes, but else may not

### Relationship to After Block
- After block: ALWAYS executes (cleanup)
- Else block: ONLY executes on success (explicit success path)
- They serve different purposes:
  - After: Resource cleanup
  - Else: Success handling

### Elixir Version
- Else blocks were added in Elixir 1.11 (November 2020)
- Older Elixir versions will not have else blocks in AST

### AST Structure
- The Elixir compiler automatically wraps multiple expressions in a `{:__block__, [], [...]}` tuple
- We can use `build_expression_triples/3` directly on the else AST
- No special handling needed for multi-expression cases

### Integration Point
- Else extraction goes in `detect_optional_blocks/3` alongside rescue, catch, and after
- Order: rescue, catch, after, else

---

## Current Status

**Status:** ✅ COMPLETE - Ready for commit and merge

**What Works:**
- hasElseClause property completed with domain, range, and FunctionalProperty
- Else block extraction fully implemented
- `build_else_block/3` function handles single and multi-expression else blocks
- Else blocks are linked via `hasElseClause` object property
- Multi-expression else blocks automatically wrapped in DoBlock by compiler
- 4 unit tests covering all else block scenarios (all passing)
- Test with all optional blocks (rescue, catch, after, else) passing
- Proper IRI structure: `{try_iri}/else`

**Test Results:**
- 433 tests total (added 4 else block tests)
- 4 else block tests: all passing
- 1 pre-existing test failure (unrelated to Phase 30.5)

**Decisions Made:**
- Complete hasElseClause property with proper domain, range, and FunctionalProperty
- Add comment explaining else block semantics (only executes on success)
- Else block is a single expression (compiler wraps multiple in block)
- Simple implementation using existing `build_expression_triples/3`

---

*Last Updated:* 2026-01-18
*Branch:* feature/phase-30-5-else-blocks
*Status:* COMPLETE
