# Phase 12.2.4: Type System Builder

## Status
**Status**: Planning
**Phase**: 12.2.4
**Priority**: High
**Dependencies**: Phase 12.1 (Builder Infrastructure), Phase 12.2.3 (Struct Builder)

## Problem Statement

Build an RDF triple generator that transforms Elixir type system elements (type definitions and function specs) into RDF triples following the elixir-structure.ttl ontology. This builder enables semantic representation of Elixir's type system for static analysis, documentation generation, and LLM consumption.

### What We're Building

A TypeSystemBuilder module that handles:
1. **Type Definitions** (@type, @typep, @opaque)
   - Type name, arity, and visibility
   - Type parameters (for parameterized types)
   - Type expression trees (union, tuple, list, map, etc.)

2. **Function Specs** (@spec, @callback)
   - Function signature (name/arity)
   - Parameter types (ordered list)
   - Return types
   - Type constraints from `when` clauses

3. **Type Expressions**
   - Basic types (atom(), integer(), binary(), etc.)
   - Union types (type1 | type2)
   - Tuple types ({type1, type2})
   - List types ([element_type])
   - Map types (%{key => value})
   - Function types ((args -> return))
   - Remote types (Module.type())
   - Type variables (a, element, etc.)

### Why This Matters

The type system is critical for:
- **Static Analysis**: Enable Dialyzer integration and type checking
- **Documentation**: Link types to functions for API documentation
- **Code Understanding**: Help LLMs understand type contracts and constraints
- **Module Dependencies**: Track type references across modules

---

## Solution Overview

### High-Level Approach

The TypeSystemBuilder follows the established builder pattern:

```elixir
defmodule ElixirOntologies.Builders.TypeSystemBuilder do
  # Public API
  def build_type_definition(type_def, module_iri, context)
  def build_function_spec(func_spec, module_iri, context)

  # Type expression tree building
  defp build_type_expression(type_expr, context)
end
```

### Key Design Decisions

1. **Type IRI Pattern**: Use `{module_iri}/type/{name}/{arity}` to uniquely identify types
   - Example: `https://example.org/code#MyModule/type/my_list/1`

2. **Spec IRI Pattern**: Use function IRI pattern since specs annotate functions
   - Example: `https://example.org/code#MyModule/get_user/1` (reuse function IRI)

3. **Type Expression IRIs**: Use blank nodes for complex nested type expressions
   - Only top-level types get IRIs
   - Nested expressions (union members, tuple elements) use blank nodes

4. **Recursive Type Expression Building**: Parse type expression AST recursively
   - Use TypeExpression extractor as a guide
   - Build RDF triple sets for each expression node

---

## Technical Details

### Type IRI Generation Patterns

| Element | IRI Pattern | Example |
|---------|-------------|---------|
| Type Definition | `{module_iri}/type/{name}/{arity}` | `.../MyModule/type/user_t/0` |
| Function Spec | `{function_iri}` (reuse existing) | `.../MyModule/get_user/1` |
| Type Expression | Blank node | `_:b1` |
| Type Variable | Blank node | `_:b2` |

### TypeSpec Extractor Data Structures

#### TypeDefinition.t()

```elixir
%TypeDefinition{
  name: atom(),                    # Type name (e.g., :user_t)
  arity: non_neg_integer(),        # Number of type parameters
  visibility: :public | :private | :opaque,
  parameters: [atom()],            # Type parameter names
  expression: Macro.t(),           # Type expression AST
  location: SourceLocation.t() | nil,
  metadata: %{
    attribute: :type | :typep | :opaque,
    is_parameterized: boolean()
  }
}
```

#### FunctionSpec.t()

```elixir
%FunctionSpec{
  name: atom(),                    # Function name
  arity: non_neg_integer(),        # Parameter count
  parameter_types: [Macro.t()],    # List of type expression ASTs
  return_type: Macro.t(),          # Return type expression AST
  type_constraints: %{atom() => Macro.t()},  # When clause constraints
  location: SourceLocation.t() | nil,
  metadata: %{
    has_when_clause: boolean()
  }
}
```

