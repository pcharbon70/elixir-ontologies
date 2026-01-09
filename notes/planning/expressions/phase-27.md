# Phase 27: Function Bodies and Block Expressions

This phase implements extraction for block expressions including do blocks, anonymous function blocks, and general expression sequences. Blocks are fundamental to Elixir's control flow and appear in function bodies, do expressions, anonymous functions, and various compound expressions.

## 27.1 Block Detection and Structure

This section implements detection of different block types in the AST and establishes the structure for block expression extraction.

### 27.1.1 Block Type Detection
- [ ] 27.1.1.1 Implement `detect_block_type/1` helper in ExpressionBuilder
- [ ] 27.1.1.2 Return `:do_block` for `:do` / `:end` delimited blocks
- [ ] 27.1.1.3 Return `:fn_block` for `:fn` anonymous functions
- [ ] 27.1.1.4 Return `:block` for `:block` AST nodes (begin..end blocks)
- [ ] 27.1.1.5 Return `:single_expr` for single expressions (not a block)
- [ ] 27.1.1.6 Differ between explicit blocks vs implicit blocks

### 27.1.2 Block Structure Analysis
- [ ] 27.1.2.1 Match block AST: `{:__block__, _, [expressions]}`
- [ ] 27.1.2.2 Match fn block: `{:fn, _, [{:->, _, [[params], body]}]}`
- [ ] 27.1.2.3 Extract block boundaries (do..end, fn..end)
- [ ] 27.1.2.4 Identify block metadata (line numbers, context)
- [ ] 27.1.2.5 Detect empty blocks vs blocks with expressions

**Section 27.1 Unit Tests:**
- [ ] Test block type detection for do blocks
- [ ] Test block type detection for fn blocks
- [ ] Test block type detection for begin blocks
- [ ] Test block type detection for single expressions
- [ ] Test block structure analysis captures metadata
- [ ] Test empty block detection

## 27.2 Do Block Expression Extraction

This section implements extraction for do blocks used in function definitions and various control flow constructs.

### 27.2.1 Do Block Builder Implementation
- [ ] 27.2.1.1 Implement `build_do_block/4` in ExpressionBuilder
- [ ] 27.2.1.2 Match `{:__block__, _, expressions}` pattern
- [ ] 27.2.1.3 Create type triple: `expr_iri a Core.BlockExpression`
- [ ] 27.2.1.4 Create block type property: `core:blockType "doBlock"`
- [ ] 27.2.1.5 Generate child IRIs for each expression: `{block_iri}/expr/{index}`
- [ ] 27.2.1.6 Extract each expression in sequence recursively
- [ ] 27.2.1.7 Link expressions via `hasExpression` property (ordered)
- [ ] 27.2.1.8 Mark final expression as return value (last expression is returned)

### 27.2.2 Do Block Expression Ordering
- [ ] 27.2.2.1 Preserve expression order from source
- [ ] 27.2.2.2 Use RDF list or `rdf:Seq` for ordering
- [ ] 27.2.2.3 Add position index to each expression triple
- [ ] 27.2.2.4 Handle side-effect expressions (non-returning statements)
- [ ] 27.2.2.5 Mark return expression explicitly via `hasReturnExpression` property

**Section 27.2 Unit Tests:**
- [ ] Test do block extraction for single expression
- [ ] Test do block extraction for multiple expressions
- [ ] Test do block extraction preserves expression order
- [ ] Test do block extraction identifies return expression
- [ ] Test do block extraction handles empty blocks
- [ ] Test do block extraction handles nested blocks

## 27.3 Anonymous Function Block Extraction

This section implements extraction for anonymous function (fn) blocks including their parameter patterns and bodies.

### 27.3.1 Fn Block Builder Implementation
- [ ] 27.3.1.1 Implement `build_fn_block/4` in ExpressionBuilder
- [ ] 27.3.1.2 Match `{:fn, _, [{:->, _, [[params], body]}]}` single clause
- [ ] 27.3.1.3 Match `{:fn, _, [{:->, _, [[params], body]}, ...]}` multiple clauses
- [ ] 27.3.1.4 Create type triple: `expr_iri a Core.AnonymousFunction`
- [ ] 27.3.1.5 For each clause: create clause IRI: `{fn_iri}/clause/{index}`
- [ ] 27.3.1.6 Extract parameter patterns via `ExpressionBuilder.build_pattern/3`
- [ ] 27.3.1.7 Link parameters via `hasParameter` property
- [ ] 27.3.1.8 Extract clause body via `ExpressionBuilder.build/3`
- [ ] 27.3.1.9 Link body via `hasBody` property

### 27.3.2 Multi-Clause Anonymous Functions
- [ ] 27.3.2.1 Handle fn with multiple pattern-matching clauses
- [ ] 27.3.2.2 Create clause IRIs: `{fn_iri}/clause/{index}`
- [ ] 27.3.2.3 Extract each clause's parameters independently
- [ ] 27.3.2.4 Extract each clause's guard if present
- [ ] 27.3.2.5 Extract each clause's body
- [ ] 27.3.2.6 Link clauses via `hasClause` property (ordered)
- [ ] 27.3.2.7 Preserve clause order (first match wins)

