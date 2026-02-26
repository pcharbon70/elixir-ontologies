# Phase 21.4: Core Expression Builders

**Status:** ✅ Complete
**Branch:** `feature/phase-21-4-core-expression-builders`
**Created:** 2025-01-09
**Completed:** 2025-01-09
**Target:** Implement core expression building functions for nested operands and literals

## Problem Statement

The current ExpressionBuilder has stub functions for binary and unary operators that only create the operator type and symbol triples. They don't:
1. Build triples for nested operand expressions (left, right, single operand)
2. Create operand linking triples (`hasLeftOperand`, `hasRightOperand`, `hasOperand`)
3. Build proper triples for literal values (integers, floats, strings, atoms)
4. Generate child expression IRIs using relative paths

This limits the expression graph to shallow operators without capturing the full expression structure.

## Solution Overview

Implement proper recursive expression building that:
1. Builds nested operand expressions with their own IRIs and triples
2. Links parent expressions to children using `hasLeftOperand`, `hasRightOperand`, `hasOperand`
3. Creates proper literal type triples with typed values
4. Uses relative IRIs for child expressions (e.g., `expr/0/left`, `expr/0/right`)

## Technical Details

### Files to Modify

- `lib/elixir_ontologies/builders/expression_builder.ex` - Enhance builder functions
- `test/elixir_ontologies/builders/expression_builder_test.exs` - Add new tests

### Ontology Terms Used

**Classes:**
- `Core.IntegerLiteral` - Integer literal values
- `Core.FloatLiteral` - Float literal values
- `Core.StringLiteral` - String literal values
- `Core.AtomLiteral` - Atom literal values (including `:true`, `:false`, `:nil`)
- `Core.WildcardPattern` - Wildcard pattern (`_`)

**Object Properties:**
- `Core.hasLeftOperand` - Links binary operator to left operand
- `Core.hasRightOperand` - Links binary operator to right operand
- `Core.hasOperand` - Links unary operator to its operand

**Datatype Properties:**
- `Core.integerValue` - Integer literal value (xsd:integer)
- `Core.floatValue` - Float literal value (xsd:double)
- `Core.stringValue` - String literal value (xsd:string)
- `Core.atomValue` - Atom literal value (xsd:string)

### Builder Function Signatures

```elixir
# Binary operator builder
defp build_binary_operator(op, left_ast, right_ast, expr_iri, context, type_class)

# Unary operator builder
defp build_unary_operator(op, operand_ast, expr_iri, context, type_class)

# Literal builder
defp build_literal(value, expr_iri, literal_type, value_property, xsd_type)

# Atom literal builder
defp build_atom_literal(atom_value, expr_iri)

# Variable builder (already exists, needs verification)
defp build_variable({name, _meta, _ctx}, expr_iri, _context)

# Wildcard builder (already exists, needs verification)
defp build_wildcard(expr_iri)
```

## Implementation Plan

### 21.4.1 Binary Operator Builder

- [ ] 21.4.1.1 Implement `build_binary_operator/6` for ops with left and right operands
- [ ] 21.4.1.2 Generate `left_iri` using `fresh_iri/2` with "left" suffix
- [ ] 21.4.1.3 Recursively build left operand triples via `build_expression_triples/3`
- [ ] 21.4.1.4 Generate `right_iri` using `fresh_iri/2` with "right" suffix
- [ ] 21.4.1.5 Recursively build right operand triples via `build_expression_triples/3`
- [ ] 21.4.1.6 Create type triple: `expr_iri a OperatorType`
- [ ] 21.4.1.7 Create `operatorSymbol` triple with operator name
- [ ] 21.4.1.8 Create `hasLeftOperand` triple linking to `left_iri`
- [ ] 21.4.1.9 Create `hasRightOperand` triple linking to `right_iri`
- [ ] 21.4.1.10 Return combined triples from all expressions

### 21.4.2 Unary Operator Builder

