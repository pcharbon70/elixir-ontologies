# Phase 21.5: Context Propagation for ExpressionBuilder Integration

**Status:** ✅ Complete
**Branch:** `feature/phase-21-5-context-propagation`
**Created:** 2025-01-09
**Completed:** 2025-01-09
**Target:** Integrate ExpressionBuilder into ControlFlowBuilder and ClauseBuilder

## Problem Statement

The ExpressionBuilder module (completed in Phase 21.4) can build RDF triples for Elixir AST expression nodes, but it is not integrated into the other builders that handle control flow structures and function clauses. Currently:

1. **ControlFlowBuilder** only stores boolean flags (e.g., `hasCondition: true`) but doesn't build actual expression triples for conditions and branch bodies
2. **ClauseBuilder** doesn't build expression triples for guard conditions or clause bodies
3. The `include_expressions` configuration option exists but is not used by these builders

This means that even when `include_expressions: true` is set, the full expression trees are not being extracted from conditionals and clauses.

## Solution Overview

Implement optional ExpressionBuilder integration for ControlFlowBuilder and ClauseBuilder:

1. **Optional Parameter Pattern**: Add optional `expression_builder` parameter to builder functions
2. **Context-Based Mode Check**: Use `Context.full_mode_for_file?/2` to check if expressions should be built
3. **Conditional Expression Building**: Only build expressions when ExpressionBuilder is provided AND full mode is enabled
4. **Backward Compatibility**: When ExpressionBuilder is nil or full mode is disabled, fall back to boolean flag behavior

## Technical Details

### Files to Modify

- `lib/elixir_ontologies/builders/control_flow_builder.ex` - Add ExpressionBuilder integration
- `lib/elixir_ontologies/builders/clause_builder.ex` - Add ExpressionBuilder integration
- `test/elixir_ontologies/builders/control_flow_builder_test.exs` - Add integration tests
- `test/elixir_ontologies/builders/clause_builder_test.exs` - Add integration tests

### Integration Points

#### ControlFlowBuilder

**Current behavior** (lines 402-410):
```elixir
defp add_condition_triple(triples, expr_iri, condition, type)
     when type in [:if, :unless] and not is_nil(condition) do
  triple = Helpers.datatype_property(expr_iri, Core.hasCondition(), true, RDF.XSD.Boolean)
  [triple | triples]
end
```

**New behavior** with ExpressionBuilder:
- If ExpressionBuilder provided and full mode: Build expression triples for condition AST
- Otherwise: Fall back to boolean flag behavior

**Integration points**:
1. `build_conditional/3` - Accept optional `:expression_builder` opt
2. `add_condition_triple/4` - Build expression for condition AST
3. `add_single_branch_triple/3` - Build expression for branch body AST
4. `add_cond_clause_triples/4` - Build expressions for cond clause conditions and bodies

#### ClauseBuilder

**Current behavior** (lines 219-235):
```elixir
defp build_guard_triples(head_bnode, clause_info) do
  case clause_info.head[:guard] do
    nil -> []
    _guard_ast ->
      guard_bnode = Helpers.blank_node("guard")
      [
        Helpers.type_triple(guard_bnode, Core.GuardClause),
        Helpers.object_property(head_bnode, Core.hasGuard(), guard_bnode)
      ]
  end
end
```

**New behavior** with ExpressionBuilder:
- If ExpressionBuilder provided and full mode: Build expression triples for guard AST
- Otherwise: Create GuardClause blank node only

**Integration points**:
1. `build_clause/3` - Accept optional `:expression_builder` opt
2. `build_guard_triples/2` - Build expression for guard AST
3. `build_function_body/2` - Build expression for body AST

### Ontology Terms Used

**Object Properties** (for linking to expressions):
- `Core.hasCondition()` - Links conditional to its condition expression
- `Core.hasThenBranch()` - Links if to then branch expression
- `Core.hasElseBranch()` - Links if to else branch expression
- `Core.hasGuard()` - Links clause head to guard expression
- `Core.hasBody()` - Links clause to body expression

**Expression Types** (from ExpressionBuilder):
- `Core.ComparisonOperator`
- `Core.LogicalOperator`
- `Core.IntegerLiteral`
- `Core.Variable`
- etc.

## Implementation Plan

