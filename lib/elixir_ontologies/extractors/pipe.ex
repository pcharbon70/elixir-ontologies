defmodule ElixirOntologies.Extractors.Pipe do
  @moduledoc """
  Extracts pipe chain information from Elixir AST.

  This module provides extraction of pipe chains (`|>` operator sequences),
  preserving the chain structure and extracting each step as a function call.

  ## Pipe Chain Structure

  Pipe chains are left-associative, meaning `a |> b() |> c()` becomes:

      {:|>, meta, [
        {:|>, meta, [a, b_call]},  # left is nested pipe
        c_call                      # right is the last step
      ]}

  This extractor flattens the nested structure into an ordered list of steps.

  ## Examples

      iex> ast = {:|>, [], [{:data, [], nil}, {:transform, [], []}]}
      iex> ElixirOntologies.Extractors.Pipe.pipe_chain?(ast)
      true

      iex> ast = {:|>, [], [{:x, [], nil}, {:foo, [], [1, 2]}]}
      iex> {:ok, chain} = ElixirOntologies.Extractors.Pipe.extract_pipe_chain(ast)
      iex> chain.length
      1
      iex> chain.start_value
      {:x, [], nil}

      iex> ast = {:foo, [], []}
      iex> ElixirOntologies.Extractors.Pipe.pipe_chain?(ast)
      false
  """

  alias ElixirOntologies.Extractors.{Call, Helpers}
  alias ElixirOntologies.Extractors.Call.FunctionCall
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # ===========================================================================
  # Struct Definitions
  # ===========================================================================

  defmodule PipeStep do
    @moduledoc """
    Represents a single step in a pipe chain.

    ## Fields

    - `:index` - 0-based position in the chain
    - `:call` - The function call for this step (FunctionCall struct)
    - `:explicit_args` - Arguments provided explicitly (not including piped value)
    - `:location` - Source location if available
    """

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            call: FunctionCall.t(),
            explicit_args: [Macro.t()],
            location: SourceLocation.t() | nil
          }

    @enforce_keys [:index, :call]
    defstruct [:index, :call, explicit_args: [], location: nil]
  end

  defmodule PipeChain do
    @moduledoc """
    Represents a pipe chain extracted from AST.

    ## Fields

    - `:start_value` - The initial value being piped (leftmost expression)
    - `:steps` - List of PipeStep structs in order
    - `:length` - Number of steps in the chain
    - `:location` - Source location of the entire chain
    - `:metadata` - Additional information
    """

    @type t :: %__MODULE__{
            start_value: Macro.t(),
            steps: [ElixirOntologies.Extractors.Pipe.PipeStep.t()],
            length: non_neg_integer(),
            location: SourceLocation.t() | nil,
            metadata: map()
          }

    @enforce_keys [:start_value, :steps, :length]
    defstruct [:start_value, :location, steps: [], length: 0, metadata: %{}]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if the given AST node represents a pipe chain.

  Returns `true` for any pipe operator usage (`|>`).

  ## Examples

      iex> ast = {:|>, [], [{:x, [], nil}, {:foo, [], []}]}
      iex> ElixirOntologies.Extractors.Pipe.pipe_chain?(ast)
      true

      iex> ast = {:|>, [], [{:|>, [], [{:a, [], nil}, {:b, [], []}]}, {:c, [], []}]}
      iex> ElixirOntologies.Extractors.Pipe.pipe_chain?(ast)
      true

      iex> ast = {:foo, [], [{:x, [], nil}]}
      iex> ElixirOntologies.Extractors.Pipe.pipe_chain?(ast)
      false

      iex> ElixirOntologies.Extractors.Pipe.pipe_chain?(:not_a_pipe)
      false
  """
  @spec pipe_chain?(Macro.t()) :: boolean()
  def pipe_chain?({:|>, _meta, [_left, _right]}), do: true
  def pipe_chain?(_), do: false

  # ===========================================================================
  # Single Extraction
  # ===========================================================================

  @doc """
  Extracts a pipe chain from an AST node.

  Returns `{:ok, %PipeChain{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:|>, [], [{:data, [], nil}, {:transform, [], []}]}
      iex> {:ok, chain} = ElixirOntologies.Extractors.Pipe.extract_pipe_chain(ast)
      iex> chain.length
      1
      iex> chain.start_value
      {:data, [], nil}
      iex> hd(chain.steps).call.name
      :transform

      iex> ast = {:|>, [], [
      ...>   {:|>, [], [{:x, [], nil}, {:a, [], []}]},
      ...>   {:b, [], [1]}
      ...> ]}
      iex> {:ok, chain} = ElixirOntologies.Extractors.Pipe.extract_pipe_chain(ast)
      iex> chain.length
      2
      iex> Enum.map(chain.steps, & &1.call.name)
      [:a, :b]

      iex> ast = {:foo, [], []}
      iex> ElixirOntologies.Extractors.Pipe.extract_pipe_chain(ast)
      {:error, {:not_a_pipe_chain, "Not a pipe chain: {:foo, [], []}"}}
  """
  @spec extract_pipe_chain(Macro.t(), keyword()) :: {:ok, PipeChain.t()} | {:error, term()}
  def extract_pipe_chain(ast, opts \\ [])

  def extract_pipe_chain({:|>, _meta, [_left, _right]} = ast, opts) do
    {start_value, step_asts} = flatten_pipe_chain(ast)
    steps = build_steps(step_asts, opts)
    location = Helpers.extract_location_if(ast, opts)

    {:ok,
     %PipeChain{
       start_value: start_value,
       steps: steps,
       length: length(steps),
       location: location,
       metadata: %{}
     }}
  end

  def extract_pipe_chain(ast, _opts) do
    {:error, {:not_a_pipe_chain, Helpers.format_error("Not a pipe chain", ast)}}
  end

  @doc """
  Extracts a pipe chain, raising on error.

  ## Examples

      iex> ast = {:|>, [], [{:x, [], nil}, {:foo, [], []}]}
      iex> chain = ElixirOntologies.Extractors.Pipe.extract_pipe_chain!(ast)
      iex> chain.length
      1
  """
  @spec extract_pipe_chain!(Macro.t(), keyword()) :: PipeChain.t()
  def extract_pipe_chain!(ast, opts \\ []) do
    case extract_pipe_chain(ast, opts) do
      {:ok, chain} -> chain
      {:error, reason} -> raise ArgumentError, "Failed to extract pipe chain: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Bulk Extraction
  # ===========================================================================

  @doc """
  Extracts all pipe chains from an AST.

  Walks the entire AST tree and extracts all pipe chains found.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)
  - `:max_depth` - Maximum recursion depth (default: 100)

  ## Examples

      iex> body = [
      ...>   {:|>, [], [{:x, [], nil}, {:foo, [], []}]},
      ...>   {:bar, [], []},
      ...>   {:|>, [], [{:y, [], nil}, {:baz, [], []}]}
      ...> ]
      iex> chains = ElixirOntologies.Extractors.Pipe.extract_pipe_chains(body)
      iex> length(chains)
      2

      iex> ast = {:if, [], [true, [do: {:|>, [], [{:x, [], nil}, {:foo, [], []}]}]]}
      iex> chains = ElixirOntologies.Extractors.Pipe.extract_pipe_chains(ast)
      iex> length(chains)
      1
  """
  @spec extract_pipe_chains(Macro.t(), keyword()) :: [PipeChain.t()]
  def extract_pipe_chains(ast, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, Helpers.max_recursion_depth())
    extract_chains_recursive(ast, opts, 0, max_depth)
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  # Flatten a nested pipe chain into (start_value, [step_asts])
  defp flatten_pipe_chain({:|>, _meta, [left, right]}) do
    case left do
      {:|>, _, _} = nested_pipe ->
        {start_value, steps} = flatten_pipe_chain(nested_pipe)
        {start_value, steps ++ [right]}

      start_value ->
        {start_value, [right]}
    end
  end

  # Build PipeStep structs from step ASTs
  defp build_steps(step_asts, opts) do
    step_asts
    |> Enum.with_index()
    |> Enum.map(fn {step_ast, index} ->
      build_step(step_ast, index, opts)
    end)
  end

  defp build_step(step_ast, index, opts) do
    location = Helpers.extract_location_if(step_ast, opts)
    {call, explicit_args} = extract_step_call(step_ast, opts)

    %PipeStep{
      index: index,
      call: call,
      explicit_args: explicit_args,
      location: location
    }
  end

  # Extract the function call from a step, accounting for implicit first arg
  defp extract_step_call(step_ast, opts) do
    case step_ast do
      # Remote call: Module.func(args...)
      {{:., _dot_meta, [_receiver, _func_name]}, _meta, args} = node ->
        case Call.extract_remote(node, opts) do
          {:ok, call} ->
            # The call has the explicit args, piped value is implicit
            {call, args}

          {:error, _} ->
            # Fallback for unusual patterns
            build_fallback_call(step_ast, args, opts)
        end

      # Local call: func(args...)
      {name, _meta, args} = node when is_atom(name) and is_list(args) ->
        case Call.extract(node, opts) do
          {:ok, call} ->
            {call, args}

          {:error, _} ->
            build_fallback_call(step_ast, args, opts)
        end

      # Local call with no parens: func (unusual in pipes but possible)
      {name, _meta, nil} = node when is_atom(name) ->
        # Treat as zero-arity call
        call = %FunctionCall{
          type: :local,
          name: name,
          arity: 0,
          arguments: [],
          location: Helpers.extract_location_if(node, opts),
          metadata: %{no_parens: true}
        }

        {call, []}

      # Other expressions (anonymous function call, etc.)
      other ->
        build_fallback_call(other, [], opts)
    end
  end

  # Build a fallback call for unusual step patterns
  defp build_fallback_call(step_ast, args, opts) do
    call = %FunctionCall{
      type: :dynamic,
      name: :pipe_step,
      arity: length(args),
      arguments: args,
      location: Helpers.extract_location_if(step_ast, opts),
      metadata: %{raw_ast: step_ast}
    }

    {call, args}
  end

  # ===========================================================================
  # Recursive Extraction
  # ===========================================================================

  defp extract_chains_recursive(_ast, _opts, depth, max_depth) when depth > max_depth do
    []
  end

  defp extract_chains_recursive(statements, opts, depth, max_depth) when is_list(statements) do
    Enum.flat_map(statements, &extract_chains_recursive(&1, opts, depth, max_depth))
  end

  defp extract_chains_recursive({:__block__, _meta, statements}, opts, depth, max_depth) do
    extract_chains_recursive(statements, opts, depth, max_depth)
  end

  # Handle pipe chain - extract it but don't recurse into it (it's already captured)
  defp extract_chains_recursive({:|>, _meta, [_left, _right]} = ast, opts, _depth, _max_depth) do
    case extract_pipe_chain(ast, opts) do
      {:ok, chain} -> [chain]
      {:error, _} -> []
    end
  end

  # Handle three-element tuples (AST nodes)
  defp extract_chains_recursive({_name, _meta, args}, opts, depth, max_depth)
       when is_list(args) do
    extract_chains_recursive(args, opts, depth + 1, max_depth)
  end

  # Handle two-element tuples (keyword pairs, etc.)
  defp extract_chains_recursive({left, right}, opts, depth, max_depth) do
    extract_chains_recursive(left, opts, depth + 1, max_depth) ++
      extract_chains_recursive(right, opts, depth + 1, max_depth)
  end

  # Handle three-element tuples that aren't AST nodes
  defp extract_chains_recursive({a, b, c}, opts, depth, max_depth)
       when not is_atom(a) or not is_list(b) do
    extract_chains_recursive(a, opts, depth + 1, max_depth) ++
      extract_chains_recursive(b, opts, depth + 1, max_depth) ++
      extract_chains_recursive(c, opts, depth + 1, max_depth)
  end

  defp extract_chains_recursive(_other, _opts, _depth, _max_depth) do
    []
  end
end
