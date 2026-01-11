# Phase 23.5: Match and Capture Operators - Summary

**Status:** ✅ Complete
**Branch:** `feature/phase-23-5-capture-operator`
**Date:** 2025-01-11

## Overview

This phase implemented the capture operator (`&`) extraction for the Elixir Ontology ExpressionBuilder. The match operator (`=`) was already implemented in Phase 22.

## What Was Already Implemented

- **Match operator (`=`)**: ✅ Fully implemented and tested
  - Handler: line 313-314 in `expression_builder.ex`
  - Type class: `Core.MatchOperator`
  - Tests: Already present

## What Was Implemented

### Capture Operator (`&`)

**Argument Capture (`&1`, `&2`, `&3` etc.):**

- Handler pattern: `{:&, _, [arg]}` where arg is an integer
- Type class: `Core.CaptureOperator`
- Operator symbol: "&"
- Property: `RDF.value()` with the capture index (integer)

**Function Reference (`&Mod.fun/arity`, `&Mod.fun`):**

- Handler pattern: `{:&, _, [{:/, _, [function_ref, arity]}]}` for arity specified
- Handler pattern: `{:&, _, [function_ref]}` for arity inferred
- Type class: `Core.CaptureOperator`
- Operator symbol: "&"
- Properties:
  - `RDFS.label()` with descriptive label (e.g., "&Enum.map/2")
  - `RDF.value()` with arity (if specified)

## Key Design Decisions

### Ontology Property Limitations

The elixir-core.ttl ontology doesn't have dedicated properties for:
- `captureIndex` - for argument capture (&1, &2, etc.)
- `moduleName` - for function references
- `functionName` - for function references
- `arity` - for function references

**Workaround:** Use standard RDF properties:
- `RDF.value()` - for capture index and arity
- `RDFS.label()` - for descriptive function reference labels

This approach ensures the implementation works without requiring ontology changes. Future work could add dedicated properties to the ontology.

### Handler Ordering

The capture operator handlers must be placed **after** the match operator handler but **before** integer literals, because:

1. `{:&, _, [N]}` where N is an integer could conflict with the integer literal handler
2. Pattern matching is top-to-bottom
3. The capture operator pattern is more specific than the integer pattern

**Implementation locations:**
- Capture operator handlers: lines 317-330
- Integer literals start at: line 332

### Helper Functions

Created helper functions for capture operator handling:

1. **`build_capture_index/2`** - Handles argument capture (`&1`, `&2`, etc.)
   ```elixir
   defp build_capture_index(index, expr_iri) do
     [
       {expr_iri, RDF.type(), Core.CaptureOperator},
       {expr_iri, Core.operatorSymbol(), RDF.Literal.new("&")},
       {expr_iri, RDF.value(), RDF.Literal.new(index)}
     ]
   end
   ```

2. **`build_capture_function_ref/4`** - Handles function references (`&Mod.fun/arity`)
   - Extracts module and function name
   - Creates descriptive label
   - Adds arity if specified

3. **`extract_function_ref_parts/1`** - Extracts module/function from AST
4. **`extract_module_name/1`** - Extracts module name from AST
5. **`extract_function_name/1`** - Extracts function name from AST

## Test Coverage

Added 6 new tests for capture operator:

1. **dispatches &1 to CaptureOperator** - Basic argument index capture
2. **dispatches &2 to CaptureOperator** - Argument index 2
3. **dispatches &3 to CaptureOperator** - Argument index 3
4. **dispatches &Mod.fun/arity to CaptureOperator** - Function reference with arity
5. **dispatches &Mod.fun to CaptureOperator without arity** - Function reference without arity
6. **capture operator distinguishes argument index from function reference** - Differentiates the two forms

## Test Results

- **ExpressionBuilder tests:** 178 tests (up from 172), 0 failures
- **Full test suite:** 7210 tests, 0 failures, 361 excluded
- **No regressions detected**

## Files Modified

1. `lib/elixir_ontologies/builders/expression_builder.ex`
   - Added capture operator handlers (lines 317-330)
   - Added `build_capture_index/2` helper (lines 1006-1015)
   - Added `build_capture_function_ref/4` helper (lines 1018-1043)
   - Added `extract_function_ref_parts/1` helper (lines 1046-1061)
   - Added `extract_module_name/1` helper (lines 1063-1069)
   - Added `extract_function_name/1` helper (lines 1071-1075)

2. `test/elixir_ontologies/builders/expression_builder_test.exs`
   - Added "capture operator" describe block with 6 tests (lines 522-626)

3. `notes/features/phase-23-5-capture-operator.md` - Planning document
4. `notes/summaries/phase-23-5-capture-operator.md` - This summary

## AST Patterns

| Source | AST Pattern | Handler |
|--------|-------------|---------|
| `&1` | `{:&, meta, [1]}` | Argument index handler |
| `&2` | `{:&, meta, [2]}` | Argument index handler |
| `&Enum.map/2` | `{:&, meta, [{:/, meta, [function_ref, 2]}]}` | Function reference with arity |
| `&IO.inspect` | `{:&, meta, [function_ref]}` | Function reference without arity |

The key distinction is:
- Integer argument → `build_capture_index/2`
- Function reference AST → `build_capture_function_ref/4`

## Example Output

For input `&1`, the generated triples include:
- Type triple: `expr_iri a Core.CaptureOperator`
- Operator symbol: `expr_iri Core.operatorSymbol "&"`
- Capture index: `expr_iri RDF.value 1` (using RDF.value() as generic property)

For input `&Enum.map/2`, the generated triples include:
- Type triple: `expr_iri a Core.CaptureOperator`
- Operator symbol: `expr_iri Core.operatorSymbol "&"`
- Label: `expr_iri RDFS.label "&Enum.map/2"`
- Arity: `expr_iri RDF.value 2`

## Limitations and Future Work

### Current Limitations

1. **Property Mismatch:** Using `RDF.value()` and `RDFS.label()` instead of dedicated ontology properties
2. **No Anonymous Function Shorthand:** Complex forms like `&1 + &2` are not handled
3. **No Module Attribute Support:** `&@mod.fun` references not tested

### Future Enhancements

1. **Add Ontology Properties:**
   - `core:captureIndex` for argument index
   - `core:moduleName` for function references
   - `core:functionName` for function references
   - `core:arity` for function references

2. **Support Anonymous Function Shorthand:**
   - Handle `&1 + &2` style expressions
   - These create anonymous functions with captured parameters

3. **Support Module Attributes:**
   - Handle `&@mod.fun` references
   - Handle `&__MODULE__.fun` references

## Next Steps

This completes section 23.5 (Match and Capture Operators) of the expressions plan.
- Match operator: Already implemented in Phase 22
- Capture operator: Now implemented

The feature branch `feature/phase-23-5-capture-operator` is ready to be merged into the `expressions` branch.
