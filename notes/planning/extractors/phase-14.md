# Phase 14: Type System Completion

This phase completes the type system extraction and building capabilities. While basic type definitions and function specs are extracted, complex type expressions like unions, intersections, generics, and remote types are not fully captured. This phase implements comprehensive type expression parsing and RDF generation for the full type system ontology.

## 14.1 Type Expression Enhancement

This section enhances the TypeExpression extractor to handle all type expression forms defined in the elixir-structure.ttl ontology, including composite types, parameterized types, and special forms.

### 14.1.1 Union and Intersection Types
- [x] **Task 14.1.1 Complete**

Extract union types (|) and intersection type information from typespecs, representing the full type algebra.

Note: Intersection types are not part of Elixir's type system (they exist in TypeScript and other languages). Only union types are implemented.

- [x] 14.1.1.1 Update `lib/elixir_ontologies/extractors/type_expression.ex` to detect union type AST patterns
- [x] 14.1.1.2 Implement `extract_union_type/1` returning `%{type: :union, types: [...]}` (via `do_parse/1` for `{:|, _, [left, right]}`)
- [x] 14.1.1.3 Handle nested unions (flattening `a | b | c` into single union) (via `flatten_union/1`)
- [x] 14.1.1.4 Extract type positions for each union member (via `union_position` in metadata)
- [x] 14.1.1.5 Create `%TypeExpression{kind: :union}` struct variant
- [x] 14.1.1.6 Add union type support to existing tests (7 tests for union types + 3 new position tracking tests)

### 14.1.2 Parameterized Types (Generics)
- [x] **Task 14.1.2 Complete**

Extract parameterized types like `list(integer())`, `map(atom(), binary())`, and user-defined generic types.

Note: Rather than a separate `kind: :parameterized`, parameterized types use `kind: :basic` or `kind: :remote` with `parameterized: true` in metadata, which is more consistent with Elixir's type system.

- [x] 14.1.2.1 Implement `extract_parameterized_type/1` for built-in parameterized types (existing, enhanced with position tracking)
- [x] 14.1.2.2 Handle `list(t)`, `map(k, v)`, `keyword(t)`, `tuple()` patterns (tested)
- [x] 14.1.2.3 Extract type parameters and their positions (via `param_position` in metadata, `param_count` in parent)
- [x] 14.1.2.4 Support nested parameterized types (e.g., `list(map(atom(), integer()))`) (tested)
- [x] 14.1.2.5 Create `%TypeExpression{kind: :parameterized, base_type: ..., parameters: [...]}` struct (using `kind: :basic` with `parameterized: true` instead)
- [x] 14.1.2.6 Add parameterized type tests (10 new tests + `parameterized?/1` helper)

### 14.1.3 Remote Types
- [x] **Task 14.1.3 Complete**

Extract remote type references like `String.t()`, `Enum.t()`, and qualified type names from external modules.

Note: Remote type detection was already implemented. This task enhanced it with arity tracking and IRI-compatible format helpers for RDF generation.

- [x] 14.1.3.1 Implement `extract_remote_type/1` detecting `Module.type()` AST pattern (existing)
- [x] 14.1.3.2 Extract module reference as IRI-compatible format (via `module_iri/1` helper)
- [x] 14.1.3.3 Extract type name and arity (arity in metadata)
- [x] 14.1.3.4 Handle parameterized remote types (e.g., `GenServer.on_start()`) (existing with param_position from 14.1.2)
- [x] 14.1.3.5 Create `%TypeExpression{kind: :remote, module: ..., type_name: ..., arity: ...}` struct (arity now in metadata)
- [x] 14.1.3.6 Add remote type tests (11 new tests)

### 14.1.4 Type Variables and Constraints
- [x] **Task 14.1.4 Complete**

Extract type variables used in polymorphic type definitions and their `when` constraints.

Note: Type variable detection was already implemented (`kind: :variable`). This task added constraint-aware parsing via `parse_with_constraints/2` and helper functions for constraint introspection.

- [x] 14.1.4.1 Implement `extract_type_variable/1` for lowercase type names in specs (existing)
- [x] 14.1.4.2 Parse `when` clauses to extract type variable constraints (via `parse_with_constraints/2`)
- [x] 14.1.4.3 Track type variable scope (function-level via constraint map parameter)
- [x] 14.1.4.4 Extract constraint relationships (e.g., `when a: integer()`) (constraints parsed to TypeExpression)
- [x] 14.1.4.5 Create `%TypeVariable{name: ..., constraints: [...]}` struct (using existing struct with `constraint` in metadata)
- [x] 14.1.4.6 Add type variable and constraint tests (20 new tests + 9 doctests)

**Section 14.1 Unit Tests:**
- [x] Test union type extraction for `integer() | atom()` (existing)
- [x] Test nested union flattening (existing)
- [x] Test parameterized type extraction for `list(integer())` (existing)
- [x] Test nested parameterized types (existing)
- [x] Test remote type extraction for `String.t()` (existing)
- [x] Test type variable detection (existing)
- [x] Test `when` constraint parsing (20 new tests)
- [x] Test complex type expressions combining all forms (constraint propagation tests)

## 14.2 Special Type Forms

This section handles special type forms defined in the ontology including function types, struct types, tuple types with specific arities, and literal types.

### 14.2.1 Function Types
- [x] **Task 14.2.1 Complete**

Extract function type signatures like `(integer() -> atom())` used in higher-order function specs.

Note: Function type extraction was already implemented (`kind: :function`). This task added helper functions for introspection and comprehensive tests for edge cases.

- [x] 14.2.1.1 Implement `extract_function_type/1` for arrow syntax in types (existing)
- [x] 14.2.1.2 Extract parameter types list (existing `param_types` field + new `param_types/1` helper)
- [x] 14.2.1.3 Extract return type (existing `return_type` field + new `return_type/1` helper)
- [x] 14.2.1.4 Handle multiple arities (e.g., `(-> atom()) | (integer() -> atom())`) (works via union parsing)
- [x] 14.2.1.5 Create `%TypeExpression{kind: :function, ...}` struct (existing, uses `kind: :function`)
- [x] 14.2.1.6 Add function type tests (14 new tests + 9 doctests)

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
