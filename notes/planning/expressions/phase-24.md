# Phase 24: Pattern Expression Extraction

This phase implements extraction for all pattern types defined in the elixir-core.ttl ontology. Patterns in Elixir are used in function heads, case clauses, match expressions, and for comprehension generators. We'll handle literal patterns, variable patterns, wildcard patterns, pin patterns, tuple patterns, list patterns, map patterns, struct patterns, binary patterns, and as-patterns.

## 24.1 Pattern Detection and Dispatch

This section implements the pattern detection and dispatch system that routes different AST patterns to their appropriate builders.

### 24.1.1 Pattern Type Detection
- [ ] 24.1.1.1 Implement `detect_pattern_type/1` helper in ExpressionBuilder
- [ ] 24.1.1.2 Return `:literal_pattern` for literal values
- [ ] 24.1.1.3 Return `:variable_pattern` for `{name, _, context}` variables
- [ ] 24.1.1.4 Return `:wildcard_pattern` for `{:_}` patterns
- [ ] 24.1.1.5 Return `:pin_pattern` for `{:^, _, [_]}` patterns
- [ ] 24.1.1.6 Return `:tuple_pattern` for `{:{}, _, _}` patterns
- [ ] 24.1.1.7 Return `:list_pattern` for `[...]` patterns
- [ ] 24.1.1.8 Return `:map_pattern` for `{:%{}, _, _}` patterns
- [ ] 24.1.1.9 Return `:struct_pattern` for `{:%, _, _}` patterns
- [ ] 24.1.1.10 Return `:binary_pattern` for `{:<<>>, _, _}` patterns
- [ ] 24.1.1.11 Return `:as_pattern` for `{:=, _, [pattern, var]}` patterns

### 24.1.2 Pattern Builder Dispatch
- [ ] 24.1.2.1 Implement `build_pattern/3` in ExpressionBuilder
- [ ] 24.1.2.2 Dispatch to `build_literal_pattern/3` for literals
- [ ] 24.1.2.3 Dispatch to `build_variable_pattern/3` for variables
- [ ] 24.1.2.4 Dispatch to `build_wildcard_pattern/3` for wildcards
- [ ] 24.1.2.5 Dispatch to `build_pin_pattern/3` for pinned variables
- [ ] 24.1.2.6 Dispatch to `build_tuple_pattern/3` for tuples
- [ ] 24.1.2.7 Dispatch to `build_list_pattern/3` for lists
- [ ] 24.1.2.8 Dispatch to `build_map_pattern/3` for maps
- [ ] 24.1.2.9 Dispatch to `build_struct_pattern/3` for structs
- [ ] 24.1.2.10 Dispatch to `build_binary_pattern/3` for binaries
- [ ] 24.1.2.11 Dispatch to `build_as_pattern/3` for as-patterns

**Section 24.1 Unit Tests:**
- [ ] Test pattern type detection for all pattern types
- [ ] Test pattern type detection handles nested patterns
- [ ] Test pattern type detection returns :unknown for unhandled patterns
- [ ] Test pattern dispatch routes to correct builder
- [ ] Test pattern dispatch handles edge cases

## 24.2 Literal and Variable Patterns

This section implements extraction for literal patterns (matching against specific values) and variable patterns (binding values to names).

### 24.2.1 Literal Pattern Extraction
- [ ] 24.2.1.1 Implement `build_literal_pattern/3` in ExpressionBuilder
- [ ] 24.2.1.2 Match integer literals in pattern context
- [ ] 24.2.1.3 Match float literals in pattern context
- [ ] 24.2.1.4 Match string literals in pattern context
- [ ] 24.2.1.5 Match atom literals in pattern context (including `true`, `false`, `nil`)
- [ ] 24.2.1.6 Create type triple: `expr_iri a Core.LiteralPattern`
- [ ] 24.2.1.7 Reuse literal value extraction from Phase 22
- [ ] 24.2.1.8 Create `hasLiteralValue` property linking to value
- [ ] 24.2.1.9 Distinguish pattern context from literal expression context

