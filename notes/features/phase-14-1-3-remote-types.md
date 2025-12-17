# Feature: Phase 14.1.3 - Remote Types

## Problem Statement

Task 14.1.3 from the Phase 14 plan calls for implementing remote type extraction. Upon review, the existing `TypeExpression` extractor already handles remote types with significant capability:

**Current Implementation:**
- Remote types (`Module.type()`) are detected via AST pattern matching
- Module path is extracted as list of atoms (e.g., `[:MyApp, :Accounts, :User]`)
- Type name is extracted
- Parameterized remote types are supported with `param_position` and `param_count` (from 14.1.2)
- `remote?/1` helper function exists

**What's Missing (from subtasks):**
1. Type arity tracking (number of parameters the type accepts)
2. IRI-compatible module format for RDF generation
3. Comprehensive tests for all remote type patterns

**Design Decision:** Rather than restructuring the existing implementation, we will enhance it by:
- Adding `arity` to metadata (number of type parameters)
- Adding `module_iri/1` helper to generate IRI-compatible module references
- Adding `type_iri/1` helper to generate full type IRI
- Adding comprehensive tests

## Solution Overview

Enhance the existing remote type handling to include:
1. Arity tracking in metadata (0 for non-parameterized, N for parameterized)
2. IRI helper functions for RDF generation
3. Comprehensive test coverage for all remote type scenarios

## Technical Details

### File Locations
- **Extractor**: `lib/elixir_ontologies/extractors/type_expression.ex`
- **Tests**: `test/elixir_ontologies/extractors/type_expression_test.exs`

### Current Implementation (lines 368-398)

```elixir
# Remote type with parameters: Module.type(args)
defp do_parse({{:., _, [{:__aliases__, _, module_parts}, type_name]}, _, args} = ast)
     when is_list(args) do
  parsed_params =
    if args == [] do
      nil
    else
      args
      |> Enum.with_index()
      |> Enum.map(fn {arg, index} ->
        parsed = do_parse(arg)
        %{parsed | metadata: Map.put(parsed.metadata, :param_position, index)}
      end)
    end

  metadata =
    if args == [] do
      %{parameterized: false}
    else
      %{parameterized: true, param_count: length(args)}
    end

  %__MODULE__{
    kind: :remote,
    name: type_name,
    module: module_parts,
    elements: parsed_params,
    ast: ast,
    metadata: metadata
  }
end
```

### Enhancement Required

1. Add `arity` to metadata:

```elixir
metadata =
  if args == [] do
    %{parameterized: false, arity: 0}
  else
    %{parameterized: true, param_count: length(args), arity: length(args)}
  end
```

2. Add IRI helper functions:

```elixir
@doc """
Returns the module as an IRI-compatible string.

## Examples

    iex> ast = {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}
    iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
    iex> ElixirOntologies.Extractors.TypeExpression.module_iri(result)
    "Elixir.String"
"""
@spec module_iri(t()) :: String.t() | nil
def module_iri(%__MODULE__{kind: :remote, module: module_parts}) do
  "Elixir." <> Enum.join(module_parts, ".")
end
def module_iri(_), do: nil

@doc """
Returns the full type reference as an IRI-compatible string.

## Examples

    iex> ast = {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}
    iex> {:ok, result} = ElixirOntologies.Extractors.TypeExpression.parse(ast)
    iex> ElixirOntologies.Extractors.TypeExpression.type_iri(result)
    "Elixir.String#t/0"
"""
@spec type_iri(t()) :: String.t() | nil
def type_iri(%__MODULE__{kind: :remote, module: module_parts, name: type_name, metadata: metadata}) do
  arity = Map.get(metadata, :arity, 0)
  "Elixir." <> Enum.join(module_parts, ".") <> "##{type_name}/#{arity}"
end
def type_iri(_), do: nil
```

## Success Criteria

- [x] Remote types have `arity` in metadata
- [x] `module_iri/1` returns IRI-compatible module string
- [x] `type_iri/1` returns full type IRI with arity
- [x] Tests for various remote type patterns
- [x] Tests for nested module paths
- [x] Tests for parameterized remote types with arity
- [x] All existing tests continue to pass (117 total: 28 doctests + 89 tests)

## Implementation Plan

### Step 1: Add Arity to Remote Type Metadata
Update `do_parse/1` for remote types to include arity in metadata.

### Step 2: Add `module_iri/1` Helper Function
Add helper to generate IRI-compatible module reference.

### Step 3: Add `type_iri/1` Helper Function
Add helper to generate full type IRI with name and arity.

### Step 4: Add Comprehensive Tests
Add tests for:
- Arity tracking (0 and non-zero)
- `module_iri/1` for various module paths
- `type_iri/1` for various type references
- Edge cases (single module, deeply nested modules)

### Step 5: Verify All Tests Pass
Run test suite to ensure no regressions.

## Current Status

- **Branch**: `feature/phase-14-1-3-remote-types`
- **What works**:
  - Arity tracking for all remote types (`arity` in metadata)
  - `module_iri/1` helper for IRI-compatible module references
  - `type_iri/1` helper for full type IRI with name and arity
  - All 117 tests pass (28 doctests + 89 tests)
- **Complete**: Feature implementation is done
- **How to run**: `mix test test/elixir_ontologies/extractors/type_expression_test.exs`

## Notes

- The arity represents how many type parameters the remote type accepts
- IRI format follows Elixir's module naming convention with `.` separators
- Type IRI includes `#type_name/arity` suffix for unique identification
