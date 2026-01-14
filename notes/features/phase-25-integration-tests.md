# Phase 25 Integration Tests

**Feature Branch:** `feature/phase-25-integration-tests`
**Created:** 2026-01-14
**Based On:** Phase 25 Integration Tests section of notes/planning/expressions/phase-25.md

---

## Problem Statement

Phase 25 has implemented individual control flow expression builders (if/unless/cond/case/with/receive/try/raise/throw), but there is no comprehensive integration test suite that verifies:

1. All control flow types work together correctly
2. Light mode (backward compatibility) vs Full mode (expression extraction) behavior
3. Nested control flow structures
4. SPARQL queryability of the generated RDF
5. Expression tree structure navigability

Currently:
- Individual unit tests exist for each control flow type in `control_flow_builder_test.exs`
- No end-to-end integration tests verify complete control flow extraction
- No tests verify SPARQL queries work against the generated RDF

---

## Current Implementation Analysis

**Location:** `test/elixir_ontologies/builders/control_flow_builder_test.exs`

**Status:** 97 tests exist covering individual control flow builders:
- If/Unless expression tests (Phase 25.1)
- Cond expression tests (Phase 25.2)
- Case expression tests (Phase 25.3)
- With expression tests (Phase 25.4)
- Receive expression tests (Phase 25.5)
- Try expression tests (Phase 25.6)
- Raise/Throw expression tests (Phase 25.7)

**Missing:** Integration test file `test/elixir_ontologies/builders/control_flow_full_test.exs`

### Existing Test Patterns

From `expression_builder_integration_test.exs`:
- Uses `Context.with_expression_counter()` for expression tracking
- Tests multi-expression scenarios
- Tests nested expression hierarchies
- Verifies context threading between builds
- Uses RDF triple filtering to verify structure

### ControlFlowBuilder API

All control flow builders follow the same pattern:
```elixir
{expr_iri, triples} = ControlFlowBuilder.build_<type>(expr, context, opts)

# Options:
- :containing_function - IRI fragment of containing function
- :index - Expression index within the function (default: 0)
- :expression_builder - ExpressionBuilder module for full mode
```

---

## Solution Overview

Create `control_flow_full_test.exs` with comprehensive integration tests that verify:

1. **Complete Control Flow Extraction**: All 7 control flow types work end-to-end
2. **Mode Behavior**: Light mode (minimal triples) vs Full mode (expression trees)
3. **Nested Control Flow**: Control flow inside other control flow
4. **Complex Expressions**: Complex conditions and branch bodies
5. **SPARQL Queryability**: RDF can be queried by type, condition, body, etc.
6. **Expression Tree Structure**: Navigate the generated expression tree

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Create new test file | Separate integration tests from unit tests |
| Use `describe` blocks for organization | Group tests by category (light mode, full mode, SPARQL) |
| Reuse existing test helpers | Follow patterns from expression_builder_integration_test.exs |
| Test both light and full mode | Verify backward compatibility and new features |
| Include SPARQL query tests | Verify the RDF is queryable (mentioned in plan) |

---

## Implementation Plan

### Step 1: Create test file structure

**Location:** `test/elixir_ontologies/builders/control_flow_full_test.exs`

**Module structure:**
```elixir
defmodule ElixirOntologies.Builders.ControlFlowFullTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{ControlFlowBuilder, Context, ExpressionBuilder}
  alias ElixirOntologies.Extractors.{Conditional, CaseWith, Comprehension, Exception}
  alias ElixirOntologies.NS.Core

  @base_iri "https://example.org/code#"

  describe "complete control flow extraction" do
    # Test all 7 control flow types
  end

  describe "light mode vs full mode" do
    # Test backward compatibility
  end

  describe "nested control flow" do
    # Test control flow inside control flow
  end

  describe "complex expressions" do
    # Test complex conditions and bodies
  end

  describe "SPARQL queryability" do
    # Test RDF can be queried
  end
end
```

### Step 2: Implement "complete control flow extraction" tests

