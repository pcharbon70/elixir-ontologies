# Phase 30: Try, Raise, Throw, and Exception Handling Expressions

This phase implements extraction for exception handling constructs including try/rescue/catch/after blocks, raise expressions, and throw expressions. Exception handling is critical for understanding error propagation and recovery strategies in Elixir code.

## 30.1 Try Expression Structure

This section implements the basic structure for try expressions including the try body and optional rescue, catch, and after blocks.

### 30.1.1 Try Expression Detection
- [ ] 30.1.1.1 Implement `detect_try/1` helper in ExpressionBuilder
- [ ] 30.1.1.2 Match `:try` AST pattern with 3-tuple: `{:try, _, [blocks]}`
- [ ] 30.1.1.3 Match `:try` AST pattern with keyword list format
- [ ] 30.1.1.4 Identify try body (required)
- [ ] 30.1.1.5 Identify rescue clauses (optional)
- [ ] 30.1.1.6 Identify catch clauses (optional)
- [ ] 30.1.1.7 Identify after block (optional)
- [ ] 30.1.1.8 Identify else block (optional, Elixir 1.11+)

### 30.1.2 Try Expression Builder Implementation
- [ ] 30.1.2.1 Implement `build_try/4` in ExpressionBuilder
- [ ] 30.1.2.2 Create type triple: `expr_iri a Core.TryExpression`
- [ ] 30.1.2.3 Extract try body expression
- [ ] 30.1.2.4 Generate body IRI: `{try_iri}/body`
- [ ] 30.1.2.5 Link via `hasTryBody` object property
- [ ] 30.1.2.6 Handle empty try body
- [ ] 30.1.2.7 Handle try body with multiple expressions

**Section 30.1 Unit Tests:**
- [ ] Test try expression detection for simple try
- [ ] Test try expression detection for try with rescue
- [ ] Test try expression detection for try with catch
- [ ] Test try expression detection for try with after
- [ ] Test try expression detection for complete try
- [ ] Test try expression builder creates correct structure

## 30.2 Rescue Clause Expression Extraction

This section implements extraction for rescue clauses with exception pattern matching.

### 30.2.1 Rescue Clause Detection
- [ ] 30.2.1.1 Match rescue clauses in try AST
- [ ] 30.2.1.2 Identify rescue block: `rescue: [...]`
- [ ] 30.2.1.3 Extract rescue clause patterns
- [ ] 30.2.1.4 Match clause format: `{:->, _, [[pattern], body]}`
- [ ] 30.2.1.5 Handle wildcard rescue: `rescue: _`
- [ ] 30.2.1.6 Handle variable rescue: `rescue: e`
- [ ] 30.2.1.7 Handle typed rescue: `rescue: %Error{} -> ...`

### 30.2.2 Rescue Pattern Extraction
- [ ] 30.2.2.1 For each rescue clause: create clause IRI: `{try_iri}/rescue/{index}`
- [ ] 30.2.2.2 Extract exception pattern via ExpressionBuilder pattern builder
- [ ] 30.2.2.3 Match struct patterns: `%RuntimeError{}`, `%ArgumentError{message: msg}`
- [ ] 30.2.2.4 Match variable patterns: `e`, `error`
- [ ] 30.2.2.5 Match wildcard patterns: `_`
- [ ] 30.2.2.6 Link pattern via `hasExceptionPattern` property
- [ ] 30.2.2.7 Link exception type via `refersToExceptionType` property

### 30.2.3 Rescue Body Extraction
- [ ] 30.2.3.1 Extract rescue body expression for each clause
- [ ] 30.2.3.2 Generate body IRI: `{rescue_clause_iri}/body`
- [ ] 30.2.3.3 Link via `hasRescueBody` property
- [ ] 30.2.3.4 Handle rescue body with multiple expressions
- [ ] 30.2.3.5 Link rescue clauses via `hasRescueClause` property (ordered)

