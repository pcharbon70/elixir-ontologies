# Phase 23: Operator Expression Extraction

This phase implements extraction for all operator types defined in the elixir-core.ttl ontology. Operators form the backbone of expression trees and include arithmetic, comparison, logical, pipe, match, capture, string concatenation, list, and in operators. Each operator type requires specific handling for operands, operator symbols, and associativity.

## 23.1 Arithmetic Operators

This section implements extraction for arithmetic operators: addition, subtraction, multiplication, division, and remainder.

### 23.1.1 Arithmetic Operator Detection
- [ ] 23.1.1.1 Implement `build_arithmetic/5` in ExpressionBuilder
- [ ] 23.1.1.2 Match `:+` for addition operator
- [ ] 23.1.1.3 Match `:-` for subtraction operator (when binary)
- [ ] 23.1.1.4 Match `:*` for multiplication operator
- [ ] 23.1.1.5 Match `:/` for division operator
- [ ] 23.1.1.6 Match `:div` for integer division
- [ ] 23.1.1.7 Match `:rem` for remainder/modulo operator
- [ ] 23.1.1.8 Distinguish unary minus from binary minus via AST structure

### 23.1.2 Arithmetic Operand Extraction
- [ ] 23.1.2.1 Extract left operand recursively for all binary arithmetic ops
- [ ] 23.1.2.2 Extract right operand recursively for all binary arithmetic ops
- [ ] 23.1.2.3 Generate child IRIs: `{expr_iri}/left` and `{expr_iri}/right`
- [ ] 23.1.2.4 Create type triple: `expr_iri a Core.ArithmeticOperator`
- [ ] 23.1.2.5 Create `operatorSymbol` triple with operator name
- [ ] 23.1.2.6 Create `hasLeftOperand` triple linking to left child IRI
- [ ] 23.1.2.7 Create `hasRightOperand` triple linking to right child IRI
- [ ] 23.1.2.8 Combine all triples: expression + left + right children