#### TypeExpression.t()

```elixir
%TypeExpression{
  kind: :basic | :union | :tuple | :list | :map | :function | :remote | :variable | :literal,
  name: atom() | nil,              # For basic/remote/variable types
  elements: [TypeExpression.t()] | nil,  # For union/tuple/list
  key_type: TypeExpression.t() | nil,    # For map types
  value_type: TypeExpression.t() | nil,  # For map types
  param_types: [TypeExpression.t()] | nil,  # For function types
  return_type: TypeExpression.t() | nil,    # For function types
  module: [atom()] | nil,          # For remote types
  ast: Macro.t(),                  # Original AST
  metadata: map()
}
```

### Ontology Classes and Properties

#### Type Definition Classes

From `elixir-structure.ttl`:
- `struct:TypeSpec` - Base class for type definitions
- `struct:PublicType` - Public type (@type)
- `struct:PrivateType` - Private type (@typep)
- `struct:OpaqueType` - Opaque type (@opaque)

#### Type Expression Classes

- `struct:TypeExpression` - Base class
- `struct:BasicType` - Built-in types (atom(), integer(), etc.)
- `struct:UnionType` - Union of types (type1 | type2)
- `struct:TupleType` - Tuple types ({type1, type2})
- `struct:ListType` - List types ([element])
- `struct:MapType` - Map types (%{key => value})
- `struct:FunctionType` - Function types ((args -> return))
- `struct:ParameterizedType` - Types with parameters (Enum.t(a))
- `struct:TypeVariable` - Type variables (a, element)

#### Function Spec Classes

- `struct:FunctionSpec` - Type specification for functions
- `struct:CallbackSpec` - Callback specifications
- `struct:MacroCallbackSpec` - Macro callback specifications

#### Object Properties

- `struct:containsType` - Module contains type definition
- `struct:hasTypeVariable` - Type has type parameter
- `struct:hasReturnType` - Spec has return type
- `struct:hasParameterTypes` - Spec has parameter types (as RDF list)
- `struct:hasTypeAnnotation` - Parameter has type annotation
- `struct:unionMember` - Union contains member type
- `struct:elementType` - List element type
- `struct:keyType` - Map key type
- `struct:valueType` - Map value type
- `struct:referencesType` - Type expression references defined type

#### Datatype Properties

- `struct:typeName` - Type name (string)
- `struct:typeArity` - Type arity (non-negative integer)

### Integration Points

#### Module Builder
- Type definitions belong to modules
- Module builder will call TypeSystemBuilder for each type definition
- Triple: `{module_iri, struct:containsType, type_iri}`

#### Function Builder
- Function specs annotate functions
- Link function to its spec
- Triple: `{function_iri, RDF.type(), struct:FunctionSpec}` (if spec exists)

#### IRI Module
- Need to add `IRI.for_type/4` function:
  ```elixir
  def for_type(base_iri, module, type_name, arity)
  ```
- Pattern: `{base}Module/type/type_name/arity`

---

## Implementation Plan

### Step 1: Extend IRI Module

**File**: `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex`

Add type IRI generation:
```elixir
@doc """
Generates an IRI for a type definition.

## Examples

    iex> IRI.for_type("https://example.org/code#", "MyModule", "user_t", 0)
    ~I<https://example.org/code#MyModule/type/user_t/0>
"""
@spec for_type(String.t() | RDF.IRI.t(), String.t() | atom(), String.t() | atom(), non_neg_integer()) :: RDF.IRI.t()
def for_type(base_iri, module, type_name, arity)
```

### Step 2: Create TypeSystemBuilder Module

**File**: `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/type_system_builder.ex`

