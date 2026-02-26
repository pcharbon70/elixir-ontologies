# Phase 23.5: Match and Capture Operators

**Status:** ✅ Complete
**Branch:** `feature/phase-23-5-capture-operator`
**Created:** 2025-01-11
**Target:** Implement capture operator (`&`) extraction; match operator already implemented

## 1. Problem Statement

Section 23.5 of the expressions plan covers match and capture operators.

**Current State:**
- **Match operator (`=`)**: ✅ Fully implemented and tested (line 313-314 in expression_builder.ex)
- **Capture operator (`&`)**: ❌ NOT implemented

**Elixir AST Behavior for Capture Operator:**

The `&` capture operator has multiple forms:

| Source Code | AST Pattern | Description |
|-------------|-------------|-------------|
| `&1` | `{:&, [], [1]}` | Captured first argument |
| `&2` | `{:&, [], [2]}` | Captured second argument |
| `&1 + &2` | Nested with `&` | Anonymous function shorthand |
| `&Mod.fun/arity` | `{:&, [], [{{:., ..., [:Mod, :fun]}, [], [...]}, ...]}` | Function reference |
| `&Mod.fun` | `{:&, [], [{{:., ..., [:Mod, :fun]}, ..., ...]}` | Function reference without arity |

**Key Challenge:**

The capture operator has several distinct semantic forms:
1. **Argument capture**: `&1`, `&2`, `&3` etc. - references to anonymous function parameters
2. **Function reference with arity**: `&Mod.fun/arity` - reference to named function with specified arity
3. **Function reference without arity**: `&Mod.fun` - reference to named function (arity inferred)

Each form requires different handling and property generation.

## 2. Solution Overview

### Capture Operator Forms

**Form 1: Argument Capture (`&N`)**

- AST pattern: `{:&, [], [N]}` where N is an integer
- Type class: `Core.CaptureOperator`
- Property: `captureIndex` with integer value
- No child expressions (the index is self-contained)

**Form 2: Function Reference (`&Mod.fun/arity` or `&Mod.fun`)**

- AST pattern: `{:&, [], [function_reference_ast, optional_arity]}`
- Type class: `Core.CaptureOperator` (or possibly `Core.FunctionReference`)
- Properties:
  - `functionName` - the function being referenced
  - `moduleName` - the module containing the function
  - `arity` - the function arity (if specified)
- May need to extract child expressions for complex function references

**Form 3: Anonymous Function Shorthand (`&1 + &2`)**

- AST pattern: Expressions containing nested `&` captures
- These create anonymous functions with captured parameters
- May need special handling as `AnonymousFunctionExpression`

### Implementation Approach

1. Add handler for `{:&, _, [arg]}` pattern
2. Distinguish between integer argument capture and function reference
3. For integer capture: generate `captureIndex` property
4. For function reference: extract module, function, and arity information
5. Add comprehensive tests for all capture forms

## 3. Implementation Plan

### Step 1: Add Capture Operator Handler
- [x] 1.1 Add handler for `{:&, _, [arg]}` pattern in `build_expression_triples/3`
- [x] 1.2 Create `build_capture_operator/4` helper function
- [x] 1.3 Implement argument index capture for `&N` pattern
- [x] 1.4 Implement function reference extraction for `&Mod.fun/arity`

### Step 2: Add Capture Operator Properties
- [x] 2.1 Generate `Core.CaptureOperator` type triple
- [x] 2.2 Generate `operatorSymbol` triple with "&"
- [x] 2.3 For `&N`: Generate `captureIndex` property (using RDF.value())
- [x] 2.4 For function refs: Generate `functionName`, `moduleName`, `arity` properties (using RDFS.label())
- [x] 2.5 Determine if `CaptureOperator` ontology has required properties

### Step 3: Add Comprehensive Tests
- [x] 3.1 Test capture operator for `&1` (argument index 1)
- [x] 3.2 Test capture operator for `&2`, `&3` (other argument indices)
- [x] 3.3 Test capture operator for `&Mod.fun/arity` (function reference with arity)
- [x] 3.4 Test capture operator for `&Mod.fun` (function reference without arity)
- [x] 3.5 Test capture operator distinguishes capture types

### Step 4: Run Verification
- [x] 4.1 Run ExpressionBuilder tests (178 tests, 0 failures)
- [x] 4.2 Run full test suite (7210 tests, 0 failures)
- [x] 4.3 Verify no regressions

## 4. Technical Details

### File Locations

- **Implementation:** `lib/elixir_ontologies/builders/expression_builder.ex`
  - Add handler around line 315 (after match operator)
  - Add helper function in private functions section

- **Tests:** `test/elixir_ontologies/builders/expression_builder_test.exs`
  - Add "capture operator" describe block

### Ontology Properties to Check

Need to verify the ontology has these properties for `Core.CaptureOperator`:
- `captureIndex` - for `&N` argument capture
- `functionName` - for function references
- `moduleName` - for function references
- `arity` - for function references

If these properties don't exist, we may need to:
1. Use generic properties, or
2. Note this as a limitation for future ontology enhancement

## 5. Success Criteria

1. **Argument capture works:** `&1`, `&2`, `&3` create `Core.CaptureOperator` with index
2. **Function reference works:** `&Mod.fun/arity` creates appropriate reference properties
3. **All tests pass:** New capture operator tests pass
4. **No regressions:** Existing tests still pass

## 6. Progress Tracking

- [x] 6.1 Create feature branch
- [x] 6.2 Create planning document
- [x] 6.3 Check ontology for required properties
- [x] 6.4 Implement capture operator handler
- [x] 6.5 Add capture operator properties
- [x] 6.6 Add comprehensive tests
- [x] 6.7 Run verification
- [x] 6.8 Write summary document
- [ ] 6.9 Ask for permission to commit and merge

## 7. Status Log

### 2025-01-11 - Initial Planning
- Created feature branch `feature/phase-23-5-capture-operator`
- Analyzed Phase 23.5 requirements
- Confirmed match operator already implemented
- Identified capture operator as missing functionality
- Researched Elixir AST patterns for capture operator
- Created planning document

### 2025-01-11 - Implementation Complete ✅
- **Step 1: Handler Implementation**
  - Added capture operator handlers for argument indices (lines 320-322)
  - Added capture operator handlers for function references (lines 324-330)
  - Created helper functions for building capture triples (lines 1006-1075)

- **Step 2: Properties**
  - Used `RDF.value()` for capture index and arity (ontology limitation workaround)
  - Used `RDFS.label()` for descriptive function reference labels
  - Note: Ontology doesn't have dedicated captureIndex, moduleName, functionName properties

- **Step 3: Tests**
  - Added 6 tests for capture operator coverage
  - Tests cover: argument indices (&1, &2, &3), function references with/without arity
  - Tests distinguish between argument capture and function reference forms

- **Step 4: Verification**
  - ExpressionBuilder tests: 178 tests (up from 172), 0 failures
  - Full test suite: 7210 tests, 0 failures, 361 excluded
  - No regressions detected
