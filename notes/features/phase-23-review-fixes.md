# Phase 23 Review Fixes: Comprehensive Planning Document

**Date:** 2026-01-12
**Branch:** `expressions`
**Phase:** 23 (Operator Expression Extraction)
**Purpose:** Address all findings from the Phase 23 comprehensive review

---

## Executive Summary

Phase 23 has been comprehensively reviewed by 6 review agents with an overall score of **8.7/10**. No blocking issues were identified, but several concerns and suggestions require attention. This document provides a prioritized implementation plan to address all findings while balancing impact, effort, and codebase maintainability.

**Overall Assessment:** Production-ready with recommended improvements for long-term maintainability.

---

## Problem Statement

The Phase 23 implementation successfully completes operator expression extraction but exhibits:

1. **Test Coverage Variance:** Early operators (comparison, logical, arithmetic) have minimal test coverage compared to later operators
2. **Test Code Duplication:** ~60% repetitive test patterns create maintenance burden
3. **Missing Test File:** Integration test file `operator_builder_test.exs` not created as specified in planning
4. **Missing SPARQL Tests:** No query validation tests for operator expressions
5. **Ontology Workaround:** Capture operator uses generic RDF.value/RDFS.label instead of dedicated properties
6. **Context Inconsistency:** Binary/unary operators call build_expression_triples directly instead of build/3
7. **Test Gaps:** Missing edge cases (empty enumerable, additional capture indices, chained operations)

**Impact:** Medium - Code works correctly but has maintainability and consistency concerns

---

## Solution Overview

### Priority Framework

| Priority | Criteria | Examples |
|----------|----------|----------|
| **HIGH** | High impact, low effort, clear ROI | Test refactoring, coverage gaps |
| **MEDIUM** | Medium impact, medium effort, or high impact/high effort | Integration tests, ontology properties |
| **LOW** | Low impact, high effort, or nice-to-have | Operator registry, benchmarks |

### High-Priority Items (Immediate Action)

1. **Test Coverage Standardization** (2-3 hours)
   - Add missing test cases for early operators
   - Ensure consistent depth across all operator types
   - Add missing edge cases (empty enumerable, &4/&5 capture indices)

2. **Test Refactoring** (4-6 hours)
   - Implement table-driven tests for literals
   - Implement parameterized operator tests
   - Extract test helpers to reduce duplication
   - **Expected Benefit:** 54% test file reduction while maintaining coverage

### Medium-Priority Items (Short-term)

3. **Integration Test File** (2-3 hours)
   - Create dedicated `expression_builder_integration_test.exs`
   - Add SPARQL query validation tests
   - Document why existing tests are sufficient for builder validation

4. **Ontology Property Addition** (1-2 hours)
   - Add `captureIndex`, `moduleName`, `functionName`, `arity` properties to ontology
   - Update capture operator implementation to use dedicated properties
   - Document the change in migration notes

5. **Context Threading Consistency** (1 hour)
   - Evaluate whether build_expression_triples direct calls are intentional
   - Document the design decision or refactor for consistency

### Low-Priority Items (Long-term)

6. **Operator Registry** (4-6 hours)
   - Create registry for DRY handler generation
   - Only valuable if adding many more operators

7. **Performance Benchmarks** (2-3 hours)
   - Add benchmark suite for expression building
   - Track performance over time

---

## Agent Consultations Performed

### 1. Codebase Architecture Analysis

**Finding:** The current implementation correctly uses `build_expression_triples` for child expressions (operands) because:
- Child expressions use relative IRIs (e.g., `expr/0/left`, `expr/0/right`)
- They don't need counter allocation - that's already done by the parent
- The `build/3` function allocates counters, while `build_expression_triples` generates triples

**Conclusion:** The context threading behavior is **intentional and correct**, not an inconsistency.

**Evidence:**
- Line 501-502 in `expression_builder.ex`: `build_expression_triples(left_ast, left_iri, context)`
- Line 520-522: Similar pattern for unary operators
- Line 647-654: `build_child_expressions/3` properly threads context for collection literals

### 2. Ontology Structure Analysis

