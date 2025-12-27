defmodule ElixirOntologies.Builders.ClauseBuilder do
  @moduledoc """
  Builds RDF triples for function clauses with their heads and bodies.

  This module transforms `ElixirOntologies.Extractors.Clause` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Clause ordering (clauseOrder property, 1-indexed)
  - Nested structures (FunctionHead and FunctionBody as blank nodes)
  - Ordered parameter lists (RDF lists preserving pattern-match order)
  - Parameter type classification (Parameter, DefaultParameter, PatternParameter)
  - Guard expressions if present
  - Clause-to-function relationships (hasClause property)

  ## Key Indexing Conventions

  **IRIs use 0-indexed ordering**:
  - First clause: `<function_iri>/clause/0`
  - First parameter: `<clause_iri>/param/0`

  **RDF properties use 1-indexed ordering**:
  - First clause: `clauseOrder "1"^^xsd:positiveInteger`
  - First parameter: `parameterPosition "1"^^xsd:positiveInteger`

  ## Usage

      alias ElixirOntologies.Builders.{ClauseBuilder, Context}
      alias ElixirOntologies.Extractors.Clause

      clause_info = %Clause{
        name: :get_user,
        arity: 1,
        visibility: :public,
        order: 1,
        head: %{
          parameters: [{:id, [], nil}],
          guard: nil
        },
        body: quote(do: :ok),
        location: nil,
        metadata: %{}
      }

      function_iri = ~I<https://example.org/code#MyApp/get_user/1>
      context = Context.new(base_iri: "https://example.org/code#")
      {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # clause_iri => ~I<https://example.org/code#MyApp/get_user/1/clause/0>
      # triples => [
      #   {clause_iri, RDF.type(), Structure.FunctionClause},
      #   {clause_iri, Structure.clauseOrder(), 1},
      #   {function_iri, Structure.hasClause(), clause_iri},
      #   ...
      # ]

  ## Examples

      iex> alias ElixirOntologies.Builders.{ClauseBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Clause
      iex> clause_info = %Clause{
      ...>   name: :hello,
      ...>   arity: 0,
      ...>   visibility: :public,
      ...>   order: 1,
      ...>   head: %{parameters: [], guard: nil},
      ...>   body: quote(do: :ok),
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> function_iri = ~I<https://example.org/code#MyApp/hello/0>
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {clause_iri, _triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)
      iex> to_string(clause_iri)
      "https://example.org/code#MyApp/hello/0/clause/0"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.{Clause, Parameter}
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a function clause.

  Takes a clause extraction result and builder context, returns the clause IRI
  and a list of RDF triples representing the clause structure including head,
  body, and parameters.

  ## Parameters

  - `clause_info` - Clause extraction result from `Extractors.Clause.extract/1`
  - `function_iri` - The IRI of the parent function
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{clause_iri, triples}` where:
  - `clause_iri` - The IRI of the clause (0-indexed path)
  - `triples` - List of RDF triples describing the clause structure

  ## Examples

      iex> alias ElixirOntologies.Builders.{ClauseBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Clause
      iex> clause_info = %Clause{
      ...>   name: :test,
      ...>   arity: 1,
      ...>   visibility: :public,
      ...>   order: 1,
      ...>   head: %{parameters: [{:x, [], nil}], guard: nil},
      ...>   body: quote(do: :ok),
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> function_iri = ~I<https://example.org/code#MyApp/test/1>
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^clause_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build_clause(Clause.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_clause(clause_info, function_iri, context) do
    # Generate clause IRI (convert 1-indexed order to 0-indexed for IRI)
    clause_iri = generate_clause_iri(clause_info, function_iri)

    # Build all triples
    triples = []

    # Core clause triples (type, order, hasClause)
    triples = triples ++ build_core_clause_triples(clause_iri, clause_info, function_iri)

    # FunctionHead triples (includes parameters and guard)
    {head_bnode, head_triples} = build_function_head(clause_iri, clause_info, context)

    triples =
      triples ++
        head_triples ++ [Helpers.object_property(clause_iri, Structure.hasHead(), head_bnode)]

    # FunctionBody triples
    {body_bnode, body_triples} = build_function_body(clause_info)

    triples =
      triples ++
        body_triples ++ [Helpers.object_property(clause_iri, Structure.hasBody(), body_bnode)]

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {clause_iri, triples}
  end

  # ===========================================================================
  # Core Clause Triple Generation
  # ===========================================================================

  # Generate clause IRI (convert 1-indexed order to 0-indexed)
  defp generate_clause_iri(clause_info, function_iri) do
    # Clause order is 1-indexed in extractor, but IRI uses 0-indexed
    clause_index = clause_info.order - 1
    IRI.for_clause(function_iri, clause_index)
  end

  # Build core clause triples: type, clauseOrder, hasClause
  defp build_core_clause_triples(clause_iri, clause_info, function_iri) do
    [
      # rdf:type struct:FunctionClause
      Helpers.type_triple(clause_iri, Structure.FunctionClause),
      # struct:clauseOrder (1-indexed)
      Helpers.datatype_property(
        clause_iri,
        Structure.clauseOrder(),
        clause_info.order,
        RDF.XSD.PositiveInteger
      ),
      # function struct:hasClause clause
      Helpers.object_property(function_iri, Structure.hasClause(), clause_iri)
    ]
  end

  # ===========================================================================
  # FunctionHead Building
  # ===========================================================================

  # Build FunctionHead with parameters and optional guard
  defp build_function_head(clause_iri, clause_info, context) do
    head_bnode = Helpers.blank_node("function_head")

    # Extract parameters
    {parameter_iris, parameter_triples} = build_parameters(clause_iri, clause_info, context)

    # Build RDF list for parameters
    {list_head, list_triples} = Helpers.build_rdf_list(parameter_iris)

    # Head triples
    # Guard triples if present
    head_triples =
      [
        # rdf:type struct:FunctionHead
        Helpers.type_triple(head_bnode, Structure.FunctionHead),
        # struct:hasParameters <list_head>
        Helpers.object_property(head_bnode, Structure.hasParameters(), list_head)
      ] ++
        build_guard_triples(head_bnode, clause_info)

    # Combine all triples
    all_triples = head_triples ++ parameter_triples ++ list_triples

    {head_bnode, all_triples}
  end

  # Build guard triples if guard is present
  defp build_guard_triples(head_bnode, clause_info) do
    case clause_info.head[:guard] do
      nil ->
        []

      _guard_ast ->
        guard_bnode = Helpers.blank_node("guard")

        [
          # rdf:type core:GuardClause
          Helpers.type_triple(guard_bnode, Core.GuardClause),
          # head core:hasGuard guard
          Helpers.object_property(head_bnode, Core.hasGuard(), guard_bnode)
        ]
    end
  end

  # ===========================================================================
  # Parameter Building
  # ===========================================================================

  # Build parameter IRIs and triples from clause head
  defp build_parameters(clause_iri, clause_info, context) do
    # Extract parameters from clause head
    parameter_asts = clause_info.head[:parameters] || []

    # Extract each parameter with position
    parameters =
      parameter_asts
      |> Enum.with_index()
      |> Enum.map(fn {param_ast, index} ->
        case Parameter.extract(param_ast, position: index) do
          {:ok, param} -> param
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Build IRIs and triples for each parameter
    {parameter_iris, all_parameter_triples} =
      parameters
      |> Enum.reduce({[], []}, fn param, {iris, triples} ->
        param_iri = IRI.for_parameter(clause_iri, param.position)
        param_triples = build_parameter_triples(param_iri, param, context)

        {iris ++ [param_iri], triples ++ param_triples}
      end)

    {parameter_iris, all_parameter_triples}
  end

  # Build RDF triples for a single parameter
  defp build_parameter_triples(param_iri, param, _context) do
    # Determine parameter class based on type
    param_class = determine_parameter_class(param)

    triples = [
      # rdf:type (Parameter, DefaultParameter, or PatternParameter)
      Helpers.type_triple(param_iri, param_class),
      # struct:parameterPosition (1-indexed)
      Helpers.datatype_property(
        param_iri,
        Structure.parameterPosition(),
        param.position + 1,
        RDF.XSD.PositiveInteger
      )
    ]

    # Add parameterName if present
    triples =
      if param.name do
        triples ++
          [
            Helpers.datatype_property(
              param_iri,
              Structure.parameterName(),
              Atom.to_string(param.name),
              RDF.XSD.String
            )
          ]
      else
        triples
      end

    triples
  end

  # Determine parameter RDF class based on type
  defp determine_parameter_class(%Parameter{type: :simple}), do: Structure.Parameter
  defp determine_parameter_class(%Parameter{type: :default}), do: Structure.DefaultParameter
  defp determine_parameter_class(%Parameter{type: :pattern}), do: Structure.PatternParameter
  defp determine_parameter_class(%Parameter{type: :pin}), do: Structure.PatternParameter

  # ===========================================================================
  # FunctionBody Building
  # ===========================================================================

  # Build FunctionBody blank node
  defp build_function_body(_clause_info) do
    body_bnode = Helpers.blank_node("function_body")

    body_triples = [
      # rdf:type struct:FunctionBody
      Helpers.type_triple(body_bnode, Structure.FunctionBody)
    ]

    {body_bnode, body_triples}
  end
end
