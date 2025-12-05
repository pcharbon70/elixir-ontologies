# Phase 3: Core Extractors (elixir-core.ttl)

This phase implements extractors for foundational constructs defined in elixir-core.ttl: literals, operators, expressions, patterns, control flow, and variables.

## 3.1 Literal Extractors

This section extracts literal values from AST nodes and builds corresponding RDF representations for all 12 literal types.

### 3.1.1 Literal Extractor Module
- [x] **Task 3.1.1 Complete**

Create extractors for each literal type defined in the core ontology.

- [x] 3.1.1.1 Create `lib/elixir_ontologies/extractors/literal.ex`
- [x] 3.1.1.2 Implement `Literal.extract/1` dispatching by literal type
- [x] 3.1.1.3 Extract `AtomLiteral` with `atomValue` property
- [x] 3.1.1.4 Extract `IntegerLiteral` with `integerValue` property
- [x] 3.1.1.5 Extract `FloatLiteral` with `floatValue` property
- [x] 3.1.1.6 Extract `StringLiteral` with `stringValue` property
- [x] 3.1.1.7 Extract `ListLiteral` with child elements
- [x] 3.1.1.8 Extract `TupleLiteral` with child elements
- [x] 3.1.1.9 Extract `MapLiteral` with key-value pairs
- [x] 3.1.1.10 Extract `KeywordListLiteral`
- [x] 3.1.1.11 Extract `BinaryLiteral` with `binaryValue`
- [x] 3.1.1.12 Extract `CharlistLiteral`
- [x] 3.1.1.13 Extract `SigilLiteral` with `sigilChar`, `sigilContent`, `sigilModifiers`
- [x] 3.1.1.14 Extract `RangeLiteral` with `rangeStart`, `rangeEnd`, `rangeStep`
- [x] 3.1.1.15 Write literal extraction tests (success: 121 tests - 48 doctests + 73 unit tests)

**Section 3.1 Unit Tests:**
- [x] Test atom literal extraction (:ok, :error, true, false, nil)
- [x] Test integer literal in various bases (decimal, hex, binary)
- [x] Test float literal extraction
- [x] Test string literal with interpolation markers
- [x] Test list literal with nested elements
- [x] Test tuple literal extraction
- [x] Test map literal with atom and string keys
- [x] Test sigil extraction (~r, ~s, ~w)
- [x] Test range literal with and without step

## 3.2 Operator Extractors

This section extracts operator expressions and classifies them according to the ontology's operator hierarchy.

### 3.2.1 Operator Extractor Module
- [ ] **Task 3.2.1 Complete**

Create extractors for all operator types with operand relationships.

- [ ] 3.2.1.1 Create `lib/elixir_ontologies/extractors/operator.ex`
- [ ] 3.2.1.2 Define operator classification map (symbol → class)
- [ ] 3.2.1.3 Implement `Operator.extract/1` dispatching by operator
- [ ] 3.2.1.4 Extract `ArithmeticOperator` (+, -, *, /, div, rem)
- [ ] 3.2.1.5 Extract `ComparisonOperator` (==, !=, ===, !==, <, >, <=, >=)
- [ ] 3.2.1.6 Extract `LogicalOperator` (and, or, not, &&, ||, !)
- [ ] 3.2.1.7 Extract `PipeOperator` (|>)
- [ ] 3.2.1.8 Extract `MatchOperator` (=)
- [ ] 3.2.1.9 Extract `CaptureOperator` (&)
- [ ] 3.2.1.10 Extract `StringConcatOperator` (<>)
- [ ] 3.2.1.11 Extract `ListOperator` (++, --)
- [ ] 3.2.1.12 Extract `InOperator` (in)
- [ ] 3.2.1.13 Add `hasLeftOperand`, `hasRightOperand` for binary operators
- [ ] 3.2.1.14 Add `hasOperand` for unary operators
- [ ] 3.2.1.15 Add `operatorSymbol` data property
- [ ] 3.2.1.16 Write operator tests (success: 20 tests covering all types)

**Section 3.2 Unit Tests:**
- [ ] Test arithmetic operator extraction
- [ ] Test comparison operator extraction
- [ ] Test logical operator extraction
- [ ] Test pipe operator with left/right operands
- [ ] Test match operator extraction
- [ ] Test capture operator extraction
- [ ] Test unary operator (not, !) extraction

## 3.3 Pattern Extractors

This section extracts pattern matching constructs which are fundamental to Elixir.

### 3.3.1 Pattern Extractor Module
- [ ] **Task 3.3.1 Complete**

Create extractors for all 11 pattern types.

- [ ] 3.3.1.1 Create `lib/elixir_ontologies/extractors/pattern.ex`
- [ ] 3.3.1.2 Implement `Pattern.extract/1` dispatching by pattern type
- [ ] 3.3.1.3 Extract `LiteralPattern` with matched value
- [ ] 3.3.1.4 Extract `VariablePattern` with `bindsVariable` property
- [ ] 3.3.1.5 Extract `WildcardPattern` (_)
- [ ] 3.3.1.6 Extract `PinPattern` (^var) with `pinsVariable` property
- [ ] 3.3.1.7 Extract `TuplePattern` with nested patterns
- [ ] 3.3.1.8 Extract `ListPattern` including head|tail decomposition
- [ ] 3.3.1.9 Extract `MapPattern` with key patterns
- [ ] 3.3.1.10 Extract `StructPattern` with struct name and field patterns
- [ ] 3.3.1.11 Extract `BinaryPattern` with size/type specifiers
- [ ] 3.3.1.12 Extract `AsPattern` (pattern = var)
- [ ] 3.3.1.13 Extract `Guard` and `GuardClause`
- [ ] 3.3.1.14 Write pattern tests (success: 22 tests)

