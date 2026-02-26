# Phase 21: Configuration & Expression Infrastructure

This phase establishes the infrastructure for optional expression extraction. We'll add the `include_expressions` configuration option, create the `ExpressionBuilder` module with core AST-to-RDF conversion, establish IRI generation patterns for nested expressions, and update the Context to propagate the configuration through the builder pipeline.

## 21.1 Configuration Extension ✅ COMPLETE

This section extends the Config module to support the `include_expressions` option that controls whether full expression ASTs are extracted and stored in the RDF graph.

### 21.1.1 Add include_expressions to Config Struct ✅
- [x] 21.1.1.1 Add `include_expressions: false` field to `Config` struct in `lib/elixir_ontologies/config.ex`
- [x] 21.1.1.2 Add `include_expressions: boolean()` to the `@type t()` spec
- [x] 21.1.1.3 Update module documentation to describe the new option
- [x] 21.1.1.4 Document trade-offs: storage vs. detail, extraction speed

### 21.1.2 Update Config Merge and Validation ✅
- [x] 21.1.2.1 Add `:include_expressions` to `valid_keys` list in `merge/2`
- [x] 21.1.2.2 Add `validate_boolean(:include_expressions, config.include_expressions)` call in `validate/1`
- [x] 21.1.2.3 Update validation docstring to include `include_expressions`
- [x] 21.1.2.4 Update defaults documentation in `default/0` docstring

### 21.1.3 Project vs Dependencies Distinction ✅
- [x] 21.1.3.1 Document that `include_expressions: true` applies only to project code, not dependencies
- [x] 21.1.3.2 Add `project_file?/1` helper to detect project files vs dependency files
- [x] 21.1.3.3 Check for `/deps/` in file path to identify dependencies
- [x] 21.1.3.4 Add `should_extract_full?(path, config)` helper combining both checks
- [x] 21.1.3.5 Document that dependencies are always extracted in light mode regardless of config
- [x] 21.1.3.6 Add configuration note explaining storage efficiency rationale
- [x] 21.1.3.7 Update `Context.full_mode_for_file?/2` to accept file path for automatic detection

**Section 21.1 Unit Tests:** ✅
- [x] Test Config struct initializes with `include_expressions: false`
- [x] Test Config.merge/2 accepts `include_expressions` option
- [x] Test Config.merge/2 rejects invalid `include_expressions` values (non-boolean)
- [x] Test Config.validate/1 passes with valid `include_expressions` values
- [x] Test Config.validate/1 returns errors for invalid `include_expressions`
- [x] Test `project_file?/1` returns true for lib/ and src/ files
- [x] Test `project_file?/1` returns false for deps/ files
- [x] Test `should_extract_full?/2` returns true when config enabled and project file
- [x] Test `should_extract_full?/2` returns false when config disabled
- [x] Test `should_extract_full?/2` returns false for dependency files even with config enabled

## 21.2 ExpressionBuilder Module

This section creates the core ExpressionBuilder module that converts Elixir AST nodes to their RDF representation according to the elixir-core.ttl ontology.

### 21.2.1 Create ExpressionBuilder Module Structure
- [ ] 21.2.1.1 Create `lib/elixir_ontologies/builders/expression_builder.ex`
- [ ] 21.2.1.2 Add `@moduledoc` describing the module's purpose and API
- [ ] 21.2.1.3 Import required modules: `Context`, `Helpers`, `NS.Core`
- [ ] 21.2.1.4 Add `use RDF.Turtle` for convenient triple generation
- [ ] 21.2.1.5 Define `@spec build/3` return type: `{:ok, {RDF.IRI.t(), [RDF.Triple.t()]}} | :skip`

### 21.2.2 Implement Main build/3 Function
- [ ] 21.2.2.1 Implement `build(ast, context, opts)` that checks `context.config.include_expressions`
- [ ] 21.2.2.2 Return `:skip` immediately when `include_expressions` is `false`
- [ ] 21.2.2.3 Return `:skip` for `nil` AST nodes
- [ ] 21.2.2.4 Generate expression IRI using `expression_iri/2` helper
- [ ] 21.2.2.5 Call `build_expression_triples/3` to generate triples
- [ ] 21.2.2.6 Return `{:ok, {expr_iri, triples}}` tuple

