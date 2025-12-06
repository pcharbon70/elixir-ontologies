defmodule ElixirOntologies.Extractors.OTP.Supervisor do
  @moduledoc """
  Extracts Supervisor implementations from module AST nodes.

  This module analyzes Elixir AST nodes to detect modules implementing the
  Supervisor or DynamicSupervisor behaviour. Supports the OTP-related classes
  from elixir-otp.ttl:

  - Supervisor: A module implementing static supervision
  - DynamicSupervisor: A module implementing dynamic supervision
  - implementsOTPBehaviour: Relationship linking to Supervisor behaviour

  ## Detection Methods

  Supervisor implementations can be detected via two patterns:

  1. `use Supervisor` / `use DynamicSupervisor` - Macro invocation
  2. `@behaviour Supervisor` / `@behaviour DynamicSupervisor` - Direct declaration

  ## Usage

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule MySup do use Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.supervisor?(body)
      true

  ## Extracting Implementation Details

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule MySup do use Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = SupervisorExtractor.extract(body)
      iex> result.supervisor_type
      :supervisor
      iex> result.detection_method
      :use

  ## DynamicSupervisor Detection

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule DynSup do use DynamicSupervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = SupervisorExtractor.extract(body)
      iex> result.supervisor_type
      :dynamic_supervisor
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The type of supervisor detected.
  """
  @type supervisor_type :: :supervisor | :dynamic_supervisor

  @typedoc """
  The result of Supervisor extraction from a module body.

  - `:supervisor_type` - The type of supervisor (:supervisor or :dynamic_supervisor)
  - `:detection_method` - How it was detected (:use or :behaviour)
  - `:use_options` - Options passed to `use Supervisor` (nil if via @behaviour)
  - `:location` - Source location of the detection point
  - `:metadata` - Additional information about the implementation
  """
  @type t :: %__MODULE__{
          supervisor_type: supervisor_type(),
          detection_method: :use | :behaviour,
          use_options: keyword() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct [
    supervisor_type: :supervisor,
    detection_method: :use,
    use_options: nil,
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if a module body implements any Supervisor type.

  Returns true for both Supervisor and DynamicSupervisor.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.supervisor?(body)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use DynamicSupervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.supervisor?(body)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.supervisor?(body)
      false
  """
  @spec supervisor?(Macro.t()) :: boolean()
  def supervisor?(body) do
    statements = Helpers.normalize_body(body)

    uses_supervisor?(statements) or
      uses_dynamic_supervisor?(statements) or
      declares_supervisor_behaviour?(statements) or
      declares_dynamic_supervisor_behaviour?(statements)
  end

  @doc """
  Checks if a single AST node is a `use Supervisor` invocation.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "use Supervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.use_supervisor?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "use DynamicSupervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.use_supervisor?(ast)
      false
  """
  @spec use_supervisor?(Macro.t()) :: boolean()
  def use_supervisor?({:use, _meta, [{:__aliases__, _, [:Supervisor]} | _opts]}), do: true
  def use_supervisor?({:use, _meta, [Supervisor | _opts]}), do: true
  def use_supervisor?(_), do: false

  @doc """
  Checks if a single AST node is a `use DynamicSupervisor` invocation.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "use DynamicSupervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.use_dynamic_supervisor?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "use Supervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.use_dynamic_supervisor?(ast)
      false
  """
  @spec use_dynamic_supervisor?(Macro.t()) :: boolean()
  def use_dynamic_supervisor?({:use, _meta, [{:__aliases__, _, [:DynamicSupervisor]} | _opts]}), do: true
  def use_dynamic_supervisor?({:use, _meta, [DynamicSupervisor | _opts]}), do: true
  def use_dynamic_supervisor?(_), do: false

  @doc """
  Checks if a single AST node is a `@behaviour Supervisor` declaration.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "@behaviour Supervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.behaviour_supervisor?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "@behaviour GenServer"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.behaviour_supervisor?(ast)
      false
  """
  @spec behaviour_supervisor?(Macro.t()) :: boolean()
  def behaviour_supervisor?({:@, _meta, [{:behaviour, _attr_meta, [{:__aliases__, _, [:Supervisor]}]}]}), do: true
  def behaviour_supervisor?({:@, _meta, [{:behaviour, _attr_meta, [Supervisor]}]}), do: true
  def behaviour_supervisor?(_), do: false

  @doc """
  Checks if a single AST node is a `@behaviour DynamicSupervisor` declaration.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "@behaviour DynamicSupervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.behaviour_dynamic_supervisor?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "@behaviour Supervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.behaviour_dynamic_supervisor?(ast)
      false
  """
  @spec behaviour_dynamic_supervisor?(Macro.t()) :: boolean()
  def behaviour_dynamic_supervisor?({:@, _meta, [{:behaviour, _attr_meta, [{:__aliases__, _, [:DynamicSupervisor]}]}]}), do: true
  def behaviour_dynamic_supervisor?({:@, _meta, [{:behaviour, _attr_meta, [DynamicSupervisor]}]}), do: true
  def behaviour_dynamic_supervisor?(_), do: false

  # ===========================================================================
  # Extraction
  # ===========================================================================

  @doc """
  Extracts Supervisor implementation details from a module body.

  Returns `{:ok, result}` if the module implements Supervisor or DynamicSupervisor,
  or `{:error, reason}` if it doesn't.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = SupervisorExtractor.extract(body)
      iex> result.supervisor_type
      :supervisor
      iex> result.detection_method
      :use

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use DynamicSupervisor, strategy: :one_for_one end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = SupervisorExtractor.extract(body)
      iex> result.supervisor_type
      :dynamic_supervisor
      iex> result.use_options
      [strategy: :one_for_one]

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do @behaviour Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = SupervisorExtractor.extract(body)
      iex> result.detection_method
      :behaviour
      iex> result.use_options
      nil

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do def foo, do: :ok end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.extract(body)
      {:error, "Module does not implement Supervisor"}
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(body, opts \\ []) do
    statements = Helpers.normalize_body(body)

    cond do
      uses_supervisor?(statements) ->
        extract_use_supervisor(statements, :supervisor, opts)

      uses_dynamic_supervisor?(statements) ->
        extract_use_supervisor(statements, :dynamic_supervisor, opts)

      declares_supervisor_behaviour?(statements) ->
        extract_behaviour_supervisor(statements, :supervisor, opts)

      declares_dynamic_supervisor_behaviour?(statements) ->
        extract_behaviour_supervisor(statements, :dynamic_supervisor, opts)

      true ->
        {:error, "Module does not implement Supervisor"}
    end
  end

  @doc """
  Extracts Supervisor implementation, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = SupervisorExtractor.extract!(body)
      iex> result.supervisor_type
      :supervisor
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
  Returns the supervisor type for the module body.

  Returns `:supervisor`, `:dynamic_supervisor`, or `nil` if not a supervisor.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.supervisor_type(body)
      :supervisor

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use DynamicSupervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.supervisor_type(body)
      :dynamic_supervisor

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.supervisor_type(body)
      nil
  """
  @spec supervisor_type(Macro.t()) :: supervisor_type() | nil
  def supervisor_type(body) do
    statements = Helpers.normalize_body(body)

    cond do
      uses_supervisor?(statements) or declares_supervisor_behaviour?(statements) ->
        :supervisor

      uses_dynamic_supervisor?(statements) or declares_dynamic_supervisor_behaviour?(statements) ->
        :dynamic_supervisor

      true ->
        nil
    end
  end

  @doc """
  Returns the detection method used for Supervisor in the module body.

  Returns `:use`, `:behaviour`, or `nil` if not a supervisor.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.detection_method(body)
      :use

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do @behaviour DynamicSupervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.detection_method(body)
      :behaviour

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.detection_method(body)
      nil
  """
  @spec detection_method(Macro.t()) :: :use | :behaviour | nil
  def detection_method(body) do
    statements = Helpers.normalize_body(body)

    cond do
      uses_supervisor?(statements) or uses_dynamic_supervisor?(statements) ->
        :use

      declares_supervisor_behaviour?(statements) or declares_dynamic_supervisor_behaviour?(statements) ->
        :behaviour

      true ->
        nil
    end
  end

  @doc """
  Extracts use options from a module body that uses Supervisor or DynamicSupervisor.

  Returns the keyword list of options, or `nil` if using @behaviour
  or if no options were provided.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use DynamicSupervisor, strategy: :one_for_one end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.use_options(body)
      [strategy: :one_for_one]

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.use_options(body)
      []

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do @behaviour Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.use_options(body)
      nil
  """
  @spec use_options(Macro.t()) :: keyword() | nil
  def use_options(body) do
    statements = Helpers.normalize_body(body)

    cond do
      uses_supervisor?(statements) ->
        find_use_options(statements, &use_supervisor?/1)

      uses_dynamic_supervisor?(statements) ->
        find_use_options(statements, &use_dynamic_supervisor?/1)

      true ->
        nil
    end
  end

  @doc """
  Checks if the module is a DynamicSupervisor.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use DynamicSupervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.dynamic_supervisor?(body)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use Supervisor end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.dynamic_supervisor?(body)
      false
  """
  @spec dynamic_supervisor?(Macro.t()) :: boolean()
  def dynamic_supervisor?(body) do
    supervisor_type(body) == :dynamic_supervisor
  end

  @doc """
  Returns the OTP behaviour type for this extractor.

  This is used when linking via `implementsOTPBehaviour`.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> SupervisorExtractor.otp_behaviour()
      :supervisor
  """
  @spec otp_behaviour() :: :supervisor
  def otp_behaviour, do: :supervisor

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp uses_supervisor?(statements) do
    Enum.any?(statements, &use_supervisor?/1)
  end

  defp uses_dynamic_supervisor?(statements) do
    Enum.any?(statements, &use_dynamic_supervisor?/1)
  end

  defp declares_supervisor_behaviour?(statements) do
    Enum.any?(statements, &behaviour_supervisor?/1)
  end

  defp declares_dynamic_supervisor_behaviour?(statements) do
    Enum.any?(statements, &behaviour_dynamic_supervisor?/1)
  end

  defp extract_use_supervisor(statements, sup_type, opts) do
    finder = if sup_type == :supervisor, do: &use_supervisor?/1, else: &use_dynamic_supervisor?/1
    use_node = Enum.find(statements, finder)
    location = Helpers.extract_location_if(use_node, opts)
    options = extract_use_options(use_node)

    {:ok,
     %__MODULE__{
       supervisor_type: sup_type,
       detection_method: :use,
       use_options: options,
       location: location,
       metadata: %{
         otp_behaviour: :supervisor,
         is_dynamic: sup_type == :dynamic_supervisor,
         has_options: options != []
       }
     }}
  end

  defp extract_behaviour_supervisor(statements, sup_type, opts) do
    finder =
      if sup_type == :supervisor,
        do: &behaviour_supervisor?/1,
        else: &behaviour_dynamic_supervisor?/1

    behaviour_node = Enum.find(statements, finder)
    location = Helpers.extract_location_if(behaviour_node, opts)

    {:ok,
     %__MODULE__{
       supervisor_type: sup_type,
       detection_method: :behaviour,
       use_options: nil,
       location: location,
       metadata: %{
         otp_behaviour: :supervisor,
         is_dynamic: sup_type == :dynamic_supervisor
       }
     }}
  end

  defp extract_use_options({:use, _meta, [{:__aliases__, _, [:Supervisor]}]}), do: []
  defp extract_use_options({:use, _meta, [Supervisor]}), do: []
  defp extract_use_options({:use, _meta, [{:__aliases__, _, [:Supervisor]}, opts]}) when is_list(opts), do: opts
  defp extract_use_options({:use, _meta, [Supervisor, opts]}) when is_list(opts), do: opts
  defp extract_use_options({:use, _meta, [{:__aliases__, _, [:DynamicSupervisor]}]}), do: []
  defp extract_use_options({:use, _meta, [DynamicSupervisor]}), do: []
  defp extract_use_options({:use, _meta, [{:__aliases__, _, [:DynamicSupervisor]}, opts]}) when is_list(opts), do: opts
  defp extract_use_options({:use, _meta, [DynamicSupervisor, opts]}) when is_list(opts), do: opts
  defp extract_use_options(_), do: []

  defp find_use_options(statements, finder) do
    case Enum.find(statements, finder) do
      nil -> nil
      node -> extract_use_options(node)
    end
  end
end