- [ ] 21.4.2.1 Implement `build_unary_operator/5` for ops with single operand
- [ ] 21.4.2.2 Generate `operand_iri` using `fresh_iri/2` with "operand" suffix
- [ ] 21.4.3 Recursively build operand triples via `build_expression_triples/3`
- [ ] 21.4.2.4 Create type triple: `expr_iri a OperatorType`
- [ ] 21.4.2.5 Create `operatorSymbol` triple with operator name
- [ ] 21.4.2.6 Create `hasOperand` triple linking to `operand_iri`
- [ ] 21.4.2.7 Return combined triples

### 21.4.3 Variable and Pattern Builders

- [ ] 21.4.3.1 Verify `build_variable/3` creates correct `Variable` type triple
- [ ] 21.4.3.2 Verify `build_variable/3` creates `name` triple with variable name
- [ ] 21.4.3.3 Verify `build_wildcard/3` creates `WildcardPattern` type triple
- [ ] 21.4.3.4 Implement `build_atom_literal/3` for atom values
- [ ] 21.4.3.5 Create `AtomLiteral` type triple
- [ ] 21.4.3.6 Create `atomValue` triple with atom name as string

### 21.4.4 Literal Builder

- [ ] 21.4.4.1 Implement `build_literal/5` for typed literal values
- [ ] 21.4.4.2 Handle integers with `Core.IntegerLiteral` type and `integerValue` property
- [ ] 21.4.4.3 Handle floats with `Core.FloatLiteral` type and `floatValue` property
- [ ] 21.4.4.4 Handle strings with `Core.StringLiteral` type and `stringValue` property
- [ ] 21.4.4.5 Use appropriate XSD datatypes (`xsd:integer`, `xsd:double`, `xsd:string`)

### 21.4.5 Update Existing Operator Builders

- [ ] 21.4.5.1 Update `build_comparison/5` to use `build_binary_operator/6`
- [ ] 21.4.5.2 Update `build_logical/5` to use `build_binary_operator/6`
- [ ] 21.4.5.3 Update `build_arithmetic/5` to use `build_binary_operator/6`
- [ ] 21.4.5.4 Update `build_unary/4` to use `build_unary_operator/5`
- [ ] 21.4.5.5 Update pipe/string concat/list op builders as needed

## Unit Tests

### Binary Operator Tests
- [ ] Test `build_binary_operator/6` creates correct type and symbol triples
- [ ] Test `build_binary_operator/6` creates left operand with relative IRI
- [ ] Test `build_binary_operator/6` creates right operand with relative IRI
- [ ] Test `build_binary_operator/6` links operands with `hasLeftOperand` and `hasRightOperand`
- [ ] Test `build_binary_operator/6` handles nested binary operators
- [ ] Test `build_binary_operator/6` handles literals as operands
- [ ] Test `build_binary_operator/6` handles variables as operands

### Unary Operator Tests
- [ ] Test `build_unary_operator/5` creates correct type and symbol triples
- [ ] Test `build_unary_operator/5` creates operand with relative IRI
- [ ] Test `build_unary_operator/5` links operand with `hasOperand`
- [ ] Test `build_unary_operator/5` handles nested expressions

### Literal Tests
- [ ] Test integer literals create `IntegerLiteral` with `integerValue`
- [ ] Test float literals create `FloatLiteral` with `floatValue`
- [ ] Test string literals create `StringLiteral` with `stringValue`
- [ ] Test atom literals create `AtomLiteral` with `atomValue`
- [ ] Test `true`, `false`, `nil` are handled as atom literals

### Variable and Wildcard Tests
- [ ] Test variables create `Variable` with `name` property
- [ ] Test wildcards create `WildcardPattern`

### Integration Tests
- [ ] Test complete expression: `x > 5` builds correct graph
- [ ] Test nested expression: `x > 5 and y < 10` builds correct hierarchy
- [ ] Test complex expression: `x + y * 2` builds correct structure
- [ ] Test literal-heavy expression: `foo(42, "bar", :baz)` includes all literals

