# Phase 11.4.1: Remove pySHACL Implementation - Implementation Plan

## Executive Summary

Phase 11.4.1 removes all pySHACL-related code and transitions the public API to use the native Elixir SHACL implementation completed in Phases 11.1-11.3. This completes the migration from external Python dependency to pure Elixir validation.

**Status**: ✅ Planning Complete → 🚧 Ready for Implementation
**Dependencies**: Phase 11.3.1 (Complete - SPARQL Evaluator), native SHACL stack complete (262 tests)
**Target**: Remove pySHACL, update public API, clean up all references

## Context & Architecture

### What We Have (Built in Previous Phases)

**Complete Native SHACL Stack (262 tests):**
- Phase 11.1: SHACL Infrastructure (Reader, Writer, Models) - 113 tests
- Phase 11.2: Core Validation (Validators, Orchestration) - 132 tests
- Phase 11.3: SPARQL Constraints - 17 tests

**Old pySHACL Implementation (to be removed):**
- `lib/elixir_ontologies/validator/shacl_engine.ex` - Python wrapper
- Test files with `:requires_pyshacl` tags
- `Validator.available?/0` and `installation_instructions/0` functions
- Mix task pySHACL availability checks

### What We're Removing (Phase 11.4.1)

All pySHACL-related code and dependencies:

1. **Delete pySHACL wrapper code**
2. **Update Validator public API** to use native SHACL
3. **Remove dependency checks** and installation instructions
4. **Clean up test tags** (`:requires_pyshacl`)
5. **Update Mix tasks** for native validation

## Implementation Status

### ✅ Completed Tasks

- [x] Planning document created
- [x] Feature branch created: `feature/phase-11-4-1-remove-pyshacl`

### 📋 Pending

- [ ] Step 1: Identify and catalog all pySHACL references
- [ ] Step 2: Delete pySHACL wrapper code
- [ ] Step 3: Update Validator public API
- [ ] Step 4: Update Mix tasks
- [ ] Step 5: Clean up tests and verify

## Detailed Design

### Files to Delete

Based on Phase 11 plan:

1. **lib/elixir_ontologies/validator/shacl_engine.ex** - pySHACL wrapper
2. All pySHACL-specific test files (if any exist separately)

### Files to Modify

1. **lib/elixir_ontologies/validator.ex**
   - Remove `available?/0` function
   - Remove `installation_instructions/0` function
   - Update `validate/2` to call native `SHACL.Validator.run/3`
   - Remove pySHACL-specific error handling

2. **lib/mix/tasks/elixir_ontologies.analyze.ex**
   - Remove pySHACL availability checks
   - Update validation output formatting for native reports
   - Update error reporting

3. **Test files**
   - Remove all `:requires_pyshacl` tags
   - Update tests to work with native validation

### Public API Design

**Current (pySHACL-based):**
```elixir
defmodule ElixirOntologies.Validator do
  def available?(), do: ...  # Check if pySHACL is installed
  def installation_instructions(), do: ...
  def validate(graph, shapes_graph), do: ...  # Calls pySHACL
end
```

**After (Native SHACL):**
```elixir
defmodule ElixirOntologies.Validator do
  alias ElixirOntologies.SHACL

  def validate(graph, shapes_graph, opts \\\\ []) do
    SHACL.Validator.run(graph, shapes_graph, opts)
  end
end
```

## Implementation Sequence

### Step 1: Identify and Catalog pySHACL References

**Tasks**:
1. Search codebase for pySHACL-related files
2. Identify all `:requires_pyshacl` test tags
3. Find `shacl_engine` references
4. Document what needs to be changed

**Commands**:
```bash
grep -r "shacl_engine" lib/ test/
grep -r "requires_pyshacl" test/
grep -r "available?" lib/
grep -r "installation_instructions" lib/
```

### Step 2: Delete pySHACL Wrapper Code

**Tasks**:
1. Delete `lib/elixir_ontologies/validator/shacl_engine.ex`
2. Delete any pySHACL-specific test files
3. Verify no broken imports

### Step 3: Update Validator Public API

**Tasks**:
1. Open `lib/elixir_ontologies/validator.ex`
2. Remove `available?/0` function
3. Remove `installation_instructions/0` function
4. Update `validate/2` to delegate to `SHACL.Validator.run/3`
5. Update module documentation
6. Add proper error handling for native validation

