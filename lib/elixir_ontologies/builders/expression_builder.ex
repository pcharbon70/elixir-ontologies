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

  ## Public API vs Internal Functions

  This module provides two layers of functions for expression building:

  ### `build/3` - Public API

  Use `build/3` for top-level expression building from external code:
  - Handles mode checking (full vs light mode)
  - Manages IRI counter in the context
  - Returns `{:ok, {expr_iri, triples, updated_context}}` or `:skip`
  - Thread the returned context to subsequent `build/3` calls

  ### `build_expression_triples/3` - Internal Dispatch

  Internal function used by operator builders for recursive expression building:
  - Directly builds triples given an expression IRI
  - Does NOT check mode (assumes caller already validated)
  - Does NOT manage context counter
  - Returns a list of RDF triples
  - Used when the expr_iri is already known (e.g., child expressions)

  ### When to Use Each

  - **Use `build/3`** when building expressions from external code (e.g., processing AST)
  - **Use `build_expression_triples/3`** when implementing operator builders that need to recursively build child expressions

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

  @doc """
  Builds RDF triples for an expression given its IRI.

  This is the internal dispatch function that pattern matches on AST nodes
  and generates the appropriate RDF triples. Unlike `build/3`, this function:

  - Does NOT check mode (assumes caller validated)
  - Does NOT manage context counter
  - Returns a list of triples directly (not wrapped in {:ok, ...})
  - Requires an explicit expr_iri parameter

  ## Parameters

  - `ast` - The Elixir AST node (3-tuple format or literal)
  - `expr_iri` - The IRI to use for this expression
  - `context` - The builder context (for configuration, not counter management)

  ## Returns

  A list of RDF triples representing the expression.

  ## When to Use

  Use this function when implementing operator builders that need to
  recursively build child expressions. For top-level expression building,
  use `build/3` instead.
  """
  @spec build_expression_triples(Macro.t(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  def build_expression_triples(ast, expr_iri, context)

  # Comparison operators
  def build_expression_triples({:==, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:==, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  def build_expression_triples({:!=, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:!=, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  def build_expression_triples({:===, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:===, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  def build_expression_triples({:!==, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:!==, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  def build_expression_triples({:<, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:<, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  def build_expression_triples({:>, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:>, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  def build_expression_triples({:<=, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:<=, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  def build_expression_triples({:>=, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:>=, left, right, expr_iri, context, Core.ComparisonOperator)
  end

  # Logical operators
  def build_expression_triples({:and, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:and, left, right, expr_iri, context, Core.LogicalOperator)
  end

  def build_expression_triples({:or, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:or, left, right, expr_iri, context, Core.LogicalOperator)
  end

  def build_expression_triples({:&&, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:&&, left, right, expr_iri, context, Core.LogicalOperator)
  end

  def build_expression_triples({:||, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:||, left, right, expr_iri, context, Core.LogicalOperator)
  end

  # Unary operators (not, !, +, -)
  def build_expression_triples({:not, _, [arg]}, expr_iri, context) do
    build_unary(:not, arg, expr_iri, context)
  end

  def build_expression_triples({:!, _, [arg]}, expr_iri, context) do
    build_unary(:!, arg, expr_iri, context)
  end

  # Unary arithmetic operators (must come before binary to match single-argument case)
  def build_expression_triples({:-, _, [operand]}, expr_iri, context) do
    build_unary_arithmetic(:-, operand, expr_iri, context)
  end

  def build_expression_triples({:+, _, [operand]}, expr_iri, context) do
    build_unary_arithmetic(:+, operand, expr_iri, context)
  end

  # Arithmetic operators
  def build_expression_triples({:+, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:+, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  def build_expression_triples({:-, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:-, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  def build_expression_triples({:*, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:*, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  def build_expression_triples({:/, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:/, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  def build_expression_triples({:div, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:div, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  def build_expression_triples({:rem, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:rem, left, right, expr_iri, context, Core.ArithmeticOperator)
  end

  # Pipe operator
  def build_expression_triples({:|>, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:|>, left, right, expr_iri, context, Core.PipeOperator)
  end

  # String concatenation
  def build_expression_triples({:<>, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:<>, left, right, expr_iri, context, Core.StringConcatOperator)
  end

  # List operators
  def build_expression_triples({:++, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:++, left, right, expr_iri, context, Core.ListOperator)
  end

  def build_expression_triples({:--, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:--, left, right, expr_iri, context, Core.ListOperator)
  end

  # Match operator
  def build_expression_triples({:=, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:=, left, right, expr_iri, context, Core.MatchOperator)
  end

  # Capture operator (&)
  # Matches: &1, &2, &3 (argument capture)
  # Matches: &Mod.fun/arity, &Mod.fun (function reference)
  def build_expression_triples({:&, _, [arg]}, expr_iri, _context) when is_integer(arg) do
    build_capture_index(arg, expr_iri)
  end

  def build_expression_triples({:&, _, [{:/, _, [function_ref, arity]}]}, expr_iri, context) do
    build_capture_function_ref(function_ref, arity, expr_iri, context)
  end

  def build_expression_triples({:&, _, [function_ref]}, expr_iri, context) do
    build_capture_function_ref(function_ref, nil, expr_iri, context)
  end

  # In operator
  def build_expression_triples({:in, _, [left, right]}, expr_iri, context) do
    build_binary_operator(:in, left, right, expr_iri, context, Core.InOperator)
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

  # List literals and charlist literals (lists of integers representing UTF-8 codepoints)
  # Must come before generic handlers that might match lists
  def build_expression_triples(list, expr_iri, context) when is_list(list) do
    cond do
      # Check for keyword list: all elements are 2-tuples with atom first elements
      # Must come before cons pattern check (cons lists are also lists)
      Keyword.keyword?(list) and list != [] ->
        build_keyword_list(list, expr_iri, context)

      # Check for cons pattern: [{:|, _, [head, tail]}]
      cons_pattern?(list) ->
        build_cons_list(list, expr_iri, context)

      # Check for regular list (non-charlist):
      # - Contains non-integer elements
      # - Contains integers outside Unicode range
      # - Is a nested list structure
      not charlist?(list) ->
        build_list_literal(list, expr_iri, context)

      # Otherwise, it's a charlist (all elements are valid Unicode codepoints)
      true ->
        string_value = List.to_string(list)
        build_literal(string_value, expr_iri, Core.CharlistLiteral, Core.charlistValue(), RDF.XSD.String)
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

  # Tuple literals - must come before local call handler
  # General tuple form: {:{}, meta, elements} - covers empty tuple and 3+ tuples
  def build_expression_triples({:{}, _meta, elements}, expr_iri, context) do
    build_tuple_literal(elements, expr_iri, context)
  end

  # 2-tuple: {left, right} - special form, not a 3-tuple AST node
  def build_expression_triples({left, right}, expr_iri, context) do
    build_tuple_literal([left, right], expr_iri, context)
  end

  # Struct literals - must come before map handler (both start with :%)
  # Struct pattern: {:%, meta, [module_ast, map_ast]}
  def build_expression_triples({:%, _meta, [module_ast, map_ast]}, expr_iri, context) do
    build_struct_literal(module_ast, map_ast, expr_iri, context)
  end

  # Map literals
  # Map pattern: {:%{}, meta, pairs}
  def build_expression_triples({:%{}, _meta, pairs}, expr_iri, context) do
    build_map_literal(pairs, expr_iri, context)
  end

  # Range literals: 1..10, 1..10//2, a..b, etc.
  # Simple range pattern: {:.., meta, [first, last]}
  # Step range pattern: {:"..//", meta, [first, last, step]}
  def build_expression_triples({:.., _meta, [first, last]}, expr_iri, context) do
    build_range_literal(first, last, expr_iri, context)
  end

  def build_expression_triples({:"..//", _meta, [first, last, step]}, expr_iri, context) do
    build_range_literal(first, last, step, expr_iri, context)
  end

  # Local call: function(args) - must come before variable pattern
  # Note: This handler also checks for sigil atoms (sigil_c, sigil_r, sigil_s, sigil_w)
  # and dispatches them to the sigil literal handler
  def build_expression_triples({function, meta, args}, expr_iri, context)
      when is_atom(function) and is_list(meta) and is_list(args) do
    # Check if this is a sigil literal (pattern: {:sigil_CHAR, meta, [content_ast, modifiers_ast]})
    # Sigils have exactly 2 elements in args list: [content_ast, modifiers_ast]
    # We check if the atom name starts with "sigil_"
    if is_sigil_atom?(function) and length(args) == 2 do
      build_sigil_literal(function, Enum.at(args, 0), Enum.at(args, 1), expr_iri, context)
    else
      build_local_call(function, args, expr_iri, context)
    end
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

  # Unary operators (not, !)
  defp build_unary(op, arg, expr_iri, context) do
    build_unary_operator(op, arg, expr_iri, context, Core.LogicalOperator)
  end

  # Unary arithmetic operators (+, -)
  defp build_unary_arithmetic(op, operand, expr_iri, context) do
    build_unary_operator(op, operand, expr_iri, context, Core.ArithmeticOperator)
  end

  # ===========================================================================
  # Core Expression Builders
  # ===========================================================================

  # Builds a binary operator with left and right operands
  defp build_binary_operator(op, left_ast, right_ast, expr_iri, context, type_class) do
    # Generate relative IRIs for child expressions
    left_iri = fresh_iri(expr_iri, "left")
    right_iri = fresh_iri(expr_iri, "right")

    # Recursively build operand triples using build_expression_triples/3 directly.
    # We use build_expression_triples/3 instead of build/3 here because:
    # 1. The expr_iri for each operand is already known (left_iri, right_iri)
    # 2. Mode checking was already done by the parent build/3 call
    # 3. We don't need additional IRI counter management (child IRIs are relative)
    # 4. We need direct access to the triples list for concatenation
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

    # Recursively build operand triples using build_expression_triples/3 directly.
    # We use build_expression_triples/3 instead of build/3 here because:
    # 1. The expr_iri for the operand is already known (operand_iri)
    # 2. Mode checking was already done by the parent build/3 call
    # 3. We don't need additional IRI counter management (child IRIs are relative)
    # 4. We need direct access to the triples list for concatenation
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
    # Use IO.iodata_to_binary for O(n) performance instead of O(n²) string concatenation
    IO.iodata_to_binary(segments)
  end

  # Check if a list is a cons pattern: [{:|, _, [head, tail]}]
  defp cons_pattern?([{:|, _, [_head, _tail]}]), do: true
  defp cons_pattern?(_), do: false

  # Build child expressions from a collection, threading context through
  # Returns {flat_triples_list, final_context}
  # A mapper function can be provided to transform items before building
  defp build_child_expressions(items, context, mapper \\ fn item -> item end) do
    {triples_list, final_ctx} =
      Enum.map_reduce(items, context, fn item, ctx ->
        {:ok, {_child_iri, triples, new_ctx}} = build(mapper.(item), ctx, [])
        {triples, new_ctx}
      end)

    {List.flatten(triples_list), final_ctx}
  end

  # Build a list literal from a list of elements
  defp build_list_literal(list, expr_iri, context) do
    # Create the ListLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.ListLiteral)

    # Build child expressions for each element
    {child_triples, _final_context} = build_child_expressions(list, context)

    # Include type triple and all child triples
    [type_triple | child_triples]
  end

  # Build a cons pattern [head | tail]
  defp build_cons_list([{:|, _, [head, tail]}], expr_iri, context) do
    # Create the ListLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.ListLiteral)

    # Build head expression
    {:ok, {_head_iri, head_triples, context_after_head}} = build(head, context, [])

    # Build tail expression
    {:ok, {_tail_iri, tail_triples, _context_after_tail}} = build(tail, context_after_head, [])

    # Note: hasHead and hasTail properties would need to be added to ontology
    # For now, we just include the type triple and child expressions
    [type_triple | head_triples] ++ tail_triples
  end

  # Build a keyword list from a list of {atom, value} tuples
  defp build_keyword_list(pairs, expr_iri, context) do
    # Create the KeywordListLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.KeywordListLiteral)

    # Build expressions for each value (keys are atom literals)
    {value_triples, _final_context} =
      build_child_expressions(pairs, context, fn {_key, value} -> value end)

    # Include type triple and all value triples
    [type_triple | value_triples]
  end

  # Build a tuple literal from a list of elements
  defp build_tuple_literal(elements, expr_iri, context) do
    # Create the TupleLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.TupleLiteral)

    # Build child expressions for each element
    {child_triples, _final_context} = build_child_expressions(elements, context)

    # Include type triple and all child triples
    [type_triple | child_triples]
  end

  # Build a struct literal from module AST and map AST
  defp build_struct_literal(module_ast, map_ast, expr_iri, context) do
    # Extract module name from {:__aliases__, _, parts}
    module_name =
      case module_ast do
        {:__aliases__, _meta, parts} -> Enum.join(parts, ".")
        _ -> inspect(module_ast)
      end

    # Create the StructLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.StructLiteral)

    # Create refersToModule property
    # refersToModule expects an IRI, so we create a module IRI
    module_iri_string = "#{context.base_iri}module/#{module_name}"
    module_iri = RDF.IRI.new(module_iri_string)
    refers_to_triple = {expr_iri, Core.refersToModule(), module_iri}

    # Extract map entries from the map part of the struct
    # The map_ast is {:%{}, meta, pairs}
    map_triples =
      case map_ast do
        {:%{}, _meta, pairs} ->
          build_map_entries(pairs, expr_iri, context)

        _ ->
          []
      end

    [type_triple, refers_to_triple | map_triples]
  end

  # Build a map literal from a list of key-value pairs
  defp build_map_literal(pairs, expr_iri, context) do
    # Create the MapLiteral type triple
    type_triple = Helpers.type_triple(expr_iri, Core.MapLiteral)

    # Build map entries
    entry_triples = build_map_entries(pairs, expr_iri, context)

    [type_triple | entry_triples]
  end

  # Build map entries from a list of key-value pairs
  # Pairs can be:
  # - Keyword tuples: {:a, 1} (for atom keys using a: 1 syntax)
  # - 2-tuples: {"a", 1} (for other keys using "a" => 1 syntax)
  defp build_map_entries(pairs, _expr_iri, _context) when pairs == [], do: []

  defp build_map_entries(pairs, _expr_iri, context) do
    # Build expressions for each value (keys are literals, not expressions)
    # Filter out map update syntax {:|, ..., [...]} for now
    regular_pairs = Enum.filter(pairs, fn
      {:|, _, _} -> false
      _ -> true
    end)

    {value_triples, _final_context} =
      build_child_expressions(regular_pairs, context, fn {_key, value} -> value end)

    value_triples
  end

  # Generic expression for unknown AST nodes
  defp build_generic_expression(expr_iri) do
    [Helpers.type_triple(expr_iri, Core.Expression)]
  end

  # ===========================================================================
  # Sigil Literal Builders
  # ===========================================================================

  @doc false
  defp build_sigil_literal(sigil_atom, content_ast, modifiers_ast, expr_iri, _context) do
    # Extract sigil character from atom name (e.g., :sigil_w -> "w")
    sigil_char = extract_sigil_char(sigil_atom)

    # Extract content from binary construction
    sigil_content = extract_sigil_content(content_ast)

    # Convert modifiers from charlist to string
    sigil_modifiers = extract_sigil_modifiers(modifiers_ast)

    # Build the RDF triples
    type_triple = Helpers.type_triple(expr_iri, Core.SigilLiteral)
    char_triple = {expr_iri, Core.sigilChar, RDF.XSD.String.new(sigil_char)}
    content_triple = {expr_iri, Core.sigilContent, RDF.XSD.String.new(sigil_content)}

    # Only add modifiers triple if non-empty
    modifiers_triples =
      if sigil_modifiers != "" do
        [{expr_iri, Core.sigilModifiers, RDF.XSD.String.new(sigil_modifiers)}]
      else
        []
      end

    [type_triple, char_triple, content_triple | modifiers_triples]
  end

  @doc false
  defp extract_sigil_char(sigil_atom) do
    sigil_name = Atom.to_string(sigil_atom)
    # Remove "sigil_" prefix to get the character
    String.replace_prefix(sigil_name, "sigil_", "")
  end

  @doc false
  defp extract_sigil_content({:<<>>, _meta, [content]}) when is_binary(content) do
    content
  end

  # Fallback for unexpected content format
  defp extract_sigil_content(_other) do
    ""
  end

  @doc false
  defp extract_sigil_modifiers([]), do: ""

  defp extract_sigil_modifiers(modifiers) when is_list(modifiers) do
    # Convert charlist to string
    List.to_string(modifiers)
  end

  # Fallback for unexpected modifier format
  defp extract_sigil_modifiers(_other), do: ""

  @doc false
  defp is_sigil_atom?(atom) when is_atom(atom) do
    atom_name = Atom.to_string(atom)
    String.starts_with?(atom_name, "sigil_")
  end

  # ===========================================================================
  # Range Literal Builders
  # ===========================================================================

  @doc false
  defp build_range_literal(first, last, expr_iri, context) do
    # Build the first and last as child expressions
    {:ok, {first_iri, first_triples, _}} = build(first, context, [])
    {:ok, {last_iri, last_triples, _}} = build(last, context, [])

    # Create the RangeLiteral type and property triples
    type_triple = Helpers.type_triple(expr_iri, Core.RangeLiteral)
    start_triple = {expr_iri, Core.rangeStart(), first_iri}
    end_triple = {expr_iri, Core.rangeEnd(), last_iri}

    [type_triple, start_triple, end_triple | first_triples ++ last_triples]
  end

  defp build_range_literal(first, last, step, expr_iri, context) do
    # Build the first, last, and step as child expressions
    {:ok, {first_iri, first_triples, _}} = build(first, context, [])
    {:ok, {last_iri, last_triples, _}} = build(last, context, [])
    {:ok, {step_iri, step_triples, _}} = build(step, context, [])

    # Create the RangeLiteral type and property triples
    type_triple = Helpers.type_triple(expr_iri, Core.RangeLiteral)
    start_triple = {expr_iri, Core.rangeStart(), first_iri}
    end_triple = {expr_iri, Core.rangeEnd(), last_iri}
    step_triple = {expr_iri, Core.rangeStep(), step_iri}

    [type_triple, start_triple, end_triple, step_triple | first_triples ++ last_triples ++ step_triples]
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

  # ===========================================================================
  # Capture Operator Helpers
  # ===========================================================================

  @doc false
  # Build capture operator for argument index (&1, &2, etc.)
  # Uses dedicated captureIndex property from the ontology
  defp build_capture_index(index, expr_iri) do
    [
      {expr_iri, RDF.type(), Core.CaptureOperator},
      {expr_iri, Core.operatorSymbol(), RDF.Literal.new("&")},
      {expr_iri, Core.captureIndex(), RDF.Literal.new(index)}
    ]
  end

  @doc false
  # Build capture operator for function reference (&Mod.fun/arity)
  # Uses dedicated captureModuleName, captureFunctionName, and captureArity properties
  defp build_capture_function_ref(function_ref, arity, expr_iri, _context) do
    # Extract module and function name from function_ref AST
    {module, function} = extract_function_ref_parts(function_ref)

    base_triples = [
      {expr_iri, RDF.type(), Core.CaptureOperator},
      {expr_iri, Core.operatorSymbol(), RDF.Literal.new("&")},
      {expr_iri, Core.captureModuleName(), RDF.Literal.new(module)},
      {expr_iri, Core.captureFunctionName(), RDF.Literal.new(function)}
    ]

    # Add arity if specified
    if arity do
      base_triples ++ [{expr_iri, Core.captureArity(), RDF.Literal.new(arity)}]
    else
      base_triples
    end
  end

  @doc false
  # Extract module and function name from a function reference AST
  # Handles: {{:., _, [module, function]}, _, args}
  defp extract_function_ref_parts({{:., _, [module_ast, function_ast]}, _meta, _args}) do
    module = extract_module_name(module_ast)
    function = extract_function_name(function_ast)
    {module, function}
  end

  defp extract_function_ref_parts({:., _, [module_ast, function_ast]}) do
    module = extract_module_name(module_ast)
    function = extract_function_name(function_ast)
    {module, function}
  end

  # Fallback for other patterns
  defp extract_function_ref_parts(other), do: {inspect(other), "unknown"}

  @doc false
  # Extract module name from AST
  defp extract_module_name({:__aliases__, _, parts}), do: Enum.join(parts, ".")
  defp extract_module_name({:@, _, [{:__MODULE__, _, []}]}), do: "__MODULE__"
  defp extract_module_name({:__MODULE__, [], []}), do: "__MODULE__"
  defp extract_module_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp extract_module_name(other), do: inspect(other)

  @doc false
  # Extract function name from AST
  defp extract_function_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp extract_function_name(other), do: inspect(other)

  # ===========================================================================
  # Pattern Detection and Dispatch
  # ===========================================================================

  @doc """
  Detects the type of pattern from an Elixir AST node.

  ## Parameters

  - `ast` - The Elixir AST node to analyze

  ## Returns

  An atom representing the pattern type:
  - `:literal_pattern` - Literal values (integers, floats, strings, atoms)
  - `:variable_pattern` - Variable binding patterns
  - `:wildcard_pattern` - Underscore wildcard patterns
  - `:pin_pattern` - Pin operator patterns (^var)
  - `:tuple_pattern` - Tuple destructuring patterns
  - `:list_pattern` - List destructuring patterns
  - `:map_pattern` - Map pattern matching
  - `:struct_pattern` - Struct pattern matching
  - `:binary_pattern` - Binary/bitstring patterns
  - `:as_pattern` - Pattern aliasing (pattern = var)
  - `:unknown` - Unrecognized pattern

  ## Examples

      iex> ExpressionBuilder.detect_pattern_type({:_})
      :wildcard_pattern

      iex> ExpressionBuilder.detect_pattern_type({:x, [], Elixir})
      :variable_pattern

      iex> ExpressionBuilder.detect_pattern_type(42)
      :literal_pattern
  """
  @spec detect_pattern_type(Macro.t()) :: atom()
  def detect_pattern_type({:_}), do: :wildcard_pattern
  def detect_pattern_type({:^, _, [{_var, _, _}]}), do: :pin_pattern
  def detect_pattern_type({:=, _, [_, _]}), do: :as_pattern
  def detect_pattern_type({:{}, _, _}), do: :tuple_pattern
  def detect_pattern_type({:%, _, [{:{}, _, _}, {:%{}, _, _}]}), do: :struct_pattern
  def detect_pattern_type({:%, _, [{:__aliases__, _, _}, {:%{}, _, _}]}), do: :struct_pattern
  def detect_pattern_type({:%{}, _, _}), do: :map_pattern
  def detect_pattern_type({:<<>>, _, _}), do: :binary_pattern
  def detect_pattern_type(list) when is_list(list), do: :list_pattern
  # Variable pattern must come after all other tuple-based patterns
  # because {name, _, ctx} also matches {:{}, [], []}
  def detect_pattern_type({name, _, _ctx}) when is_atom(name) and name != :{} and name != :_, do: :variable_pattern
  # 2-tuple is a special case: {left, right} without the {:{}, _, _} wrapper
  # Must come after variable pattern to avoid conflicts
  def detect_pattern_type({left, _right}) when not is_tuple(left), do: :tuple_pattern
  def detect_pattern_type(value) when is_integer(value), do: :literal_pattern
  def detect_pattern_type(value) when is_float(value), do: :literal_pattern
  def detect_pattern_type(value) when is_binary(value), do: :literal_pattern
  def detect_pattern_type(value) when is_atom(value), do: :literal_pattern
  def detect_pattern_type(nil), do: :literal_pattern
  def detect_pattern_type(_), do: :unknown

  @doc """
  Builds RDF triples for a pattern expression.

  Uses `detect_pattern_type/1` to identify the pattern type and dispatches
  to the appropriate builder function.

  ## Parameters

  - `ast` - The Elixir AST pattern node
  - `expr_iri` - The IRI for this pattern expression
  - `context` - The builder context

  ## Returns

  A list of RDF triples representing the pattern.

  ## Examples

      iex> ast = {:x, [], Elixir}
      iex> context = ElixirOntologies.Builders.Context.new(base_iri: "https://example.org/test#", config: %{include_expressions: true}, file_path: "lib/my_app/users.ex") |> ElixirOntologies.Builders.Context.with_expression_counter()
      iex> {:ok, {iri, _triples, ctx}} = ExpressionBuilder.build(ast, context, [])
      iex> pattern_triples = ExpressionBuilder.build_pattern(ast, iri, ctx)
      iex> Enum.any?(pattern_triples, fn {s, p, o} -> p == RDF.type() and o == Core.VariablePattern end)
      true
  """
  @spec build_pattern(Macro.t(), RDF.IRI.t(), Context.t()) :: [RDF.Triple.t()]
  def build_pattern(ast, expr_iri, context) do
    case detect_pattern_type(ast) do
      :literal_pattern -> build_literal_pattern(ast, expr_iri, context)
      :variable_pattern -> build_variable_pattern(ast, expr_iri, context)
      :wildcard_pattern -> build_wildcard_pattern(ast, expr_iri, context)
      :pin_pattern -> build_pin_pattern(ast, expr_iri, context)
      :tuple_pattern -> build_tuple_pattern(ast, expr_iri, context)
      :list_pattern -> build_list_pattern(ast, expr_iri, context)
      :map_pattern -> build_map_pattern(ast, expr_iri, context)
      :struct_pattern -> build_struct_pattern(ast, expr_iri, context)
      :binary_pattern -> build_binary_pattern(ast, expr_iri, context)
      :as_pattern -> build_as_pattern(ast, expr_iri, context)
      :unknown -> build_generic_expression(expr_iri)
    end
  end

  # Placeholder builder functions for individual pattern types
  # Full implementations will be added in later sections (24.2-24.6)

  @doc false
  defp build_literal_pattern(ast, expr_iri, _context) do
    {value_property, xsd_type, value} = literal_value_info(ast)

    [
      Helpers.type_triple(expr_iri, Core.LiteralPattern),
      Helpers.datatype_property(expr_iri, value_property, value, xsd_type)
    ]
  end

  @doc """
  Returns the value property, XSD type, and actual value for literal patterns.

  For atoms, uses atom_to_string/1 to get the source representation.
  For other literals, uses the raw value.

  ## Returns

  `{property_iri, xsd_type, value}` triple
  """
  defp literal_value_info(int) when is_integer(int), do: {Core.integerValue(), RDF.XSD.Integer, int}
  defp literal_value_info(float) when is_float(float), do: {Core.floatValue(), RDF.XSD.Double, float}
  defp literal_value_info(str) when is_binary(str), do: {Core.stringValue(), RDF.XSD.String, str}
  defp literal_value_info(atom) when is_atom(atom), do: {Core.atomValue(), RDF.XSD.String, atom_to_string(atom)}

  @doc """
  Builds RDF triples for a variable pattern.

  Variable patterns bind matched values to variable names.
  This is distinct from Variable expressions (expression context).

  ## Notes

  - Variables with leading underscores (_name) are still variable patterns, not wildcards
  - The single underscore (_) is a wildcard pattern, handled elsewhere
  - Pin patterns (^x) are handled elsewhere
  - For future scope analysis, this should link to a Core.Variable instance
  """
  defp build_variable_pattern({name, _meta, _ctx}, expr_iri, _context) do
    [
      Helpers.type_triple(expr_iri, Core.VariablePattern),
      Helpers.datatype_property(expr_iri, Core.name(), Atom.to_string(name), RDF.XSD.String)
    ]
  end

  @doc """
  Builds a wildcard pattern from AST.

  The wildcard pattern (`_`) matches any value and discards it.
  It is represented in AST as `{:_}` (a 2-tuple with atom `:_`).

  ## Examples

      iex> ast = {:_}
      ...> expr_iri = RDF.iri("ex://pattern/1")
      ...> build_wildcard_pattern(ast, expr_iri, %{})
      ...> |> Enum.at(0)
      {RDF.iri("ex://pattern/1"), RDF.type(), Core.WildcardPattern()}

  """
  defp build_wildcard_pattern(_ast, expr_iri, _context) do
    [Helpers.type_triple(expr_iri, Core.WildcardPattern)]
  end

  @doc """
  Builds a pin pattern from AST.

  The pin pattern (`^x`) matches against the existing value of a variable.
  It is represented in AST as `{:^, _, [{:x, _, _}]}`.

  The pin operator ensures pattern matching uses the already-bound value
  of the variable rather than rebinding it.

  ## Examples

      iex> ast = {:^, [], [{:x, [], Elixir}]}
      ...> expr_iri = RDF.iri("ex://pattern/1")
      ...> build_pin_pattern(ast, expr_iri, %{})
      ...> |> Enum.at(0)
      {RDF.iri("ex://pattern/1"), RDF.type(), Core.PinPattern()}

  """
  defp build_pin_pattern(ast, expr_iri, _context) do
    {:^, _, [{var, _, _}]} = ast
    [
      Helpers.type_triple(expr_iri, Core.PinPattern),
      Helpers.datatype_property(expr_iri, Core.name(), Atom.to_string(var), RDF.XSD.String)
    ]
  end

  @doc false
  defp build_tuple_pattern(_ast, expr_iri, _context) do
    [Helpers.type_triple(expr_iri, Core.TuplePattern)]
  end

  @doc false
  defp build_list_pattern(_ast, expr_iri, _context) do
    [Helpers.type_triple(expr_iri, Core.ListPattern)]
  end

  @doc false
  defp build_map_pattern(_ast, expr_iri, _context) do
    [Helpers.type_triple(expr_iri, Core.MapPattern)]
  end

  @doc false
  defp build_struct_pattern(_ast, expr_iri, _context) do
    [Helpers.type_triple(expr_iri, Core.StructPattern)]
  end

  @doc false
  defp build_binary_pattern(_ast, expr_iri, _context) do
    [Helpers.type_triple(expr_iri, Core.BinaryPattern)]
  end

  @doc false
  defp build_as_pattern(_ast, expr_iri, _context) do
    [Helpers.type_triple(expr_iri, Core.AsPattern)]
  end
end
