defmodule ElixirOntologies.Extractors.Call do
  @moduledoc """
  Extracts function call information from Elixir AST.

  This module provides extraction of function calls including:
  - **Local calls** - calls to functions in the same module
  - **Remote calls** - calls via `Module.function(args)` syntax

  ## Architecture Note

  This extractor is designed for composable, on-demand call graph analysis. It is
  intentionally **not** automatically invoked by the main Pipeline module. This
  separation allows:

  - Lightweight module extraction when call details aren't needed
  - Targeted call graph analysis when building dependency graphs
  - Flexibility to use extractors individually or in combination

  ## Call Types

  ### Local Calls

  Local calls are calls to functions in the same module:

      {:foo, [line: 1], []}           # foo()
      {:bar, [line: 1], [1, 2]}       # bar(1, 2)

  ### Remote Calls

  Remote calls use the `Module.function(args)` syntax:

      # String.upcase("hello")
      {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}

      # :ets.new(:table, [])
      {{:., [], [:ets, :new]}, [], [:table, []]}

  ## Examples

      iex> ast = {:foo, [line: 1], []}
      iex> ElixirOntologies.Extractors.Call.local_call?(ast)
      true

      iex> ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      iex> ElixirOntologies.Extractors.Call.remote_call?(ast)
      true

      iex> ast = {:foo, [line: 1], [1, 2]}
      iex> {:ok, call} = ElixirOntologies.Extractors.Call.extract(ast)
      iex> call.name
      :foo
      iex> call.arity
      2
  """

  alias ElixirOntologies.Extractors.Helpers
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # ===========================================================================
  # Struct Definition
  # ===========================================================================

  defmodule FunctionCall do
    @moduledoc """
    Represents a function call extracted from AST.

    ## Fields

    - `:type` - Call type (:local, :remote, or :dynamic)
    - `:name` - Function name as atom
    - `:arity` - Number of arguments
    - `:module` - Target module for remote calls (nil for local calls)
    - `:arguments` - List of argument AST nodes (raw AST)
    - `:location` - Source location if available
    - `:metadata` - Additional information (e.g., alias info, containing function)
    """

    @typedoc """
    The type of function call.

    - `:local` - Call to function in same module
    - `:remote` - Call via Module.function syntax
    - `:dynamic` - Call via apply or anonymous function
    """
    @type call_type :: :local | :remote | :dynamic

    @type t :: %__MODULE__{
            type: call_type(),
            name: atom(),
            arity: non_neg_integer(),
            module: [atom()] | atom() | nil,
            arguments: [Macro.t()],
            location: SourceLocation.t() | nil,
            metadata: map()
          }

    @enforce_keys [:type, :name, :arity]
    defstruct [:type, :name, :arity, :module, arguments: [], location: nil, metadata: %{}]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if the given AST node represents a local function call.

  Returns `true` for calls to local functions (functions in the same module).
  Returns `false` for variable references, special forms, operators, and
  remote calls.

  ## Key Distinction

  The third element of the AST tuple determines if it's a call or variable:
  - List (even empty) → function call
  - nil or atom → variable reference

  ## Examples

      iex> ElixirOntologies.Extractors.Call.local_call?({:foo, [], []})
      true

      iex> ElixirOntologies.Extractors.Call.local_call?({:bar, [line: 1], [1, 2]})
      true

      iex> ElixirOntologies.Extractors.Call.local_call?({:x, [], nil})
      false

      iex> ElixirOntologies.Extractors.Call.local_call?({:def, [], [[do: :ok]]})
      false

      iex> ElixirOntologies.Extractors.Call.local_call?({:if, [], [true, [do: 1]]})
      false

      iex> ElixirOntologies.Extractors.Call.local_call?(:not_a_call)
      false
  """
  @spec local_call?(Macro.t()) :: boolean()
  def local_call?({name, _meta, args})
      when is_atom(name) and is_list(args) do
    not Helpers.special_form?(name) and not operator?(name)
  end

  def local_call?(_), do: false

  # Operators that might appear with list args but aren't local calls
  @operators [:+, :-, :*, :/, :==, :!=, :===, :!==, :<, :>, :<=, :>=, :&&, :||, :!, :and, :or, :not,
              :++, :--, :<>, :in, :@, :when, :"not in"]

  defp operator?(name), do: name in @operators

  @doc """
  Checks if the given AST node represents a remote function call.

  Returns `true` for calls using the `Module.function(args)` syntax.
  This includes calls to Elixir modules, Erlang modules, and `__MODULE__`.

  ## Examples

      iex> ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      iex> ElixirOntologies.Extractors.Call.remote_call?(ast)
      true

      iex> ast = {{:., [], [:ets, :new]}, [], [:table, []]}
      iex> ElixirOntologies.Extractors.Call.remote_call?(ast)
      true

      iex> ast = {{:., [], [{:__MODULE__, [], Elixir}, :helper]}, [], []}
      iex> ElixirOntologies.Extractors.Call.remote_call?(ast)
      true

      iex> ast = {:foo, [], []}
      iex> ElixirOntologies.Extractors.Call.remote_call?(ast)
      false

      iex> ElixirOntologies.Extractors.Call.remote_call?(:not_a_call)
      false
  """
  @spec remote_call?(Macro.t()) :: boolean()
  # Elixir module call: Module.function(args)
  def remote_call?({{:., _dot_meta, [{:__aliases__, _alias_meta, _parts}, func_name]}, _meta, args})
      when is_atom(func_name) and is_list(args) do
    true
  end

  # Erlang module call: :module.function(args)
  def remote_call?({{:., _dot_meta, [module, func_name]}, _meta, args})
      when is_atom(module) and is_atom(func_name) and is_list(args) do
    true
  end

  # __MODULE__.function(args)
  def remote_call?({{:., _dot_meta, [{:__MODULE__, _mod_meta, _ctx}, func_name]}, _meta, args})
      when is_atom(func_name) and is_list(args) do
    true
  end

  # Variable receiver (dynamic): var.function(args)
  def remote_call?({{:., _dot_meta, [{var_name, _var_meta, ctx}, func_name]}, _meta, args})
      when is_atom(var_name) and is_atom(ctx) and is_atom(func_name) and is_list(args) do
    true
  end

  def remote_call?(_), do: false

  # ===========================================================================
  # Single Extraction
  # ===========================================================================

  @doc """
  Extracts a local function call from an AST node.

  Returns `{:ok, %FunctionCall{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:foo, [line: 5], []}
      iex> {:ok, call} = ElixirOntologies.Extractors.Call.extract(ast)
      iex> call.name
      :foo
      iex> call.arity
      0
      iex> call.type
      :local

      iex> ast = {:bar, [], [1, {:x, [], nil}]}
      iex> {:ok, call} = ElixirOntologies.Extractors.Call.extract(ast)
      iex> call.name
      :bar
      iex> call.arity
      2
      iex> length(call.arguments)
      2

      iex> ElixirOntologies.Extractors.Call.extract({:x, [], nil})
      {:error, {:not_a_local_call, "Not a local function call: {:x, [], nil}"}}
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, FunctionCall.t()} | {:error, term()}
  def extract(ast, opts \\ [])

  def extract({name, _meta, args} = node, opts)
      when is_atom(name) and is_list(args) do
    if local_call?(node) do
      build_local_call(name, args, node, opts)
    else
      {:error, {:not_a_local_call, Helpers.format_error("Not a local function call", node)}}
    end
  end

  def extract(node, _opts) do
    {:error, {:not_a_local_call, Helpers.format_error("Not a local function call", node)}}
  end

  @doc """
  Extracts a local function call, raising on error.

  ## Examples

      iex> ast = {:foo, [], [1, 2]}
      iex> call = ElixirOntologies.Extractors.Call.extract!(ast)
      iex> call.name
      :foo
      iex> call.arity
      2
  """
  @spec extract!(Macro.t(), keyword()) :: FunctionCall.t()
  def extract!(ast, opts \\ []) do
    case extract(ast, opts) do
      {:ok, call} -> call
      {:error, reason} -> raise ArgumentError, "Failed to extract call: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Remote Call Extraction
  # ===========================================================================

  @doc """
  Extracts a remote function call from an AST node.

  Returns `{:ok, %FunctionCall{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      iex> {:ok, call} = ElixirOntologies.Extractors.Call.extract_remote(ast)
      iex> call.name
      :upcase
      iex> call.module
      [:String]
      iex> call.type
      :remote

      iex> ast = {{:., [], [:ets, :new]}, [], [:table, []]}
      iex> {:ok, call} = ElixirOntologies.Extractors.Call.extract_remote(ast)
      iex> call.name
      :new
      iex> call.module
      :ets

      iex> ElixirOntologies.Extractors.Call.extract_remote({:foo, [], []})
      {:error, {:not_a_remote_call, "Not a remote function call: {:foo, [], []}"}}
  """
  @spec extract_remote(Macro.t(), keyword()) :: {:ok, FunctionCall.t()} | {:error, term()}
  def extract_remote(ast, opts \\ [])

  # Elixir module call: Module.function(args)
  def extract_remote(
        {{:., _dot_meta, [{:__aliases__, _alias_meta, parts}, func_name]}, _meta, args} = node,
        opts
      )
      when is_atom(func_name) and is_list(args) do
    build_remote_call(parts, func_name, args, node, opts, %{})
  end

  # Erlang module call: :module.function(args)
  def extract_remote({{:., _dot_meta, [module, func_name]}, _meta, args} = node, opts)
      when is_atom(module) and is_atom(func_name) and is_list(args) do
    build_remote_call(module, func_name, args, node, opts, %{erlang_module: true})
  end

  # __MODULE__.function(args)
  def extract_remote(
        {{:., _dot_meta, [{:__MODULE__, _mod_meta, _ctx}, func_name]}, _meta, args} = node,
        opts
      )
      when is_atom(func_name) and is_list(args) do
    build_remote_call(:__MODULE__, func_name, args, node, opts, %{current_module: true})
  end

  # Variable receiver (dynamic): var.function(args)
  def extract_remote(
        {{:., _dot_meta, [{var_name, _var_meta, ctx}, func_name]}, _meta, args} = node,
        opts
      )
      when is_atom(var_name) and is_atom(ctx) and is_atom(func_name) and is_list(args) do
    build_remote_call(var_name, func_name, args, node, opts, %{
      dynamic_receiver: true,
      receiver_variable: var_name
    })
  end

  def extract_remote(node, _opts) do
    {:error, {:not_a_remote_call, Helpers.format_error("Not a remote function call", node)}}
  end

  @doc """
  Extracts a remote function call, raising on error.

  ## Examples

      iex> ast = {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], [[1, 2], {:fn, [], []}]}
      iex> call = ElixirOntologies.Extractors.Call.extract_remote!(ast)
      iex> call.name
      :map
      iex> call.module
      [:Enum]
  """
  @spec extract_remote!(Macro.t(), keyword()) :: FunctionCall.t()
  def extract_remote!(ast, opts \\ []) do
    case extract_remote(ast, opts) do
      {:ok, call} -> call
      {:error, reason} -> raise ArgumentError, "Failed to extract remote call: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Bulk Extraction
  # ===========================================================================

  @doc """
  Extracts all local function calls from an AST.

  Walks the entire AST tree and extracts all local function calls found.
  This includes calls in function bodies, nested blocks, and within arguments
  of other calls.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)
  - `:max_depth` - Maximum recursion depth (default: 100)

  ## Examples

      iex> body = [
      ...>   {:foo, [], []},
      ...>   {:bar, [], [1, 2]},
      ...>   {:def, [], [{:test, [], nil}, [do: {:baz, [], []}]]}
      ...> ]
      iex> calls = ElixirOntologies.Extractors.Call.extract_local_calls(body)
      iex> Enum.map(calls, & &1.name)
      [:foo, :bar, :baz]

      iex> ast = {:if, [], [true, [do: {:foo, [], []}]]}
      iex> calls = ElixirOntologies.Extractors.Call.extract_local_calls(ast)
      iex> Enum.map(calls, & &1.name)
      [:foo]
  """
  @spec extract_local_calls(Macro.t(), keyword()) :: [FunctionCall.t()]
  def extract_local_calls(ast, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, Helpers.max_recursion_depth())
    extract_calls_recursive(ast, opts, 0, max_depth, :local)
  end

  @doc """
  Extracts all remote function calls from an AST.

  Walks the entire AST tree and extracts all remote function calls found
  (calls using `Module.function(args)` syntax).

  ## Options

  - `:include_location` - Whether to extract source location (default: true)
  - `:max_depth` - Maximum recursion depth (default: 100)

  ## Examples

      iex> ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      iex> calls = ElixirOntologies.Extractors.Call.extract_remote_calls(ast)
      iex> length(calls)
      1
      iex> hd(calls).module
      [:String]
  """
  @spec extract_remote_calls(Macro.t(), keyword()) :: [FunctionCall.t()]
  def extract_remote_calls(ast, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, Helpers.max_recursion_depth())
    extract_calls_recursive(ast, opts, 0, max_depth, :remote)
  end

  @doc """
  Extracts all function calls (both local and remote) from an AST.

  Walks the entire AST tree and extracts all function calls found.
  This is useful when you need a complete call graph.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)
  - `:max_depth` - Maximum recursion depth (default: 100)

  ## Examples

      iex> body = [
      ...>   {:foo, [], []},
      ...>   {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      ...> ]
      iex> calls = ElixirOntologies.Extractors.Call.extract_all_calls(body)
      iex> length(calls)
      2
      iex> Enum.map(calls, & &1.type)
      [:local, :remote]
  """
  @spec extract_all_calls(Macro.t(), keyword()) :: [FunctionCall.t()]
  def extract_all_calls(ast, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, Helpers.max_recursion_depth())
    extract_calls_recursive(ast, opts, 0, max_depth, :all)
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp build_local_call(name, args, node, opts) do
    location = Helpers.extract_location_if(node, opts)

    {:ok,
     %FunctionCall{
       type: :local,
       name: name,
       arity: length(args),
       arguments: args,
       location: location,
       metadata: %{}
     }}
  end

  defp build_remote_call(module, func_name, args, node, opts, extra_metadata) do
    location = Helpers.extract_location_if(node, opts)

    {:ok,
     %FunctionCall{
       type: :remote,
       name: func_name,
       arity: length(args),
       module: module,
       arguments: args,
       location: location,
       metadata: extra_metadata
     }}
  end

  # ===========================================================================
  # Recursive Extraction
  # ===========================================================================

  # mode can be :local, :remote, or :all

  # Recursive extraction with depth tracking
  defp extract_calls_recursive(_ast, _opts, depth, max_depth, _mode) when depth > max_depth do
    []
  end

  # Handle list of statements
  defp extract_calls_recursive(statements, opts, depth, max_depth, mode) when is_list(statements) do
    Enum.flat_map(statements, &extract_calls_recursive(&1, opts, depth, max_depth, mode))
  end

  # Handle __block__
  defp extract_calls_recursive({:__block__, _meta, statements}, opts, depth, max_depth, mode) do
    extract_calls_recursive(statements, opts, depth, max_depth, mode)
  end

  # Handle remote function call - {{:., _, [receiver, func]}, _, args}
  defp extract_calls_recursive(
         {{:., _dot_meta, [_receiver, _func_name]}, _meta, args} = node,
         opts,
         depth,
         max_depth,
         mode
       )
       when is_list(args) do
    calls_from_args = extract_calls_recursive(args, opts, depth + 1, max_depth, mode)

    if mode in [:remote, :all] and remote_call?(node) do
      case extract_remote(node, opts) do
        {:ok, call} -> [call | calls_from_args]
        {:error, _} -> calls_from_args
      end
    else
      calls_from_args
    end
  end

  # Handle local function call - extract it and recurse into args
  defp extract_calls_recursive({name, _meta, args} = node, opts, depth, max_depth, mode)
       when is_atom(name) and is_list(args) do
    calls_from_args = extract_calls_recursive(args, opts, depth + 1, max_depth, mode)

    if mode in [:local, :all] and local_call?(node) do
      case extract(node, opts) do
        {:ok, call} -> [call | calls_from_args]
        {:error, _} -> calls_from_args
      end
    else
      # Still recurse into args for special forms like if, case, etc.
      calls_from_args
    end
  end

  # Handle two-element tuples (e.g., keyword pairs, {key, value})
  defp extract_calls_recursive({left, right}, opts, depth, max_depth, mode) do
    extract_calls_recursive(left, opts, depth + 1, max_depth, mode) ++
      extract_calls_recursive(right, opts, depth + 1, max_depth, mode)
  end

  # Handle three-element tuples that aren't AST nodes (rare)
  defp extract_calls_recursive({a, b, c}, opts, depth, max_depth, mode)
       when not is_atom(a) or not is_list(b) do
    extract_calls_recursive(a, opts, depth + 1, max_depth, mode) ++
      extract_calls_recursive(b, opts, depth + 1, max_depth, mode) ++
      extract_calls_recursive(c, opts, depth + 1, max_depth, mode)
  end

  # Ignore atoms, literals, and other non-tuple forms
  defp extract_calls_recursive(_other, _opts, _depth, _max_depth, _mode) do
    []
  end
end
