# Phase 21.5: Context Propagation for ExpressionBuilder Integration - Summary

**Status:** ✅ Complete
**Branch:** `feature/phase-21-5-context-propagation`
**Date:** 2025-01-09

## Overview

Integrated ExpressionBuilder into ControlFlowBuilder and ClauseBuilder, enabling full expression extraction for control flow structures and function clauses when `include_expressions: true` is configured.

## Implementation Summary

### ControlFlowBuilder Integration

Updated `lib/elixir_ontologies/builders/control_flow_builder.ex`:

1. **Optional ExpressionBuilder Parameter**
   - `build_conditional/3` now accepts `:expression_builder` option
   - Passes ExpressionBuilder to helper functions for expression building

2. **Condition Expression Building**
   ```elixir
   defp add_condition_triple(triples, expr_iri, condition, type, expression_builder, build_expressions?, context)
   ```
   - When `build_expressions?` is true: Builds full expression triples via `expression_builder.build/3`
   - Links condition expression via `Core.hasCondition()` object property
   - Falls back to boolean flag `hasCondition: true` in light mode

3. **Branch Body Expression Building**
   ```elixir
   defp add_single_branch_triple(triples, expr_iri, %Branch{type: :then, body: body}, expression_builder, build_expressions?, context)
   ```
   - Builds expression triples for then/else branch bodies
   - Links via `Core.hasThenBranch()` / `Core.hasElseBranch()` object properties
   - Falls back to boolean flags in light mode

4. **Cond Clause Expression Building**
   ```elixir
   defp add_cond_clause_expression_triples(triples, expr_iri, clause, expression_builder, context)
   ```
   - Builds expression triples for cond clause conditions and bodies
   - Links conditions via `Core.hasCondition()` object property

### ClauseBuilder Integration

Updated `lib/elixir_ontologies/builders/clause_builder.ex`:

1. **Optional ExpressionBuilder Parameter**
   - `build_clause/4` now accepts `:expression_builder` option
   - Extracts option and checks mode via `Context.full_mode_for_file?/2`

2. **Guard Expression Building**
   ```elixir
   defp build_guard_triples(head_bnode, clause_info, context, expression_builder, build_expressions?)
   ```
   - When `build_expressions?` is true: Builds full expression triples for guard AST
   - Links guard expression via `Core.hasGuard()` object property
   - Falls back to GuardClause blank node in light mode

3. **Body Expression Building**
   ```elixir
   defp build_function_body(clause_info, context, expression_builder, build_expressions?)
   ```
   - When `build_expressions?` is true: Builds full expression triples for body AST
   - Includes expression triples along with FunctionBody type triple
   - Falls back to FunctionBody blank node only in light mode

### Mode Checking

Both builders use `Context.full_mode_for_file?/2` to determine expression building mode:

```elixir
build_expressions? =
  expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)
```

This ensures:
- Full mode: `include_expressions: true` in config AND file is project code (not in `/deps/`)
- Light mode: Either `include_expressions: false` OR file is a dependency

## Documentation Updates

### ControlFlowBuilder

Updated @moduledoc to include:
- Expression Building section explaining light vs full mode
- Usage examples for both modes
- Documentation of `:expression_builder` option

### ClauseBuilder

Updated @moduledoc to include:
- Expression Building section explaining light vs full mode
- Usage examples for both modes
- Documentation of `:expression_builder` option

### @spec Annotations

Both builders updated with @spec noting optional ExpressionBuilder parameter:
- `@spec build_conditional(Conditional.t(), Context.t(), keyword())`
- `@spec build_clause(Clause.t(), RDF.IRI.t(), Context.t(), keyword())`

## Test Results

### New Tests Added

**ControlFlowBuilder Tests** (5 new tests):
1. `build_conditional/3 with expression_builder in full mode builds condition expression`
2. `build_conditional/3 without expression_builder uses boolean flags`
3. `build_conditional/3 in light mode uses boolean flags even with expression_builder`
4. `build_conditional/3 with dependency file uses boolean flags even in full mode`
5. `build_conditional/3 builds branch body expressions in full mode`

**ClauseBuilder Tests** (5 new tests):
1. `build_clause/3 with expression_builder in full mode builds guard expression`
2. `build_clause/3 without expression_builder uses blank node for guard`
3. `build_clause/3 in light mode uses blank node even with expression_builder`
4. `build_clause/3 with dependency file uses blank node even in full mode`
5. `build_clause/3 with nil guard handles gracefully`

### Full Test Suite
- 1636 doctests
- 29 properties
- 7108 tests total (up from 7098)
- 0 failures
- 361 excluded (pending/integration)

## Files Modified

1. `lib/elixir_ontologies/builders/control_flow_builder.ex` - Added ExpressionBuilder integration
2. `lib/elixir_ontologies/builders/clause_builder.ex` - Added ExpressionBuilder integration
3. `test/elixir_ontologies/builders/control_flow_builder_test.exs` - Added 5 integration tests
4. `test/elixir_ontologies/builders/clause_builder_test.exs` - Added 5 integration tests

## Files Created

1. `notes/features/phase-21-5-context-propagation.md` - Feature planning document
2. `notes/summaries/phase-21-5-context-propagation.md` - This summary document

## Next Steps

Phase 21.5 is complete. The ExpressionBuilder is now integrated into:
- ControlFlowBuilder for conditionals (if/unless/cond)
- ClauseBuilder for function clauses (guards and bodies)

Both builders support:
- Full mode: Complete expression triples when `include_expressions: true` and project file
- Light mode: Minimal metadata (boolean flags / blank nodes) for dependencies or when disabled

Ready for Phase 21.6+ which will integrate ExpressionBuilder into additional builders as needed.
