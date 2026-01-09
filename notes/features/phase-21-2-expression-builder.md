# Feature: Phase 21.2 - ExpressionBuilder Module

## Status: In Progress

**Started:** 2025-01-09
**Branch:** `feature/phase-21-2-expression-builder`
**Target:** `expressions` branch

## Problem Statement

The elixir-ontologies project needs to convert Elixir AST nodes to their RDF representation according to the elixir-core.ttl ontology. Currently, there is no module to handle expression extraction, which is essential for capturing:
- Function guards
- Condition expressions
- Function bodies
- Other code constructs

## Solution Overview

Create an `ExpressionBuilder` module that:
1. Checks if expression extraction is enabled (via `Context.full_mode_for_file?/2`)
2. Pattern matches on Elixir AST nodes to dispatch to appropriate builder functions
3. Returns either `{:ok, {expr_iri, triples}}` or `:skip` for light mode
4. Uses the Core ontology classes for expression types

## Technical Details

### Files to Create/Modify

**Primary:**
- `lib/elixir_ontologies/builders/expression_builder.ex` - NEW module

**Tests:**
- `test/elixir_ontologies/builders/expression_builder_test.exs` - NEW test file

### Dependencies

- `ElixirOntologies.Builders.Context` - For checking expression mode
- `ElixirOntologies.Builders.Helpers` - For triple generation utilities
- `ElixirOntologies.NS.Core` - For ontology classes (Expression, Literal, OperatorExpression, etc.)
- `RDF` - For RDF data structures

### Module Structure

```elixir
defmodule ElixirOntologies.Builders.ExpressionBuilder do
  @moduledoc """
  Builds RDF triples for Elixir AST expression nodes.

  This module converts Elixir AST nodes to their RDF representation
  according to the elixir-core.ttl ontology. Expression extraction is
  opt-in via the `include_expressions` configuration option.
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.NS.Core

  # Main entry point
  def build(ast, context, opts \\ [])

  # Expression dispatch via pattern matching
  defp build_expression_triples(ast, expr_iri, context)

  # Specific expression builders (implemented incrementally)
  defp build_comparison(op, left, right, expr_iri, context)
  defp build_logical(op, left, right, expr_iri, context)
  defp build_arithmetic(op, left, right, expr_iri, context)
  # ... etc
end
```

### Elixir AST Format

Elixir AST uses 3-tuple format: `{atom | tuple, metadata, children}`

Examples:
- `{:==, [], [{:x, [], nil}, 1]}` - comparison `x == 1`
- `{:and, [], [true, false]}` - logical `and`
- `{:+, [], [1, 2]}` - arithmetic `1 + 2`
- `{:"::", _, [{:x, [], nil}, {:integer, [], []}]}` - type spec `x :: integer()`
- `{{:., [], [{:__aliases__, [], [:String]}, :to_integer]}, [], ["123"]}` - remote call `String.to_integer("123")`

## Success Criteria

- [ ] ExpressionBuilder module created with proper moduledoc
- [ ] `build/3` function returns `:skip` in light mode
- [ ] `build/3` function returns `:skip` for nil AST
- [ ] Expression dispatch correctly routes comparison operators
- [ ] Expression dispatch correctly routes logical operators
- [ ] Expression dispatch correctly routes arithmetic operators
- [ ] Expression dispatch correctly routes literals
- [ ] Expression dispatch correctly routes variables
- [ ] Unknown expressions get generic `Expression` type
- [ ] All functions have @spec annotations
- [ ] Unit tests for all public functions
- [ ] Unit tests for expression dispatch routing
- [ ] 100% test coverage

## Implementation Plan

### Step 1: Create Module Structure
- [ ] Create `lib/elixir_ontologies/builders/expression_builder.ex`
- [ ] Add module documentation with usage examples
- [ ] Define @spec for main `build/3` function
- [ ] Import required modules (Context, Helpers, NS.Core)

### Step 2: Implement Main build/3 Function
- [ ] Check `Context.full_mode_for_file?/2` for mode
- [ ] Return `:skip` when light mode or nil AST
- [ ] Generate expression IRI (simple counter-based for now, refined in 21.3)
- [ ] Call `build_expression_triples/3`
- [ ] Return `{:ok, {expr_iri, triples}}` tuple

### Step 3: Implement Expression Dispatch
- [ ] Add `build_expression_triples/3` with pattern matching
- [ ] Match comparison operators (`==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`)
- [ ] Match logical operators (`and`, `or`, `not`, `&&`, `||`, `!`)
- [ ] Match arithmetic operators (`+`, `-`, `*`, `/`, `div`, `rem`)
- [ ] Match literals (integers, floats, strings, atoms)
- [ ] Match variables `{name, [], context}`
- [ ] Match wildcard `{:_}`
- [ ] Add fallback for unknown expressions

### Step 4: Implement Builder Functions (stubs for now, detailed in 21.4)
- [ ] `build_comparison/5` - stub returning generic BinaryOperator
- [ ] `build_logical/5` - stub returning generic LogicalOperator
- [ ] `build_arithmetic/5` - stub returning generic ArithmeticOperator
- [ ] `build_literal/5` - for integers, floats, strings
- [ ] `build_atom_literal/3` - for atoms
- [ ] `build_variable/3` - for variables
- [ ] `build_wildcard/3` - for `_` pattern

### Step 5: Write Tests
- [ ] Create test file
- [ ] Test light mode returns `:skip`
- [ ] Test nil AST returns `:skip`
- [ ] Test comparison operators generate correct types
- [ ] Test logical operators generate correct types
- [ ] Test literals generate correct types
- [ ] Test variables generate correct triples
- [ ] Test unknown expressions get generic Expression type

## Notes/Considerations

1. **IRI Generation**: Step 2 uses simple counter-based IRIs. Phase 21.3 will refine this with proper IRI generation patterns.

2. **Builder Functions**: Step 4 creates stub functions that return basic types. Phase 21.4 will implement full nested expression building with proper operand handling.

3. **AST Metadata**: The second element of AST tuples contains metadata (line numbers, etc.). We're not using this yet but should consider for Phase 21.3+.

4. **Remote Calls**: The AST for `Module.function(args)` is complex:
   ```elixir
   {{:., [], [{:__aliases__, [], [:Module]}, :function]}, [], [args]}
   ```
   This will need special handling in Phase 21.4 or later.

5. **Test Coverage**: Focus on testing the dispatch logic and return values. Detailed triple content testing will be more relevant after Phase 21.4 implements full builders.

## Progress

- [x] Create feature branch
- [x] Read planning documents and existing code
- [x] Create feature planning document
- [ ] Implement module structure
- [ ] Implement main build/3 function
- [ ] Implement expression dispatch
- [ ] Implement builder stubs
- [ ] Write tests
- [ ] Update planning document
- [ ] Ask for permission to commit and merge
