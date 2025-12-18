# Phase 14.4.1: Callback Spec Enhancement

## Problem Statement

The current `FunctionSpec` extractor only handles `@spec` attributes. To fully capture Elixir's type system, we need to also extract:

- `@callback` - Required callback specifications in behaviours
- `@macrocallback` - Macro callback specifications
- `@optional_callbacks` - List of optional callback names

**Impact**: Without callback extraction, behaviour definitions cannot be fully represented in the knowledge graph.

## Analysis

### Ontology Support

The `elixir-structure.ttl` ontology provides:

| Class | Description |
|-------|-------------|
| `CallbackSpec` | A behaviour callback specification defined with @callback |
| `OptionalCallbackSpec` | An optional callback (subclass of CallbackSpec) |
| `MacroCallbackSpec` | A macro callback spec (subclass of CallbackSpec) |
| `Behaviour` | An Elixir behaviour defining a contract |
| `definesCallback` | Property linking Behaviour to CallbackFunction |

### AST Patterns

```elixir
# @callback
{:@, [], [{:callback, [], [{:"::", [], [{:name, [], [types...]}, return_type]}]}]}

# @macrocallback
{:@, [], [{:macrocallback, [], [{:"::", [], [{:name, [], [types...]}, return_type]}]}]}

# @optional_callbacks
{:@, [], [{:optional_callbacks, [], [[name: arity, ...]]}]}
```

### Current Implementation

`FunctionSpec.extract/2` handles:
- `@spec name(...) :: return_type`
- `@spec name(...) :: return_type when constraints`

## Solution

Extend `FunctionSpec` module to handle callback attributes with a new `spec_type` field:

1. Add `spec_type` field to struct (`:spec`, `:callback`, `:macrocallback`)
2. Add detection functions: `callback?/1`, `macrocallback?/1`, `optional_callbacks?/1`
3. Add extraction patterns for callback AST
4. Add `extract_optional_callbacks/1` for the list
5. Update `extract_all/1` to include callbacks

## Implementation Plan

### Step 1: Update FunctionSpec struct
- [x] Add `spec_type` field with default `:spec`
- [x] Update typedoc and typespec

### Step 2: Add callback detection functions
- [x] Add `callback?/1` function
- [x] Add `macrocallback?/1` function
- [x] Add `optional_callbacks?/1` function

### Step 3: Add callback extraction
- [x] Add extract pattern for `@callback`
- [x] Add extract pattern for `@macrocallback`
- [x] Set `spec_type` appropriately

### Step 4: Add optional_callbacks extraction
- [x] Create new struct `OptionalCallbacks` or use simple return
- [x] Add `extract_optional_callbacks/1` function

### Step 5: Update extract_all
- [x] Include callbacks in extraction
- [x] Handle optional_callbacks separately

### Step 6: Add tests
- [x] Test @callback extraction
- [x] Test @macrocallback extraction
- [x] Test @optional_callbacks extraction
- [x] Test extract_all with mixed specs

### Step 7: Documentation
- [x] Update phase-14.md
- [x] Create summary document

## Success Criteria

- [x] `callback?/1` detects @callback attributes
- [x] `macrocallback?/1` detects @macrocallback attributes
- [x] `extract/1` handles callback AST patterns
- [x] `spec_type` field correctly identifies spec type
- [x] `extract_optional_callbacks/1` returns list of {name, arity}
- [x] All tests pass
- [x] `mix compile --warnings-as-errors` passes
- [x] `mix credo --strict` passes

## Notes/Considerations

- Callbacks have the same structure as specs (name, arity, param_types, return_type)
- Optional callbacks is a list, not individual specs
- The `spec_type` field allows downstream code to generate correct RDF classes