**Finding:** The ontology defines `CaptureOperator` class but lacks dedicated properties:
- No `captureIndex` property (uses generic `RDF.value()`)
- No `moduleName` property (uses generic `RDFS.label()`)
- No `functionName` property (embedded in label)
- No `arity` property (uses generic `RDF.value()`)

**Current Location:** `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl`
- Line 230-233: `CaptureOperator` class definition
- Lines 557-573: Operand properties for other operators (hasLeftOperand, hasRightOperand, hasOperand)

**Recommendation:** Add dedicated properties to ontology for semantic clarity and SPARQL queryability.

### 3. Test Pattern Analysis

**Finding:** Test file has 2591 lines with 179 test cases
- ~60% repetitive patterns identified by redundancy review
- Table-driven tests could reduce file by 54% (~1400 lines)
- Current approach: Individual test cases for each operator variant
- Alternative approach: Parameterized tests with test data tables

**Example of Current Pattern:**
```elixir
test "unary minus with integer literal" do
  context = full_mode_context()
  ast = {:-, [], [42]}
  {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])
  assert has_type?(triples, Core.ArithmeticOperator)
  assert has_operator_symbol?(triples, "-")
  assert has_child_with_type?(triples, expr_iri, Core.IntegerLiteral)
end
```

**Example of Table-Driven Pattern:**
```elixir
for {op, value, type_class} <- [
  {:-, 42, Core.IntegerLiteral},
  {:-, 3.14, Core.FloatLiteral},
  {:+, 42, Core.IntegerLiteral}
] do
  test "unary #{op} with #{type_class}" do
    # Single test body with parameterized assertions
  end
end
```

**Recommendation:** Hybrid approach - table-driven for literals, parameterized for operators.

### 4. SPARQL Testing Patterns

**Finding:** SPARQL tests exist in `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/shacl/validators/sparql_test.exs`
- Tests validate SPARQL constraint evaluation
- No integration tests verify queryability of generated operator graphs
- No tests verify that SPARQL can navigate operator expression hierarchies

**Example SPARQL Query for Operators:**
```sparql
SELECT ?operator ?left ?right
WHERE {
  ?operator a :BinaryOperator ;
            :hasLeftOperand ?left ;
            :hasRightOperand ?right .
}
```

**Recommendation:** Add integration tests that verify SPARQL queryability of operator expressions.

---

## Technical Details

### File Structure

```
/home/ducky/code/elixir-ontologies/
├── lib/elixir_ontologies/builders/
│   └── expression_builder.ex                  # Main implementation (1082 lines)
├── test/elixir_ontologies/builders/
│   ├── expression_builder_test.exs           # Current tests (2591 lines, 179 tests)
│   └── expression_builder_integration_test.exs # NEW: Integration tests
├── ontology/
│   └── elixir-core.ttl                        # Ontology to modify
└── test/elixir_ontologies/fixtures/
    └── expressions/                           # NEW: Expression fixtures for SPARQL tests
        ├── comparison_operators.ttl
        ├── logical_operators.ttl
        └── capture_operators.ttl
```

### Ontology Properties to Add

**Location:** `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl` (after line 573)

```turtle
# =============================================================================
# Capture Operator Properties
# =============================================================================

:captureIndex a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "capture index"@en ;
    rdfs:comment """The argument index captured by &1, &2, etc.
    Used in anonymous function shorthand."""@en ;
    rdfs:domain :CaptureOperator ;
    rdfs:range xsd:integer .

:captureModuleName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "capture module name"@en ;
    rdfs:comment """The module name referenced in &Module.fun/arity
    function capture syntax."""@en ;
    rdfs:domain :CaptureOperator ;
    rdfs:range xsd:string .

:captureFunctionName a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "capture function name"@en ;
    rdfs:comment """The function name referenced in &Module.fun/arity
    function capture syntax."""@en ;
    rdfs:domain :CaptureOperator ;
    rdfs:range xsd:string .

:captureArity a owl:DatatypeProperty, owl:FunctionalProperty ;
    rdfs:label "capture arity"@en ;
    rdfs:comment """The arity specified in &Module.fun/arity
    function capture syntax."""@en ;
    rdfs:domain :CaptureOperator ;
    rdfs:range xsd:integer .
```