### 24.2.2 Variable Pattern Extraction
- [ ] 24.2.2.1 Implement `build_variable_pattern/3` in ExpressionBuilder
- [ ] 24.2.2.2 Match `{name, _, context}` where name is an atom variable
- [ ] 24.2.2.3 Exclude underscore (wildcard) and pinned variables
- [ ] 24.2.2.4 Create type triple: `expr_iri a Core.VariablePattern`
- [ ] 24.2.2.5 Create `variableName` property with variable name as string
- [ ] 24.2.2.6 Link to `Core.Variable` via appropriate property
- [ ] 24.2.2.7 Track variable binding for scope analysis (future)

**Section 24.2 Unit Tests:**
- [ ] Test literal pattern extraction for integers
- [ ] Test literal pattern extraction for floats
- [ ] Test literal pattern extraction for strings
- [ ] Test literal pattern extraction for atoms
- [ ] Test literal pattern extraction for booleans and nil
- [ ] Test variable pattern extraction for simple variables
- [ ] Test variable pattern extraction for variables with underscores
- [ ] Test variable pattern extraction captures variable name
- [ ] Test pattern vs expression distinction is maintained

## 24.3 Wildcard and Pin Patterns

This section implements extraction for wildcard patterns (which match anything and discard the value) and pin patterns (which match against existing variable values).

### 24.3.1 Wildcard Pattern Extraction
- [ ] 24.3.1.1 Implement `build_wildcard_pattern/3` in ExpressionBuilder
- [ ] 24.3.1.2 Match `{:_}` pattern (single underscore)
- [ ] 24.3.1.3 Match leading underscore: `_var` (still wildcard in patterns)
- [ ] 24.3.1.4 Create type triple: `expr_iri a Core.WildcardPattern`
- [ ] 24.3.1.5 Optionally store original variable name (if `_foo`)
- [ ] 24.3.1.6 Document that wildcards don't bind values

### 24.3.2 Pin Pattern Extraction
- [ ] 24.3.2.1 Implement `build_pin_pattern/3` in ExpressionBuilder
- [ ] 24.3.2.2 Match `{:^, _, [{var_name, _, _}]}` pattern
- [ ] 24.3.2.3 Extract pinned variable name
- [ ] 24.3.2.4 Create type triple: `expr_iri a Core.PinPattern`
- [ ] 24.3.2.5 Create `pinsVariable` property linking to variable
- [ ] 24.3.2.6 Link to `Core.Variable` via appropriate property
- [ ] 24.3.2.7 Document pin semantics (match against existing value)

**Section 24.3 Unit Tests:**
- [ ] Test wildcard pattern extraction for `_`
- [ ] Test wildcard pattern extraction for `_var`
- [ ] Test wildcard pattern is distinguished from variable
- [ ] Test pin pattern extraction for `^var`
- [ ] Test pin pattern extraction captures pinned variable name
- [ ] Test pin pattern links to variable correctly
- [ ] Test nested patterns with wildcards and pins

## 24.4 Tuple and List Patterns

This section implements extraction for tuple patterns and list patterns, including nested structures and cons patterns.

### 24.4.1 Tuple Pattern Extraction
- [ ] 24.4.1.1 Implement `build_tuple_pattern/3` in ExpressionBuilder
- [ ] 24.4.1.2 Match `{{}, _, elements}` explicit tuple pattern
- [ ] 24.4.1.3 Match 2-tuple special form: `{left, right}`
- [ ] 24.4.1.4 Handle nested tuples: `{{a, b}, {c, d}}`
- [ ] 24.4.1.5 Create type triple: `expr_iri a Core.TuplePattern`
- [ ] 24.4.1.6 Extract each element as a sub-pattern recursively
- [ ] 24.4.1.7 Link elements via `hasElement` property with position
- [ ] 24.4.1.8 Create ordered list or RDF list for element access

### 24.4.2 List Pattern Extraction
- [ ] 24.4.2.1 Implement `build_list_pattern/3` in ExpressionBuilder
- [ ] 24.4.2.2 Match empty list pattern: `[]`
- [ ] 24.4.2.3 Match flat list: `[a, b, c]`
- [ ] 24.4.2.4 Match nested lists: `[[1, 2], [3, 4]]`
- [ ] 24.4.2.5 Create type triple: `expr_iri a Core.ListPattern`
- [ ] 24.4.2.6 Extract each element as a sub-pattern recursively
- [ ] 24.4.2.7 Link elements via `hasElement` property with position