**Structure**:
```elixir
defmodule ElixirOntologies.Builders.TypeSystemBuilder do
  @moduledoc """
  Builds RDF triples for Elixir type system elements.

  Handles:
  - Type definitions (@type, @typep, @opaque)
  - Function specs (@spec, @callback)
  - Type expressions (union, tuple, list, map, etc.)
  """

  # ===========================================================================
  # Public API - Type Definition Building
  # ===========================================================================

  @spec build_type_definition(TypeDefinition.t(), RDF.IRI.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_type_definition(type_def, module_iri, context)

  # ===========================================================================
  # Public API - Function Spec Building
  # ===========================================================================

  @spec build_function_spec(FunctionSpec.t(), RDF.IRI.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_function_spec(func_spec, module_iri, context)

  # ===========================================================================
  # Core Triple Generation - Type Definitions
  # ===========================================================================

  defp build_type_triple(type_iri, visibility)
  defp build_type_name_triple(type_iri, type_def)
  defp build_type_arity_triple(type_iri, type_def)
  defp build_module_contains_type_triple(module_iri, type_iri)
  defp build_type_expression_triples(type_iri, type_def, context)
  defp build_type_parameter_triples(type_iri, type_def, context)

  # ===========================================================================
  # Core Triple Generation - Function Specs
  # ===========================================================================

  defp build_spec_type_triple(function_iri)
  defp build_parameter_types_triples(function_iri, func_spec, context)
  defp build_return_type_triples(function_iri, func_spec, context)
  defp build_type_constraints_triples(function_iri, func_spec, context)

  # ===========================================================================
  # Type Expression Building (Recursive)
  # ===========================================================================

  defp build_type_expression(type_expr, context)
  defp build_basic_type(type_expr, context)
  defp build_union_type(type_expr, context)
  defp build_tuple_type(type_expr, context)
  defp build_list_type(type_expr, context)
  defp build_map_type(type_expr, context)
  defp build_function_type(type_expr, context)
  defp build_remote_type(type_expr, context)
  defp build_type_variable(type_expr, context)
  defp build_literal_type(type_expr, context)

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp generate_type_iri(type_def, module_iri, context)
  defp determine_type_class(visibility)
  defp module_name_from_iri(module_iri)
end
```

### Step 3: Implement build_type_definition/3

**Core Logic**:
1. Generate type IRI from module, name, and arity
2. Build rdf:type triple (PublicType/PrivateType/OpaqueType)
3. Build typeName and typeArity datatype properties
4. Build containsType relationship from module
5. Build type parameter triples (if parameterized)
6. Build type expression triples (recursive)
7. Build location triple (if available)
8. Flatten and deduplicate

**Example Output**:
```turtle
# @type user_t :: %{name: String.t(), age: integer()}

<#MyModule/type/user_t/0> a struct:PublicType ;
    struct:typeName "user_t"^^xsd:string ;
    struct:typeArity 0^^xsd:nonNegativeInteger ;
    # Type expression (blank node for map)
    # ... (recursive type expression triples)
    .

<#MyModule> struct:containsType <#MyModule/type/user_t/0> .
```

### Step 4: Implement build_function_spec/3

**Core Logic**:
1. Reuse function IRI (spec annotates existing function)
2. Add rdf:type struct:FunctionSpec triple
3. Build parameter types as RDF list (ordered)
4. Build return type expression
5. Build type constraints from when clause (if present)
6. Build location triple (if available)

**Example Output**:
```turtle
# @spec get_user(integer()) :: {:ok, user_t()} | :error

<#MyModule/get_user/1> a struct:FunctionSpec ;
    struct:hasParameterTypes ( _:param_type1 ) ;
    struct:hasReturnType _:return_type .

_:param_type1 a struct:BasicType ;
    struct:typeName "integer"^^xsd:string .

_:return_type a struct:UnionType ;
    struct:unionMember _:ok_tuple ;
    struct:unionMember _:error_atom .

_:ok_tuple a struct:TupleType ;
    # ... (nested tuple structure)
    .

_:error_atom a struct:BasicType ;
    struct:typeName "error"^^xsd:string .
```

### Step 5: Implement Type Expression Building (Recursive)

**Architecture**: Use TypeExpression extractor's parse result to guide RDF generation