### 21.5.1 ControlFlowBuilder Updates

- [ ] 21.5.1.1 Add `:expression_builder` to `build_conditional/3` opts
- [ ] 21.5.1.2 Update `add_condition_triple/4` to use ExpressionBuilder when provided
- [ ] 21.5.1.3 Build expression triples for if/unless condition AST
- [ ] 21.5.1.4 Link condition expression via `Core.hasCondition()` object property
- [ ] 21.5.1.5 Update `add_single_branch_triple/3` to use ExpressionBuilder
- [ ] 21.5.1.6 Build expression triples for then/else branch body AST
- [ ] 21.5.1.7 Update `add_cond_clause_triples/4` for cond expressions
- [ ] 21.5.1.8 Build expression triples for cond clause conditions and bodies
- [ ] 21.5.1.9 Ensure fallback to boolean flags when ExpressionBuilder is nil

### 21.5.2 ClauseBuilder Updates

- [ ] 21.5.2.1 Add `:expression_builder` to `build_clause/3` opts
- [ ] 21.5.2.2 Update `build_guard_triples/2` to use ExpressionBuilder when provided
- [ ] 21.5.2.3 Build expression triples for guard AST
- [ ] 21.5.2.4 Link guard expression via `Core.hasGuard()` object property
- [ ] 21.5.2.5 Update `build_function_body/2` to use ExpressionBuilder
- [ ] 21.5.2.6 Build expression triples for clause body AST
- [ ] 21.5.2.7 Link body expression via `Structure.hasBody()` object property
- [ ] 21.5.2.8 Ensure fallback when ExpressionBuilder is nil

### 21.5.3 Documentation and Specs

- [ ] 21.5.3.1 Add `@spec` annotations noting ExpressionBuilder dependency
- [ ] 21.5.3.2 Document optional ExpressionBuilder parameter in @moduledoc
- [ ] 21.5.3.3 Document that expressions require `include_expressions: true`
- [ ] 21.5.3.4 Add examples showing ExpressionBuilder usage

### 21.5.4 Tests

- [ ] 21.5.4.1 Test ControlFlowBuilder with ExpressionBuilder (full mode)
- [ ] 21.5.4.2 Test ControlFlowBuilder without ExpressionBuilder (light mode)
- [ ] 21.5.4.3 Test condition expression triples are built correctly
- [ ] 21.5.4.4 Test branch body expression triples are built correctly
- [ ] 21.5.4.5 Test cond clause expressions are built correctly
- [ ] 21.5.4.6 Test ClauseBuilder with ExpressionBuilder (full mode)
- [ ] 21.5.4.7 Test ClauseBuilder without ExpressionBuilder (light mode)
- [ ] 21.5.4.8 Test guard expression triples are built correctly
- [ ] 21.5.4.9 Test body expression triples are built correctly
- [ ] 21.5.4.10 Test config propagation through context (full_mode_for_file?)

## Success Criteria

1. ControlFlowBuilder accepts optional ExpressionBuilder parameter
2. ControlFlowBuilder builds expression triples when provided and full mode enabled
3. ControlFlowBuilder falls back to boolean flags when ExpressionBuilder is nil or light mode
4. ClauseBuilder accepts optional ExpressionBuilder parameter
5. ClauseBuilder builds expression triples when provided and full mode enabled
6. ClauseBuilder falls back to blank nodes when ExpressionBuilder is nil or light mode
7. @spec annotations document ExpressionBuilder dependency
8. Module documentation explains `include_expressions` requirement
9. All new tests pass
10. All existing tests continue to pass

## Example Usage

### ControlFlowBuilder with ExpressionBuilder

```elixir
alias ElixirOntologies.Builders.{ControlFlowBuilder, Context, ExpressionBuilder}

context = Context.new(
  base_iri: "https://example.org/code#",
  config: %{include_expressions: true},
  file_path: "lib/my_app.ex"
)

conditional = %Conditional{
  type: :if,
  condition: {:>, [], [{:x, [], nil}, 5]},
  branches: [
    %Branch{type: :then, body: :ok},
    %Branch{type: :else, body: :error}
  ],
  metadata: %{}
}

# With ExpressionBuilder
{expr_iri, triples} = ControlFlowBuilder.build_conditional(
  conditional,
  context,
  containing_function: "MyApp/check/0",
  index: 0,
  expression_builder: ExpressionBuilder
)

# Result includes:
# - expr_iri a IfExpression
# - expr_iri core:hasCondition expr/0 (ComparisonOperator: x > 5)
# - expr_iri core:hasThenBranch expr/0/then (AtomLiteral: :ok)
# - expr_iri core:hasElseBranch expr/0/else (AtomLiteral: :error)
```

