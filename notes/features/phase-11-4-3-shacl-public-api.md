# Phase 11.4.3: Create SHACL Public API - Implementation Plan

## Executive Summary

Phase 11.4.3 creates a clean, well-documented public API module (`ElixirOntologies.SHACL`) as the main entry point for SHACL validation functionality. This consolidates the existing internal SHACL modules into a user-friendly public interface.

**Status**: ✅ Planning Complete → 🚧 Ready for Implementation
**Dependencies**: Phase 11.4.1 (Complete), Phase 11.4.2 (Complete)
**Target**: Create public API module with comprehensive documentation and 10+ tests

## Context & Architecture

### What We Have (Built in Previous Phases)

**Complete Native SHACL Stack (262 tests):**
- `SHACL.Validator` - Main orchestration engine (internal)
- `SHACL.Reader` - Parses SHACL shapes from RDF
- `SHACL.Writer` - Serializes ValidationReport to RDF/Turtle
- `SHACL.Model.*` - Data structures (NodeShape, PropertyShape, ValidationReport, etc.)
- `SHACL.Validators.*` - 6 constraint validators (cardinality, type, string, value, qualified, SPARQL)

**Current Public API:**
- `ElixirOntologies.Validator.validate/2` - Validates Graph struct with options

### What We're Building (Phase 11.4.3)

A **new public API module** (`lib/elixir_ontologies/shacl.ex`) that provides:

1. **Clean Entry Point**: `ElixirOntologies.SHACL` as the main module
2. **Core Validation**: `validate/3` - validates RDF graphs with SHACL shapes
3. **Convenience Functions**: `validate_file/3` - validates files directly
4. **Comprehensive Documentation**: Examples, usage patterns, options
5. **Integration Tests**: 10+ tests for public API usage

## Problem Statement

**Current Situation:**
- Internal SHACL modules (`SHACL.Validator`, `SHACL.Reader`, etc.) are implementation details
- Users must know to call `SHACL.Validator.run/3` directly
- No consolidated entry point for SHACL functionality
- Documentation scattered across internal modules
- No convenience functions for common use cases

**Impact:**
- Harder to discover how to use SHACL validation
- Users exposed to internal implementation details
- No clear separation between public API and internals
- Difficult to version and evolve the API

**Desired Outcome:**
- Single, well-documented entry point: `ElixirOntologies.SHACL`
- Clear public API with `validate/3` and `validate_file/3`
- Comprehensive documentation with examples
- Clean separation between public API and internal modules
- Easy to use, easy to discover

## Solution Overview

### Design Decisions

1. **Module Location**: `lib/elixir_ontologies/shacl.ex`
   - Top-level SHACL module for easy discovery
   - Delegates to internal `SHACL.Validator.run/3`

2. **API Functions**:
   - `validate/3` - Main validation function (RDF graphs)
   - `validate_file/3` - Convenience for validating files
   - Consistent signature: `(data, shapes, opts \\ [])`

3. **Return Type**: Same as internal validator
   - `{:ok, ValidationReport.t()}` on success
   - `{:error, reason}` on failure

4. **Options**: Pass-through to `SHACL.Validator.run/3`
   - `:parallel` - Enable parallel validation
   - `:max_concurrency` - Max concurrent tasks
   - `:timeout` - Validation timeout per shape

5. **Documentation Strategy**:
   - Comprehensive @moduledoc with overview and examples
   - @doc for each function with usage examples
   - @spec typespecs for all public functions
   - Link to internal modules for advanced usage

### Architecture

```
ElixirOntologies.SHACL (public API)
  ├── validate/3           → SHACL.Validator.run/3
  ├── validate_file/3      → read files + validate/3
  └── (future: validate_string/3, validate_graph/3, etc.)

Internal Modules (unchanged):
  ├── SHACL.Validator      (orchestration)
  ├── SHACL.Reader         (shape parsing)
  ├── SHACL.Writer         (report serialization)
  ├── SHACL.Model.*        (data structures)
  └── SHACL.Validators.*   (constraint validation)
```

## Implementation Status

### ✅ Completed Tasks

- [x] Planning document created
- [x] Feature branch created: `feature/phase-11-4-3-shacl-public-api`

### 📋 Pending

- [ ] Step 1: Create `lib/elixir_ontologies/shacl.ex` module structure
- [ ] Step 2: Implement `validate/3` function
- [ ] Step 3: Implement `validate_file/3` convenience function
- [ ] Step 4: Add comprehensive documentation
- [ ] Step 5: Write public API integration tests (10+ tests)