**build_type_expression/2 dispatcher**:
```elixir
defp build_type_expression(type_expr_ast, context) do
  {:ok, parsed} = TypeExpression.parse(type_expr_ast)

  case parsed.kind do
    :basic -> build_basic_type(parsed, context)
    :union -> build_union_type(parsed, context)
    :tuple -> build_tuple_type(parsed, context)
    :list -> build_list_type(parsed, context)
    :map -> build_map_type(parsed, context)
    :function -> build_function_type(parsed, context)
    :remote -> build_remote_type(parsed, context)
    :variable -> build_type_variable(parsed, context)
    :literal -> build_literal_type(parsed, context)
    :any -> build_any_type(parsed, context)
  end
end
```

**For each type kind**:
1. Create blank node for this expression
2. Add rdf:type triple (BasicType, UnionType, etc.)
3. Add kind-specific properties:
   - BasicType: typeName
   - UnionType: unionMember for each member (recursive)
   - TupleType: ordered elements via RDF list
   - ListType: elementType (recursive)
   - MapType: keyType and valueType (recursive)
   - FunctionType: parameter types and return type
   - TypeVariable: variable name
4. Return `{blank_node, triples}`

**Example - Union Type**:
```elixir
defp build_union_type(%TypeExpression{kind: :union, elements: elements}, context) do
  node = Helpers.blank_node()

  # Build type triple
  type_triple = Helpers.type_triple(node, Structure.UnionType)

  # Build each member recursively
  {member_triples, member_nodes} =
    elements
    |> Enum.map(&build_type_expression(&1.ast, context))
    |> Enum.unzip()

  # Build unionMember triples
  member_relation_triples =
    Enum.map(member_nodes, fn member_node ->
      Helpers.object_property(node, Structure.unionMember(), member_node)
    end)

  all_triples = [type_triple] ++ member_relation_triples ++ List.flatten(member_triples)

  {node, all_triples}
end
```

### Step 6: Write Comprehensive Tests

**File**: `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/type_system_builder_test.exs`

**Test Categories**:

1. **Type Definition Tests**
   - Minimal public type (@type t :: any)
   - Private type (@typep internal :: atom)
   - Opaque type (@opaque t :: term)
   - Parameterized type (@type my_list(a) :: [a])
   - Type with location information

2. **Function Spec Tests**
   - Basic spec (@spec foo() :: :ok)
   - Spec with parameters (@spec add(integer(), integer()) :: integer())
   - Spec with union return (@spec fetch() :: {:ok, term()} | :error)
   - Spec with when clause (@spec identity(a) :: a when a: var)
   - Callback spec (@callback init(term()) :: {:ok, state()})

3. **Type Expression Tests**
   - Basic types (atom(), integer(), binary())
   - Union types (:ok | :error)
   - Tuple types ({:ok, term()})
   - List types ([integer()])
   - Map types (%{required(atom()) => term()})
   - Function types ((integer() -> atom()))
   - Remote types (String.t(), Enum.t(integer()))
   - Type variables (a, element)
   - Nested complex types

4. **Integration Tests**
   - Module with types and specs
   - Type referencing another type
   - Spec using defined types
   - Parameterized types with constraints

**Test Structure** (following existing pattern):
```elixir
defmodule ElixirOntologies.Builders.TypeSystemBuilderTest do
  use ExUnit.Case, async: true
  doctest ElixirOntologies.Builders.TypeSystemBuilder

  alias ElixirOntologies.Builders.{TypeSystemBuilder, Context}
  alias ElixirOntologies.Extractors.{TypeDefinition, FunctionSpec}
  alias ElixirOntologies.NS.Structure

  # Test helpers
  defp build_test_context(opts \\ [])
  defp build_test_module_iri(opts \\ [])
  defp build_test_type_def(opts \\ [])
  defp build_test_function_spec(opts \\ [])

  # Test suites
  describe "build_type_definition/3 - basic types"
  describe "build_type_definition/3 - parameterized types"
  describe "build_type_definition/3 - visibility"
  describe "build_function_spec/3 - basic specs"
  describe "build_function_spec/3 - complex types"
  describe "type expressions - basic types"
  describe "type expressions - union types"
  describe "type expressions - tuple types"
  describe "type expressions - list types"
  describe "type expressions - map types"
  describe "type expressions - function types"
  describe "type expressions - remote types"
  describe "type expressions - nested types"
end
```

