# Phase 14: Type System Completion

This phase completes the type system extraction and building capabilities. While basic type definitions and function specs are extracted, complex type expressions like unions, intersections, generics, and remote types are not fully captured. This phase implements comprehensive type expression parsing and RDF generation for the full type system ontology.

## 14.1 Type Expression Enhancement

This section enhances the TypeExpression extractor to handle all type expression forms defined in the elixir-structure.ttl ontology, including composite types, parameterized types, and special forms.

### 14.1.1 Union and Intersection Types
- [ ] **Task 14.1.1 Pending**

Extract union types (|) and intersection type information from typespecs, representing the full type algebra.

- [ ] 14.1.1.1 Update `lib/elixir_ontologies/extractors/type_expression.ex` to detect union type AST patterns
- [ ] 14.1.1.2 Implement `extract_union_type/1` returning `%{type: :union, types: [...]}`
- [ ] 14.1.1.3 Handle nested unions (flattening `a | b | c` into single union)
- [ ] 14.1.1.4 Extract type positions for each union member
- [ ] 14.1.1.5 Create `%TypeExpression{kind: :union}` struct variant
- [ ] 14.1.1.6 Add union type support to existing tests

### 14.1.2 Parameterized Types (Generics)
- [ ] **Task 14.1.2 Pending**

Extract parameterized types like `list(integer())`, `map(atom(), binary())`, and user-defined generic types.

- [ ] 14.1.2.1 Implement `extract_parameterized_type/1` for built-in parameterized types
- [ ] 14.1.2.2 Handle `list(t)`, `map(k, v)`, `keyword(t)`, `tuple()` patterns
- [ ] 14.1.2.3 Extract type parameters and their positions
- [ ] 14.1.2.4 Support nested parameterized types (e.g., `list(map(atom(), integer()))`)
- [ ] 14.1.2.5 Create `%TypeExpression{kind: :parameterized, base_type: ..., parameters: [...]}` struct
- [ ] 14.1.2.6 Add parameterized type tests

### 14.1.3 Remote Types
- [ ] **Task 14.1.3 Pending**

Extract remote type references like `String.t()`, `Enum.t()`, and qualified type names from external modules.

- [ ] 14.1.3.1 Implement `extract_remote_type/1` detecting `Module.type()` AST pattern
- [ ] 14.1.3.2 Extract module reference as IRI-compatible format
- [ ] 14.1.3.3 Extract type name and arity
- [ ] 14.1.3.4 Handle parameterized remote types (e.g., `GenServer.on_start()`)
- [ ] 14.1.3.5 Create `%TypeExpression{kind: :remote, module: ..., type_name: ..., arity: ...}` struct
- [ ] 14.1.3.6 Add remote type tests

### 14.1.4 Type Variables and Constraints
- [ ] **Task 14.1.4 Pending**

Extract type variables used in polymorphic type definitions and their `when` constraints.

- [ ] 14.1.4.1 Implement `extract_type_variable/1` for lowercase type names in specs
- [ ] 14.1.4.2 Parse `when` clauses to extract type variable constraints
- [ ] 14.1.4.3 Track type variable scope (function-level vs type-level)
- [ ] 14.1.4.4 Extract constraint relationships (e.g., `when a: integer()`)
- [ ] 14.1.4.5 Create `%TypeVariable{name: ..., constraints: [...]}` struct
- [ ] 14.1.4.6 Add type variable and constraint tests

**Section 14.1 Unit Tests:**
- [ ] Test union type extraction for `integer() | atom()`
- [ ] Test nested union flattening
- [ ] Test parameterized type extraction for `list(integer())`
- [ ] Test nested parameterized types
- [ ] Test remote type extraction for `String.t()`
- [ ] Test type variable detection
- [ ] Test `when` constraint parsing
- [ ] Test complex type expressions combining all forms

## 14.2 Special Type Forms

This section handles special type forms defined in the ontology including function types, struct types, tuple types with specific arities, and literal types.

### 14.2.1 Function Types
- [ ] **Task 14.2.1 Pending**

Extract function type signatures like `(integer() -> atom())` used in higher-order function specs.

