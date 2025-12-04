# Elixir Structure Ontology Guide

**File**: `elixir-structure.ttl`
**Namespace**: `https://w3id.org/elixir-code/structure#`
**Prefix**: `struct:`

## Overview

The structure ontology models Elixir-specific code constructs: modules, functions, macros, protocols, behaviours, structs, and the type system. It captures the unique aspects of Elixir's design that distinguish it from other languages.

## Dependencies

```turtle
owl:imports <https://w3id.org/elixir-code/core>
```

Extends classes from `elixir-core.ttl` with Elixir-specific semantics.

## Module System

### Module Class

Modules are the primary unit of code organization in Elixir:

```turtle
struct:Module a owl:Class ;
    rdfs:subClassOf core:CodeElement ;
    skos:example "defmodule MyApp.Users do ... end"@en .
```

Key properties:
- `moduleName` - Fully qualified name (e.g., `"MyApp.Users"`)
- `containsFunction` - Functions defined in the module
- `containsMacro` - Macros defined in the module
- `containsType` - Type specifications
- `containsStruct` - The module's struct (if any)

### Nested Modules

```turtle
struct:NestedModule a owl:Class ;
    rdfs:subClassOf struct:Module .
```

Despite lexical nesting, nested modules are separate compilation units:

```elixir
defmodule Outer do
  defmodule Inner do  # Compiles as Outer.Inner, separate module
  end
end
```

Properties:
- `parentModule` - The lexically enclosing module
- `hasNestedModule` - Inverse relationship

### Module Directives

| Class | Purpose | Example |
|-------|---------|---------|
| `ModuleAlias` | Shortened module reference | `alias MyApp.Users, as: U` |
| `Import` | Bring functions into namespace | `import Enum, only: [map: 2]` |
| `Require` | Ensure module compiled for macros | `require Logger` |
| `Use` | Invoke `__using__/1` macro | `use GenServer` |

Properties:
- `aliasesModule`, `importsFrom`, `requiresModule`, `usesModule`

## Functions - The Heart of Elixir

### Function Identity

**Critical concept**: In Elixir, function identity is the triple `(Module, Name, Arity)`. Functions with the same name but different arities are completely different functions.

```turtle
struct:Function a owl:Class ;
    owl:hasKey ( struct:belongsTo struct:functionName struct:arity ) .
```

This `owl:hasKey` axiom declares the composite key—essential for proper reasoning.

### Function Types

```
Function
├── PublicFunction   # def - callable from outside
├── PrivateFunction  # defp - module-internal only
├── GuardFunction    # defguard/defguardp - usable in guards
└── DelegatedFunction # defdelegate - forwards to another module
```

### Function Clauses

Functions can have multiple clauses with different patterns:

```elixir
def factorial(0), do: 1
def factorial(n) when n > 0, do: n * factorial(n - 1)
```

**Order matters**—clauses are matched in source order, first match wins.

```turtle
struct:hasClauses a owl:ObjectProperty ;
    rdfs:domain struct:Function ;
    rdfs:range rdf:List .  # Ordered list preserving source order
```

Each clause has:
- `hasHead` - The function head (name, parameters, guards)
- `hasBody` - The implementation block
- `clauseOrder` - 1-indexed position in the function

### Parameters

```turtle
struct:Parameter a owl:Class ;
    rdfs:subClassOf core:CodeElement .

struct:DefaultParameter a owl:Class ;
    rdfs:subClassOf struct:Parameter .
```

Default parameters create multiple arities at compile time:

```elixir
def greet(name, greeting \\ "Hello")
# Creates both greet/1 and greet/2
```

Properties:
- `parameterPosition` - 0-indexed position
- `parameterName` - Variable name
- `hasDefaultValue` - Default expression (for DefaultParameter)

### Function Relationships

```turtle
struct:callsFunction a owl:ObjectProperty ;
    rdfs:domain struct:Function ;
    rdfs:range struct:Function .

struct:callsMacro a owl:ObjectProperty ;
    rdfs:domain struct:Function ;
    rdfs:range struct:Macro .
```

## Anonymous Functions

### AnonymousFunction

```turtle
struct:AnonymousFunction a owl:Class ;
    rdfs:subClassOf core:Closure .
```

Created with `fn...end` syntax, can have multiple clauses:

```elixir
fn
  {:ok, value} -> value
  {:error, _} -> nil
end
```

### Captured Functions

```turtle
struct:CapturedFunction a owl:Class ;
    rdfs:subClassOf core:FunctionReference .

struct:PartialApplication a owl:Class ;
    rdfs:subClassOf struct:CapturedFunction .
```

Examples:
- `&Enum.map/2` - Captures named function
- `&(&1 + 5)` - Partial application

## Protocols

Protocols enable type-based polymorphism—dispatch based on the first argument's type.