### Implementation Changes Required

#### 1. Capture Operator Builder (expression_builder.ex, lines 1012-1049)

**Before:**
```elixir
defp build_capture_index(index, expr_iri) do
  [
    {expr_iri, RDF.type(), Core.CaptureOperator},
    {expr_iri, Core.operatorSymbol(), RDF.Literal.new("&")},
    {expr_iri, RDF.value(), RDF.Literal.new(index)}
  ]
end
```

**After:**
```elixir
defp build_capture_index(index, expr_iri) do
  [
    {expr_iri, RDF.type(), Core.CaptureOperator},
    {expr_iri, Core.operatorSymbol(), RDF.Literal.new("&")},
    {expr_iri, Core.captureIndex(), RDF.Literal.new(index)}
  ]
end
```

#### 2. Capture Function Reference Builder (lines 1024-1049)

**Before:**
```elixir
defp build_capture_function_ref(function_ref, arity, expr_iri, _context) do
  {module, function} = extract_function_ref_parts(function_ref)
  ref_label = if arity, do: "&#{module}.#{function}/#{arity}", else: "&#{module}.#{function}"

  base_triples = [
    {expr_iri, RDF.type(), Core.CaptureOperator},
    {expr_iri, Core.operatorSymbol(), RDF.Literal.new("&")},
    {expr_iri, RDF.NS.RDFS.label(), RDF.Literal.new(ref_label)}
  ]

  arity_triples = if arity do
    [{expr_iri, RDF.value(), RDF.Literal.new(arity)}]
  else
    []
  end

  base_triples ++ arity_triples
end
```

**After:**
```elixir
defp build_capture_function_ref(function_ref, arity, expr_iri, _context) do
  {module, function} = extract_function_ref_parts(function_ref)

  base_triples = [
    {expr_iri, RDF.type(), Core.CaptureOperator},
    {expr_iri, Core.operatorSymbol(), RDF.Literal.new("&")},
    {expr_iri, Core.captureModuleName(), RDF.Literal.new(module)},
    {expr_iri, Core.captureFunctionName(), RDF.Literal.new(function)}
  ]

  arity_triples = if arity do
    [{expr_iri, Core.captureArity(), RDF.Literal.new(arity)}]
  else
    []
  end

  base_triples ++ arity_triples
end
```

### Test Refactoring Strategy

#### Phase 1: Extract Test Helpers (No Reduction, Better Organization)

**New File:** `test/elixir_ontologies/builders/expression_test_helpers.ex`

```elixir
defmodule ElixirOntologies.Builders.ExpressionTestHelpers do
  @moduledoc """
  Shared test helpers for expression builder tests.
  """

  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.NS.Core

  def full_mode_context(opts \\ []) do
    Keyword.merge(
      [
        base_iri: "https://example.org/code#",
        config: %{include_expressions: true},
        file_path: "lib/my_app/users.ex"
      ],
      opts
    )
    |> Context.new()
  end

  def has_type?(triples, expected_type) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == RDF.type() and o == expected_type
    end)
  end

  def has_operator_symbol?(triples, symbol) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == Core.operatorSymbol() and RDF.Literal.value(o) == symbol
    end)
  end

  def has_literal_value?(triples, subject, predicate, expected_value) do
    Enum.any?(triples, fn {s, p, o} ->
      s == subject and
        p == predicate and
        RDF.Literal.value(o) == expected_value
    end)
  end

  def has_child_with_type?(triples, parent_iri, child_type) do
    Enum.any?(triples, fn {s, p, o} ->
      # Find child expression (hasLeftOperand, hasRightOperand, hasOperand)
      (p == Core.hasLeftOperand() or p == Core.hasRightOperand() or p == Core.hasOperand()) and
        s == parent_iri and
        # Check if child has the expected type
        Enum.any?(triples, fn {child_s, child_p, child_o} ->
          child_s == o and child_p == RDF.type() and child_o == child_type
        end)
    end)
  end
end
```

