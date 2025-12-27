defmodule ElixirOntologies.Builders.ExceptionBuilder do
  @moduledoc """
  Builds RDF triples for exception handling structures.

  This module transforms extracted exception handling expressions into RDF
  triples following the elixir-core.ttl ontology. It handles:

  - **Try expressions**: Exception handling with rescue/catch/after/else
  - **Raise expressions**: Raising exceptions (including reraise)
  - **Throw expressions**: Throwing values for catch clauses

  ## Usage

      alias ElixirOntologies.Builders.{ExceptionBuilder, Context}
      alias ElixirOntologies.Extractors.Exception

      try_expr = %Exception{
        body: {:risky_call, [], []},
        has_rescue: true,
        rescue_clauses: [%Exception.RescueClause{body: :error, is_catch_all: true}],
        has_after: true,
        after_body: {:cleanup, [], []}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {expr_iri, triples} = ExceptionBuilder.build_try(try_expr, context)

  ## IRI Patterns

  - Try: `{base}try/{function_fragment}/{index}`
  - Raise: `{base}raise/{function_fragment}/{index}`
  - Throw: `{base}throw/{function_fragment}/{index}`

  ## Examples

      iex> alias ElixirOntologies.Builders.{ExceptionBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Exception
      iex> try_expr = %Exception{body: :ok, has_rescue: true, rescue_clauses: [%Exception.RescueClause{body: :error}]}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ExceptionBuilder.build_try(try_expr, context, containing_function: "MyApp/test/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#try/MyApp/test/0/0"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.NS.Core
  alias ElixirOntologies.Extractors.Exception
  alias ElixirOntologies.Extractors.Exception.{RaiseExpression, ThrowExpression, ExitExpression}

  # ===========================================================================
  # Public API - Try Expression Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for a try expression.

  ## Parameters

  - `try_expr` - Exception extraction result
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)

  ## Returns

  A tuple `{expr_iri, triples}` where:
  - `expr_iri` - The IRI of the try expression
  - `triples` - List of RDF triples

  ## Examples

      iex> alias ElixirOntologies.Builders.{ExceptionBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Exception
      iex> try_expr = %Exception{body: :ok, has_rescue: true, rescue_clauses: [%Exception.RescueClause{body: :err}]}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_iri, triples} = ExceptionBuilder.build_try(try_expr, context, containing_function: "MyApp/test/0", index: 0)
      iex> Enum.any?(triples, fn {_, p, _} -> p == RDF.type() end)
      true
  """
  @spec build_try(Exception.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_try(%Exception{} = try_expr, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)

    expr_iri = try_iri(context.base_iri, containing_function, index)

    triples =
      []
      |> add_type_triple(expr_iri, Core.TryExpression)
      |> add_rescue_triple(expr_iri, try_expr.has_rescue)
      |> add_catch_triple(expr_iri, try_expr.has_catch)
      |> add_after_triple(expr_iri, try_expr.has_after)
      |> add_else_triple(expr_iri, try_expr.has_else)
      |> add_location_triple(expr_iri, try_expr.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for a try expression.

  ## Examples

      iex> ElixirOntologies.Builders.ExceptionBuilder.try_iri("https://example.org/code#", "MyApp/foo/1", 0)
      ~I<https://example.org/code#try/MyApp/foo/1/0>
  """
  @spec try_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
  def try_iri(base_iri, containing_function, index) when is_binary(base_iri) do
    RDF.iri("#{base_iri}try/#{containing_function}/#{index}")
  end

  def try_iri(%RDF.IRI{value: base}, containing_function, index) do
    try_iri(base, containing_function, index)
  end

  # ===========================================================================
  # Public API - Raise Expression Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for a raise or reraise expression.

  ## Parameters

  - `raise_expr` - RaiseExpression extraction result
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)

  ## Returns

  A tuple `{expr_iri, triples}`.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ExceptionBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Exception.RaiseExpression
      iex> raise_expr = %RaiseExpression{message: "error"}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ExceptionBuilder.build_raise(raise_expr, context, containing_function: "MyApp/run/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#raise/MyApp/run/0/0"
  """
  @spec build_raise(RaiseExpression.t(), Context.t(), keyword()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_raise(%RaiseExpression{} = raise_expr, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)

    expr_iri = raise_iri(context.base_iri, containing_function, index)

    triples =
      []
      |> add_type_triple(expr_iri, Core.RaiseExpression)
      |> add_location_triple(expr_iri, raise_expr.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for a raise expression.

  ## Examples

      iex> ElixirOntologies.Builders.ExceptionBuilder.raise_iri("https://example.org/code#", "MyApp/foo/1", 0)
      ~I<https://example.org/code#raise/MyApp/foo/1/0>
  """
  @spec raise_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
  def raise_iri(base_iri, containing_function, index) when is_binary(base_iri) do
    RDF.iri("#{base_iri}raise/#{containing_function}/#{index}")
  end

  def raise_iri(%RDF.IRI{value: base}, containing_function, index) do
    raise_iri(base, containing_function, index)
  end

  # ===========================================================================
  # Public API - Throw Expression Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for a throw expression.

  ## Parameters

  - `throw_expr` - ThrowExpression extraction result
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)

  ## Returns

  A tuple `{expr_iri, triples}`.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ExceptionBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Exception.ThrowExpression
      iex> throw_expr = %ThrowExpression{value: :done}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ExceptionBuilder.build_throw(throw_expr, context, containing_function: "MyApp/run/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#throw/MyApp/run/0/0"
  """
  @spec build_throw(ThrowExpression.t(), Context.t(), keyword()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_throw(%ThrowExpression{} = throw_expr, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)

    expr_iri = throw_iri(context.base_iri, containing_function, index)

    triples =
      []
      |> add_type_triple(expr_iri, Core.ThrowExpression)
      |> add_location_triple(expr_iri, throw_expr.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for a throw expression.

  ## Examples

      iex> ElixirOntologies.Builders.ExceptionBuilder.throw_iri("https://example.org/code#", "MyApp/foo/1", 0)
      ~I<https://example.org/code#throw/MyApp/foo/1/0>
  """
  @spec throw_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
  def throw_iri(base_iri, containing_function, index) when is_binary(base_iri) do
    RDF.iri("#{base_iri}throw/#{containing_function}/#{index}")
  end

  def throw_iri(%RDF.IRI{value: base}, containing_function, index) do
    throw_iri(base, containing_function, index)
  end

  # ===========================================================================
  # Public API - Exit Expression Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for an exit expression.

  ## Parameters

  - `exit_expr` - ExitExpression extraction result
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)

  ## Returns

  A tuple `{expr_iri, triples}`.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ExceptionBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Exception.ExitExpression
      iex> exit_expr = %ExitExpression{reason: :normal}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ExceptionBuilder.build_exit(exit_expr, context, containing_function: "MyApp/run/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#exit/MyApp/run/0/0"
  """
  @spec build_exit(ExitExpression.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_exit(%ExitExpression{} = exit_expr, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)

    expr_iri = exit_iri(context.base_iri, containing_function, index)

    triples =
      []
      |> add_type_triple(expr_iri, Core.ExitExpression)
      |> add_location_triple(expr_iri, exit_expr.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for an exit expression.

  ## Examples

      iex> ElixirOntologies.Builders.ExceptionBuilder.exit_iri("https://example.org/code#", "MyApp/foo/1", 0)
      ~I<https://example.org/code#exit/MyApp/foo/1/0>
  """
  @spec exit_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
  def exit_iri(base_iri, containing_function, index) when is_binary(base_iri) do
    RDF.iri("#{base_iri}exit/#{containing_function}/#{index}")
  end

  def exit_iri(%RDF.IRI{value: base}, containing_function, index) do
    exit_iri(base, containing_function, index)
  end

  # ===========================================================================
  # Private - Type Triple
  # ===========================================================================

  defp add_type_triple(triples, expr_iri, type) do
    [Helpers.type_triple(expr_iri, type) | triples]
  end

  # ===========================================================================
  # Private - Try Clause Triples
  # ===========================================================================

  defp add_rescue_triple(triples, expr_iri, true) do
    triple = Helpers.datatype_property(expr_iri, Core.hasRescueClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end

  defp add_rescue_triple(triples, _expr_iri, _), do: triples

  defp add_catch_triple(triples, expr_iri, true) do
    triple = Helpers.datatype_property(expr_iri, Core.hasCatchClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end

  defp add_catch_triple(triples, _expr_iri, _), do: triples

  defp add_after_triple(triples, expr_iri, true) do
    triple = Helpers.datatype_property(expr_iri, Core.hasAfterClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end

  defp add_after_triple(triples, _expr_iri, _), do: triples

  defp add_else_triple(triples, expr_iri, true) do
    triple = Helpers.datatype_property(expr_iri, Core.hasElseClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end

  defp add_else_triple(triples, _expr_iri, _), do: triples

  # ===========================================================================
  # Private - Common Helpers
  # ===========================================================================

  defp add_location_triple(triples, expr_iri, %{line: line}) when is_integer(line) do
    triple = Helpers.datatype_property(expr_iri, Core.startLine(), line, RDF.XSD.PositiveInteger)
    [triple | triples]
  end

  defp add_location_triple(triples, _expr_iri, _location), do: triples
end
