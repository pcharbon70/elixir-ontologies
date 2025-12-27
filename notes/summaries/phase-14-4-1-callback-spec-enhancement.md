# Phase 14.4.1 Summary: Callback Spec Enhancement

## Overview

Enhanced the `FunctionSpec` extractor to handle `@callback`, `@macrocallback`, and `@optional_callbacks` attributes in addition to `@spec`. This enables full extraction of behaviour callback specifications.

## Changes Made

### FunctionSpec Struct (`lib/elixir_ontologies/extractors/function_spec.ex`)

**New Field:**
- `spec_type` - Indicates the type of spec: `:spec`, `:callback`, or `:macrocallback`

**New Detection Functions:**
- `callback?/1` - Detects `@callback` attributes
- `macrocallback?/1` - Detects `@macrocallback` attributes
- `optional_callbacks?/1` - Detects `@optional_callbacks` attributes
- `any_spec?/1` - Detects any spec-like attribute

**New Extraction Patterns:**
- `@callback name(...) :: return_type`
- `@callback name(...) :: return_type when constraints`
- `@macrocallback name(...) :: return_type`
- `@macrocallback name(...) :: return_type when constraints`

**New Optional Callbacks Functions:**
- `extract_optional_callbacks/1` - Extracts `{:ok, [{name, arity}, ...]}` from `@optional_callbacks`
- `extract_all_optional_callbacks/1` - Extracts all optional callbacks from module body

**Updated Functions:**
- `extract_all/1` - Now uses `any_spec?/1` to include callbacks in bulk extraction

### Tests (`test/elixir_ontologies/extractors/function_spec_test.exs`)

Added 27 new tests across 9 describe blocks:

| Describe Block | Tests Added |
|---------------|-------------|
| `callback?/1` | 3 tests |
| `macrocallback?/1` | 2 tests |
| `optional_callbacks?/1` | 2 tests |
| `any_spec?/1` | 5 tests |
| `extract/2 @callback` | 4 tests |
| `extract/2 @macrocallback` | 2 tests |
| `extract_optional_callbacks/1` | 2 tests |
| `extract_all_optional_callbacks/1` | 2 tests |
| `extract_all/1 with callbacks` | 2 tests |
| `spec_type field` | 3 tests |

## Usage Examples

### Detecting Callback Types

```elixir
FunctionSpec.callback?({:@, [], [{:callback, [], [...]}]})     # true
FunctionSpec.macrocallback?({:@, [], [{:macrocallback, [], [...]}]})  # true
FunctionSpec.any_spec?(ast)  # true for @spec, @callback, @macrocallback
```

### Extracting Callbacks

```elixir
ast = quote do
  @callback init(args :: term()) :: {:ok, state} | {:error, reason}
end

{:ok, result} = FunctionSpec.extract(ast)
result.name        # :init
result.arity       # 1
result.spec_type   # :callback
```

### Extracting Optional Callbacks

```elixir
ast = {:@, [], [{:optional_callbacks, [], [[foo: 1, bar: 2]]}]}
{:ok, callbacks} = FunctionSpec.extract_optional_callbacks(ast)
callbacks  # [foo: 1, bar: 2]
```

## Ontology Integration

The `spec_type` field enables downstream RDF generation to use the correct ontology class:

| spec_type | Ontology Class |
|-----------|---------------|
| `:spec` | `FunctionSpec` |
| `:callback` | `CallbackSpec` |
| `:macrocallback` | `MacroCallbackSpec` |

Integration with the builder (task 14.4.2) will generate the correct RDF triples.

## Verification

- `mix compile --warnings-as-errors` passes
- `mix credo --strict` passes
- All 102 tests pass (32 doctests + 70 unit tests)

## Files Modified

1. `lib/elixir_ontologies/extractors/function_spec.ex` - Added ~150 lines
2. `test/elixir_ontologies/extractors/function_spec_test.exs` - Added ~260 lines
3. `notes/planning/extractors/phase-14.md` - Marked complete
4. `notes/features/phase-14-4-1-callback-spec-enhancement.md` - Created
5. `notes/summaries/phase-14-4-1-callback-spec-enhancement.md` - Created (this file)

## Next Task

The next logical task is **14.4.2 Spec Builder Enhancement**, which will:
- Generate `rdf:type structure:CallbackSpec` for callbacks
- Generate `rdf:type structure:MacroCallbackSpec` for macrocallbacks
- Link callbacks to their defining behaviours via `structure:definedBy`
