# Phase 30.1: Try Expression Structure

**Feature Branch:** `feature/phase-30-1-try-expression-structure`
**Created:** 2026-01-16
**Based On:** Phase 30 Expressions Plan (`notes/planning/expressions/phase-30.md`)

---

## Problem Statement

Phase 30.1 implements the basic structure for try expressions including the try body and optional rescue, catch, and after blocks. This is a critical part of exception handling in Elixir and needs to be properly represented in the ontology.

### Current State
- Try expressions are not yet supported in ExpressionBuilder
- The ontology has `TryExpression`, `RaiseExpression`, `ThrowExpression` classes
- The ontology has `hasRescueClause`, `hasCatchClause`, `hasAfterClause`, `hasElseClause` properties
- **The ontology is missing `hasTryBody` property** (mentioned in plan but not in ontology)

### Requirements
1. Detect try expressions in Elixir AST
2. Extract try body expression
3. Link try body to TryExpression via `hasTryBody` property
4. Support optional rescue, catch, after, and else blocks (structure only in 30.1)

---

## Solution Overview

Implement try expression detection and basic structure building in ExpressionBuilder:

### Try Expression Detection
- Match `:try` AST pattern with keyword list format
- Parse try body (required)
- Identify optional blocks: rescue, catch, after, else (structure only)

### Try Expression Builder
- Create `TryExpression` type triple
- Extract and link try body via `hasTryBody` property
- Generate IRIs for optional blocks (placeholder for full implementation in later phases)

---

## Agent Consultations

None yet - this is a straightforward implementation based on the existing patterns in ExpressionBuilder.

---

## Technical Details

### Files to Modify

| File | Changes | Purpose |
|------|---------|---------|
| `lib/elixir_ontologies/builders/expression_builder.ex` | Add try detection and builder | Implement try expression support |
| `test/elixir_ontologies/builders/expression_builder_test.exs` | Add try expression tests | Test coverage |
| `priv/ontologies/elixir-core.ttl` | Add `hasTryBody` property | **TODO: Ask developer if needed** |

### AST Pattern for Try Expressions

```elixir
# Simple try
{:try, _, [[do: body]]}

# Try with rescue
{:try, _, [[do: body], [rescue: rescue_clauses]]}

# Try with catch
{:try, _, [[do: body], [catch: catch_clauses]]}

# Try with after
{:try, _, [[do: body], [after: after_block]]}

# Try with else (Elixir 1.11+)
{:try, _, [[do: body], [else: else_block]]}

# Complete try
{:try, _, [[do: body], [rescue: rescue_clauses], [catch: catch_clauses], [after: after_block], [else: else_block]]}
```

### IRI Structure

- Try expression: `{base_iri}expr/{counter}/try`
- Try body: `{try_iri}/body`
- Rescue clause: `{try_iri}/rescue/{index}`
- Catch clause: `{try_iri}/catch/{index}`
- After block: `{try_iri}/after`
- Else block: `{try_iri}/else`

---

## Success Criteria

1. **Try expression detection** - Correctly identify try expressions in AST
2. **Try body extraction** - Extract and link try body expression
3. **Optional block detection** - Identify presence of rescue, catch, after, else blocks
4. **Test coverage** - 5+ unit tests for try expression detection and building
5. **Integration** - Works with existing ExpressionBuilder patterns

---

## Implementation Plan

### 1.0 Setup ✅
- [x] 1.1 Create feature branch `feature/phase-30-1-try-expression-structure`
- [x] 1.2 Create planning document

### 2.0 Ontology Update ✅
- [x] 2.1 Added `hasTryBody` property to elixir-core.ttl
- [x] 2.2 Property definition: domain=TryExpression, range=Block

### 3.0 Try Expression Detection ✅
- [x] 3.1 Add `:try` handler to `build_expression_triples/3`
- [x] 3.2 Match try AST pattern with keyword list format
- [x] 3.3 Extract try body from AST
- [x] 3.4 Detect optional rescue clauses
- [x] 3.5 Detect optional catch clauses
- [x] 3.6 Detect optional after block
- [x] 3.7 Detect optional else block

### 4.0 Try Expression Builder ✅
- [x] 4.1 Implement `build_try_expression/3`
- [x] 4.2 Create type triple: `expr_iri a Core.TryExpression`
- [x] 4.3 Generate body IRI: `{expr_iri}/body`
- [x] 4.4 Extract try body expression
- [x] 4.5 Link via `hasTryBody` object property
- [x] 4.6 Handle empty try body
- [x] 4.7 Handle try body with multiple expressions (wrap in block)

### 5.0 Unit Tests ✅
- [x] 5.1 Test try expression detection for simple try
- [x] 5.2 Test try expression detection for try with rescue
- [x] 5.3 Test try expression detection for try with catch
- [x] 5.4 Test try expression detection for try with after
- [x] 5.5 Test try expression detection for complete try
- [x] 5.6 Test try expression builder creates correct structure

### 6.0 Final Verification ✅
- [x] 6.1 Run all tests (10 tests, 0 failures)
- [x] 6.2 Verify no regressions
- [x] 6.3 Create summary document
- [x] 6.4 Mark tasks complete in plan
- [x] 6.5 Ask for commit and merge permission

---

## Notes and Considerations

### Ontology Property Question

The Phase 30.1 plan mentions using `hasTryBody` property, but this property is not defined in `elixir-core.ttl`. There are a few options:

1. **Add `hasTryBody` property to ontology**
   - Pros: Matches the plan, clear semantic meaning
   - Cons: Requires ontology change

2. **Reuse `hasThenBranch` property**
   - Pros: Already exists, used for if/then/else
   - Cons: Semantically confusing (try doesn't have "then" branch)

3. **Use generic `hasBody` property (if it exists)**
   - Pros: Generic, reusable
   - Cons: Need to check if it exists in ontology

**Question for developer:** Should I add `hasTryBody` property to the ontology, or use an existing property?

### Block Handling

For Phase 30.1, we only need to:
- Detect the presence of optional blocks (rescue, catch, after, else)
- Create placeholder IRIs for these blocks
- Full extraction will be done in later phases (30.2-30.5)

### Multiple Expression Try Body

If the try body has multiple expressions, they should be wrapped in a block:
```elixir
try do
  expr1()
  expr2()
end
```

This is similar to how `do` blocks are handled in Phase 27.

---

## Current Status

**Status:** ✅ COMPLETE

**What Works:**
- Feature branch created
- Planning document complete
- `hasTryBody` property added to ontology
- Try expression detection implemented
- Try expression builder implemented with body extraction
- 10 comprehensive unit tests added and passing
- Summary document created

**Decisions Made:**
- Added `hasTryBody` property to elixir-core.ttl (as suggested by developer)
- Used `quote do end` blocks in tests to avoid AST literal parsing issues
- Implemented placeholder `detect_optional_blocks/3` for future phases (30.2-30.5)

---

*Last Updated:* 2026-01-17
*Branch:* feature/phase-30-1-try-expression-structure
