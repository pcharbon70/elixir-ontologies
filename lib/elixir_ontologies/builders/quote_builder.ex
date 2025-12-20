defmodule ElixirOntologies.Builders.QuoteBuilder do
  @moduledoc """
  Builds RDF triples for quote blocks and unquote expressions.

  This module transforms `ElixirOntologies.Extractors.Quote` results into RDF
  triples following the elixir-structure.ttl ontology. It handles:

  - Quote block type and options
  - Unquote expression linking
  - Hygiene violation tracking
  - Quote option properties (context, bind_quoted, etc.)

  ## Usage

      alias ElixirOntologies.Builders.{QuoteBuilder, Context}
      alias ElixirOntologies.Extractors.Quote.QuotedExpression

      quote_expr = %QuotedExpression{
        body: {:+, [], [1, 2]},
        options: %QuoteOptions{context: :match},
        unquotes: [],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      # Module and index are passed via options
      {quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

  ## Examples

      iex> alias ElixirOntologies.Builders.{QuoteBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Quote.{QuotedExpression, QuoteOptions}
      iex> quote_expr = %QuotedExpression{
      ...>   body: :ok,
      ...>   options: %QuoteOptions{},
      ...>   unquotes: [],
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {quote_iri, _triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)
      iex> to_string(quote_iri) =~ "quote"
      true
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.Quote.{QuotedExpression, QuoteOptions, UnquoteExpression, HygieneViolation}
  alias NS.Structure

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for a quote block.

  Takes a quote expression extraction result and builder context, returns the
  quote IRI and a list of RDF triples.

  ## Parameters

  - `quote_expr` - QuotedExpression struct from extraction
  - `context` - Builder context with base IRI
  - `opts` - Options including `:module` (required) and `:index` (required)

  ## Options

  - `:module` - The module containing the quote (required, as list of atoms)
  - `:index` - Index of the quote within the module (required)
  - `:hygiene_violations` - List of HygieneViolation structs to include (optional)

  ## Returns

  A tuple `{quote_iri, triples}` where:
  - `quote_iri` - The IRI of the quote block
  - `triples` - List of RDF triples describing the quote

  ## Examples

      iex> alias ElixirOntologies.Builders.{QuoteBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Quote.{QuotedExpression, QuoteOptions}
      iex> quote_expr = %QuotedExpression{
      ...>   body: {:+, [], [1, 2]},
      ...>   options: %QuoteOptions{context: :match},
      ...>   unquotes: [],
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)
      iex> length(triples) > 0
      true
  """
  @spec build(QuotedExpression.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(quote_expr, context, opts \\ []) do
    build_quote_block(quote_expr, context, opts)
  end

  @doc """
  Builds RDF triples for a quote block with options.

  This is the full-featured version that accepts all options.

  ## Examples

      iex> alias ElixirOntologies.Builders.{QuoteBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Quote.{QuotedExpression, QuoteOptions}
      iex> quote_expr = %QuotedExpression{
      ...>   body: :ok,
      ...>   options: %QuoteOptions{bind_quoted: [x: 1]},
      ...>   unquotes: [],
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = QuoteBuilder.build_quote_block(quote_expr, context, module: [:MyApp], index: 0)
      iex> to_string(iri) =~ "quote"
      true
  """
  @spec build_quote_block(QuotedExpression.t(), Context.t(), keyword()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_quote_block(quote_expr, context, opts) do
    # Get module and index from options
    module_name = get_module_name(opts)
    index = Keyword.get(opts, :index, 0)

    # Generate quote IRI
    quote_iri = IRI.for_quote(context.base_iri, module_name, index)

    # Build all triples
    hygiene_violations = Keyword.get(opts, :hygiene_violations, [])

    triples =
      [
        build_type_triple(quote_iri)
      ] ++
        build_options_triples(quote_iri, quote_expr.options) ++
        build_unquote_triples(quote_iri, quote_expr.unquotes, context) ++
        build_hygiene_triples(quote_iri, hygiene_violations, context) ++
        build_location_triple(quote_iri, quote_expr, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {quote_iri, triples}
  end

  @doc """
  Builds RDF triples for an unquote expression.

  ## Parameters

  - `unquote_expr` - UnquoteExpression struct from extraction
  - `context` - Builder context with base IRI
  - `opts` - Options including `:quote_iri` (required) and `:index` (required)

  ## Examples

      iex> alias ElixirOntologies.Builders.{QuoteBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Quote.UnquoteExpression
      iex> unquote_expr = %UnquoteExpression{
      ...>   kind: :unquote,
      ...>   value: {:x, [], nil},
      ...>   depth: 1,
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> quote_iri = RDF.iri("https://example.org/code#MyApp/quote/0")
      iex> {unquote_iri, _triples} = QuoteBuilder.build_unquote(unquote_expr, context, quote_iri: quote_iri, index: 0)
      iex> to_string(unquote_iri) =~ "unquote"
      true
  """
  @spec build_unquote(UnquoteExpression.t(), Context.t(), keyword()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_unquote(unquote_expr, context, opts) do
    quote_iri = Keyword.fetch!(opts, :quote_iri)
    index = Keyword.get(opts, :index, 0)

    # Generate unquote IRI
    unquote_iri = IRI.for_unquote(quote_iri, index)

    # Build triples
    triples =
      [
        build_unquote_type_triple(unquote_iri, unquote_expr),
        build_unquote_depth_triple(unquote_iri, unquote_expr)
      ] ++ build_unquote_location_triple(unquote_iri, unquote_expr, context)

    triples = List.flatten(triples) |> Enum.uniq()

    {unquote_iri, triples}
  end

  @doc """
  Builds RDF triples for a hygiene violation.

  ## Parameters

  - `violation` - HygieneViolation struct from extraction
  - `context` - Builder context with base IRI
  - `opts` - Options including `:quote_iri` (required) and `:index` (required)

  ## Examples

      iex> alias ElixirOntologies.Builders.{QuoteBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Quote.HygieneViolation
      iex> violation = %HygieneViolation{
      ...>   type: :var_bang,
      ...>   variable: :x,
      ...>   context: nil,
      ...>   metadata: %{}
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> quote_iri = RDF.iri("https://example.org/code#MyApp/quote/0")
      iex> {violation_iri, _triples} = QuoteBuilder.build_hygiene_violation(violation, context, quote_iri: quote_iri, index: 0)
      iex> to_string(violation_iri) =~ "hygiene"
      true
  """
  @spec build_hygiene_violation(HygieneViolation.t(), Context.t(), keyword()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_hygiene_violation(violation, context, opts) do
    quote_iri = Keyword.fetch!(opts, :quote_iri)
    index = Keyword.get(opts, :index, 0)

    # Generate hygiene IRI
    violation_iri = IRI.for_hygiene_violation(quote_iri, index)

    # Build triples
    triples =
      [
        Helpers.type_triple(violation_iri, Structure.Hygiene),
        build_violation_type_triple(violation_iri, violation)
      ] ++
        build_violation_variable_triple(violation_iri, violation) ++
        build_violation_context_triple(violation_iri, violation) ++
        build_violation_location_triple(violation_iri, violation, context)

    triples = List.flatten(triples) |> Enum.uniq()

    {violation_iri, triples}
  end

  # ===========================================================================
  # Module Name Extraction
  # ===========================================================================

  defp get_module_name(opts) do
    case Keyword.get(opts, :module) do
      nil -> "Unknown"
      parts when is_list(parts) -> Enum.map_join(parts, ".", &Atom.to_string/1)
      atom when is_atom(atom) -> Atom.to_string(atom) |> String.replace_prefix("Elixir.", "")
      str when is_binary(str) -> str
    end
  end

  # ===========================================================================
  # Quote Triple Generation
  # ===========================================================================

  # Build rdf:type triple for quote
  defp build_type_triple(quote_iri) do
    Helpers.type_triple(quote_iri, Structure.QuotedExpression)
  end

  # Build quote options triples
  defp build_options_triples(quote_iri, %QuoteOptions{} = options) do
    triples = []

    # Context option
    triples =
      if options.context do
        context_str =
          case options.context do
            ctx when is_atom(ctx) -> Atom.to_string(ctx)
            ctx -> inspect(ctx)
          end

        [
          Helpers.datatype_property(
            quote_iri,
            Structure.quoteContext(),
            context_str,
            RDF.XSD.String
          )
          | triples
        ]
      else
        triples
      end

    # Bind quoted option
    triples =
      if options.bind_quoted && options.bind_quoted != [] do
        [
          Helpers.datatype_property(
            quote_iri,
            Structure.hasBindQuoted(),
            true,
            RDF.XSD.Boolean
          )
          | triples
        ]
      else
        triples
      end

    # Location :keep option
    triples =
      if options.location == :keep do
        [
          Helpers.datatype_property(
            quote_iri,
            Structure.locationKeep(),
            true,
            RDF.XSD.Boolean
          )
          | triples
        ]
      else
        triples
      end

    # Unquote disabled option
    triples =
      if options.unquote == false do
        [
          Helpers.datatype_property(
            quote_iri,
            Structure.unquoteEnabled(),
            false,
            RDF.XSD.Boolean
          )
          | triples
        ]
      else
        triples
      end

    # Generated option
    triples =
      if options.generated == true do
        [
          Helpers.datatype_property(
            quote_iri,
            Structure.isGenerated(),
            true,
            RDF.XSD.Boolean
          )
          | triples
        ]
      else
        triples
      end

    triples
  end

  # Build unquote triples and links
  defp build_unquote_triples(quote_iri, unquotes, context) when is_list(unquotes) do
    unquotes
    |> Enum.with_index()
    |> Enum.flat_map(fn {unquote_expr, idx} ->
      {unquote_iri, unquote_triples} =
        build_unquote(unquote_expr, context, quote_iri: quote_iri, index: idx)

      # Link from quote to unquote
      link_triple =
        Helpers.object_property(quote_iri, Structure.containsUnquote(), unquote_iri)

      [link_triple | unquote_triples]
    end)
  end

  # Build hygiene violation triples and links
  defp build_hygiene_triples(quote_iri, violations, context) when is_list(violations) do
    violations
    |> Enum.with_index()
    |> Enum.flat_map(fn {violation, idx} ->
      {violation_iri, violation_triples} =
        build_hygiene_violation(violation, context, quote_iri: quote_iri, index: idx)

      # Link from quote to violation
      link_triple =
        Helpers.object_property(quote_iri, Structure.hasHygieneViolation(), violation_iri)

      [link_triple | violation_triples]
    end)
  end

  # Build location triple for quote
  defp build_location_triple(_quote_iri, %{location: nil}, _context), do: []

  defp build_location_triple(quote_iri, quote_expr, context) do
    location = quote_expr.location

    case location do
      %{start_line: line} when is_integer(line) and line > 0 ->
        location_iri = generate_location_iri(quote_iri, location)

        [
          Helpers.object_property(quote_iri, NS.Core.hasSourceLocation(), location_iri),
          build_location_line_triples(location_iri, location, context)
        ]

      _ ->
        []
    end
  end

  # ===========================================================================
  # Unquote Triple Generation
  # ===========================================================================

  # Build type triple for unquote (regular or splicing)
  defp build_unquote_type_triple(unquote_iri, %UnquoteExpression{kind: :unquote_splicing}) do
    Helpers.type_triple(unquote_iri, Structure.UnquoteSplicingExpression)
  end

  defp build_unquote_type_triple(unquote_iri, %UnquoteExpression{kind: :unquote}) do
    Helpers.type_triple(unquote_iri, Structure.UnquoteExpression)
  end

  # Build depth triple for unquote
  defp build_unquote_depth_triple(unquote_iri, %UnquoteExpression{depth: depth}) do
    Helpers.datatype_property(
      unquote_iri,
      Structure.unquoteDepth(),
      depth,
      RDF.XSD.PositiveInteger
    )
  end

  # Build location triple for unquote
  defp build_unquote_location_triple(_unquote_iri, %{location: nil}, _context), do: []

  defp build_unquote_location_triple(unquote_iri, unquote_expr, context) do
    location = unquote_expr.location

    case location do
      %{start_line: line} when is_integer(line) and line > 0 ->
        location_iri = generate_location_iri(unquote_iri, location)

        [
          Helpers.object_property(unquote_iri, NS.Core.hasSourceLocation(), location_iri),
          build_location_line_triples(location_iri, location, context)
        ]

      _ ->
        []
    end
  end

  # ===========================================================================
  # Hygiene Violation Triple Generation
  # ===========================================================================

  # Build violation type triple
  defp build_violation_type_triple(violation_iri, %HygieneViolation{type: type}) do
    Helpers.datatype_property(
      violation_iri,
      Structure.violationType(),
      Atom.to_string(type),
      RDF.XSD.String
    )
  end

  # Build violation variable triple
  defp build_violation_variable_triple(_violation_iri, %HygieneViolation{variable: nil}), do: []

  defp build_violation_variable_triple(violation_iri, %HygieneViolation{variable: variable}) do
    [
      Helpers.datatype_property(
        violation_iri,
        Structure.unhygienicVariable(),
        Atom.to_string(variable),
        RDF.XSD.String
      )
    ]
  end

  # Build violation context triple
  defp build_violation_context_triple(_violation_iri, %HygieneViolation{context: nil}), do: []

  defp build_violation_context_triple(violation_iri, %HygieneViolation{context: context}) do
    context_str =
      case context do
        ctx when is_atom(ctx) -> Atom.to_string(ctx)
        ctx -> inspect(ctx)
      end

    [
      Helpers.datatype_property(
        violation_iri,
        Structure.hygieneContext(),
        context_str,
        RDF.XSD.String
      )
    ]
  end

  # Build location triple for hygiene violation
  defp build_violation_location_triple(_violation_iri, %{location: nil}, _context), do: []

  defp build_violation_location_triple(violation_iri, violation, context) do
    location = violation.location

    case location do
      %{start_line: line} when is_integer(line) and line > 0 ->
        location_iri = generate_location_iri(violation_iri, location)

        [
          Helpers.object_property(violation_iri, NS.Core.hasSourceLocation(), location_iri),
          build_location_line_triples(location_iri, location, context)
        ]

      _ ->
        []
    end
  end

  # ===========================================================================
  # Location Helpers
  # ===========================================================================

  defp generate_location_iri(parent_iri, location) do
    line = location.start_line || 0
    end_line = location.end_line || line

    RDF.iri("#{parent_iri}/L#{line}-#{end_line}")
  end

  defp build_location_line_triples(location_iri, location, _context) do
    triples = [Helpers.type_triple(location_iri, NS.Core.SourceLocation)]

    triples =
      if location.start_line do
        [
          Helpers.datatype_property(
            location_iri,
            NS.Core.startLine(),
            location.start_line,
            RDF.XSD.PositiveInteger
          )
          | triples
        ]
      else
        triples
      end

    triples =
      if location.end_line do
        [
          Helpers.datatype_property(
            location_iri,
            NS.Core.endLine(),
            location.end_line,
            RDF.XSD.PositiveInteger
          )
          | triples
        ]
      else
        triples
      end

    triples
  end
end
