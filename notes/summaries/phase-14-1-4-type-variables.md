# Summary: Phase 14.1.4 - Type Variables and Constraints

## Overview

Task 14.1.4 enhances type variable handling in the TypeExpression extractor by adding constraint-aware parsing. The existing implementation already detected type variables (`kind: :variable`) but didn't support parsing `when` clause constraints. This task added `parse_with_constraints/2` to apply constraints during parsing and helper functions for introspection.

## Changes Made

### 1. Added `parse_with_constraints/2` and `parse_with_constraints!/2`

New public functions that parse type expressions while applying a constraint map:

```elixir
@spec parse_with_constraints(Macro.t(), map()) :: {:ok, t()}
def parse_with_constraints(ast, constraints) when is_map(constraints) do
  {:ok, do_parse_with_constraints(ast, constraints)}
end
```

Usage:
```elixir
constraints = %{a: {:integer, [], []}, b: {:atom, [], []}}
{:ok, result} = TypeExpression.parse_with_constraints({:a, [], nil}, constraints)
# result.metadata.constrained == true
# result.metadata.constraint.kind == :basic
# result.metadata.constraint.name == :integer
```

### 2. Added Constraint-Aware Internal Parsing

Added `do_parse_with_constraints/2` that mirrors `do_parse/1` but propagates constraints through all type expression kinds:
- Union types
- Tuple types
- List types
- Function types
- Map types
- Parameterized basic types
- Remote types
- Type variables (applies constraints)

### 3. Added `constrained?/1` Helper

Returns true if a type variable has a constraint:

```elixir
@spec constrained?(t()) :: boolean()
def constrained?(%__MODULE__{kind: :variable, metadata: %{constrained: true}}), do: true
def constrained?(_), do: false
```

### 4. Added `constraint_type/1` Helper

Returns the constraint TypeExpression for a constrained type variable:

```elixir
@spec constraint_type(t()) :: t() | nil
def constraint_type(%__MODULE__{kind: :variable, metadata: %{constraint: constraint}}), do: constraint
def constraint_type(_), do: nil
```

## Test Results

All 146 tests pass (37 doctests + 109 tests):
```
mix test test/elixir_ontologies/extractors/type_expression_test.exs
```

## Files Modified

1. `lib/elixir_ontologies/extractors/type_expression.ex`
   - Added `parse_with_constraints/2` function (with 3 doctests)
   - Added `parse_with_constraints!/2` function (with 1 doctest)
   - Added `constrained?/1` helper (with 3 doctests)
   - Added `constraint_type/1` helper (with 2 doctests)
   - Added `do_parse_with_constraints/2` internal parsing (~300 lines)
   - Added `parse_map_pairs_with_constraints/2` helper

2. `test/elixir_ontologies/extractors/type_expression_test.exs`
   - Added 20 new tests in 3 describe blocks:
     - `parse_with_constraints/2` (12 tests)
     - `constrained?/1` (4 tests)
     - `constraint_type/1` (4 tests)

## New Public Functions

- `parse_with_constraints/2` - Parse with constraint map
- `parse_with_constraints!/2` - Parse with constraints (raises)
- `constrained?/1` - Check if type variable is constrained
- `constraint_type/1` - Get constraint TypeExpression

## New Metadata Fields

On type variables parsed with constraints:
- `constrained: true | false` - Whether variable has a constraint
- `constraint: TypeExpression.t()` - The parsed constraint type (when constrained)

## Design Decisions

1. **Constraint map format**: Uses `%{variable_name => constraint_ast}` mirroring the keyword list from `when` clauses

2. **Backward compatibility**: Regular `parse/1` is unchanged; constraints are opt-in via new functions

3. **FunctionSpec integration**: Deferred - FunctionSpec already stores raw constraint AST, and consumers can use `parse_with_constraints/2` when they need full type information

4. **Constraint scope**: Currently function-level (per-spec constraints via parameter)

## Next Task

The next logical task is **14.2.1 Function Types**, which will extract function type expressions for higher-order function signatures. The current implementation already handles basic function types; this task may add enhanced support for named parameters, guards, or other function type features.

## Section 14.1 Complete

With task 14.1.4 complete, all of Section 14.1 (Core Type Expressions) is now done:
- 14.1.1 Union Types - Position tracking
- 14.1.2 Parameterized Types - Position and count tracking
- 14.1.3 Remote Types - Arity and IRI helpers
- 14.1.4 Type Variables - Constraint-aware parsing