**Implementation**:
```elixir
defmodule ElixirOntologies.Validator do
  @moduledoc """
  Public API for SHACL validation of RDF graphs.

  This module provides a simple interface to validate RDF graphs against
  SHACL shapes using the native Elixir SHACL implementation.
  """

  alias ElixirOntologies.SHACL.Validator, as: SHACLValidator

  @doc """
  Validate an RDF graph against SHACL shapes.

  ## Parameters

  - `data_graph` - RDF.Graph.t() to validate
  - `shapes_graph` - RDF.Graph.t() containing SHACL shapes
  - `opts` - Keyword list of options (passed to SHACL.Validator.run/3)

  ## Returns

  - `{:ok, ValidationReport.t()}` - Validation completed
  - `{:error, reason}` - Validation failed

  ## Examples

      {:ok, data} = RDF.Turtle.read_file("data.ttl")
      {:ok, shapes} = RDF.Turtle.read_file("shapes.ttl")
      {:ok, report} = Validator.validate(data, shapes)

      if report.conforms? do
        IO.puts("Valid!")
      else
        IO.puts("Found violations:")
        Enum.each(report.results, fn result ->
          IO.puts("  - #{result.message}")
        end)
      end
  """
  @spec validate(RDF.Graph.t(), RDF.Graph.t(), keyword()) ::
          {:ok, SHACL.Model.ValidationReport.t()} | {:error, term()}
  def validate(data_graph, shapes_graph, opts \\\\ []) do
    SHACLValidator.run(data_graph, shapes_graph, opts)
  end
end
```

### Step 4: Update Mix Tasks

**Tasks**:
1. Open `lib/mix/tasks/elixir_ontologies.analyze.ex`
2. Remove pySHACL availability checks
3. Update validation output formatting
4. Test `mix elixir_ontologies.analyze --validate`

**Changes needed**:
- Remove any `if Validator.available?()` checks
- Update error messages to reflect native implementation
- Ensure validation report formatting works with native ValidationReport struct

### Step 5: Clean Up Tests and Verify

**Tasks**:
1. Remove all `:requires_pyshacl` tags from test files
2. Update any tests that expect pySHACL-specific behavior
3. Run full test suite to verify everything works
4. Verify Mix task works end-to-end

**Test Commands**:
```bash
# Remove tags
grep -r "@tag :requires_pyshacl" test/ | cut -d: -f1 | sort -u

# Run all tests
mix test

# Test Mix task
mix elixir_ontologies.analyze --validate
```

## Success Criteria

- [ ] All pySHACL code deleted
- [ ] `available?/0` and `installation_instructions/0` functions removed
- [ ] `Validator.validate/2` uses native SHACL implementation
- [ ] All `:requires_pyshacl` tags removed from tests
- [ ] Mix task `--validate` flag works with native implementation
- [ ] All existing tests pass (no regressions)
- [ ] Documentation updated to reflect native implementation
- [ ] No references to pySHACL remain in codebase

## Implementation Checklist

### Code Changes

- [ ] Delete `lib/elixir_ontologies/validator/shacl_engine.ex`
- [ ] Update `lib/elixir_ontologies/validator.ex`
  - [ ] Remove `available?/0`
  - [ ] Remove `installation_instructions/0`
  - [ ] Update `validate/2` to use SHACL.Validator.run/3
  - [ ] Update @moduledoc
- [ ] Update `lib/mix/tasks/elixir_ontologies.analyze.ex`
  - [ ] Remove pySHACL availability checks
  - [ ] Update validation output formatting
  - [ ] Update error messages

### Test Cleanup

- [ ] Find and remove all `:requires_pyshacl` tags
- [ ] Update tests expecting pySHACL-specific behavior
- [ ] Verify all tests pass

### Verification

- [ ] Run `mix test` - all tests pass
- [ ] Run `mix elixir_ontologies.analyze --validate` - works correctly
- [ ] Verify no pySHACL references: `grep -r "pyshacl" . --exclude-dir=.git`
- [ ] Verify no `available?` references remain
- [ ] Documentation review

## Risk Analysis

**Low Risk:**
- Native SHACL implementation is complete and well-tested (262 tests)
- Clear migration path from pySHACL to native
- No external dependencies being added

**Potential Issues:**
- Tests might expect pySHACL-specific validation report format
- Mix task output formatting might need adjustment
- Some tests might be skipped with `:requires_pyshacl` and need updating

**Mitigations:**
- Careful review of test changes
- Run full test suite before and after
- Test Mix task manually
- Check validation report compatibility

## Expected Outcomes

**Before:**
- External Python dependency required (pySHACL)
- Validation requires Python environment
- Installation complexity
- Performance overhead from Python interop

**After:**
- Pure Elixir implementation
- No external dependencies
- Native performance
- Easier installation and deployment
- 262 comprehensive tests

## Notes

- This is primarily a deletion/cleanup task
- Native implementation already complete and tested
- Should be straightforward with no new functionality
- Main risk is ensuring compatibility with existing usage patterns
