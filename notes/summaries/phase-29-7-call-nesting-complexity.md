# Phase 29.7: Call Nesting and Complexity - Summary

**Date:** 2026-01-16
**Feature Branch:** `feature/phase-29-7-call-nesting-complexity`
**Based On:** Phase 29 Expressions Plan (`notes/planning/expressions/phase-29.md`)

---

## Executive Summary

Successfully validated that the existing call and reference extraction system handles nested calls and complex scenarios correctly. This phase focused on **testing and validation** rather than implementing new extraction logic. All existing functionality for remote calls, local calls, anonymous function calls, module references, and function references works correctly in complex, real-world scenarios.

---

## Changes Made

### 1. Tests Added

**File:** `test/elixir_ontologies/builders/expression_builder_test.exs` (lines 1882-2118)

**Added Test Suite:** "nested and complex calls"

1. **Test: handles nested remote calls**
   - Validates `String.upcase(Integer.to_string(123))`
   - Verifies outer call properties (moduleName: "String", functionName: "upcase", arity: 1)
   - Verifies inner call is extracted as argument (moduleName: "Integer", functionName: "to_string")
   - Verifies inner call's argument (IntegerLiteral: 123)
   - Confirms IRI hierarchy follows pattern: `expr_0/arg-0` for nested call

2. **Test: handles nested remote and local calls**
   - Validates `process(Enum.map(items, &process/1))`
   - Verifies outer local call (functionName: "process")
   - Verifies inner remote call within argument (Enum.map)

3. **Test: handles pipe operator chaining**
   - Validates `1 |> Integer.to_string() |> String.upcase()`
   - Verifies outer PipeOperator with hasLeftOperand and hasRightOperand
   - Verifies inner PipeOperator as left operand
   - Verifies RemoteCall (String.upcase) as right operand

4. **Test: handles calls with complex argument expressions**
   - Validates `calc(a + b, c * d)`
   - Verifies LocalCall with arity 2
   - Verifies ArithmeticOperator expressions as arguments

5. **Test: handles calls with keyword arguments**
   - Validates `Repo.insert(changeset, returning: [:id, :name])`
   - Verifies RemoteCall with arity 2
   - Verifies second argument is properly extracted

6. **Test: anonymous function call via variable**
   - Validates `fun.(x, y)`
   - Verifies AnonymousFunctionCall type
   - Verifies hasFunctionExpression links to Variable

---

## Files Modified

| File | Lines Changed | Description |
|------|---------------|-------------|
| `test/elixir_ontologies/builders/expression_builder_test.exs` | +237 | Added 6 tests for nested and complex calls |
| `notes/features/phase-29-7-call-nesting-complexity.md` | NEW | Planning document |
| `notes/summaries/phase-29-7-call-nesting-complexity.md` | NEW | This summary document |

---

## Test Results

### Before Changes
- 398 expression builder tests (including 9 doctests)
- 134 control flow builder tests

### After Changes
- **404 expression builder tests (including 9 doctests), 0 failures** (+6 new tests)
- **134 control flow builder tests, 0 failures**
- **Total: 535 tests, 0 failures**

---

## Findings

### What Works Correctly

1. **Nested calls**: The `build_call_arguments/3` function correctly handles nested calls by recursively building expressions for each argument using `build_expression_triples/3`.

2. **IRI hierarchy**: The `fresh_iri/2` function creates unique, hierarchical IRIs for nested expressions (e.g., `expr_0/arg-0`, `expr_0/arg-0/arg-0`).

3. **Pipe operators**: The pipe operator `|>` is handled as a `PipeOperator` type with `hasLeftOperand` and `hasRightOperand` properties. Chained pipes create a proper tree structure.

4. **Complex arguments**: Arithmetic operators, variables, and literals within call arguments are correctly extracted.

5. **Call semantics**: Remote vs local vs anonymous function call distinctions are preserved in complex scenarios.

### Scope Limitations Discovered

1. **Control flow expressions**: The `if` expression is handled by `ControlFlowBuilder`, not `ExpressionBuilder`. This is correct architectural separation - control flow is handled at a higher level.

2. **Direct anonymous function calls**: Direct calls to anonymous function literals like `(fn x -> x + 1 end).(5)` are not handled by `ExpressionBuilder`. Anonymous functions must be stored in variables first, then called via `fun.(args)` pattern.

---

## Design Notes

### No New Implementation Required

The existing implementation from Phases 29.1-29.6 already handles all the complex scenarios:

- **Phase 29.1**: Remote/local call properties and `refersToFunction` linking
- **Phase 29.2**: Local call expression extraction
- **Phase 29.3**: Anonymous function call extraction
- **Phase 29.4**: Capture operator extraction
- **Phase 29.5**: Module reference extraction
- **Phase 29.6**: Function reference extraction with `FunctionReference` type

The `build_call_arguments/3` function recursively processes arguments, ensuring that nested expressions are properly extracted with correct IRI hierarchies.

---

## Known Limitations

1. **Control flow in expressions**: `if`, `case`, `cond` are handled by `ControlFlowBuilder`, not `ExpressionBuilder`. This is by design.

2. **Direct anonymous function calls**: `(fn -> end).()` pattern is not supported. Anonymous functions must be assigned to variables first.

3. **Macro calls**: Macro calls (e.g., `use GenServer`) are handled at compile time and may not appear in the AST as regular calls.

---

**Status:** ✅ COMPLETE - Ready for commit and merge

**Summary Date:** 2026-01-16
**Branch:** feature/phase-29-7-call-nesting-complexity