### 23.1.3 Unary Arithmetic Operators
- [ ] 23.1.3.1 Match unary minus: `{:-, _, [operand]}`
- [ ] 23.1.3.2 Match unary plus: {:+, _, [operand]}` (if present)
- [ ] 23.1.3.3 Create type triple: `expr_iri a Core.ArithmeticOperator`
- [ ] 23.1.3.4 Create `operatorSymbol` triple with "+" or "-"
- [ ] 23.1.3.5 Create `hasOperand` triple linking to child IRI
- [ ] 23.1.3.6 Extract child operand recursively

**Section 23.1 Unit Tests:**
- [ ] Test arithmetic operator extraction for addition
- [ ] Test arithmetic operator extraction for subtraction
- [ ] Test arithmetic operator extraction for multiplication
- [ ] Test arithmetic operator extraction for division
- [ ] Test arithmetic operator extraction for integer division
- [ ] Test arithmetic operator extraction for remainder
- [ ] Test arithmetic operator extraction for unary minus
- [ ] Test arithmetic operator extraction handles nested arithmetic
- [ ] Test arithmetic operator extraction preserves operator precedence via structure

## 23.2 Comparison Operators

This section implements extraction for comparison operators: equality, inequality, strict equality, strict inequality, and ordering comparisons.

### 23.2.1 Comparison Operator Detection
- [ ] 23.2.1.1 Implement `build_comparison/5` in ExpressionBuilder
- [ ] 23.2.1.2 Match `:==` for loose equality
- [ ] 23.2.1.3 Match `:!=` or `:!==` for inequality
- [ ] 23.2.1.4 Match `:===` for strict equality
- [ ] 23.2.1.5 Match `:<` for less than
- [ ] 23.2.1.6 Match `:>` for greater than
- [ ] 23.2.1.7 Match `:<=` for less than or equal
- [ ] 23.2.1.8 Match `:>=` for greater than or equal

### 23.2.2 Comparison Operand Extraction
- [ ] 23.2.2.1 Extract left operand recursively for all comparison ops
- [ ] 23.2.2.2 Extract right operand recursively for all comparison ops
- [ ] 23.2.2.3 Generate child IRIs: `{expr_iri}/left` and `{expr_iri}/right`
- [ ] 23.2.2.4 Create type triple: `expr_iri a Core.ComparisonOperator`
- [ ] 23.2.2.5 Create `operatorSymbol` triple with operator string
- [ ] 23.2.2.6 Create `hasLeftOperand` triple
- [ ] 23.2.2.7 Create `hasRightOperand` triple
- [ ] 23.2.2.8 Combine triples from expression and children

**Section 23.2 Unit Tests:**
- [ ] Test comparison operator extraction for equality
- [ ] Test comparison operator extraction for inequality
- [ ] Test comparison operator extraction for strict equality
- [ ] Test comparison operator extraction for less than
- [ ] Test comparison operator extraction for greater than
- [ ] Test comparison operator extraction for less than or equal
- [ ] Test comparison operator extraction for greater than or equal
- [ ] Test comparison operator extraction handles nested comparisons
- [ ] Test comparison operator extraction with literal and variable operands
- [ ] Test comparison operator extraction with complex sub-expressions

## 23.3 Logical Operators

This section implements extraction for logical operators: boolean and/or, short-circuit and/or, and not.

### 23.3.1 Logical Operator Detection
- [ ] 23.3.1.1 Implement `build_logical/5` in ExpressionBuilder
- [ ] 23.3.1.2 Match `:and` for boolean and
- [ ] 23.3.1.3 Match `:or` for boolean or
- [ ] 23.3.1.4 Match `:&&` for short-circuit and
- [ ] 23.3.1.5 Match `:||` for short-circuit or
- [ ] 23.3.1.6 Match `:!` for not/unary not
- [ ] 23.3.1.7 Match `:not` for boolean not (if used as expression)

### 23.3.2 Logical Operand Extraction
- [ ] 23.3.2.1 Extract left operand for binary logical operators (and/or/&&/||)
- [ ] 23.3.2.2 Extract right operand for binary logical operators
- [ ] 23.3.2.3 Extract single operand for unary operators (!/not)
- [ ] 23.3.2.4 Create type triple: `expr_iri a Core.LogicalOperator`
- [ ] 23.3.2.5 Create `operatorSymbol` triple with operator name
- [ ] 23.3.2.6 For binary: create `hasLeftOperand` and `hasRightOperand` triples
- [ ] 23.3.2.7 For unary: create `hasOperand` triple
- [ ] 23.3.2.8 Combine all triples recursively

**Section 23.3 Unit Tests:**
- [ ] Test logical operator extraction for and
- [ ] Test logical operator extraction for or
- [ ] Test logical operator extraction for short-circuit and (&&)
- [ ] Test logical operator extraction for short-circuit or (||)
- [ ] Test logical operator extraction for not (!)
- [ ] Test logical operator extraction handles boolean not
- [ ] Test logical operator extraction for nested logical operations
- [ ] Test logical operator extraction preserves evaluation order via structure

## 23.4 Pipe Operator

This section implements extraction for the pipe operator (`|>`) which passes the left expression as the first argument to the right expression.

### 23.4.1 Pipe Operator Detection
- [ ] 23.4.1.1 Implement `build_pipe/5` in ExpressionBuilder
- [ ] 23.4.1.2 Match `:|>` AST pattern
- [ ] 23.4.1.3 Extract left expression (the value being piped)
- [ ] 23.4.1.4 Extract right expression (the function receiving the pipe)
- [ ] 23.4.1.5 Create type triple: `expr_iri a Core.PipeOperator`

### 23.4.2 Pipe Operand Extraction
- [ ] 23.4.2.1 Generate child IRI for left operand: `{expr_iri}/left`
- [ ] 23.4.2.2 Generate child IRI for right operand: `{expr_iri}/right`
- [ ] 23.4.2.3 Recursively build left operand expression
- [ ] 23.4.2.4 Recursively build right operand expression
- [ ] 23.4.2.5 Create `hasLeftOperand` triple (value being piped)
- [ ] 23.4.2.6 Create `hasRightOperand` triple (function call)
- [ ] 23.4.2.7 Optionally capture pipe semantics via annotation

**Section 23.4 Unit Tests:**
- [ ] Test pipe operator extraction for simple pipe
- [ ] Test pipe operator extraction for chained pipes
- [ ] Test pipe operator extraction captures left expression
- [ ] Test pipe operator extraction captures right expression
- [ ] Test pipe operator extraction handles complex nested pipes
- [ ] Test pipe operator extraction preserves pipe order

## 23.5 Match and Capture Operators

This section implements extraction for the match operator (`=`) and capture operator (`&`).

### 23.5.1 Match Operator Extraction
- [ ] 23.5.1.1 Implement `build_match_operator/5` for `=` pattern matching
- [ ] 23.5.1.2 Match `:=` in expression context (not function head)
- [ ] 23.5.1.3 Extract left side (pattern)
- [ ] 23.5.1.4 Extract right side (expression)
- [ ] 23.5.1.5 Create type triple: `expr_iri a Core.MatchOperator`
- [ ] 23.5.1.6 Create `operatorSymbol` triple with "="
- [ ] 23.5.1.7 Create `hasLeftOperand` (pattern)
- [ ] 23.5.1.8 Create `hasRightOperand` (expression)

### 23.5.2 Capture Operator Extraction
- [ ] 23.5.2.1 Implement `build_capture_operator/5` for `&` capture
- [ ] 23.5.2.2 Match `:&` in expression context
- [ ] 23.5.2.3 Match `&1`, `&2` etc. (captured arguments)
- [ ] 23.5.2.4 Match `&Mod.fun/arity` (anonymous function references)
- [ ] 23.5.2.5 Create type triple: `expr_iri a Core.CaptureOperator`
- [ ] 23.5.2.6 Create `operatorSymbol` triple with "&"
- [ ] 23.5.2.7 For `&N`: create index property
- [ ] 23.5.2.8 For `&Mod.fun`: create function reference properties
- [ ] 23.5.2.9 Create `hasOperand` or appropriate property

**Section 23.5 Unit Tests:**
- [ ] Test match operator extraction for pattern = expression
- [ ] Test match operator extraction handles complex patterns
- [ ] Test match operator extraction captures both sides
- [ ] Test capture operator extraction for &1
- [ ] Test capture operator extraction for &2, &3 etc.
- [ ] Test capture operator extraction for &Mod.fun/arity
- [ ] Test capture operator extraction for &Mod.fun
- [ ] Test capture operator extraction distinguishes capture types

## 23.6 String Concatenation and List Operators

This section implements extraction for string concatenation (`<>`), list concatenation (`++`), and list subtraction (`--`) operators.

### 23.6.1 String Concatenation Operator
- [ ] 23.6.1.1 Implement `build_string_concat/5` for `<>` operator
- [ ] 23.6.1.2 Match `:<>` AST pattern
- [ ] 23.6.1.3 Extract left binary/expression
- [ ] 23.6.1.4 Extract right binary/expression
- [ ] 23.6.1.5 Create type triple: `expr_iri a Core.StringConcatOperator`
- [ ] 23.6.1.6 Create `operatorSymbol` triple with "<>"
- [ ] 23.6.1.7 Create `hasLeftOperand` and `hasRightOperand` triples
- [ ] 23.6.1.8 Support for chained concatenation: `a <> b <> c`

### 23.6.2 List Operators
- [ ] 23.6.2.1 Implement `build_list_operator/5` for `++` and `--`
- [ ] 23.6.2.2 Match `:++` for list concatenation
- [ ] 23.6.2.3 Match `:--` for list subtraction
- [ ] 23.6.2.4 Create type triple: `expr_iri a Core.ListOperator`
- [ ] 23.6.2.5 Create `operatorSymbol` triple with "++" or "--"
- [ ] 23.6.2.6 Create `hasLeftOperand` and `hasRightOperand` triples
- [ ] 23.6.2.7 Handle list operator associativity

**Section 23.6 Unit Tests:**
- [ ] Test string concat operator extraction for `<>`
- [ ] Test string concat operator extraction for chained `<>`
- [ ] Test string concat operator extraction handles binary operands
- [ ] Test list operator extraction for `++`
- [ ] Test list operator extraction for `--`
- [ ] Test list operator extraction handles list operands
- [ ] Test list operator extraction for chained list operations

## 23.7 In Operator

This section implements extraction for the membership testing operator (`in`).

### 23.7.1 In Operator Extraction
- [ ] 23.7.1.1 Implement `build_in_operator/5` for `in` operator
- [ ] 23.7.1.2 Match `:in` AST pattern
- [ ] 23.7.1.3 Extract left expression (element being tested)
- [ ] 23.7.1.4 Extract right expression (enumerable)
- [ ] 23.7.1.5 Create type triple: `expr_iri a Core.InOperator`
- [ ] 23.7.1.6 Create `operatorSymbol` triple with "in"
- [ ] 23.7.1.7 Create `hasLeftOperand` triple (element)
- [ ] 23.7.1.8 Create `hasRightOperand` triple (enumerable)

**Section 23.7 Unit Tests:**
- [ ] Test in operator extraction for simple membership test
- [ ] Test in operator extraction captures element
- [ ] Test in operator extraction captures enumerable
- [ ] Test in operator extraction handles complex expressions

## Phase 23 Integration Tests

- [ ] Test complete operator extraction: arithmetic, comparison, logical
- [ ] Test operator extraction preserves expression structure
- [ ] Test nested operator extraction creates correct tree
- [ ] Test operator extraction with mixed operator types
- [ ] Test operator IRI generation follows parent-child hierarchy
- [ ] Test SPARQL queries find operators by type
- [ ] Test SPARQL queries navigate operator operands
- [ ] Test light mode skips operator extraction
- [ ] Test full mode includes all operator triples
- [ ] Test operator extraction handles complex real-world expressions

**Integration Test Summary:**
- 10 integration tests covering all operator types
- Tests verify expression tree structure and SPARQL queryability
- Tests confirm both light and full mode behavior
- Test file: `test/elixir_ontologies/builders/operator_builder_test.exs`
