# Feature: Phase 14.2.1 - Function Types

## Problem Statement

Task 14.2.1 from the Phase 14 plan calls for extracting function type signatures. Upon review, the existing `TypeExpression` extractor already handles function types comprehensively:

**Current Implementation:**
- Function types are detected via `[{:->, _, [params, return_type]}]` pattern
- Parameter types stored in `param_types` field (list or `:any`)
- Return type stored in `return_type` field
- Arity tracked in metadata
- Zero-arity, multi-param, and any-arity functions supported
- `function?/1` helper exists

**What Can Be Enhanced:**
1. Add `param_types/1` helper to safely extract parameter types
2. Add `return_type/1` helper to safely extract return type
3. Add `function_arity/1` helper to get arity from function type
4. Add tests for union of function types (multiple arities)
5. Add tests for nested function types (higher-order functions)
6. Add tests for function types with type variables

## Solution Overview

Add helper functions for function type introspection and comprehensive tests for edge cases.

## Technical Details

### File Locations
- **Extractor**: `lib/elixir_ontologies/extractors/type_expression.ex`
- **Tests**: `test/elixir_ontologies/extractors/type_expression_test.exs`

### Current Function Type Implementation (lines 323-341)

```elixir
defp do_parse([{:->, _, [params, return_type]}] = ast) do
  param_types =
    case params do
      [{:..., _, _}] -> :any
      params when is_list(params) -> Enum.map(params, &do_parse/1)
    end

  %__MODULE__{
    kind: :function,
    param_types: param_types,
    return_type: do_parse(return_type),
    ast: ast,
    metadata: %{
      arity: if(param_types == :any, do: :any, else: length(param_types))
    }
  }
end
```

### Proposed Helper Functions

```elixir
@doc """
Returns the parameter types for a function type expression.
"""
@spec param_types(t()) :: [t()] | :any | nil
def param_types(%__MODULE__{kind: :function, param_types: params}), do: params
def param_types(_), do: nil

@doc """
Returns the return type for a function type expression.
"""
@spec return_type(t()) :: t() | nil
def return_type(%__MODULE__{kind: :function, return_type: return}), do: return
def return_type(_), do: nil

@doc """
Returns the arity of a function type expression.
"""
@spec function_arity(t()) :: non_neg_integer() | :any | nil
def function_arity(%__MODULE__{kind: :function, metadata: %{arity: arity}}), do: arity
def function_arity(_), do: nil
```

## Success Criteria

- [x] `param_types/1` helper returns parameter types for function expressions
- [x] `return_type/1` helper returns return type for function expressions
- [x] `function_arity/1` helper returns arity for function expressions
- [x] Tests for union of function types (multiple arities)
- [x] Tests for nested function types (functions returning functions)
- [x] Tests for function types with complex params/returns
- [x] All existing tests continue to pass (169 total: 46 doctests + 123 tests)

## Implementation Plan

### Step 1: Add Helper Functions
Add `param_types/1`, `return_type/1`, and `function_arity/1` helpers.

### Step 2: Add Comprehensive Tests
Add tests for:
- Helper functions
- Union of function types
- Nested function types
- Function types with type variables
- Edge cases

### Step 3: Verify All Tests Pass
Run test suite to ensure no regressions.

## Current Status

- **Branch**: `feature/phase-14-2-1-function-types`
- **What works**:
  - `param_types/1`, `return_type/1`, `function_arity/1` helper functions
  - Union of function types (multiple arities)
  - Nested function types (higher-order functions)
  - Function types with complex parameters and returns
  - All 169 tests pass (46 doctests + 123 tests)
- **Complete**: Feature implementation is done
- **How to run**: `mix test test/elixir_ontologies/extractors/type_expression_test.exs`

## Notes

- The existing implementation was already comprehensive
- Helpers provide consistent API for accessing function type components
- Union of function types already works through normal union parsing
- 3 new helper functions + 9 doctests + 14 new tests added
