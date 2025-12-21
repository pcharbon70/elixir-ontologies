defmodule ElixirOntologies.Builders.ControlFlowBuilder do
  @moduledoc """
  Builds RDF triples for control flow structures.

  This module transforms extracted control flow expressions into RDF
  triples following the elixir-core.ttl ontology. It handles:

  - **Conditionals**: if/unless/cond expressions
  - **Case expressions**: Pattern matching with clauses
  - **With expressions**: Monadic pattern matching chains

  ## Usage

      alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      alias ElixirOntologies.Extractors.Conditional.Conditional

      conditional = %Conditional{
        type: :if,
        condition: {:is_valid, [], [x]},
        branches: [%Branch{type: :then, body: :ok}, %Branch{type: :else, body: :error}],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context)

  ## IRI Patterns

  - Conditional: `{base}cond/{function_fragment}/{index}`
  - Case: `{base}case/{function_fragment}/{index}`
  - With: `{base}with/{function_fragment}/{index}`
  - Clause: `{parent_iri}/clause/{index}`

  ## Examples

      iex> alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Conditional.{Conditional, Branch}
      iex> cond = %Conditional{type: :if, condition: :x, branches: [%Branch{type: :then, body: 1}], metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ControlFlowBuilder.build_conditional(cond, context, containing_function: "MyApp/test/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#cond/MyApp/test/0/0"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.NS.Core
  alias ElixirOntologies.Extractors.Conditional.{Conditional, Branch}
  alias ElixirOntologies.Extractors.CaseWith.{CaseExpression, WithExpression}

  # ===========================================================================
  # Public API - Conditional Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for a conditional expression (if/unless/cond).

  ## Parameters

  - `conditional` - Conditional extraction result
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)

  ## Returns

  A tuple `{expr_iri, triples}` where:
  - `expr_iri` - The IRI of the conditional expression
  - `triples` - List of RDF triples

  ## Examples

      iex> alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Conditional.{Conditional, Branch}
      iex> cond = %Conditional{type: :unless, condition: :x, branches: [%Branch{type: :then, body: 1}], metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_iri, triples} = ControlFlowBuilder.build_conditional(cond, context, containing_function: "MyApp/test/0", index: 0)
      iex> Enum.any?(triples, fn {_, p, _} -> p == RDF.type() end)
      true
  """
  @spec build_conditional(Conditional.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_conditional(%Conditional{} = conditional, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)

    expr_iri = conditional_iri(context.base_iri, containing_function, index)

    triples =
      []
      |> add_conditional_type_triple(expr_iri, conditional.type)
      |> add_condition_triple(expr_iri, conditional.condition, conditional.type)
      |> add_branch_triples(expr_iri, conditional.branches, conditional.type)
      |> add_cond_clause_triples(expr_iri, conditional.clauses, conditional.type)
      |> add_location_triple(expr_iri, conditional.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for a conditional expression.

  ## Examples

      iex> ElixirOntologies.Builders.ControlFlowBuilder.conditional_iri("https://example.org/code#", "MyApp/foo/1", 0)
      ~I<https://example.org/code#cond/MyApp/foo/1/0>
  """
  @spec conditional_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
  def conditional_iri(base_iri, containing_function, index) when is_binary(base_iri) do
    RDF.iri("#{base_iri}cond/#{containing_function}/#{index}")
  end

  def conditional_iri(%RDF.IRI{value: base}, containing_function, index) do
    conditional_iri(base, containing_function, index)
  end

  # ===========================================================================
  # Public API - Case Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for a case expression.

  ## Parameters

  - `case_expr` - CaseExpression extraction result
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)

  ## Returns

  A tuple `{expr_iri, triples}`.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      iex> alias ElixirOntologies.Extractors.CaseWith.{CaseExpression, CaseClause}
      iex> case_expr = %CaseExpression{subject: :x, clauses: [%CaseClause{index: 0, pattern: :a, body: 1}], metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ControlFlowBuilder.build_case(case_expr, context, containing_function: "MyApp/run/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#case/MyApp/run/0/0"
  """
  @spec build_case(CaseExpression.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_case(%CaseExpression{} = case_expr, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)

    expr_iri = case_iri(context.base_iri, containing_function, index)

    triples =
      []
      |> add_type_triple(expr_iri, Core.CaseExpression)
      |> add_case_clause_triples(expr_iri, case_expr.clauses)
      |> add_location_triple(expr_iri, case_expr.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for a case expression.

  ## Examples

      iex> ElixirOntologies.Builders.ControlFlowBuilder.case_iri("https://example.org/code#", "MyApp/foo/1", 0)
      ~I<https://example.org/code#case/MyApp/foo/1/0>
  """
  @spec case_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
  def case_iri(base_iri, containing_function, index) when is_binary(base_iri) do
    RDF.iri("#{base_iri}case/#{containing_function}/#{index}")
  end

  def case_iri(%RDF.IRI{value: base}, containing_function, index) do
    case_iri(base, containing_function, index)
  end

  # ===========================================================================
  # Public API - With Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for a with expression.

  ## Parameters

  - `with_expr` - WithExpression extraction result
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)

  ## Returns

  A tuple `{expr_iri, triples}`.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      iex> alias ElixirOntologies.Extractors.CaseWith.{WithExpression, WithClause}
      iex> with_expr = %WithExpression{clauses: [%WithClause{index: 0, type: :match, pattern: :ok, expression: :x}], body: :ok, metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ControlFlowBuilder.build_with(with_expr, context, containing_function: "MyApp/run/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#with/MyApp/run/0/0"
  """
  @spec build_with(WithExpression.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_with(%WithExpression{} = with_expr, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)

    expr_iri = with_iri(context.base_iri, containing_function, index)

    triples =
      []
      |> add_type_triple(expr_iri, Core.WithExpression)
      |> add_with_clause_triples(expr_iri, with_expr.clauses)
      |> add_has_else_triple(expr_iri, with_expr.else_clauses)
      |> add_location_triple(expr_iri, with_expr.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for a with expression.

  ## Examples

      iex> ElixirOntologies.Builders.ControlFlowBuilder.with_iri("https://example.org/code#", "MyApp/foo/1", 0)
      ~I<https://example.org/code#with/MyApp/foo/1/0>
  """
  @spec with_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
  def with_iri(base_iri, containing_function, index) when is_binary(base_iri) do
    RDF.iri("#{base_iri}with/#{containing_function}/#{index}")
  end

  def with_iri(%RDF.IRI{value: base}, containing_function, index) do
    with_iri(base, containing_function, index)
  end

  # ===========================================================================
  # Private - Type Triples
  # ===========================================================================

  defp add_conditional_type_triple(triples, expr_iri, :if) do
    [Helpers.type_triple(expr_iri, Core.IfExpression) | triples]
  end

  defp add_conditional_type_triple(triples, expr_iri, :unless) do
    [Helpers.type_triple(expr_iri, Core.UnlessExpression) | triples]
  end

  defp add_conditional_type_triple(triples, expr_iri, :cond) do
    [Helpers.type_triple(expr_iri, Core.CondExpression) | triples]
  end

  defp add_conditional_type_triple(triples, _expr_iri, _type), do: triples

  defp add_type_triple(triples, expr_iri, type) do
    [Helpers.type_triple(expr_iri, type) | triples]
  end

  # ===========================================================================
  # Private - Condition and Branch Triples
  # ===========================================================================

  # Add condition triple for if/unless (cond has conditions per clause)
  defp add_condition_triple(triples, expr_iri, condition, type)
       when type in [:if, :unless] and not is_nil(condition) do
    # Store condition as a boolean expression indicator
    # The actual AST isn't stored directly, but we note the presence
    triple = Helpers.datatype_property(expr_iri, Core.hasCondition(), true, RDF.XSD.Boolean)
    [triple | triples]
  end

  defp add_condition_triple(triples, _expr_iri, _condition, _type), do: triples

  # Add branch triples for if/unless
  defp add_branch_triples(triples, expr_iri, branches, type) when type in [:if, :unless] do
    Enum.reduce(branches, triples, fn branch, acc ->
      add_single_branch_triple(acc, expr_iri, branch)
    end)
  end

  defp add_branch_triples(triples, _expr_iri, _branches, _type), do: triples

  defp add_single_branch_triple(triples, expr_iri, %Branch{type: :then}) do
    triple = Helpers.datatype_property(expr_iri, Core.hasThenBranch(), true, RDF.XSD.Boolean)
    [triple | triples]
  end

  defp add_single_branch_triple(triples, expr_iri, %Branch{type: :else}) do
    triple = Helpers.datatype_property(expr_iri, Core.hasElseBranch(), true, RDF.XSD.Boolean)
    [triple | triples]
  end

  defp add_single_branch_triple(triples, _expr_iri, _branch), do: triples

  # ===========================================================================
  # Private - Cond Clause Triples
  # ===========================================================================

  # For cond expressions, we track that clauses exist via hasClause boolean property
  defp add_cond_clause_triples(triples, expr_iri, clauses, :cond) when is_list(clauses) and clauses != [] do
    # Add hasClause as boolean to indicate clauses are present
    triple = Helpers.datatype_property(expr_iri, Core.hasClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end

  defp add_cond_clause_triples(triples, _expr_iri, _clauses, _type), do: triples

  # ===========================================================================
  # Private - Case Clause Triples
  # ===========================================================================

  # For case expressions, track that clauses exist and whether any have guards
  defp add_case_clause_triples(triples, expr_iri, clauses) when is_list(clauses) and clauses != [] do
    # Add hasClause to indicate clauses are present
    clause_triple = Helpers.datatype_property(expr_iri, Core.hasClause(), true, RDF.XSD.Boolean)

    # Check if any clauses have guards
    has_guards = Enum.any?(clauses, & &1.has_guard)

    if has_guards do
      guard_triple = Helpers.datatype_property(expr_iri, Core.hasGuard(), true, RDF.XSD.Boolean)
      [guard_triple, clause_triple | triples]
    else
      [clause_triple | triples]
    end
  end

  defp add_case_clause_triples(triples, _expr_iri, _clauses), do: triples

  # ===========================================================================
  # Private - With Clause Triples
  # ===========================================================================

  # For with expressions, track that clauses exist
  defp add_with_clause_triples(triples, expr_iri, clauses) when is_list(clauses) and clauses != [] do
    # Add hasClause to indicate clauses are present
    triple = Helpers.datatype_property(expr_iri, Core.hasClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end

  defp add_with_clause_triples(triples, _expr_iri, _clauses), do: triples

  # Track presence of else clauses using hasElseClause
  defp add_has_else_triple(triples, expr_iri, else_clauses) when is_list(else_clauses) and else_clauses != [] do
    triple = Helpers.datatype_property(expr_iri, Core.hasElseClause(), true, RDF.XSD.Boolean)
    [triple | triples]
  end

  defp add_has_else_triple(triples, _expr_iri, _else_clauses), do: triples

  # ===========================================================================
  # Private - Common Helpers
  # ===========================================================================

  defp add_location_triple(triples, expr_iri, %{line: line}) when is_integer(line) do
    triple = Helpers.datatype_property(expr_iri, Core.startLine(), line, RDF.XSD.PositiveInteger)
    [triple | triples]
  end

  defp add_location_triple(triples, _expr_iri, _location), do: triples
end
