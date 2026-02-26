defmodule ElixirOntologies.Builders.ExpressionTestHelpers do
  @moduledoc """
  Shared test helpers for expression builder tests.

  This module provides common helper functions used across multiple
  expression builder test files to reduce code duplication and improve
  test maintainability.
  """

  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.NS.Core

  @doc """
  Creates a full mode context for expression testing.

  ## Examples

      iex> context = full_mode_context()
      iex> context.config.include_expressions
      true
  """
  def full_mode_context(opts \\ []) do
    Keyword.merge(
      [
        base_iri: "https://example.org/code#",
        config: %{include_expressions: true},
        file_path: "lib/my_app/users.ex"
      ],
      opts
    )
    |> Context.new()
    |> Context.with_expression_counter()
  end

  @doc """
  Checks if the given triples contain a specific RDF type.

  ## Parameters

  - triples: List of RDF triples {subject, predicate, object}
  - expected_type: The RDF type IRI to look for

  ## Examples

      iex> triples = [{iri, RDF.type(), Core.IntegerLiteral}]
      iex> has_type?(triples, Core.IntegerLiteral)
      true
  """
  def has_type?(triples, expected_type) do
    Enum.any?(triples, fn {_s, p, o} -> p == RDF.type() and o == expected_type end)
  end

  @doc """
  Checks if the given triples contain an operator with the specified symbol.

  ## Parameters

  - triples: List of RDF triples
  - symbol: The operator symbol to look for (e.g., "+", "==", "and")

  ## Examples

      iex> triples = [{iri, Core.operatorSymbol(), ~L"+"}]
      iex> has_operator_symbol?(triples, "+")
      true
  """
  def has_operator_symbol?(triples, symbol) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == Core.operatorSymbol() and RDF.Literal.value(o) == symbol
    end)
  end

  @doc """
  Checks if a specific IRI has a given operator symbol.

  ## Parameters

  - triples: List of RDF triples
  - iri: The subject IRI to check
  - symbol: The operator symbol to look for

  ## Examples

      iex> triples = [{expr_iri, Core.operatorSymbol(), ~L"|>"}]
      iex> has_operator_symbol_for_iri?(triples, expr_iri, "|>")
      true
  """
  def has_operator_symbol_for_iri?(triples, iri, symbol) do
    Enum.any?(triples, fn {s, p, o} ->
      s == iri and p == Core.operatorSymbol() and RDF.Literal.value(o) == symbol
    end)
  end

  @doc """
  Checks if the given triples contain a specific literal value.

  ## Parameters

  - triples: List of RDF triples
  - subject: The subject IRI to check
  - predicate: The predicate IRI to check
  - expected_value: The expected literal value

  ## Examples

      iex> triples = [{iri, Core.name(), ~L"x"}]
      iex> has_literal_value?(triples, iri, Core.name(), "x")
      true
  """
  def has_literal_value?(triples, subject, predicate, expected_value) do
    Enum.any?(triples, fn {s, p, o} ->
      s == subject and p == predicate and RDF.Literal.value(o) == expected_value
    end)
  end

  @doc """
  Checks if the given triples contain a specific binary literal value.

  For Base64Binary literals, RDF.Literal.value/1 returns nil, so we need
  to check RDF.Literal.lexical/1 instead.

  ## Parameters

  - triples: List of RDF triples
  - subject: The subject IRI to check
  - predicate: The predicate IRI to check
  - expected_value: The expected binary literal value (as string)

  ## Examples

      iex> triples = [{iri, Core.binaryValue(), ~L"<<1, 2, 3>>"}]
      iex> has_binary_literal_value?(triples, iri, Core.binaryValue(), "<<1, 2, 3>>")
      true
  """
  def has_binary_literal_value?(triples, subject, predicate, expected_value) do
    Enum.any?(triples, fn {s, p, o} ->
      s == subject and p == predicate and RDF.Literal.lexical(o) == expected_value
    end)
  end

  @doc """
  Checks if an expression has a hasOperand property (for unary operators).

  ## Parameters

  - triples: List of RDF triples
  - expr_iri: The expression IRI to check

  ## Examples

      iex> triples = [{expr_iri, Core.hasOperand(), operand_iri}]
      iex> has_operand?(triples, expr_iri)
      true
  """
  def has_operand?(triples, expr_iri) do
    Enum.any?(triples, fn {s, p, _o} ->
      s == expr_iri and p == Core.hasOperand()
    end)
  end

  @doc """
  Checks if an expression has a child expression of a specific type.

  This helper finds child expressions via hasOperand, hasLeftOperand, or
  hasRightOperand properties and checks if any child has the expected type.

  ## Parameters

  - triples: List of RDF triples
  - expr_iri: The parent expression IRI
  - child_type: The expected child type IRI

  ## Examples

      iex> triples = [
      ...>   {expr_iri, Core.hasOperand(), child_iri},
      ...>   {child_iri, RDF.type(), Core.IntegerLiteral}
      ...> ]
      iex> has_child_with_type?(triples, expr_iri, Core.IntegerLiteral)
      true
  """
  def has_child_with_type?(triples, expr_iri, child_type) do
    # First find the hasOperand or hasLeftOperand/hasRightOperand property
    child_iris =
      triples
      |> Enum.filter(fn {s, _p, _o} -> s == expr_iri end)
      |> Enum.filter(fn {_s, p, _o} ->
        p == Core.hasOperand() or p == Core.hasLeftOperand() or p == Core.hasRightOperand()
      end)
      |> Enum.map(fn {_s, _p, o} -> o end)

    # Check if any child IRI has the expected type
    Enum.any?(child_iris, fn child_iri ->
      Enum.any?(triples, fn {s, p, o} ->
        s == child_iri and p == RDF.type() and o == child_type
      end)
    end)
  end

  @doc """
  Checks if an expression has a specific left operand.

  ## Parameters

  - triples: List of RDF triples
  - expr_iri: The parent expression IRI
  - expected_iri: The expected left operand IRI

  ## Examples

      iex> triples = [{expr_iri, Core.hasLeftOperand(), left_iri}]
      iex> has_left_operand?(triples, expr_iri, left_iri)
      true
  """
  def has_left_operand?(triples, expr_iri, expected_iri) do
    Enum.any?(triples, fn {s, p, o} ->
      s == expr_iri and p == Core.hasLeftOperand() and o == expected_iri
    end)
  end

  @doc """
  Checks if an expression has a specific right operand.

  ## Parameters

  - triples: List of RDF triples
  - expr_iri: The parent expression IRI
  - expected_iri: The expected right operand IRI

  ## Examples

      iex> triples = [{expr_iri, Core.hasRightOperand(), right_iri}]
      iex> has_right_operand?(triples, expr_iri, right_iri)
      true
  """
  def has_right_operand?(triples, expr_iri, expected_iri) do
    Enum.any?(triples, fn {s, p, o} ->
      s == expr_iri and p == Core.hasRightOperand() and o == expected_iri
    end)
  end
end
