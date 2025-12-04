# Elixir Core Ontology Guide

**File**: `elixir-core.ttl`
**Namespace**: `https://w3id.org/elixir-code/core#`
**Prefix**: `core:`

## Overview

The core ontology provides language-agnostic foundations for representing source code as a semantic knowledge graph. It models Abstract Syntax Tree (AST) primitives, expressions, patterns, and scoping constructs that apply across programming languages while being tailored for Elixir's expression-oriented nature.

This is the foundational layer—all other ontology modules import it.

## Foundational Alignment

### BFO Integration

The ontology aligns with Basic Formal Ontology (BFO), an ISO standard (ISO/IEC 21838-2) used by 350+ ontologies:

```turtle
core:CodeElement a owl:Class ;
    rdfs:subClassOf bfo:BFO_0000031 .  # Generically Dependent Continuant
```

Code elements are modeled as **Generically Dependent Continuants**—abstract content that can be realized in multiple physical carriers (source files, compiled bytecode, memory representations).

Related BFO alignments:
- `SourceLocation` → `bfo:BFO_0000006` (Spatial Region)
- `SourceFile` → `bfo:BFO_0000030` (Object - physical carrier)

## Class Hierarchy

### AST Node Structure

```
CodeElement
└── ASTNode
    ├── Expression
    │   ├── Literal
    │   ├── OperatorExpression
    │   ├── ControlFlowExpression
    │   ├── Comprehension
    │   ├── Variable
    │   ├── Reference
    │   ├── Block
    │   └── Guard
    ├── Statement
    ├── Declaration
    └── Pattern
```

In Elixir, almost everything is an expression that returns a value. The `Statement` class exists for constructs evaluated primarily for side effects.

### Literal Types

Elixir has rich literal syntax. Each type has its own class:

| Class | Description | Example |
|-------|-------------|---------|
| `AtomLiteral` | Constants whose name is their value | `:ok`, `:error`, `true` |
| `IntegerLiteral` | Integers in any base | `42`, `0xFF`, `0b1010` |
| `FloatLiteral` | Floating-point numbers | `3.14`, `1.0e-10` |
| `StringLiteral` | UTF-8 binary strings | `"hello"` |
| `CharlistLiteral` | Lists of codepoints | `'hello'` |
| `BinaryLiteral` | Binaries/bitstrings | `<<1, 2, 3>>` |
| `ListLiteral` | Linked lists | `[1, 2, 3]` |
| `TupleLiteral` | Fixed-size tuples | `{:ok, value}` |
| `MapLiteral` | Key-value maps | `%{a: 1, b: 2}` |
| `KeywordListLiteral` | Atom-keyed lists | `[name: "John"]` |
| `SigilLiteral` | Sigil expressions | `~r/pattern/`, `~w(a b c)` |
| `RangeLiteral` | Range structs | `1..10`, `1..10//2` |

All literal types are declared disjoint via `owl:AllDisjointClasses`.

### Operator Expressions

Operators are categorized by semantics:

```
OperatorExpression
├── UnaryOperator       # Single operand: not, !, -, +
├── BinaryOperator      # Two operands (base class)
├── ArithmeticOperator  # +, -, *, /, div, rem
├── ComparisonOperator  # ==, !=, ===, !==, <, >, <=, >=
├── LogicalOperator     # and, or, not, &&, ||, !
├── PipeOperator        # |> (passes result as first arg)
├── MatchOperator       # = (pattern matching)
├── CaptureOperator     # & (function capture)
├── StringConcatOperator # <> (binary concatenation)
├── ListOperator        # ++ (concat), -- (subtract)
└── InOperator          # in (membership test)
```

The `PipeOperator` is central to Elixir's idioms—it threads the result of the left expression as the first argument to the right.

### Control Flow

Elixir's control flow constructs are all expressions:

| Class | Description |
|-------|-------------|
| `IfExpression` | Conditional with optional else |
| `UnlessExpression` | Negated conditional |
| `CaseExpression` | Pattern matching on a value |
| `CondExpression` | Multi-branch boolean conditions |
| `WithExpression` | Monadic binding with early return |
| `TryExpression` | Exception handling |
| `RaiseExpression` | Raises an exception |
| `ThrowExpression` | Throws a value (non-local return) |
| `ReceiveExpression` | Process mailbox pattern matching |

`WithExpression` is particularly important for Elixir—it enables clean error handling by short-circuiting on pattern match failure.

## Pattern Matching

Pattern matching is fundamental to Elixir. The ontology models patterns as first-class entities:

```
Pattern
├── LiteralPattern    # Match specific value: 0, :ok
├── VariablePattern   # Bind to variable: x, name
├── WildcardPattern   # Discard: _
├── PinPattern        # Match existing value: ^x
├── TuplePattern      # Match tuple: {a, b}
├── ListPattern       # Match list: [h | t]
├── MapPattern        # Match map keys: %{key: v}
├── StructPattern     # Match struct: %User{name: n}
├── BinaryPattern     # Match binary: <<x::8, rest::binary>>
└── AsPattern         # Bind whole + destructure: %User{} = user
```

### Guard Expressions

Guards constrain pattern matches with boolean expressions:

```turtle
core:Guard a owl:Class ;
    rdfs:comment "A boolean expression constraining a pattern match. Only
    a limited set of expressions are allowed in guards."@en ;
    rdfs:subClassOf core:Expression .
```

Only guard-safe expressions (comparisons, type checks, arithmetic, certain BIFs) are valid in guards.

## Scoping Model

Elixir has three scope levels:

```turtle
core:Scope
├── ModuleScope    # Module-level: attributes, functions
├── FunctionScope  # Function body
└── BlockScope     # do/end, fn/end, comprehensions
```

Key properties:
- `parentScope` - Links nested scopes
- `ancestorScope` - Transitive closure (via property chain)
- `hasBinding` - Variables bound in the scope
- `capturesVariable` - For closures capturing outer variables

## Key Properties

### Source Location and References

Every code element can have a source location and direct links to source files:

```turtle
core:hasSourceLocation a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain core:CodeElement ;
    rdfs:range core:SourceLocation .

core:hasSourceFile a owl:ObjectProperty, owl:FunctionalProperty ;
    rdfs:domain core:CodeElement ;
    rdfs:range core:SourceFile .  # Direct shortcut
```

Location properties:
- `startLine`, `endLine` - Line numbers (1-indexed)
- `startColumn`, `endColumn` - Column positions
- `inSourceFile` - Reference to the source file (from SourceLocation)
- `filePath` - Absolute file system path
- `relativeFilePath` - Path relative to repository root
- `sourceUrl` - Direct URL to view the code (e.g., GitHub permalink)

### Repository and Version Control

Source files can be linked to their repository and specific commits:

```turtle
core:Repository a owl:Class .
core:CommitRef a owl:Class .
```

**Repository properties:**
- `repositoryUrl` - URL of the repository (e.g., `https://github.com/elixir-lang/elixir`)
- `repositoryName` - Name of the repository

**Commit properties:**
- `commitSha` - Full SHA hash of the commit
- `commitTag` - Tag name (e.g., `v1.15.0`)
- `branchName` - Branch name (e.g., `main`)

**Relationship chain:**
```
CodeElement --hasSourceFile--> SourceFile --inRepository--> Repository
                                    |
                                    +--atCommit--> CommitRef
```

Example:
```turtle
ex:myFunction core:hasSourceFile ex:usersFile ;
    core:sourceUrl "https://github.com/org/app/blob/abc123/lib/users.ex#L10-L25"^^xsd:anyURI .

ex:usersFile a core:SourceFile ;
    core:filePath "/home/dev/app/lib/users.ex" ;
    core:relativeFilePath "lib/users.ex" ;
    core:inRepository ex:appRepo ;
    core:atCommit ex:commit123 .

ex:appRepo a core:Repository ;
    core:repositoryUrl "https://github.com/org/app"^^xsd:anyURI ;
    core:repositoryName "app" .

ex:commit123 a core:CommitRef ;
    core:commitSha "abc123def456..." ;
    core:commitTag "v1.0.0" ;
    core:branchName "main" .
```

