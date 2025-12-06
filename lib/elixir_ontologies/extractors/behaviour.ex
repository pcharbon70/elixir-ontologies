defmodule ElixirOntologies.Extractors.Behaviour do
  @moduledoc """
  Extracts behaviour definitions from module AST nodes.

  This module analyzes Elixir AST nodes to extract behaviour definitions,
  including @callback, @macrocallback, and @optional_callbacks. Supports
  the behaviour-related classes from elixir-structure.ttl:

  - Behaviour: A module defining callbacks
  - Callback: A required callback function
  - MacroCallback: A required macro callback
  - OptionalCallback: A callback marked as optional

  ## Usage

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule MyBehaviour do @callback foo(term()) :: :ok end"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = {:ok, ast}
      iex> result = Behaviour.extract_from_body(body)
      iex> length(result.callbacks)
      1
      iex> hd(result.callbacks).name
      :foo

  ## Callback Extraction

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "@callback start_link(opts :: keyword()) :: GenServer.on_start()"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, callback} = Behaviour.extract_callback(ast)
      iex> callback.name
      :start_link
      iex> callback.arity
      1

  ## Optional Callbacks

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule B do @callback req(t) :: t; @callback opt(t) :: t; @optional_callbacks [opt: 1] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_from_body(body)
      iex> Enum.find(result.callbacks, & &1.name == :opt).is_optional
      true
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Structs
  # ===========================================================================

  @typedoc """
  The result of behaviour extraction from a module body.

  - `:callbacks` - List of @callback definitions
  - `:macrocallbacks` - List of @macrocallback definitions
  - `:optional_callbacks` - List of {name, arity} marked optional
  - `:doc` - @moduledoc content if present
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          callbacks: [callback()],
          macrocallbacks: [callback()],
          optional_callbacks: [{atom(), non_neg_integer()}],
          doc: String.t() | false | nil,
          metadata: map()
        }

  @typedoc """
  A callback definition.

  - `:name` - Callback function name
  - `:arity` - Number of parameters
  - `:spec` - Full typespec AST
  - `:return_type` - Return type AST
  - `:parameters` - List of parameter type specs
  - `:is_optional` - Whether marked in @optional_callbacks
  - `:doc` - @doc content if present
  - `:location` - Source location
  """
  @type callback :: %{
          name: atom(),
          arity: non_neg_integer(),
          spec: Macro.t(),
          return_type: Macro.t() | nil,
          parameters: [Macro.t()],
          is_optional: boolean(),
          doc: String.t() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  defstruct [
    callbacks: [],
    macrocallbacks: [],
    optional_callbacks: [],
    doc: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Implementation Structs
  # ===========================================================================

  @typedoc """
  A behaviour implementation extracted from a module.

  - `:behaviour` - The behaviour module being implemented
  - `:behaviour_alias` - The alias AST for the behaviour
  - `:location` - Source location of @behaviour declaration
  """
  @type implementation :: %{
          behaviour: module() | atom(),
          behaviour_alias: Macro.t(),
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  @typedoc """
  An overridable function declaration.

  - `:name` - Function name
  - `:arity` - Function arity
  - `:source` - :list (keyword list) or :module (behaviour module reference)
  - `:location` - Source location
  """
  @type overridable :: %{
          name: atom(),
          arity: non_neg_integer(),
          source: :list | :module,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  @typedoc """
  Result of extracting behaviour implementations from a module.

  - `:behaviours` - List of @behaviour declarations
  - `:overridables` - List of defoverridable entries
  - `:functions` - List of {name, arity} defined in module
  """
  @type implementation_result :: %{
          behaviours: [implementation()],
          overridables: [overridable()],
          functions: [{atom(), non_neg_integer()}]
        }

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node is a @callback attribute.

  ## Examples

      iex> ElixirOntologies.Extractors.Behaviour.callback?({:@, [], [{:callback, [], [{:"::", [], [:foo, :ok]}]}]})
      true

      iex> ElixirOntologies.Extractors.Behaviour.callback?({:@, [], [{:doc, [], ["text"]}]})
      false
  """
  @spec callback?(Macro.t()) :: boolean()
  def callback?({:@, _meta, [{:callback, _attr_meta, [_spec]}]}), do: true
  def callback?(_), do: false

  @doc """
  Checks if an AST node is a @macrocallback attribute.

  ## Examples

      iex> ElixirOntologies.Extractors.Behaviour.macrocallback?({:@, [], [{:macrocallback, [], [{:"::", [], [:foo, :ok]}]}]})
      true

      iex> ElixirOntologies.Extractors.Behaviour.macrocallback?({:@, [], [{:callback, [], [{:"::", [], [:foo, :ok]}]}]})
      false
  """
  @spec macrocallback?(Macro.t()) :: boolean()
  def macrocallback?({:@, _meta, [{:macrocallback, _attr_meta, [_spec]}]}), do: true
  def macrocallback?(_), do: false

  @doc """
  Checks if an AST node is a @optional_callbacks attribute.

  ## Examples

      iex> ElixirOntologies.Extractors.Behaviour.optional_callbacks?({:@, [], [{:optional_callbacks, [], [[foo: 1]]}]})
      true

      iex> ElixirOntologies.Extractors.Behaviour.optional_callbacks?({:@, [], [{:callback, [], [{:"::", [], [:foo, :ok]}]}]})
      false
  """
  @spec optional_callbacks?(Macro.t()) :: boolean()
  def optional_callbacks?({:@, _meta, [{:optional_callbacks, _attr_meta, [_list]}]}), do: true
  def optional_callbacks?(_), do: false

  @doc """
  Checks if an AST node is a @behaviour attribute.

  ## Examples

      iex> ElixirOntologies.Extractors.Behaviour.behaviour_declaration?({:@, [], [{:behaviour, [], [{:__aliases__, [], [:GenServer]}]}]})
      true

      iex> ElixirOntologies.Extractors.Behaviour.behaviour_declaration?({:@, [], [{:callback, [], [{:"::", [], [:foo, :ok]}]}]})
      false
  """
  @spec behaviour_declaration?(Macro.t()) :: boolean()
  def behaviour_declaration?({:@, _meta, [{:behaviour, _attr_meta, [_module]}]}), do: true
  def behaviour_declaration?(_), do: false

  @doc """
  Checks if an AST node is a defoverridable declaration.

  ## Examples

      iex> ElixirOntologies.Extractors.Behaviour.defoverridable?({:defoverridable, [], [[foo: 1, bar: 2]]})
      true

      iex> ElixirOntologies.Extractors.Behaviour.defoverridable?({:defoverridable, [], [{:__aliases__, [], [:MyBehaviour]}]})
      true

      iex> ElixirOntologies.Extractors.Behaviour.defoverridable?({:def, [], [{:foo, [], nil}]})
      false
  """
  @spec defoverridable?(Macro.t()) :: boolean()
  def defoverridable?({:defoverridable, _meta, [_args]}), do: true
  def defoverridable?(_), do: false

  # ===========================================================================
  # Module Body Extraction
  # ===========================================================================

  @doc """
  Extracts all behaviour information from a module body.

  This is the main extraction function that processes the body of a defmodule
  and extracts all callbacks, macrocallbacks, and optional_callbacks.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule B do @callback foo(t) :: t; @macrocallback bar(t) :: Macro.t() end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_from_body(body)
      iex> length(result.callbacks)
      1
      iex> length(result.macrocallbacks)
      1
  """
  @spec extract_from_body(Macro.t()) :: t()
  def extract_from_body(body) do
    statements = extract_statements(body)

    # First pass: extract optional_callbacks list
    optional_list = extract_optional_callbacks_list(statements)

    # Second pass: extract callbacks with pending doc
    {callbacks, macrocallbacks, _pending_doc} =
      Enum.reduce(statements, {[], [], nil}, fn
        # @doc - save for next callback
        {:@, _meta, [{:doc, _doc_meta, [doc_value]}]}, {cbs, mcbs, _doc} ->
          {cbs, mcbs, doc_value}

        # @callback
        {:@, meta, [{:callback, _attr_meta, [spec]}]}, {cbs, mcbs, doc} ->
          callback = extract_callback_from_spec(spec, meta, doc, optional_list, :callback)
          {[callback | cbs], mcbs, nil}

        # @macrocallback
        {:@, meta, [{:macrocallback, _attr_meta, [spec]}]}, {cbs, mcbs, doc} ->
          callback = extract_callback_from_spec(spec, meta, doc, optional_list, :macrocallback)
          {cbs, [callback | mcbs], nil}

        # Other nodes - preserve pending doc
        _other, {cbs, mcbs, doc} ->
          {cbs, mcbs, doc}
      end)

    doc = extract_moduledoc(statements)

    %__MODULE__{
      callbacks: Enum.reverse(callbacks),
      macrocallbacks: Enum.reverse(macrocallbacks),
      optional_callbacks: optional_list,
      doc: doc,
      metadata: %{}
    }
  end

  @doc """
  Checks if a module body defines a behaviour (has @callback or @macrocallback).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule B do @callback foo(t) :: t end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Behaviour.defines_behaviour?(body)
      true

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule M do def foo, do: :ok end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Behaviour.defines_behaviour?(body)
      false
  """
  @spec defines_behaviour?(Macro.t()) :: boolean()
  def defines_behaviour?(body) do
    statements = extract_statements(body)

    Enum.any?(statements, fn
      {:@, _meta, [{:callback, _attr_meta, _}]} -> true
      {:@, _meta, [{:macrocallback, _attr_meta, _}]} -> true
      _ -> false
    end)
  end

  @doc """
  Checks if a module body implements any behaviours (has @behaviour declarations).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule M do @behaviour GenServer; def init(a), do: {:ok, a} end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Behaviour.implements_behaviour?(body)
      true

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule M do def foo, do: :ok end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Behaviour.implements_behaviour?(body)
      false
  """
  @spec implements_behaviour?(Macro.t()) :: boolean()
  def implements_behaviour?(body) do
    statements = extract_statements(body)

    Enum.any?(statements, fn
      {:@, _meta, [{:behaviour, _attr_meta, _}]} -> true
      _ -> false
    end)
  end

  @doc """
  Extracts behaviour implementations from a module body.

  Returns a map containing:
  - `:behaviours` - List of @behaviour declarations
  - `:overridables` - List of defoverridable entries
  - `:functions` - List of {name, arity} defined in module

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule M do @behaviour GenServer; def init(a), do: {:ok, a} end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_implementations(body)
      iex> length(result.behaviours)
      1
      iex> hd(result.behaviours).behaviour
      GenServer

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule M do @behaviour Plug; @behaviour GenServer; def init(a), do: {:ok, a}; def call(c,o), do: c end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_implementations(body)
      iex> length(result.behaviours)
      2
      iex> result.functions
      [{:init, 1}, {:call, 2}]
  """
  @spec extract_implementations(Macro.t()) :: implementation_result()
  def extract_implementations(body) do
    statements = extract_statements(body)

    behaviours = extract_behaviour_declarations(statements)
    overridables = extract_overridables(statements)
    functions = extract_function_signatures(statements)

    %{
      behaviours: behaviours,
      overridables: overridables,
      functions: functions
    }
  end

  @doc """
  Extracts a single @behaviour declaration.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "@behaviour GenServer"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, impl} = Behaviour.extract_behaviour_declaration(ast)
      iex> impl.behaviour
      GenServer

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "@behaviour MyApp.CustomBehaviour"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, impl} = Behaviour.extract_behaviour_declaration(ast)
      iex> impl.behaviour
      MyApp.CustomBehaviour
  """
  @spec extract_behaviour_declaration(Macro.t()) :: {:ok, implementation()} | {:error, String.t()}
  def extract_behaviour_declaration({:@, meta, [{:behaviour, _attr_meta, [module_ast]}]}) do
    location = Helpers.extract_location({:@, meta, []})
    module = module_ast_to_module(module_ast)

    {:ok,
     %{
       behaviour: module,
       behaviour_alias: module_ast,
       location: location
     }}
  end

  def extract_behaviour_declaration(other) do
    {:error, Helpers.format_error("Not a @behaviour declaration", other)}
  end

  @doc """
  Extracts a single @behaviour declaration, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "@behaviour GenServer"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> impl = Behaviour.extract_behaviour_declaration!(ast)
      iex> impl.behaviour
      GenServer
  """
  @spec extract_behaviour_declaration!(Macro.t()) :: implementation()
  @dialyzer {:nowarn_function, extract_behaviour_declaration!: 1}
  def extract_behaviour_declaration!(node) do
    case extract_behaviour_declaration(node) do
      {:ok, impl} -> impl
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Extracts a defoverridable declaration.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defoverridable [init: 1, call: 2]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> overridables = Behaviour.extract_defoverridable(ast)
      iex> length(overridables)
      2
      iex> hd(overridables).name
      :init

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defoverridable MyBehaviour"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> overridables = Behaviour.extract_defoverridable(ast)
      iex> length(overridables)
      1
      iex> hd(overridables).source
      :module
  """
  @spec extract_defoverridable(Macro.t()) :: [overridable()]
  def extract_defoverridable({:defoverridable, meta, [args]}) do
    location = Helpers.extract_location({:defoverridable, meta, []})

    case args do
      # Keyword list: [init: 1, call: 2]
      list when is_list(list) ->
        Enum.map(list, fn {name, arity} ->
          %{
            name: name,
            arity: arity,
            source: :list,
            location: location
          }
        end)

      # Module reference: MyBehaviour
      {:__aliases__, _, _} = module_ast ->
        module = module_ast_to_module(module_ast)

        [
          %{
            name: module,
            arity: 0,
            source: :module,
            location: location
          }
        ]

      # Atom module: :some_behaviour (unlikely but handle)
      atom when is_atom(atom) ->
        [
          %{
            name: atom,
            arity: 0,
            source: :module,
            location: location
          }
        ]

      _ ->
        []
    end
  end

  def extract_defoverridable(_), do: []

  # ===========================================================================
  # Implementation Extraction Helpers
  # ===========================================================================

  defp extract_behaviour_declarations(statements) do
    statements
    |> Enum.filter(&behaviour_declaration?/1)
    |> Enum.map(fn node ->
      {:ok, impl} = extract_behaviour_declaration(node)
      impl
    end)
  end

  defp extract_overridables(statements) do
    statements
    |> Enum.filter(&defoverridable?/1)
    |> Enum.flat_map(&extract_defoverridable/1)
  end

  defp extract_function_signatures(statements) do
    statements
    |> Enum.flat_map(&extract_def_signature/1)
    |> Enum.uniq()
  end

  # Extract {name, arity} from def/defp
  defp extract_def_signature({def_type, _meta, [{name, _fn_meta, args} | _]})
       when def_type in [:def, :defp] and is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    [{name, arity}]
  end

  # def with when clause
  defp extract_def_signature({def_type, _meta, [{:when, _, [{name, _fn_meta, args} | _]} | _]})
       when def_type in [:def, :defp] and is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    [{name, arity}]
  end

  defp extract_def_signature(_), do: []

  # Convert module AST to atom
  defp module_ast_to_module({:__aliases__, _, parts}) do
    Module.concat(parts)
  end

  defp module_ast_to_module(atom) when is_atom(atom), do: atom
  defp module_ast_to_module(_), do: nil

  # ===========================================================================
  # Single Callback Extraction
  # ===========================================================================

  @doc """
  Extracts a single @callback attribute.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "@callback start_link(opts :: keyword()) :: GenServer.on_start()"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, callback} = Behaviour.extract_callback(ast)
      iex> callback.name
      :start_link
      iex> callback.arity
      1

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> Behaviour.extract_callback({:@, [], [{:doc, [], ["text"]}]})
      {:error, "Not a callback: {:@, [], [{:doc, [], [\\"text\\"]}]}"}
  """
  @spec extract_callback(Macro.t()) :: {:ok, callback()} | {:error, String.t()}
  def extract_callback(node) do
    case node do
      {:@, meta, [{:callback, _attr_meta, [spec]}]} ->
        callback = extract_callback_from_spec(spec, meta, nil, [], :callback)
        {:ok, callback}

      {:@, meta, [{:macrocallback, _attr_meta, [spec]}]} ->
        callback = extract_callback_from_spec(spec, meta, nil, [], :macrocallback)
        {:ok, callback}

      _ ->
        {:error, Helpers.format_error("Not a callback", node)}
    end
  end

  @doc """
  Extracts a callback, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "@callback init(args :: term()) :: {:ok, state :: term()}"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> callback = Behaviour.extract_callback!(ast)
      iex> callback.name
      :init
  """
  @spec extract_callback!(Macro.t()) :: callback()
  # Dialyzer false positive: extract_callback/1 can return {:ok, callback}
  @dialyzer {:nowarn_function, extract_callback!: 1}
  def extract_callback!(node) do
    case extract_callback(node) do
      {:ok, callback} -> callback
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ===========================================================================
  # Callback Spec Parsing
  # ===========================================================================

  defp extract_callback_from_spec(spec, meta, doc, optional_list, type) do
    location = Helpers.extract_location({:@, meta, []})
    {name, arity, parameters, return_type} = parse_callback_spec(spec)

    is_optional = {name, arity} in optional_list

    %{
      name: name,
      arity: arity,
      spec: spec,
      return_type: return_type,
      parameters: parameters,
      is_optional: is_optional,
      doc: doc,
      location: location,
      type: type
    }
  end

  # Parse typespec: fun(args) :: return_type
  defp parse_callback_spec({:"::", _meta, [function_head, return_type]}) do
    {name, parameters} = parse_function_head(function_head)
    arity = length(parameters)
    {name, arity, parameters, return_type}
  end

  # Callback without return type (shouldn't happen but handle gracefully)
  defp parse_callback_spec({name, _meta, args}) when is_atom(name) do
    params = if is_list(args), do: args, else: []
    {name, length(params), params, nil}
  end

  defp parse_callback_spec(other) do
    {:unknown, 0, [], other}
  end

  # Parse function head: fun(arg1, arg2, ...)
  defp parse_function_head({name, _meta, args}) when is_atom(name) do
    params = if is_list(args), do: args, else: []
    {name, params}
  end

  # Parse function head with when clause: fun(args) when guards
  defp parse_function_head({:when, _meta, [{name, _fn_meta, args} | _guards]}) when is_atom(name) do
    params = if is_list(args), do: args, else: []
    {name, params}
  end

  defp parse_function_head(other) do
    {:unknown, [other]}
  end

  # ===========================================================================
  # Optional Callbacks Extraction
  # ===========================================================================

  defp extract_optional_callbacks_list(statements) do
    Enum.reduce(statements, [], fn
      {:@, _meta, [{:optional_callbacks, _attr_meta, [list]}]}, acc when is_list(list) ->
        # list is like [foo: 1, bar: 2]
        acc ++ list

      {:@, _meta, [{:optional_callbacks, _attr_meta, [[_ | _] = list]}]}, acc ->
        acc ++ list

      _, acc ->
        acc
    end)
  end

  # ===========================================================================
  # Moduledoc Extraction
  # ===========================================================================

  defp extract_moduledoc(statements) do
    Enum.reduce_while(statements, nil, fn
      {:@, _meta, [{:moduledoc, _doc_meta, [doc]}]}, _acc when is_binary(doc) ->
        {:halt, doc}

      {:@, _meta, [{:moduledoc, _doc_meta, [false]}]}, _acc ->
        {:halt, false}

      _, acc ->
        {:cont, acc}
    end)
  end

  # ===========================================================================
  # Statement Extraction
  # ===========================================================================

  defp extract_statements({:__block__, _, statements}), do: statements
  defp extract_statements(nil), do: []
  defp extract_statements(single), do: [single]

  # ===========================================================================
  # Utility Functions
  # ===========================================================================

  @doc """
  Returns all callback names (both regular and macro).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule B do @callback foo(t) :: t; @macrocallback bar(t) :: Macro.t() end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_from_body(body)
      iex> Behaviour.callback_names(result)
      [:foo, :bar]
  """
  @spec callback_names(t()) :: [atom()]
  def callback_names(%__MODULE__{callbacks: callbacks, macrocallbacks: macrocallbacks}) do
    callbacks_names = Enum.map(callbacks, & &1.name)
    macro_names = Enum.map(macrocallbacks, & &1.name)
    callbacks_names ++ macro_names
  end

  @doc """
  Returns only the required callback names (not in optional_callbacks).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule B do @callback req(t) :: t; @callback opt(t) :: t; @optional_callbacks [opt: 1] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_from_body(body)
      iex> Behaviour.required_callback_names(result)
      [:req]
  """
  @spec required_callback_names(t()) :: [atom()]
  def required_callback_names(%__MODULE__{callbacks: callbacks, macrocallbacks: macrocallbacks}) do
    all = callbacks ++ macrocallbacks

    all
    |> Enum.reject(& &1.is_optional)
    |> Enum.map(& &1.name)
  end

  @doc """
  Returns the optional callback names.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule B do @callback req(t) :: t; @callback opt(t) :: t; @optional_callbacks [opt: 1] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_from_body(body)
      iex> Behaviour.optional_callback_names(result)
      [:opt]
  """
  @spec optional_callback_names(t()) :: [atom()]
  def optional_callback_names(%__MODULE__{callbacks: callbacks, macrocallbacks: macrocallbacks}) do
    all = callbacks ++ macrocallbacks

    all
    |> Enum.filter(& &1.is_optional)
    |> Enum.map(& &1.name)
  end

  @doc """
  Gets a callback by name.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule B do @callback foo(t) :: t; @callback bar(t, t) :: t end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_from_body(body)
      iex> cb = Behaviour.get_callback(result, :bar)
      iex> cb.arity
      2
  """
  @spec get_callback(t(), atom()) :: callback() | nil
  def get_callback(%__MODULE__{callbacks: callbacks, macrocallbacks: macrocallbacks}, name) do
    all = callbacks ++ macrocallbacks
    Enum.find(all, fn cb -> cb.name == name end)
  end

  @doc """
  Checks if a callback is optional.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule B do @callback opt(t) :: t; @optional_callbacks [opt: 1] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_from_body(body)
      iex> Behaviour.optional?(result, :opt, 1)
      true
      iex> Behaviour.optional?(result, :other, 1)
      false
  """
  @spec optional?(t(), atom(), non_neg_integer()) :: boolean()
  def optional?(%__MODULE__{optional_callbacks: optional_list}, name, arity) do
    {name, arity} in optional_list
  end

  # ===========================================================================
  # Implementation Utility Functions
  # ===========================================================================

  @doc """
  Returns the list of behaviour modules implemented.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule M do @behaviour GenServer; @behaviour Plug end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_implementations(body)
      iex> Behaviour.implemented_behaviours(result)
      [GenServer, Plug]
  """
  @spec implemented_behaviours(implementation_result()) :: [module()]
  def implemented_behaviours(%{behaviours: behaviours}) do
    Enum.map(behaviours, & &1.behaviour)
  end

  @doc """
  Returns list of {name, arity} for overridable functions.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule M do defoverridable [init: 1, call: 2] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_implementations(body)
      iex> Behaviour.overridable_functions(result)
      [{:init, 1}, {:call, 2}]
  """
  @spec overridable_functions(implementation_result()) :: [{atom(), non_neg_integer()}]
  def overridable_functions(%{overridables: overridables}) do
    overridables
    |> Enum.filter(&(&1.source == :list))
    |> Enum.map(&{&1.name, &1.arity})
  end

  @doc """
  Checks if a function is marked as overridable.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule M do defoverridable [init: 1] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_implementations(body)
      iex> Behaviour.overridable?(result, :init, 1)
      true
      iex> Behaviour.overridable?(result, :other, 1)
      false
  """
  @spec overridable?(implementation_result(), atom(), non_neg_integer()) :: boolean()
  def overridable?(%{overridables: overridables}, name, arity) do
    Enum.any?(overridables, fn
      %{name: ^name, arity: ^arity, source: :list} -> true
      _ -> false
    end)
  end

  @doc """
  Checks if a module implements a specific behaviour.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule M do @behaviour GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_implementations(body)
      iex> Behaviour.implements?(result, GenServer)
      true
      iex> Behaviour.implements?(result, Plug)
      false
  """
  @spec implements?(implementation_result(), module()) :: boolean()
  def implements?(%{behaviours: behaviours}, module) do
    Enum.any?(behaviours, &(&1.behaviour == module))
  end

  @doc """
  Returns functions that match callback signatures (by name/arity).

  This is useful for verifying callback implementations.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule M do @behaviour GenServer; def init(a), do: {:ok, a}; def handle_call(r,f,s), do: {:reply,:ok,s} end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_implementations(body)
      iex> callbacks = [{:init, 1}, {:handle_call, 3}, {:handle_cast, 2}]
      iex> Behaviour.matching_callbacks(result, callbacks)
      [{:init, 1}, {:handle_call, 3}]
  """
  @spec matching_callbacks(implementation_result(), [{atom(), non_neg_integer()}]) :: [
          {atom(), non_neg_integer()}
        ]
  def matching_callbacks(%{functions: functions}, callback_signatures) do
    callback_set = MapSet.new(callback_signatures)

    functions
    |> Enum.filter(&MapSet.member?(callback_set, &1))
  end

  @doc """
  Returns callbacks that are NOT implemented in the module.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Behaviour
      iex> code = "defmodule M do def init(a), do: {:ok, a} end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Behaviour.extract_implementations(body)
      iex> callbacks = [{:init, 1}, {:handle_call, 3}]
      iex> Behaviour.missing_callbacks(result, callbacks)
      [{:handle_call, 3}]
  """
  @spec missing_callbacks(implementation_result(), [{atom(), non_neg_integer()}]) :: [
          {atom(), non_neg_integer()}
        ]
  def missing_callbacks(%{functions: functions}, callback_signatures) do
    function_set = MapSet.new(functions)

    callback_signatures
    |> Enum.reject(&MapSet.member?(function_set, &1))
  end
end