### 24.4.3 Cons Pattern Extraction
- [ ] 24.4.3.1 Match cons pattern: `[head | tail]`
- [ ] 24.4.3.2 Match nested cons: `[a, b | tail]` (desugars to nested cons)
- [ ] 24.4.3.3 Create type triple: `expr_iri a Core.ListPattern`
- [ ] 24.4.3.4 Extract `head` sub-pattern and link via `hasHead`
- [ ] 24.4.3.5 Extract `tail` sub-pattern and link via `hasTail`
- [ ] 24.4.3.6 For `[a, b | tail]`, create intermediate cons nodes

**Section 24.4 Unit Tests:**
- [ ] Test tuple pattern extraction for empty tuple
- [ ] Test tuple pattern extraction for 2-tuple
- [ ] Test tuple pattern extraction for n-tuple
- [ ] Test tuple pattern extraction for nested tuples
- [ ] Test list pattern extraction for empty list
- [ ] Test list pattern extraction for flat list
- [ ] Test list pattern extraction for nested list
- [ ] Test cons pattern extraction for `[head | tail]`
- [ ] Test cons pattern extraction for `[a, b | tail]`
- [ ] Test cons pattern extraction for proper vs improper lists

## 24.5 Map and Struct Patterns

This section implements extraction for map patterns and struct patterns, including key-value matching and update syntax.

### 24.5.1 Map Pattern Extraction
- [ ] 24.5.1.1 Implement `build_map_pattern/3` in ExpressionBuilder
- [ ] 24.5.1.2 Match empty map pattern: `%{}`
- [ ] 24.5.1.3 Match map with atom keys: `%{key: pattern}`
- [ ] 24.5.1.4 Match map with string keys: `%{"key" => pattern}`
- [ ] 24.5.1.5 Match map with mixed keys
- [ ] 24.5.1.6 Create type triple: `expr_iri a Core.MapPattern`
- [ ] 24.5.1.7 Extract each key-value pair
- [ ] 24.5.1.8 For each pair: extract key and value pattern
- [ ] 24.5.1.9 Link pairs via `hasKeyValuePair` or similar property

### 24.5.2 Struct Pattern Extraction
- [ ] 24.5.2.1 Implement `build_struct_pattern/3` in ExpressionBuilder
- [ ] 24.5.2.2 Match struct pattern: `%StructName{key: pattern}`
- [ ] 24.5.2.3 Match struct with update: `%StructName{struct | key: value}`
- [ ] 24.5.2.4 Match nested struct: `%Outer{inner: %Inner{}}`
- [ ] 24.5.2.5 Create type triple: `expr_iri a Core.StructPattern`
- [ ] 24.5.2.6 Extract struct name and link via `hasStructType`
- [ ] 24.5.2.7 Create `refersToModule` property for struct type
- [ ] 24.5.2.8 Extract struct fields as map pattern entries
- [ ] 24.5.2.9 For update syntax: track base struct and updates separately

**Section 24.5 Unit Tests:**
- [ ] Test map pattern extraction for empty map
- [ ] Test map pattern extraction for atom keys
- [ ] Test map pattern extraction for string keys
- [ ] Test map pattern extraction for mixed keys
- [ ] Test map pattern extraction for nested maps
- [ ] Test struct pattern extraction includes struct name
- [ ] Test struct pattern extraction includes fields
- [ ] Test struct pattern extraction for update syntax
- [ ] Test struct pattern extraction for nested structs

## 24.6 Binary and As Patterns

This section implements extraction for binary patterns (with size, type, and unit modifiers) and as-patterns (pattern = variable binding).

### 24.6.1 Binary Pattern Extraction
- [ ] 24.6.1.1 Implement `build_binary_pattern/3` in ExpressionBuilder
- [ ] 24.6.1.2 Match empty binary: `<<>>`
- [ ] 24.6.1.3 Match binary with segment: `<<var::size>>`
- [ ] 24.6.1.4 Match binary with type: `<<var::binary>>`
- [ ] 24.6.1.5 Match binary with unit: `<<var::unit(8)>>`
- [ ] 24.6.1.6 Match complex binary: `<<head::8, rest::binary>>`
- [ ] 24.6.1.7 Create type triple: `expr_iri a Core.BinaryPattern`
- [ ] 24.6.1.8 Extract each segment as a sub-pattern
- [ ] 24.6.1.9 For segments: extract variable, size, type, unit modifiers
- [ ] 24.6.1.10 Link segments via `hasSegment` property