### Step 7: Documentation and Examples

Add comprehensive moduledoc with:
- Purpose and scope
- Type IRI patterns
- Usage examples for common scenarios
- Integration with other builders

---

## Success Criteria

### Functional Requirements

- [ ] TypeSystemBuilder module created
- [ ] `build_type_definition/3` generates correct RDF triples for:
  - [ ] Public types (@type)
  - [ ] Private types (@typep)
  - [ ] Opaque types (@opaque)
  - [ ] Parameterized types (type parameters)
  - [ ] Type expression trees
- [ ] `build_function_spec/3` generates correct RDF triples for:
  - [ ] Function specs (@spec)
  - [ ] Parameter types (as ordered RDF list)
  - [ ] Return types
  - [ ] Type constraints (when clauses)
- [ ] Type expression building handles:
  - [ ] Basic types (atom(), integer(), etc.)
  - [ ] Union types (type1 | type2)
  - [ ] Tuple types ({type1, type2})
  - [ ] List types ([element])
  - [ ] Map types (%{key => value})
  - [ ] Function types ((args -> return))
  - [ ] Remote types (Module.type())
  - [ ] Type variables (a, element)
  - [ ] Literal types (:ok, 42)
  - [ ] Nested complex types
- [ ] Source location information included when available

### Code Quality Requirements

- [ ] All functions documented with @doc and examples
- [ ] Comprehensive test coverage (>95%)
- [ ] Follows existing builder patterns (StructBuilder, BehaviourBuilder)
- [ ] Uses Helpers module for triple generation
- [ ] Proper error handling
- [ ] IRI generation added to IRI module

### Integration Requirements

- [ ] Module builder can use TypeSystemBuilder for type definitions
- [ ] Function builder can use TypeSystemBuilder for specs
- [ ] Consistent IRI patterns with other builders
- [ ] Compatible with existing Context structure

### Validation Requirements

- [ ] Generated triples validate against elixir-structure.ttl ontology
- [ ] Type IRIs are unique and deterministic
- [ ] No duplicate triples in output
- [ ] Blank nodes used appropriately for nested expressions
- [ ] RDF lists used for ordered parameter types

---

## Testing Strategy

### Test Categories

1. **Unit Tests** (test individual functions)
   - Type IRI generation
   - Type triple generation
   - Expression builders
   - Helper functions

2. **Integration Tests** (test complete flows)
   - Full type definition building
   - Full function spec building
   - Complex nested type expressions
   - Module integration

3. **Property Tests** (test invariants)
   - Same input always produces same output (deterministic)
   - No duplicate triples
   - All IRIs are valid
   - All referenced IRIs exist in output

4. **Regression Tests** (prevent known issues)
   - Edge cases from TypeExpression extractor
   - Complex union types
   - Deeply nested types

### Test Data Sources

Use extractors to generate test data:
```elixir
# Real Elixir code → AST → Extractor → Builder → RDF
ast = quote do
  @type user_t :: %{name: String.t(), age: integer()}
end

{:ok, type_def} = TypeDefinition.extract(ast)
{type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)
```

### Coverage Goals

- **Line Coverage**: >95%
- **Branch Coverage**: >90%
- **Function Coverage**: 100%
- **Type Expression Coverage**: All 9 kinds tested

### Validation Strategy

1. **Schema Validation**: Generated triples conform to ontology
2. **RDF Validation**: Valid RDF syntax and structure
3. **Semantic Validation**: Logical consistency (e.g., type references exist)
4. **Round-trip Testing**: Can query and reconstruct type information

---

## Dependencies and Integration

### Required Files