## Detailed Design

### Module Structure

**File**: `lib/elixir_ontologies/shacl.ex`

```elixir
defmodule ElixirOntologies.SHACL do
  @moduledoc """
  Public API for SHACL validation of RDF graphs.

  This module provides a clean, well-documented interface for validating
  RDF graphs against SHACL shapes using the native Elixir SHACL implementation.

  ## Quick Start

      # Validate RDF graphs
      {:ok, data} = RDF.Turtle.read_file("data.ttl")
      {:ok, shapes} = RDF.Turtle.read_file("shapes.ttl")
      {:ok, report} = SHACL.validate(data, shapes)

      if report.conforms? do
        IO.puts("Valid!")
      else
        IO.puts("Found violations:")
        Enum.each(report.results, fn r ->
          IO.puts("  - #{r.message}")
        end)
      end

      # Validate files directly
      {:ok, report} = SHACL.validate_file("data.ttl", "shapes.ttl")

  ## Features

  - Native Elixir implementation (no external dependencies)
  - Supports core SHACL constraints (cardinality, type, string, value, qualified)
  - Supports SPARQL-based constraints for complex rules
  - Parallel validation for performance
  - Structured validation reports

  ## Options

  - `:parallel` - Enable parallel validation (default: true)
  - `:max_concurrency` - Max concurrent tasks (default: System.schedulers_online())
  - `:timeout` - Validation timeout per shape in ms (default: 5000)

  ## See Also

  - `SHACL.Validator` - Internal orchestration engine
  - `SHACL.Model.ValidationReport` - Report structure
  - `SHACL.Model.ValidationResult` - Individual violation details
  """

  alias ElixirOntologies.SHACL.{Validator, Model}

  @typedoc "SHACL validation options"
  @type option ::
          {:parallel, boolean()}
          | {:max_concurrency, pos_integer()}
          | {:timeout, timeout()}

  @typedoc "SHACL validation result"
  @type validation_result ::
          {:ok, Model.ValidationReport.t()} | {:error, term()}

  @doc """
  Validates an RDF data graph against SHACL shapes.

  ## Parameters

  - `data_graph` - RDF.Graph.t() containing the data to validate
  - `shapes_graph` - RDF.Graph.t() containing SHACL shapes
  - `opts` - Keyword list of options (see module docs)

  ## Returns

  - `{:ok, report}` - Validation completed, check `report.conforms?`
  - `{:error, reason}` - Validation failed

  ## Examples

      # Basic validation
      {:ok, data} = RDF.Turtle.read_file("data.ttl")
      {:ok, shapes} = RDF.Turtle.read_file("shapes.ttl")
      {:ok, report} = SHACL.validate(data, shapes)

      if report.conforms? do
        IO.puts("Valid!")
      else
        IO.puts("Found #{length(report.results)} violations")
      end

      # With options
      {:ok, report} = SHACL.validate(data, shapes,
        parallel: false,
        timeout: 10_000
      )
  """
  @spec validate(RDF.Graph.t(), RDF.Graph.t(), [option()]) :: validation_result()
  def validate(data_graph, shapes_graph, opts \\ []) do
    Validator.run(data_graph, shapes_graph, opts)
  end

  @doc """
  Validates RDF files directly.

  Convenience function that reads Turtle files and validates them.

  ## Parameters

  - `data_file` - Path to Turtle file with data
  - `shapes_file` - Path to Turtle file with SHACL shapes
  - `opts` - Keyword list of options (see module docs)

  ## Returns

  - `{:ok, report}` - Validation completed
  - `{:error, reason}` - File read or validation failed

  ## Examples

      # Validate files
      {:ok, report} = SHACL.validate_file("data.ttl", "shapes.ttl")

      # With options
      {:ok, report} = SHACL.validate_file(
        "data.ttl",
        "shapes.ttl",
        parallel: false
      )
  """
  @spec validate_file(Path.t(), Path.t(), [option()]) :: validation_result()
  def validate_file(data_file, shapes_file, opts \\ []) do
    with {:ok, data_graph} <- read_turtle_file(data_file, :data),
         {:ok, shapes_graph} <- read_turtle_file(shapes_file, :shapes) do
      validate(data_graph, shapes_graph, opts)
    end
  end

  # Private helper to read Turtle files with error context
  @spec read_turtle_file(Path.t(), :data | :shapes) ::
          {:ok, RDF.Graph.t()} | {:error, term()}
  defp read_turtle_file(path, type) do
    case RDF.Turtle.read_file(path) do
      {:ok, graph} ->
        {:ok, graph}

      {:error, reason} ->
        {:error, {:file_read_error, type, path, reason}}
    end
  end
end
```

