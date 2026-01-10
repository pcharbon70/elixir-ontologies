# Phase 21.6: Helper Functions Module

**Status:** ✅ Complete
**Branch:** `feature/phase-21-6-helper-functions`
**Created:** 2025-01-09
**Completed:** 2025-01-09
**Target:** Add helper functions for common patterns in expression building

## Problem Statement

The ExpressionBuilder and related modules need helper functions for common patterns when building expressions. While the `Helpers` module provides general RDF triple building utilities (type_triple, datatype_property, etc.), there are specific patterns used repeatedly in expression building that should be abstracted into reusable helpers.

Current state:
- `Helpers` module has general RDF utilities (21.6.1 items mostly complete)
- ExpressionBuilder lacks specific expression-building helpers (21.6.2 needs implementation)
- Repeated patterns in ExpressionBuilder for building child expressions, combining triples, conditional building

## Solution Overview

1. **Verify 21.6.1 Triple Building Helpers**: Confirm existing `Helpers` module functions
2. **Implement 21.6.2 Expression Building Helpers**: Add new helpers to `ExpressionBuilder`:
   - `build_child_expressions/3` - Build multiple child expressions from AST list
   - `combine_triples/1` - Flatten and deduplicate triple lists
   - `maybe_build/3` - Conditional expression building with guard

These helpers will be used internally by ExpressionBuilder and could be useful for other builders that integrate with ExpressionBuilder.

## Technical Details

### Files to Modify

- `lib/elixir_ontologies/builders/expression_builder.ex` - Add expression building helpers
- `test/elixir_ontologies/builders/expression_builder_test.exs` - Add tests for helpers

### 21.6.1 Triple Building Helpers (Verification)

These helpers already exist in `Helpers` module:
- ✅ `type_triple/2` - Creates rdf:type triple
- ✅ `datatype_property/4` - Creates datatype property triple with literal
- ✅ `object_property/3` - Creates object property triple
- ✅ `blank_node/1` - Creates blank node with optional label

**Action**: Document these as verified and add any missing @spec or documentation if needed.

### 21.6.2 Expression Building Helpers (New)

#### build_child_expressions/3

Builds RDF triples for a list of child AST expressions.

```elixir
@spec build_child_expressions([Macro.t()], Context.t(), keyword()) ::
        {[{RDF.IRI.t(), [RDF.Triple.t()]}], [RDF.Triple.t()]}
def build_child_expressions(asts, context, opts \\ [])
```

- Iterates through list of AST nodes
- Calls `build/3` for each AST
- Returns list of `{iri, triples}` tuples plus combined triples
- Skips nil ASTs and :skip results
- Used for function arguments, list elements, etc.

#### combine_triples/1

Flattens nested triple lists and removes duplicates.

```elixir
@spec combine_triples([[RDF.Triple.t()]] | [RDF.Triple.t()]) :: [RDF.Triple.t()]
def combine_triples(triple_lists)
```

- Handles arbitrarily nested lists of triples
- Flattens to single list
- Removes duplicates using `Enum.uniq/1`
- Used after building nested expressions

#### maybe_build/3

Conditionally builds an expression based on a guard clause.

```elixir
@spec maybe_build(Macro.t() | nil, Context.t(), keyword()) ::
        {:ok, {RDF.IRI.t(), [RDF.Triple.t()]}} | :skip | nil
def maybe_build(ast, context, opts \\ [])
```

- Returns `nil` for nil AST (different from :skip)
- Returns `:skip` when `build/3` returns `:skip`
- Otherwise returns `{:ok, {iri, triples}}`
- Used for optional expressions (e.g., else clause, guard)

## Implementation Plan

### 21.6.1 Verify Triple Building Helpers

- [ ] 21.6.1.1 Verify `type_triple/2` exists and is documented
- [ ] 21.6.1.2 Verify `datatype_property/4` exists and is documented
- [ ] 21.6.1.3 Verify `object_property/3` exists and is documented
- [ ] 21.6.1.4 Verify `blank_node/1` exists and is documented
- [ ] 21.6.1.5 Add any missing @spec annotations
- [ ] 21.6.1.6 Add any missing examples

### 21.6.2 Implement Expression Building Helpers

- [ ] 21.6.2.1 Implement `build_child_expressions/3` in ExpressionBuilder
- [ ] 21.6.2.2 Add @spec and documentation for `build_child_expressions/3`
- [ ] 21.6.2.3 Implement `combine_triples/1` in ExpressionBuilder
- [ ] 21.6.2.4 Add @spec and documentation for `combine_triples/1`
- [ ] 21.6.2.5 Implement `maybe_build/3` in ExpressionBuilder
- [ ] 21.6.2.6 Add @spec and documentation for `maybe_build/3`

