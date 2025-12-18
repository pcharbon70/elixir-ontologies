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
- [x] **Task 14.2.2 Complete**

Extract struct type references like `%User{}` and `%User{name: String.t()}` in typespecs.

Note: Struct type detection was already implemented (`kind: :struct`). This task enhanced it with field type constraint extraction and helper functions for IRI-compatible module references and field introspection.

- [x] 14.2.2.1 Implement `extract_struct_type/1` for struct pattern in types (existing)
- [x] 14.2.2.2 Extract struct module reference (via `struct_module/1` helper)
- [x] 14.2.2.3 Extract optional field type constraints (via `elements` field with parsed fields)
- [x] 14.2.2.4 Handle `t()` convention for struct types (handled at type definition level)
- [x] 14.2.2.5 Create `%TypeExpression{kind: :struct, module: ..., elements: [...]}` struct (uses `kind: :struct`)
- [x] 14.2.2.6 Add struct type tests (17 new tests + 6 doctests)

### 14.2.3 Literal Types
- [x] **Task 14.2.3 Complete**

Extract literal type values like `:ok`, `1..10`, and specific atom/integer literals in types.

Note: Basic literal types (atoms, integers, floats) were already implemented. This task added range literals, binary literals with size specifications, and helper functions for literal type introspection.

- [x] 14.2.3.1 Implement `extract_literal_type/1` for atom literals in types (existing)
- [x] 14.2.3.2 Handle integer literal types (specific values) (existing)
- [x] 14.2.3.3 Handle range literal types (`1..100`, `1..100//5`, negative ranges)
- [x] 14.2.3.4 Handle binary literal types with size specifications (`<<_::8>>`, `<<_::binary>>`, `<<_::_*8>>`)
- [x] 14.2.3.5 Create `%TypeExpression{kind: :literal, ...}` struct (uses `literal_type` in metadata)
- [x] 14.2.3.6 Add literal type tests (21 new tests + 10 doctests)

### 14.2.4 Tuple Types
- [x] **Task 14.2.4 Complete**

Extract tuple types with specific element types like `{:ok, result}` and `{atom(), integer(), binary()}`.

Note: Tuple type parsing was already comprehensive (empty, 2-tuple, N-tuple, tagged). This task added helper functions for tuple introspection and comprehensive tests for edge cases.

- [x] 14.2.4.1 Implement `extract_tuple_type/1` for fixed-arity tuples (existing)
- [x] 14.2.4.2 Extract element types in order (existing, via `tuple_elements/1` helper)
- [x] 14.2.4.3 Handle tagged tuples (existing, via `tagged_tuple?/1` and `tuple_tag/1` helpers)
- [x] 14.2.4.4 Distinguish from generic `tuple()` type (generic is `kind: :basic`)
- [x] 14.2.4.5 Create `%TypeExpression{kind: :tuple, elements: [...]}` struct (existing)
- [x] 14.2.4.6 Add tuple type tests (20 new tests + 11 doctests)

**Section 14.2 Unit Tests:**
- [x] Test function type extraction `(integer() -> atom())` (existing)
- [x] Test multi-arity function types (14.2.1)
- [x] Test struct type extraction `%User{}` (existing)
- [x] Test struct type with field constraints (14.2.2)
- [x] Test literal atom type `:ok` (existing)
- [x] Test literal range type `1..10` (14.2.3)
- [x] Test tuple type `{atom(), integer()}` (14.2.4)
- [x] Test tagged tuple patterns (14.2.4)

## 14.3 Type System Builder Enhancement

This section enhances the TypeSystemBuilder to generate RDF triples for all extracted type information, linking to the appropriate ontology classes.

### 14.3.1 Union Type Builder
- [x] **Task 14.3.1 Complete**

Generate RDF triples for union types using the structure:UnionType class and unionOf property.

Note: The ontology uses `structure:unionOf` property (not `hasUnionMember`). Implementation also includes builders for all other type expression kinds (basic, literal, tuple, list, map, function, remote, struct, variable) via the `build_type_expression/2` public API.