- [ ] 14.2.1.1 Implement `extract_function_type/1` for arrow syntax in types
- [ ] 14.2.1.2 Extract parameter types list
- [ ] 14.2.1.3 Extract return type
- [ ] 14.2.1.4 Handle multiple arities (e.g., `(-> atom()) | (integer() -> atom())`)
- [ ] 14.2.1.5 Create `%TypeExpression{kind: :function_type, params: [...], return: ...}` struct
- [ ] 14.2.1.6 Add function type tests

### 14.2.2 Struct Types
- [ ] **Task 14.2.2 Pending**

Extract struct type references like `%User{}` and `%User{name: String.t()}` in typespecs.

- [ ] 14.2.2.1 Implement `extract_struct_type/1` for struct pattern in types
- [ ] 14.2.2.2 Extract struct module reference
- [ ] 14.2.2.3 Extract optional field type constraints
- [ ] 14.2.2.4 Handle `t()` convention for struct types
- [ ] 14.2.2.5 Create `%TypeExpression{kind: :struct_type, module: ..., fields: [...]}` struct
- [ ] 14.2.2.6 Add struct type tests

### 14.2.3 Literal Types
- [ ] **Task 14.2.3 Pending**

Extract literal type values like `:ok`, `1..10`, and specific atom/integer literals in types.

- [ ] 14.2.3.1 Implement `extract_literal_type/1` for atom literals in types
- [ ] 14.2.3.2 Handle integer literal types (specific values)
- [ ] 14.2.3.3 Handle range literal types (`1..100`)
- [ ] 14.2.3.4 Handle binary literal types with size specifications
- [ ] 14.2.3.5 Create `%TypeExpression{kind: :literal, value: ...}` struct
- [ ] 14.2.3.6 Add literal type tests

### 14.2.4 Tuple Types
- [ ] **Task 14.2.4 Pending**

Extract tuple types with specific element types like `{:ok, result}` and `{atom(), integer(), binary()}`.

- [ ] 14.2.4.1 Implement `extract_tuple_type/1` for fixed-arity tuples
- [ ] 14.2.4.2 Extract element types in order
- [ ] 14.2.4.3 Handle tagged tuples (e.g., `{:ok, t}`, `{:error, reason}`)
- [ ] 14.2.4.4 Distinguish from generic `tuple()` type
- [ ] 14.2.4.5 Create `%TypeExpression{kind: :tuple, elements: [...]}` struct
- [ ] 14.2.4.6 Add tuple type tests

**Section 14.2 Unit Tests:**
- [ ] Test function type extraction `(integer() -> atom())`
- [ ] Test multi-arity function types
- [ ] Test struct type extraction `%User{}`
- [ ] Test struct type with field constraints
- [ ] Test literal atom type `:ok`
- [ ] Test literal range type `1..10`
- [ ] Test tuple type `{atom(), integer()}`
- [ ] Test tagged tuple patterns

## 14.3 Type System Builder Enhancement

This section enhances the TypeSystemBuilder to generate RDF triples for all extracted type information, linking to the appropriate ontology classes.

### 14.3.1 Union Type Builder
- [ ] **Task 14.3.1 Pending**

Generate RDF triples for union types using the structure:UnionType class and hasUnionMember property.

- [ ] 14.3.1.1 Update `lib/elixir_ontologies/builders/type_system_builder.ex`
- [ ] 14.3.1.2 Implement `build_union_type/3` generating union type IRI
- [ ] 14.3.1.3 Generate `rdf:type structure:UnionType` triple
- [ ] 14.3.1.4 Generate `structure:hasUnionMember` triples for each member type
- [ ] 14.3.1.5 Handle recursive building for nested type expressions
- [ ] 14.3.1.6 Add union type builder tests

### 14.3.2 Parameterized Type Builder
- [ ] **Task 14.3.2 Pending**

Generate RDF triples for parameterized types using structure:ParameterizedType class.

- [ ] 14.3.2.1 Implement `build_parameterized_type/3` generating type IRI
- [ ] 14.3.2.2 Generate `rdf:type structure:ParameterizedType` triple
- [ ] 14.3.2.3 Generate `structure:hasBaseType` linking to base type
- [ ] 14.3.2.4 Generate `structure:hasTypeParameter` triples with ordering
- [ ] 14.3.2.5 Handle nested parameterized types recursively
- [ ] 14.3.2.6 Add parameterized type builder tests

