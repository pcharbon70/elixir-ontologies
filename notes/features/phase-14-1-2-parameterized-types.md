# Feature: Phase 14.1.2 - Parameterized Types (Generics)

## Problem Statement

Task 14.1.2 from the Phase 14 plan calls for implementing parameterized type extraction. Upon review, the existing `TypeExpression` extractor already handles parameterized types:

**Current Implementation:**
- Basic types with parameters (`list(integer())`) are parsed as `kind: :basic` with `parameterized: true` in metadata
- Type parameters are stored in the `elements` field
- Remote types with parameters also track `parameterized: true`

**What's Missing (from subtasks):**
1. Position tracking for type parameters (like union types have)
2. Comprehensive tests for all parameterized type patterns
3. Better support for nested parameterized types verification

**Design Decision:** Rather than introducing a new `kind: :parameterized`, which would break existing code and tests, we will enhance the current approach by:
- Adding position tracking (`param_position`) to type parameters
- Adding `param_count` to metadata
- Adding comprehensive tests

## Solution Overview

Enhance the existing parameterized type handling to include:
1. Position tracking for each type parameter (0-indexed `param_position` in metadata)
2. `param_count` in parent metadata for easy access
3. Comprehensive test coverage for all parameterized type scenarios

## Technical Details

### File Locations
- **Extractor**: `lib/elixir_ontologies/extractors/type_expression.ex`
- **Tests**: `test/elixir_ontologies/extractors/type_expression_test.exs`

### Current Implementation (lines 395-405)

```elixir
# Parameterized basic type: list(element), keyword(value)
defp do_parse({name, _, args} = ast)
     when name in @basic_types and is_list(args) and args != [] do
  %__MODULE__{
    kind: :basic,
    name: name,
    elements: Enum.map(args, &do_parse/1),
    ast: ast,
    metadata: %{parameterized: true}
  }
end
```

### Enhancement Required

Add position tracking similar to union types:

```elixir
defp do_parse({name, _, args} = ast)
     when name in @basic_types and is_list(args) and args != [] do
  parsed_params =
    args
    |> Enum.with_index()
    |> Enum.map(fn {arg, index} ->
      parsed = do_parse(arg)
      %{parsed | metadata: Map.put(parsed.metadata, :param_position, index)}
    end)

  %__MODULE__{
    kind: :basic,
    name: name,
    elements: parsed_params,
    ast: ast,
    metadata: %{parameterized: true, param_count: length(args)}
  }
end
```

Also enhance remote types similarly.

## Success Criteria

- [x] Parameterized basic types detected correctly
- [x] Type parameters have `param_position` in metadata
- [x] Parent has `param_count` in metadata
- [x] Tests for `list(t)`, `map(k, v)`, `keyword(t)` patterns
- [x] Tests for nested parameterized types
- [x] All existing tests continue to pass

## Implementation Plan

### Step 1: Add Position Tracking to Basic Parameterized Types
Update `do_parse/1` for parameterized basic types to track parameter positions.

### Step 2: Add Position Tracking to Remote Parameterized Types
Update `do_parse/1` for remote types with parameters to track parameter positions.

### Step 3: Add Helper Function `parameterized?/1`
Add a helper function to check if a type expression is parameterized.

### Step 4: Add Comprehensive Tests
Add tests for:
- Position tracking in parameterized types
- `list(integer())`, `list(atom())`
- `map(atom(), term())`
- `keyword(String.t())`
- Nested: `list(map(atom(), integer()))`
- Multi-param: `map(key, value)` with 2 params

### Step 5: Verify All Tests Pass
Run test suite to ensure no regressions.

## Current Status

- **Branch**: `feature/phase-14-1-2-parameterized-types`
- **What works**:
  - Position tracking for all parameterized type parameters (`param_position` in metadata)
  - `param_count` in parent metadata
  - Support for both basic and remote parameterized types
  - Nested parameterized types (e.g., `list(map(k, v))`)
  - `parameterized?/1` helper function
  - All 102 tests pass (24 doctests + 78 tests)
- **Complete**: Feature implementation is done
- **How to run**: `mix test test/elixir_ontologies/extractors/type_expression_test.exs`

## Notes

- The plan suggested `kind: :parameterized` but the current approach using `kind: :basic` with `parameterized: true` is more consistent with how Elixir's type system works (these are still basic types, just with parameters)
- The approach mirrors how union types now track positions
