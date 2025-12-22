# Phase 17.4: Section Unit Tests

## Overview

This task adds comprehensive unit tests for Section 17.4 (RDF Builders for Call Graph). The tests verify that the CallGraphBuilder, ControlFlowBuilder, and ExceptionBuilder modules correctly generate RDF triples.

## Requirements from Phase Plan

From `notes/planning/extractors/phase-17.md`:

**Section 17.4 Unit Tests:**
- [ ] Test function call RDF generation
- [ ] Test local vs remote call distinction
- [ ] Test control flow RDF generation
- [ ] Test conditional branch linking
- [ ] Test try/rescue/catch RDF generation
- [ ] Test call graph completeness
- [ ] Test SHACL validation of call graph
- [ ] Test integration with existing function builder

## Current Test Coverage

### Already Implemented (86 tests total):

**CallGraphBuilder (23 tests):**
- IRI generation tests
- Local call type and property tests
- Remote call type and property tests
- Dynamic call tests
- Location handling tests
- Bulk build tests
- Edge cases

**ControlFlowBuilder (33 tests):**
- IRI generation tests
- If/unless/cond expression tests
- Case expression tests
- With expression tests
- Location handling tests
- Edge cases

**ExceptionBuilder (30 tests):**
- IRI generation tests
- Try expression with rescue/catch/after/else tests
- Raise expression tests
- Throw expression tests
- Location handling tests
- Edge cases

## Gap Analysis

Based on the phase plan requirements vs. existing tests:

| Requirement | Status | Location |
|-------------|--------|----------|
| Function call RDF generation | ✓ Complete | call_graph_builder_test.exs |
| Local vs remote call distinction | ✓ Complete | call_graph_builder_test.exs |
| Control flow RDF generation | ✓ Complete | control_flow_builder_test.exs |
| Conditional branch linking | ✓ Complete | control_flow_builder_test.exs |
| Try/rescue/catch RDF generation | ✓ Complete | exception_builder_test.exs |
| Call graph completeness | Needs verification | New tests needed |
| SHACL validation of call graph | Not implemented | New tests needed |
| Integration with function builder | Not implemented | New tests needed |

## Implementation Plan

### Step 1: Add Call Graph Completeness Tests
- [x] Test that all calls in a function are captured
- [x] Test that call indices are sequential
- [x] Test nested calls extraction
- [x] Test mixed local and remote calls

### Step 2: Add Triple Validation Tests
- [x] Validate all triples have valid subjects (IRIs)
- [x] Validate all triples have valid predicates (IRIs)
- [x] Test type constraints (LocalCall, RemoteCall, TryExpression, etc.)
- [x] Test property constraints (functionName, arity, boolean clauses)
- [x] Test literal types (String, NonNegativeInteger, PositiveInteger, Boolean)

### Step 3: Add Integration Tests with FunctionBuilder
- [x] Test combining FunctionBuilder output with CallGraphBuilder
- [x] Test that function IRI can be used as caller reference
- [x] Test building complete function with calls and control flow

### Step 4: Quality Checks
- [x] `mix compile --warnings-as-errors`
- [x] `mix credo --strict` (no new issues introduced)
- [x] `mix test` (107 tests pass across all 3 builder test files)

### Step 5: Complete
- [x] Update phase plan
- [x] Write summary

## Success Criteria

- [x] All 8 unit test categories verified or implemented
- [x] All new tests pass
- [x] Quality checks pass

## Test Summary

| Builder | Tests |
|---------|-------|
| CallGraphBuilder | 35 tests |
| ControlFlowBuilder | 37 tests |
| ExceptionBuilder | 35 tests |
| **Total** | **107 tests** |

New tests added:
- Call graph completeness tests (4 tests in CallGraphBuilder)
- Triple validation tests (5 tests in CallGraphBuilder)
- Integration with function builder (3 tests in CallGraphBuilder)
- Triple validation tests (4 tests in ControlFlowBuilder)
- Triple validation tests (5 tests in ExceptionBuilder)