### 21.2.3 Implement Expression Dispatch
- [ ] 21.2.3.1 Add `build_expression_triples/3` with pattern matching on AST nodes
- [ ] 21.2.3.2 Match comparison operators (`==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`) → `build_comparison/5`
- [ ] 21.2.3.3 Match logical operators (`and`, `or`, `not`, `&&`, `||`, `!`) → `build_logical/5`
- [ ] 21.2.3.4 Match arithmetic operators (`+`, `-`, `*`, `/`, `div`, `rem`) → `build_arithmetic/5`
- [ ] 21.2.3.5 Match pipe operator (`|>`) → `build_pipe/5`
- [ ] 21.2.3.6 Match remote call (`{:., _, [module, function]}`) → `build_remote_call/3`
- [ ] 21.2.3.7 Match local call (atom call with args) → `build_local_call/3`
- [ ] 21.2.3.8 Match integer literals → `build_literal/5`
- [ ] 21.2.3.9 Match string literals → `build_literal/5`
- [ ] 21.2.3.10 Match atom literals (`:foo`, `true`, `false`, `nil`) → `build_atom_literal/3`
- [ ] 21.2.3.11 Match wildcard pattern `{:_}` → `build_wildcard/3`
- [ ] 21.2.3.12 Match variables `{name, _, context}` → `build_variable/3`
- [ ] 21.2.3.13 Add fallback for unknown expressions → generic `Expression` type

**Section 21.2 Unit Tests:**
- [ ] Test ExpressionBuilder.build/3 returns `:skip` when `include_expressions` is `false`
- [ ] Test ExpressionBuilder.build/3 returns `:skip` for `nil` AST
- [ ] Test ExpressionBuilder.build/3 generates IRI with correct base
- [ ] Test ExpressionBuilder.dispatch routes comparison operators correctly
- [ ] Test ExpressionBuilder.dispatch routes logical operators correctly
- [ ] Test ExpressionBuilder.dispatch routes literals correctly
- [ ] Test ExpressionBuilder.dispatch routes variables correctly
- [ ] Test ExpressionBuilder.dispatch routes unknown expressions to generic type

## 21.3 IRI Generation for Expressions

This section implements IRI generation strategies for nested expressions, ensuring stable, queryable IRIs that reflect the expression structure.

### 21.3.1 Expression IRI Helpers
- [ ] 21.3.1.1 Implement `expression_iri(context, opts)` generating `{base}expr/{suffix}`
- [ ] 21.3.1.2 Extract `base_iri` from `:base_iri` option or fallback to `context.base_iri`
- [ ] 21.3.1.3 Extract suffix from `:suffix` option or generate `"anon_#{counter}"`
- [ ] 21.3.1.4 Implement `fresh_iri(base_iri, suffix)` for nested expressions
- [ ] 21.3.1.5 Handle relative IRIs for child expressions (left, right, condition, etc.)
- [ ] 21.3.1.6 Ensure IRI uniqueness within a single extraction

### 21.3.2 IRI Caching and Deduplication
- [ ] 21.3.2.1 Add optional caching map to context for expression IRIs
- [ ] 21.3.2.2 Implement `get_or_create_iri(cache, key, generator)` pattern
- [ ] 21.3.2.3 Document when caching is beneficial (shared sub-expressions)
- [ ] 21.3.2.4 Add helper for generating stable IRIs from AST hash (future optimization)

**Section 21.3 Unit Tests:**
- [ ] Test expression_iri/2 generates correct IRI with base_iri option
- [ ] Test expression_iri/2 generates correct IRI with suffix option
- [ ] Test expression_iri/2 defaults to context.base_iri when no option
- [ ] Test fresh_iri/3 creates relative IRI from base
- [ ] Test expression IRIs are unique for different expressions
- [ ] Test expression IRIs are deterministic for same AST

