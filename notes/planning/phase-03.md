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
- [x] **Task 3.2.1 Complete**

Create extractors for all operator types with operand relationships.

- [x] 3.2.1.1 Create `lib/elixir_ontologies/extractors/operator.ex`
- [x] 3.2.1.2 Define operator classification map (symbol → class)
- [x] 3.2.1.3 Implement `Operator.extract/1` dispatching by operator
- [x] 3.2.1.4 Extract `ArithmeticOperator` (+, -, *, /, div, rem)
- [x] 3.2.1.5 Extract `ComparisonOperator` (==, !=, ===, !==, <, >, <=, >=)
- [x] 3.2.1.6 Extract `LogicalOperator` (and, or, not, &&, ||, !)
- [x] 3.2.1.7 Extract `PipeOperator` (|>)
- [x] 3.2.1.8 Extract `MatchOperator` (=)
- [x] 3.2.1.9 Extract `CaptureOperator` (&)
- [x] 3.2.1.10 Extract `StringConcatOperator` (<>)
- [x] 3.2.1.11 Extract `ListOperator` (++, --)
- [x] 3.2.1.12 Extract `InOperator` (in)
- [x] 3.2.1.13 Add `hasLeftOperand`, `hasRightOperand` for binary operators
- [x] 3.2.1.14 Add `hasOperand` for unary operators
- [x] 3.2.1.15 Add `operatorSymbol` data property
- [x] 3.2.1.16 Write operator tests (success: 92 tests - 35 doctests + 57 unit tests)

**Section 3.2 Unit Tests:**
- [x] Test arithmetic operator extraction
- [x] Test comparison operator extraction
- [x] Test logical operator extraction
- [x] Test pipe operator with left/right operands
- [x] Test match operator extraction
- [x] Test capture operator extraction
- [x] Test unary operator (not, !) extraction

## 3.3 Pattern Extractors

This section extracts pattern matching constructs which are fundamental to Elixir.

### 3.3.1 Pattern Extractor Module
- [x] **Task 3.3.1 Complete**

Create extractors for all 11 pattern types.

- [x] 3.3.1.1 Create `lib/elixir_ontologies/extractors/pattern.ex`
- [x] 3.3.1.2 Implement `Pattern.extract/1` dispatching by pattern type
- [x] 3.3.1.3 Extract `LiteralPattern` with matched value
- [x] 3.3.1.4 Extract `VariablePattern` with `bindsVariable` property
- [x] 3.3.1.5 Extract `WildcardPattern` (_)
- [x] 3.3.1.6 Extract `PinPattern` (^var) with `pinsVariable` property
- [x] 3.3.1.7 Extract `TuplePattern` with nested patterns
- [x] 3.3.1.8 Extract `ListPattern` including head|tail decomposition
- [x] 3.3.1.9 Extract `MapPattern` with key patterns
- [x] 3.3.1.10 Extract `StructPattern` with struct name and field patterns
- [x] 3.3.1.11 Extract `BinaryPattern` with size/type specifiers
- [x] 3.3.1.12 Extract `AsPattern` (pattern = var)
- [x] 3.3.1.13 Extract `Guard` and `GuardClause`
- [x] 3.3.1.14 Write pattern tests (success: 110 tests - 30 doctests + 80 unit tests)

**Section 3.3 Unit Tests:**
- [x] Test variable pattern binding
- [x] Test wildcard pattern
- [x] Test pin pattern
- [x] Test tuple pattern with nested elements
- [x] Test list pattern with head|tail
- [x] Test map pattern with various key types
- [x] Test struct pattern (e.g., %User{name: name})
- [x] Test binary pattern with specifiers
- [x] Test guard clause extraction

## 3.4 Control Flow Extractors

This section extracts control flow expressions: if, unless, case, cond, with, try, receive.

### 3.4.1 Control Flow Extractor Module
- [x] **Task 3.4.1 Complete**

Create extractors for all control flow expression types.

- [x] 3.4.1.1 Create `lib/elixir_ontologies/extractors/control_flow.ex`
- [x] 3.4.1.2 Extract `IfExpression` with condition, then branch, else branch
- [x] 3.4.1.3 Extract `UnlessExpression` (syntactic negation of if)
- [x] 3.4.1.4 Extract `CaseExpression` with matched value and clauses
- [x] 3.4.1.5 Extract `CondExpression` with condition-body pairs
- [x] 3.4.1.6 Extract `WithExpression` with match clauses and else
- [x] 3.4.1.7 Extract `TryExpression` with body, rescue, catch, after clauses
- [x] 3.4.1.8 Extract `RaiseExpression` with exception
- [x] 3.4.1.9 Extract `ThrowExpression` with thrown value
- [x] 3.4.1.10 Extract `ReceiveExpression` with patterns and timeout
- [x] 3.4.1.11 Link clauses via `hasClause` property
- [x] 3.4.1.12 Write control flow tests (success: 92 tests - 27 doctests + 65 unit tests)

