# Feature: Phase 14.2.2 - Struct Types

## Problem Statement

Task 14.2.2 from the Phase 14 plan calls for extracting struct type references. The existing `TypeExpression` extractor already detects struct types but doesn't extract field type constraints.

**Current Implementation:**
- Struct types detected via `{:%, _, [{:__aliases__, _, module_parts}, {:%{}, _, _fields}]}` pattern
- Module path extracted to `module` field
- Field constraints are ignored (`_fields`)
- `struct?/1` helper exists

**What's Missing:**
1. Extract field type constraints from struct types
2. Add `struct_module/1` helper for IRI-compatible module reference
3. Add `struct_fields/1` helper for getting field type constraints
4. Store field types in struct metadata or elements

## Solution Overview

Enhance struct type parsing to extract field type constraints and add helper functions for introspection.

## Technical Details

### File Locations
- **Extractor**: `lib/elixir_ontologies/extractors/type_expression.ex`
- **Tests**: `test/elixir_ontologies/extractors/type_expression_test.exs`

### Current Struct Type Implementation (lines 405-415)

```elixir
defp do_parse({:%, _, [{:__aliases__, _, module_parts}, {:%{}, _, _fields}]} = ast) do
  %__MODULE__{
    kind: :struct,
    module: module_parts,
    ast: ast,
    metadata: %{}
  }
end
```

### Struct Type AST Structure

```elixir
# %User{name: String.t(), age: integer()}
{:%, [line: 1],
 [
   {:__aliases__, [line: 1], [:User]},
   {:%{}, [line: 1],
    [
      name: {{:., [line: 1], [{:__aliases__, [line: 1], [:String]}, :t]}, [line: 1], []},
      age: {:integer, [line: 1], []}
    ]}
 ]}
```

### Proposed Enhancement

1. Extract field constraints:

```elixir
defp do_parse({:%, _, [{:__aliases__, _, module_parts}, {:%{}, _, fields}]} = ast) do
  parsed_fields =
    if fields == [] do
      nil
    else
      fields
      |> Enum.map(fn {field_name, field_type} ->
        %{name: field_name, type: do_parse(field_type)}
      end)
    end

  %__MODULE__{
    kind: :struct,
    module: module_parts,
    elements: parsed_fields,
    ast: ast,
    metadata: %{
      field_count: if(parsed_fields, do: length(parsed_fields), else: 0)
    }
  }
end
```

2. Add `struct_module/1` helper:

```elixir
@spec struct_module(t()) :: String.t() | nil
def struct_module(%__MODULE__{kind: :struct, module: module_parts}) when is_list(module_parts) do
  "Elixir." <> Enum.join(module_parts, ".")
end
def struct_module(_), do: nil
```

3. Add `struct_fields/1` helper:

```elixir
@spec struct_fields(t()) :: [%{name: atom(), type: t()}] | nil
def struct_fields(%__MODULE__{kind: :struct, elements: fields}) when is_list(fields), do: fields
def struct_fields(_), do: nil
```

## Success Criteria

- [ ] Struct types extract field type constraints
- [ ] `struct_module/1` returns IRI-compatible module string
- [ ] `struct_fields/1` returns list of field name/type pairs
- [ ] Tests for struct types with and without fields
- [ ] Tests for nested module paths
- [ ] Tests for complex field types
- [ ] All existing tests continue to pass

## Implementation Plan

### Step 1: Enhance Struct Type Parsing
Update `do_parse/1` for struct types to extract field constraints.

### Step 2: Update Constraint-Aware Parsing
Update `do_parse_with_constraints/2` for struct types similarly.

### Step 3: Add `struct_module/1` Helper Function
Add helper to generate IRI-compatible module reference.

### Step 4: Add `struct_fields/1` Helper Function
Add helper to get field type constraints.

### Step 5: Add Comprehensive Tests
Add tests for all struct type scenarios.

## Current Status

- **Branch**: `feature/phase-14-2-2-struct-types`
- **Status**: Planning complete
- **How to run**: `mix test test/elixir_ontologies/extractors/type_expression_test.exs`

## Notes

- Field constraints are optional (empty struct `%User{}` has no fields)
- Each field has a name (atom) and type (TypeExpression)
- Nested module paths already supported
- The `t()` convention is handled at the type definition level, not struct type level
