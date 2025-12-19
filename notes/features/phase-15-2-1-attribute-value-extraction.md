# Phase 15.2.1: Compile-time Value Extraction

## Problem Statement

The current `Attribute` extractor captures attribute names and raw values, but doesn't provide structured value extraction with type classification. For semantic analysis, we need to:
- Classify attribute values by their type (literal, expression, AST reference)
- Handle complex values like keyword lists and maps
- Track whether attributes are accumulated (`Module.register_attribute(:attr, accumulate: true)`)

**Impact**: Structured value extraction enables:
- Accurate RDF representation of attribute values
- Type-safe queries on attribute metadata
- Distinguishing between accumulated and single-assignment attributes
- Better tooling for attribute introspection

## Solution Overview

Create an `AttributeValue` struct that captures typed value information:
1. Define `%AttributeValue{}` with type, raw_value, evaluated_value, and accumulated fields
2. Add value classification functions to determine value types
3. Add helper functions for common value patterns
4. Track register_attribute calls for accumulation detection

## Technical Details

### Files to Modify
- **Modify**: `lib/elixir_ontologies/extractors/attribute.ex`
- **Modify**: `test/elixir_ontologies/extractors/attribute_test.exs`
- **Modify**: `notes/planning/extractors/phase-15.md` (mark task complete)

### AttributeValue Struct

```elixir
defmodule ElixirOntologies.Extractors.Attribute.AttributeValue do
  defstruct [
    :type,           # :literal | :list | :map | :keyword_list | :ast | :module_ref
    :value,          # The extracted/evaluated value
    :raw_ast,        # Original AST for non-literal values
    accumulated: false  # Whether this attribute accumulates
  ]
end
```

### Value Types

1. **Literal values**: atoms, integers, floats, strings, booleans
2. **List values**: `[a, b, c]` - homogeneous or heterogeneous lists
3. **Map values**: `%{key: value}` - maps with various key types
4. **Keyword list values**: `[key: value]` - special form of lists
5. **Module references**: `{:__aliases__, _, parts}` - module names
6. **AST values**: Complex expressions that can't be statically evaluated

### Design Decisions

- Values that can be statically evaluated are stored in `value` field
- Complex/dynamic values keep the AST in `raw_ast`
- Accumulated attributes are detected from `Module.register_attribute/3` calls
- Value type is inferred from the AST structure

## Implementation Plan

### Step 1: Define AttributeValue Struct
- [x] Create `AttributeValue` nested module inside Attribute
- [x] Add typespec for value types
- [x] Add constructor function `new/1`

### Step 2: Value Type Classification
- [x] Implement `classify_value/1` for type detection
- [x] Handle literal values (atoms, strings, numbers, booleans)
- [x] Handle list and map values
- [x] Handle keyword lists
- [x] Handle module references

### Step 3: Value Extraction Functions
- [x] Implement `extract_typed_value/1` returning AttributeValue
- [x] Add `try_evaluate_value/1` for static evaluation
- [x] Add `keyword_list?/1` helper

### Step 4: Accumulation Detection
- [x] Implement `extract_accumulated_attributes/1`
- [x] Track accumulated attribute names
- [x] Add `accumulated?/2` to check if attribute accumulates

### Step 5: Integration
- [x] Add `value_info/1` function to Attribute struct
- [x] Update metadata to include value type information
- [x] Add helper predicates for value types

### Step 6: Write Tests
- [x] Test AttributeValue struct creation
- [x] Test literal value extraction (atoms, integers, strings, floats, booleans)
- [x] Test list value extraction
- [x] Test map value extraction
- [x] Test keyword list detection
- [x] Test module reference extraction
- [x] Test accumulation detection
- [x] Test complex AST values

## Success Criteria

- [x] All subtasks in phase-15.md marked complete
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes
- [x] All tests pass
- [x] Value extraction works for all attribute types

## Notes

- Some values require runtime evaluation (e.g., function calls) - these are kept as AST
- Accumulated attributes are rare but important for tools like Ecto changesets
- The `raw_ast` field preserves full information for cases where evaluation isn't possible