### Protocol Definition

```turtle
struct:Protocol a owl:Class ;
    rdfs:subClassOf core:CodeElement ;
    skos:example "defprotocol Size do def size(data) end"@en .
```

Properties:
- `protocolName` - Protocol module name
- `definesProtocolFunction` - Functions the protocol declares
- `fallbackToAny` - Whether to use `Any` implementation as fallback
- `isConsolidated` - Whether protocol is consolidated (production optimization)

### Protocol Implementation

```turtle
struct:ProtocolImplementation a owl:Class ;
    rdfs:subClassOf core:CodeElement .
```

Properties:
- `implementsProtocol` - Which protocol
- `forDataType` - Which data type (e.g., `List`, `Map`, `MyStruct`)

Implementation types:
- `DerivedImplementation` - Auto-generated via `@derive`
- `AnyImplementation` - Fallback for `Any` type

### Protocol vs Behaviour

| Aspect | Protocol | Behaviour |
|--------|----------|-----------|
| Dispatch | On data type (first arg) | On module |
| Definition | `defprotocol` | `@callback` in module |
| Implementation | `defimpl` per type | `@behaviour` + implement callbacks |
| Use case | Polymorphic functions | Module contracts |

## Behaviours

Behaviours define callback contracts that modules must implement.

### Behaviour Definition

```turtle
struct:Behaviour a owl:Class ;
    rdfs:subClassOf core:CodeElement .
```

Defined implicitly by declaring `@callback` specs:

```elixir
defmodule MyBehaviour do
  @callback required_function(arg :: term) :: term
  @callback optional_function() :: term
  @optional_callbacks optional_function: 0
end
```

### Callback Types

```
CallbackFunction
├── RequiredCallback  # Must be implemented
├── OptionalCallback  # May be implemented
└── MacroCallback     # Macro callback (@macrocallback)
```

### Behaviour Implementation

```turtle
struct:BehaviourImplementation a owl:Class .

struct:implementsBehaviour a owl:ObjectProperty ;
    rdfs:domain struct:Module ;
    rdfs:range struct:Behaviour .
```

Properties:
- `implementsCallback` - Links function to the callback it implements
- `overridesDefault` - For overriding default implementations

## Structs

### Struct Definition

```turtle
struct:Struct a owl:Class ;
    rdfs:subClassOf core:CodeElement .
```

Structs are maps with a fixed set of keys and a `__struct__` field:

```elixir
defmodule User do
  defstruct [:name, :email, active: true]
  @enforce_keys [:name]
end
```

Properties:
- `hasField` - The struct's fields
- `hasEnforcedKey` - Fields that must be provided
- `derivesProtocol` - Protocols derived via `@derive`

### Struct Fields

```turtle
struct:StructField a owl:Class .
struct:EnforcedKey a owl:Class ;
    rdfs:subClassOf struct:StructField .
```

Properties:
- `fieldName` - Atom name of the field
- `hasDefaultFieldValue` - Whether a default exists

### Exceptions

```turtle
struct:Exception a owl:Class ;
    rdfs:subClassOf struct:Struct .
```

Exceptions are structs that implement the `Exception` behaviour:

```elixir
defmodule MyError do
  defexception [:message, :code]
end
```

## Macros

### Macro Definition

```turtle
struct:Macro a owl:Class ;
    rdfs:subClassOf core:CodeElement .
```

Macros receive AST (quoted expressions) and return AST:

```elixir
defmacro unless(condition, do: block) do
  quote do
    if !unquote(condition), do: unquote(block)
  end
end
```

Types:
- `PublicMacro` - `defmacro`, usable from other modules
- `PrivateMacro` - `defmacrop`, module-internal

Properties:
- `macroName`, `macroArity` - Identity
- `isHygienic` - Whether macro maintains variable hygiene

### Quoted Expressions

```turtle
struct:QuotedExpression a owl:Class ;
    rdfs:subClassOf core:Expression .

struct:UnquoteExpression a owl:Class .
struct:UnquoteSplicingExpression a owl:Class .
```

- `quote do...end` creates AST representation
- `unquote()` injects values into quoted code
- `unquote_splicing()` injects and flattens lists

Properties:
- `quotesExpression` - The expression being quoted
- `unquotesValue` - The value being injected
- `quoteContext` - Context option (`:match`, `:guard`, etc.)

## Type System

### Type Specifications

```
TypeSpec
├── PublicType   # @type - visible externally
├── PrivateType  # @typep - module-internal
└── OpaqueType   # @opaque - structure hidden externally
```

Properties:
- `typeName` - The type's name
- `typeArity` - Number of type parameters
- `hasTypeVariable` - Type parameters

### Function Specs

```turtle
struct:FunctionSpec a owl:Class ;
    rdfs:subClassOf struct:ModuleAttribute .
```

