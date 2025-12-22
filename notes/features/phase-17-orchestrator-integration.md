# Phase 17 Orchestrator Integration

## Problem Statement

The Phase 17 builders (CallGraphBuilder, ControlFlowBuilder, ExceptionBuilder) exist as standalone modules but are not integrated into the Orchestrator. This means:

1. When analyzing files with `Pipeline.analyze_and_build/3`, call graphs, control flow, and exception handling are not included in the RDF output
2. The Phase 17 extractors (Call, Conditional, CaseWith, Comprehension, Exception, Pipe) are not invoked during file analysis
3. Integration tests cannot verify end-to-end behavior

## Solution Overview

Integrate Phase 17 builders into the existing Orchestrator pipeline by:

1. **Extend ModuleAnalysis struct** - Add fields for calls, control_flow, and exceptions
2. **Add extractors to FileAnalyzer** - Extract calls, control flow, and exceptions during analysis
3. **Add builders to Orchestrator** - Include Phase 17 builders in the Phase 2 parallel execution
4. **Update Pipeline conversion** - Map new ModuleAnalysis fields to Orchestrator format

## Implementation Plan

### Step 1: Extend ModuleAnalysis Struct ✅
- [x] Add `calls` field (list)
- [x] Add `control_flow` field (map with conditionals, cases, withs, receives, comprehensions)
- [x] Add `exceptions` field (map with tries, raises, throws, exits)
- [x] Update typespec

### Step 2: Add Extractors to FileAnalyzer ✅
- [x] Add `extract_calls/1` function
- [x] Add `extract_control_flow/1` function
- [x] Add `extract_exceptions/1` function
- [x] Wire up in `extract_module_content/3`

### Step 3: Add Builders to Orchestrator ✅
- [x] Add aliases for CallGraphBuilder, ControlFlowBuilder, ExceptionBuilder
- [x] Add `build_calls/3` function
- [x] Add `build_control_flow/3` function (conditionals, cases, withs)
- [x] Add `build_exceptions/3` function (tries, raises, throws)
- [x] Register in `build_phase_2/7` builders list

### Step 4: Update Pipeline Conversion ✅
- [x] Update `convert_module_analysis/1` to extract calls
- [x] Update to extract control_flow components
- [x] Update to extract exceptions components

### Step 5: Add Integration Tests ✅
- [x] Test Pipeline with call extraction
- [x] Test Pipeline with control flow extraction
- [x] Test Orchestrator coordination with Phase 17 builders
- [x] Test empty Phase 17 data handling

### Step 6: Quality Checks ✅
- [x] `mix compile --warnings-as-errors`
- [x] `mix credo --strict`
- [x] `mix test`

## Current Status

### Completed
1. ✅ Extended ModuleAnalysis struct with Phase 17 fields
2. ✅ Added Phase 17 extractors to FileAnalyzer
3. ✅ Integrated Phase 17 builders into Orchestrator
4. ✅ Updated Pipeline conversion
5. ✅ Added 4 integration tests
6. ✅ All quality checks pass

### Limitations
- `build_receive` and `build_comprehension` not yet in ControlFlowBuilder
- `build_exit` not yet in ExceptionBuilder (available in review-improvements branch)
- These are extracted but not built to RDF

## Files Modified

### Implementation (3 files)
1. `lib/elixir_ontologies/analyzer/file_analyzer.ex`
   - Extended ModuleAnalysis struct with calls, control_flow, exceptions
   - Added extract_calls/1, extract_control_flow/1, extract_exceptions/1
2. `lib/elixir_ontologies/builders/orchestrator.ex`
   - Added Phase 17 builder aliases
   - Added build_calls/3, build_control_flow/3, build_exceptions/3
   - Added helper builders and derive_containing_function/1
3. `lib/elixir_ontologies/pipeline.ex`
   - Updated convert_module_analysis/1 to include Phase 17 fields

### Tests (1 file)
1. `test/elixir_ontologies/phase17_integration_test.exs`
   - Added Pipeline integration tests
   - Added Orchestrator coordination tests

### Documentation (2 files)
1. `notes/features/phase-17-orchestrator-integration.md` - This plan
2. `notes/summaries/phase-17-orchestrator-integration.md` - Summary

## How to Run
```bash
# Run Phase 17 integration tests
mix test test/elixir_ontologies/phase17_integration_test.exs

# Run all tests
mix test

# Quality checks
mix compile --warnings-as-errors
mix credo --strict
```

## Notes

- Phase 17 builders use `containing_function` option derived from module IRI
- For module-level expressions, uses `ModuleName/module/0` format
- Control flow and exception structures are per-module (not per-function) in current implementation
