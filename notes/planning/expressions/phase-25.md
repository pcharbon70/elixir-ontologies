# Phase 25: Control Flow Expression Integration

This phase integrates the ExpressionBuilder into ControlFlowBuilder to extract full condition expressions, branch bodies, and clause patterns for if/unless/cond/case/with/receive expressions. This transforms the current boolean-flag approach into full AST representation while maintaining backward compatibility with light mode.

## 25.1 If/Unless Expression Integration

This section updates ControlFlowBuilder to extract full condition and branch expressions for if and unless expressions when `include_expressions: true`.

### 25.1.1 Update add_condition_triple for Full Mode
- [ ] 25.1.1.1 Modify `add_condition_triple/4` in ControlFlowBuilder to accept context
- [ ] 25.1.1.2 Check `context.config.include_expressions` flag
- [ ] 25.1.1.3 When `false`: use existing boolean flag behavior (light mode)
- [ ] 25.1.1.4 When `true`: call `ExpressionBuilder.build/3` for condition AST
- [ ] 25.1.1.5 Pass `base_iri: expr_iri, suffix: "condition"` to ExpressionBuilder
- [ ] 25.1.1.6 Handle `:skip` return (shouldn't happen in full mode)
- [ ] 25.1.1.7 For `{:ok, {condition_iri, triples}}`: add triples and link via `hasCondition`
- [ ] 25.1.1.8 Preserve backward compatibility: light mode unchanged

### 25.1.2 Extract Branch Bodies for If/Unless
- [ ] 25.1.2.1 Update `add_branch_triples/4` to accept context parameter
- [ ] 25.1.2.2 For then branch: extract body expression when full mode
- [ ] 25.1.2.3 For else branch: extract body expression when full mode
- [ ] 25.1.2.4 Create child IRIs: `{if_iri}/then` and `{if_iri}/else`
- [ ] 25.1.2.5 Call `ExpressionBuilder.build/3` for branch body AST
- [ ] 25.1.2.6 Create `hasThenBranch` or `hasElseBranch` object property
- [ ] 25.1.2.7 In light mode: continue using boolean flags
- [ ] 25.1.2.8 Handle empty do blocks and single-expression bodies

**Section 25.1 Unit Tests:**
- [ ] Test if condition extraction in light mode (boolean flag)
- [ ] Test if condition extraction in full mode (expression tree)
- [ ] Test if condition extraction handles complex conditions
- [ ] Test if then branch extraction in full mode
- [ ] Test if else branch extraction in full mode
- [ ] Test unless condition extraction in full mode
- [ ] Test unless branch extraction in full mode
- [ ] Test if/unless extraction preserves backward compatibility

## 25.2 Cond Expression Integration

This section updates cond expression extraction to include full condition expressions for each clause.

### 25.2.1 Update Cond Clause Extraction
- [ ] 25.2.1.1 Identify cond clauses in `add_cond_clause_triples/4`
- [ ] 25.2.1.2 When `include_expressions: true`: extract each clause separately
- [ ] 25.2.1.3 Create clause IRIs: `{cond_iri}/clause/{index}`
- [ ] 25.2.1.4 Extract condition expression for each clause via ExpressionBuilder
- [ ] 25.2.1.5 Create `hasCondition` object property for each clause
- [ ] 25.2.1.6 Extract body expression for each clause via ExpressionBuilder
- [ ] 25.2.1.7 Create `hasThenBranch` or `hasBody` property
- [ ] 25.2.1.8 In light mode: use existing boolean flag approach
- [ ] 25.2.1.9 Handle final catch-all clause (condition: `true`)

**Section 25.2 Unit Tests:**
- [ ] Test cond clause extraction in light mode
- [ ] Test cond clause extraction in full mode
- [ ] Test cond clause extraction captures condition expression
- [ ] Test cond clause extraction captures body expression
- [ ] Test cond clause extraction handles multiple clauses
- [ ] Test cond clause extraction handles catch-all clause
- [ ] Test cond clause extraction preserves clause order

## 25.3 Case Expression Integration

This section updates case expression extraction to include the subject expression, full clause patterns, guard expressions, and clause bodies.

### 25.3.1 Extract Case Subject Expression
- [ ] 25.3.1.1 Update `build_case/3` to extract subject expression when full mode
- [ ] 25.3.1.2 Match subject AST from `CaseExpression` struct
- [ ] 25.3.1.3 Create `hasExpression` property for case subject
- [ ] 25.3.1.4 Call `ExpressionBuilder.build/3` for subject AST
- [ ] 25.3.1.5 Generate child IRI: `{case_iri}/subject`
- [ ] 25.3.1.6 Link via `hasExpression` object property

### 25.3.2 Extract Case Clauses with Patterns and Guards
- [ ] 25.3.2.1 Update `add_case_clause_triples/4` to accept context
- [ ] 25.3.2.2 For each clause: create clause IRI: `{case_iri}/clause/{index}`
- [ ] 25.3.2.3 Extract pattern via `ExpressionBuilder.build_pattern/3`
- [ ] 25.3.2.4 Link pattern via `hasPattern` property
- [ ] 25.3.2.5 Extract guard expression if present (via ExpressionBuilder)
- [ ] 25.3.2.6 Link guard via `hasGuard` property
- [ ] 25.3.2.7 Extract body expression for each clause
- [ ] 25.3.2.8 Link body via `hasBody` or `hasThenBranch` property
- [ ] 25.3.2.9 In light mode: use existing boolean flag approach

**Section 25.3 Unit Tests:**
- [ ] Test case subject expression extraction in full mode
- [ ] Test case clause pattern extraction in full mode
- [ ] Test case clause guard extraction in full mode
- [ ] Test case clause body extraction in full mode
- [ ] Test case extraction with multiple clauses
- [ ] Test case extraction with guarded clauses
- [ ] Test case extraction preserves clause order

## 25.4 With Expression Integration

This section updates with expression extraction to include match patterns, optional else clauses, and body expressions.

### 25.4.1 Extract With Clause Patterns
- [ ] 25.4.1.1 Update `add_with_clause_triples/4` for full mode
- [ ] 25.4.1.2 For each with clause: create clause IRI: `{with_iri}/clause/{index}`
- [ ] 25.4.1.3 Extract pattern from match clause via ExpressionBuilder
- [ ] 25.4.1.4 Extract expression from right side of match
- [ ] 25.4.1.5 Link pattern via `hasPattern` property
- [ ] 25.4.1.6 Link expression via `hasExpression` property
- [ ] 25.4.1.7 For `:match` type clauses: use pattern extraction
- [ ] 25.4.1.8 For `:else` type clauses: extract as expression

### 25.4.2 Extract With Body and Else
- [ ] 25.4.2.1 Extract with body expression (do block)
- [ ] 25.4.2.2 Create body IRI: `{with_iri}/body`
- [ ] 25.4.2.3 Call `ExpressionBuilder.build/3` for body AST
- [ ] 25.4.2.4 Link via `hasBody` property
- [ ] 25.4.2.5 Extract else clauses if present
- [ ] 25.4.2.6 For else: create `hasElseClause` linking to else IRI
- [ ] 25.4.2.7 In light mode: use existing boolean flag approach

**Section 25.4 Unit Tests:**
- [ ] Test with clause pattern extraction in full mode
- [ ] Test with clause expression extraction in full mode
- [ ] Test with body extraction in full mode
- [ ] Test with else clause extraction in full mode
- [ ] Test with extraction for multiple clauses
- [ ] Test with extraction handles nested matches

## 25.5 Receive Expression Integration

This section updates receive expression extraction to include message patterns, timeout expressions, after clauses, and body expressions.

### 25.5.1 Extract Receive Message Patterns
- [ ] 25.5.1.1 Update `add_receive_clause_triples/4` for full mode
- [ ] 25.5.1.2 For each message clause: create clause IRI
- [ ] 25.5.1.3 Extract message pattern via ExpressionBuilder pattern builder
- [ ] 25.5.1.4 Link pattern via `hasPattern` property
- [ ] 25.5.1.5 Extract guard expression if present
- [ ] 25.5.1.6 Link guard via `hasGuard` property
- [ ] 25.5.1.7 Extract body expression for message handler
- [ ] 25.5.1.8 Link body via `hasBody` property

### 25.5.2 Extract Receive Timeout and After
- [ ] 25.5.2.1 Extract timeout expression if present (not just integer)
- [ ] 25.5.2.2 Create timeout IRI: `{receive_iri}/timeout`
- [ ] 25.5.2.3 Call `ExpressionBuilder.build/3` for timeout AST
- [ ] 25.5.2.4 Link via `hasTimeout` property
- [ ] 25.5.2.5 Extract after block if present
- [ ] 25.5.2.6 Create after IRI: `{receive_iri}/after`
- [ ] 25.5.2.7 Extract after block expression via ExpressionBuilder
- [ ] 25.5.2.8 Link via `hasAfterClause` property
- [ ] 25.5.2.9 In light mode: use existing boolean flags

**Section 25.5 Unit Tests:**
- [ ] Test receive clause pattern extraction in full mode
- [ ] Test receive clause guard extraction in full mode
- [ ] Test receive clause body extraction in full mode
- [ ] Test receive timeout expression extraction
- [ ] Test receive after block extraction
- [ ] Test receive extraction for do..end block
- [ ] Test receive extraction handles multiple clauses

## 25.6 Try Expression Integration

This section implements extraction for try/rescue/catch/after expressions with full pattern matching for exceptions.

### 25.6.1 Try Expression Structure
- [ ] 25.6.1.1 Implement `build_try/3` in ControlFlowBuilder (new)
- [ ] 25.6.1.2 Match `try...rescue...catch...after` AST
- [ ] 25.6.1.3 Extract try body expression
- [ ] 25.6.1.4 Extract rescue clauses with exception patterns
- [ ] 25.6.1.5 Extract catch clauses with exception patterns
- [ ] 25.6.1.6 Extract after block if present
- [ ] 25.6.1.7 Create type triple: `expr_iri a Core.TryExpression`
- [ ] 25.6.1.8 Support simple try: `try do expr end`

### 25.6.2 Rescue and Catch Pattern Extraction
- [ ] 25.6.2.1 For rescue clauses: extract exception pattern
- [ ] 25.6.2.2 Match exception patterns: `%Error{}`, `%Error{msg}`, etc.
- [ ] 25.6.2.3 Use pattern extraction from ExpressionBuilder
- [ ] 25.6.2.4 Link via `hasRescueClause` property
- [ ] 25.6.2.5 For catch clauses: extract catch pattern
- [ ] 25.6.2.6 Match catch patterns: `:error`, `e`, `%type{}`
- [ ] 25.6.2.7 Link via `hasCatchClause` property
- [ ] 25.6.2.8 Extract body expressions for each rescue/catch clause

### 25.6.3 After Block Extraction
- [ ] 25.6.3.1 Extract after block expression if present
- [ ] 25.6.3.2 Create after IRI: `{try_iri}/after`
- [ ] 25.6.3.3 Call `ExpressionBuilder.build/3` for after AST
- [ ] 25.6.3.4 Link via `hasAfterClause` object property

**Section 25.6 Unit Tests:**
- [ ] Test try expression extraction for try body
- [ ] Test try expression rescue pattern extraction
- [ ] Test try expression catch pattern extraction
- [ ] Test try expression after block extraction
- [ ] Test try expression extraction handles multiple rescue clauses
- [ ] Test try expression extraction handles wildcard rescue
- [ ] Test try expression extraction for simple try

## 25.7 Raise and Throw Expression Integration

This section implements extraction for raise and throw expressions.

### 25.7.1 Raise Expression Extraction
- [ ] 25.7.1.1 Implement `build_raise/3` in ControlFlowBuilder
- [ ] 25.7.1.2 Match `raise/1`, `raise/2`, `raise/3` AST
- [ ] 25.7.1.3 Extract exception argument expression
- [ ] 25.7.1.4 Create type triple: `expr_iri a Core.RaiseExpression`
- [ ] 25.7.1.5 Link argument via `hasArgument` property
- [ ] 25.7.1.6 Handle `raise message` vs `raise Exception, message`

### 25.7.2 Throw Expression Extraction
- [ ] 25.7.2.1 Implement `build_throw/3` in ControlFlowBuilder
- [ ] 25.7.2.2 Match `throw/1` AST
- [ ] 25.7.2.3 Extract thrown value expression
- [ ] 25.7.2.4 Create type triple: `expr_iri a Core.ThrowExpression`
- [ ] 25.7.2.5 Link value via `hasValue` property

**Section 25.7 Unit Tests:**
- [ ] Test raise expression extraction with message
- [ ] Test raise expression extraction with exception and message
- [ ] Test raise expression extraction with reraise
- [ ] Test throw expression extraction for value
- [ ] Test raise/throw extraction handles complex expressions

## Phase 25 Integration Tests

- [ ] Test complete control flow extraction: if/unless/cond/case/with/receive
- [ ] Test control flow extraction in light mode (backward compat)
- [ ] Test control flow extraction in full mode (expressions)
- [ ] Test nested control flow (if inside case, etc.)
- [ ] Test control flow with complex condition expressions
- [ ] Test control flow with complex branch bodies
- [ ] Test SPARQL queries find control flow by type
- [ ] Test SPARQL queries navigate condition expressions
- [ ] Test SPARQL queries navigate branch bodies
- [ ] Test SPARQL queries find guards within clauses
- [ ] Test all control flow types produce valid RDF
- [ ] Test expression tree structure is queryable

**Integration Test Summary:**
- 12 integration tests covering all control flow types
- Tests verify light/full mode behavior and SPARQL queryability
- Test file: `test/elixir_ontologies/builders/control_flow_full_test.exs`