## 21.4 Core Expression Builders

This section implements the core expression building functions for common AST patterns that will be reused across all phases.

### 21.4.1 Binary Operator Builder
- [ ] 21.4.1.1 Implement `build_binary_operator/5` for ops with left and right operands
- [ ] 21.4.1.2 Generate `expr_iri` as base expression
- [ ] 21.4.1.3 Generate `left_iri` and recursively build left operand
- [ ] 21.4.1.4 Generate `right_iri` and recursively build right operand
- [ ] 21.4.1.5 Create type triple: `expr_iri a OperatorType`
- [ ] 21.4.1.6 Create `operatorSymbol` triple with operator name
- [ ] 21.4.1.7 Create `hasLeftOperand` triple linking to `left_iri`
- [ ] 21.4.1.8 Create `hasRightOperand` triple linking to `right_iri`
- [ ] 21.4.1.9 Return combined triples from all expressions

### 21.4.2 Unary Operator Builder
- [ ] 21.4.2.1 Implement `build_unary_operator/5` for ops with single operand
- [ ] 21.4.2.2 Generate `expr_iri` as base expression
- [ ] 21.4.2.3 Generate `operand_iri` and recursively build operand
- [ ] 21.4.2.4 Create type triple: `expr_iri a OperatorType`
- [ ] 21.4.2.5 Create `operatorSymbol` triple with operator name
- [ ] 21.4.2.6 Create `hasOperand` triple linking to `operand_iri`
- [ ] 21.4.2.7 Return combined triples

### 21.4.3 Variable and Reference Builders
- [ ] 21.4.3.1 Implement `build_variable/3` for `{name, _, context}` pattern
- [ ] 21.4.3.2 Create `Variable` type triple
- [ ] 21.4.3.3 Create `name` triple with variable name as string
- [ ] 21.4.3.4 Implement `build_wildcard/3` for `{:_}` pattern
- [ ] 21.4.3.5 Create `WildcardPattern` type triple
- [ ] 21.4.3.6 Implement `build_atom_literal/3` for atom values
- [ ] 21.4.3.7 Create `AtomLiteral` type triple
- [ ] 21.4.3.8 Create `atomValue` triple with atom name as string

### 21.4.4 Literal Builder
- [ ] 21.4.4.1 Implement `build_literal/5` for typed literal values
- [ ] 21.4.4.2 Handle integers with `Core.IntegerLiteral` type and `integerValue` property
- [ ] 21.4.4.3 Handle floats with `Core.FloatLiteral` type and `floatValue` property
- [ ] 21.4.4.4 Handle strings with `Core.StringLiteral` type and `stringValue` property
- [ ] 21.4.4.5 Use appropriate XSD datatypes (`xsd:integer`, `xsd:double`, `xsd:string`)

**Section 21.4 Unit Tests:**
- [ ] Test build_binary_operator/5 for comparison operator with two literals
- [ ] Test build_binary_operator/5 for nested binary operators
- [ ] Test build_unary_operator/5 for not operator
- [ ] Test build_variable/3 creates correct triples
- [ ] Test build_wildcard/3 creates WildcardPattern
- [ ] Test build_atom_literal/3 handles true, false, nil
- [ ] Test build_atom_literal/3 handles custom atoms
- [ ] Test build_literal/5 handles integer literals
- [ ] Test build_literal/5 handles float literals
- [ ] Test build_literal/5 handles string literals

## 21.5 Context Propagation ✅ COMPLETE

This section updates the Context module to propagate the `include_expressions` configuration through the builder pipeline, with automatic project file detection.

### 21.5.1 Update Context Module ✅
- [x] 21.5.1.1 Ensure `Context` struct has `config` field holding `%Config{}`
- [x] 21.5.1.2 Verify `Context.new/2` accepts and stores config
- [x] 21.5.1.3 Add helper `Context.full_mode?/1` checking `config.include_expressions`
- [x] 21.5.1.4 Add helper `Context.full_mode_for_file?/2` checking both config and `project_file?/1`
- [x] 21.5.1.5 Add helper `Context.light_mode?/1` checking `!config.include_expressions`
- [x] 21.5.1.6 Document the helpers in `@moduledoc` with project vs dependency distinction

