# Phase 23.1: Arithmetic Operators

**Status:** ✅ Complete
**Branch:** `feature/phase-23-1-arithmetic-operators`
**Created:** 2025-01-11
**Completed:** 2025-01-11
**Target:** Implement unary arithmetic operators (unary plus and unary minus)

## 1. Problem Statement

Section 23.1 of the expressions plan covers arithmetic operators. Binary arithmetic operators (+, -, *, /, div, rem) are already implemented in Phase 22. However, **unary arithmetic operators** (unary minus and unary plus) are NOT yet implemented.

**Current State:**
- Binary arithmetic operators: ✅ Implemented (Phase 22)
- Unary logical operators (!, not): ✅ Implemented (Phase 22)
- Unary arithmetic operators (+x, -x): ❌ NOT Implemented

**Elixir AST Behavior:**

| Source Code | AST Pattern | Distinguishing Feature |
|-------------|-------------|------------------------|
| `-5` (unary) | `{:-, meta, [5]}` | Single element list |
| `5 - 3` (binary) | `{:-, meta, [5, 3]}` | Two element list |
| `+5` (unary) | `{:+, meta, [5]}` | Single element list |
| `5 + 3` (binary) | `{:+, meta, [5, 3]}` | Two element list |

**Key Challenge:**

The current handler for `:+` and `:-` expects TWO arguments (binary operator). We need to add handlers for the single-argument case (unary operator) BEFORE the binary operator handlers, so they match first.

## 2. Solution Overview

### Unary Arithmetic Operators

**Unary Minus (-x):**
- Match pattern: `{:-, _meta, [operand]}` where list has exactly 1 element
- Type class: `Core.ArithmeticOperator`
- Operator symbol: "-"
- Property: `hasOperand` (not `hasLeftOperand`/`hasRightOperand`)

**Unary Plus (+x):**
- Match pattern: `{:+, _meta, [operand]}` where list has exactly 1 element
- Type class: `Core.ArithmeticOperator` (or could be a different type)
- Operator symbol: "+"
- Property: `hasOperand`

### Handler Ordering

IMPORTANT: Unary operators must be placed BEFORE binary operators in the dispatch order because:
1. Pattern matching in Elixir is top-to-bottom
2. Binary handlers will also match unary patterns if placed first
3. We need the more specific single-argument pattern to match first

Current handler locations:
- Binary arithmetic operators: lines 260-282
- Unary logical operators: lines 251-257

**New handlers should be placed at: lines 258-259** (before binary arithmetic, after unary logical)

## 3. Implementation Plan

### Step 1: Add Unary Minus Handler
- [x] 1.1 Add handler for `{:-, _, [operand]}` pattern
- [x] 1.2 Use `build_unary_operator/4` with `Core.ArithmeticOperator`
- [x] 1.3 Place BEFORE binary minus handler
- [x] 1.4 Test unary minus with literal
- [x] 1.5 Test unary minus with variable
- [x] 1.6 Test unary minus with expression

### Step 2: Add Unary Plus Handler
- [x] 2.1 Add handler for `{:+, _, [operand]}` pattern
- [x] 2.2 Use `build_unary_operator/4` with `Core.ArithmeticOperator`
- [x] 2.3 Place BEFORE binary plus handler
- [x] 2.4 Test unary plus with literal
- [x] 2.5 Test unary plus with variable
- [x] 2.6 Test unary plus with expression

### Step 3: Add Comprehensive Tests
- [x] 3.1 Test unary minus on integer literal
- [x] 3.2 Test unary minus on float literal
- [x] 3.3 Test unary minus on variable
- [x] 3.4 Test unary minus on complex expression
- [x] 3.5 Test unary plus on integer literal
- [x] 3.6 Test unary plus on float literal
- [x] 3.7 Test nested unary operators (e.g., `- -x`)
- [x] 3.8 Test unary operator has correct operatorSymbol
- [x] 3.9 Test unary operator has hasOperand property

### Step 4: Run Verification
- [x] 4.1 Run ExpressionBuilder tests (166 tests, 0 failures)
- [x] 4.2 Run full test suite (7198 tests, 0 failures)
- [x] 4.3 Verify no regressions

## 4. Success Criteria

1. **Unary Minus Works:**
   - `-5` creates ArithmeticOperator with operatorSymbol "-"
   - `-x` creates ArithmeticOperator with hasOperand linking to x
   - `-(a + b)` creates ArithmeticOperator with operand as AdditionOperator

2. **Unary Plus Works:**
   - `+5` creates ArithmeticOperator with operatorSymbol "+"
   - `+x` creates ArithmeticOperator with hasOperand linking to x

3. **Handler Order Correct:**
   - Unary handlers match before binary handlers
   - Binary operators still work correctly
   - No pattern conflicts

4. **All Tests Pass:**
   - New unary operator tests pass
   - Existing binary operator tests still pass
   - No regressions in other parts

## 5. Files Modified

- `lib/elixir_ontologies/builders/expression_builder.ex` - Add unary operators handlers
- `test/elixir_ontologies/builders/expression_builder_test.exs` - Add tests

## 6. Progress Tracking

- [x] 6.1 Create feature branch
- [x] 6.2 Create planning document
- [x] 6.3 Implement Step 1 (Unary minus)
- [x] 6.4 Implement Step 2 (Unary plus)
- [x] 6.5 Implement Step 3 (Tests)
- [x] 6.6 Implement Step 4 (Verification)
- [x] 6.7 Write summary document
- [ ] 6.8 Ask for permission to commit and merge

## 7. Status Log

### 2025-01-11 - Initial Planning
- Created feature branch `feature/phase-23-1-arithmetic-operators`
- Analyzed Phase 23.1 requirements
- Discovered binary operators already implemented in Phase 22
- Identified unary arithmetic operators as missing functionality
- Verified AST distinguishes unary vs binary via list length
- Created planning document

### 2025-01-11 - Implementation Complete ✅
- **Step 1: Unary Minus Handler**
  - Added handler for `{:-, _, [operand]}` pattern (lines 260-262)
  - Created `build_unary_arithmetic/4` helper (lines 465-468)
  - Placed BEFORE binary minus handler to ensure correct matching

- **Step 2: Unary Plus Handler**
  - Added handler for `{:+, _, [operand]}` pattern (lines 264-266)
  - Uses same `build_unary_arithmetic/4` helper
  - Placed BEFORE binary plus handler

- **Step 3: Tests**
  - Added 9 tests for unary arithmetic operators
  - Tests cover: integer literals, float literals, variables, expressions, nested operators
  - Added helper functions `has_operand?/2` and `has_child_with_type?/3`

- **Step 4: Verification**
  - ExpressionBuilder tests: 166 tests (up from 157), 0 failures
  - Full test suite: 7198 tests, 0 failures
  - No regressions