**New Files**:
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/type_system_builder.ex`
- `/home/ducky/code/elixir-ontologies/test/elixir_ontologies/builders/type_system_builder_test.exs`

**Modified Files**:
- `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex` (add `for_type/4`)

### External Dependencies

**Extractors**:
- `ElixirOntologies.Extractors.TypeDefinition` - Provides type definition data
- `ElixirOntologies.Extractors.FunctionSpec` - Provides spec data
- `ElixirOntologies.Extractors.TypeExpression` - Guides expression parsing

**Builders**:
- `ElixirOntologies.Builders.Context` - Builder context
- `ElixirOntologies.Builders.Helpers` - Triple generation utilities

**Infrastructure**:
- `ElixirOntologies.IRI` - IRI generation
- `ElixirOntologies.NS.Structure` - Ontology vocabulary

### Integration Points

**Module Builder** (`module_builder.ex`):
```elixir
# Will call TypeSystemBuilder for each type definition
types = TypeDefinition.extract_all(body)
type_triples =
  Enum.flat_map(types, fn type_def ->
    {_type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)
    triples
  end)
```

**Function Builder** (`function_builder.ex`):
```elixir
# Will call TypeSystemBuilder to add spec information
case FunctionSpec.extract_for_function(name, arity, body) do
  {:ok, spec} ->
    {_func_iri, spec_triples} = TypeSystemBuilder.build_function_spec(spec, module_iri, context)
  {:error, _} ->
    []
end
```

---

## Risks and Mitigations

### Risk 1: Complex Type Expression Parsing

**Risk**: Nested type expressions can be arbitrarily complex and hard to model in RDF.

**Mitigation**:
- Use TypeExpression extractor as trusted source
- Build incrementally: basic types first, then compounds
- Extensive testing with real-world Elixir types
- Use blank nodes to simplify graph structure

### Risk 2: Type Reference Resolution

**Risk**: Types can reference other types that may not exist yet (forward references).

**Mitigation**:
- Don't resolve references during building
- Use `referencesType` property for cross-references
- Let graph queries handle resolution
- Document reference semantics in ontology

### Risk 3: IRI Collision with Functions

**Risk**: Type name/arity could collide with function name/arity.

**Mitigation**:
- Use distinct IRI pattern: `/type/{name}/{arity}` vs `/{name}/{arity}`
- Clear namespace separation
- Validate no collisions in tests

### Risk 4: Performance with Large Type Trees

**Risk**: Deeply nested types generate many triples.

**Mitigation**:
- Lazy evaluation where possible
- Share common type expression nodes (deduplication)
- Performance benchmarks in tests
- Consider caching for identical type expressions

---

## Future Enhancements

### Phase 2 Features (Future Work)

1. **Type Inference Support**
   - Link inferred types from Dialyzer
   - Represent type narrowing

2. **Type Alias Tracking**
   - Track when types reference other types
   - Build dependency graphs

3. **Gradual Typing**
   - Support for dynamic/any boundaries
   - Type safety annotations

4. **Protocol Type Integration**
   - Link protocol function specs to implementations
   - Type-based dispatch modeling

5. **Spec Validation**
   - Validate specs match function definitions
   - Detect spec/implementation mismatches

---

## References

### Code References

- **Extractor Implementations**:
  - `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/type_definition.ex`
  - `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/function_spec.ex`
  - `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/extractors/type_expression.ex`

- **Builder Patterns**:
  - `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/struct_builder.ex`
  - `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/behaviour_builder.ex`
  - `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/function_builder.ex`

- **Infrastructure**:
  - `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/context.ex`
  - `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/builders/helpers.ex`
  - `/home/ducky/code/elixir-ontologies/lib/elixir_ontologies/iri.ex`

### Ontology References

- **Ontology**: `/home/ducky/code/elixir-ontologies/priv/ontologies/elixir-structure.ttl`
  - Lines 156-250: Type System classes and properties
  - Lines 759-819: Type relationship properties

### Documentation References

- **Elixir Type System**: https://hexdocs.pm/elixir/typespecs.html
- **Dialyzer**: http://erlang.org/doc/man/dialyzer.html
- **RDF Lists**: https://www.w3.org/TR/rdf-schema/#ch_list

---

## Approval and Sign-off

**Planning Complete**: Ready for implementation upon approval.

**Next Steps**:
1. Review this planning document
2. Approve approach and design decisions
3. Begin implementation (Step 1: Extend IRI module)
4. Iterate through steps 2-7
5. Integration testing with module builder
6. Documentation and final review
