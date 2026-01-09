# Phase 26: Function Guard Expression Integration

This phase integrates the ExpressionBuilder into ClauseBuilder to extract full guard expressions for function clauses. Guards are a critical part of Elixir's pattern matching system and must be extracted completely to enable queries like "find all functions that guard on `is_binary/1`" or "find functions with compound guards".

## 26.1 Guard Clause Detection and Extraction

This section updates the guard detection and extraction in ClauseBuilder to support full expression trees.

### 26.1.1 Update build_guard_triples for Full Mode
- [ ] 26.1.1.1 Modify `build_guard_triples/3` in ClauseBuilder to accept context
- [ ] 26.1.1.2 Check `context.config.include_expressions` flag
- [ ] 26.1.1.3 When `false`: use existing blank node approach (light mode)
- [ ] 26.1.1.4 When `true`: generate named guard IRI instead of blank node
- [ ] 26.1.1.5 Generate guard IRI: `{head_bnode}/guard`
- [ ] 26.1.1.6 Call `ExpressionBuilder.build/3` with guard AST
- [ ] 26.1.1.7 Pass `base_iri: head_bnode, suffix: "guard"` to ExpressionBuilder
- [ ] 26.1.1.8 Handle `:skip` return gracefully (shouldn't happen in full mode)
- [ ] 26.1.1.9 Return guard triples including expression tree

### 26.1.2 Guard Clause Type Assignment
- [ ] 26.1.2.1 Create type triple: `guard_iri a Core.GuardClause`
- [ ] 26.1.2.2 Link from function head via `core:hasGuard guard_iri`
- [ ] 26.1.2.3 Preserve existing guard structure in light mode
- [ ] 26.1.2.4 Ensure guard IRI is queryable via SPARQL

**Section 26.1 Unit Tests:**
- [ ] Test guard extraction in light mode (blank node)
- [ ] Test guard extraction in full mode (named IRI with expression)
- [ ] Test guard extraction creates GuardClause type
- [ ] Test guard extraction links from function head
- [ ] Test guard extraction handles simple guard: `when x > 0`
- [ ] Test guard extraction handles complex guard

## 26.2 Compound Guard Expression Support

This section implements support for guards combined with `and` and `or` operators.

### 26.2.1 And-Combined Guards
- [ ] 26.2.1.1 Detect `:and` in guard AST
- [ ] 26.2.1.2 Extract left guard expression recursively
- [ ] 26.2.1.3 Extract right guard expression recursively
- [ ] 26.2.1.4 Build as `Core.LogicalOperator` with operator "and"
- [ ] 26.2.1.5 Link sub-guards via `hasLeftOperand` and `hasRightOperand`
- [ ] 26.2.1.6 Ensure guard expression tree is preserved
- [ ] 26.2.1.7 Handle 3+ combined guards: `a and b and c` (nested structure)

### 26.2.2 Or-Combined Guards
- [ ] 26.2.2.1 Detect `:or` in guard AST
- [ ] 26.2.2.2 Extract left guard expression recursively
- [ ] 26.2.2.3 Extract right guard expression recursively
- [ ] 26.2.2.4 Build as `Core.LogicalOperator` with operator "or"
- [ ] 26.2.2.5 Link sub-guards via `hasLeftOperand` and `hasRightOperand`
- [ ] 26.2.2.6 Handle 3+ combined guards: `a or b or c` (nested structure)

**Section 26.2 Unit Tests:**
- [ ] Test guard extraction with and combination
- [ ] Test guard extraction with or combination
- [ ] Test guard extraction with mixed and/or
- [ ] Test guard extraction with multiple and/or
- [ ] Test guard extraction preserves guard structure

## 26.3 Guard Built-in Function Extraction

This section implements extraction for guard built-in functions like `is_binary/1`, `is_integer/1`, `is_list/1`, etc.

### 26.3.1 Detect Guard Built-in Calls
- [ ] 26.3.1.1 Detect remote calls starting with `is_` prefix
- [ ] 26.3.1.2 Match `{:., _, [{:is_, _, _}, function]}` pattern
- [ ] 26.3.1.3 Match other allowed guard functions
- [ ] 26.3.1.4 Identify function name: `is_binary`, `is_integer`, etc.
- [ ] 26.3.1.5 Identify arity (number of arguments)
- [ ] 26.3.1.6 Extract function arguments as expressions

### 26.3.2 Build Guard Function Calls
- [ ] 26.3.2.1 Create type triple: `expr_iri a Core.RemoteCall` (or specific type)
- [ ] 26.3.2.2 Extract function name and store in `functionName` property
- [ ] 26.3.2.3 Extract module name (often implicit as `:erlang` or `Kernel`)
- [ ] 26.3.2.4 Link module via `refersToModule` or similar
- [ ] 26.3.2.5 Extract each argument recursively
- [ ] 26.3.2.6 Link arguments via `hasArgument` property
- [ ] 26.3.2.7 Handle common guard functions: `is_binary/1`, `is_integer/1`, `is_list/1`, `is_atom/1`, `is_map/1`, `is_tuple/1`, `is_number/1`, `is_bitstring/1`, `is_float/1`, `is_function/1`, `is_function/2`, `is_pid/1`, `is_port/1`, `is_reference/1`, `is_alive/1`, `is_process_alive/1`

### 26.3.3 Guard Comparison Operators
- [ ] 26.3.3.1 Detect comparison operators within guards: `==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`
- [ ] 26.3.3.2 Extract using existing comparison operator builder
- [ ] 26.3.3.3 Ensure operator type is `Core.ComparisonOperator`
- [ ] 26.3.3.4 Link operands correctly

**Section 26.3 Unit Tests:**
- [ ] Test guard extraction for is_binary/1
- [ ] Test guard extraction for is_integer/1
- [ ] Test guard extraction for is_list/1
- [ ] Test guard extraction for is_atom/1
- [ ] Test guard extraction for is_map/1
- [ ] Test guard extraction for is_tuple/1
- [ ] Test guard extraction for comparison in guard
- [ ] Test guard extraction for complex guard with built-ins
- [ ] Test guard extraction for guard with multiple arguments

## 26.4 Guard Context and Semantics

This section ensures that guard expressions preserve their semantic meaning and can be distinguished from regular expressions.

### 26.4.1 Guard Context Marking
- [ ] 26.4.1.1 Ensure guard expressions are marked with guard context
- [ ] 26.4.1.2 Create `inGuardContext` property or annotation
- [ ] 26.4.1.3 Distinguish guard expressions from body expressions
- [ ] 26.4.1.4 Document guard limitations (only certain expressions allowed)
- [ ] 26.4.1.5 Note: guard-friendly expressions are a subset of all expressions

### 26.4.2 Guard Expression Validation
- [ ] 26.4.2.1 Optionally validate that guard expressions are guard-safe
- [ ] 26.4.2.2 Create list of allowed guard operations
- [ ] 26.4.2.3 Create list of allowed guard functions
- [ ] 26.4.2.4 Add validation helper: `guard_safe?/1`
- [ ] 26.4.2.5 Optionally warn about non-guard-safe expressions
- [ ] 26.4.2.6 Document that Elixir compiler validates guards

**Section 26.4 Unit Tests:**
- [ ] Test guard context marking works correctly
- [ ] Test guard expressions are distinguished from body expressions
- [ ] Test guard_safe?/1 identifies allowed guard operations
- [ ] Test guard_safe?/1 rejects non-guard-safe operations
- [ ] Test guard_safe?/1 handles nested expressions

## 26.5 Multi-Clause Function Guards

This section ensures that guards are correctly extracted for functions with multiple clauses, each potentially having different guards.

### 26.5.1 Per-Clause Guard Extraction
- [ ] 26.5.1.1 Ensure guard extraction works for each clause independently
- [ ] 26.5.1.2 Handle clauses with guards vs clauses without guards
- [ ] 26.5.1.3 Generate unique guard IRIs: `{clause_iri}/guard`
- [ ] 26.5.1.4 Link guards from function head
- [ ] 26.5.1.5 Preserve guard clause order (important for semantics)

### 26.5.2 Guard Order and Evaluation
- [ ] 26.5.2.1 Document that guards are evaluated in order
- [ ] 26.5.2.2 First matching clause wins (Elixir semantics)
- [ ] 26.5.2.3 Guard expression structure should reflect evaluation order
- [ ] 26.5.2.4 And/or expressions preserve left-to-right evaluation

**Section 26.5 Unit Tests:**
- [ ] Test guard extraction for multi-clause function
- [ ] Test guard extraction handles mixed guarded/unguarded clauses
- [ ] Test guard extraction preserves guard order
- [ ] Test guard extraction works for complex multi-clause functions

## Phase 26 Integration Tests

- [ ] Test complete guard extraction: simple guards, compound guards, guard functions
- [ ] Test guard extraction in light mode (backward compat)
- [ ] Test guard extraction in full mode (full expression tree)
- [ ] Test guard extraction for real-world function guards
- [ ] Test guard extraction handles all guard built-in functions
- [ ] Test guard extraction with nested and/or combinations
- [ ] Test SPARQL queries find functions by guard type
- [ ] Test SPARQL queries find functions using specific guard functions
- [ ] Test SPARQL queries find functions with comparison guards
- [ ] Test guard expression trees are correctly structured
- [ ] Test guard extraction integrates with clause extraction

**Integration Test Summary:**
- 11 integration tests covering all guard scenarios
- Tests verify guard extraction completeness and SPARQL queryability
- Tests confirm both light and full mode behavior
- Test file: `test/elixir_ontologies/builders/guard_extraction_test.exs`
