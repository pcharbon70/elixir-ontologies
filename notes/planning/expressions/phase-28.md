# Phase 28: Comprehension Expression Integration

This phase integrates the ExpressionBuilder into ComprehensionBuilder to extract full generator patterns, filter expressions, and collectable expressions for list and bitstring comprehensions. Comprehensions are a powerful Elixir feature for transforming and filtering enumerable data.

## 28.1 List Comprehension Generator Integration

This section updates ComprehensionBuilder to extract full generator patterns when `include_expressions: true`.

### 28.1.1 Generator Pattern Extraction
- [ ] 28.1.1.1 Update `build_list_comprehension/3` to accept context
- [ ] 28.1.1.2 Check `context.config.include_expressions` flag
- [ ] 28.1.1.3 When `true`: extract generator pattern via ExpressionBuilder
- [ ] 28.1.1.4 Call `ExpressionBuilder.build_pattern/3` for generator AST
- [ ] 28.1.1.5 Generate child IRI: `{comp_iri}/generator/{index}`
- [ ] 28.1.1.6 Link pattern via `hasPattern` property
- [ ] 28.1.1.7 Extract enumerable expression for generator
- [ ] 28.1.1.8 Link enumerable via `hasEnumerable` property
- [ ] 28.1.1.9 When `false`: use existing blank node approach (light mode)

### 28.1.2 Multiple Generator Support
- [ ] 28.1.2.1 Handle comprehensions with multiple generators: `for x <- xs, y <- ys`
- [ ] 28.1.2.2 Create separate generator IRIs for each
- [ ] 28.1.2.3 Link generators via `hasGenerator` property (ordered)
- [ ] 28.1.2.4 Preserve generator order (important for semantics)
- [ ] 28.1.2.5 Extract each generator's pattern and enumerable
- [ ] 28.1.2.6 Handle nested generator patterns: `{x, y} <- list_of_tuples`

**Section 28.1 Unit Tests:**
- [ ] Test list comprehension generator extraction in light mode
- [ ] Test list comprehension generator extraction in full mode
- [ ] Test generator extraction captures pattern
- [ ] Test generator extraction captures enumerable
- [ ] Test generator extraction handles multiple generators
- [ ] Test generator extraction preserves generator order
- [ ] Test generator extraction handles nested patterns

## 28.2 Bitstring Comprehension Integration

This section implements full expression extraction for bitstring comprehensions (`for <<pattern>> <- enumerable`).

### 28.2.1 Bitstring Generator Extraction
- [ ] 28.2.1.1 Update `build_bitstring_comprehension/3` to accept context
- [ ] 28.2.1.2 Match `:for` with `:<<>>` pattern
- [ ] 28.2.1.3 Create type triple: `expr_iri a Core.BitstringComprehension`
- [ ] 28.2.1.4 Extract bitstring pattern via ExpressionBuilder pattern builder
- [ ] 28.2.1.5 Extract enumerable expression
- [ ] 28.2.1.6 Link pattern and enumerable correctly
- [ ] 28.2.1.7 Handle bitstring comprehensions with options

### 28.2.2 Bitstring Segment Patterns
- [ ] 28.2.2.1 Handle bitstring patterns with size: `<<x::8>>`
- [ ] 28.2.2.2 Handle bitstring patterns with type: `<<x::binary>>`
- [ ] 28.2.2.3 Handle bitstring patterns with unit: `<<x::unit(8)>>`
- [ ] 28.2.2.4 Handle complex bitstring patterns: `<<head::8, rest::binary>>`
- [ ] 28.2.2.5 Extract modifiers as part of pattern metadata

**Section 28.2 Unit Tests:**
- [ ] Test bitstring comprehension extraction in full mode
- [ ] Test bitstring comprehension extracts pattern
- [ ] Test bitstring comprehension extracts enumerable
- [ ] Test bitstring comprehension handles size modifiers
- [ ] Test bitstring comprehension handles type modifiers
- [ ] Test bitstring comprehension handles complex patterns

## 28.3 Filter Expression Integration

This section updates ComprehensionBuilder to extract full filter expressions when `include_expressions: true`.

### 28.3.1 Filter Expression Extraction
- [ ] 28.3.1.1 Identify filter clauses in comprehension AST
- [ ] 28.3.1.2 Match filter pattern: `filter_expr` (not <- assignment)
- [ ] 28.3.1.3 When `include_expressions: true`: extract filter via ExpressionBuilder
- [ ] 28.3.1.4 Generate child IRI: `{comp_iri}/filter/{index}`
- [ ] 28.3.1.5 Extract filter expression recursively
- [ ] 28.3.1.6 Link filter via `hasFilter` property
- [ ] 28.3.1.7 Handle multiple filters: `for x <- xs, x > 0, x < 100`

### 28.3.2 Complex Filter Expressions
- [ ] 28.3.2.1 Handle filters with and/or: `for x <- xs, is_binary(x) and byte_size(x) > 0`
- [ ] 28.3.2.2 Handle filters with function calls: `for x <- xs, valid?(x)`
- [ ] 28.3.2.3 Handle filters with comparison operators
- [ ] 28.3.2.4 Handle filters with guard expressions
- [ ] 28.3.2.5 Ensure filter expression tree is preserved

**Section 28.3 Unit Tests:**
- [ ] Test filter expression extraction in full mode
- [ ] Test filter extraction handles boolean expressions
- [ ] Test filter extraction handles function calls
- [ ] Test filter extraction handles multiple filters
- [ ] Test filter extraction preserves filter structure
- [ ] Test filter extraction handles complex guards

## 28.4 Collect Expression Integration

