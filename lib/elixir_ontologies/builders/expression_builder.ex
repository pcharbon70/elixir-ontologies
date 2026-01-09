defmodule ElixirOntologies.Builders.ExpressionBuilder do
  @moduledoc """
  Builds RDF triples for Elixir AST expression nodes.

  This module converts Elixir AST nodes to their RDF representation
  according to the elixir-core.ttl ontology. Expression extraction is
  opt-in via the `include_expressions` configuration option.

  ## Mode Selection

  Expression extraction only occurs in "full mode" which requires:
  - `include_expressions: true` in the configuration
  - The file being processed is project code (not a dependency)

  When either condition is false, `build/3` returns `:skip`.

  ## Usage

      context = Context.new(
        base_iri: "https://example.org/code#",
        config: %{include_expressions: true},
        file_path: "lib/my_app/users.ex"
      )

      # Build expression from AST
      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, triples}} = ExpressionBuilder.build(ast, context)

      # In light mode or for dependencies
      ExpressionBuilder.build(ast, light_mode_context)
      # => :skip

  ## Expression Dispatch

  The builder pattern matches on AST node types and dispatches to
  specialized builders:

  - Comparison operators (`==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`)
  - Logical operators (`and`, `or`, `not`, `&&`, `||`, `!`)
  - Arithmetic operators (`+`, `-`, `*`, `/`, `div`, `rem`)
  - Literals (integers, floats, strings, atoms)
  - Variables and wildcards
  - Remote and local function calls
  - Unknown expressions (generic `Expression` type)

  ## Return Values

  - `{:ok, {expr_iri, triples}}` - Expression successfully built
  - `:skip` - Expression should not be extracted (light mode or nil AST)

  ## IRI Generation

  Expression IRIs are generated using a deterministic counter pattern:
  `{base_iri}expr/{counter}` (e.g., `expr/0`, `expr/1`, `expr/2`)

  The counter is maintained in the context metadata and increments for each
  expression built, ensuring:
  - Deterministic IRIs within a single extraction
  - Uniqueness across all expressions in a graph
  - Queryable expression structure via SPARQL

  For child expressions (operands in binary operators), relative IRIs are used:
  `{base_iri}expr/{counter}/left`, `{base_iri}expr/{counter}/right`

  The `expression_iri/3`, `fresh_iri/2`, and `get_or_create_iri/3` functions
  provide flexible IRI generation patterns for different use cases.
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.NS.Core

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for an Elixir AST expression node.

  Returns `:skip` when expression extraction is disabled or the AST is nil.
  Returns `{:ok, {expr_iri, triples}}` with the expression IRI and all triples.

  ## Parameters

  - `ast` - The Elixir AST node (3-tuple format or literal)
  - `context` - The builder context containing configuration
  - `opts` - Optional keyword list for IRI generation

  ## Options

  - `:base_iri` - Override IRI base (defaults to `context.base_iri`)
  - `:suffix` - IRI suffix (defaults to generated counter)
  - `:counter` - Counter for unique IRIs (internal use)

  ## Examples

      # Full mode - expression extracted
      context = Context.new(
        base_iri: "https://example.org/code#",
        config: %{include_expressions: true},
        file_path: "lib/my_app/users.ex"
      )

      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, triples}} = ExpressionBuilder.build(ast, context)

      # Light mode - expression skipped
      light_context = Context.new(
        base_iri: "https://example.org/code#",
        config: %{include_expressions: false},
        file_path: "lib/my_app/users.ex"
      )

      ExpressionBuilder.build(ast, light_context)
      # => :skip

      # Dependency file - always skipped
      dep_context = Context.new(
        base_iri: "https://example.org/code#",
        config: %{include_expressions: true},
        file_path: "deps/decimal/lib/decimal.ex"
      )

      ExpressionBuilder.build(ast, dep_context)
      # => :skip

  """
  @spec build(Macro.t() | nil, Context.t(), keyword()) ::
          {:ok, {RDF.IRI.t(), [RDF.Triple.t()]}} | :skip
  def build(nil, _context, _opts), do: :skip

  def build(ast, %Context{} = context, opts) do
    # Check if we should extract full expressions for this file
    if Context.full_mode_for_file?(context, context.file_path) do
      do_build(ast, context, opts)
    else
      :skip
    end
  end

  # ===========================================================================
  # Main Build Logic
  # ===========================================================================

  defp do_build(ast, context, opts) do
    # Get base IRI from options or context
    base_iri = Keyword.get(opts, :base_iri, context.base_iri)

    # Generate expression IRI
    # Uses a process-keyed counter to maintain state across build calls
    # within the same extraction process
    expr_iri = expression_iri_for_build(base_iri, opts)

    # Build expression triples
    triples = build_expression_triples(ast, expr_iri, context)

    {:ok, {expr_iri, triples}}
  end

  # Gets or creates a counter key for this base IRI
  defp counter_key(base_iri), do: {:expression_builder_counter, base_iri}

  # Gets the next counter value for this base IRI
  defp get_next_counter(base_iri) do
    key = counter_key(base_iri)

    case Process.get(key) do
      nil ->
        Process.put(key, 1)
        0

      counter ->
        Process.put(key, counter + 1)
        counter
    end
  end

  # Resets the counter for this base IRI (useful for testing)
  @doc false
  def reset_counter(base_iri) do
    Process.delete(counter_key(base_iri))
    :ok
  end

  # Generates an expression IRI for the build/3 flow
  # Uses process dictionary to maintain counter across calls
  defp expression_iri_for_build(base_iri, opts) do
    suffix =
      cond do
        # Explicit suffix provided (doesn't use counter)
        custom_suffix = Keyword.get(opts, :suffix) ->
          custom_suffix

        # Explicit counter provided (advanced use)
        counter = Keyword.get(opts, :counter) ->
          "expr_#{counter}"

        # Use process-local counter for deterministic IRIs
        true ->
          counter = get_next_counter(base_iri)
          "expr_#{counter}"
      end

    iri_string = "#{base_iri}expr/#{suffix}"
    RDF.IRI.new(iri_string)
  end

  # ===========================================================================
  # Expression Dispatch
  # ===========================================================================

  @doc false
  @spec build_expression_triples(Macro.t(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  def build_expression_triples(ast, expr_iri, context)

  # Comparison operators
  def build_expression_triples({:==, _, [left, right]}, expr_iri, context) do
    build_comparison(:==, left, right, expr_iri, context)
  end

  def build_expression_triples({:!=, _, [left, right]}, expr_iri, context) do
    build_comparison(:!=, left, right, expr_iri, context)
  end

  def build_expression_triples({:===, _, [left, right]}, expr_iri, context) do
    build_comparison(:===, left, right, expr_iri, context)
  end

  def build_expression_triples({:!==, _, [left, right]}, expr_iri, context) do
    build_comparison(:!==, left, right, expr_iri, context)
  end

  def build_expression_triples({:<, _, [left, right]}, expr_iri, context) do
    build_comparison(:<, left, right, expr_iri, context)
  end

  def build_expression_triples({:>, _, [left, right]}, expr_iri, context) do
    build_comparison(:>, left, right, expr_iri, context)
  end

  def build_expression_triples({:<=, _, [left, right]}, expr_iri, context) do
    build_comparison(:<=, left, right, expr_iri, context)
  end

  def build_expression_triples({:>=, _, [left, right]}, expr_iri, context) do
    build_comparison(:>=, left, right, expr_iri, context)
  end

  # Logical operators
  def build_expression_triples({:and, _, [left, right]}, expr_iri, context) do
    build_logical(:and, left, right, expr_iri, context)
  end

  def build_expression_triples({:or, _, [left, right]}, expr_iri, context) do
    build_logical(:or, left, right, expr_iri, context)
  end

  def build_expression_triples({:&&, _, [left, right]}, expr_iri, context) do
    build_logical(:&&, left, right, expr_iri, context)
  end

  def build_expression_triples({:||, _, [left, right]}, expr_iri, context) do
    build_logical(:||, left, right, expr_iri, context)
  end

  # Unary operators (not, !, +, -)
  def build_expression_triples({:not, _, [arg]}, expr_iri, context) do
    build_unary(:not, arg, expr_iri, context)
  end

  def build_expression_triples({:!, _, [arg]}, expr_iri, context) do
    build_unary(:!, arg, expr_iri, context)
  end

  # Arithmetic operators
  def build_expression_triples({:+, _, [left, right]}, expr_iri, context) do
    build_arithmetic(:+, left, right, expr_iri, context)
  end

  def build_expression_triples({:-, _, [left, right]}, expr_iri, context) do
    build_arithmetic(:-, left, right, expr_iri, context)
  end

  def build_expression_triples({:*, _, [left, right]}, expr_iri, context) do
    build_arithmetic(:*, left, right, expr_iri, context)
  end

  def build_expression_triples({:/, _, [left, right]}, expr_iri, context) do
    build_arithmetic(:/, left, right, expr_iri, context)
  end

  def build_expression_triples({:div, _, [left, right]}, expr_iri, context) do
    build_arithmetic(:div, left, right, expr_iri, context)
  end

  def build_expression_triples({:rem, _, [left, right]}, expr_iri, context) do
    build_arithmetic(:rem, left, right, expr_iri, context)
  end

  # Pipe operator
  def build_expression_triples({:|>, _, [left, right]}, expr_iri, context) do
    build_pipe(left, right, expr_iri, context)
  end

  # String concatenation
  def build_expression_triples({:<>, _, [left, right]}, expr_iri, context) do
    build_string_concat(left, right, expr_iri, context)
  end

  # List operators
  def build_expression_triples({:++, _, [left, right]}, expr_iri, context) do
    build_list_op(:++, left, right, expr_iri, context)
  end

  def build_expression_triples({:--, _, [left, right]}, expr_iri, context) do
    build_list_op(:--, left, right, expr_iri, context)
  end

  # Match operator
  def build_expression_triples({:=, _, [left, right]}, expr_iri, context) do
    build_match(left, right, expr_iri, context)
  end

  # Integer literals
  def build_expression_triples(int, _expr_iri, _context) when is_integer(int) do
    # Literals are handled inline in parent expressions
    # This is a fallback for standalone literals
    []
  end

  # Float literals
  def build_expression_triples(float, _expr_iri, _context) when is_float(float) do
    []
  end

  # String literals (binaries)
  def build_expression_triples(str, _expr_iri, _context) when is_binary(str) do
    []
  end

  # Atom literals (including true, false, nil)
  def build_expression_triples(atom, _expr_iri, _context) when is_atom(atom) do
    []
  end

  # Local call: function(args) - must come before variable pattern
  def build_expression_triples({function, meta, args}, expr_iri, context)
      when is_atom(function) and is_list(meta) and is_list(args) do
    build_local_call(function, args, expr_iri, context)
  end

  # Remote call: Module.function(args)
  def build_expression_triples(
        {{:., _, [module, function]}, _, args},
        expr_iri,
        context
      ) do
    build_remote_call(module, function, args, expr_iri, context)
  end

  # Variable pattern: {name, meta, ctx} where ctx is nil or an atom
  # This must come after calls to avoid matching function calls
  def build_expression_triples({name, meta, ctx} = var, expr_iri, build_context)
      when is_atom(name) and is_list(meta) and (is_nil(ctx) or is_atom(ctx)) do
    build_variable(var, expr_iri, build_context)
  end

  # Wildcard pattern
  def build_expression_triples({:_}, expr_iri, _context) do
    build_wildcard(expr_iri)
  end

  # Fallback for unknown expressions
  def build_expression_triples(_ast, expr_iri, _context) do
    build_generic_expression(expr_iri)
  end

  # ===========================================================================
  # Builder Functions
  # ===========================================================================

  # Comparison operators (==, !=, ===, !==, <, >, <=, >=)
  defp build_comparison(op, _left, _right, expr_iri, _context) do
    # For Phase 21.2, create a stub with operator symbol
    # Full implementation with nested expressions in Phase 21.4
    [
      Helpers.type_triple(expr_iri, Core.ComparisonOperator),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), to_string(op), RDF.XSD.String)
    ]
  end

  # Logical operators (and, or, &&, ||)
  defp build_logical(op, _left, _right, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.LogicalOperator),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), to_string(op), RDF.XSD.String)
    ]
  end

  # Arithmetic operators (+, -, *, /, div, rem)
  defp build_arithmetic(op, _left, _right, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.ArithmeticOperator),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), to_string(op), RDF.XSD.String)
    ]
  end

  # Unary operators (not, !)
  defp build_unary(op, _arg, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.LogicalOperator),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), to_string(op), RDF.XSD.String)
    ]
  end

  # Pipe operator (|>)
  defp build_pipe(_left, _right, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.PipeOperator),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), "|>", RDF.XSD.String)
    ]
  end

  # String concatenation (<>)
  defp build_string_concat(_left, _right, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.StringConcatOperator),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), "<>", RDF.XSD.String)
    ]
  end

  # List operators (++, --)
  defp build_list_op(op, _left, _right, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.ListOperator),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), to_string(op), RDF.XSD.String)
    ]
  end

  # Match operator (=)
  defp build_match(_left, _right, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.MatchOperator),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), "=", RDF.XSD.String)
    ]
  end

  # Remote call: Module.function(args)
  defp build_remote_call(module, function, _args, expr_iri, _context) do
    # Extract module name from aliases AST
    module_name =
      case module do
        {:__aliases__, _, parts} -> Enum.join(parts, ".")
        {:@, _, [{:__, _, [:module]}]} -> :__MODULE__
        {:__MODULE__, [], []} -> :__MODULE__
        _ -> inspect(module)
      end

    function_name =
      case function do
        fun when is_atom(fun) -> fun
        _ -> inspect(function)
      end

    [
      Helpers.type_triple(expr_iri, Core.RemoteCall),
      Helpers.datatype_property(expr_iri, Core.name(), "#{module_name}.#{function_name}", RDF.XSD.String)
    ]
  end

  # Local call: function(args)
  defp build_local_call(function, _args, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.LocalCall),
      Helpers.datatype_property(expr_iri, Core.name(), to_string(function), RDF.XSD.String)
    ]
  end

  # Variable: {name, meta, ctx}
  defp build_variable({name, _meta, _ctx}, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.Variable),
      Helpers.datatype_property(expr_iri, Core.name(), to_string(name), RDF.XSD.String)
    ]
  end

  # Wildcard pattern: _
  defp build_wildcard(expr_iri) do
    [Helpers.type_triple(expr_iri, Core.WildcardPattern)]
  end

  # Generic expression for unknown AST nodes
  defp build_generic_expression(expr_iri) do
    [Helpers.type_triple(expr_iri, Core.Expression)]
  end

  # ===========================================================================
  # IRI Generation
  # ===========================================================================

  @doc """
  Generates an expression IRI with deterministic counter-based suffix.

  ## Parameters

  - `base_iri` - The base IRI string (e.g., "https://example.org/code#")
  - `context` - The builder context (for counter access)
  - `opts` - Optional keywords:
    - `:suffix` - Custom suffix (overrides counter generation)
    - `:counter` - Specific counter value (advanced use)

  ## Returns

  `{iri, updated_context}` - The expression IRI and context with incremented counter

  ## Examples

      # Using context counter (recommended)
      {iri, context} = expression_iri("https://example.org/code#", context)
      # => {~I<https://example.org/code#expr/0>, %Context{metadata: %{expression_counter: 1}}}

      # With custom suffix
      {iri, context} = expression_iri("https://example.org/code#", context, suffix: "my_expr")
      # => {~I<https://example.org/code#expr/my_expr>, %Context{}}

  """
  @spec expression_iri(String.t(), Context.t(), keyword()) :: {RDF.IRI.t(), Context.t()}
  def expression_iri(base_iri, context, opts \\ []) do
    {suffix, updated_context} =
      cond do
        # Explicit suffix provided (doesn't consume counter)
        custom_suffix = Keyword.get(opts, :suffix) ->
          {custom_suffix, context}

        # Explicit counter provided (advanced use)
        counter = Keyword.get(opts, :counter) ->
          {"expr_#{counter}", context}

        # Use context counter for deterministic IRIs
        true ->
          {counter, new_context} = Context.next_expression_counter(context)
          {"expr_#{counter}", new_context}
      end

    iri_string = "#{base_iri}expr/#{suffix}"
    iri = RDF.IRI.new(iri_string)

    {iri, updated_context}
  end

  @doc """
  Generates a relative IRI for child expressions.

  Child expressions (like left/right operands) get IRIs relative to their
  parent expression for clear hierarchy in the RDF graph.

  ## Parameters

  - `parent_iri` - The parent expression's IRI
  - `child_name` - The child relationship name (e.g., "left", "right", "condition")

  ## Returns

  A new IRI that is relative to the parent

  ## Examples

      parent = ~I<https://example.org/code#expr/0>
      fresh_iri(parent, "left")
      # => ~I<https://example.org/code#expr/0/left>

      fresh_iri(parent, "right")
      # => ~I<https://example.org/code#expr/0/right>

  """
  @spec fresh_iri(RDF.IRI.t(), String.t()) :: RDF.IRI.t()
  def fresh_iri(parent_iri, child_name) when is_binary(child_name) do
    parent_string = RDF.IRI.to_string(parent_iri)
    iri_string = "#{parent_string}/#{child_name}"
    RDF.IRI.new(iri_string)
  end

  @doc """
  Gets or creates an IRI from a cache, supporting expression deduplication.

  This pattern allows sharing the same IRI for identical sub-expressions
  that appear multiple times in a graph, reducing redundancy.

  ## Parameters

  - `cache` - A map cache (can be `nil` to skip caching)
  - `key` - Cache key (typically AST hash or structure signature)
  - `generator` - A zero-arity function that generates a new IRI

  ## Returns

  `{iri, updated_cache}` - The IRI (cached or new) and updated cache map

  ## Examples

      # First call - creates new IRI
      cache = %{}
      {iri1, cache1} = get_or_create_iri(cache, :some_key, fn -> ~I<https://example.org/expr/0> end)

      # Second call with same key - reuses cached IRI
      {iri2, cache2} = get_or_create_iri(cache1, :some_key, fn -> ~I<https://example.org/expr/1> end)
      iri1 == iri2  # => true

      # Different key - creates new IRI
      {iri3, cache3} = get_or_create_iri(cache2, :other_key, fn -> ~I<https://example.org/expr/2> end)
      iri1 == iri3  # => false

  """
  @spec get_or_create_iri(map() | nil, term(), function()) :: {RDF.IRI.t(), map()}
  def get_or_create_iri(nil, _key, generator), do: {generator.(), %{}}

  def get_or_create_iri(cache, key, generator) when is_map(cache) do
    case Map.get(cache, key) do
      nil ->
        iri = generator.()
        {iri, Map.put(cache, key, iri)}

      cached_iri ->
        {cached_iri, cache}
    end
  end
end