**Section 30.2 Unit Tests:**
- [ ] Test rescue clause extraction for wildcard rescue
- [ ] Test rescue clause extraction for variable rescue
- [ ] Test rescue clause extraction for typed rescue
- [ ] Test rescue clause extraction captures exception pattern
- [ ] Test rescue clause extraction captures rescue body
- [ ] Test rescue clause extraction handles multiple rescue clauses
- [ ] Test rescue clause extraction preserves clause order

## 30.3 Catch Clause Expression Extraction

This section implements extraction for catch clauses which catch thrown values, errors, exits, and throws.

### 30.3.1 Catch Clause Detection
- [ ] 30.3.1.1 Match catch clauses in try AST
- [ ] 30.3.1.2 Identify catch block: `catch: [...]`
- [ ] 30.3.1.3 Extract catch clause patterns
- [ ] 30.3.1.4 Match clause format: `{:->, _, [[pattern], body]}`
- [ ] 30.3.1.5 Handle catch types: `:throw`, `:error`, `:exit`
- [ ] 30.3.1.6 Handle typed catch: `catch: :throw, x -> ...`
- [ ] 30.3.1.7 Handle wildcard catch: `catch: _ -> ...`

### 30.3.2 Catch Pattern Extraction
- [ ] 30.3.2.1 For each catch clause: create clause IRI: `{try_iri}/catch/{index}`
- [ ] 30.3.2.2 Extract catch pattern via ExpressionBuilder pattern builder
- [ ] 30.3.2.3 Match catch type atom: `:throw`, `:error`, `:exit`
- [ ] 30.3.2.4 Extract caught value pattern
- [ ] 30.3.2.5 Link catch type via `hasCatchType` property
- [ ] 30.3.2.6 Link pattern via `hasCatchPattern` property
- [ ] 30.3.2.7 Handle implicit catch type (catches all)

### 30.3.3 Catch Body Extraction
- [ ] 30.3.3.1 Extract catch body expression for each clause
- [ ] 30.3.3.2 Generate body IRI: `{catch_clause_iri}/body`
- [ ] 30.3.3.3 Link via `hasCatchBody` property
- [ ] 30.3.3.4 Handle catch body with multiple expressions
- [ ] 30.3.3.5 Link catch clauses via `hasCatchClause` property (ordered)

**Section 30.3 Unit Tests:**
- [ ] Test catch clause extraction for typed catch
- [ ] Test catch clause extraction for wildcard catch
- [ ] 30.3.3.1 Test catch clause extraction captures catch type
- [ ] 30.3.3.1 Test catch clause extraction captures catch pattern
- [ ] 30.3.3.1 Test catch clause extraction captures catch body
- [ ] 30.3.3.1 Test catch clause extraction handles multiple catch clauses
- [ ] 30.3.3.1 Test catch clause extraction distinguishes throw/error/exit

## 30.4 After Block Expression Extraction

This section implements extraction for after blocks which always execute regardless of whether an exception occurred.

### 30.4.1 After Block Detection
- [ ] 30.4.1.1 Match after block in try AST
- [ ] 30.4.1.2 Identify `after: ...` keyword in try expression
- [ ] 30.4.1.3 Extract after block AST
- [ ] 30.4.1.4 Handle empty after block
- [ ] 30.4.1.5 Handle after block with expressions

### 30.4.2 After Block Builder
- [ ] 30.4.2.1 Implement `build_after_block/4` in ExpressionBuilder
- [ ] 30.4.2.2 Generate after IRI: `{try_iri}/after`
- [ ] 30.4.2.3 Extract after block expression via ExpressionBuilder
- [ ] 30.4.2.4 Link via `hasAfterClause` object property
- [ ] 30.4.2.5 Handle after block with multiple expressions
- [ ] 30.4.2.6 Document that after block always executes

**Section 30.4 Unit Tests:**
- [ ] Test after block extraction for empty after
- [ ] Test after block extraction for single expression
- [ ] Test after block extraction for multiple expressions
- [ ] Test after block extraction creates correct structure

## 30.5 Else Block Expression Extraction

This section implements extraction for else blocks (Elixir 1.11+) which execute when no exception occurs.

