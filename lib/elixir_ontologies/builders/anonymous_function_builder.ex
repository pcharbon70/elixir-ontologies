defmodule ElixirOntologies.Builders.AnonymousFunctionBuilder do
  @moduledoc """
  Builds RDF triples for Elixir anonymous functions.

  This module transforms `ElixirOntologies.Extractors.AnonymousFunction` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Anonymous function type classification (struct:AnonymousFunction)
  - Arity property (struct:arity)
  - Clause relationships (struct:hasClause, struct:hasClauses)
  - Source location information (core:hasSourceLocation)

  ## Usage

      alias ElixirOntologies.Builders.{AnonymousFunctionBuilder, Context}
      alias ElixirOntologies.Extractors.AnonymousFunction

      ast = quote do: fn x -> x + 1 end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(
        base_iri: "https://example.org/code#",
        metadata: %{module: [:MyApp]}
      )

      {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # anon_iri => ~I<https://example.org/code#MyApp/anon/0>
      # triples => [
      #   {anon_iri, RDF.type(), Structure.AnonymousFunction},
      #   {anon_iri, Structure.arity(), 1},
      #   ...
      # ]

  ## Examples

      iex> alias ElixirOntologies.Builders.{AnonymousFunctionBuilder, Context}
      iex> alias ElixirOntologies.Extractors.AnonymousFunction
      iex> ast = quote do: fn x -> x + 1 end
      iex> {:ok, anon} = AnonymousFunction.extract(ast)
      iex> context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      iex> {anon_iri, _triples} = AnonymousFunctionBuilder.build(anon, context, 0)
      iex> to_string(anon_iri)
      "https://example.org/code#MyApp/anon/0"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.AnonymousFunction
  alias NS.{Structure, Core}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for an anonymous function.

  Takes an anonymous function extraction result, builder context, and an index
  for generating a unique IRI. Returns the anonymous function IRI and a list
  of RDF triples.

  ## Parameters

  - `anon_info` - AnonymousFunction extraction result
  - `context` - Builder context with base IRI and optional module context
  - `index` - Index of the anonymous function within its context (for unique IRI)

  ## Returns

  A tuple `{anon_iri, triples}` where:
  - `anon_iri` - The IRI of the anonymous function
  - `triples` - List of RDF triples describing the anonymous function

  ## Examples

      iex> alias ElixirOntologies.Builders.{AnonymousFunctionBuilder, Context}
      iex> alias ElixirOntologies.Extractors.AnonymousFunction
      iex> ast = quote do: fn -> :ok end
      iex> {:ok, anon} = AnonymousFunction.extract(ast)
      iex> context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      iex> {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^anon_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build(AnonymousFunction.t(), Context.t(), non_neg_integer()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(anon_info, context, index) do
    # Generate anonymous function IRI
    anon_iri = generate_anon_iri(context, index)

    # Build all triples
    triples =
      [
        # Core anonymous function triples
        build_type_triple(anon_iri),
        build_arity_triple(anon_iri, anon_info)
      ] ++
        build_clause_triples(anon_iri, anon_info) ++
        build_location_triple(anon_iri, anon_info, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {anon_iri, triples}
  end

  # ===========================================================================
  # Core Triple Generation
  # ===========================================================================

  # Generate anonymous function IRI based on context
  defp generate_anon_iri(context, index) do
    context_iri = Context.get_context_iri(context, "anonymous")
    IRI.for_anonymous_function(context_iri, index)
  end

  # Build rdf:type triple
  defp build_type_triple(anon_iri) do
    Helpers.type_triple(anon_iri, Structure.AnonymousFunction)
  end

  # Build struct:arity datatype property
  defp build_arity_triple(anon_iri, anon_info) do
    Helpers.datatype_property(
      anon_iri,
      Structure.arity(),
      anon_info.arity,
      RDF.XSD.NonNegativeInteger
    )
  end

  # ===========================================================================
  # Clause Triple Generation
  # ===========================================================================

  # Build triples for all clauses
  defp build_clause_triples(anon_iri, anon_info) do
    clauses = anon_info.clauses

    clause_triples =
      clauses
      |> Enum.with_index()
      |> Enum.flat_map(fn {clause, idx} ->
        build_single_clause_triples(anon_iri, clause, idx)
      end)

    # Build hasClause relationships
    clause_iris =
      clauses
      |> Enum.with_index()
      |> Enum.map(fn {_clause, idx} -> IRI.for_anonymous_clause(anon_iri, idx) end)

    has_clause_triples =
      Enum.map(clause_iris, fn clause_iri ->
        Helpers.object_property(anon_iri, Structure.hasClause(), clause_iri)
      end)

    # Build hasClauses list if multiple clauses
    {_list_head, list_triples} =
      if length(clause_iris) > 1 do
        Helpers.build_rdf_list(clause_iris)
      else
        {nil, []}
      end

    has_clauses_triples =
      if length(clause_iris) > 1 do
        {list_head, _} = Helpers.build_rdf_list(clause_iris)
        [Helpers.object_property(anon_iri, Structure.hasClauses(), list_head)]
      else
        []
      end

    clause_triples ++ has_clause_triples ++ list_triples ++ has_clauses_triples
  end

  # Build triples for a single clause
  defp build_single_clause_triples(anon_iri, clause, index) do
    clause_iri = IRI.for_anonymous_clause(anon_iri, index)

    base_triples = [
      # rdf:type
      Helpers.type_triple(clause_iri, Structure.FunctionClause),
      # struct:clauseOrder (1-indexed as per ontology convention)
      Helpers.datatype_property(
        clause_iri,
        Structure.clauseOrder(),
        index + 1,
        RDF.XSD.PositiveInteger
      )
    ]

    # Add guard triple if present
    guard_triples =
      if clause.guard do
        [
          Helpers.datatype_property(
            clause_iri,
            Core.hasGuard(),
            true,
            RDF.XSD.Boolean
          )
        ]
      else
        []
      end

    base_triples ++ guard_triples
  end

  # ===========================================================================
  # Source Location
  # ===========================================================================

  # Build core:hasSourceLocation triple if location information available
  defp build_location_triple(anon_iri, anon_info, context) do
    case {anon_info.location, context.file_path} do
      {nil, _} ->
        []

      {_location, nil} ->
        # Location exists but no file path - skip location triple
        []

      {location, file_path} ->
        file_iri = IRI.for_source_file(context.base_iri, file_path)

        # Need end line - use start line if end not available
        start_line = Map.get(location, :start_line) || Map.get(location, :line)
        end_line = Map.get(location, :end_line) || start_line

        if start_line do
          location_iri = IRI.for_source_location(file_iri, start_line, end_line)
          [Helpers.object_property(anon_iri, Core.hasSourceLocation(), location_iri)]
        else
          []
        end
    end
  end
end
