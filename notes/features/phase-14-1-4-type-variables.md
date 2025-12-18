# Feature: Phase 14.1.4 - Type Variables and Constraints

## Problem Statement

Task 14.1.4 from the Phase 14 plan calls for extracting type variables and their `when` constraints from polymorphic type definitions.

**Current Implementation Status:**

1. **TypeExpression extractor** (`type_expression.ex`):
   - Already detects type variables (`kind: :variable`)
   - Parses lowercase type names in specs (e.g., `{:a, [], nil}`)
   - Does NOT track constraints or scope

2. **FunctionSpec extractor** (`function_spec.ex`):
   - Already extracts `when` clause constraints
   - Stores raw constraint AST in `type_constraints` map
   - Does NOT parse constraint types through TypeExpression

**What's Missing (from subtasks):**

1. Parse constraint types through TypeExpression (not just store raw AST)
2. Track type variable scope (function-level vs type-level)
3. Link constraints to their type variables in TypeExpression
4. Provide helper functions for constraint introspection

**Design Decision:** Enhance TypeExpression to:
- Accept optional constraints when parsing type variables
- Add `constraints` field to type variable metadata
- Add helper functions for working with constrained type variables

## Solution Overview

### Approach

1. **Add constraint parsing to TypeExpression**: When parsing a type variable, optionally accept constraints and store parsed TypeExpression in metadata.

2. **Add `parse_with_constraints/2`**: New function that parses a type expression with a constraint map, applying constraints to type variables.

3. **Enhance FunctionSpec**: Use TypeExpression to parse constraint types instead of storing raw AST.

4. **Add helper functions**: `constrained?/1`, `constraint_type/2` for introspection.

## Technical Details

### File Locations
- **TypeExpression**: `lib/elixir_ontologies/extractors/type_expression.ex`
- **FunctionSpec**: `lib/elixir_ontologies/extractors/function_spec.ex`
- **Tests**: `test/elixir_ontologies/extractors/type_expression_test.exs`

### Current Type Variable Implementation (lines 438-446)

```elixir
# Type variable: a, element, etc. (bare atom with context)
defp do_parse({name, _, context} = ast) when is_atom(name) and is_atom(context) do
  %__MODULE__{
    kind: :variable,
    name: name,
    ast: ast,
    metadata: %{}
  }
end
```

### Proposed Enhancement

1. Add `parse_with_constraints/2` function:

```elixir
@doc """
Parses a type expression AST with type variable constraints.

The constraints map associates type variable names with their constraint types.
When a type variable is encountered, its constraint (if any) is parsed and
stored in the metadata.

## Examples

    iex> constraints = %{a: {:integer, [], []}}
    iex> {:ok, result} = TypeExpression.parse_with_constraints({:a, [], nil}, constraints)
    iex> result.kind
    :variable
    iex> result.metadata.constraint.kind
    :basic
"""
@spec parse_with_constraints(Macro.t(), map()) :: {:ok, t()}
def parse_with_constraints(ast, constraints) when is_map(constraints) do
  {:ok, do_parse_with_constraints(ast, constraints)}
end
```

2. Add `constrained?/1` helper:

```elixir
@doc """
Returns true if the type variable has a constraint.
"""
@spec constrained?(t()) :: boolean()
def constrained?(%__MODULE__{kind: :variable, metadata: %{constraint: _}}), do: true
def constrained?(_), do: false
```

3. Add `constraint_type/1` helper:

```elixir
@doc """
Returns the constraint type expression for a constrained type variable.
"""
@spec constraint_type(t()) :: t() | nil
def constraint_type(%__MODULE__{kind: :variable, metadata: %{constraint: constraint}}), do: constraint
def constraint_type(_), do: nil
```

## Success Criteria

- [x] `parse_with_constraints/2` parses type expressions with constraint map
- [x] Type variables get `constraint` in metadata when constraints provided
- [x] `constrained?/1` helper returns true for constrained type variables
- [x] `constraint_type/1` helper returns the constraint TypeExpression
- [x] Nested type expressions properly propagate constraints
- [x] FunctionSpec integration deferred (already stores raw AST, can use TypeExpression when needed)
- [x] Tests for all constraint scenarios (20 new tests)
- [x] All existing tests continue to pass (146 total: 37 doctests + 109 tests)

## Implementation Plan

### Step 1: Add `parse_with_constraints/2` Function
Add new public function that accepts a constraint map and passes it through parsing.

### Step 2: Add Internal Constraint-Aware Parsing
Add `do_parse_with_constraints/2` that applies constraints to type variables.

### Step 3: Add Helper Functions
Add `constrained?/1` and `constraint_type/1` for introspection.

### Step 4: Update FunctionSpec to Parse Constraints
Enhance `extract_constraints/1` to parse constraint types through TypeExpression.

### Step 5: Add Comprehensive Tests
Test constraint application, nested types, and helper functions.

## Current Status

- **Branch**: `feature/phase-14-1-4-type-variables`
- **What works**:
  - `parse_with_constraints/2` and `parse_with_constraints!/2` for constraint-aware parsing
  - Type variables get `constrained: true/false` and `constraint` in metadata
  - `constrained?/1` and `constraint_type/1` helper functions
  - All type expression kinds propagate constraints to nested elements
  - All 146 tests pass (37 doctests + 109 tests)
- **Complete**: Feature implementation is done
- **How to run**: `mix test test/elixir_ontologies/extractors/type_expression_test.exs`

## Notes

- Constraints are function-level scope (applied within a single spec)
- Type-level scope would be for `@type` definitions (future enhancement)
- The constraint map format mirrors the keyword list from `when` clauses
- FunctionSpec already extracts constraints as raw AST; consumers can use `parse_with_constraints/2` to get full type information