#### Phase 2: Table-Driven Literal Tests

**Current:** ~500 lines testing individual literals
**Refactored:** ~150 lines using test data tables

```elixir
describe "integer literals" do
  @integer_cases [
    {0, "zero"},
    {42, "small positive"},
    {-42, "small negative"},
    {1_000_000, "million"},
    {0xFF, "hexadecimal"},
    {0o755, "octal"},
    {0b1010, "binary"}
  ]

  for {value, description} <- @integer_cases do
    test "builds integer literal for #{description}: #{inspect(value)}" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _context}} = ExpressionBuilder.build(value, context, [])

      assert has_type?(triples, Core.IntegerLiteral)
      assert has_literal_value?(triples, expr_iri, Core.integerValue(), unquote(value))
    end
  end
end
```

#### Phase 3: Parameterized Operator Tests

**Current:** ~300 lines for binary operator tests
**Refactored:** ~100 lines using parameterization

```elixir
describe "binary operators" do
  @binary_operators [
    # Arithmetic
    {:+, "1 + 2", Core.ArithmeticOperator},
    {:-, "1 - 2", Core.ArithmeticOperator},
    {:*, "1 * 2", Core.ArithmeticOperator},
    {:/, "1 / 2", Core.ArithmeticOperator},
    {:div, "div 1, 2", Core.ArithmeticOperator},
    {:rem, "rem 1, 2", Core.ArithmeticOperator},
    # Comparison
    {:==, "1 == 2", Core.ComparisonOperator},
    {:!=, "1 != 2", Core.ComparisonOperator},
    {:===, "1 === 2", Core.ComparisonOperator},
    {:!==, "1 !== 2", Core.ComparisonOperator},
    {:<, "1 < 2", Core.ComparisonOperator},
    {:>, "1 > 2", Core.ComparisonOperator},
    {:<=, "1 <= 2", Core.ComparisonOperator},
    {:>=, "1 >= 2", Core.ComparisonOperator},
    # Logical
    {:and, "true and false", Core.LogicalOperator},
    {:or, "true or false", Core.LogicalOperator},
    {:&&, "true && false", Core.LogicalOperator},
    {:||, "true || false", Core.LogicalOperator},
    # Other
    {:<>, "\"hello\" <> \"world\"", Core.StringConcatOperator},
    {:"++", "[1] ++ [2]", Core.ListOperator},
    {:"--", "[1, 2] -- [2]", Core.ListOperator},
    {:|>, "1 |> func()", Core.PipeOperator},
    {:=, "1 = 2", Core.MatchOperator},
    {:in, "1 in [1, 2]", Core.InOperator}
  ]

  for {op, description, type_class} <- @binary_operators do
    test "builds #{type_class} for #{description}" do
      context = full_mode_context()
      ast = {unquote(op), [], [1, 2]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, unquote(type_class))
      assert has_operator_symbol?(triples, to_string(unquote(op)))
    end
  end
end
```

---

## Success Criteria

### For Each Priority Level

#### HIGH Priority (Must Complete)

1. **Test Coverage Standardization**
   - [ ] All operators have consistent test depth
   - [ ] Missing edge cases added (empty enumerable, &4/&5 indices)
   - [ ] Operand capture tests for early operators
   - [ ] Chained operation tests for arithmetic

2. **Test Refactoring**
   - [ ] Test helpers extracted to shared module
   - [ ] Table-driven tests for literals (500→150 lines)
   - [ ] Parameterized tests for operators (300→100 lines)
   - [ ] All 179 tests still passing
   - [ ] Test file reduced to ~1200 lines (54% reduction)

#### MEDIUM Priority (Should Complete)

3. **Integration Test File**
   - [ ] `expression_builder_integration_test.exs` created
   - [ ] SPARQL query tests verify operator queryability
   - [ ] Fixture files for test data
   - [ ] Documentation explaining test structure

4. **Ontology Property Addition**
   - [ ] Four new properties added to elixir-core.ttl
   - [ ] Capture operator implementation updated
   - [ ] All tests pass with new properties
   - [ ] Migration notes documented