This section implements extraction for the collect expression in comprehensions.

### 28.4.1 Collect Expression Extraction
- [ ] 28.4.1.1 Identify collect expression in comprehension AST
- [ ] 28.4.1.2 Match collect pattern (expression after generators/filters)
- [ ] 28.4.1.3 When `include_expressions: true`: extract collect via ExpressionBuilder
- [ ] 28.4.1.4 Generate child IRI: `{comp_iri}/collect`
- [ ] 28.4.1.5 Extract collect expression recursively
- [ ] 28.4.1.6 Link via `hasCollectExpression` property
- [ ] 28.4.1.7 Handle implicit collect (when omitted, defaults to generator variable)

### 28.4.2 Complex Collect Expressions
- [ ] 28.4.2.1 Handle collect with pattern: `for {k, v} <- map, do: {k, v * 2}`
- [ ] 28.4.2.2 Handle collect with expression: `for x <- xs, do: x * 2`
- [ ] 28.4.2.3 Handle collect with block: `for x <- xs, do: (calc = x * 2; calc + 1)`
- [ ] 28.4.2.4 Handle collect with struct literal: `for x <- xs, do: %{value: x}`

**Section 28.4 Unit Tests:**
- [ ] Test collect expression extraction in full mode
- [ ] Test collect extraction handles simple expressions
- [ ] Test collect extraction handles pattern collect
- [ ] Test collect extraction handles block collect
- [ ] Test collect extraction handles struct collect
- [ ] Test collect extraction handles implicit collect

## 28.5 Comprehension Option Expression Integration

This section implements extraction for comprehension options like `:into`, `:reduce`, and `:uniq`.

### 28.5.1 Into Option Extraction
- [ ] 28.5.1.1 Match `:into` option in comprehension AST
- [ ] 28.5.1.2 Extract `:into` expression (e.g., `%{}`, `MapSet.new()`)
- [ ] 28.5.1.3 Generate child IRI: `{comp_iri}/into`
- [ ] 28.5.1.4 Extract via ExpressionBuilder if expression
- [ ] 28.5.1.5 Link via `hasIntoExpression` property
- [ ] 28.5.1.6 Handle literal `%{}` vs function call `MapSet.new()`

### 28.5.2 Reduce Option Extraction
- [ ] 28.5.2.1 Match `:reduce` option in comprehension AST
- [ ] 28.5.2.2 Extract `:reduce` accumulator expression
- [ ] 28.5.2.3 Generate child IRI: `{comp_iri}/reduce`
- [ ] 28.5.2.4 Extract via ExpressionBuilder
- [ ] 28.5.2.5 Link via `hasReduceExpression` property
- [ ] 28.5.2.6 Handle reduce with and without `:acc` option

### 28.5.3 Uniq Option Extraction
- [ ] 28.5.3.1 Match `:uniq` option in comprehension AST
- [ ] 28.5.3.2 Extract `:uniq` boolean or expression
- [ ] 28.5.3.3 Create `hasUniqExpression` property
- [ ] 28.5.3.4 Handle `uniq: true` vs `uniq: &key/1`

**Section 28.5 Unit Tests:**
- [ ] Test into option extraction for literal map
- [ ] Test into option extraction for function call
- [ ] Test reduce option extraction
- [ ] Test uniq option extraction
- [ ] Test comprehension with multiple options
- [ ] Test comprehension with no options

## 28.6 Comprehension Nesting and Complexity

This section ensures that the comprehension extraction system handles nested comprehensions and complex scenarios.

### 28.6.1 Nested Comprehension Support
- [ ] 28.6.1.1 Test nested list comprehensions: `for x <- xs, for y <- ys, do: {x, y}`
- [ ] 28.6.1.2 Test nested bitstring comprehensions
- [ ] 28.6.1.3 Test comprehensions within other constructs (if, case, etc.)
- [ ] 28.6.1.4 Verify nested comprehension IRIs follow hierarchy
- [ ] 28.6.1.5 Ensure parent-child relationships are preserved

### 28.6.2 Complex Comprehension Scenarios
- [ ] 28.6.2.1 Test comprehension with all components: generators, filters, collect, options
- [ ] 28.6.2.2 Test comprehension with pattern destructuring in generators
- [ ] 28.6.2.3 Test comprehension with complex filter expressions
- [ ] 28.6.2.4 Test comprehension with side effects in collect block
- [ ] 28.6.2.5 Verify extraction preserves comprehension semantics

**Section 28.6 Unit Tests:**
- [ ] Test nested list comprehension extraction
- [ ] Test nested bitstring comprehension extraction
- [ ] Test comprehension within control flow
- [ ] Test comprehension with all components
- [ ] Test comprehension preserves semantics

## Phase 28 Integration Tests

- [ ] Test complete comprehension extraction: generators, filters, collect, options
- [ ] Test list comprehension extraction in light mode
- [ ] Test list comprehension extraction in full mode
- [ ] Test bitstring comprehension extraction in full mode
- [ ] Test nested comprehension extraction
- [ ] Test comprehension extraction with complex filters
- [ ] Test comprehension extraction with options
- [ ] Test SPARQL queries find comprehensions by type
- [ ] Test SPARQL queries navigate comprehension generators
- [ ] Test SPARQL queries navigate comprehension filters
- [ ] Test SPARQL queries find collect expressions
- [ ] Test comprehension extraction integrates with ExpressionBuilder

**Integration Test Summary:**
- 12 integration tests covering all comprehension scenarios
- Tests verify comprehension extraction completeness and SPARQL queryability
- Tests confirm both light and full mode behavior
- Test file: `test/elixir_ontologies/builders/comprehension_expression_test.exs`
