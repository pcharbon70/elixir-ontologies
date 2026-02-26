# Phase 21.2: ExpressionBuilder Module

**Status:** ✅ Complete
**Branch:** `feature/phase-21-2-expression-builder`
**Created:** 2025-01-10
**Completed:** 2025-01-10
**Target:** Implement core ExpressionBuilder module for AST-to-RDF conversion

## Problem Statement

The expression extraction infrastructure requires a central module that converts Elixir AST nodes into their RDF representation according to the elixir-core.ttl ontology. Currently, no such module exists, and each builder would need to implement its own ad-hoc expression handling.

The ExpressionBuilder module needs to:
1. Accept any Elixir AST node as input
2. Check configuration to determine if expressions should be extracted
3. Generate appropriate IRIs for expression resources
4. Dispatch to specific builder functions based on AST pattern
5. Return either `{:ok, {iri, triples}}` or `:skip`

## Solution Overview

Implement the ExpressionBuilder module with three main components:

1. **Module Structure (21.2.1)**: Basic module setup with imports, types, and documentation
2. **Main build/3 Function (21.2.2)**: Entry point that checks mode and delegates to dispatch
3. **Expression Dispatch (21.2.3)**: Pattern matching on AST to route to specific builders

The module will initially return `:skip` for all expressions since the specific builder functions (21.4) will be implemented in a later phase. This phase focuses on establishing the architecture and dispatch logic.

## Technical Details

### File to Create

- `lib/elixir_ontologies/builders/expression_builder.ex` - New module

### Module Dependencies

```elixir
# Required imports
alias ElixirOntologies.Builders.Context
alias ElixirOntologies.Builders.Helpers
alias ElixirOntologies.NS.Core
use RDF.Turtle
```

### Return Type Convention

```elixir
@spec build(Macro.t(), Context.t(), keyword()) ::
        {:ok, {RDF.IRI.t(), [RDF.Triple.t()]}} | :skip
```

- `{:ok, {iri, triples}}` - Expression was successfully built
- `:skip` - Expression should not be extracted (light mode or unsupported)

## Implementation Plan

### 21.2.1 Create ExpressionBuilder Module Structure

- [x] 21.2.1.1 Create `lib/elixir_ontologies/builders/expression_builder.ex`
- [x] 21.2.1.2 Add `@moduledoc` describing the module's purpose and API
- [x] 21.2.1.3 Import required modules: `Context`, `Helpers`, `NS.Core`
- [x] 21.2.1.4 Add `use RDF.Turtle` for convenient triple generation (NOT USED - removed)
- [x] 21.2.1.5 Define `@spec build/3` return type
- [x] 21.2.1.6 Add `@type ast :: Macro.t()` for clarity

### 21.2.2 Implement Main build/3 Function

- [x] 21.2.2.1 Implement `build(ast, context, opts)` that checks `context.config.include_expressions`
- [x] 21.2.2.2 Return `:skip` immediately when `include_expressions` is `false`
- [x] 21.2.2.3 Return `:skip` for `nil` AST nodes
- [x] 21.2.2.4 Check `Context.full_mode_for_file?/2` for project vs dependency
- [x] 21.2.2.5 Call `build_expression_triples/3` to generate triples
- [x] 21.2.2.6 Return `{:ok, {expr_iri, triples}}` tuple

### 21.2.3 Implement Expression Dispatch

- [x] 21.2.3.1 Add `build_expression_triples/3` with pattern matching on AST nodes
- [x] 21.2.3.2 Match comparison operators (`==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`) - STUB
- [x] 21.2.3.3 Match logical operators (`and`, `or`, `not`, `&&`, `||`, `!`) - STUB
- [x] 21.2.3.4 Match arithmetic operators (`+`, `-`, `*`, `/`, `div`, `rem`) - STUB
- [x] 21.2.3.5 Match pipe operator (`|>`) - STUB
- [x] 21.2.3.6 Match remote call (`{:., _, [module, function]}`) - STUB
- [x] 21.2.3.7 Match local call (atom call with args) - STUB
- [x] 21.2.3.8 Match integer literals - STUB
- [x] 21.2.3.9 Match string literals - STUB
- [x] 21.2.3.10 Match atom literals (`:foo`, `true`, `false`, `nil`) - STUB
- [x] 21.2.3.11 Match wildcard pattern `{:_}` - STUB
- [x] 21.2.3.12 Match variables `{name, _, context}` - STUB
- [x] 21.2.3.13 Add fallback for unknown expressions - STUB

**Note**: STUB functions will initially return `{:ok, {generic_iri, []}}` or similar placeholder behavior. Full implementation will be in section 21.4.

### Unit Tests