### 21.5.2 Update Existing Builders for ExpressionBuilder Access
- [ ] 21.5.2.1 Update `ControlFlowBuilder` to accept optional ExpressionBuilder
- [ ] 21.5.2.2 Update `ClauseBuilder` to accept optional ExpressionBuilder
- [ ] 21.5.2.3 Add `@spec` annotations noting ExpressionBuilder dependency
- [ ] 21.5.2.4 Document in module docs that expressions require `include_expressions: true`

**Section 21.5 Unit Tests:** ✅
- [x] Test Context.full_mode?/1 returns true when `include_expressions: true`
- [x] Test Context.full_mode?/1 returns false when `include_expressions: false`
- [x] Test Context.full_mode_for_file?/2 returns true for project file with config enabled
- [x] Test Context.full_mode_for_file?/2 returns false for project file with config disabled
- [x] Test Context.full_mode_for_file?/2 returns false for dependency file even with config enabled
- [x] Test Context.light_mode?/1 returns false when `include_expressions: true`
- [x] Test Context.light_mode?/1 returns true when `include_expressions: false`
- [ ] Test Context propagates config through nested builders

## 21.6 Helper Functions Module

This section creates helper functions for common patterns in expression building.

### 21.6.1 Triple Building Helpers
- [ ] 21.6.1.1 Add `type_triple/2` wrapping `Helpers.type_triple/2`
- [ ] 21.6.1.2 Add `datatype_property/4` wrapping `Helpers.datatype_property/4`
- [ ] 21.6.1.3 Add `object_property/3` wrapping `Helpers.object_property/3`
- [ ] 21.6.1.4 Add `blank_node/1` wrapping `Helpers.blank_node/1`

### 21.6.2 Expression Building Helpers
- [ ] 21.6.2.1 Implement `build_child_expressions/3` for building multiple child expressions
- [ ] 21.6.2.2 Implement `combine_triples/1` for flattening and deduplicating triple lists
- [ ] 21.6.2.3 Implement `maybe_build/3` for conditional expression building
- [ ] 21.6.2.4 Document helpers with `@doc` and examples

**Section 21.6 Unit Tests:**
- [ ] Test type_triple/2 creates correct RDF triple
- [ ] Test datatype_property/4 handles various XSD types
- [ ] Test object_property/3 creates object property triple
- [ ] Test blank_node/1 generates unique blank nodes
- [ ] Test build_child_expressions/3 handles list of expressions
- [ ] Test combine_triples/1 flattens nested lists
- [ ] Test combine_triples/1 removes duplicates
- [ ] Test maybe_build/3 builds when condition is true
- [ ] Test maybe_build/3 returns :skip when condition is false

## Phase 21 Integration Tests

- [ ] Test complete config flow: Config.new → merge → validate → use in Context
- [ ] Test ExpressionBuilder returns `:skip` in light mode for all expression types
- [ ] Test ExpressionBuilder builds expressions in full mode for comparison operators
- [ ] Test ExpressionBuilder builds expressions in full mode for logical operators
- [ ] Test nested binary operators create correct IRI hierarchy
- [ ] Test expression IRIs are queryable via SPARQL
- [ ] Test Context propagation from Config → Context → ExpressionBuilder
- [ ] Test Helper functions work correctly with real AST nodes
- [ ] Test light mode extraction produces same output as before (backward compat)
- [ ] Test full mode extraction includes expression triples where expected
- [ ] Test full mode applies to project files but not dependency files
- [ ] Test dependency files are always extracted in light mode regardless of config

**Integration Test Summary:**
- 12 integration tests covering config, ExpressionBuilder, Context propagation, helpers, and project vs dependency distinction
- Tests verify both light and full mode behavior
- Tests confirm backward compatibility with existing extractions
- Tests confirm dependencies are always light mode
- Test file: `test/elixir_ontologies/builders/expression_builder_test.exs`
