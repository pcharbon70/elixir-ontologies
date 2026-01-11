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
      |> Context.with_expression_counter()

      # Build expression from AST
      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, triples, updated_context}} = ExpressionBuilder.build(ast, context)

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

  - `{:ok, {expr_iri, triples, updated_context}}` - Expression successfully built
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

  ## Limitations

  The following builder functions currently only record the call signature:
  - `build_remote_call/5` - Records `Module.function` but doesn't build argument expressions
  - `build_local_call/4` - Records `function` but doesn't build argument expressions

  Full argument expression building is planned for a future phase. The current
  implementation captures the function call identity but does not recursively
  build the argument ASTs into expression triples.
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.NS.Core

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for an Elixir AST expression node.

  Returns `:skip` when expression extraction is disabled or the AST is nil.
  Returns `{:ok, {expr_iri, triples, updated_context}}` with the expression IRI,
  all triples, and updated context with incremented counter.

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
      |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, triples, updated_context}} = ExpressionBuilder.build(ast, context)

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
          {:ok, {RDF.IRI.t(), [RDF.Triple.t()], Context.t()}} | :skip
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

    # Generate expression IRI using context-based counter
    {expr_iri, updated_context} = expression_iri_for_build(base_iri, context, opts)

    # Build expression triples
    triples = build_expression_triples(ast, expr_iri, updated_context)

    {:ok, {expr_iri, triples, updated_context}}
  end

  # Generates an expression IRI for the build/3 flow using context-based counter
  # This replaces the old process dictionary approach with thread-safe context counters
  defp expression_iri_for_build(base_iri, context, opts) do
    {suffix_string, updated_context} =
      cond do
        # Explicit suffix provided (doesn't use counter)
        custom_suffix = Keyword.get(opts, :suffix) ->
          {custom_suffix, context}

        # Explicit counter provided (advanced use)
        counter = Keyword.get(opts, :counter) ->
          {"expr_#{counter}", context}

        # Use context counter for deterministic IRIs (thread-safe)
        true ->
          {counter, new_context} = Context.next_expression_counter(context)
          {"expr_#{counter}", new_context}
      end

    iri_string = "#{base_iri}expr/#{suffix_string}"
    iri = RDF.IRI.new(iri_string)
    {iri, updated_context}
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
  def build_expression_triples(int, expr_iri, _context) when is_integer(int) do
    build_literal(int, expr_iri, Core.IntegerLiteral, Core.integerValue(), RDF.XSD.Integer)
  end

  # Float literals
  def build_expression_triples(float, expr_iri, _context) when is_float(float) do
    build_literal(float, expr_iri, Core.FloatLiteral, Core.floatValue(), RDF.XSD.Double)
  end

  # String literals (binaries)
  def build_expression_triples(str, expr_iri, _context) when is_binary(str) do
    build_literal(str, expr_iri, Core.StringLiteral, Core.stringValue(), RDF.XSD.String)
  end

  # Charlist literals (lists of integers representing UTF-8 codepoints)
  # Must come before generic handlers that might match lists
  def build_expression_triples(list, expr_iri, _context) when is_list(list) do
    if charlist?(list) do
      string_value = List.to_string(list)
      build_literal(string_value, expr_iri, Core.CharlistLiteral, Core.charlistValue(), RDF.XSD.String)
    else
      # Not a charlist, treat as generic list or unknown expression
      build_generic_expression(expr_iri)
    end
  end

  # Binary literals (<<>>)
  # Matches binary construction patterns like <<65>> or <<x::8>>
  # Note: Literal binaries like <<"hello">> compile to plain binaries and are caught by is_binary/1
  def build_expression_triples({:<<>>, _meta, segments}, expr_iri, _context) do
    if binary_literal?(segments) do
      # All segments are literal integers - we can construct the binary
      binary_value = construct_binary_from_literals(segments)
      # RDF.XSD.Base64Binary handles base64 encoding internally
      build_literal(binary_value, expr_iri, Core.BinaryLiteral, Core.binaryValue(), RDF.XSD.Base64Binary)
    else
      # Binary contains variables or complex type specs
      # For now, treat as generic expression
      # Full pattern support deferred to pattern phase
      build_generic_expression(expr_iri)
    end
  end

  # Atom literals (including true, false, nil)
  def build_expression_triples(atom, expr_iri, _context) when is_atom(atom) do
    build_atom_literal(atom, expr_iri)
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
  defp build_comparison(op, left, right, expr_iri, context) do
    build_binary_operator(op, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  # Logical operators (and, or, &&, ||)
  defp build_logical(op, left, right, expr_iri, context) do
    build_binary_operator(op, left, right, expr_iri, context, Core.LogicalOperator)
  end

  # Arithmetic operators (+, -, *, /, div, rem)
  defp build_arithmetic(op, left, right, expr_iri, context) do
    build_binary_operator(op, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  # Unary operators (not, !)
  defp build_unary(op, arg, expr_iri, context) do
    build_unary_operator(op, arg, expr_iri, context, Core.LogicalOperator)
  end

  # Pipe operator (|>)
  defp build_pipe(left, right, expr_iri, context) do
    # Pipe operator is binary but with special semantics
    # For now, treat as binary operator
    build_binary_operator(:|>, left, right, expr_iri, context, Core.PipeOperator)
  end

  # String concatenation (<>)
  defp build_string_concat(left, right, expr_iri, context) do
    build_binary_operator(:<>, left, right, expr_iri, context, Core.StringConcatOperator)
  end

  # List operators (++, --)
  defp build_list_op(op, left, right, expr_iri, context) do
    build_binary_operator(op, left, right, expr_iri, context, Core.ListOperator)
  end

  # Match operator (=)
  defp build_match(left, right, expr_iri, context) do
    build_binary_operator(:=, left, right, expr_iri, context, Core.MatchOperator)
  end

  # ===========================================================================
  # Core Expression Builders
  # ===========================================================================

  # Builds a binary operator with left and right operands
  defp build_binary_operator(op, left_ast, right_ast, expr_iri, context, type_class) do
    # Generate relative IRIs for child expressions
    left_iri = fresh_iri(expr_iri, "left")
    right_iri = fresh_iri(expr_iri, "right")

    # Recursively build operand triples
    left_triples = build_expression_triples(left_ast, left_iri, context)
    right_triples = build_expression_triples(right_ast, right_iri, context)

    # Build operator triples
    operator_triples = [
      Helpers.type_triple(expr_iri, type_class),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), to_string(op), RDF.XSD.String),
      Helpers.object_property(expr_iri, Core.hasLeftOperand(), left_iri),
      Helpers.object_property(expr_iri, Core.hasRightOperand(), right_iri)
    ]

    # Combine all triples
    operator_triples ++ left_triples ++ right_triples
  end

  # Builds a unary operator with a single operand
  defp build_unary_operator(op, operand_ast, expr_iri, context, type_class) do
    # Generate relative IRI for child expression
    operand_iri = fresh_iri(expr_iri, "operand")

    # Recursively build operand triples
    operand_triples = build_expression_triples(operand_ast, operand_iri, context)

    # Build operator triples
    operator_triples = [
      Helpers.type_triple(expr_iri, type_class),
      Helpers.datatype_property(expr_iri, Core.operatorSymbol(), to_string(op), RDF.XSD.String),
      Helpers.object_property(expr_iri, Core.hasOperand(), operand_iri)
    ]

    # Combine all triples
    operator_triples ++ operand_triples
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

  # ===========================================================================
  # Literal Builders
  # ===========================================================================

  # Builds a typed literal (integer, float, string)
  defp build_literal(value, expr_iri, literal_type, value_property, xsd_type) do
    [
      Helpers.type_triple(expr_iri, literal_type),
      Helpers.datatype_property(expr_iri, value_property, value, xsd_type)
    ]
  end

  # Builds an atom literal (including :true, :false, :nil)
  # Uses specific types for booleans and nil: BooleanLiteral and NilLiteral
  defp build_atom_literal(atom_value, expr_iri) do
    type_class =
      case atom_value do
        true -> Core.BooleanLiteral
        false -> Core.BooleanLiteral
        nil -> Core.NilLiteral
        _ -> Core.AtomLiteral
      end

    [
      Helpers.type_triple(expr_iri, type_class),
      Helpers.datatype_property(expr_iri, Core.atomValue(), atom_to_string(atom_value), RDF.XSD.String)
    ]
  end

  # Converts atom to string representation
  # Handles special atoms (true, false, nil) and custom atoms
  defp atom_to_string(true), do: "true"
  defp atom_to_string(false), do: "false"
  defp atom_to_string(nil), do: "nil"
  defp atom_to_string(atom) when is_atom(atom), do: ":" <> Atom.to_string(atom)

  # Check if a list represents a charlist (all elements are valid UTF-8 codepoints)
  # A charlist is a list of integers where each integer is a valid Unicode codepoint (0x0 to 0x10FFFF)
  defp charlist?(list) when is_list(list) do
    Enum.all?(list, fn
      x when is_integer(x) -> x >= 0 and x <= 0x10FFFF
      _ -> false
    end)
  end

  # Check if binary segments are all literal integers (no variables, no type specs)
  # This allows us to construct a binary value from literals like <<65, 66, 67>>
  defp binary_literal?(segments) when is_list(segments) do
    Enum.all?(segments, fn
      x when is_integer(x) -> x >= 0 and x <= 255
      _ -> false
    end)
  end

  # Construct a binary from a list of literal integer segments
  # Each integer should be a byte value (0-255)
  defp construct_binary_from_literals(segments) when is_list(segments) do
    # Use :erlang.iolist_to_binary or manual construction
    # Since we know all segments are integers, we can use <<>> syntax
    Enum.reduce(segments, <<>>, fn byte, acc ->
      acc <> <<byte>>
    end)
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