### 24.6.2 As-Pattern Extraction
- [ ] 24.6.2.1 Implement `build_as_pattern/3` in ExpressionBuilder
- [ ] 24.6.2.2 Match `{:=, _, [pattern, variable]}` pattern
- [ ] 24.6.2.3 Handle nested as-patterns: `{a, b} = var = expr`
- [ ] 24.6.2.4 Create type triple: `expr_iri a Core.AsPattern`
- [ ] 24.6.2.5 Extract inner pattern recursively
- [ ] 24.6.2.6 Extract binding variable
- [ ] 24.6.2.7 Create `hasPattern` property linking to inner pattern
- [ ] 24.6.2.8 Create `bindsVariable` property linking to variable
- [ ] 24.6.2.9 Document that as-pattern preserves the entire match

**Section 24.6 Unit Tests:**
- [ ] Test binary pattern extraction for empty binary
- [ ] Test binary pattern extraction for simple segment
- [ ] Test binary pattern extraction for typed segment
- [ ] Test binary pattern extraction for sized segment
- [ ] Test binary pattern extraction for complex multi-segment binary
- [ ] Test binary pattern extraction captures modifiers
- [ ] Test as-pattern extraction for simple pattern = var
- [ ] Test as-pattern extraction for complex pattern = var
- [ ] Test as-pattern extraction handles nested as-patterns
- [ ] Test as-pattern extraction links pattern and variable correctly

## 24.7 Pattern Nesting and Complexity

This section ensures that the pattern extraction system handles arbitrarily nested patterns correctly.

### 24.7.1 Nested Pattern Support
- [ ] 24.7.1.1 Test nested tuple patterns: `{{a, b}, {c, {d, e}}}`
- [ ] 24.7.1.2 Test nested list patterns: `[[1, 2], [3, [4]]]`
- [ ] 24.7.1.3 Test mixed nesting: `{[a, b], {c, d}}`
- [ ] 24.7.1.4 Test patterns within cons: `[{a, b} | tail]`
- [ ] 24.7.1.5 Test patterns within map: `%{key: {a, b}}`
- [ ] 24.7.1.6 Test patterns within struct: `%Struct{list: [a, b]}`
- [ ] 24.7.1.7 Test binary within tuple: `{<<x::8>>, y}`
- [ ] 24.7.1.8 Test patterns within as-pattern

### 24.7.2 Complex Pattern Combinations
- [ ] 24.7.2.1 Test function head with all pattern types
- [ ] 24.7.2.2 Test case clause with complex pattern
- [ ] 24.7.2.3 Test for comprehension with generator pattern
- [ ] 24.7.2.4 Test with clause with match patterns
- [ ] 24.7.2.5 Verify pattern extraction preserves AST structure

**Section 24.7 Unit Tests:**
- [ ] Test arbitrarily nested tuple patterns
- [ ] Test arbitrarily nested list patterns
- [ ] Test mixed nesting across pattern types
- [ ] Test real-world complex patterns from actual Elixir code
- [ ] Test pattern extraction depth limit (if any)

## Phase 24 Integration Tests

- [ ] Test complete pattern extraction: all 10 pattern types
- [ ] Test pattern extraction in function heads
- [ ] Test pattern extraction in case clauses
- [ ] Test pattern extraction in match expressions
- [ ] Test pattern extraction in for generators
- [ ] Test nested pattern extraction creates correct tree structure
- [ ] Test pattern extraction preserves binding information
- [ ] Test SPARQL queries find patterns by type
- [ ] Test SPARQL queries navigate pattern structure
- [ ] Test light mode skips pattern content (backward compat)
- [ ] Test full mode includes all pattern triples

**Integration Test Summary:**
- 11 integration tests covering all pattern types
- Tests verify pattern extraction in various contexts
- Tests confirm both light and full mode behavior
- Test file: `test/elixir_ontologies/builders/pattern_builder_test.exs`
