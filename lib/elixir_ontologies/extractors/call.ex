defmodule ElixirOntologies.Extractors.Call do
  @moduledoc """
  Extracts function call information from Elixir AST.

  This module provides extraction of function calls including:
  - **Local calls** - calls to functions in the same module
  - **Remote calls** - calls via `Module.function(args)` syntax
  - **Dynamic calls** - calls via `apply/2`, `apply/3`, or anonymous function invocation

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

  ### Dynamic Calls

  Dynamic calls are calls where the target cannot be determined at compile time:

      # apply/3: apply(Module, :func, args)
      {:apply, [], [{:__aliases__, [], [:Module]}, :func, [1, 2]]}

      # apply/2: apply(fun, args)
      {:apply, [], [{:fun, [], Elixir}, [1, 2]]}

      # Anonymous function call: fun.(args)
      {{:., [], [{:callback, [], Elixir}]}, [], [1, 2]}

  ## Examples

      iex> ast = {:foo, [line: 1], []}
      iex> ElixirOntologies.Extractors.Call.local_call?(ast)
      true

      iex> ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      iex> ElixirOntologies.Extractors.Call.remote_call?(ast)
      true

      iex> ast = {:apply, [], [{:__aliases__, [], [:Module]}, :func, [1, 2]]}
      iex> ElixirOntologies.Extractors.Call.dynamic_call?(ast)
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
  @operators [
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
    :&&,
    :||,
    :!,
    :and,
    :or,
    :not,
    :++,
    :--,
    :<>,
    :in,
    :@,
    :when,
    :"not in"
  ]

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
  def remote_call?(
        {{:., _dot_meta, [{:__aliases__, _alias_meta, _parts}, func_name]}, _meta, args}
      )
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

  @doc """
  Checks if the given AST node represents a dynamic function call.

  Returns `true` for:
  - `apply/3` calls: `apply(Module, :func, args)`
  - `apply/2` calls: `apply(fun, args)`
  - `Kernel.apply/3` calls
  - Anonymous function calls: `fun.(args)`

  ## Examples

      iex> ast = {:apply, [], [{:__aliases__, [], [:Module]}, :func, [1, 2]]}
      iex> ElixirOntologies.Extractors.Call.dynamic_call?(ast)
      true

      iex> ast = {:apply, [], [{:fun, [], Elixir}, [1, 2]]}
      iex> ElixirOntologies.Extractors.Call.dynamic_call?(ast)
      true

      iex> ast = {{:., [], [{:callback, [], Elixir}]}, [], [1, 2]}
      iex> ElixirOntologies.Extractors.Call.dynamic_call?(ast)
      true

      iex> ast = {:foo, [], []}
      iex> ElixirOntologies.Extractors.Call.dynamic_call?(ast)
      false
  """
  @spec dynamic_call?(Macro.t()) :: boolean()
  # apply/3: apply(Module, :func, args)
  def dynamic_call?({:apply, _meta, [_module, _func, args]}) when is_list(args), do: true

  # apply/2: apply(fun, args)
  def dynamic_call?({:apply, _meta, [_fun, args]}) when is_list(args), do: true

  # Kernel.apply/3: Kernel.apply(Module, :func, args)
  def dynamic_call?({{:., _, [{:__aliases__, _, [:Kernel]}, :apply]}, _, [_, _, args]})
      when is_list(args) do
    true
  end

  # Kernel.apply/2: Kernel.apply(fun, args)
  def dynamic_call?({{:., _, [{:__aliases__, _, [:Kernel]}, :apply]}, _, [_, args]})
      when is_list(args) do
    true
  end

  # Anonymous function call: fun.(args) - dot call with single element (no function name)
  def dynamic_call?({{:., _, [receiver]}, _, args})
      when is_tuple(receiver) and is_list(args) do
    # Check that receiver is a variable (not __aliases__ which would be a module)
    case receiver do
      {:__aliases__, _, _} -> false
      {:__MODULE__, _, _} -> false
      {name, _, ctx} when is_atom(name) and is_atom(ctx) -> true
      _ -> false
    end
  end

  def dynamic_call?(_), do: false

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
  # Dynamic Call Extraction
  # ===========================================================================

  @doc """
  Extracts a dynamic function call from an AST node.

  Dynamic calls include `apply/2`, `apply/3`, `Kernel.apply`, and anonymous
  function invocations (`fun.(args)`).

  Returns `{:ok, %FunctionCall{}}` on success, `{:error, reason}` on failure.

  ## Metadata

  The metadata field contains information about the dynamic call:
  - `:dynamic_type` - One of `:apply_3`, `:apply_2`, or `:anonymous_call`
  - For apply calls: `:known_module`, `:known_function` if literals
  - For apply calls: `:module_variable`, `:function_variable` if variables
  - For anonymous calls: `:function_variable`

  ## Examples

      iex> ast = {:apply, [], [{:__aliases__, [], [:String]}, :upcase, ["hello"]]}
      iex> {:ok, call} = ElixirOntologies.Extractors.Call.extract_dynamic(ast)
      iex> call.type
      :dynamic
      iex> call.metadata.dynamic_type
      :apply_3
      iex> call.metadata.known_module
      [:String]

      iex> ast = {{:., [], [{:callback, [], Elixir}]}, [], [1, 2]}
      iex> {:ok, call} = ElixirOntologies.Extractors.Call.extract_dynamic(ast)
      iex> call.metadata.dynamic_type
      :anonymous_call
      iex> call.metadata.function_variable
      :callback
  """
  @spec extract_dynamic(Macro.t(), keyword()) :: {:ok, FunctionCall.t()} | {:error, term()}
  def extract_dynamic(ast, opts \\ [])

  # apply/3: apply(Module, :func, args)
  def extract_dynamic({:apply, _meta, [module, func, args]} = node, opts)
      when is_list(args) do
    build_apply_3_call(module, func, args, node, opts)
  end

  # apply/2: apply(fun, args)
  def extract_dynamic({:apply, _meta, [fun, args]} = node, opts)
      when is_list(args) do
    build_apply_2_call(fun, args, node, opts)
  end

  # Kernel.apply/3: Kernel.apply(Module, :func, args)
  def extract_dynamic(
        {{:., _, [{:__aliases__, _, [:Kernel]}, :apply]}, _, [module, func, args]} = node,
        opts
      )
      when is_list(args) do
    build_apply_3_call(module, func, args, node, opts)
  end

  # Kernel.apply/2: Kernel.apply(fun, args)
  def extract_dynamic(
        {{:., _, [{:__aliases__, _, [:Kernel]}, :apply]}, _, [fun, args]} = node,
        opts
      )
      when is_list(args) do
    build_apply_2_call(fun, args, node, opts)
  end

  # Anonymous function call: fun.(args)
  def extract_dynamic({{:., _, [receiver]}, _, args} = node, opts)
      when is_tuple(receiver) and is_list(args) do
    case receiver do
      {name, _, ctx}
      when is_atom(name) and is_atom(ctx) and name not in [:__aliases__, :__MODULE__] ->
        build_anonymous_call(name, args, node, opts)

      _ ->
        {:error, {:not_a_dynamic_call, Helpers.format_error("Not a dynamic function call", node)}}
    end
  end

  def extract_dynamic(node, _opts) do
    {:error, {:not_a_dynamic_call, Helpers.format_error("Not a dynamic function call", node)}}
  end

  @doc """
  Extracts a dynamic function call, raising on error.

  ## Examples

      iex> ast = {:apply, [], [{:fun, [], Elixir}, [1, 2]]}
      iex> call = ElixirOntologies.Extractors.Call.extract_dynamic!(ast)
      iex> call.type
      :dynamic
  """
  @spec extract_dynamic!(Macro.t(), keyword()) :: FunctionCall.t()
  def extract_dynamic!(ast, opts \\ []) do
    case extract_dynamic(ast, opts) do
      {:ok, call} ->
        call

      {:error, reason} ->
        raise ArgumentError, "Failed to extract dynamic call: #{inspect(reason)}"
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

  @doc """
  Extracts all dynamic function calls from an AST.

  Walks the entire AST tree and extracts all dynamic function calls found
  (apply/2, apply/3, Kernel.apply, anonymous function calls).

  ## Options

  - `:include_location` - Whether to extract source location (default: true)
  - `:max_depth` - Maximum recursion depth (default: 100)

  ## Examples

      iex> ast = {:apply, [], [{:__aliases__, [], [:String]}, :upcase, ["hello"]]}
      iex> calls = ElixirOntologies.Extractors.Call.extract_dynamic_calls(ast)
      iex> length(calls)
      1
      iex> hd(calls).type
      :dynamic
  """
  @spec extract_dynamic_calls(Macro.t(), keyword()) :: [FunctionCall.t()]
  def extract_dynamic_calls(ast, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, Helpers.max_recursion_depth())
    extract_calls_recursive(ast, opts, 0, max_depth, :dynamic)
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

  # Build apply/3 call - tracks known module/function when literals
  defp build_apply_3_call(module, func, args, node, opts) do
    location = Helpers.extract_location_if(node, opts)

    metadata =
      %{dynamic_type: :apply_3}
      |> add_module_info(module)
      |> add_function_info(func)

    {:ok,
     %FunctionCall{
       type: :dynamic,
       name: :apply,
       arity: length(args),
       arguments: args,
       location: location,
       metadata: metadata
     }}
  end

  # Build apply/2 call - tracks function variable
  defp build_apply_2_call(fun, args, node, opts) do
    location = Helpers.extract_location_if(node, opts)

    metadata =
      %{dynamic_type: :apply_2}
      |> add_function_var_info(fun)

    {:ok,
     %FunctionCall{
       type: :dynamic,
       name: :apply,
       arity: length(args),
       arguments: args,
       location: location,
       metadata: metadata
     }}
  end

  # Build anonymous function call
  defp build_anonymous_call(var_name, args, node, opts) do
    location = Helpers.extract_location_if(node, opts)

    {:ok,
     %FunctionCall{
       type: :dynamic,
       name: :anonymous,
       arity: length(args),
       arguments: args,
       location: location,
       metadata: %{dynamic_type: :anonymous_call, function_variable: var_name}
     }}
  end

  # Helper to add module info to metadata
  defp add_module_info(metadata, {:__aliases__, _, parts}) do
    Map.put(metadata, :known_module, parts)
  end

  defp add_module_info(metadata, module) when is_atom(module) do
    Map.put(metadata, :known_module, module)
  end

  defp add_module_info(metadata, {var_name, _, ctx}) when is_atom(var_name) and is_atom(ctx) do
    Map.put(metadata, :module_variable, var_name)
  end

  defp add_module_info(metadata, _), do: metadata

  # Helper to add function info to metadata
  defp add_function_info(metadata, func) when is_atom(func) do
    Map.put(metadata, :known_function, func)
  end

  defp add_function_info(metadata, {var_name, _, ctx}) when is_atom(var_name) and is_atom(ctx) do
    Map.put(metadata, :function_variable, var_name)
  end

  defp add_function_info(metadata, _), do: metadata

  # Helper to add function variable info for apply/2
  defp add_function_var_info(metadata, {var_name, _, ctx})
       when is_atom(var_name) and is_atom(ctx) do
    Map.put(metadata, :function_variable, var_name)
  end

  defp add_function_var_info(metadata, {:&, _, _} = capture) do
    Map.put(metadata, :function_capture, capture)
  end

  defp add_function_var_info(metadata, _), do: metadata

  # ===========================================================================
  # Recursive Extraction
  # ===========================================================================

  # mode can be :local, :remote, :dynamic, or :all

  # Recursive extraction with depth tracking
  defp extract_calls_recursive(_ast, _opts, depth, max_depth, _mode) when depth > max_depth do
    []
  end

  # Handle list of statements
  defp extract_calls_recursive(statements, opts, depth, max_depth, mode)
       when is_list(statements) do
    Enum.flat_map(statements, &extract_calls_recursive(&1, opts, depth, max_depth, mode))
  end

  # Handle __block__
  defp extract_calls_recursive({:__block__, _meta, statements}, opts, depth, max_depth, mode) do
    extract_calls_recursive(statements, opts, depth, max_depth, mode)
  end

  # Handle anonymous function call - {{:., _, [receiver]}, _, args} (single element in dot)
  defp extract_calls_recursive(
         {{:., _dot_meta, [receiver]}, _meta, args} = node,
         opts,
         depth,
         max_depth,
         mode
       )
       when is_tuple(receiver) and is_list(args) do
    calls_from_args = extract_calls_recursive(args, opts, depth + 1, max_depth, mode)

    if mode in [:dynamic, :all] and dynamic_call?(node) do
      case extract_dynamic(node, opts) do
        {:ok, call} -> [call | calls_from_args]
        {:error, _} -> calls_from_args
      end
    else
      calls_from_args
    end
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

    # Check for Kernel.apply first (dynamic), then regular remote call
    cond do
      mode in [:dynamic, :all] and dynamic_call?(node) ->
        case extract_dynamic(node, opts) do
          {:ok, call} -> [call | calls_from_args]
          {:error, _} -> calls_from_args
        end

      mode in [:remote, :all] and remote_call?(node) ->
        case extract_remote(node, opts) do
          {:ok, call} -> [call | calls_from_args]
          {:error, _} -> calls_from_args
        end

      true ->
        calls_from_args
    end
  end

  # Handle apply/2 and apply/3 calls (dynamic)
  defp extract_calls_recursive({:apply, _meta, apply_args} = node, opts, depth, max_depth, mode)
       when is_list(apply_args) do
    calls_from_args = extract_calls_recursive(apply_args, opts, depth + 1, max_depth, mode)

    if mode in [:dynamic, :all] and dynamic_call?(node) do
      case extract_dynamic(node, opts) do
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