### 14.3.3 Remote Type Builder
- [ ] **Task 14.3.3 Pending**

Generate RDF triples for remote type references linking to external modules.

- [ ] 14.3.3.1 Implement `build_remote_type/3` generating remote type IRI
- [ ] 14.3.3.2 Generate `rdf:type structure:RemoteType` triple
- [ ] 14.3.3.3 Generate `structure:referencesModule` linking to module IRI
- [ ] 14.3.3.4 Generate `structure:referencesType` with type name
- [ ] 14.3.3.5 Handle remote types that may not be in current analysis scope
- [ ] 14.3.3.6 Add remote type builder tests

### 14.3.4 Type Variable Builder
- [ ] **Task 14.3.4 Pending**

Generate RDF triples for type variables and their constraints.

- [ ] 14.3.4.1 Implement `build_type_variable/3` generating variable IRI
- [ ] 14.3.4.2 Generate `rdf:type structure:TypeVariable` triple
- [ ] 14.3.4.3 Generate `structure:variableName` with variable name
- [ ] 14.3.4.4 Generate `structure:hasConstraint` triples for each constraint
- [ ] 14.3.4.5 Link constraints to their type expressions
- [ ] 14.3.4.6 Add type variable builder tests

**Section 14.3 Unit Tests:**
- [ ] Test union type RDF generation
- [ ] Test parameterized type RDF generation
- [ ] Test remote type RDF generation
- [ ] Test type variable RDF generation
- [ ] Test constraint RDF generation
- [ ] Test complex nested type RDF generation
- [ ] Test type IRI uniqueness and stability
- [ ] Test integration with function spec builder

## 14.4 Typespec Completeness

This section ensures complete typespec coverage including callback specs, optional callbacks, and macro callbacks.

### 14.4.1 Callback Spec Enhancement
- [ ] **Task 14.4.1 Pending**

Enhance callback spec extraction to capture full type information and optional callback markers.

- [ ] 14.4.1.1 Update `lib/elixir_ontologies/extractors/function_spec.ex` for callbacks
- [ ] 14.4.1.2 Extract `@callback` with full type expression
- [ ] 14.4.1.3 Extract `@optional_callback` list
- [ ] 14.4.1.4 Extract `@macrocallback` definitions
- [ ] 14.4.1.5 Link callbacks to their behaviours
- [ ] 14.4.1.6 Add callback spec tests

### 14.4.2 Spec Builder Enhancement
- [ ] **Task 14.4.2 Pending**

Enhance spec builder to generate complete RDF for all spec types.

- [ ] 14.4.2.1 Update TypeSystemBuilder for callback specs
- [ ] 14.4.2.2 Generate `rdf:type structure:CallbackSpec` triple
- [ ] 14.4.2.3 Generate `rdf:type structure:OptionalCallbackSpec` for optional callbacks
- [ ] 14.4.2.4 Generate `rdf:type structure:MacroCallbackSpec` for macro callbacks
- [ ] 14.4.2.5 Generate `structure:definedBy` linking to behaviour
- [ ] 14.4.2.6 Add spec builder tests

**Section 14.4 Unit Tests:**
- [ ] Test callback spec extraction
- [ ] Test optional callback extraction
- [ ] Test macro callback extraction
- [ ] Test callback RDF generation
- [ ] Test callback-to-behaviour linking
- [ ] Test multi-clause callback specs

## Phase 14 Integration Tests

- [ ] **Phase 14 Integration Tests** (15+ tests)

- [ ] Test complete type extraction for complex module with all type forms
- [ ] Test type RDF generation validates against elixir-shapes.ttl
- [ ] Test round-trip: type definition → extraction → RDF → validation
- [ ] Test remote type references resolve correctly
- [ ] Test type variable scoping in polymorphic functions
- [ ] Test union type with 5+ members
- [ ] Test deeply nested parameterized types (3+ levels)
- [ ] Test function type in callback spec
- [ ] Test struct type extraction and building
- [ ] Test Pipeline integration with enhanced type system
- [ ] Test Orchestrator coordinates type builders correctly
- [ ] Test parallel type building for large modules
- [ ] Test type IRI stability across multiple extractions
- [ ] Test backward compatibility with existing type extraction
- [ ] Test error handling for malformed type expressions
