# Summary: Phase 14.2.1 - Function Types

## Overview

Task 14.2.1 enhances function type handling in the TypeExpression extractor. The existing implementation already extracted function types comprehensively (via `[{:->, _, [params, return]}]` pattern matching). This task added helper functions for accessing function type components and comprehensive tests for edge cases.

## Changes Made

### 1. Added `param_types/1` Helper

Returns parameter types for function type expressions:

```elixir
@spec param_types(t()) :: [t()] | :any | nil
def param_types(%__MODULE__{kind: :function, param_types: params}), do: params
def param_types(_), do: nil
```

### 2. Added `return_type/1` Helper

Returns the return type for function type expressions:

```elixir
@spec return_type(t()) :: t() | nil
def return_type(%__MODULE__{kind: :function, return_type: return}), do: return
def return_type(_), do: nil
```

### 3. Added `function_arity/1` Helper

Returns the arity of function type expressions:

```elixir
@spec function_arity(t()) :: non_neg_integer() | :any | nil
def function_arity(%__MODULE__{kind: :function, metadata: %{arity: arity}}), do: arity
def function_arity(_), do: nil
```

### 4. New Tests

Added 14 new tests in 2 describe blocks:

**Function type parsing:**
- Union of function types (multiple arities)
- Nested function types (functions returning functions)
- Function types with complex parameter types (tuples, lists)
- Function types with union parameters
- Function types with union returns

**Function type helpers:**
- `param_types/1` for fixed-arity, any-arity, and non-function types
- `return_type/1` for function and non-function types
- `function_arity/1` for all arity types and non-function types

## Test Results

All 169 tests pass (46 doctests + 123 tests):
```
mix test test/elixir_ontologies/extractors/type_expression_test.exs
```

## Files Modified

1. `lib/elixir_ontologies/extractors/type_expression.ex`
   - Added `param_types/1` helper function (3 doctests)
   - Added `return_type/1` helper function (2 doctests)
   - Added `function_arity/1` helper function (4 doctests)

2. `test/elixir_ontologies/extractors/type_expression_test.exs`
   - Added 6 new tests to "parse/1 function types" describe block
   - Added 8 new tests in "function type helpers" describe block

## New Public Functions

- `param_types/1` - Get parameter types from function type
- `return_type/1` - Get return type from function type
- `function_arity/1` - Get arity from function type

## Design Decisions

1. **Helper functions return `nil` for non-function types**: Consistent with other helpers like `module_iri/1` and `constraint_type/1`

2. **Existing struct fields preserved**: Helpers access existing `param_types`, `return_type`, and `metadata.arity` fields

3. **`:any` arity handled consistently**: Any-arity functions (`... -> return`) return `:any` from both `param_types/1` and `function_arity/1`

## Next Task

The next logical task is **14.2.2 Struct Types**, which will extract struct type references like `%User{}` and handle field type constraints. The current implementation already has basic struct type detection (`kind: :struct`).