### 30.5.1 Else Block Detection
- [ ] 30.5.1.1 Match else block in try AST
- [ ] 30.5.1.2 Identify `else: ...` keyword in try expression
- [ ] 30.5.1.3 Extract else block AST
- [ ] 30.5.1.4 Handle empty else block
- [ ] 30.5.1.5 Handle else block with expressions

### 30.5.2 Else Block Builder
- [ ] 30.5.2.1 Implement `build_else_block/4` in ExpressionBuilder
- [ ] 30.5.2.2 Generate else IRI: `{try_iri}/else`
- [ ] 30.5.2.3 Extract else block expression via ExpressionBuilder
- [ ] 30.5.2.4 Link via `hasElseClause` object property
- [ ] 30.5.2.5 Handle else block with multiple expressions
- [ ] 30.5.2.6 Document that else executes only if no exception

**Section 30.5 Unit Tests:**
- [ ] Test else block extraction for empty else
- [ ] Test else block extraction for single expression
- [ ] Test else block extraction for multiple expressions
- [ ] Test else block extraction creates correct structure

## 30.6 Raise Expression Extraction

This section implements extraction for raise expressions which explicitly raise exceptions.

### 30.6.1 Raise Expression Detection
- [ ] 30.6.1.1 Implement `detect_raise/1` helper in ExpressionBuilder
- [ ] 30.6.1.2 Match `raise/1` AST: `{:raise, _, [args]}`
- [ ] 30.6.1.3 Match `raise/2` AST: `{:raise, _, [exception, args]}` (rare)
- [ ] 30.6.1.4 Match `raise/3` AST with keyword args
- [ ] 30.6.1.5 Identify raise message: `raise "message"`
- [ ] 30.6.1.6 Identify raise exception: `raise RuntimeError, "message"`
- [ ] 30.6.1.7 Identify raise with attributes: `raise ArgumentError, message: "msg"`

### 30.6.2 Raise Expression Builder
- [ ] 30.6.2.1 Implement `build_raise/4` in ExpressionBuilder
- [ ] 30.6.2.2 Create type triple: `expr_iri a Core.RaiseExpression`
- [ ] 30.6.2.3 Extract exception type if specified
- [ ] 30.6.2.4 Create `refersToExceptionType` property
- [ ] 30.6.2.5 Extract message expression
- [ ] 30.6.2.6 Link via `hasMessage` property
- [ ] 30.6.2.7 Extract additional arguments
- [ ] 30.6.2.8 Link via `hasArgument` property
- [ ] 30.6.2.9 Handle simple raise: `raise "oops"`

**Section 30.6 Unit Tests:**
- [ ] Test raise expression extraction for message only
- [ ] Test raise expression extraction for exception with message
- [ ] Test raise expression extraction for exception with attributes
- [ ] Test raise expression extraction captures message
- [ ] Test raise expression extraction captures exception type
- [ ] Test raise expression extraction handles complex arguments

## 30.7 Throw Expression Extraction

This section implements extraction for throw expressions which throw values for non-local returns.

### 30.7.1 Throw Expression Detection
- [ ] 30.7.1.1 Implement `detect_throw/1` helper in ExpressionBuilder
- [ ] 30.7.1.2 Match `throw/1` AST: `{:throw, _, [value]}`
- [ ] 30.7.1.3 Identify thrown value expression
- [ ] 30.7.1.4 Handle throw with literal: `throw :error`
- [ ] 30.7.1.5 Handle throw with variable: `throw value`
- [ ] 30.7.1.6 Handle throw with complex expression

### 30.7.2 Throw Expression Builder
- [ ] 30.7.2.1 Implement `build_throw/4` in ExpressionBuilder
- [ ] 30.7.2.2 Create type triple: `expr_iri a Core.ThrowExpression`
- [ ] 30.7.2.3 Extract thrown value expression
- [ ] 30.7.2.4 Link via `hasThrownValue` property
- [ ] 30.7.2.5 Handle literal thrown values
- [ ] 30.7.2.6 Handle variable thrown values
- [ ] 30.7.2.7 Handle complex thrown expressions

