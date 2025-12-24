defmodule ElixirOntologies.Extractors.Closure do
  @moduledoc """
  Detects free variables in anonymous functions and capture expressions.

  Free variables are variables that appear in a function body but are not
  bound by the function's parameters - they must be captured from the
  enclosing scope, making the function a closure.

  ## Free Variable Detection

  A **free variable** in a function is a variable that:
  1. Is referenced in the function body
  2. Is NOT bound by the function's parameters
  3. Is NOT a special form, module name, or function call name

  ## Examples

      iex> ast = quote do: fn x -> x + y end
      iex> {:ok, anon} = ElixirOntologies.Extractors.AnonymousFunction.extract(ast)
      iex> {:ok, analysis} = ElixirOntologies.Extractors.Closure.analyze_closure(anon)
      iex> analysis.has_captures
      true
      iex> hd(analysis.free_variables).name
      :y

      iex> # Function with no free variables (not a closure)
      iex> ast = quote do: fn x -> x + 1 end
      iex> {:ok, anon} = ElixirOntologies.Extractors.AnonymousFunction.extract(ast)
      iex> {:ok, analysis} = ElixirOntologies.Extractors.Closure.analyze_closure(anon)
      iex> analysis.has_captures
      false
  """

  alias ElixirOntologies.Extractors.AnonymousFunction
  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # FreeVariable Struct
  # ===========================================================================

  defmodule FreeVariable do
    @moduledoc """
    Represents a free variable captured from an enclosing scope.

    ## Fields

    - `:name` - The variable name (atom)
    - `:reference_count` - Number of times this variable is referenced
    - `:reference_locations` - Source locations where this variable is used
    - `:captured_at` - Location of the fn/capture that captures this variable
    - `:metadata` - Additional information
    """

    @type t :: %__MODULE__{
            name: atom(),
            reference_count: pos_integer(),
            reference_locations: [map()],
            captured_at: map() | nil,
            metadata: map()
          }

    @enforce_keys [:name, :reference_count]
    defstruct [
      :name,
      :reference_count,
      reference_locations: [],
      captured_at: nil,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # FreeVariableAnalysis Struct
  # ===========================================================================

  defmodule FreeVariableAnalysis do
    @moduledoc """
    Complete analysis of free variables in an anonymous function or closure.

    ## Fields

    - `:free_variables` - List of FreeVariable structs for captured variables
    - `:bound_variables` - Variables bound by function parameters
    - `:all_references` - All variable names referenced in the body
    - `:has_captures` - Whether any free variables exist (is this a closure?)
    - `:total_capture_count` - Total number of free variable references
    - `:metadata` - Additional information
    """

    alias ElixirOntologies.Extractors.Closure.FreeVariable

    @type t :: %__MODULE__{
            free_variables: [FreeVariable.t()],
            bound_variables: [atom()],
            all_references: [atom()],
            has_captures: boolean(),
            total_capture_count: non_neg_integer(),
            metadata: map()
          }

    @enforce_keys [:free_variables, :bound_variables]
    defstruct [
      :free_variables,
      :bound_variables,
      all_references: [],
      has_captures: false,
      total_capture_count: 0,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # High-Level Analysis
  # ===========================================================================

  @doc """
  Analyzes an anonymous function for captured (free) variables.

  Takes an `%AnonymousFunction{}` struct and returns a `%FreeVariableAnalysis{}`
  with information about which variables are captured from the enclosing scope.

  ## Examples

      iex> ast = quote do: fn x -> x + y end
      iex> {:ok, anon} = ElixirOntologies.Extractors.AnonymousFunction.extract(ast)
      iex> {:ok, analysis} = ElixirOntologies.Extractors.Closure.analyze_closure(anon)
      iex> analysis.has_captures
      true
      iex> Enum.map(analysis.free_variables, & &1.name)
      [:y]

      iex> ast = quote do: fn x, y -> x + y end
      iex> {:ok, anon} = ElixirOntologies.Extractors.AnonymousFunction.extract(ast)
      iex> {:ok, analysis} = ElixirOntologies.Extractors.Closure.analyze_closure(anon)
      iex> analysis.has_captures
      false
  """
  @spec analyze_closure(AnonymousFunction.t()) :: {:ok, FreeVariableAnalysis.t()}
  def analyze_closure(%AnonymousFunction{clauses: clauses, location: location}) do
    # Collect all bound variables from all clauses
    bound_vars =
      clauses
      |> Enum.flat_map(fn clause -> clause.bound_variables end)
      |> Enum.uniq()

    # Collect all body ASTs and analyze them
    bodies = Enum.map(clauses, fn clause -> clause.body end)

    # Find all variable references in bodies
    all_refs = find_variable_references_in_list(bodies)

    # Detect free variables
    detect_free_variables(all_refs, bound_vars, location)
  end

  # ===========================================================================
  # Free Variable Detection
  # ===========================================================================

  @doc """
  Detects free variables given variable references and bound variable names.

  Takes a list of `{name, meta}` tuples (variable references with metadata)
  and a list of bound variable names. Returns analysis of which variables
  are free (not in the bound set).

  ## Examples

      iex> refs = [{:x, [line: 1]}, {:y, [line: 2]}, {:x, [line: 3]}]
      iex> bound = [:x]
      iex> {:ok, analysis} = ElixirOntologies.Extractors.Closure.detect_free_variables(refs, bound)
      iex> analysis.has_captures
      true
      iex> hd(analysis.free_variables).name
      :y

      iex> refs = [{:x, [line: 1]}, {:y, [line: 2]}]
      iex> bound = [:x, :y]
      iex> {:ok, analysis} = ElixirOntologies.Extractors.Closure.detect_free_variables(refs, bound)
      iex> analysis.has_captures
      false
  """
  @spec detect_free_variables([{atom(), keyword()}], [atom()], map() | nil) ::
          {:ok, FreeVariableAnalysis.t()}
  def detect_free_variables(references, bound_vars, captured_at \\ nil) do
    bound_set = MapSet.new(bound_vars)

    # Group references by variable name
    refs_by_name = Enum.group_by(references, fn {name, _meta} -> name end)

    # Find free variables (not in bound set)
    free_vars =
      refs_by_name
      |> Enum.filter(fn {name, _refs} -> not MapSet.member?(bound_set, name) end)
      |> Enum.map(fn {name, refs} ->
        locations =
          refs
          |> Enum.map(fn {_name, meta} -> extract_ref_location(meta) end)
          |> Enum.reject(&is_nil/1)

        %FreeVariable{
          name: name,
          reference_count: length(refs),
          reference_locations: locations,
          captured_at: captured_at,
          metadata: %{}
        }
      end)
      |> Enum.sort_by(& &1.name)

    all_ref_names =
      references
      |> Enum.map(fn {name, _meta} -> name end)
      |> Enum.uniq()
      |> Enum.sort()

    total_captures = Enum.sum(Enum.map(free_vars, & &1.reference_count))

    {:ok,
     %FreeVariableAnalysis{
       free_variables: free_vars,
       bound_variables: Enum.sort(bound_vars),
       all_references: all_ref_names,
       has_captures: free_vars != [],
       total_capture_count: total_captures,
       metadata: %{}
     }}
  end

  # ===========================================================================
  # Variable Reference Finding
  # ===========================================================================

  @doc """
  Finds all variable references in an AST.

  Traverses the AST and collects all variable references (excluding special forms,
  function names in calls, module names, etc.).

  Returns a list of `{name, metadata}` tuples.

  ## Examples

      iex> ast = quote do: x + y
      iex> refs = ElixirOntologies.Extractors.Closure.find_variable_references(ast)
      iex> Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      [:x, :y]

      iex> ast = quote do: String.upcase(x)
      iex> refs = ElixirOntologies.Extractors.Closure.find_variable_references(ast)
      iex> Enum.map(refs, fn {name, _} -> name end)
      [:x]
  """
  @spec find_variable_references(Macro.t()) :: [{atom(), keyword()}]
  def find_variable_references(ast) do
    {_, refs} = do_find_refs(ast, [], MapSet.new())
    Enum.reverse(refs)
  end

  @doc """
  Finds variable references in a list of AST nodes.

  Useful for analyzing multiple clause bodies together.

  ## Examples

      iex> asts = [quote(do: x + 1), quote(do: y * 2)]
      iex> refs = ElixirOntologies.Extractors.Closure.find_variable_references_in_list(asts)
      iex> Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      [:x, :y]
  """
  @spec find_variable_references_in_list([Macro.t()]) :: [{atom(), keyword()}]
  def find_variable_references_in_list(asts) do
    asts
    |> Enum.flat_map(&find_variable_references/1)
  end

  # ===========================================================================
  # Private Helpers - Reference Finding
  # ===========================================================================

  # Main traversal function with scope tracking for locally bound variables
  defp do_find_refs(ast, acc, local_bindings)

  # Variable reference: {name, meta, context} where context is atom
  defp do_find_refs({name, meta, context}, acc, local_bindings)
       when is_atom(name) and is_atom(context) do
    cond do
      # Skip underscore/wildcard
      name == :_ ->
        {nil, acc}

      # Skip special forms and operators
      Helpers.special_form?(name) ->
        {nil, acc}

      # Skip locally bound variables (from case/with/for bindings)
      MapSet.member?(local_bindings, name) ->
        {nil, acc}

      # Skip if it looks like a module attribute reference
      String.starts_with?(Atom.to_string(name), "@") ->
        {nil, acc}

      # This is a variable reference
      true ->
        {nil, [{name, meta} | acc]}
    end
  end

  # Remote function call: Module.func(args) - skip module and function name
  defp do_find_refs({{:., _, [_module, _func]}, _, args}, acc, local_bindings) do
    # Only process the arguments, not the module or function
    Enum.reduce(args, acc, fn arg, acc2 ->
      {_, new_acc} = do_find_refs(arg, acc2, local_bindings)
      new_acc
    end)
    |> then(&{nil, &1})
  end

  # Anonymous function - creates new scope, parameters are bound
  defp do_find_refs({:fn, _, clauses}, acc, local_bindings) do
    # Process each clause, adding its parameters to local bindings
    new_acc =
      Enum.reduce(clauses, acc, fn clause, acc2 ->
        process_fn_clause(clause, acc2, local_bindings)
      end)

    {nil, new_acc}
  end

  # Case expression - patterns in each clause bind new variables
  defp do_find_refs({:case, _, [expr, [do: clauses]]}, acc, local_bindings) do
    # Process the expression being matched
    {_, acc2} = do_find_refs(expr, acc, local_bindings)

    # Process each clause with pattern bindings
    new_acc =
      Enum.reduce(clauses, acc2, fn clause, acc3 ->
        process_case_clause(clause, acc3, local_bindings)
      end)

    {nil, new_acc}
  end

  # With expression - each <- binds new variables visible in subsequent matches
  defp do_find_refs({:with, _, args}, acc, local_bindings) do
    process_with_expr(args, acc, local_bindings)
  end

  # For comprehension - generators bind variables
  defp do_find_refs({:for, _, args}, acc, local_bindings) do
    process_for_expr(args, acc, local_bindings)
  end

  # Cond expression
  defp do_find_refs({:cond, _, [[do: clauses]]}, acc, local_bindings) do
    new_acc =
      Enum.reduce(clauses, acc, fn {:->, _, [[condition], body]}, acc2 ->
        {_, acc3} = do_find_refs(condition, acc2, local_bindings)
        {_, acc4} = do_find_refs(body, acc3, local_bindings)
        acc4
      end)

    {nil, new_acc}
  end

  # Receive expression
  defp do_find_refs({:receive, _, [opts]}, acc, local_bindings) do
    new_acc = process_receive_opts(opts, acc, local_bindings)
    {nil, new_acc}
  end

  # Try expression
  defp do_find_refs({:try, _, [opts]}, acc, local_bindings) do
    new_acc = process_try_opts(opts, acc, local_bindings)
    {nil, new_acc}
  end

  # Match operator = (binding on left side)
  defp do_find_refs({:=, _, [pattern, expr]}, acc, local_bindings) do
    # Process the right side first (it can reference existing vars)
    {_, acc2} = do_find_refs(expr, acc, local_bindings)

    # Extract bindings from pattern and add to local scope for left side
    pattern_bindings = extract_pattern_bindings(pattern)
    new_local = MapSet.union(local_bindings, MapSet.new(pattern_bindings))

    # We don't need to process pattern - it's binding, not referencing
    # But the pattern might contain pin operators ^x which reference vars
    {_, acc3} = find_pin_references(pattern, acc2, local_bindings)

    # Return with updated bindings (though bindings don't propagate out of this context)
    {nil, acc3, new_local}
  catch
    # If pattern unpacking failed, just process normally
    _ ->
      {_, acc2} = do_find_refs(expr, acc, local_bindings)
      {nil, acc2}
  end

  # Generic tuple handling (including function calls)
  defp do_find_refs({op, _, args}, acc, local_bindings) when is_list(args) do
    # Skip function name in local calls
    args_to_process =
      if is_atom(op) and not Helpers.special_form?(op) and not operator?(op) do
        # This looks like a function call - just process args
        args
      else
        args
      end

    new_acc =
      Enum.reduce(args_to_process, acc, fn arg, acc2 ->
        {_, new_acc} = do_find_refs(arg, acc2, local_bindings)
        new_acc
      end)

    {nil, new_acc}
  end

  # List
  defp do_find_refs(list, acc, local_bindings) when is_list(list) do
    new_acc =
      Enum.reduce(list, acc, fn elem, acc2 ->
        {_, new_acc} = do_find_refs(elem, acc2, local_bindings)
        new_acc
      end)

    {nil, new_acc}
  end

  # Two-element tuple (common in AST)
  defp do_find_refs({left, right}, acc, local_bindings) do
    {_, acc2} = do_find_refs(left, acc, local_bindings)
    {_, acc3} = do_find_refs(right, acc2, local_bindings)
    {nil, acc3}
  end

  # Literals and other nodes - no variables here
  defp do_find_refs(_other, acc, _local_bindings), do: {nil, acc}

  # ===========================================================================
  # Private Helpers - Control Flow Processing
  # ===========================================================================

  defp process_fn_clause({:->, _, [params_with_guard, body]}, acc, local_bindings) do
    # Extract parameters (may have guard)
    {params, guard} = extract_params_and_guard(params_with_guard)

    # Get bindings from parameters
    param_bindings = Enum.flat_map(params, &extract_pattern_bindings/1)
    new_local = MapSet.union(local_bindings, MapSet.new(param_bindings))

    # Process guard if present (can reference params)
    acc2 =
      if guard do
        {_, new_acc} = do_find_refs(guard, acc, new_local)
        new_acc
      else
        acc
      end

    # Process body with parameter bindings
    {_, acc3} = do_find_refs(body, acc2, new_local)
    acc3
  end

  defp process_case_clause({:->, _, [patterns, body]}, acc, local_bindings) do
    # patterns is a list (typically with one element, possibly with guard)
    {pattern, guard} = extract_pattern_and_guard(patterns)

    pattern_bindings = extract_pattern_bindings(pattern)
    new_local = MapSet.union(local_bindings, MapSet.new(pattern_bindings))

    # Check for pin operators in pattern
    {_, acc2} = find_pin_references(pattern, acc, local_bindings)

    # Process guard if present
    acc3 =
      if guard do
        {_, new_acc} = do_find_refs(guard, acc2, new_local)
        new_acc
      else
        acc2
      end

    # Process body
    {_, acc4} = do_find_refs(body, acc3, new_local)
    acc4
  end

  defp process_with_expr(args, acc, local_bindings) do
    # with can have generators (<-), regular matches (=), and options ([do: ...])
    {generators, opts} = split_with_args(args)

    # Process generators, accumulating bindings
    {acc2, final_bindings} =
      Enum.reduce(generators, {acc, local_bindings}, fn
        {:<-, _, [pattern, expr]}, {acc_inner, bindings} ->
          # Process expression first (can use previous bindings)
          {_, acc3} = do_find_refs(expr, acc_inner, bindings)
          # Add pattern bindings for next iteration
          new_bindings = MapSet.union(bindings, MapSet.new(extract_pattern_bindings(pattern)))
          {acc3, new_bindings}

        {:=, _, [pattern, expr]}, {acc_inner, bindings} ->
          # Match expression
          {_, acc3} = do_find_refs(expr, acc_inner, bindings)
          new_bindings = MapSet.union(bindings, MapSet.new(extract_pattern_bindings(pattern)))
          {acc3, new_bindings}

        other, {acc_inner, bindings} ->
          {_, acc3} = do_find_refs(other, acc_inner, bindings)
          {acc3, bindings}
      end)

    # Process do/else blocks with accumulated bindings
    process_with_opts(opts, acc2, final_bindings)
  end

  defp split_with_args(args) do
    Enum.split_while(args, fn
      [do: _] -> false
      [do: _, else: _] -> false
      _ -> true
    end)
  end

  defp process_with_opts([], acc, _bindings), do: {nil, acc}

  defp process_with_opts([[do: body] | rest], acc, bindings) do
    {_, acc2} = do_find_refs(body, acc, bindings)
    process_with_opts(rest, acc2, bindings)
  end

  defp process_with_opts([[do: body, else: else_clauses] | rest], acc, bindings) do
    {_, acc2} = do_find_refs(body, acc, bindings)

    acc3 =
      Enum.reduce(else_clauses, acc2, fn clause, acc_inner ->
        process_case_clause(clause, acc_inner, bindings)
      end)

    process_with_opts(rest, acc3, bindings)
  end

  defp process_with_opts([_ | rest], acc, bindings) do
    process_with_opts(rest, acc, bindings)
  end

  defp process_for_expr(args, acc, local_bindings) do
    # Separate generators from options
    {generators, opts} = Enum.split_while(args, fn
      [_ | _] -> false
      _ -> true
    end)

    # Process generators, accumulating bindings
    {acc2, gen_bindings} =
      Enum.reduce(generators, {acc, local_bindings}, fn
        {:<-, _, [pattern, enumerable]}, {acc_inner, bindings} ->
          {_, acc3} = do_find_refs(enumerable, acc_inner, bindings)
          new_bindings = MapSet.union(bindings, MapSet.new(extract_pattern_bindings(pattern)))
          {acc3, new_bindings}

        filter, {acc_inner, bindings} ->
          {_, acc3} = do_find_refs(filter, acc_inner, bindings)
          {acc3, bindings}
      end)

    # Process do block with generator bindings
    case opts do
      [[do: body] | _] ->
        {_, acc3} = do_find_refs(body, acc2, gen_bindings)
        {nil, acc3}

      [[do: body, into: into] | _] ->
        {_, acc3} = do_find_refs(body, acc2, gen_bindings)
        {_, acc4} = do_find_refs(into, acc3, local_bindings)
        {nil, acc4}

      _ ->
        {nil, acc2}
    end
  end

  defp process_receive_opts(opts, acc, local_bindings) do
    Enum.reduce(opts, acc, fn
      {:do, clauses}, acc2 ->
        Enum.reduce(clauses, acc2, fn clause, acc3 ->
          process_case_clause(clause, acc3, local_bindings)
        end)

      {:after, [{:->, _, [[timeout], body]}]}, acc2 ->
        {_, acc3} = do_find_refs(timeout, acc2, local_bindings)
        {_, acc4} = do_find_refs(body, acc3, local_bindings)
        acc4

      _, acc2 ->
        acc2
    end)
  end

  defp process_try_opts(opts, acc, local_bindings) do
    Enum.reduce(opts, acc, fn
      {:do, body}, acc2 ->
        {_, new_acc} = do_find_refs(body, acc2, local_bindings)
        new_acc

      {:rescue, clauses}, acc2 ->
        Enum.reduce(clauses, acc2, fn clause, acc3 ->
          process_rescue_clause(clause, acc3, local_bindings)
        end)

      {:catch, clauses}, acc2 ->
        Enum.reduce(clauses, acc2, fn clause, acc3 ->
          process_case_clause(clause, acc3, local_bindings)
        end)

      {:else, clauses}, acc2 ->
        Enum.reduce(clauses, acc2, fn clause, acc3 ->
          process_case_clause(clause, acc3, local_bindings)
        end)

      {:after, body}, acc2 ->
        {_, new_acc} = do_find_refs(body, acc2, local_bindings)
        new_acc

      _, acc2 ->
        acc2
    end)
  end

  defp process_rescue_clause({:->, _, [[pattern], body]}, acc, local_bindings) do
    pattern_bindings = extract_pattern_bindings(pattern)
    new_local = MapSet.union(local_bindings, MapSet.new(pattern_bindings))
    {_, acc2} = do_find_refs(body, acc, new_local)
    acc2
  end

  defp process_rescue_clause(_, acc, _), do: acc

  # ===========================================================================
  # Private Helpers - Pattern Analysis
  # ===========================================================================

  # Extract bindings from a pattern (variables that get bound)
  defp extract_pattern_bindings(pattern) do
    {_, bindings} = extract_bindings_acc(pattern, [])
    Enum.uniq(bindings)
  end

  defp extract_bindings_acc({:_, _, _}, acc), do: {nil, acc}
  defp extract_bindings_acc({:^, _, _}, acc), do: {nil, acc}

  defp extract_bindings_acc({name, _, context}, acc)
       when is_atom(name) and is_atom(context) do
    if valid_variable_name?(name) do
      {nil, [name | acc]}
    else
      {nil, acc}
    end
  end

  defp extract_bindings_acc({:=, _, [left, right]}, acc) do
    {_, acc2} = extract_bindings_acc(left, acc)
    extract_bindings_acc(right, acc2)
  end

  defp extract_bindings_acc({:when, _, [pattern, _guard]}, acc) do
    extract_bindings_acc(pattern, acc)
  end

  defp extract_bindings_acc({:|, _, [head, tail]}, acc) do
    {_, acc2} = extract_bindings_acc(head, acc)
    extract_bindings_acc(tail, acc2)
  end

  defp extract_bindings_acc({:%{}, _, pairs}, acc) do
    Enum.reduce(pairs, acc, fn
      {_key, value}, acc2 ->
        {_, new_acc} = extract_bindings_acc(value, acc2)
        new_acc

      _, acc2 ->
        acc2
    end)
    |> then(&{nil, &1})
  end

  defp extract_bindings_acc({:%, _, [_struct, {:%{}, _, pairs}]}, acc) do
    extract_bindings_acc({:%{}, [], pairs}, acc)
  end

  defp extract_bindings_acc({:{}, _, elements}, acc) do
    Enum.reduce(elements, acc, fn elem, acc2 ->
      {_, new_acc} = extract_bindings_acc(elem, acc2)
      new_acc
    end)
    |> then(&{nil, &1})
  end

  defp extract_bindings_acc({:<<>>, _, segments}, acc) do
    Enum.reduce(segments, acc, fn
      {:"::", _, [pattern, _spec]}, acc2 ->
        {_, new_acc} = extract_bindings_acc(pattern, acc2)
        new_acc

      elem, acc2 ->
        {_, new_acc} = extract_bindings_acc(elem, acc2)
        new_acc
    end)
    |> then(&{nil, &1})
  end

  defp extract_bindings_acc(tuple, acc) when is_tuple(tuple) and tuple_size(tuple) == 2 do
    [left, right] = Tuple.to_list(tuple)
    {_, acc2} = extract_bindings_acc(left, acc)
    extract_bindings_acc(right, acc2)
  end

  defp extract_bindings_acc(list, acc) when is_list(list) do
    Enum.reduce(list, acc, fn elem, acc2 ->
      {_, new_acc} = extract_bindings_acc(elem, acc2)
      new_acc
    end)
    |> then(&{nil, &1})
  end

  defp extract_bindings_acc(_, acc), do: {nil, acc}

  # Find pin operator references (^x references existing variable x)
  defp find_pin_references({:^, _, [{name, meta, context}]}, acc, _local_bindings)
       when is_atom(name) and is_atom(context) do
    {nil, [{name, meta} | acc]}
  end

  defp find_pin_references({_, _, args}, acc, local_bindings) when is_list(args) do
    new_acc =
      Enum.reduce(args, acc, fn arg, acc2 ->
        {_, new_acc} = find_pin_references(arg, acc2, local_bindings)
        new_acc
      end)

    {nil, new_acc}
  end

  defp find_pin_references(list, acc, local_bindings) when is_list(list) do
    new_acc =
      Enum.reduce(list, acc, fn elem, acc2 ->
        {_, new_acc} = find_pin_references(elem, acc2, local_bindings)
        new_acc
      end)

    {nil, new_acc}
  end

  defp find_pin_references(tuple, acc, local_bindings)
       when is_tuple(tuple) and tuple_size(tuple) == 2 do
    [left, right] = Tuple.to_list(tuple)
    {_, acc2} = find_pin_references(left, acc, local_bindings)
    find_pin_references(right, acc2, local_bindings)
  end

  defp find_pin_references(_, acc, _), do: {nil, acc}

  # ===========================================================================
  # Private Helpers - Utilities
  # ===========================================================================

  defp extract_params_and_guard(params) when is_list(params) do
    case params do
      [{:when, _, when_contents}] when is_list(when_contents) ->
        {parameters, [guard_expr]} = Enum.split(when_contents, -1)
        {parameters, guard_expr}

      params ->
        {params, nil}
    end
  end

  defp extract_params_and_guard(_), do: {[], nil}

  defp extract_pattern_and_guard([{:when, _, [pattern | guard_rest]}]) do
    {pattern, List.last(guard_rest)}
  end

  defp extract_pattern_and_guard([pattern]), do: {pattern, nil}
  defp extract_pattern_and_guard(patterns), do: {patterns, nil}

  defp valid_variable_name?(name) when is_atom(name) do
    name_str = Atom.to_string(name)

    not String.starts_with?(name_str, "_") and
      name != :_ and
      not Helpers.special_form?(name) and
      not operator?(name)
  end

  defp operator?(op) when is_atom(op) do
    op in [
      :+,
      :-,
      :*,
      :/,
      :==,
      :!=,
      :===,
      :!==,
      :<,
      :>,
      :<=,
      :>=,
      :and,
      :or,
      :not,
      :in,
      :|>,
      :++,
      :--,
      :<>,
      :..,
      :|,
      :&,
      :@,
      :^,
      :.,
      :"::"
    ]
  end

  defp extract_ref_location(meta) when is_list(meta) do
    line = Keyword.get(meta, :line)
    column = Keyword.get(meta, :column)

    if line do
      %{
        start_line: line,
        start_column: column,
        end_line: nil,
        end_column: nil
      }
    else
      nil
    end
  end

  defp extract_ref_location(_), do: nil
end