5. **Context Threading Documentation**
   - [ ] Design decision documented in moduledoc
   - [ ] Comments explain when to use build vs build_expression_triples

#### LOW Priority (Nice to Have)

6. **Operator Registry**
   - [ ] Registry module created
   - [ ] Handlers generated from configuration
   - [ ] Documentation for adding new operators

7. **Performance Benchmarks**
   - [ ] Benchmark suite created
   - [ ] Baseline measurements recorded
   - [ ] CI integration for regression detection

### Overall Success Metrics

- **Test Coverage:** Maintained at 100% for operator handlers
- **Test Maintainability:** 54% reduction in test file size
- **Code Quality:** No regressions, all tests passing
- **Documentation:** Clear explanation of design decisions
- **Ontology Completeness:** Dedicated properties for all operator types

---

## Implementation Plan

### Week 1: HIGH Priority Fixes (Days 1-3)

#### Day 1: Test Coverage Standardization

**Owner:** Developer
**Effort:** 2-3 hours
**Files:** `test/elixir_ontologies/builders/expression_builder_test.exs`

**Tasks:**
1. Add operand capture tests for comparison operators (Phase 22)
   - Test that left/right operands are properly linked
   - Test nested expression operands

2. Add chained operation tests for arithmetic (Phase 22)
   - Test `1 + 2 + 3` (left-associative)
   - Test `1 * (2 + 3)` (precedence)

3. Add missing edge cases
   - Empty enumerable for in operator: `x in []`
   - Additional capture indices: `&4`, `&5`
   - Empty string concatenation: `"" <> "hello"`
   - Special characters in strings: `"hello\nworld"`

**Acceptance Criteria:**
- 15 new test cases added
- All tests passing
- Coverage parity between early and late operators

#### Day 2: Test Helper Extraction

**Owner:** Developer
**Effort:** 2-3 hours
**Files:**
- `test/elixir_ontologies/builders/expression_test_helpers.ex` (NEW)
- `test/elixir_ontologies/builders/expression_builder_test.exs`

**Tasks:**
1. Create shared test helpers module
2. Extract helper functions from test file
3. Update test file to import helpers
4. Verify all tests still pass

**Acceptance Criteria:**
- Helpers module created with 5+ helper functions
- Test file imports helpers
- All 179 tests still passing
- No code duplication in helpers

#### Day 3: Table-Driven Test Refactoring

**Owner:** Developer
**Effort:** 3-4 hours
**Files:** `test/elixir_ontologies/builders/expression_builder_test.exs`

**Tasks:**
1. Refactor integer literal tests (7 cases → 1 table-driven test)
2. Refactor float literal tests (6 cases → 1 table-driven test)
3. Refactor string literal tests (8 cases → 1 table-driven test)
4. Refactor atom literal tests (6 cases → 1 table-driven test)
5. Refactor boolean literal tests (3 cases → 1 table-driven test)
6. Verify all tests still pass

**Acceptance Criteria:**
- Literal tests reduced from ~500 lines to ~150 lines
- All tests passing
- Test names still descriptive
- Coverage maintained at 100%

### Week 2: MEDIUM Priority Fixes (Days 4-6)

#### Day 4: Ontology Property Addition

**Owner:** Developer + Ontology Maintainer
**Effort:** 1-2 hours
**Files:**
- `ontology/elixir-core.ttl`
- `lib/elixir_ontologies/builders/expression_builder.ex`
- `test/elixir_ontologies/builders/expression_builder_test.exs`

**Tasks:**
1. Add four new properties to elixir-core.ttl
2. Update NS module to expose new properties
3. Update capture operator builders
4. Update capture operator tests
5. Verify SPARQL queries work with new properties

**Acceptance Criteria:**
- Properties added to ontology
- Implementation uses new properties
- All tests passing
- SPARQL can query capture operator components

#### Day 5: Integration Test File Creation

**Owner:** Developer
**Effort:** 2-3 hours
**Files:**
- `test/elixir_ontologies/builders/expression_builder_integration_test.exs` (NEW)
- `test/fixtures/expressions/*.ttl` (NEW)