**Section 30.7 Unit Tests:**
- [ ] Test throw expression extraction for literal value
- [ ] Test throw expression extraction for variable value
- [ ] Test throw expression extraction for complex expression
- [ ] Test throw expression extraction captures thrown value

## 30.8 Exception Handling Nesting and Complexity

This section ensures that exception handling constructs are correctly extracted when nested and in complex scenarios.

### 30.8.1 Nested Try Expression Support
- [ ] 30.8.1.1 Test nested try expressions: `try do try do inner() end rescue end`
- [ ] 30.8.1.2 Test try within rescue clause
- [ ] 30.8.1.3 Test try within catch clause
- [ ] 30.8.1.4 Test try within after block
- [ ] 30.8.1.5 Verify nested try IRIs follow hierarchy
- [ ] 30.8.1.6 Ensure parent-child relationships are preserved

### 30.8.2 Complex Exception Handling Scenarios
- [ ] 30.8.2.1 Test try with all components: rescue, catch, after, else
- [ ] 30.8.2.2 Test try with multiple rescue clauses
- [ ] 30.8.2.3 Test try with multiple catch clauses
- [ ] 30.8.2.4 Test try with complex exception patterns
- [ ] 30.8.2.5 Test try with side effects in after block
- [ ] 30.8.2.6 Verify extraction preserves exception handling semantics

**Section 30.8 Unit Tests:**
- [ ] Test nested try expression extraction
- [ ] Test try with all components
- [ ] Test try with multiple rescue/catch clauses
- [ ] Test try within other constructs (if, case, etc.)
- [ ] Test try extraction preserves semantics

## Phase 30 Integration Tests

- [ ] Test complete exception handling extraction: try, rescue, catch, after, else
- [ ] Test try expression extraction with all clause types
- [ ] Test rescue clause extraction for all exception types
- [ ] Test catch clause extraction for all catch types
- [ ] Test raise expression extraction for all raise forms
- [ ] Test throw expression extraction
- [ ] Test nested exception handling extraction
- [ ] Test exception handling extraction in light mode (backward compat)
- [ ] Test exception handling extraction in full mode (full expression tree)
- [ ] Test SPARQL queries find exception handling by type
- [ ] Test SPARQL queries navigate exception handling clauses
- [ ] Test SPARQL queries find exception patterns
- [ ] Test exception handling extraction integrates with ExpressionBuilder

**Integration Test Summary:**
- 13 integration tests covering all exception handling scenarios
- Tests verify exception handling extraction completeness and SPARQL queryability
- Tests confirm both light and full mode behavior
- Test file: `test/elixir_ontologies/builders/exception_handling_test.exs`

## Final Phase Completion

After completing Phase 30, the expression extraction implementation will be complete:

**Coverage Summary:**
- All 270+ expression classes from elixir-core.ttl ontology
- All literal types (atoms, integers, floats, strings, binaries, lists, tuples, maps, sigils, ranges)
- All operator types (arithmetic, comparison, logical, pipe, match, capture, string concat, list, in)
- All pattern types (literals, variables, wildcards, pins, tuples, lists, maps, structs, binaries, as-patterns)
- All control flow types (if/unless, cond, case, with, receive)
- All function guard constructs (simple guards, compound guards, guard functions)
- All block types (do blocks, fn blocks, begin blocks)
- All comprehension types (list comprehensions, bitstring comprehensions)
- All call types (remote calls, local calls, anonymous function calls, captures)
- All exception handling types (try, rescue, catch, after, raise, throw)

**Success Criteria:**
- Light mode: No regression in performance or storage
- Full mode: Complete, queryable AST representation
- Test coverage: 100% of new code has unit and integration tests
- Documentation: Full API docs with examples
- SPARQL queryability: All expression types are navigable via SPARQL

**Next Steps After Phase 30:**
- Documentation updates for full mode configuration
- Performance optimization for large-scale full mode extraction
- SPARQL query examples for common expression analysis tasks
- Optional: Variable scope extraction (future enhancement)
- Optional: Data flow analysis (future enhancement)