## Success Criteria

1. Binary operators create operand triples with relative IRIs
2. Unary operators create operand triples with relative IRIs
3. Operands are linked via `hasLeftOperand`, `hasRightOperand`, `hasOperand`
4. Literals create proper typed value triples
5. Nested expressions create correct IRI hierarchy
6. All new tests pass
7. All existing tests continue to pass

## Example IRI Structure

```
# Expression: x > 5 and y < 10

expr/0 (LogicalOperator, operatorSymbol="and")
├── hasLeftOperand → expr/0/left (ComparisonOperator, operatorSymbol=">")
│   ├── hasLeftOperand → expr/0/left/left (Variable, name="x")
│   └── hasRightOperand → expr/0/left/right (IntegerLiteral, integerValue=5)
└── hasRightOperand → expr/0/right (ComparisonOperator, operatorSymbol="<")
    ├── hasLeftOperand → expr/0/right/left (Variable, name="y")
    └── hasRightOperand → expr/0/right/right (IntegerLiteral, integerValue=10)
```

## Notes/Considerations

### Recursive Building

The builder must recursively call `build_expression_triples/3` for operands. This requires:
1. Generating relative IRIs for child expressions
2. Accumulating triples from all nested calls
3. Handling skip returns for nil or invalid operands

### Literal Handling

Literals need special consideration:
- Integers, floats, strings are values, not expressions
- They should be wrapped in literal types when used as operands
- The `build_expression_triples/3` dispatch handles this

### Variable vs Call Pattern Matching

Variable pattern `{name, meta, ctx}` must come after call patterns to avoid matching function calls:
- Local call: `{function, meta, args}` where `args` is a list
- Variable: `{name, meta, ctx}` where `ctx` is nil or an atom

## Status Log

### 2025-01-09 - Implementation Complete ✅
- **Binary Operator Builder**: Implemented `build_binary_operator/6` with recursive operand building
- **Unary Operator Builder**: Implemented `build_unary_operator/5` with recursive operand building
- **Literal Builders**: Implemented `build_literal/5` for typed literals (IntegerLiteral, FloatLiteral, StringLiteral)
- **Atom Literal Builder**: Implemented `build_atom_literal/3` for atom values including true/false/nil
- **Operator Updates**: Updated all operator builders (comparison, logical, arithmetic, unary, pipe, concat, list, match)
- **Tests**: Added 5 new integration tests for nested expressions, updated 6 literal tests
- **Full Test Suite**: All 7098 tests pass (1636 doctests, 29 properties, 7098 tests, 0 failures)

### Implementation Details

**New Functions:**
- `build_binary_operator/6` - Builds binary operators with left/right operand triples
- `build_unary_operator/5` - Builds unary operators with operand triples
- `build_literal/5` - Builds typed literals (integer, float, string)
- `build_atom_literal/2` - Builds atom literals
- `atom_to_string/1` - Converts atoms to string representation

**IRI Hierarchy Example:**
```
expr/0 (LogicalOperator, operatorSymbol="and")
├── hasLeftOperand → expr/0/left (ComparisonOperator, operatorSymbol=">")
│   ├── hasLeftOperand → expr/0/left/left (Variable, name="x")
│   └── hasRightOperand → expr/0/left/right (IntegerLiteral, integerValue=5)
└── hasRightOperand → expr/0/right (ComparisonOperator, operatorSymbol="<")
    ├── hasLeftOperand → expr/0/right/left (Variable, name="y")
    └── hasRightOperand → expr/0/right/right (IntegerLiteral, integerValue=10)
```

### 2025-01-09 - Initial Planning
- Created feature planning document
- Analyzed current ExpressionBuilder stub implementations
- Verified ontology terms exist for all needed types and properties
- Created feature branch `feature/phase-21-4-core-expression-builders`
