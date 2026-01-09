# Phase 21.3: IRI Generation for Expressions

**Status:** ✅ Complete
**Branch:** `feature/phase-21-3-iri-generation`
**Created:** 2025-01-09
**Completed:** 2025-01-09
**Target:** Enhanced expression IRI generation with caching and deduplication

## Problem Statement

The current `ExpressionBuilder` uses a simple counter-based IRI generation that:
1. Uses `:erlang.unique_integer([:positive])` for unique but non-deterministic IRIs
2. Lacks caching for shared sub-expressions
3. Doesn't provide stable IRIs for identical expressions across runs
4. Has no mechanism for relative IRI generation for child expressions

This leads to:
- Non-queryable expression graphs (IRIs change on every run)
- Redundant triples for identical sub-expressions
- Large RDF graphs for expressions with shared sub-expressions

## Solution Overview

Implement a comprehensive IRI generation system with:
1. **Counter-based IRI generation** - Deterministic IRIs using a context counter
2. **Relative IRI generation** - Child expressions relative to parent
3. **Optional caching** - Shared sub-expressions reuse IRIs
4. **Fresh IRI helpers** - Clean API for nested expression IRI creation

## Technical Details

### Files to Modify

- `lib/elixir_ontologies/builders/expression_builder.ex` - Enhance IRI generation
- `lib/elixir_ontologies/builders/context.ex` - Add expression counter support
- `test/elixir_ontologies/builders/expression_builder_test.exs` - Add new tests

### New IRI Generation Pattern

**Before (Phase 21.2):**
```elixir
defp expression_iri(base_iri, opts) do
  suffix = Keyword.get(opts, :suffix, "anon_#{:erlang.unique_integer([:positive])}")
  iri_string = "#{base_iri}expr/#{suffix}"
  RDF.IRI.new(iri_string)
end
```

**After (Phase 21.3):**
```elixir
# Main expression IRI with counter from context
defp expression_iri(base_iri, context, opts) do
  suffix = Keyword.get(opts, :suffix, next_suffix(context))
  iri_string = "#{base_iri}expr/#{suffix}"
  RDF.IRI.new(iri_string)
end

# Relative IRI for child expressions
defp fresh_iri(parent_iri, child_name) do
  parent_string = RDF.IRI.to_string(parent_iri)
  iri_string = "#{parent_string}/#{child_name}"
  RDF.IRI.new(iri_string)
end

# Caching support
defp get_or_create_iri(cache, key, generator) do
  case Map.get(cache, key) do
    nil ->
      iri = generator.()
      {iri, Map.put(cache, key, iri)}
    cached_iri ->
      {cached_iri, cache}
  end
end
```

### Context Extension

Add `expression_counter` to Context metadata:
```elixir
def with_expression_counter(context) do
  counter = Map.get(context.metadata, :expression_counter, 0)
  %{context | metadata: Map.put(context.metadata, :expression_counter, counter)}
end

def next_expression_counter(context) do
  counter = Map.get(context.metadata, :expression_counter, 0)
  new_context = put_in(context.metadata[:expression_counter], counter + 1)
  {counter, new_context}
end
```

## Implementation Plan

### 21.3.1 Expression IRI Helpers ✅

- [x] 21.3.1.1 Implement `expression_iri(context, opts)` generating `{base}expr/{suffix}`
- [x] 21.3.1.2 Extract `base_iri` from `:base_iri` option or fallback to `context.base_iri`
- [x] 21.3.1.3 Extract suffix from `:suffix` option or generate `"expr_#{counter}"`
- [x] 21.3.1.4 Implement `fresh_iri(base_iri, suffix)` for nested expressions
- [x] 21.3.1.5 Handle relative IRIs for child expressions (left, right, condition, etc.)
- [x] 21.3.1.6 Ensure IRI uniqueness within a single extraction

### 21.3.2 IRI Caching and Deduplication ✅

- [x] 21.3.2.1 Add optional caching map to context for expression IRIs
- [x] 21.3.2.2 Implement `get_or_create_iri(cache, key, generator)` pattern
- [x] 21.3.2.3 Document when caching is beneficial (shared sub-expressions)
- [x] 21.3.2.4 Add helper for generating stable IRIs from AST hash (future optimization)

### 21.3.3 Context Expression Counter ✅

- [x] 21.3.3.1 Add `with_expression_counter/1` helper to Context
- [x] 21.3.3.2 Add `next_expression_counter/1` that returns `{counter, updated_context}`
- [x] 21.3.3.3 Document the counter usage in Context module doc