**Tasks:**
1. Create integration test file
2. Add SPARQL query tests for operators
   - Query all comparison operators
   - Query all logical operators
   - Query operator hierarchies
   - Query capture operators by index
3. Create fixture files for test data
4. Document integration test strategy

**Acceptance Criteria:**
- Integration test file with 10+ SPARQL tests
- Fixture files for test data
- All SPARQL queries return expected results
- Documentation explains test structure

#### Day 6: Context Threading Documentation

**Owner:** Developer
**Effort:** 1 hour
**Files:** `lib/elixir_ontologies/builders/expression_builder.ex`

**Tasks:**
1. Add @moduledoc section explaining build vs build_expression_triples
2. Add comments to key functions explaining context threading
3. Update function documentation to clarify when to use each function

**Acceptance Criteria:**
- Clear documentation in moduledoc
- Comments on lines 501-502 explaining direct calls
- Function docs updated with guidance

### Week 3: LOW Priority Enhancements (Days 7-8)

#### Day 7: Operator Registry (Optional)

**Owner:** Developer
**Effort:** 4-6 hours
**Prerequisite:** Team approval

**Tasks:**
1. Design registry configuration format
2. Implement operator registry module
3. Refactor handler dispatch to use registry
4. Update tests
5. Document registry usage

**Acceptance Criteria:**
- Registry reduces handler boilerplate
- All operators still working
- Documentation shows how to add new operators

#### Day 8: Performance Benchmarks (Optional)

**Owner:** Developer
**Effort:** 2-3 hours
**Files:** `bench/expression_builder_bench.exs` (NEW)

**Tasks:**
1. Create benchmark suite using Benchee
2. Benchmark common operators
3. Benchmark complex nested expressions
4. Record baseline measurements
5. Set up CI integration

**Acceptance Criteria:**
- Benchmark suite created
- Baseline measurements recorded
- CI runs benchmarks weekly
- Results tracked over time

---

## Dependencies and Risk Mitigation

### Dependency Graph

```
[HIGH Priority]
Day 1: Test Coverage ──────────────────────┐
Day 2: Helper Extraction ──────────────────┤
Day 3: Test Refactoring ───────────────────┤
                                           ├─→ [All Tests Pass]
[MEDIUM Priority]                          │
Day 4: Ontology Properties ────────────────┤ ← Day 4 depends on Day 3
Day 5: Integration Tests ──────────────────┤
Day 6: Documentation ──────────────────────┘

[LOW Priority]
Day 7: Operator Registry ──┐
Day 8: Benchmarks ─────────┴─→ [Optional, Independent]
```

### Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Test refactoring breaks tests | HIGH | Run tests after each refactoring step |
| Ontology changes break SPARQL queries | MEDIUM | Add SPARQL validation tests |
| Table-driven tests reduce readability | LOW | Keep descriptive test names |
| Context threading changes introduce bugs | HIGH | Document current behavior only, don't change |
| Integration test file not needed | LOW | Document why tests are sufficient |

---

## Notes and Considerations

### 1. Context Threading Decision

**Current Behavior:** Binary and unary operators call `build_expression_triples` directly for child expressions.

**Assessment:** This is **intentional and correct**:
- Parent expression (operator) allocates counter via `build/3`
- Child expressions use relative IRIs (e.g., `expr/0/left`)
- Child expressions don't need counter allocation
- `build_expression_triples` generates triples without allocating counters

**Conclusion:** Document the design, don't refactor.

### 2. Test Naming Convention

**Phase 22 Pattern:** "builds [Type] triples for [input]"
**Phase 23 Pattern:** Varied patterns

**Recommendation:** Standardize to Phase 22 pattern for consistency:
- "builds ComparisonOperator triples for =="
- "builds LogicalOperator triples for and"
- "builds ArithmeticOperator triples for +"

### 3. Integration Test File Necessity

**Question:** Do we need a separate `operator_builder_test.exs`?

**Analysis:**
- Current tests thoroughly validate builder functionality
- Integration tests would add SPARQL query validation
- Value depends on whether SPARQL querying is a priority