```elixir
@spec add(integer, integer) :: integer
```

Properties:
- `hasParameterType` - Types of parameters
- `hasReturnType` - Return type

### Type Expressions

```
TypeExpression
├── BasicType          # atom(), integer(), binary()
├── UnionType          # type1 | type2
├── TupleType          # {type1, type2}
├── ListType           # [type]
├── MapType            # %{key => value}
├── FunctionType       # (args -> return)
├── ParameterizedType  # Enumerable.t(element)
├── TypeVariable       # Polymorphic variable
└── WhenClauseType     # Type constraints
```

## Module Attributes

### Documentation

```
DocAttribute
├── ModuledocAttribute  # @moduledoc
└── TypedocAttribute    # @typedoc
```

Plus `@doc` for function documentation.

### Lifecycle Attributes

| Attribute | Purpose |
|-----------|---------|
| `DeprecatedAttribute` | Mark as deprecated |
| `SinceAttribute` | Version when added |
| `ExternalResourceAttribute` | Files affecting compilation |
| `CompileAttribute` | Compilation options |

### Callback Hooks

| Attribute | When Called |
|-----------|-------------|
| `OnDefinitionAttribute` | After each function/macro definition |
| `BeforeCompileAttribute` | Before module compilation completes |
| `AfterCompileAttribute` | After module compilation |

### Registered Attributes

```turtle
struct:RegisteredAttribute a owl:Class ;
    rdfs:subClassOf struct:ModuleAttribute .

struct:AccumulatingAttribute a owl:Class ;
    rdfs:subClassOf struct:RegisteredAttribute .
```

Properties:
- `isAccumulating` - Whether values accumulate vs replace
- `persistToRuntime` - Whether available at runtime

## OWL Axioms

### Required Properties

```turtle
# Every function must have arity
struct:Function rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty struct:arity ;
    owl:cardinality 1
] .

# Every function must belong to a module
struct:Function rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty struct:belongsTo ;
    owl:cardinality 1
] .

# Every function must have at least one clause
struct:Function rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty struct:hasClause ;
    owl:minCardinality 1
] .
```

### Protocol Implementation Constraints

```turtle
struct:ProtocolImplementation rdfs:subClassOf [
    a owl:Restriction ;
    owl:onProperty struct:implementsProtocol ;
    owl:cardinality 1
] , [
    a owl:Restriction ;
    owl:onProperty struct:forDataType ;
    owl:cardinality 1
] .
```

## Relationship to Other Modules

### Imports

- `elixir-core.ttl` - Base AST and expression classes

### Imported By

- `elixir-otp.ttl` - Extends with OTP behaviours (GenServer, Supervisor)
- `elixir-evolution.ttl` - Adds versioning to modules and functions

### Extension Examples

```turtle
# In elixir-otp.ttl
otp:GenServer a owl:Class ;
    rdfs:subClassOf struct:Behaviour .

otp:GenServerImplementation a owl:Class ;
    rdfs:subClassOf struct:BehaviourImplementation .
```

## Usage Examples

### Modeling a Function

```elixir
def greet(name, greeting \\ "Hello") do
  "#{greeting}, #{name}!"
end
```

```turtle
ex:greet2 a struct:PublicFunction ;
    struct:belongsTo ex:GreeterModule ;
    struct:functionName "greet" ;
    struct:arity 2 ;
    struct:minArity 1 ;  # Due to default
    struct:hasClauses ( ex:greetClause1 ) .

ex:greetClause1 a struct:FunctionClause ;
    struct:clauseOrder 1 ;
    struct:hasHead ex:greetHead ;
    struct:hasBody ex:greetBody .

ex:greetHead a struct:FunctionHead ;
    struct:hasParameter ex:nameParam, ex:greetingParam .

ex:greetingParam a struct:DefaultParameter ;
    struct:parameterName "greeting" ;
    struct:parameterPosition 1 ;
    struct:hasDefaultValue ex:helloLiteral .
```

### Modeling a Protocol Implementation

```elixir
defimpl Size, for: BitString do
  def size(string), do: byte_size(string)
end
```

```turtle
ex:sizeForBitString a struct:ProtocolImplementation ;
    struct:implementsProtocol ex:SizeProtocol ;
    struct:forDataType ex:BitStringType ;
    struct:containsFunction ex:sizeImpl .
```

## Design Rationale

1. **Arity as identity**: Functions are keyed by (module, name, arity) via `owl:hasKey`
2. **Ordered clauses**: `rdf:List` preserves pattern matching order
3. **Protocol/Behaviour distinction**: Different dispatch mechanisms need different models
4. **Macro awareness**: First-class representation of metaprogramming constructs
5. **Type system integration**: Specs and types are part of the semantic model