### Without ExpressionBuilder (Light Mode)

```elixir
# Without ExpressionBuilder or light mode
{expr_iri, triples} = ControlFlowBuilder.build_conditional(
  conditional,
  context,
  containing_function: "MyApp/check/0",
  index: 0
  # No expression_builder parameter
)

# Result includes:
# - expr_iri a IfExpression
# - expr_iri core:hasCondition true (boolean flag only)
# - expr_iri core:hasThenBranch true
# - expr_iri core:hasElseBranch true
```

## Notes/Considerations

### Optional Parameter vs Module Pattern

Using the module name (`ExpressionBuilder`) as an optional parameter allows:
- Runtime check for ExpressionBuilder availability
- Conditional calling: `if expression_builder, do: expression_builder.build(...)`
- No hard dependency - callers can pass nil to disable expressions

Alternative approach considered: Store ExpressionBuilder in context metadata. Rejected because:
- Context is meant for configuration, not module references
- Allows different ExpressionBuilder instances per call
- Keeps the API explicit - caller decides whether to pass ExpressionBuilder

### Mode Checking

The `Context.full_mode_for_file?/2` helper combines:
1. Config check: `include_expressions: true`
2. Project file check: `not String.contains?(file_path, "/deps/")`

This ensures dependencies always use light mode, keeping storage manageable.

### IRI Generation for Nested Expressions

Expression IRIs are generated with relative paths:
- Condition: `expr/0/condition`
- Then branch: `expr/0/then`
- Else branch: `expr/0/else`

These are generated by ExpressionBuilder using `fresh_iri/2`.

## Status Log

### 2025-01-09 - Implementation Complete ✅
- **ControlFlowBuilder Updates**: Added optional `:expression_builder` parameter to `build_conditional/3`
- **Condition Expression Building**: Implemented full expression building for if/unless conditions
- **Branch Expression Building**: Implemented full expression building for then/else branches
- **Cond Clause Expression Building**: Implemented full expression building for cond clauses
- **ClauseBuilder Updates**: Added optional `:expression_builder` parameter to `build_clause/4`
- **Guard Expression Building**: Implemented full expression building for guard clauses
- **Body Expression Building**: Implemented full expression building for clause bodies
- **Documentation**: Updated @moduledoc for both builders with expression building examples
- **@spec Annotations**: Added @spec documentation for ExpressionBuilder dependency
- **Tests**: Added 10 new tests (5 for ControlFlowBuilder, 5 for ClauseBuilder)
- **Full Test Suite**: All 7108 tests pass (1636 doctests, 29 properties, 7108 tests, 0 failures)

### Implementation Details

**ControlFlowBuilder Changes:**
- `build_conditional/3` now accepts `:expression_builder` option
- `add_condition_triple/6` builds expression triples when enabled
- `add_branch_triples/6` builds branch body expressions when enabled
- `add_cond_clause_triples/6` builds cond clause expressions when enabled
- Falls back to boolean flags when ExpressionBuilder not provided or light mode

**ClauseBuilder Changes:**
- `build_clause/4` now accepts `:expression_builder` option
- `build_function_head/5` passes expression_builder to guard building
- `build_guard_triples/5` builds guard expression triples when enabled
- `build_function_body/5` builds body expression triples when enabled
- Falls back to blank nodes when ExpressionBuilder not provided or light mode

**Mode Checking:**
Both builders use `Context.full_mode_for_file?/2` to determine if expressions should be built:
- Returns `true` only when `include_expressions: true` AND file is project code
- Dependencies (files in `/deps/`) always use light mode

### 2025-01-09 - Initial Planning
- Created feature planning document
- Analyzed ControlFlowBuilder and ClauseBuilder current implementations
- Identified integration points for ExpressionBuilder
- Created feature branch `feature/phase-21-5-context-propagation`