## Implementation Sequence

### Step 1: Create Module Structure ✅ Planning Complete

**Tasks**:
1. Create `lib/elixir_ontologies/shacl.ex`
2. Add @moduledoc with overview and quick start
3. Add module aliases and type definitions
4. Add basic module structure

**Deliverable**: Module file exists with documentation skeleton

### Step 2: Implement `validate/3` Function

**Tasks**:
1. Implement `validate/3` function
2. Add @doc with comprehensive examples
3. Add @spec typespec
4. Delegate to `SHACL.Validator.run/3`
5. Test basic validation

**Deliverable**: `validate/3` works and passes basic tests

### Step 3: Implement `validate_file/3` Convenience Function

**Tasks**:
1. Implement `validate_file/3` function
2. Add @doc with file-based examples
3. Add @spec typespec
4. Implement file reading with error handling
5. Add private `read_turtle_file/2` helper
6. Test file validation

**Deliverable**: `validate_file/3` works and passes file-based tests

### Step 4: Add Comprehensive Documentation

**Tasks**:
1. Review and enhance @moduledoc
2. Add detailed usage examples
3. Add links to related modules
4. Document all options
5. Add "See Also" section
6. Review documentation for clarity

**Deliverable**: Module has excellent documentation

### Step 5: Write Public API Integration Tests (10+ tests)

**Tasks**:
1. Create `test/elixir_ontologies/shacl_test.exs`
2. Test `validate/3` with conformant data
3. Test `validate/3` with non-conformant data
4. Test `validate/3` with options
5. Test `validate_file/3` with valid files
6. Test `validate_file/3` with invalid file paths
7. Test `validate_file/3` with malformed Turtle
8. Test error handling and edge cases
9. Test integration with existing SHACL stack
10. Test backward compatibility with Validator module

**Deliverable**: 10+ comprehensive tests all passing

## Testing Strategy

### Test Organization

**File**: `test/elixir_ontologies/shacl_test.exs`

**Target**: 10+ tests

### Test Structure

```elixir
defmodule ElixirOntologies.SHACLTest do
  use ExUnit.Case, async: true

  import RDF.Sigils
  alias ElixirOntologies.SHACL

  describe "validate/3" do
    test "validates conformant data against shapes"
    test "detects violations in non-conformant data"
    test "returns proper ValidationReport structure"
    test "accepts parallel option"
    test "accepts timeout option"
    test "handles empty data graph"
    test "handles empty shapes graph"
  end

  describe "validate_file/3" do
    test "validates Turtle files successfully"
    test "returns error for missing data file"
    test "returns error for missing shapes file"
    test "returns error for malformed Turtle in data file"
    test "returns error for malformed Turtle in shapes file"
    test "accepts validation options"
  end

  describe "integration" do
    test "works with real elixir-shapes.ttl"
    test "validates analyzed Elixir code graphs"
    test "backward compatible with SHACL.Validator.run/3"
  end
end
```

### Test Fixtures

**Create test fixture files:**
- `test/fixtures/shacl/valid_data.ttl` - Conformant data
- `test/fixtures/shacl/invalid_data.ttl` - Non-conformant data
- `test/fixtures/shacl/simple_shapes.ttl` - Simple SHACL shapes
- `test/fixtures/shacl/malformed.ttl` - Invalid Turtle syntax

## Success Criteria

- [ ] `ElixirOntologies.SHACL` module created
- [ ] `validate/3` function implemented and documented
- [ ] `validate_file/3` convenience function implemented
- [ ] Comprehensive @moduledoc with quick start and examples
- [ ] All functions have @doc and @spec
- [ ] 10+ integration tests all passing
- [ ] Tests cover success cases, error cases, and edge cases
- [ ] Backward compatible with existing `SHACL.Validator.run/3`
- [ ] Documentation reviewed for clarity and completeness
- [ ] Phase 11 planning document updated

## Implementation Checklist

### Code