- [x] 14.3.1.1 Update `lib/elixir_ontologies/builders/type_system_builder.ex` (added build_type_expression/2 and all type builders)
- [x] 14.3.1.2 Implement `build_union_type/3` generating union type blank node
- [x] 14.3.1.3 Generate `rdf:type structure:UnionType` triple
- [x] 14.3.1.4 Generate `structure:unionOf` triples for each member type
- [x] 14.3.1.5 Handle recursive building for nested type expressions (all type kinds supported)
- [x] 14.3.1.6 Add union type builder tests (12 new tests covering union, basic, tuple, function, variable types)

### 14.3.2 Parameterized Type Builder
- [x] **Task 14.3.2 Complete**

Generate RDF triples for parameterized types using structure:ParameterizedType class.

Note: The ontology does not define `hasBaseType` or `hasTypeParameter` properties. Implementation uses `typeName` for base type and `elementType` for type parameters, matching the pattern used by ListType. This was already implemented in Phase 14.3.1 via `build_basic_type/3`.

- [x] 14.3.2.1 Implement `build_parameterized_type/3` generating type IRI (handled by `build_basic_type/3` when elements present)
- [x] 14.3.2.2 Generate `rdf:type structure:ParameterizedType` triple (line 466-467)
- [x] 14.3.2.3 Generate `structure:hasBaseType` linking to base type (using `typeName` instead - property doesn't exist)
- [x] 14.3.2.4 Generate `structure:hasTypeParameter` triples with ordering (using `elementType` - ordering not available)
- [x] 14.3.2.5 Handle nested parameterized types recursively (works via recursive building)
- [x] 14.3.2.6 Add parameterized type builder tests (5 tests: basic, name, keyword, nested, deeply nested)

### 14.3.3 Remote Type Builder
- [x] **Task 14.3.3 Complete**

Generate RDF triples for remote type references linking to external modules.

Note: The ontology does not define `RemoteType` class or `referencesModule` property. Implementation uses `BasicType` with fully qualified name string (e.g., "String.t"). This was already implemented in Phase 14.3.1 via `build_remote_type/3`.

- [x] 14.3.3.1 Implement `build_remote_type/3` generating remote type IRI (already exists from 14.3.1)
- [x] 14.3.3.2 Generate `rdf:type structure:RemoteType` triple (using `BasicType` - RemoteType doesn't exist)
- [x] 14.3.3.3 Generate `structure:referencesModule` linking to module IRI (using qualified name in `typeName`)
- [x] 14.3.3.4 Generate `structure:referencesType` with type name (type name included in qualified name)
- [x] 14.3.3.5 Handle remote types that may not be in current analysis scope (uses string representation)
- [x] 14.3.3.6 Add remote type builder tests (4 tests: simple, nested module, different name, in union)

### 14.3.4 Type Variable Builder
- [x] **Task 14.3.4 Complete**

Generate RDF triples for type variables and their constraints.

Note: The ontology does not define `variableName` or `hasConstraint` properties. Implementation uses `typeName` for variable name (same as other types). Constraint handling would require ontology enhancement. This was already implemented in Phase 14.3.1 via `build_variable_type/3`.

- [x] 14.3.4.1 Implement `build_type_variable/3` generating variable IRI (`build_variable_type/3` exists from 14.3.1)
- [x] 14.3.4.2 Generate `rdf:type structure:TypeVariable` triple (line 676)
- [x] 14.3.4.3 Generate `structure:variableName` with variable name (using `typeName` - variableName doesn't exist)
- [x] 14.3.4.4 Generate `structure:hasConstraint` triples for each constraint (N/A - property doesn't exist)
- [x] 14.3.4.5 Link constraints to their type expressions (N/A - no constraint linking available)
- [x] 14.3.4.6 Add type variable builder tests (5 tests: simple, different name, in union, in function, multiple vars)

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
