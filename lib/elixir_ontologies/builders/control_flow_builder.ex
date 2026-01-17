defmodule ElixirOntologies.Builders.ControlFlowBuilder do
  @moduledoc """
  Builds RDF triples for control flow structures.

  This module transforms extracted control flow expressions into RDF
  triples following the elixir-core.ttl ontology. It handles:

  - **Conditionals**: if/unless/cond expressions
  - **Case expressions**: Pattern matching with clauses
  - **With expressions**: Monadic pattern matching chains
  - **Receive expressions**: Process message handling with optional timeout
  - **Comprehensions**: For comprehensions with generators and filters

  ## Expression Building

  By default, this builder creates lightweight RDF triples with boolean flags
  for control flow structures (e.g., `hasCondition: true`). For full expression
  extraction including AST details, pass the `:expression_builder` option with
  `ElixirOntologies.Builders.ExpressionBuilder`.

  Full expression extraction requires:
  - `expression_builder: ExpressionBuilder` option passed to build functions
  - `include_expressions: true` in the context configuration
  - The file being processed is project code (not a dependency)

  When these conditions are met, the builder creates full expression triples for:
  - Conditional conditions (e.g., `x > 5`)
  - Branch bodies (e.g., then/else expressions)
  - Cond clause conditions and bodies
  - Guard expressions in function clauses

  ## Usage

      alias ElixirOntologies.Builders.{ControlFlowBuilder, Context, ExpressionBuilder}
      alias ElixirOntologies.Extractors.Conditional.Conditional

      conditional = %Conditional{
        type: :if,
        condition: {:is_valid, [], [x]},
        branches: [%Branch{type: :then, body: :ok}, %Branch{type: :else, body: :error}],
        metadata: %{}
      }

      # Light mode (default) - boolean flags only
      context = Context.new(base_iri: "https://example.org/code#")
      {expr_iri, triples} = ControlFlowBuilder.build_conditional(conditional, context)

      # Full mode - complete expression triples
      context = Context.new(
        base_iri: "https://example.org/code#",
        config: %{include_expressions: true},
        file_path: "lib/my_app.ex"
      )
      {expr_iri, triples} = ControlFlowBuilder.build_conditional(
        conditional,
        context,
        expression_builder: ExpressionBuilder
      )

  ## IRI Patterns

  - Conditional: `{base}cond/{function_fragment}/{index}`
  - Case: `{base}case/{function_fragment}/{index}`
  - With: `{base}with/{function_fragment}/{index}`
  - Receive: `{base}receive/{function_fragment}/{index}`
  - Comprehension: `{base}for/{function_fragment}/{index}`

  ## Examples

      iex> alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Conditional.{Conditional, Branch}
      iex> cond = %Conditional{type: :if, condition: :x, branches: [%Branch{type: :then, body: 1}], metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ControlFlowBuilder.build_conditional(cond, context, containing_function: "MyApp/test/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#cond/MyApp/test/0/0"
  """

  alias ElixirOntologies.Builders.{Context, ExpressionBuilder, Helpers}
  alias ElixirOntologies.NS.{Core, Structure}
  alias ElixirOntologies.Extractors.Conditional.{Conditional, Branch}
  alias ElixirOntologies.Extractors.CaseWith.{CaseExpression, WithExpression, ReceiveExpression}
  alias ElixirOntologies.Extractors.{Comprehension, Exception}
  alias ElixirOntologies.Extractors.Exception.{RaiseExpression, ThrowExpression}

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
    - `:expression_builder` - Optional module for building expression triples
      (e.g., `ElixirOntologies.Builders.ExpressionBuilder`)

  ## Returns

  A tuple `{expr_iri, triples}` where:
  - `expr_iri` - The IRI of the conditional expression
  - `triples` - List of RDF triples

  ## Expression Building

  When `:expression_builder` is provided and `Context.full_mode_for_file?/2`
  returns `true`, this function builds full expression triples for:
  - Condition expressions (linked via `core:hasCondition`)
  - Branch body expressions (linked via `core:hasThenBranch`/`core:hasElseBranch`)
  - Cond clause conditions and bodies

  Otherwise, creates lightweight boolean flag triples only.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Conditional.{Conditional, Branch}
      iex> cond = %Conditional{type: :unless, condition: :x, branches: [%Branch{type: :then, body: 1}], metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {_iri, triples} = ControlFlowBuilder.build_conditional(cond, context, containing_function: "MyApp/test/0", index: 0)
      iex> Enum.any?(triples, fn {_, p, _} -> p == RDF.type() end)
      true
  """
  @spec build_conditional(Conditional.t(), Context.t(), keyword()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_conditional(%Conditional{} = conditional, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)
    expression_builder = Keyword.get(opts, :expression_builder)

    expr_iri = conditional_iri(context.base_iri, containing_function, index)

    # Check if we should build full expressions
    build_expressions? =
      expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

    triples =
      []
      |> add_conditional_type_triple(expr_iri, conditional.type)
      |> add_condition_triple(
        expr_iri,
        conditional.condition,
        conditional.type,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_branch_triples(
        expr_iri,
        conditional.branches,
        conditional.type,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_cond_clause_triples(
        expr_iri,
        conditional.clauses,
        conditional.type,
        expression_builder,
        build_expressions?,
        context
      )
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
    expression_builder = Keyword.get(opts, :expression_builder)

    expr_iri = case_iri(context.base_iri, containing_function, index)

    # Check if we should build full expressions
    build_expressions? =
      expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

    triples =
      []
      |> add_type_triple(expr_iri, Core.CaseExpression)
      |> add_case_subject_triple(
        expr_iri,
        case_expr.subject,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_case_clause_triples(
        expr_iri,
        case_expr.clauses,
        expression_builder,
        build_expressions?,
        context
      )
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
    expression_builder = Keyword.get(opts, :expression_builder)

    expr_iri = with_iri(context.base_iri, containing_function, index)

    # Check if we should build full expressions
    build_expressions? =
      expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

    triples =
      []
      |> add_type_triple(expr_iri, Core.WithExpression)
      |> add_with_clause_triples(
        expr_iri,
        with_expr.clauses,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_with_body_triple(
        expr_iri,
        with_expr.body,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_with_else_triples(
        expr_iri,
        with_expr.else_clauses,
        expression_builder,
        build_expressions?,
        context
      )
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
  # Public API - Receive Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for a receive expression.

  ## Parameters

  - `receive_expr` - ReceiveExpression extraction result
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)

  ## Returns

  A tuple `{expr_iri, triples}`.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      iex> alias ElixirOntologies.Extractors.CaseWith.ReceiveExpression
      iex> receive_expr = %ReceiveExpression{clauses: [], has_after: false, metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ControlFlowBuilder.build_receive(receive_expr, context, containing_function: "MyApp/loop/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#receive/MyApp/loop/0/0"
  """
  @spec build_receive(ReceiveExpression.t(), Context.t(), keyword()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_receive(%ReceiveExpression{} = receive_expr, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)
    expression_builder = Keyword.get(opts, :expression_builder)

    expr_iri = receive_iri(context.base_iri, containing_function, index)

    # Check if we should build full expressions
    build_expressions? =
      expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

    triples =
      []
      |> add_type_triple(expr_iri, Core.ReceiveExpression)
      |> add_receive_clause_triples(
        expr_iri,
        receive_expr.clauses,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_receive_after_triples(
        expr_iri,
        receive_expr.after_clause,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_location_triple(expr_iri, receive_expr.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for a receive expression.

  ## Examples

      iex> ElixirOntologies.Builders.ControlFlowBuilder.receive_iri("https://example.org/code#", "MyApp/foo/1", 0)
      ~I<https://example.org/code#receive/MyApp/foo/1/0>
  """
  @spec receive_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
  def receive_iri(base_iri, containing_function, index) when is_binary(base_iri) do
    RDF.iri("#{base_iri}receive/#{containing_function}/#{index}")
  end

  def receive_iri(%RDF.IRI{value: base}, containing_function, index) do
    receive_iri(base, containing_function, index)
  end

  # ===========================================================================
  # Public API - Try Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for a try expression.

  ## Parameters

  - `try_expr` - Exception extraction result (try expression)
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)
    - `:expression_builder` - Expression builder for full mode

  ## Returns

  A tuple `{expr_iri, triples}`.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Exception
      iex> try_expr = %Exception{body: :ok, rescue_clauses: [], has_rescue: false, metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ControlFlowBuilder.build_try(try_expr, context, containing_function: "MyApp/risky/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#try/MyApp/risky/0/0"
  """
  @spec build_try(Exception.t(), Context.t(), keyword()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_try(%Exception{} = try_expr, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)
    expression_builder = Keyword.get(opts, :expression_builder)

    expr_iri = try_iri(context.base_iri, containing_function, index)

    # Check if we should build full expressions
    build_expressions? =
      expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

    triples =
      []
      |> add_type_triple(expr_iri, Core.TryExpression)
      |> add_try_body_triple(
        expr_iri,
        try_expr.body,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_rescue_clause_triples(
        expr_iri,
        try_expr.rescue_clauses,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_catch_clause_triples(
        expr_iri,
        try_expr.catch_clauses,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_else_clause_triples(
        expr_iri,
        try_expr.else_clauses,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_try_after_triple(
        expr_iri,
        try_expr.after_body,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_location_triple(expr_iri, try_expr.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for a try expression.

  ## Examples

      iex> ElixirOntologies.Builders.ControlFlowBuilder.try_iri("https://example.org/code#", "MyApp/foo/1", 0)
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
  # Public API - Raise Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for a raise expression.

  ## Parameters

  - `raise_expr` - RaiseExpression extraction result
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)
    - `:expression_builder` - Expression builder for full mode

  ## Returns

  A tuple `{expr_iri, triples}`.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Exception.RaiseExpression
      iex> raise_expr = %RaiseExpression{message: "error", exception: nil, is_reraise: false, metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ControlFlowBuilder.build_raise(raise_expr, context, containing_function: "MyApp/raise/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#raise/MyApp/raise/0/0"
  """
  @spec build_raise(RaiseExpression.t(), Context.t(), keyword()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_raise(%RaiseExpression{} = raise_expr, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)
    expression_builder = Keyword.get(opts, :expression_builder)

    expr_iri = raise_iri(context.base_iri, containing_function, index)

    # Check if we should build full expressions
    build_expressions? =
      expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

    triples =
      []
      |> add_type_triple(expr_iri, Core.RaiseExpression)
      |> add_raise_argument_triple(
        expr_iri,
        raise_expr,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_location_triple(expr_iri, raise_expr.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for a raise expression.

  ## Examples

      iex> ElixirOntologies.Builders.ControlFlowBuilder.raise_iri("https://example.org/code#", "MyApp/foo/1", 0)
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
  # Public API - Throw Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for a throw expression.

  ## Parameters

  - `throw_expr` - ThrowExpression extraction result
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)
    - `:expression_builder` - Expression builder for full mode

  ## Returns

  A tuple `{expr_iri, triples}`.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Exception.ThrowExpression
      iex> throw_expr = %ThrowExpression{value: :error, metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ControlFlowBuilder.build_throw(throw_expr, context, containing_function: "MyApp/throw/0", index: 0)
      iex> to_string(iri)
      "https://example.org/code#throw/MyApp/throw/0/0"
  """
  @spec build_throw(ThrowExpression.t(), Context.t(), keyword()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_throw(%ThrowExpression{} = throw_expr, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)
    expression_builder = Keyword.get(opts, :expression_builder)

    expr_iri = throw_iri(context.base_iri, containing_function, index)

    # Check if we should build full expressions
    build_expressions? =
      expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

    triples =
      []
      |> add_type_triple(expr_iri, Core.ThrowExpression)
      |> add_throw_value_triple(
        expr_iri,
        throw_expr.value,
        expression_builder,
        build_expressions?,
        context
      )
      |> add_location_triple(expr_iri, throw_expr.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for a throw expression.

  ## Examples

      iex> ElixirOntologies.Builders.ControlFlowBuilder.throw_iri("https://example.org/code#", "MyApp/foo/1", 0)
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
  # Public API - Comprehension Builder
  # ===========================================================================

  @doc """
  Builds RDF triples for a for comprehension.

  ## Parameters

  - `comprehension` - Comprehension extraction result
  - `context` - Builder context with base IRI
  - `opts` - Options:
    - `:containing_function` - IRI fragment of containing function
    - `:index` - Expression index within the function (default: 0)
    - `:expression_builder` - Optional module for building expression triples
      (e.g., `ElixirOntologies.Builders.ExpressionBuilder`)

  ## Returns

  A tuple `{expr_iri, triples}`.

  ## Expression Building

  When `:expression_builder` is provided and `Context.full_mode_for_file?/2`
  returns `true`, this function builds full expression triples for:
  - Generator enumerables (linked via `core:hasGenerator`)
  - Filter expressions (linked via `core:hasFilter`)
  - Body expression
  - Option expressions (`into:`, `reduce:`)

  Otherwise, creates lightweight boolean flag triples only.

  ## Examples

      iex> alias ElixirOntologies.Builders.{ControlFlowBuilder, Context}
      iex> alias ElixirOntologies.Extractors.Comprehension
      iex> comp = %Comprehension{type: :for, generators: [], filters: [], options: %{}, metadata: %{}}
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iri, _triples} = ControlFlowBuilder.build_comprehension(comp, context, containing_function: "MyApp/map/1", index: 0)
      iex> to_string(iri)
      "https://example.org/code#for/MyApp/map/1/0"
  """
  @spec build_comprehension(Comprehension.t(), Context.t(), keyword()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_comprehension(%Comprehension{} = comprehension, %Context{} = context, opts \\ []) do
    containing_function = Keyword.get(opts, :containing_function, "unknown/0")
    index = Keyword.get(opts, :index, 0)
    expression_builder = Keyword.get(opts, :expression_builder)

    expr_iri = comprehension_iri(context.base_iri, containing_function, index)

    # Check if we should build full expressions
    build_expressions? =
      expression_builder != nil and Context.full_mode_for_file?(context, context.file_path)

    triples =
      []
      |> add_type_triple(expr_iri, Core.ForComprehension)
      |> add_generator_triples(
        expr_iri,
        comprehension.generators,
        expression_builder,
        build_expressions?,
        context,
        containing_function,
        index
      )
      |> add_filter_triples(
        expr_iri,
        comprehension.filters,
        expression_builder,
        build_expressions?,
        context,
        containing_function,
        index
      )
      |> add_comprehension_body_triple(
        expr_iri,
        comprehension.body,
        expression_builder,
        build_expressions?,
        context,
        containing_function,
        index
      )
      |> add_comprehension_options_triples(
        expr_iri,
        comprehension.options,
        expression_builder,
        build_expressions?,
        context,
        containing_function,
        index
      )
      |> add_location_triple(expr_iri, comprehension.location)

    {expr_iri, triples}
  end

  @doc """
  Generates an IRI for a for comprehension.

  ## Examples

      iex> ElixirOntologies.Builders.ControlFlowBuilder.comprehension_iri("https://example.org/code#", "MyApp/foo/1", 0)
      ~I<https://example.org/code#for/MyApp/foo/1/0>
  """
  @spec comprehension_iri(String.t() | RDF.IRI.t(), String.t(), non_neg_integer()) :: RDF.IRI.t()
  def comprehension_iri(base_iri, containing_function, index) when is_binary(base_iri) do
    RDF.iri("#{base_iri}for/#{containing_function}/#{index}")
  end

  def comprehension_iri(%RDF.IRI{value: base}, containing_function, index) do
    comprehension_iri(base, containing_function, index)
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
  # When build_expressions? is true, builds full expression triples
  # Otherwise, stores a boolean flag indicating condition presence
  defp add_condition_triple(
         triples,
         expr_iri,
         condition,
         type,
         expression_builder,
         build_expressions?,
         context
       )
       when type in [:if, :unless] and not is_nil(condition) do
    if build_expressions? do
      # Build full expression triples for the condition
      case expression_builder.build(condition, context, suffix: "condition") do
        {:ok, {condition_iri, condition_triples}} ->
          # Link to the condition expression
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), condition_iri)
          condition_triples ++ [link_triple | triples]

        {:ok, {condition_iri, condition_triples, _updated_context}} ->
          # Link to the condition expression (context-based counter version)
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), condition_iri)
          condition_triples ++ [link_triple | triples]

        :skip ->
          # ExpressionBuilder returned skip (e.g., nil condition), fall back to boolean
          triple = Helpers.datatype_property(expr_iri, Core.hasCondition(), true, RDF.XSD.Boolean)
          [triple | triples]
      end
    else
      # Light mode: store boolean flag only
      triple = Helpers.datatype_property(expr_iri, Core.hasCondition(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_condition_triple(
         triples,
         _expr_iri,
         _condition,
         _type,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # Add branch triples for if/unless
  defp add_branch_triples(
         triples,
         expr_iri,
         branches,
         type,
         expression_builder,
         build_expressions?,
         context
       )
       when type in [:if, :unless] do
    Enum.reduce(branches, triples, fn branch, acc ->
      add_single_branch_triple(
        acc,
        expr_iri,
        branch,
        expression_builder,
        build_expressions?,
        context
      )
    end)
  end

  defp add_branch_triples(
         triples,
         _expr_iri,
         _branches,
         _type,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # Add triples for a single branch (then or else)
  defp add_single_branch_triple(
         triples,
         expr_iri,
         %Branch{type: :then, body: body},
         expression_builder,
         build_expressions?,
         context
       ) do
    if build_expressions? and body != nil do
      case expression_builder.build(body, context, suffix: "then") do
        {:ok, {body_iri, body_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
          body_triples ++ [link_triple | triples]

        {:ok, {body_iri, body_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
          body_triples ++ [link_triple | triples]

        :skip ->
          triple =
            Helpers.datatype_property(expr_iri, Core.hasThenBranch(), true, RDF.XSD.Boolean)

          [triple | triples]
      end
    else
      triple = Helpers.datatype_property(expr_iri, Core.hasThenBranch(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_single_branch_triple(
         triples,
         expr_iri,
         %Branch{type: :else, body: body},
         expression_builder,
         build_expressions?,
         context
       ) do
    if build_expressions? and body != nil do
      case expression_builder.build(body, context, suffix: "else") do
        {:ok, {body_iri, body_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasElseBranch(), body_iri)
          body_triples ++ [link_triple | triples]

        {:ok, {body_iri, body_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasElseBranch(), body_iri)
          body_triples ++ [link_triple | triples]

        :skip ->
          triple =
            Helpers.datatype_property(expr_iri, Core.hasElseBranch(), true, RDF.XSD.Boolean)

          [triple | triples]
      end
    else
      triple = Helpers.datatype_property(expr_iri, Core.hasElseBranch(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_single_branch_triple(
         triples,
         _expr_iri,
         _branch,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # ===========================================================================
  # Private - Cond Clause Triples
  # ===========================================================================

  # For cond expressions, build expression triples for each clause
  defp add_cond_clause_triples(
         triples,
         expr_iri,
         clauses,
         :cond,
         expression_builder,
         build_expressions?,
         context
       )
       when is_list(clauses) and clauses != [] do
    if build_expressions? do
      # Build full expression triples for each clause
      clauses
      |> Enum.reduce(triples, fn clause, acc ->
        add_cond_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
      end)
    else
      # Light mode: store boolean flag only
      triple = Helpers.datatype_property(expr_iri, Core.hasClause(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_cond_clause_triples(
         triples,
         _expr_iri,
         _clauses,
         _type,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # Build expression triples for a single cond clause
  defp add_cond_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
    # Build condition expression
    cond_triples =
      case expression_builder.build(clause.condition, context,
             suffix: "cond_#{clause.index}_condition"
           ) do
        {:ok, {condition_iri, condition_expr_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), condition_iri)
          condition_expr_triples ++ [link_triple]

        {:ok, {condition_iri, condition_expr_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), condition_iri)
          condition_expr_triples ++ [link_triple]

        :skip ->
          []
      end

    # Build body expression and create link triple
    body_triples_with_link =
      case expression_builder.build(clause.body, context, suffix: "cond_#{clause.index}_body") do
        {:ok, {body_iri, body_expr_triples}} ->
          # Create hasThenBranch link from cond expression to body
          link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
          body_expr_triples ++ [link_triple]

        {:ok, {body_iri, body_expr_triples, _updated_context}} ->
          # Create hasThenBranch link from cond expression to body
          link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
          body_expr_triples ++ [link_triple]

        :skip ->
          []
      end

    cond_triples ++ body_triples_with_link ++ triples
  end

  # ===========================================================================
  # Private - Case Subject Expression
  # ===========================================================================

  # Build expression triples for the case subject expression
  defp add_case_subject_triple(
         triples,
         expr_iri,
         subject,
         expression_builder,
         build_expressions?,
         context
       ) do
    if build_expressions? and not is_nil(subject) do
      case expression_builder.build(subject, context, suffix: "subject") do
        {:ok, {subject_iri, subject_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), subject_iri)
          subject_triples ++ [link_triple | triples]

        {:ok, {subject_iri, subject_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), subject_iri)
          subject_triples ++ [link_triple | triples]

        :skip ->
          triples
      end
    else
      triples
    end
  end

  # ===========================================================================
  # Private - Case Clause Triples
  # ===========================================================================

  # For case expressions, build clause patterns, guards, and bodies when in full mode
  defp add_case_clause_triples(
         triples,
         expr_iri,
         clauses,
         expression_builder,
         build_expressions?,
         context
       )
       when is_list(clauses) and clauses != [] do
    if build_expressions? do
      # Build full expression triples for each clause
      clauses
      |> Enum.reduce(triples, fn clause, acc ->
        add_case_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
      end)
    else
      # Light mode: store boolean flags only
      clause_triple = Helpers.datatype_property(expr_iri, Core.hasClause(), true, RDF.XSD.Boolean)

      has_guards = Enum.any?(clauses, & &1.has_guard)

      if has_guards do
        guard_triple = Helpers.datatype_property(expr_iri, Core.hasGuard(), true, RDF.XSD.Boolean)
        [guard_triple, clause_triple | triples]
      else
        [clause_triple | triples]
      end
    end
  end

  defp add_case_clause_triples(
         triples,
         _expr_iri,
         _clauses,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # Build expression triples for a single case clause (pattern, guard, body)
  defp add_case_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
    # 1. Build pattern triples - create a pattern IRI and link it
    pattern_iri = RDF.iri("#{expr_iri}/pattern/#{clause.index}")
    pattern_triples = ExpressionBuilder.build_pattern(clause.pattern, pattern_iri, context)
    pattern_link_triple = Helpers.object_property(expr_iri, Core.hasPattern(), pattern_iri)

    # 2. Build guard expression if present
    guard_triples =
      if clause.guard != nil do
        case expression_builder.build(clause.guard, context, suffix: "case_#{clause.index}_guard") do
          {:ok, {guard_iri, guard_expr_triples}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasGuard(), guard_iri)
            guard_expr_triples ++ [link_triple]

          {:ok, {guard_iri, guard_expr_triples, _updated_context}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasGuard(), guard_iri)
            guard_expr_triples ++ [link_triple]

          :skip ->
            []
        end
      else
        []
      end

    # 3. Build body expression
    body_triples_with_link =
      case expression_builder.build(clause.body, context, suffix: "case_#{clause.index}_body") do
        {:ok, {body_iri, body_expr_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
          body_expr_triples ++ [link_triple]

        {:ok, {body_iri, body_expr_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
          body_expr_triples ++ [link_triple]

        :skip ->
          []
      end

    pattern_triples ++ [pattern_link_triple] ++ guard_triples ++ body_triples_with_link ++ triples
  end

  # ===========================================================================
  # Private - With Clause Triples
  # ===========================================================================

  # For with expressions, build full clause pattern/expression triples in full mode
  defp add_with_clause_triples(
         triples,
         expr_iri,
         clauses,
         expression_builder,
         build_expressions?,
         context
       )
       when is_list(clauses) and clauses != [] do
    if build_expressions? do
      # Build full expression triples for each clause
      clauses
      |> Enum.reduce(triples, fn clause, acc ->
        add_with_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
      end)
    else
      # Light mode: store boolean flag only
      triple = Helpers.datatype_property(expr_iri, Core.hasClause(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_with_clause_triples(
         triples,
         _expr_iri,
         _clauses,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # Build pattern and expression triples for a single with clause
  defp add_with_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
    # 1. Build pattern triples
    pattern_iri = RDF.iri("#{expr_iri}/pattern/#{clause.index}")
    pattern_triples = ExpressionBuilder.build_pattern(clause.pattern, pattern_iri, context)
    pattern_link_triple = Helpers.object_property(expr_iri, Core.hasPattern(), pattern_iri)

    # 2. Build expression being matched
    # Use hasCondition to link the expression being matched to the with expression
    # (similar to how case expressions link the subject)
    expression_triples_with_link =
      case expression_builder.build(clause.expression, context,
             suffix: "with_#{clause.index}_expression"
           ) do
        {:ok, {expr_ast_iri, expr_ast_triples}} ->
          # Create hasCondition link from with expression to the expression being matched
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), expr_ast_iri)
          expr_ast_triples ++ [link_triple]

        {:ok, {expr_ast_iri, expr_ast_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), expr_ast_iri)
          expr_ast_triples ++ [link_triple]

        :skip ->
          []
      end

    pattern_triples ++ [pattern_link_triple] ++ expression_triples_with_link ++ triples
  end

  # Extract with body expression in full mode
  defp add_with_body_triple(
         triples,
         expr_iri,
         body,
         expression_builder,
         build_expressions?,
         context
       ) do
    if build_expressions? and not is_nil(body) do
      case expression_builder.build(body, context, suffix: "body") do
        {:ok, {body_iri, body_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
          body_triples ++ [link_triple | triples]

        {:ok, {body_iri, body_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
          body_triples ++ [link_triple | triples]

        :skip ->
          triples
      end
    else
      triples
    end
  end

  # Build else clause triples in full mode
  defp add_with_else_triples(
         triples,
         expr_iri,
         else_clauses,
         expression_builder,
         build_expressions?,
         context
       )
       when is_list(else_clauses) and else_clauses != [] do
    if build_expressions? do
      # Build expression triples for else clauses
      # For with, else clauses are CaseClause structs (same as case expression)
      else_clauses
      |> Enum.reduce(triples, fn clause, acc ->
        add_else_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
      end)
    else
      # Light mode: store boolean flag only
      triple = Helpers.datatype_property(expr_iri, Core.hasElseClause(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_with_else_triples(
         triples,
         _expr_iri,
         _else_clauses,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # Build expression triples for an else clause (similar to case clauses)
  defp add_else_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
    # Build pattern
    pattern_iri = RDF.iri("#{expr_iri}/else/#{clause.index}/pattern")
    pattern_triples = ExpressionBuilder.build_pattern(clause.pattern, pattern_iri, context)
    pattern_link_triple = Helpers.object_property(expr_iri, Core.hasPattern(), pattern_iri)

    # Build guard if present
    guard_triples =
      if clause.guard != nil do
        case expression_builder.build(clause.guard, context, suffix: "else_#{clause.index}_guard") do
          {:ok, {guard_iri, guard_expr_triples}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasGuard(), guard_iri)
            guard_expr_triples ++ [link_triple]

          {:ok, {guard_iri, guard_expr_triples, _updated_context}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasGuard(), guard_iri)
            guard_expr_triples ++ [link_triple]

          :skip ->
            []
        end
      else
        []
      end

    # Build body
    body_triples_with_link =
      case expression_builder.build(clause.body, context, suffix: "else_#{clause.index}_body") do
        {:ok, {body_iri, body_expr_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
          body_expr_triples ++ [link_triple]

        {:ok, {body_iri, body_expr_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
          body_expr_triples ++ [link_triple]

        :skip ->
          []
      end

    pattern_triples ++ [pattern_link_triple] ++ guard_triples ++ body_triples_with_link ++ triples
  end

  # ===========================================================================
  # Private - Receive Expression Helpers
  # ===========================================================================

  # For receive expressions, build full clause pattern/guard/body triples in full mode
  defp add_receive_clause_triples(
         triples,
         expr_iri,
         clauses,
         expression_builder,
         build_expressions?,
         context
       )
       when is_list(clauses) and clauses != [] do
    if build_expressions? do
      # Build full expression triples for each clause
      clauses
      |> Enum.reduce(triples, fn clause, acc ->
        add_receive_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
      end)
    else
      # Light mode: store boolean flag only
      triple = Helpers.datatype_property(expr_iri, Core.hasClause(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_receive_clause_triples(
         triples,
         _expr_iri,
         _clauses,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # Build pattern, guard, and body triples for a single receive clause
  defp add_receive_clause_expression_triples(
         triples,
         expr_iri,
         clause,
         expression_builder,
         context
       ) do
    # 1. Build pattern triples
    pattern_iri = RDF.iri("#{expr_iri}/pattern/#{clause.index}")
    pattern_triples = ExpressionBuilder.build_pattern(clause.pattern, pattern_iri, context)
    pattern_link_triple = Helpers.object_property(expr_iri, Core.hasPattern(), pattern_iri)

    # 2. Build guard expression if present
    guard_triples =
      if clause.guard != nil do
        case expression_builder.build(clause.guard, context,
               suffix: "receive_#{clause.index}_guard"
             ) do
          {:ok, {guard_iri, guard_expr_triples}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasGuard(), guard_iri)
            guard_expr_triples ++ [link_triple]

          {:ok, {guard_iri, guard_expr_triples, _updated_context}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasGuard(), guard_iri)
            guard_expr_triples ++ [link_triple]

          :skip ->
            []
        end
      else
        []
      end

    # 3. Build body expression
    body_triples_with_link =
      case expression_builder.build(clause.body, context, suffix: "receive_#{clause.index}_body") do
        {:ok, {body_iri, body_expr_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
          body_expr_triples ++ [link_triple]

        {:ok, {body_iri, body_expr_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
          body_expr_triples ++ [link_triple]

        :skip ->
          []
      end

    pattern_triples ++ [pattern_link_triple] ++ guard_triples ++ body_triples_with_link ++ triples
  end

  # Build after clause triples (timeout and body) in full mode
  defp add_receive_after_triples(
         triples,
         expr_iri,
         after_clause,
         expression_builder,
         build_expressions?,
         context
       )
       when not is_nil(after_clause) do
    if build_expressions? do
      # Build full expression triples for after clause
      # Extract timeout expression
      timeout_triples =
        case expression_builder.build(after_clause.timeout, context, suffix: "timeout") do
          {:ok, {timeout_iri, timeout_expr_triples}} ->
            # Note: hasTimeout property doesn't exist in ontology, using hasCondition
            link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), timeout_iri)
            timeout_expr_triples ++ [link_triple]

          {:ok, {timeout_iri, timeout_expr_triples, _updated_context}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), timeout_iri)
            timeout_expr_triples ++ [link_triple]

          :skip ->
            []
        end

      # Extract after body
      body_triples_with_link =
        case expression_builder.build(after_clause.body, context, suffix: "after_body") do
          {:ok, {body_iri, body_expr_triples}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasAfterClause(), body_iri)
            body_expr_triples ++ [link_triple]

          {:ok, {body_iri, body_expr_triples, _updated_context}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasAfterClause(), body_iri)
            body_expr_triples ++ [link_triple]

          :skip ->
            []
        end

      timeout_triples ++ body_triples_with_link ++ triples
    else
      # Light mode: store boolean flag only
      triple = Helpers.datatype_property(expr_iri, Core.hasAfterTimeout(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_receive_after_triples(
         triples,
         _expr_iri,
         _after_clause,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # ===========================================================================
  # Private - Try Expression Helpers
  # ===========================================================================

  # Extract try body expression
  defp add_try_body_triple(
         triples,
         expr_iri,
         body,
         expression_builder,
         build_expressions?,
         context
       ) do
    if build_expressions? and not is_nil(body) do
      case expression_builder.build(body, context, suffix: "body") do
        {:ok, {body_iri, body_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
          body_triples ++ [link_triple | triples]

        {:ok, {body_iri, body_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
          body_triples ++ [link_triple | triples]

        :skip ->
          triples
      end
    else
      triples
    end
  end

  # Extract rescue clauses
  defp add_rescue_clause_triples(
         triples,
         expr_iri,
         clauses,
         expression_builder,
         build_expressions?,
         context
       )
       when is_list(clauses) and clauses != [] do
    if build_expressions? do
      Enum.reduce(clauses, triples, fn clause, acc ->
        add_rescue_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
      end)
    else
      triple = Helpers.datatype_property(expr_iri, Core.hasRescueClause(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_rescue_clause_triples(
         triples,
         _expr_iri,
         _clauses,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # Rescue clause expression extraction
  defp add_rescue_clause_expression_triples(
         triples,
         expr_iri,
         clause,
         expression_builder,
         context
       ) do
    # Create unique IRI for this rescue clause
    clause_index = :erlang.unique_integer([:positive, :monotonic])
    clause_iri = RDF.iri("#{expr_iri}/rescue/#{clause_index}")

    # Build rescue body
    body_triples_with_link =
      case expression_builder.build(clause.body, context, suffix: "rescue_#{clause_index}_body") do
        {:ok, {body_iri, body_triples}} ->
          link_triple = Helpers.object_property(clause_iri, Structure.hasBody(), body_iri)
          body_triples ++ [link_triple]

        {:ok, {body_iri, body_triples, _updated_context}} ->
          link_triple = Helpers.object_property(clause_iri, Structure.hasBody(), body_iri)
          body_triples ++ [link_triple]

        :skip ->
          []
      end

    # Link to clause via hasRescueClause
    clause_link_triple = Helpers.object_property(expr_iri, Core.hasRescueClause(), clause_iri)

    body_triples_with_link ++ [clause_link_triple] ++ triples
  end

  # Extract catch clauses
  defp add_catch_clause_triples(
         triples,
         expr_iri,
         clauses,
         expression_builder,
         build_expressions?,
         context
       )
       when is_list(clauses) and clauses != [] do
    if build_expressions? do
      Enum.reduce(clauses, triples, fn clause, acc ->
        add_catch_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
      end)
    else
      triple = Helpers.datatype_property(expr_iri, Core.hasCatchClause(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_catch_clause_triples(
         triples,
         _expr_iri,
         _clauses,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # Catch clause expression extraction
  defp add_catch_clause_expression_triples(triples, expr_iri, clause, expression_builder, context) do
    # Build pattern for catch
    clause_index = :erlang.unique_integer([:positive, :monotonic])
    pattern_iri = RDF.iri("#{expr_iri}/catch/#{clause_index}/pattern")
    pattern_triples = ExpressionBuilder.build_pattern(clause.pattern, pattern_iri, context)
    pattern_link_triple = Helpers.object_property(expr_iri, Core.hasPattern(), pattern_iri)

    # Build catch body
    body_triples_with_link =
      case expression_builder.build(clause.body, context, suffix: "catch_#{clause_index}_body") do
        {:ok, {body_iri, body_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
          body_triples ++ [link_triple]

        {:ok, {body_iri, body_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Structure.hasBody(), body_iri)
          body_triples ++ [link_triple]

        :skip ->
          []
      end

    # Link to clause via hasCatchClause
    clause_link_triple = Helpers.object_property(expr_iri, Core.hasCatchClause(), pattern_iri)

    pattern_triples ++
      [pattern_link_triple] ++ body_triples_with_link ++ [clause_link_triple] ++ triples
  end

  # Extract else clauses (similar to case else clauses)
  defp add_else_clause_triples(
         triples,
         expr_iri,
         clauses,
         expression_builder,
         build_expressions?,
         context
       )
       when is_list(clauses) and clauses != [] do
    if build_expressions? do
      Enum.reduce(clauses, triples, fn clause, acc ->
        add_try_else_clause_expression_triples(acc, expr_iri, clause, expression_builder, context)
      end)
    else
      triples
    end
  end

  defp add_else_clause_triples(
         triples,
         _expr_iri,
         _clauses,
         _expression_builder,
         _build_expressions?,
         _context
       ),
       do: triples

  # Else clause expression extraction (similar to case else clauses)
  defp add_try_else_clause_expression_triples(
         triples,
         expr_iri,
         clause,
         expression_builder,
         context
       ) do
    clause_index = :erlang.unique_integer([:positive, :monotonic])

    # Build pattern
    pattern_iri = RDF.iri("#{expr_iri}/else/#{clause_index}/pattern")
    pattern_triples = ExpressionBuilder.build_pattern(clause.pattern, pattern_iri, context)
    pattern_link_triple = Helpers.object_property(expr_iri, Core.hasPattern(), pattern_iri)

    # Build guard if present
    guard_triples =
      if clause.guard != nil do
        case expression_builder.build(clause.guard, context, suffix: "else_#{clause_index}_guard") do
          {:ok, {guard_iri, guard_expr_triples}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasGuard(), guard_iri)
            guard_expr_triples ++ [link_triple]

          {:ok, {guard_iri, guard_expr_triples, _updated_context}} ->
            link_triple = Helpers.object_property(expr_iri, Core.hasGuard(), guard_iri)
            guard_expr_triples ++ [link_triple]

          :skip ->
            []
        end
      else
        []
      end

    # Build body
    body_triples_with_link =
      case expression_builder.build(clause.body, context, suffix: "else_#{clause_index}_body") do
        {:ok, {body_iri, body_expr_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
          body_expr_triples ++ [link_triple]

        {:ok, {body_iri, body_expr_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasThenBranch(), body_iri)
          body_expr_triples ++ [link_triple]

        :skip ->
          []
      end

    pattern_triples ++ [pattern_link_triple] ++ guard_triples ++ body_triples_with_link ++ triples
  end

  # Extract after block
  defp add_try_after_triple(
         triples,
         expr_iri,
         after_body,
         expression_builder,
         build_expressions?,
         context
       ) do
    if build_expressions? and not is_nil(after_body) do
      case expression_builder.build(after_body, context, suffix: "after") do
        {:ok, {after_iri, after_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasAfterClause(), after_iri)
          after_triples ++ [link_triple | triples]

        {:ok, {after_iri, after_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasAfterClause(), after_iri)
          after_triples ++ [link_triple | triples]

        :skip ->
          triples
      end
    else
      triples
    end
  end

  # ===========================================================================
  # Private - Raise/Throw Expression Helpers
  # ===========================================================================

  # Extract raise argument (message or exception expression)
  defp add_raise_argument_triple(
         triples,
         expr_iri,
         raise_expr,
         expression_builder,
         build_expressions?,
         context
       ) do
    if build_expressions? do
      # For raise, we extract the message as the primary expression
      # If there's an exception module, we can add it as an atom
      message_triples =
        if not is_nil(raise_expr.message) do
          case expression_builder.build(raise_expr.message, context, suffix: "message") do
            {:ok, {msg_iri, msg_triples}} ->
              link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), msg_iri)
              msg_triples ++ [link_triple]

            {:ok, {msg_iri, msg_triples, _updated_context}} ->
              link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), msg_iri)
              msg_triples ++ [link_triple]

            :skip ->
              []
          end
        else
          []
        end

      triples ++ message_triples
    else
      triples
    end
  end

  # Extract throw value
  defp add_throw_value_triple(
         triples,
         expr_iri,
         value,
         expression_builder,
         build_expressions?,
         context
       ) do
    if build_expressions? do
      case expression_builder.build(value, context, suffix: "value") do
        {:ok, {value_iri, value_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), value_iri)
          value_triples ++ [link_triple | triples]

        {:ok, {value_iri, value_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasCondition(), value_iri)
          value_triples ++ [link_triple | triples]

        :skip ->
          triples
      end
    else
      triples
    end
  end

  # ===========================================================================
  # Private - Comprehension Helpers
  # ===========================================================================

  # Maximum nesting depth for comprehensions to prevent stack overflow
  @max_comprehension_depth 50

  # IRI helper functions for comprehensions
  defp generator_iri(comprehension_iri, index) do
    RDF.iri("#{comprehension_iri.value}/gen/#{index}")
  end

  defp pattern_iri(generator_iri) do
    RDF.iri("#{generator_iri}/pattern")
  end

  defp filter_iri(comprehension_iri, index) do
    RDF.iri("#{comprehension_iri.value}/filter/#{index}")
  end

  # Add generator triples with optional expression building
  defp add_generator_triples(
         triples,
         expr_iri,
         generators,
         expression_builder,
         build_expressions?,
         context,
         containing_function,
         comprehension_index
       )
       when is_list(generators) and generators != [] do
    if build_expressions? do
      # Build full expression triples for each generator's enumerable and pattern
      {all_generator_triples, _} =
        Enum.map_reduce(generators, 0, fn gen, idx ->
          gen_iri = generator_iri(expr_iri, idx)
          pattern_iri = pattern_iri(gen_iri)

          gen_triples =
            []
            |> add_type_triple(gen_iri, Core.Generator)
            |> add_generator_pattern_triple(pattern_iri, gen.pattern, expression_builder, context)
            |> add_generator_enumerable_triple(
              gen_iri,
              gen.enumerable,
              expression_builder,
              context,
              containing_function,
              comprehension_index,
              idx
            )
            |> add_pattern_link_triple(gen_iri, pattern_iri)

          link_triple = Helpers.object_property(expr_iri, Core.hasGenerator(), gen_iri)
          {gen_triples ++ [link_triple], idx + 1}
        end)

      List.flatten(all_generator_triples) ++ triples
    else
      # Light mode: store boolean flag only
      triple = Helpers.datatype_property(expr_iri, Core.hasGenerator(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_generator_triples(
         triples,
         _expr_iri,
         _generators,
         _expression_builder,
         _build_expressions?,
         _context,
         _containing_function,
         _index
       ),
       do: triples

  # Add enumerable expression for a generator
  defp add_generator_enumerable_triple(
         triples,
         gen_iri,
         enumerable,
         expression_builder,
         context,
         containing_function,
         comp_index,
         gen_index
       ) do
    case expression_builder.build(enumerable, context,
           containing_function: containing_function,
           index: comp_index * 100 + gen_index
         ) do
      {:ok, {enum_iri, enum_triples}} ->
        link_triple = Helpers.object_property(gen_iri, Core.hasEnumerable(), enum_iri)
        enum_triples ++ [link_triple | triples]

      {:ok, {enum_iri, enum_triples, _updated_context}} ->
        link_triple = Helpers.object_property(gen_iri, Core.hasEnumerable(), enum_iri)
        enum_triples ++ [link_triple | triples]

      :skip ->
        triples
    end
  end

  # Add pattern triples for a generator
  defp add_generator_pattern_triple(
         triples,
         pattern_iri,
         pattern_ast,
         expression_builder,
         context
       ) do
    pattern_triples = expression_builder.build_pattern(pattern_ast, pattern_iri, context)
    pattern_triples ++ triples
  end

  # Link generator to its pattern
  defp add_pattern_link_triple(triples, gen_iri, pattern_iri) do
    link_triple = Helpers.object_property(gen_iri, Core.hasPattern(), pattern_iri)
    [link_triple | triples]
  end

  # Add filter triples with optional expression building
  defp add_filter_triples(
         triples,
         expr_iri,
         filters,
         expression_builder,
         build_expressions?,
         context,
         containing_function,
         comprehension_index
       )
       when is_list(filters) and filters != [] do
    if build_expressions? do
      # Build full expression triples for each filter
      {all_filter_triples, _} =
        Enum.map_reduce(filters, 0, fn filter, idx ->
          filter_iri = filter_iri(expr_iri, idx)

          filter_triples =
            []
            |> add_type_triple(filter_iri, Core.Filter)
            |> add_filter_expression_triple(
              filter_iri,
              filter.expression,
              expression_builder,
              context,
              containing_function,
              comprehension_index,
              idx
            )

          link_triple = Helpers.object_property(expr_iri, Core.hasFilter(), filter_iri)
          {filter_triples ++ [link_triple], idx + 1}
        end)

      List.flatten(all_filter_triples) ++ triples
    else
      # Light mode: store boolean flag only
      triple = Helpers.datatype_property(expr_iri, Core.hasFilter(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_filter_triples(
         triples,
         _expr_iri,
         _filters,
         _expression_builder,
         _build_expressions?,
         _context,
         _containing_function,
         _index
       ),
       do: triples

  # Add filter expression
  defp add_filter_expression_triple(
         triples,
         filter_iri,
         expression,
         expression_builder,
         context,
         containing_function,
         comp_index,
         filter_index
       ) do
    case expression_builder.build(expression, context,
           containing_function: containing_function,
           index: comp_index * 100 + filter_index + 50
         ) do
      {:ok, {expr_iri, expr_triples}} ->
        link_triple = Helpers.object_property(filter_iri, Core.hasFilterExpression(), expr_iri)
        expr_triples ++ [link_triple | triples]

      {:ok, {expr_iri, expr_triples, _updated_context}} ->
        link_triple = Helpers.object_property(filter_iri, Core.hasFilterExpression(), expr_iri)
        expr_triples ++ [link_triple | triples]

      :skip ->
        triples
    end
  end

  # Add comprehension body triple
  defp add_comprehension_body_triple(
         triples,
         _expr_iri,
         nil,
         _expression_builder,
         _build_expressions?,
         _context,
         _containing_function,
         _index
       ),
       do: triples

  defp add_comprehension_body_triple(
         triples,
         expr_iri,
         %Comprehension{} = body_comprehension,
         expression_builder,
         build_expressions?,
         context,
         containing_function,
         comprehension_index
       ) do
    if build_expressions? and
         comprehension_depth_level(comprehension_index) < @max_comprehension_depth do
      # Nested comprehension - recursively build it with updated index
      nested_index = comprehension_index * 100 + 99

      {body_iri, body_triples} =
        build_comprehension(body_comprehension, context,
          containing_function: containing_function,
          index: nested_index,
          expression_builder: expression_builder
        )

      link_triple = Helpers.object_property(expr_iri, Core.hasCollectExpression(), body_iri)
      body_triples ++ [link_triple | triples]
    else
      # Skip nested comprehension if depth exceeded or not in full mode
      triples
    end
  end

  defp add_comprehension_body_triple(
         triples,
         expr_iri,
         body,
         expression_builder,
         build_expressions?,
         context,
         containing_function,
         comprehension_index
       ) do
    if build_expressions? and body != nil do
      case expression_builder.build(body, context,
             containing_function: containing_function,
             index: comprehension_index * 100 + 99
           ) do
        {:ok, {body_iri, body_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasCollectExpression(), body_iri)
          body_triples ++ [link_triple | triples]

        {:ok, {body_iri, body_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasCollectExpression(), body_iri)
          body_triples ++ [link_triple | triples]

        :skip ->
          triples
      end
    else
      triples
    end
  end

  # Calculate the nesting depth level from the comprehension index
  # Index 0 -> level 0, Index 99 -> level 1, Index 9999 -> level 2, etc.
  defp comprehension_depth_level(index) when index < 100, do: 0
  defp comprehension_depth_level(index), do: 1 + comprehension_depth_level(div(index, 100))

  # Track comprehension options (into, reduce, uniq) with optional expression building
  defp add_comprehension_options_triples(
         triples,
         expr_iri,
         options,
         expression_builder,
         build_expressions?,
         context,
         containing_function,
         comprehension_index
       )
       when is_map(options) do
    triples
    |> add_into_option_triple(
      expr_iri,
      Map.get(options, :into),
      expression_builder,
      build_expressions?,
      context,
      containing_function,
      comprehension_index
    )
    |> add_reduce_option_triple(
      expr_iri,
      Map.get(options, :reduce),
      expression_builder,
      build_expressions?,
      context,
      containing_function,
      comprehension_index
    )
    |> add_uniq_option_triple(expr_iri, Map.get(options, :uniq))
  end

  defp add_comprehension_options_triples(
         triples,
         _expr_iri,
         _options,
         _expression_builder,
         _build_expressions?,
         _context,
         _containing_function,
         _index
       ),
       do: triples

  defp add_into_option_triple(
         triples,
         expr_iri,
         into,
         expression_builder,
         build_expressions?,
         context,
         containing_function,
         comprehension_index
       )
       when not is_nil(into) do
    if build_expressions? do
      case expression_builder.build(into, context,
             containing_function: containing_function,
             index: comprehension_index * 100 + 10
           ) do
        {:ok, {into_iri, into_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasIntoOption(), into_iri)
          into_triples ++ [link_triple | triples]

        {:ok, {into_iri, into_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasIntoOption(), into_iri)
          into_triples ++ [link_triple | triples]

        :skip ->
          triple =
            Helpers.datatype_property(expr_iri, Core.hasIntoOption(), true, RDF.XSD.Boolean)

          [triple | triples]
      end
    else
      triple = Helpers.datatype_property(expr_iri, Core.hasIntoOption(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_into_option_triple(
         triples,
         _expr_iri,
         _into,
         _expression_builder,
         _build_expressions?,
         _context,
         _containing_function,
         _index
       ),
       do: triples

  defp add_reduce_option_triple(
         triples,
         expr_iri,
         reduce,
         expression_builder,
         build_expressions?,
         context,
         containing_function,
         comprehension_index
       )
       when not is_nil(reduce) do
    if build_expressions? do
      case expression_builder.build(reduce, context,
             containing_function: containing_function,
             index: comprehension_index * 100 + 20
           ) do
        {:ok, {reduce_iri, reduce_triples}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasReduceOption(), reduce_iri)
          reduce_triples ++ [link_triple | triples]

        {:ok, {reduce_iri, reduce_triples, _updated_context}} ->
          link_triple = Helpers.object_property(expr_iri, Core.hasReduceOption(), reduce_iri)
          reduce_triples ++ [link_triple | triples]

        :skip ->
          triple =
            Helpers.datatype_property(expr_iri, Core.hasReduceOption(), true, RDF.XSD.Boolean)

          [triple | triples]
      end
    else
      triple = Helpers.datatype_property(expr_iri, Core.hasReduceOption(), true, RDF.XSD.Boolean)
      [triple | triples]
    end
  end

  defp add_reduce_option_triple(
         triples,
         _expr_iri,
         _reduce,
         _expression_builder,
         _build_expressions?,
         _context,
         _containing_function,
         _index
       ),
       do: triples

  defp add_uniq_option_triple(triples, expr_iri, true) do
    triple = Helpers.datatype_property(expr_iri, Core.hasUniqOption(), true, RDF.XSD.Boolean)
    [triple | triples]
  end

  defp add_uniq_option_triple(triples, _expr_iri, _uniq), do: triples

  # ===========================================================================
  # Private - Common Helpers
  # ===========================================================================

  # Helper for building expressions with the expression_builder.
  # Handles the 3-way return pattern: {:ok, {iri, triples}}, {:ok, {iri, triples, context}}, or :skip
  defp add_location_triple(triples, expr_iri, %{line: line}) when is_integer(line) do
    triple = Helpers.datatype_property(expr_iri, Core.startLine(), line, RDF.XSD.PositiveInteger)
    [triple | triples]
  end

  defp add_location_triple(triples, _expr_iri, _location), do: triples
end