### 21.6.3 Tests

- [ ] 21.6.3.1 Test `build_child_expressions/3` with list of literals
- [ ] 21.6.3.2 Test `build_child_expressions/3` handles nil ASTs
- [ ] 21.6.3.3 Test `build_child_expressions/3` handles :skip results
- [ ] 21.6.3.4 Test `combine_triples/1` flattens nested lists
- [ ] 21.6.3.5 Test `combine_triples/1` removes duplicates
- [ ] 21.6.3.6 Test `maybe_build/3` returns nil for nil AST
- [ ] 21.6.3.7 Test `maybe_build/3` returns :skip in light mode
- [ ] 21.6.3.8 Test `maybe_build/3` builds expression in full mode

## Success Criteria

1. All triple building helpers from 21.6.1 verified in Helpers module
2. All expression building helpers from 21.6.2 implemented in ExpressionBuilder
3. All helpers have proper @spec annotations
4. All helpers have documentation with examples
5. All new tests pass
6. All existing tests continue to pass

## Notes/Considerations

### Helper Location

Question: Should expression building helpers go in ExpressionBuilder or a separate module?

**Decision**: Keep in ExpressionBuilder as private functions (prefixed with `defp`) since they are specific to expression building patterns and use ExpressionBuilder's `build/3` internally.

### Helper Visibility

All helpers in 21.6.2 will be private (`defp`) since they are internal to ExpressionBuilder. If other builders need them, they can be made public later.

### Existing Helpers

The `Helpers.finalize_triples/1` function already does what `combine_triples/1` would do. We may want to:
- Use `finalize_triples/1` from Helpers
- OR add `combine_triples/1` as an alias
- OR keep them separate if semantics differ

**Decision**: Use `Helpers.finalize_triples/1` where appropriate, but `combine_triples/1` may have different semantics for expression building (will determine during implementation).

## Status Log

### 2025-01-09 - Implementation Complete ✅
- **21.6.1 Triple Building Helpers Verified**: All triple building helpers exist in `Helpers` module
  - ✅ `type_triple/2` - Creates rdf:type triple
  - ✅ `datatype_property/4` - Creates datatype property triple with literal
  - ✅ `object_property/3` - Creates object property triple
  - ✅ `blank_node/1` - Creates blank node with optional label
- **21.6.2 Expression Building Helpers Implemented**: Added 3 new helper functions to ExpressionBuilder
  - ✅ `build_child_expressions/3` - Build multiple child expressions from AST list
  - ✅ `combine_triples/1` - Flatten and deduplicate triple lists
  - ✅ `maybe_build/3` - Conditional expression building with guard
- **Tests Added**: 13 new tests for helper functions
  - 5 tests for `build_child_expressions/3`
  - 4 tests for `combine_triples/1`
  - 5 tests for `maybe_build/3`
- **Full Test Suite**: All 7122 tests pass (1636 doctests, 29 properties, 7122 tests, 0 failures)

### Implementation Details

**build_child_expressions/3** (lines 715-733):
```elixir
def build_child_expressions(asts, context, opts \\ []) when is_list(asts) do
  asts
  |> Enum.map(fn ast -> build(ast, context, opts) end)
  |> Enum.filter(fn
    :skip -> false
    _ -> true
  end)
  |> Enum.map(fn
    {:ok, result} -> result
  end)
  |> Enum.reduce({[], []}, fn {iri, triples}, {results, all_triples} ->
    {[{iri, triples} | results], triples ++ all_triples}
  end)
  |> then(fn {results, all_triples} ->
    {Enum.reverse(results), all_triples}
  end)
end
```

**combine_triples/1** (lines 763-768):
```elixir
def combine_triples(triple_lists) when is_list(triple_lists) do
  triple_lists
  |> List.flatten()
  |> Enum.uniq()
end
```

**maybe_build/3** (lines 812-821):
```elixir
def maybe_build(nil, _context, _opts), do: nil

def maybe_build(ast, context, opts) do
  case build(ast, context, opts) do
    {:ok, result} -> {:ok, result}
    :skip -> :skip
  end
end
```

### 2025-01-09 - Initial Planning
- Created feature planning document
- Verified existing Helpers module has 21.6.1 functions
- Identified 21.6.2 functions to implement
- Created feature branch `feature/phase-21-6-helper-functions`