**Recommendation:** Create `expression_builder_integration_test.exs` with SPARQL validation tests.

### 4. Test Refactoring Trade-offs

**Pros of Table-Driven Tests:**
- 54% reduction in test file size
- Easier to add new test cases
- Centralized test data

**Cons of Table-Driven Tests:**
- Less readable test failures (which case failed?)
- Harder to debug specific cases
- May reduce clarity

**Recommendation:** Hybrid approach:
- Table-driven for literals (simple, many cases)
- Parameterized for operators (medium complexity)
- Individual tests for edge cases (complex, few cases)

### 5. Ontology Property Migration

**Current Workaround:** Using `RDF.value()` and `RDFS.label()` for capture operator components.

**Migration Strategy:**
1. Add new properties to ontology
2. Update implementation to use new properties
3. Update tests to assert new properties
4. Keep old tests for backward compatibility (optional)
5. Document migration in changelog

**Backward Compatibility:** Old RDF graphs will still work (they just used generic properties). New graphs will use dedicated properties.

---

## Key Questions to Resolve

### Q1: For Capture Operator Ontology Properties

**Question:** Should we add these properties now or document the workaround for future work?

**Recommendation:** **Add now** (MEDIUM Priority)

**Reasoning:**
- Low effort (1-2 hours)
- High semantic clarity
- Enables better SPARQL queries
- Capture operator is a core Elixir feature
- Workaround is already identified

**File to Modify:** `/home/ducky/code/elixir-ontologies/ontology/elixir-core.ttl`
**Location:** After line 573 (after `hasOperand` property definition)

### Q2: For Integration Test File

**Question:** Should we create a separate file or add to existing tests?

**Recommendation:** **Create separate file** `expression_builder_integration_test.exs`

**Reasoning:**
- Integration tests have different focus (SPARQL queryability)
- Unit tests already comprehensive (179 tests)
- Separation of concerns (unit vs integration)
- Integration tests can be slower, run separately

**What SPARQL Queries to Test:**
1. Query all operators by type
2. Query operator hierarchies (left/right operands)
3. Query capture operators by index
4. Query function references (module/function/arity)
5. Query nested expressions
6. Validate cardinality constraints

### Q3: For Test Refactoring

**Question:** What's the right balance between DRY and readability?

**Recommendation:** **Hybrid approach** with table-driven tests for literals, parameterized for operators, individual for edge cases

**Reasoning:**
- Literals: Many simple cases (perfect for table-driven)
- Operators: Medium complexity (good for parameterized)
- Edge cases: Complex, few cases (keep individual)
- Maintain readability while reducing duplication

**Target:** 54% reduction (2591 → ~1200 lines)

### Q4: For Context Threading Inconsistency

**Question:** Is the current behavior intentional and correct?

**Answer:** **Yes, it's intentional and correct**

**Explanation:**
- `build/3`: Allocates counter, returns updated context
- `build_expression_triples/3`: Generates triples, doesn't allocate counter
- Child expressions use relative IRIs (e.g., `expr/0/left`)
- They don't need counter allocation
- Direct calls are appropriate

**Recommendation:** **Document the design decision**, don't refactor

---

## Conclusion

Phase 23 is production-ready with no blocking issues. The recommended improvements focus on:

1. **Maintainability:** Reduce test duplication through refactoring
2. **Consistency:** Standardize test coverage across all operators
3. **Completeness:** Add integration tests and ontology properties
4. **Documentation:** Clarify design decisions

The implementation plan prioritizes high-impact, low-effort improvements first, followed by medium-priority enhancements, and optionally low-priority optimizations.

**Overall Timeline:** 3-8 days depending on which priorities are addressed

**Next Steps:**
1. Review and approve this plan
2. Begin HIGH Priority fixes (Days 1-3)
3. Continue to MEDIUM Priority fixes (Days 4-6)
4. Evaluate LOW Priority items (Days 7-8)

---

**Document Version:** 1.0
**Last Updated:** 2026-01-12
**Status:** Ready for Review