Tests needed:
1. Test if expression extraction
2. Test unless expression extraction
3. Test cond expression extraction
4. Test case expression extraction
5. Test with expression extraction
6. Test receive expression extraction
7. Test try expression extraction
8. Test raise/throw expression extraction

### Step 3: Implement "light mode vs full mode" tests

Tests needed:
1. Test light mode produces minimal triples (type only)
2. Test full mode produces expression tree
3. Test all control flow types respect mode setting

### Step 4: Implement "nested control flow" tests

Tests needed:
1. Test if inside case
2. Test case inside with
3. Test cond inside receive
4. Verify nested expression IRIs are distinct

### Step 5: Implement "complex expressions" tests

Tests needed:
1. Test complex condition expressions (operators, function calls)
2. Test complex branch bodies (multiple statements, nested expressions)
3. Test guard expressions in case/with clauses

### Step 6: Implement "SPARQL queryability" tests

Tests needed:
1. Test find control flow by type (e.g., all IfExpressions)
2. Test navigate condition expressions
3. Test navigate branch bodies
4. Test find guards within clauses
5. Test expression tree structure is queryable

**Note:** SPARQL tests may require a TripleStore connection. Check existing test patterns.

---

## Success Criteria

- [ ] 1.1: Test complete control flow extraction for if/unless
- [ ] 1.2: Test complete control flow extraction for cond
- [ ] 1.3: Test complete control flow extraction for case
- [ ] 1.4: Test complete control flow extraction for with
- [ ] 1.5: Test complete control flow extraction for receive
- [ ] 1.6: Test complete control flow extraction for try
- [ ] 1.7: Test complete control flow extraction for raise/throw
- [ ] 2.1: Test light mode produces minimal triples
- [ ] 2.2: Test full mode produces expression tree
- [ ] 2.3: Test all control flow types respect mode setting
- [ ] 3.1: Test nested control flow (if inside case)
- [ ] 3.2: Test nested control flow (case inside with)
- [ ] 3.3: Verify nested expression IRIs are distinct
- [ ] 4.1: Test complex condition expressions
- [ ] 4.2: Test complex branch bodies
- [ ] 5.1: Test find control flow by type
- [ ] 5.2: Test navigate condition expressions
- [ ] 5.3: Test navigate branch bodies
- [ ] 5.4: Test find guards within clauses
- [ ] All integration tests pass

---

## Test Coverage

New tests needed (17 tests total):

**Complete Control Flow Extraction (7 tests):**
1. Test if expression extraction in full mode
2. Test unless expression extraction in full mode
3. Test cond expression extraction in full mode
4. Test case expression extraction in full mode
5. Test with expression extraction in full mode
6. Test receive expression extraction in full mode
7. Test try/raise/throw expression extraction in full mode

**Light Mode vs Full Mode (3 tests):**
8. Test light mode produces minimal triples
9. Test full mode produces expression tree
10. Test mode setting affects all control flow types

**Nested Control Flow (3 tests):**
11. Test if inside case
12. Test case inside with
13. Test multiple nesting levels

**Complex Expressions (2 tests):**
14. Test complex condition expressions
15. Test complex branch bodies

**SPARQL Queryability (2 tests):**
16. Test find control flow by type
17. Test navigate expression tree

---

## Files to Create

| File | Purpose |
|------|---------|
| `test/elixir_ontologies/builders/control_flow_full_test.exs` | Integration tests |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| SPARQL tests may require TripleStore | Check existing test patterns for SPARQL |
| Complex test setup may be brittle | Use `setup` blocks for common context |
| Test execution time | Use `async: true` where possible |
| Missing ontology properties | Use existing Core properties from namespace |

---

## Implementation Status

- [x] Planning document complete
- [x] Test file structure created
- [x] Complete control flow extraction tests implemented
- [x] Light/full mode tests implemented
- [x] Nested control flow tests implemented
- [x] Complex expression tests implemented
- [x] SPARQL queryability tests implemented
- [x] All tests passing (18/18)
- [x] Summary written

---

*Last Updated:* 2026-01-14
*Branch:* feature/phase-25-integration-tests
