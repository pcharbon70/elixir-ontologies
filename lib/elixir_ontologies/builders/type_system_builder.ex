defmodule ElixirOntologies.Builders.TypeSystemBuilder do
  @moduledoc """
  Builds RDF triples for Elixir type system elements.

  This module transforms type definitions and function specs from the extractors
  into RDF triples following the elixir-structure.ttl ontology. It handles:

  - Type definitions (@type, @typep, @opaque)
  - Type parameters for polymorphic types
  - Type expressions (unions, tuples, lists, maps, functions)
  - Function specs (@spec)
  - Type constraints from `when` clauses

  ## Type Definitions vs Function Specs

  **Type Definitions** declare custom types:
  - Use type IRI pattern: `base#Module/type/name/arity`
  - Define type parameters (for polymorphic types)
  - Define type expression body
  - Visibility: public (@type), private (@typep), or opaque (@opaque)

  **Function Specs** annotate function signatures:
  - Reuse function IRI pattern: `base#Module/function/arity`
  - Define parameter types (ordered list)
  - Define return type
  - Optional type constraints from `when` clauses

  ## Usage

      alias ElixirOntologies.Builders.{TypeSystemBuilder, Context}
      alias ElixirOntologies.Extractors.{TypeDefinition, FunctionSpec}

      # Build type definition
      type_def = %TypeDefinition{
        name: :user_t,
        arity: 0,
        visibility: :public,
        parameters: [],
        expression: {:map, [], []},
        location: nil,
        metadata: %{}
      }
      module_iri = ~I<https://example.org/code#MyApp.User>
      context = Context.new(base_iri: "https://example.org/code#")
      {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)

      # Build function spec
      func_spec = %FunctionSpec{
        name: :get_user,
        arity: 1,
        parameter_types: [{:integer, [], []}],
        return_type: {:user_t, [], []},
        type_constraints: %{},
        location: nil,
        metadata: %{}
      }
      function_iri = ~I<https://example.org/code#MyApp.User/get_user/1>
      {spec_iri, triples} = TypeSystemBuilder.build_function_spec(func_spec, function_iri, context)

  ## Examples

      iex> alias ElixirOntologies.Builders.{TypeSystemBuilder, Context}
      iex> alias ElixirOntologies.Extractors.TypeDefinition
      iex> type_def = %TypeDefinition{
      ...>   name: :t,
      ...>   arity: 0,
      ...>   visibility: :public,
      ...>   parameters: [],
      ...>   expression: :any,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#MyModule")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {type_iri, _triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)
      iex> to_string(type_iri)
      "https://example.org/code#MyModule/type/t/0"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.{TypeDefinition, FunctionSpec}
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API - Type Definition Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a type definition.

  Takes a type definition extraction result and builder context, returns the type IRI
  and a list of RDF triples representing the type and its expression.

  ## Parameters

  - `type_def` - Type definition extraction result from `Extractors.TypeDefinition.extract/1`
  - `module_iri` - The IRI of the module defining this type
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{type_iri, triples}` where:
  - `type_iri` - The IRI of the type definition
  - `triples` - List of RDF triples describing the type

  ## Examples

      iex> alias ElixirOntologies.Builders.{TypeSystemBuilder, Context}
      iex> alias ElixirOntologies.Extractors.TypeDefinition
      iex> type_def = %TypeDefinition{
      ...>   name: :user,
      ...>   arity: 0,
      ...>   visibility: :public,
      ...>   parameters: [],
      ...>   expression: :any,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#Test")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {type_iri, triples} = TypeSystemBuilder.build_type_definition(type_def, module_iri, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^type_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build_type_definition(TypeDefinition.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_type_definition(type_def, module_iri, context) do
    # Extract module name from module IRI
    module_name = extract_module_name(module_iri)

    # Generate type IRI
    type_iri = IRI.for_type(context.base_iri, module_name, type_def.name, type_def.arity)

    # Build all triples
    triples =
      [
        # Core type triples
        build_type_class_triple(type_iri, type_def.visibility),
        build_module_contains_type_triple(module_iri, type_iri),
        build_type_name_triple(type_iri, type_def.name),
        build_type_arity_triple(type_iri, type_def.arity)
      ] ++
        build_type_parameters_triples(type_iri, type_def.parameters, context) ++
        build_type_expression_triples(type_iri, type_def.expression, context) ++
        build_type_location_triple(type_iri, type_def.location, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {type_iri, triples}
  end

  # ===========================================================================
  # Public API - Function Spec Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a function spec.

  Takes a function spec extraction result and builder context, returns the spec IRI
  and a list of RDF triples representing the spec's type signature.

  ## Parameters

  - `func_spec` - Function spec extraction result from `Extractors.FunctionSpec.extract/1`
  - `function_iri` - The IRI of the function being annotated
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{spec_iri, triples}` where:
  - `spec_iri` - The IRI of the function spec (same as function_iri)
  - `triples` - List of RDF triples describing the spec

  ## Examples

      iex> alias ElixirOntologies.Builders.{TypeSystemBuilder, Context}
      iex> alias ElixirOntologies.Extractors.FunctionSpec
      iex> func_spec = %FunctionSpec{
      ...>   name: :add,
      ...>   arity: 2,
      ...>   parameter_types: [{:integer, [], []}, {:integer, [], []}],
      ...>   return_type: {:integer, [], []},
      ...>   type_constraints: %{},
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> function_iri = RDF.iri("https://example.org/code#Test/add/2")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {spec_iri, _triples} = TypeSystemBuilder.build_function_spec(func_spec, function_iri, context)
      iex> spec_iri == function_iri
      true
  """
  @spec build_function_spec(FunctionSpec.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_function_spec(func_spec, function_iri, context) do
    # Spec IRI is the same as function IRI
    spec_iri = function_iri

    # Build all triples
    triples =
      [
        # Core spec triples
        build_spec_class_triple(spec_iri),
        build_function_has_spec_triple(function_iri, spec_iri)
      ] ++
        build_parameter_types_triples(spec_iri, func_spec.parameter_types, context) ++
        build_return_type_triples(spec_iri, func_spec.return_type, context) ++
        build_type_constraints_triples(spec_iri, func_spec.type_constraints, context) ++
        build_spec_location_triple(spec_iri, func_spec.location, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {spec_iri, triples}
  end

  # ===========================================================================
  # Type Definition Triple Generation
  # ===========================================================================

  # Build rdf:type triple for type definition
  defp build_type_class_triple(type_iri, :public) do
    Helpers.type_triple(type_iri, Structure.PublicType)
  end

  defp build_type_class_triple(type_iri, :private) do
    Helpers.type_triple(type_iri, Structure.PrivateType)
  end

  defp build_type_class_triple(type_iri, :opaque) do
    Helpers.type_triple(type_iri, Structure.OpaqueType)
  end

  # Build struct:containsType triple from module to type
  defp build_module_contains_type_triple(module_iri, type_iri) do
    Helpers.object_property(module_iri, Structure.containsType(), type_iri)
  end

  # Build struct:typeName triple
  defp build_type_name_triple(type_iri, name) do
    Helpers.datatype_property(type_iri, Structure.typeName(), Atom.to_string(name), RDF.XSD.String)
  end

  # Build struct:typeArity triple
  defp build_type_arity_triple(type_iri, arity) do
    Helpers.datatype_property(
      type_iri,
      Structure.typeArity(),
      arity,
      RDF.XSD.NonNegativeInteger
    )
  end

  # Build triples for type parameters (type variables)
  defp build_type_parameters_triples(type_iri, parameters, _context) do
    parameters
    |> Enum.map(fn _param_name ->
      # Create a blank node for the type variable
      type_var_node = RDF.BlankNode.new()

      [
        # rdf:type struct:TypeVariable
        Helpers.type_triple(type_var_node, Structure.TypeVariable),
        # struct:hasTypeVariable
        Helpers.object_property(type_iri, Structure.hasTypeVariable(), type_var_node)
        # variable name (if there's a property for it)
        # For now, type variables are represented as blank nodes without names
      ]
    end)
    |> List.flatten()
  end

  # Build type location triple if present
  defp build_type_location_triple(_type_iri, nil, _context), do: []
  defp build_type_location_triple(_type_iri, _location, %Context{file_path: nil}), do: []

  defp build_type_location_triple(type_iri, location, context) do
    file_iri = IRI.for_source_file(context.base_iri, context.file_path)
    end_line = location.end_line || location.start_line
    location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

    [Helpers.object_property(type_iri, Core.hasSourceLocation(), location_iri)]
  end

  # ===========================================================================
  # Function Spec Triple Generation
  # ===========================================================================

  # Build rdf:type struct:FunctionSpec triple
  defp build_spec_class_triple(spec_iri) do
    Helpers.type_triple(spec_iri, Structure.FunctionSpec)
  end

  # Build struct:hasSpec triple from function to spec
  defp build_function_has_spec_triple(function_iri, spec_iri) do
    Helpers.object_property(function_iri, Structure.hasSpec(), spec_iri)
  end

  # Build spec location triple if present
  defp build_spec_location_triple(_spec_iri, nil, _context), do: []
  defp build_spec_location_triple(_spec_iri, _location, %Context{file_path: nil}), do: []

  defp build_spec_location_triple(spec_iri, location, context) do
    file_iri = IRI.for_source_file(context.base_iri, context.file_path)
    end_line = location.end_line || location.start_line
    location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

    [Helpers.object_property(spec_iri, Core.hasSourceLocation(), location_iri)]
  end

  # ===========================================================================
  # Type Expression Triple Generation
  # ===========================================================================

  # Build triples for type expression (the body of a type definition)
  defp build_type_expression_triples(_type_iri, _expression, _context) do
    # TODO: Implement recursive type expression building
    # For now, return empty list
    []
  end

  # Build triples for parameter types in a function spec
  defp build_parameter_types_triples(_spec_iri, parameter_types, _context) do
    # Build type expression for each parameter type
    _param_type_nodes =
      parameter_types
      |> Enum.map(fn _param_type_ast ->
        # For now, create blank nodes for type expressions
        # TODO: Implement full type expression building
        RDF.BlankNode.new()
      end)

    # TODO: Create RDF list for ordered parameter types
    # For now, return empty list
    []
  end

  # Build triples for return type in a function spec
  defp build_return_type_triples(_spec_iri, _return_type_ast, _context) do
    # TODO: Build type expression for return type
    # For now, return empty list
    []
  end

  # Build triples for type constraints from `when` clause
  defp build_type_constraints_triples(_spec_iri, _type_constraints, _context) do
    # TODO: Build type constraint triples
    # For now, return empty list
    []
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  # Extract module name from module IRI
  defp extract_module_name(module_iri) do
    module_iri
    |> to_string()
    |> String.split("#")
    |> List.last()
    |> URI.decode()
  end
end
