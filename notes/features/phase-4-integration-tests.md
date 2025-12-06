# Feature: Phase 4 Integration Tests

## Overview

Create comprehensive integration tests that verify all Phase 4 Structure Extractors work together correctly when extracting real-world Elixir modules.

## Problem Statement

While each extractor in Phase 4 has unit tests, we need integration tests that verify:
1. Extractors work together on complete module ASTs
2. Cross-references between extracted elements are correct
3. Real-world patterns (GenServer, multi-clause functions, macros) are handled properly
4. Parameter types from specs correctly correlate with function parameters

## Test Scenarios from Phase Plan

From `notes/planning/phase-04.md`:
- [ ] Test full module extraction with functions, specs, and attributes
- [ ] Test extraction of GenServer module with callbacks
- [ ] Test multi-clause function extraction preserves order
- [ ] Test parameter-to-type linking via specs
- [ ] Test macro extraction in metaprogramming-heavy module

## Implementation Plan

### Step 1: Create Integration Test File
- [x] Create `test/elixir_ontologies/extractors/phase_4_integration_test.exs`
- [x] Set up test module with async: true

### Step 2: Full Module Extraction Test
- [x] Create a complete module fixture with functions, specs, types, and attributes
- [x] Extract module and verify all components are found
- [x] Verify functions, types, specs are correctly extracted
- [x] Verify module attributes (docs, behaviours) are extracted

### Step 3: GenServer Module Test
- [x] Create GenServer module fixture with init/1, handle_call/3, handle_cast/2
- [x] Verify @behaviour GenServer is detected
- [x] Verify callback functions are extracted with correct arities
- [x] Test @impl attribute detection

### Step 4: Multi-Clause Function Test
- [x] Create function with multiple pattern-matched clauses
- [x] Extract using Clause extractor
- [x] Verify clause ordering is preserved (clause_order)
- [x] Verify guards are correctly extracted for each clause

### Step 5: Parameter-Type Linking Test
- [x] Create function with @spec
- [x] Extract both function parameters and spec parameter types
- [x] Verify parameter count matches type count
- [x] Verify type expressions are correctly parsed

### Step 6: Macro Extraction Test
- [x] Create module with defmacro and quote/unquote usage
- [x] Extract macro definitions
- [x] Extract quote blocks within macros
- [x] Verify unquote expressions are found
- [x] Test hygiene detection (var!, Macro.escape)

## Extractors to Test

| Extractor | Module | Key Functions |
|-----------|--------|---------------|
| Module | `ElixirOntologies.Extractors.Module` | `extract/2`, `module?/1` |
| Attribute | `ElixirOntologies.Extractors.Attribute` | `extract/2`, `extract_all/1` |
| Function | `ElixirOntologies.Extractors.Function` | `extract/2`, `extract_all/1` |
| Clause | `ElixirOntologies.Extractors.Clause` | `extract/2`, `extract_all_clauses/1` |
| Parameter | `ElixirOntologies.Extractors.Parameter` | `extract/2`, `extract_all/1` |
| Guard | `ElixirOntologies.Extractors.Guard` | `extract/2`, `extract_all/1` |
| ReturnExpression | `ElixirOntologies.Extractors.ReturnExpression` | `extract/2` |
| TypeDefinition | `ElixirOntologies.Extractors.TypeDefinition` | `extract/2`, `extract_all/1` |
| FunctionSpec | `ElixirOntologies.Extractors.FunctionSpec` | `extract/2`, `extract_all/1` |
| TypeExpression | `ElixirOntologies.Extractors.TypeExpression` | `extract/2` |
| Macro | `ElixirOntologies.Extractors.Macro` | `extract/2`, `extract_all/1` |
| Quote | `ElixirOntologies.Extractors.Quote` | `extract/2`, `find_unquotes/1` |

## Success Criteria

- [x] All 5 integration test scenarios passing
- [x] Tests use realistic Elixir code patterns
- [x] Tests verify cross-extractor relationships
- [x] Dialyzer passes with no errors

## Files to Create

- `test/elixir_ontologies/extractors/phase_4_integration_test.exs`

## Status

- **Current Step:** Complete
- **Tests:** 22 tests passing
- **Dialyzer:** Passing with no errors
