defmodule ElixirOntologies.Builders.ClosureBuilder do
  @moduledoc """
  Builds RDF triples for closure semantics in anonymous functions.

  This module extends anonymous function representations with closure-specific
  triples when the function captures variables from its enclosing scope. It
  uses the `Closure.analyze_closure/1` function to detect free variables and
  generates appropriate RDF triples.

  ## Closure Detection

  A function is considered a closure if it references variables that are not
  bound by its parameters. These "free variables" must be captured from the
  enclosing scope.

  ## Generated Triples

  For each captured variable, this builder generates:
  - `core:capturesVariable` linking the closure to a variable IRI
  - Variable type triple (`rdf:type core:Variable`)
  - Variable name triple (`core:name`)

  ## Usage

      alias ElixirOntologies.Builders.{ClosureBuilder, Context}
      alias ElixirOntologies.Extractors.AnonymousFunction

      ast = quote do: fn -> x + y end  # captures x and y
      {:ok, anon} = AnonymousFunction.extract(ast)

      anon_iri = ~I<https://example.org/code#MyApp/anon/0>
      context = Context.new(base_iri: "https://example.org/code#")

      triples = ClosureBuilder.build_closure(anon, anon_iri, context)
      # Returns triples for captured variables

  ## Examples

      iex> alias ElixirOntologies.Builders.{ClosureBuilder, Context}
      iex> alias ElixirOntologies.Extractors.AnonymousFunction
      iex> ast = quote do: fn -> x + 1 end
      iex> {:ok, anon} = AnonymousFunction.extract(ast)
      iex> anon_iri = RDF.iri("https://example.org/code#MyApp/anon/0")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = ClosureBuilder.build_closure(anon, anon_iri, context)
      iex> length(triples) > 0
      true
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.{AnonymousFunction, Closure}
  alias NS.Core

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds closure-specific RDF triples for an anonymous function.

  Analyzes the anonymous function for free variables and generates triples
  for each captured variable. If the function has no captures (is not a
  closure), returns an empty list.

  ## Parameters

  - `anon_info` - AnonymousFunction extraction result
  - `anon_iri` - The IRI of the anonymous function (already generated)
  - `context` - Builder context

  ## Returns

  A list of RDF triples for the closure semantics. Empty list if no captures.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ClosureBuilder, Context}
      iex> alias ElixirOntologies.Extractors.AnonymousFunction
      iex> ast = quote do: fn x -> x + 1 end  # no captures
      iex> {:ok, anon} = AnonymousFunction.extract(ast)
      iex> anon_iri = RDF.iri("https://example.org/code#MyApp/anon/0")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = ClosureBuilder.build_closure(anon, anon_iri, context)
      iex> triples
      []

      iex> alias ElixirOntologies.Builders.{ClosureBuilder, Context}
      iex> alias ElixirOntologies.Extractors.AnonymousFunction
      iex> ast = quote do: fn -> y end  # captures y
      iex> {:ok, anon} = AnonymousFunction.extract(ast)
      iex> anon_iri = RDF.iri("https://example.org/code#MyApp/anon/0")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = ClosureBuilder.build_closure(anon, anon_iri, context)
      iex> Enum.any?(triples, fn {_, pred, _} -> pred == ElixirOntologies.NS.Core.capturesVariable() end)
      true
  """
  @spec build_closure(AnonymousFunction.t(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  def build_closure(anon_info, anon_iri, _context) do
    # Analyze the anonymous function for free variables
    {:ok, analysis} = Closure.analyze_closure(anon_info)

    if analysis.has_captures do
      # Generate triples for each captured variable
      build_capture_triples(anon_iri, analysis.free_variables)
    else
      # Not a closure - no additional triples needed
      []
    end
  end

  @doc """
  Checks if an anonymous function is a closure (captures variables).

  ## Parameters

  - `anon_info` - AnonymousFunction extraction result

  ## Returns

  `true` if the function captures at least one variable, `false` otherwise.

  ## Examples

      iex> alias ElixirOntologies.Builders.ClosureBuilder
      iex> alias ElixirOntologies.Extractors.AnonymousFunction
      iex> ast = quote do: fn x -> x + 1 end
      iex> {:ok, anon} = AnonymousFunction.extract(ast)
      iex> ClosureBuilder.is_closure?(anon)
      false

      iex> alias ElixirOntologies.Builders.ClosureBuilder
      iex> alias ElixirOntologies.Extractors.AnonymousFunction
      iex> ast = quote do: fn -> y end
      iex> {:ok, anon} = AnonymousFunction.extract(ast)
      iex> ClosureBuilder.is_closure?(anon)
      true
  """
  @spec is_closure?(AnonymousFunction.t()) :: boolean()
  def is_closure?(anon_info) do
    {:ok, analysis} = Closure.analyze_closure(anon_info)
    analysis.has_captures
  end

  # ===========================================================================
  # Triple Generation
  # ===========================================================================

  # Build triples for all captured variables
  defp build_capture_triples(anon_iri, free_vars) do
    free_vars
    |> Enum.flat_map(fn free_var ->
      build_single_capture_triples(anon_iri, free_var)
    end)
  end

  # Build triples for a single captured variable
  defp build_single_capture_triples(anon_iri, free_var) do
    var_name = free_var.name
    var_iri = IRI.for_captured_variable(anon_iri, var_name)

    [
      # Link closure to captured variable
      Helpers.object_property(anon_iri, Core.capturesVariable(), var_iri),

      # Variable type triple
      Helpers.type_triple(var_iri, Core.Variable),

      # Variable name triple
      Helpers.datatype_property(var_iri, Core.name(), Atom.to_string(var_name), RDF.XSD.String)
    ]
  end
end