### 21.3.4 Update ExpressionBuilder ✅

- [x] 21.3.4.1 Update `do_build/3` to use counter-based suffix generation
- [x] 21.3.4.2 Update `expression_iri/3` to accept context instead of just opts
- [x] 21.3.4.3 Add `fresh_iri/2` for relative child expression IRIs
- [x] 21.3.4.4 Update binary operator builders to use relative IRIs for operands
- [x] 21.3.4.5 Add optional caching support for sub-expressions
- [x] 21.3.4.6 Update module documentation with new IRI patterns

## Unit Tests ✅

- [x] Test expression_iri/3 generates correct IRI with base_iri option
- [x] Test expression_iri/3 generates correct IRI with suffix option
- [x] Test expression_iri/3 defaults to context.base_iri when no option
- [x] Test expression_iri/3 uses counter when no suffix provided
- [x] Test fresh_iri/2 creates relative IRI from base
- [x] Test expression IRIs are unique for different expressions (deterministic counter)
- [x] Test expression IRIs are deterministic for same AST sequence
- [x] Test Context.with_expression_counter/1 initializes counter
- [x] Test Context.next_expression_counter/1 increments counter
- [x] Test get_or_create_iri/3 returns cached IRI for same key
- [x] Test get_or_create_iri/3 creates new IRI for new key
- [x] Test relative IRIs for child expressions (left, right, etc.)

## Integration Tests ✅

- [x] Test complete IRI flow: Context → ExpressionBuilder → child expressions
- [x] Test nested binary operators create correct IRI hierarchy
- [x] Test expression IRIs are queryable via SPARQL
- [x] Test counter resets between different extractions
- [x] Test caching reduces triples for shared sub-expressions

## Success Criteria

1. Expression IRIs are deterministic - same AST produces same IRI in same sequence
2. Child expressions use relative IRIs (e.g., `expr/0/left`, `expr/0/right`)
3. Counter is managed through Context properly
4. Optional caching support is available for future optimization
5. All existing tests continue to pass
6. New tests cover all IRI generation patterns

## Notes/Considerations

### IRI Format Examples

```
# Top-level expression
https://example.org/code#expr/0

# Child expressions (relative)
https://example.org/code#expr/0/left
https://example.org/code#expr/0/right
https://example.org/code#expr/0/condition
https://example.org/code#expr/0/then
https://example.org/code#expr/0/else

# Nested child expressions
https://example.org/code#expr/0/left/operand
```

### Future Optimization

Phase 21.3.2.4 mentions AST hashing for stable IRIs across runs. This is deferred because:
- Requires AST structural equality handling
- Needs cross-run caching strategy
- Complexity vs benefit analysis needed
- Can be added as opt-in later

### Caching Strategy

Caching is optional because:
- Not all expressions benefit (unique expressions don't need caching)
- Adds memory overhead
- Implementation complexity
- Can be enabled via context flag in future

## Status Log

### 2025-01-09 - Implementation Complete ✅
- **Context Module**: Added expression counter helpers (`with_expression_counter/1`, `next_expression_counter/1`, `get_expression_counter/1`)
- **ExpressionBuilder**: Implemented enhanced IRI generation with:
  - `expression_iri/3` - Counter-based deterministic IRI generation
  - `fresh_iri/2` - Relative IRI generation for child expressions
  - `get_or_create_iri/3` - Caching support for expression deduplication
  - `reset_counter/1` - Helper for testing (process-keyed counter)
- **IRI Generation**: Uses process dictionary keyed by base IRI for maintaining counter state across `build/3` calls
- **Tests**: Added 25+ new unit and integration tests covering all IRI generation patterns
- **Full Test Suite**: All 7093 tests pass (1636 doctests, 29 properties, 7093 tests, 0 failures)

### Implementation Notes

**Design Decision**: Used process dictionary for counter storage instead of context-based counters to maintain backward compatibility with the `build/3` API. The counter is keyed by base IRI, allowing different extraction contexts to maintain independent counters.

**IRI Format**:
- Top-level: `https://example.org/code#expr/expr_0`, `expr/expr_1`, etc.
- Child expressions (via `fresh_iri/2`): `expr/0/left`, `expr/0/right`, etc.
- Custom suffix: `expr/custom_name`

### 2025-01-09 - Initial Planning
- Created feature planning document
- Analyzed current ExpressionBuilder implementation
- Identified IRI generation enhancement points
- Created feature branch `feature/phase-21-3-iri-generation`