- [ ] Create `lib/elixir_ontologies/shacl.ex`
- [ ] Add comprehensive @moduledoc with overview
- [ ] Add module aliases (`alias ElixirOntologies.SHACL.{Validator, Model}`)
- [ ] Add type definitions (`@type option`, `@type validation_result`)
- [ ] Implement `validate/3` function
- [ ] Add @doc for `validate/3` with examples
- [ ] Add @spec for `validate/3`
- [ ] Implement `validate_file/3` function
- [ ] Add @doc for `validate_file/3` with examples
- [ ] Add @spec for `validate_file/3`
- [ ] Implement `read_turtle_file/2` private helper
- [ ] Add quick start examples in @moduledoc
- [ ] Add "See Also" section linking to internal modules

### Tests

- [ ] Create `test/elixir_ontologies/shacl_test.exs`
- [ ] Create test fixture directory `test/fixtures/shacl/`
- [ ] Create fixture files (valid_data.ttl, invalid_data.ttl, simple_shapes.ttl, malformed.ttl)
- [ ] Test `validate/3` with conformant data
- [ ] Test `validate/3` with non-conformant data
- [ ] Test `validate/3` with options (parallel, timeout)
- [ ] Test `validate/3` with empty graphs
- [ ] Test `validate_file/3` with valid files
- [ ] Test `validate_file/3` with missing files
- [ ] Test `validate_file/3` with malformed Turtle
- [ ] Test `validate_file/3` with options
- [ ] Test integration with real elixir-shapes.ttl
- [ ] Test backward compatibility with SHACL.Validator.run/3
- [ ] Verify all 10+ tests passing

### Documentation

- [ ] Review @moduledoc for clarity
- [ ] Ensure quick start example is clear and complete
- [ ] Add feature list to @moduledoc
- [ ] Document all options with defaults
- [ ] Add @doc to all public functions
- [ ] Add usage examples to all @doc blocks
- [ ] Add @spec typespecs to all public functions
- [ ] Link to related modules and structs
- [ ] Review documentation for completeness

### Integration

- [ ] Update Phase 11 planning document to mark 11.4.3 complete
- [ ] Write implementation summary
- [ ] Verify backward compatibility
- [ ] Run full test suite (should be 2912+ tests)
- [ ] No regressions in existing tests

## Dependencies & Prerequisites

**External Libraries:**
- ✅ RDF.ex - Already installed
- ✅ SPARQL.ex - Already installed (for SPARQL constraints)

**Internal Dependencies:**
- ✅ SHACL.Validator - Already implemented (Phase 11.2.2)
- ✅ SHACL.Model.ValidationReport - Already implemented (Phase 11.1.1)
- ✅ SHACL.Model.ValidationResult - Already implemented (Phase 11.1.1)
- ✅ All constraint validators - Already implemented (Phases 11.2.1, 11.3.1)

## Risk Analysis

**Low Risk:**
- Simple delegation to existing `SHACL.Validator.run/3`
- No new validation logic, just API surface
- Existing SHACL stack is complete and tested (262 tests)

**Medium Risk:**
- File I/O in `validate_file/3` could have edge cases
- Error message formatting for file read errors

**Mitigations:**
- Comprehensive error handling in `validate_file/3`
- Test file read errors (missing files, malformed Turtle, permissions)
- Clear error messages with file context

## Expected Outcomes

**Before:**
```elixir
# Users must know internal API
alias ElixirOntologies.SHACL.Validator

{:ok, data} = RDF.Turtle.read_file("data.ttl")
{:ok, shapes} = RDF.Turtle.read_file("shapes.ttl")
{:ok, report} = Validator.run(data, shapes)
```

**After:**
```elixir
# Clean public API
alias ElixirOntologies.SHACL

# Option 1: Direct graph validation
{:ok, data} = RDF.Turtle.read_file("data.ttl")
{:ok, shapes} = RDF.Turtle.read_file("shapes.ttl")
{:ok, report} = SHACL.validate(data, shapes)

# Option 2: Convenience file validation
{:ok, report} = SHACL.validate_file("data.ttl", "shapes.ttl")
```

**Benefits:**
- ✅ Easier to discover and use
- ✅ Better documentation at entry point
- ✅ Convenience functions for common use cases
- ✅ Clear separation of public API vs internals
- ✅ Easier to version and evolve

## Notes

- This is a **pure API enhancement** - no new validation logic
- All validation functionality already exists in internal modules
- Focus is on **usability, documentation, and discoverability**
- `validate/3` is a thin wrapper around `SHACL.Validator.run/3`
- `validate_file/3` adds file I/O convenience
- Tests focus on **integration and error handling**, not core validation (already tested)