**Section 3.3 Unit Tests:**
- [ ] Test variable pattern binding
- [ ] Test wildcard pattern
- [ ] Test pin pattern
- [ ] Test tuple pattern with nested elements
- [ ] Test list pattern with head|tail
- [ ] Test map pattern with various key types
- [ ] Test struct pattern (e.g., %User{name: name})
- [ ] Test binary pattern with specifiers
- [ ] Test guard clause extraction

## 3.4 Control Flow Extractors

This section extracts control flow expressions: if, unless, case, cond, with, try, receive.

### 3.4.1 Control Flow Extractor Module
- [ ] **Task 3.4.1 Complete**

Create extractors for all control flow expression types.

- [ ] 3.4.1.1 Create `lib/elixir_ontologies/extractors/control_flow.ex`
- [ ] 3.4.1.2 Extract `IfExpression` with condition, then branch, else branch
- [ ] 3.4.1.3 Extract `UnlessExpression` (syntactic negation of if)
- [ ] 3.4.1.4 Extract `CaseExpression` with matched value and clauses
- [ ] 3.4.1.5 Extract `CondExpression` with condition-body pairs
- [ ] 3.4.1.6 Extract `WithExpression` with match clauses and else
- [ ] 3.4.1.7 Extract `TryExpression` with body, rescue, catch, after clauses
- [ ] 3.4.1.8 Extract `RaiseExpression` with exception
- [ ] 3.4.1.9 Extract `ThrowExpression` with thrown value
- [ ] 3.4.1.10 Extract `ReceiveExpression` with patterns and timeout
- [ ] 3.4.1.11 Link clauses via `hasClause` property
- [ ] 3.4.1.12 Write control flow tests (success: 18 tests)

**Section 3.4 Unit Tests:**
- [ ] Test if/else extraction
- [ ] Test unless extraction
- [ ] Test case with multiple clauses
- [ ] Test cond extraction
- [ ] Test with expression including else clause
- [ ] Test try/rescue/after extraction
- [ ] Test receive with timeout

## 3.5 Comprehension and Block Extractors

This section extracts for comprehensions and block structures.

### 3.5.1 Comprehension Extractor
- [ ] **Task 3.5.1 Complete**

Extract for comprehensions with generators, filters, and into clauses.

- [ ] 3.5.1.1 Create `lib/elixir_ontologies/extractors/comprehension.ex`
- [ ] 3.5.1.2 Extract `ForComprehension` with body expression
- [ ] 3.5.1.3 Extract `Generator` (pattern <- enumerable)
- [ ] 3.5.1.4 Extract `BitstringGenerator` (pattern <<- bitstring)
- [ ] 3.5.1.5 Extract `Filter` (boolean expressions)
- [ ] 3.5.1.6 Link generators via `hasGenerator`
- [ ] 3.5.1.7 Link filters via `hasFilter`
- [ ] 3.5.1.8 Extract `:into` option as `hasIntoCollector`
- [ ] 3.5.1.9 Extract `:reduce` option
- [ ] 3.5.1.10 Write comprehension tests (success: 10 tests)

### 3.5.2 Block Extractor
- [ ] **Task 3.5.2 Complete**

Extract block structures with ordered expressions.

- [ ] 3.5.2.1 Create `lib/elixir_ontologies/extractors/block.ex`
- [ ] 3.5.2.2 Extract `Block` with contained expressions
- [ ] 3.5.2.3 Extract `DoBlock` from do...end syntax
- [ ] 3.5.2.4 Extract `FnBlock` from fn...end syntax
- [ ] 3.5.2.5 Add `containsExpression` relationships
- [ ] 3.5.2.6 Add `expressionOrder` for each contained expression
- [ ] 3.5.2.7 Write block tests (success: 8 tests)

**Section 3.5 Unit Tests:**
- [ ] Test for comprehension with single generator
- [ ] Test for comprehension with multiple generators
- [ ] Test for comprehension with filter
- [ ] Test for comprehension with :into
- [ ] Test do block extraction
- [ ] Test expression ordering in blocks

## 3.6 Variable and Reference Extractors

This section extracts variables, references, and function calls.

### 3.6.1 Variable and Reference Extractor
- [ ] **Task 3.6.1 Complete**

Extract variable bindings and various reference types.

- [ ] 3.6.1.1 Create `lib/elixir_ontologies/extractors/reference.ex`
- [ ] 3.6.1.2 Extract `Variable` with name
- [ ] 3.6.1.3 Extract `ModuleReference` (alias references)
- [ ] 3.6.1.4 Extract `FunctionReference` (captured functions)
- [ ] 3.6.1.5 Extract `RemoteCall` (Module.function(args))
- [ ] 3.6.1.6 Extract `LocalCall` (function(args))
- [ ] 3.6.1.7 Add `refersToModule`, `refersToFunction` properties
- [ ] 3.6.1.8 Track variable scope and rebinding
- [ ] 3.6.1.9 Write reference tests (success: 12 tests)

**Section 3.6 Unit Tests:**
- [ ] Test variable extraction
- [ ] Test module reference extraction
- [ ] Test function capture extraction (&Mod.fun/2)
- [ ] Test remote call extraction
- [ ] Test local call extraction

## Phase 3 Integration Tests

- [ ] Test extraction of module with all literal types
- [ ] Test extraction of function with complex patterns
- [ ] Test extraction of control flow heavy function
- [ ] Test extraction preserves source locations for all elements
- [ ] Test all core ontology classes have corresponding extractors
