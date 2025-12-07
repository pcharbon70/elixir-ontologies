defmodule ElixirOntologies.Extractors.OTP.GenServer do
  @moduledoc """
  Extracts GenServer implementations from module AST nodes.

  This module analyzes Elixir AST nodes to detect modules implementing the
  GenServer behaviour. Supports the OTP-related classes from elixir-otp.ttl:

  - GenServerImplementation: A module implementing GenServer
  - implementsOTPBehaviour: Relationship linking to GenServer behaviour

  ## Detection Methods

  GenServer implementations can be detected via two patterns:

  1. `use GenServer` - Macro invocation that injects GenServer behaviour
  2. `@behaviour GenServer` - Direct behaviour declaration

  ## Usage

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule Counter do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> GenServerExtractor.genserver?(body)
      true

  ## Extracting Implementation Details

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule Counter do use GenServer, restart: :transient end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = GenServerExtractor.extract(body)
      iex> result.detection_method
      :use
      iex> result.use_options
      [restart: :transient]

  ## Behaviour Declaration

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule Counter do @behaviour GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = GenServerExtractor.extract(body)
      iex> result.detection_method
      :behaviour
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of GenServer extraction from a module body.

  - `:detection_method` - How GenServer was detected (:use or :behaviour)
  - `:use_options` - Options passed to `use GenServer` (nil if via @behaviour)
  - `:location` - Source location of the detection point
  - `:metadata` - Additional information about the implementation
  """
  @type t :: %__MODULE__{
          detection_method: :use | :behaviour,
          use_options: keyword() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct detection_method: :use,
            use_options: nil,
            location: nil,
            metadata: %{}

  # ===========================================================================
  # Callback Struct
  # ===========================================================================

  defmodule Callback do
    @moduledoc """
    Represents an extracted GenServer callback function.
    """

    @typedoc """
    The type of GenServer callback.
    """
    @type callback_type ::
            :init
            | :handle_call
            | :handle_cast
            | :handle_info
            | :handle_continue
            | :terminate
            | :code_change
            | :format_status

    @typedoc """
    An extracted GenServer callback.

    - `:type` - The callback type (init, handle_call, etc.)
    - `:name` - Function name (always matches type)
    - `:arity` - Function arity
    - `:clauses` - Number of function clauses
    - `:has_impl` - Whether @impl annotation is present
    - `:location` - Source location of first clause
    - `:metadata` - Additional information
    """
    @type t :: %__MODULE__{
            type: callback_type(),
            name: atom(),
            arity: non_neg_integer(),
            clauses: non_neg_integer(),
            has_impl: boolean(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct type: :init,
              name: :init,
              arity: 1,
              clauses: 1,
              has_impl: false,
              location: nil,
              metadata: %{}
  end

  # GenServer callback specifications: {name, arity, type}
  @genserver_callbacks [
    {:init, 1, :init},
    {:handle_call, 3, :handle_call},
    {:handle_cast, 2, :handle_cast},
    {:handle_info, 2, :handle_info},
    {:handle_continue, 2, :handle_continue},
    {:terminate, 2, :terminate},
    {:code_change, 3, :code_change},
    {:format_status, 1, :format_status}
  ]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if a module body implements GenServer (via `use` or `@behaviour`).

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> GenServerExtractor.genserver?(body)
      true

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do @behaviour GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> GenServerExtractor.genserver?(body)
      true

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do def foo, do: :ok end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> GenServerExtractor.genserver?(body)
      false
  """
  @spec genserver?(Macro.t()) :: boolean()
  def genserver?(body) do
    statements = Helpers.normalize_body(body)
    uses_genserver?(statements) or declares_genserver_behaviour?(statements)
  end

  @doc """
  Checks if a single AST node is a `use GenServer` invocation.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "use GenServer"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> GenServerExtractor.use_genserver?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "use GenServer, restart: :transient"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> GenServerExtractor.use_genserver?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "use Supervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> GenServerExtractor.use_genserver?(ast)
      false
  """
  @spec use_genserver?(Macro.t()) :: boolean()
  def use_genserver?({:use, _meta, [{:__aliases__, _, [:GenServer]} | _opts]}), do: true
  def use_genserver?({:use, _meta, [GenServer | _opts]}), do: true
  def use_genserver?(_), do: false

  @doc """
  Checks if a single AST node is a `@behaviour GenServer` declaration.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "@behaviour GenServer"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> GenServerExtractor.behaviour_genserver?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "@behaviour Supervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> GenServerExtractor.behaviour_genserver?(ast)
      false
  """
  @spec behaviour_genserver?(Macro.t()) :: boolean()
  def behaviour_genserver?(
        {:@, _meta, [{:behaviour, _attr_meta, [{:__aliases__, _, [:GenServer]}]}]}
      ),
      do: true

  def behaviour_genserver?({:@, _meta, [{:behaviour, _attr_meta, [GenServer]}]}), do: true
  def behaviour_genserver?(_), do: false

  # ===========================================================================
  # Extraction
  # ===========================================================================

  @doc """
  Extracts GenServer implementation details from a module body.

  Returns `{:ok, result}` if the module implements GenServer, or
  `{:error, reason}` if it doesn't.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = GenServerExtractor.extract(body)
      iex> result.detection_method
      :use

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do use GenServer, restart: :transient end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = GenServerExtractor.extract(body)
      iex> result.use_options
      [restart: :transient]

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do @behaviour GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = GenServerExtractor.extract(body)
      iex> result.detection_method
      :behaviour
      iex> result.use_options
      nil

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do def foo, do: :ok end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> GenServerExtractor.extract(body)
      {:error, "Module does not implement GenServer"}
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(body, opts \\ []) do
    statements = Helpers.normalize_body(body)

    cond do
      uses_genserver?(statements) ->
        extract_use_genserver(statements, opts)

      declares_genserver_behaviour?(statements) ->
        extract_behaviour_genserver(statements, opts)

      true ->
        {:error, "Module does not implement GenServer"}
    end
  end

  @doc """
  Extracts GenServer implementation, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = GenServerExtractor.extract!(body)
      iex> result.detection_method
      :use
  """
  @spec extract!(Macro.t(), keyword()) :: t()
  def extract!(body, opts \\ []) do
    case extract(body, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ===========================================================================
  # Utility Functions
  # ===========================================================================

  @doc """
  Returns the detection method used for GenServer in the module body.

  Returns `:use`, `:behaviour`, or `nil` if not a GenServer.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> GenServerExtractor.detection_method(body)
      :use

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do @behaviour GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> GenServerExtractor.detection_method(body)
      :behaviour

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do def foo, do: :ok end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> GenServerExtractor.detection_method(body)
      nil
  """
  @spec detection_method(Macro.t()) :: :use | :behaviour | nil
  def detection_method(body) do
    statements = Helpers.normalize_body(body)

    cond do
      uses_genserver?(statements) -> :use
      declares_genserver_behaviour?(statements) -> :behaviour
      true -> nil
    end
  end

  @doc """
  Extracts use options from a module body that uses GenServer.

  Returns the keyword list of options, or `nil` if using @behaviour
  or if no options were provided.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do use GenServer, restart: :transient, shutdown: 5000 end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> GenServerExtractor.use_options(body)
      [restart: :transient, shutdown: 5000]

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> GenServerExtractor.use_options(body)
      []

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do @behaviour GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> GenServerExtractor.use_options(body)
      nil
  """
  @spec use_options(Macro.t()) :: keyword() | nil
  def use_options(body) do
    statements = Helpers.normalize_body(body)
    find_use_options(statements)
  end

  @doc """
  Returns the OTP behaviour type for this extractor.

  This is used when linking via `implementsOTPBehaviour`.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> GenServerExtractor.otp_behaviour()
      :genserver
  """
  @spec otp_behaviour() :: :genserver
  def otp_behaviour, do: :genserver

  # ===========================================================================
  # Callback Extraction
  # ===========================================================================

  @doc """
  Extracts all GenServer callbacks from a module body.

  Returns a list of `Callback` structs for each detected callback.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do use GenServer; def init(s), do: {:ok, s} end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> callbacks = GenServerExtractor.extract_callbacks(body)
      iex> length(callbacks)
      1
      iex> hd(callbacks).type
      :init

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do use GenServer; def init(s), do: {:ok, s}; def handle_call(r,f,s), do: {:reply,:ok,s} end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> callbacks = GenServerExtractor.extract_callbacks(body)
      iex> length(callbacks)
      2
      iex> Enum.map(callbacks, & &1.type)
      [:init, :handle_call]
  """
  @spec extract_callbacks(Macro.t(), keyword()) :: [Callback.t()]
  def extract_callbacks(body, opts \\ []) do
    statements = Helpers.normalize_body(body)

    # Find all @impl annotations
    impl_positions = find_impl_positions(statements)

    # Extract callbacks for each known GenServer callback type
    @genserver_callbacks
    |> Enum.flat_map(fn {name, arity, type} ->
      extract_callback_type(statements, name, arity, type, impl_positions, opts)
    end)
    |> Enum.sort_by(fn cb -> {cb.location && cb.location.start_line, cb.name} end)
  end

  @doc """
  Checks if a function definition is a GenServer callback.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "def init(state), do: {:ok, state}"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> GenServerExtractor.genserver_callback?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "def handle_call(request, from, state), do: {:reply, :ok, state}"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> GenServerExtractor.genserver_callback?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "def my_function(arg), do: arg"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> GenServerExtractor.genserver_callback?(ast)
      false
  """
  @spec genserver_callback?(Macro.t()) :: boolean()
  def genserver_callback?(node) do
    case extract_def_signature(node) do
      {name, arity} ->
        Enum.any?(@genserver_callbacks, fn {cb_name, cb_arity, _type} ->
          name == cb_name and arity == cb_arity
        end)

      nil ->
        false
    end
  end

  @doc """
  Returns the callback type for a function definition.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "def init(state), do: {:ok, state}"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> GenServerExtractor.callback_type(ast)
      :init

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "def handle_cast(msg, state), do: {:noreply, state}"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> GenServerExtractor.callback_type(ast)
      :handle_cast

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "def my_function(arg), do: arg"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> GenServerExtractor.callback_type(ast)
      nil
  """
  @spec callback_type(Macro.t()) :: Callback.callback_type() | nil
  def callback_type(node) do
    case extract_def_signature(node) do
      {name, arity} ->
        case Enum.find(@genserver_callbacks, fn {cb_name, cb_arity, _type} ->
               name == cb_name and arity == cb_arity
             end) do
          {_name, _arity, type} -> type
          nil -> nil
        end

      nil ->
        nil
    end
  end

  @doc """
  Extracts a specific callback type from module body.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do def init(s), do: {:ok, s}; def init(s, o), do: {:ok, {s,o}} end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> callbacks = GenServerExtractor.extract_callback(body, :init)
      iex> length(callbacks)
      1
      iex> hd(callbacks).clauses
      1

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> code = "defmodule C do def handle_call(:get, _from, s), do: {:reply, s, s}; def handle_call(:put, _from, s), do: {:reply, :ok, s} end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> callbacks = GenServerExtractor.extract_callback(body, :handle_call)
      iex> hd(callbacks).clauses
      2
  """
  @spec extract_callback(Macro.t(), Callback.callback_type(), keyword()) :: [Callback.t()]
  def extract_callback(body, type, opts \\ []) do
    statements = Helpers.normalize_body(body)
    impl_positions = find_impl_positions(statements)

    case Enum.find(@genserver_callbacks, fn {_name, _arity, cb_type} -> cb_type == type end) do
      {name, arity, cb_type} ->
        extract_callback_type(statements, name, arity, cb_type, impl_positions, opts)

      nil ->
        []
    end
  end

  @doc """
  Returns the list of known GenServer callback specifications.

  Each tuple contains `{name, arity, type}`.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor
      iex> specs = GenServerExtractor.callback_specs()
      iex> {:init, 1, :init} in specs
      true
      iex> {:handle_call, 3, :handle_call} in specs
      true
  """
  @spec callback_specs() :: [{atom(), non_neg_integer(), Callback.callback_type()}]
  def callback_specs, do: @genserver_callbacks

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp uses_genserver?(statements) do
    Enum.any?(statements, &use_genserver?/1)
  end

  defp declares_genserver_behaviour?(statements) do
    Enum.any?(statements, &behaviour_genserver?/1)
  end

  defp extract_use_genserver(statements, opts) do
    use_node = Enum.find(statements, &use_genserver?/1)
    location = Helpers.extract_location_if(use_node, opts)
    options = extract_use_options(use_node)

    {:ok,
     %__MODULE__{
       detection_method: :use,
       use_options: options,
       location: location,
       metadata: %{
         otp_behaviour: :genserver,
         has_options: options != []
       }
     }}
  end

  defp extract_behaviour_genserver(statements, opts) do
    behaviour_node = Enum.find(statements, &behaviour_genserver?/1)
    location = Helpers.extract_location_if(behaviour_node, opts)

    {:ok,
     %__MODULE__{
       detection_method: :behaviour,
       use_options: nil,
       location: location,
       metadata: %{
         otp_behaviour: :genserver
       }
     }}
  end

  defp extract_use_options({:use, _meta, [{:__aliases__, _, [:GenServer]}]}), do: []
  defp extract_use_options({:use, _meta, [GenServer]}), do: []

  defp extract_use_options({:use, _meta, [{:__aliases__, _, [:GenServer]}, opts]})
       when is_list(opts),
       do: opts

  defp extract_use_options({:use, _meta, [GenServer, opts]}) when is_list(opts), do: opts
  defp extract_use_options(_), do: []

  defp find_use_options(statements) do
    case Enum.find(statements, &use_genserver?/1) do
      nil -> nil
      node -> extract_use_options(node)
    end
  end

  # ===========================================================================
  # Callback Extraction Helpers
  # ===========================================================================

  # Extract signature {name, arity} from a def node
  defp extract_def_signature({:def, _meta, [{:when, _, [{name, _call_meta, args} | _]} | _]})
       when is_atom(name) and name != :when do
    {name, length(args || [])}
  end

  defp extract_def_signature({:def, _meta, [{name, _call_meta, args} | _]})
       when is_atom(name) and name != :when do
    {name, length(args || [])}
  end

  defp extract_def_signature(_), do: nil

  # Find positions (line numbers) of @impl annotations
  defp find_impl_positions(statements) do
    statements
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {statement, index}, acc ->
      case statement do
        {:@, meta, [{:impl, _attr_meta, [true]}]} ->
          line = Keyword.get(meta, :line)
          Map.put(acc, index, line)

        {:@, meta, [{:impl, _attr_meta, [{:__aliases__, _, _}]}]} ->
          # @impl SomeBehaviour
          line = Keyword.get(meta, :line)
          Map.put(acc, index, line)

        {:@, meta, [{:impl, _attr_meta, [atom]}]} when is_atom(atom) and atom != false ->
          # @impl GenServer
          line = Keyword.get(meta, :line)
          Map.put(acc, index, line)

        _ ->
          acc
      end
    end)
  end

  # Check if a def at position has @impl before it
  defp has_impl_annotation?(_statements, def_index, impl_positions) do
    # Check if there's an @impl immediately before this def
    Map.has_key?(impl_positions, def_index - 1)
  end

  # Extract a specific callback type from statements
  defp extract_callback_type(statements, name, arity, type, impl_positions, opts) do
    # Find all clauses matching this callback signature
    clauses_with_index =
      statements
      |> Enum.with_index()
      |> Enum.filter(fn {statement, _index} ->
        case extract_def_signature(statement) do
          {^name, ^arity} -> true
          _ -> false
        end
      end)

    case clauses_with_index do
      [] ->
        []

      [{first_clause, first_index} | _rest] ->
        location = Helpers.extract_location_if(first_clause, opts)
        has_impl = has_impl_annotation?(statements, first_index, impl_positions)

        [
          %Callback{
            type: type,
            name: name,
            arity: arity,
            clauses: length(clauses_with_index),
            has_impl: has_impl,
            location: location,
            metadata: %{
              clause_count: length(clauses_with_index)
            }
          }
        ]
    end
  end
end