**Section 3.4 Unit Tests:**
- [x] Test if/else extraction
- [x] Test unless extraction
- [x] Test case with multiple clauses
- [x] Test cond extraction
- [x] Test with expression including else clause
- [x] Test try/rescue/after extraction
- [x] Test receive with timeout

## 3.5 Comprehension and Block Extractors

This section extracts for comprehensions and block structures.

### 3.5.1 Comprehension Extractor
- [x] **Task 3.5.1 Complete**

Extract for comprehensions with generators, filters, and into clauses.

- [x] 3.5.1.1 Create `lib/elixir_ontologies/extractors/comprehension.ex`
- [x] 3.5.1.2 Extract `ForComprehension` with body expression
- [x] 3.5.1.3 Extract `Generator` (pattern <- enumerable)
- [x] 3.5.1.4 Extract `BitstringGenerator` (pattern <<- bitstring)
- [x] 3.5.1.5 Extract `Filter` (boolean expressions)
- [x] 3.5.1.6 Link generators via `hasGenerator`
- [x] 3.5.1.7 Link filters via `hasFilter`
- [x] 3.5.1.8 Extract `:into` option as `hasIntoCollector`
- [x] 3.5.1.9 Extract `:reduce` option
- [x] 3.5.1.10 Write comprehension tests (success: 65 tests - 21 doctests + 44 unit tests)

### 3.5.2 Block Extractor
- [x] **Task 3.5.2 Complete**

Extract block structures with ordered expressions.

- [x] 3.5.2.1 Create `lib/elixir_ontologies/extractors/block.ex`
- [x] 3.5.2.2 Extract `Block` with contained expressions
- [x] 3.5.2.3 Extract `DoBlock` from do...end syntax
- [x] 3.5.2.4 Extract `FnBlock` from fn...end syntax
- [x] 3.5.2.5 Add `containsExpression` relationships
- [x] 3.5.2.6 Add `expressionOrder` for each contained expression
- [x] 3.5.2.7 Write block tests (success: 67 tests - 22 doctests + 45 unit tests)

**Section 3.5 Unit Tests:**
- [x] Test for comprehension with single generator
- [x] Test for comprehension with multiple generators
- [x] Test for comprehension with filter
- [x] Test for comprehension with :into
- [x] Test do block extraction
- [x] Test expression ordering in blocks

## 3.6 Variable and Reference Extractors

This section extracts variables, references, and function calls.

### 3.6.1 Variable and Reference Extractor
- [x] **Task 3.6.1 Complete**

Extract variable bindings and various reference types.

- [x] 3.6.1.1 Create `lib/elixir_ontologies/extractors/reference.ex`
- [x] 3.6.1.2 Extract `Variable` with name
- [x] 3.6.1.3 Extract `ModuleReference` (alias references)
- [x] 3.6.1.4 Extract `FunctionReference` (captured functions)
- [x] 3.6.1.5 Extract `RemoteCall` (Module.function(args))
- [x] 3.6.1.6 Extract `LocalCall` (function(args))
- [x] 3.6.1.7 Add `refersToModule`, `refersToFunction` properties
- [x] 3.6.1.8 Track variable scope and rebinding
- [x] 3.6.1.9 Write reference tests (success: 104 tests - 43 doctests + 61 unit tests)

**Section 3.6 Unit Tests:**
- [x] Test variable extraction
- [x] Test module reference extraction
- [x] Test function capture extraction (&Mod.fun/2)
- [x] Test remote call extraction
- [x] Test local call extraction

## Phase 3 Integration Tests

- [x] Test extraction of module with all literal types (12 tests)
- [x] Test extraction of function with complex patterns (11 tests)
- [x] Test extraction of control flow heavy function (10 tests)
- [x] Test extraction preserves source locations for all elements (5 tests)
- [x] Test all core ontology classes have corresponding extractors (7 tests)
- [x] Cross-extractor integration scenarios (5 tests)

**Total: 69 integration tests passing**