- [x] Test ExpressionBuilder.build/3 returns `:skip` when `include_expressions` is `false`
- [x] Test ExpressionBuilder.build/3 returns `:skip` for `nil` AST
- [x] Test ExpressionBuilder.build/3 returns `:skip` for dependency files
- [x] Test ExpressionBuilder.dispatch routes comparison operators
- [x] Test ExpressionBuilder.dispatch routes logical operators
- [x] Test ExpressionBuilder.dispatch routes literals
- [x] Test ExpressionBuilder.dispatch routes variables
- [x] Test ExpressionBuilder.dispatch routes unknown expressions to generic type

## Success Criteria

1. ExpressionBuilder module created with proper structure ✅
2. Main build/3 function checks mode and returns `:skip` appropriately ✅
3. Expression dispatch routes all AST patterns to stub functions ✅
4. All unit tests pass (55 tests) ✅
5. Module is well-documented with @moduledoc and @spec annotations ✅

## Status Log

### 2025-01-10 - Implementation Complete ✅
- **Created**: `lib/elixir_ontologies/builders/expression_builder.ex` (550+ lines)
- **Created**: `test/elixir_ontologies/builders/expression_builder_test.exs` (550+ lines, 55 tests)
- **All tests passing**: 55/55 tests pass

### Technical Implementation Details

**Module Structure**:
- Imports: `Context`, `Helpers`, `NS.Core`
- Types: `ast()`, `result()`
- Counter management: ETS-based counter for unique IRI generation

**Main build/3 Function**:
- Returns `:skip` for `nil` AST nodes
- Returns `:skip` in light mode (`!Context.full_mode?/1`)
- Returns `:skip` for dependency files (`!Context.full_mode_for_file?/2`)
- Delegates to `build_expression_triples/3` in full mode for project files

**Expression Dispatch (13 patterns implemented)**:
1. Comparison operators: `==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`
2. Logical operators: `and`, `or`, `not`, `&&`, `||`, `!`
3. Arithmetic operators: `+`, `-`, `*`, `/`, `div`, `rem`
4. Special operators: `|>`, `=`, `<>`, `++`, `--`, `in`, `&`
5. Calls: Remote (`Module.function`), Local (`function(args)`)
6. Literals: Integer, Float, String, Atom, List, Tuple, Map
7. Patterns: Variable (`{name, _, ctx}`), Wildcard (`{:_}`)
8. Fallback: Generic Expression type for unknown AST nodes

**Stub Functions**:
- `build_stub_expression/4` - Generates stub triples for operators with proper type and symbol
- `build_stub_literal/4` - Generates stub triples for literals with value properties
- `build_stub_variable/3` - Generates stub triples for variables with name property
- `build_stub_wildcard/2` - Generates stub triples for wildcard patterns

**IRI Generation**:
- Pattern: `{base_iri}expr_{counter}` for root expressions
- Helper: `fresh_iri/2` for nested expressions (e.g., `{parent}/left`, `{parent}/right`)
- Counter: ETS-based with `reset_counter/1` and `next_counter/1`

**Key Implementation Decisions**:
1. **Pattern Order**: Variables must come before local calls, wildcards before tuples
2. **Charlists**: All lists treated as ListLiterals (cannot distinguish `~c"hello"` from `[104, 101, ...]`)
3. **nil Handling**: `nil` returns `:skip` (treated as "no expression")
4. **ETS Counter**: Stores "next value" for correct increment behavior

### 2025-01-10 - Initial Planning
- Created feature planning document
- Identified 28 tasks across 3 sections
- Created feature branch `feature/phase-21-2-expression-builder`
- Analyzed existing builder patterns for consistency

## Notes/Considerations

### Stub Implementation Approach

Since section 21.4 (Core Expression Builders) will implement the actual builder functions, this phase should:

1. Create the dispatch structure with pattern matching
2. Return placeholder results from stubs (e.g., `{:ok, {iri, []}}` with generic Expression type)
3. Focus on getting the architecture right

Alternative: Implement a few simple expression types (literals, variables) to demonstrate the pattern, leaving complex operators for 21.4.

### File Path Detection

The main `build/3` function should check `Context.full_mode_for_file?/2` which combines:
- `context.config.include_expressions`
- `Config.project_file?(file_path)`

This ensures dependency files are always light mode.

### Counter for IRI Generation

A simple counter will be needed for generating unique expression IRIs. This can be:
- An Elixir Agent for process-global state
- A counter stored in the Context
- A simple integer counter with `generate_counter/0` function

For this phase, a simple counter function will suffice.

## Status Log

### 2025-01-10 - Initial Planning
- Created feature planning document
- Identified 13 tasks across 3 sections
- Created feature branch `feature/phase-21-2-expression-builder`
- Analyzed existing builder patterns for consistency
