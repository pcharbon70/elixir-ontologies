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
  alias ElixirOntologies.Extractors.{TypeDefinition, FunctionSpec, TypeExpression}
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
        # Core spec triples - use spec_type to determine class
        build_spec_class_triple(spec_iri, func_spec),
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

  @doc """
  Builds an RDF triple marking a callback as optional.

  Use this function when a callback is listed in `@optional_callbacks`.
  It generates an additional `rdf:type structure:OptionalCallbackSpec` triple.

  Note: `OptionalCallbackSpec` is a subclass of `CallbackSpec`, so callbacks
  can have both types when marked as optional.

  ## Parameters

  - `callback_iri` - The IRI of the callback spec

  ## Returns

  An RDF triple marking the callback as optional.

  ## Examples

      iex> alias ElixirOntologies.Builders.TypeSystemBuilder
      iex> alias ElixirOntologies.NS.Structure
      iex> callback_iri = RDF.iri("https://example.org/MyBehaviour#init/1")
      iex> triple = TypeSystemBuilder.build_optional_callback_triple(callback_iri)
      iex> match?({^callback_iri, _, _}, triple) and elem(triple, 2) == Structure.OptionalCallbackSpec
      true
  """
  @spec build_optional_callback_triple(RDF.IRI.t()) :: RDF.Triple.t()
  def build_optional_callback_triple(callback_iri) do
    Helpers.type_triple(callback_iri, Structure.OptionalCallbackSpec)
  end

  # ===========================================================================
  # Public API - Type Expression Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a type expression AST.

  Takes a type expression AST (from @type definitions or @spec) and builds
  RDF triples representing the type structure. Returns a blank node representing
  the type expression and all associated triples.

  ## Parameters

  - `type_ast` - The type expression AST from Elixir's quote
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{type_node, triples}` where:
  - `type_node` - An RDF blank node representing the type expression
  - `triples` - List of RDF triples describing the type

  ## Examples

      iex> alias ElixirOntologies.Builders.{TypeSystemBuilder, Context}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {node, triples} = TypeSystemBuilder.build_type_expression({:|, [], [:ok, :error]}, context)
      iex> Enum.any?(triples, fn {^node, pred, _} -> pred == RDF.type() end)
      true
  """
  @spec build_type_expression(Macro.t(), Context.t()) :: {RDF.BlankNode.t(), [RDF.Triple.t()]}
  def build_type_expression(type_ast, context) do
    # TypeExpression.parse always succeeds (returns {:ok, result})
    {:ok, type_expr} = TypeExpression.parse(type_ast)
    build_from_type_expression(type_expr, context)
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

  # Build rdf:type triple based on spec_type
  # @spec -> FunctionSpec, @callback -> CallbackSpec, @macrocallback -> MacroCallbackSpec
  defp build_spec_class_triple(spec_iri, %FunctionSpec{spec_type: :spec}) do
    Helpers.type_triple(spec_iri, Structure.FunctionSpec)
  end

  defp build_spec_class_triple(spec_iri, %FunctionSpec{spec_type: :callback}) do
    Helpers.type_triple(spec_iri, Structure.CallbackSpec)
  end

  defp build_spec_class_triple(spec_iri, %FunctionSpec{spec_type: :macrocallback}) do
    Helpers.type_triple(spec_iri, Structure.MacroCallbackSpec)
  end

  # Fallback for specs without spec_type (backward compatibility)
  defp build_spec_class_triple(spec_iri, _func_spec) do
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
  # Note: Type definitions reference their body expression via referencesType
  defp build_type_expression_triples(type_iri, expression, context) do
    {expr_node, expr_triples} = build_type_expression(expression, context)

    # Link type definition to its expression (only if we got triples)
    if Enum.empty?(expr_triples) do
      []
    else
      link_triple = Helpers.object_property(type_iri, Structure.referencesType(), expr_node)
      [link_triple | expr_triples]
    end
  end

  # ===========================================================================
  # Type Expression Builders (Internal)
  # ===========================================================================

  # Build RDF from parsed TypeExpression struct
  @spec build_from_type_expression(TypeExpression.t(), Context.t()) ::
          {RDF.BlankNode.t(), [RDF.Triple.t()]}
  defp build_from_type_expression(%TypeExpression{kind: :union} = type_expr, context) do
    build_union_type(type_expr, context)
  end

  defp build_from_type_expression(%TypeExpression{kind: :basic} = type_expr, context) do
    build_basic_type(type_expr, context)
  end

  defp build_from_type_expression(%TypeExpression{kind: :literal} = type_expr, context) do
    build_literal_type(type_expr, context)
  end

  defp build_from_type_expression(%TypeExpression{kind: :tuple} = type_expr, context) do
    build_tuple_type(type_expr, context)
  end

  defp build_from_type_expression(%TypeExpression{kind: :list} = type_expr, context) do
    build_list_type(type_expr, context)
  end

  defp build_from_type_expression(%TypeExpression{kind: :map} = type_expr, context) do
    build_map_type(type_expr, context)
  end

  defp build_from_type_expression(%TypeExpression{kind: :function} = type_expr, context) do
    build_function_type_expr(type_expr, context)
  end

  defp build_from_type_expression(%TypeExpression{kind: :remote} = type_expr, context) do
    build_remote_type(type_expr, context)
  end

  defp build_from_type_expression(%TypeExpression{kind: :struct} = type_expr, context) do
    build_struct_type(type_expr, context)
  end

  defp build_from_type_expression(%TypeExpression{kind: :variable} = type_expr, context) do
    build_variable_type(type_expr, context)
  end

  defp build_from_type_expression(%TypeExpression{kind: :any}, _context) do
    # Any type - basic type with name "any"
    node = RDF.BlankNode.new()

    triples = [
      Helpers.type_triple(node, Structure.BasicType),
      Helpers.datatype_property(node, Structure.typeName(), "any", RDF.XSD.String)
    ]

    {node, triples}
  end

  defp build_from_type_expression(_type_expr, _context) do
    # Fallback for unknown kinds
    {RDF.BlankNode.new(), []}
  end

  # Build union type: structure:UnionType with structure:unionOf links
  @spec build_union_type(TypeExpression.t(), Context.t()) :: {RDF.BlankNode.t(), [RDF.Triple.t()]}
  defp build_union_type(%TypeExpression{kind: :union, elements: elements}, context) do
    union_node = RDF.BlankNode.new()

    # Type triple
    type_triple = Helpers.type_triple(union_node, Structure.UnionType)

    # Build each member type recursively and link with unionOf
    {member_triples, all_member_triples} =
      elements
      |> Enum.map(fn member_expr ->
        {member_node, member_triples} = build_from_type_expression(member_expr, context)
        union_of_triple = Helpers.object_property(union_node, Structure.unionOf(), member_node)
        {union_of_triple, member_triples}
      end)
      |> Enum.unzip()

    all_triples = [type_triple | member_triples] ++ List.flatten(all_member_triples)
    {union_node, all_triples}
  end

  # Build basic type: structure:BasicType with structure:typeName
  # For parameterized types like list(integer()), uses ParameterizedType class
  @spec build_basic_type(TypeExpression.t(), Context.t()) :: {RDF.BlankNode.t(), [RDF.Triple.t()]}
  defp build_basic_type(%TypeExpression{kind: :basic, name: name, elements: elements}, context) do
    node = RDF.BlankNode.new()

    # Determine if parameterized
    is_parameterized = elements && not Enum.empty?(elements)

    # Type triple - use ParameterizedType for parameterized, BasicType otherwise
    type_triple =
      if is_parameterized do
        Helpers.type_triple(node, Structure.ParameterizedType)
      else
        Helpers.type_triple(node, Structure.BasicType)
      end

    # Name triple
    name_str = if name, do: Atom.to_string(name), else: "unknown"
    name_triple = Helpers.datatype_property(node, Structure.typeName(), name_str, RDF.XSD.String)

    base_triples = [type_triple, name_triple]

    # If parameterized, add element types using elementType property
    param_triples =
      if is_parameterized do
        elements
        |> Enum.flat_map(fn element_expr ->
          {param_node, param_triples} = build_from_type_expression(element_expr, context)
          # Use elementType for type parameters (reusing list type property)
          param_link = Helpers.object_property(node, Structure.elementType(), param_node)
          [param_link | param_triples]
        end)
      else
        []
      end

    {node, base_triples ++ param_triples}
  end

  # Build literal type: structure:BasicType with literal value
  @spec build_literal_type(TypeExpression.t(), Context.t()) ::
          {RDF.BlankNode.t(), [RDF.Triple.t()]}
  defp build_literal_type(%TypeExpression{kind: :literal, name: name, metadata: metadata}, _context) do
    node = RDF.BlankNode.new()

    # Type triple - literals are represented as BasicType with literal value
    type_triple = Helpers.type_triple(node, Structure.BasicType)

    # For literal types, use the literal_type from metadata or the name
    literal_type = Map.get(metadata, :literal_type, :atom)

    name_triple =
      case literal_type do
        :atom when is_atom(name) ->
          Helpers.datatype_property(node, Structure.typeName(), Atom.to_string(name), RDF.XSD.String)

        :integer when is_integer(name) ->
          Helpers.datatype_property(node, Structure.typeName(), Integer.to_string(name), RDF.XSD.String)

        :range ->
          # For ranges, format as "start..end"
          range_start = Map.get(metadata, :range_start, 0)
          range_end = Map.get(metadata, :range_end, 0)
          Helpers.datatype_property(node, Structure.typeName(), "#{range_start}..#{range_end}", RDF.XSD.String)

        _ ->
          name_str = if name, do: to_string(name), else: "literal"
          Helpers.datatype_property(node, Structure.typeName(), name_str, RDF.XSD.String)
      end

    {node, [type_triple, name_triple]}
  end

  # Build tuple type: structure:TupleType with element types
  # Note: Using elementType property (same as ListType) for tuple elements
  @spec build_tuple_type(TypeExpression.t(), Context.t()) :: {RDF.BlankNode.t(), [RDF.Triple.t()]}
  defp build_tuple_type(%TypeExpression{kind: :tuple, elements: elements}, context) do
    node = RDF.BlankNode.new()

    type_triple = Helpers.type_triple(node, Structure.TupleType)

    element_triples =
      (elements || [])
      |> Enum.flat_map(fn element_expr ->
        {element_node, element_triples} = build_from_type_expression(element_expr, context)
        # Note: Using elementType for tuples (same as lists)
        element_link = Helpers.object_property(node, Structure.elementType(), element_node)
        [element_link | element_triples]
      end)

    {node, [type_triple | element_triples]}
  end

  # Build list type: structure:ListType with element type
  @spec build_list_type(TypeExpression.t(), Context.t()) :: {RDF.BlankNode.t(), [RDF.Triple.t()]}
  defp build_list_type(%TypeExpression{kind: :list, elements: elements}, context) do
    node = RDF.BlankNode.new()

    type_triple = Helpers.type_triple(node, Structure.ListType)

    element_triples =
      case elements do
        [element_expr | _] ->
          {element_node, element_triples} = build_from_type_expression(element_expr, context)
          element_link = Helpers.object_property(node, Structure.elementType(), element_node)
          [element_link | element_triples]

        _ ->
          []
      end

    {node, [type_triple | element_triples]}
  end

  # Build map type: structure:MapType with key/value types
  @spec build_map_type(TypeExpression.t(), Context.t()) :: {RDF.BlankNode.t(), [RDF.Triple.t()]}
  defp build_map_type(%TypeExpression{kind: :map, key_type: key_type, value_type: value_type}, context) do
    node = RDF.BlankNode.new()

    type_triple = Helpers.type_triple(node, Structure.MapType)

    key_triples =
      if key_type do
        {key_node, key_type_triples} = build_from_type_expression(key_type, context)
        key_link = Helpers.object_property(node, Structure.keyType(), key_node)
        [key_link | key_type_triples]
      else
        []
      end

    value_triples =
      if value_type do
        {value_node, value_type_triples} = build_from_type_expression(value_type, context)
        value_link = Helpers.object_property(node, Structure.valueType(), value_node)
        [value_link | value_type_triples]
      else
        []
      end

    {node, [type_triple] ++ key_triples ++ value_triples}
  end

  # Build function type: structure:FunctionType with param/return types
  @spec build_function_type_expr(TypeExpression.t(), Context.t()) ::
          {RDF.BlankNode.t(), [RDF.Triple.t()]}
  defp build_function_type_expr(
         %TypeExpression{kind: :function, param_types: param_types, return_type: return_type},
         context
       ) do
    node = RDF.BlankNode.new()

    type_triple = Helpers.type_triple(node, Structure.FunctionType)

    param_triples =
      (param_types || [])
      |> Enum.flat_map(fn param_expr ->
        {param_node, param_type_triples} = build_from_type_expression(param_expr, context)
        param_link = Helpers.object_property(node, Structure.hasParameterType(), param_node)
        [param_link | param_type_triples]
      end)

    return_triples =
      if return_type do
        {return_node, return_type_triples} = build_from_type_expression(return_type, context)
        return_link = Helpers.object_property(node, Structure.hasReturnType(), return_node)
        [return_link | return_type_triples]
      else
        []
      end

    {node, [type_triple] ++ param_triples ++ return_triples}
  end

  # Build remote type: references external module type
  @spec build_remote_type(TypeExpression.t(), Context.t()) ::
          {RDF.BlankNode.t(), [RDF.Triple.t()]}
  defp build_remote_type(%TypeExpression{kind: :remote, module: module, name: name}, _context) do
    node = RDF.BlankNode.new()

    # Use BasicType for now - ParameterizedType would be for generic remote types
    type_triple = Helpers.type_triple(node, Structure.BasicType)

    # Format module.type name
    module_str = if module, do: Enum.map_join(module, ".", &Atom.to_string/1), else: ""
    name_str = if name, do: Atom.to_string(name), else: "t"
    full_name = "#{module_str}.#{name_str}"

    name_triple = Helpers.datatype_property(node, Structure.typeName(), full_name, RDF.XSD.String)

    {node, [type_triple, name_triple]}
  end

  # Build struct type: structure:StructType
  @spec build_struct_type(TypeExpression.t(), Context.t()) ::
          {RDF.BlankNode.t(), [RDF.Triple.t()]}
  defp build_struct_type(%TypeExpression{kind: :struct, module: module}, _context) do
    node = RDF.BlankNode.new()

    # Use BasicType with struct name for now
    type_triple = Helpers.type_triple(node, Structure.BasicType)

    module_str =
      case module do
        nil -> "%{}"
        mods when is_list(mods) -> "%" <> Enum.map_join(mods, ".", &Atom.to_string/1) <> "{}"
        mod when is_atom(mod) -> "%" <> Atom.to_string(mod) <> "{}"
      end

    name_triple = Helpers.datatype_property(node, Structure.typeName(), module_str, RDF.XSD.String)

    {node, [type_triple, name_triple]}
  end

  # Build type variable: structure:TypeVariable
  # Note: Using typeName property for variable name (variableName not in ontology)
  @spec build_variable_type(TypeExpression.t(), Context.t()) ::
          {RDF.BlankNode.t(), [RDF.Triple.t()]}
  defp build_variable_type(%TypeExpression{kind: :variable, name: name}, _context) do
    node = RDF.BlankNode.new()

    type_triple = Helpers.type_triple(node, Structure.TypeVariable)
    name_str = if name, do: Atom.to_string(name), else: "var"
    # Using typeName for variable name since variableName doesn't exist in ontology
    name_triple = Helpers.datatype_property(node, Structure.typeName(), name_str, RDF.XSD.String)

    {node, [type_triple, name_triple]}
  end

  # Build triples for parameter types in a function spec
  # Planned for Phase 14.3: Create RDF list for ordered parameter types
  defp build_parameter_types_triples(_spec_iri, parameter_types, _context) do
    _param_type_nodes =
      parameter_types
      |> Enum.map(fn _param_type_ast ->
        RDF.BlankNode.new()
      end)

    []
  end

  # Build triples for return type in a function spec
  # Planned for Phase 14.3: Build type expression for return type
  defp build_return_type_triples(_spec_iri, _return_type_ast, _context) do
    []
  end

  # Build triples for type constraints from `when` clause
  # Planned for Phase 14.3: Build type constraint triples
  defp build_type_constraints_triples(_spec_iri, _type_constraints, _context) do
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