**Section 27.3 Unit Tests:**
- [ ] Test fn block extraction for single clause
- [ ] Test fn block extraction for multiple clauses
- [ ] Test fn block extraction with parameters
- [ ] Test fn block extraction with guards
- [ ] Test fn block extraction with multiple body expressions
- [ ] Test fn block extraction preserves clause order
- [ ] Test fn block extraction handles pattern parameters

## 27.4 Begin Block Expression Extraction

This section implements extraction for begin..end blocks which create explicit expression sequences.

### 27.4.1 Begin Block Builder Implementation
- [ ] 27.4.1.1 Implement `build_begin_block/4` in ExpressionBuilder
- [ ] 27.4.1.2 Match `{:begin, _, [expressions]}` pattern
- [ ] 27.4.1.3 Create type triple: `expr_iri a Core.BlockExpression`
- [ ] 27.4.1.4 Create block type property: `core:blockType "beginBlock"`
- [ ] 27.4.1.5 Extract each expression in sequence recursively
- [ ] 27.4.1.6 Link via `hasExpression` property (ordered)
- [ ] 27.4.1.7 Mark final expression as return value

### 27.4.2 Begin Block vs Do Block
- [ ] 27.4.2.1 Distinguish begin blocks from do blocks via type property
- [ ] 27.4.2.2 Document semantic differences (evaluates expressions, returns last)
- [ ] 27.4.2.3 Note: begin is semantically equivalent to parentheses
- [ ] 27.4.2.4 Store both as BlockExpression but with different blockType

**Section 27.4 Unit Tests:**
- [ ] Test begin block extraction for single expression
- [ ] Test begin block extraction for multiple expressions
- [ ] Test begin block extraction is distinguished from do block
- [ ] Test begin block extraction preserves expression order
- [ ] Test begin block extraction identifies return expression

## 27.5 Expression Sequences and Side Effects

This section ensures that expression sequences properly handle side effects and control flow within blocks.

### 27.5.1 Side Effect Expression Tracking
- [ ] 27.5.1.1 Identify expressions with side effects (IO, state mutation)
- [ ] 27.5.1.2 Track side-effecting expressions within blocks
- [ ] 27.5.1.3 Optionally annotate side-effecting expressions
- [ ] 27.5.1.4 Preserve execution order for side effects
- [ ] 27.5.1.5 Note: Elixir evaluates expressions left-to-right

### 27.5.2 Early Return Detection
- [ ] 27.5.2.1 Detect explicit return expressions (rare in Elixir)
- [ ] 27.5.2.2 Detect throw expressions within blocks
- [ ] 27.5.2.3 Detect error-raising expressions within blocks
- [ ] 27.5.2.4 Document that last expression is implicit return value
- [ ] 27.5.2.5 Handle early exit expressions correctly

**Section 27.5 Unit Tests:**
- [ ] Test block extraction handles IO expressions
- [ ] Test block extraction preserves side-effect order
- [ ] Test block extraction handles throw expressions
- [ ] Test block extraction handles error-raising expressions
- [ ] Test block extraction correctly identifies implicit returns

## 27.6 Block Nesting and Scope

This section ensures that nested blocks and scope boundaries are correctly represented in the extracted RDF.

### 27.6.1 Nested Block Support
- [ ] 27.6.1.1 Test nested do blocks: `do do inner() end end`
- [ ] 27.6.1.2 Test fn within do blocks
- [ ] 27.6.1.3 Test begin within do blocks
- [ ] 27.6.1.4 Test blocks within control flow (if, case, etc.)
- [ ] 27.6.1.5 Verify nested block IRIs follow hierarchy
- [ ] 27.6.1.6 Ensure parent-child relationships are preserved

### 27.6.2 Variable Scope Boundaries
- [ ] 27.6.2.1 Note: Variable scope is not yet extracted (future phase)
- [ ] 27.6.2.2 Document that blocks create scope boundaries
- [ ] 27.6.2.3 Annotate block IRIs with scope metadata
- [ ] 27.6.2.4 Prepare for future scope extraction (variables, bindings)
- [ ] 27.6.2.5 Track block nesting depth for scope analysis

**Section 27.6 Unit Tests:**
- [ ] Test nested do block extraction
- [ ] Test nested fn block extraction
- [ ] Test mixed nesting (do within fn, etc.)
- [ ] Test block IRI hierarchy follows nesting
- [ ] Test block metadata captures nesting information

## Phase 27 Integration Tests

- [ ] Test complete block extraction: do blocks, fn blocks, begin blocks
- [ ] Test block extraction with multiple expressions
- [ ] Test block extraction preserves expression order
- [ ] Test block extraction identifies return expressions
- [ ] Test nested block extraction creates correct hierarchy
- [ ] Test block extraction in light mode (backward compat)
- [ ] Test block extraction in full mode (full expression tree)
- [ ] Test SPARQL queries find blocks by type
- [ ] Test SPARQL queries navigate block expressions
- [ ] Test SPARQL queries find return expressions
- [ ] Test block extraction integrates with function extraction
- [ ] Test block extraction handles real-world function bodies

**Integration Test Summary:**
- 12 integration tests covering all block types and scenarios
- Tests verify block extraction completeness and SPARQL queryability
- Tests confirm both light and full mode behavior
- Test file: `test/elixir_ontologies/builders/block_expression_test.exs`
