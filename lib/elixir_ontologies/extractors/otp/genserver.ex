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

  defstruct [
    detection_method: :use,
    use_options: nil,
    location: nil,
    metadata: %{}
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
  def behaviour_genserver?({:@, _meta, [{:behaviour, _attr_meta, [{:__aliases__, _, [:GenServer]}]}]}), do: true
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
  defp extract_use_options({:use, _meta, [{:__aliases__, _, [:GenServer]}, opts]}) when is_list(opts), do: opts
  defp extract_use_options({:use, _meta, [GenServer, opts]}) when is_list(opts), do: opts
  defp extract_use_options(_), do: []

  defp find_use_options(statements) do
    case Enum.find(statements, &use_genserver?/1) do
      nil -> nil
      node -> extract_use_options(node)
    end
  end
end