### AST Structure

The AST is modeled with parent-child relationships:

```turtle
core:hasChild a owl:ObjectProperty ;
    rdfs:domain core:ASTNode ;
    rdfs:range core:ASTNode .

core:hasParent a owl:ObjectProperty ;
    owl:inverseOf core:hasChild .
```

Specialized properties for operators:
- `hasLeftOperand`, `hasRightOperand` - For binary operators
- `hasOperand` - For unary operators

### Blocks and Expressions

Blocks contain ordered expressions:

```turtle
core:containsExpression a owl:ObjectProperty ;
    rdfs:domain core:Block ;
    rdfs:range core:Expression .

core:expressionOrder a owl:DatatypeProperty ;
    rdfs:comment "The position of an expression within a block (1-indexed)."@en .
```

## OWL Axioms

### Cardinality Constraints

```turtle
# Binary operators must have exactly two operands
core:BinaryOperator rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty core:hasLeftOperand ;
    owl:cardinality 1
] , [
    a owl:Restriction ;
    owl:onProperty core:hasRightOperand ;
    owl:cardinality 1
] .

# If expression must have condition and then branch
core:IfExpression rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty core:hasCondition ;
    owl:cardinality 1
] , [
    a owl:Restriction ;
    owl:onProperty core:hasThenBranch ;
    owl:cardinality 1
] .
```

### Property Chains

Scope ancestry is computed via property chain:

```turtle
core:ancestorScope a owl:ObjectProperty, owl:TransitiveProperty ;
    owl:propertyChainAxiom ( core:parentScope core:ancestorScope ) .
```

## Relationship to Other Modules

### Imported By

- **elixir-structure.ttl** - Extends with Elixir-specific constructs (Module, Function, Protocol)
- **elixir-otp.ttl** - Indirectly via structure
- **elixir-evolution.ttl** - Indirectly via structure

### Extension Pattern

Other modules extend core classes:

```turtle
# In elixir-structure.ttl
struct:Function a owl:Class ;
    rdfs:subClassOf core:CodeElement .

struct:FunctionBody a owl:Class ;
    rdfs:subClassOf core:Block .
```

## Usage Examples

### Representing a Simple Expression

The expression `x + 1`:

```turtle
ex:expr1 a core:ArithmeticOperator ;
    core:operatorSymbol "+" ;
    core:hasLeftOperand ex:varX ;
    core:hasRightOperand ex:literal1 ;
    core:hasSourceLocation ex:loc1 .

ex:varX a core:Variable ;
    core:name "x" .

ex:literal1 a core:IntegerLiteral ;
    core:integerValue 1 .
```

### Representing a Pattern Match

The pattern `{:ok, value}`:

```turtle
ex:pattern1 a core:TuplePattern ;
    core:hasChild ex:okPattern, ex:valuePattern .

ex:okPattern a core:LiteralPattern ;
    core:atomValue "ok" .

ex:valuePattern a core:VariablePattern ;
    core:bindsVariable ex:valueVar .

ex:valueVar a core:Variable ;
    core:name "value" .
```

## Design Rationale

1. **Expression-centric**: Elixir is expression-oriented; almost everything returns a value
2. **Pattern-first**: Patterns are first-class, not just syntax sugar
3. **Scope tracking**: Essential for understanding variable visibility and closures
4. **BFO alignment**: Enables interoperability with other BFO-based ontologies
5. **Language-agnostic base**: Core concepts apply to other functional languages
6. **Source traceability**: Direct links from code elements to source files, repositories, and commits enable full provenance tracking
