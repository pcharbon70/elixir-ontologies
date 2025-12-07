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
  # Strategy Struct
  # ===========================================================================

  defmodule Strategy do
    @moduledoc """
    Represents a supervision strategy extracted from a Supervisor's init/1 callback.

    ## Strategy Types

    - `:one_for_one` - Only restart the failed child
    - `:one_for_all` - Restart all children on any failure
    - `:rest_for_one` - Restart failed child and all started after it

    ## Fields

    - `:type` - The strategy type atom
    - `:max_restarts` - Maximum restarts allowed in time window (default: 3)
    - `:max_seconds` - Time window in seconds (default: 5)
    - `:location` - Source location of the strategy
    - `:metadata` - Additional information
    """

    @type strategy_type :: :one_for_one | :one_for_all | :rest_for_one

    @type t :: %__MODULE__{
            type: strategy_type(),
            max_restarts: non_neg_integer() | nil,
            max_seconds: non_neg_integer() | nil,
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct type: :one_for_one,
              max_restarts: nil,
              max_seconds: nil,
              location: nil,
              metadata: %{}
  end

  # ===========================================================================
  # ChildSpec Struct
  # ===========================================================================

  defmodule ChildSpec do
    @moduledoc """
    Represents a child specification extracted from a Supervisor's init/1 callback.

    ## Restart Types

    - `:permanent` - Always restart (default)
    - `:temporary` - Never restart
    - `:transient` - Restart only on abnormal exit

    ## Shutdown Types

    - integer - Timeout in milliseconds
    - `:infinity` - Wait forever
    - `:brutal_kill` - Kill immediately

    ## Fields

    - `:id` - Child identifier (usually module name)
    - `:module` - Module implementing the child
    - `:restart` - Restart policy
    - `:shutdown` - Shutdown strategy
    - `:type` - Child type (:worker or :supervisor)
    - `:location` - Source location
    - `:metadata` - Additional information
    """

    @type restart_type :: :permanent | :temporary | :transient
    @type shutdown_type :: non_neg_integer() | :infinity | :brutal_kill
    @type child_type :: :worker | :supervisor

    @type t :: %__MODULE__{
            id: atom() | term(),
            module: atom() | nil,
            restart: restart_type(),
            shutdown: shutdown_type() | nil,
            type: child_type(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct id: nil,
              module: nil,
              restart: :permanent,
              shutdown: nil,
              type: :worker,
              location: nil,
              metadata: %{}
  end

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

  defstruct supervisor_type: :supervisor,
            detection_method: :use,
            use_options: nil,
            location: nil,
            metadata: %{}

  # ===========================================================================
  # Generic Use/Behaviour Detection Helpers
  # ===========================================================================

  @doc """
  Checks if a single AST node is a `use Module` invocation for the given module.

  This is a generic helper that reduces duplication in module detection.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "use Supervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.use_module?(ast, :Supervisor)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "use GenServer"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.use_module?(ast, :Supervisor)
      false
  """
  @spec use_module?(Macro.t(), atom()) :: boolean()
  def use_module?({:use, _meta, [{:__aliases__, _, [module_name]} | _opts]}, target)
      when module_name == target,
      do: true

  def use_module?({:use, _meta, [module_atom | _opts]}, target)
      when is_atom(module_atom) and module_atom == target,
      do: true

  def use_module?(_, _), do: false

  @doc """
  Checks if a single AST node is a `@behaviour Module` declaration for the given module.

  This is a generic helper that reduces duplication in behaviour detection.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "@behaviour Supervisor"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.behaviour_module?(ast, :Supervisor)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "@behaviour GenServer"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.behaviour_module?(ast, :Supervisor)
      false
  """
  @spec behaviour_module?(Macro.t(), atom()) :: boolean()
  def behaviour_module?(
        {:@, _meta, [{:behaviour, _attr_meta, [{:__aliases__, _, [module_name]}]}]},
        target
      )
      when module_name == target,
      do: true

  def behaviour_module?({:@, _meta, [{:behaviour, _attr_meta, [module_atom]}]}, target)
      when is_atom(module_atom) and module_atom == target,
      do: true

  def behaviour_module?(_, _), do: false

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
  def use_supervisor?(ast), do: use_module?(ast, :Supervisor)

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
  def use_dynamic_supervisor?(ast), do: use_module?(ast, :DynamicSupervisor)

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
  def behaviour_supervisor?(ast), do: behaviour_module?(ast, :Supervisor)

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
  def behaviour_dynamic_supervisor?(ast), do: behaviour_module?(ast, :DynamicSupervisor)

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

      declares_supervisor_behaviour?(statements) or
          declares_dynamic_supervisor_behaviour?(statements) ->
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

  # Generic helper to extract options from any use statement
  defp extract_use_options({:use, _meta, [{:__aliases__, _, [_module]}]}), do: []
  defp extract_use_options({:use, _meta, [module]}) when is_atom(module), do: []

  defp extract_use_options({:use, _meta, [{:__aliases__, _, [_module]}, opts]})
       when is_list(opts),
       do: opts

  defp extract_use_options({:use, _meta, [module, opts]}) when is_atom(module) and is_list(opts),
    do: opts

  defp extract_use_options(_), do: []

  defp find_use_options(statements, finder) do
    case Enum.find(statements, finder) do
      nil -> nil
      node -> extract_use_options(node)
    end
  end

  # ===========================================================================
  # Strategy Extraction
  # ===========================================================================

  @doc """
  Extracts the supervision strategy from a module body.

  Parses the `init/1` callback to find the strategy used.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = ~S'''
      ...> defmodule MySup do
      ...>   use Supervisor
      ...>   def init(_) do
      ...>     Supervisor.init([], strategy: :one_for_one)
      ...>   end
      ...> end
      ...> '''
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, strategy} = SupervisorExtractor.extract_strategy(body)
      iex> strategy.type
      :one_for_one

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.extract_strategy(body)
      {:error, "No supervision strategy found"}
  """
  @spec extract_strategy(Macro.t(), keyword()) :: {:ok, Strategy.t()} | {:error, String.t()}
  def extract_strategy(body, opts \\ []) do
    statements = Helpers.normalize_body(body)

    case find_init_callback(statements) do
      nil ->
        {:error, "No supervision strategy found"}

      init_ast ->
        case extract_strategy_from_init(init_ast, opts) do
          nil -> {:error, "No supervision strategy found"}
          strategy -> {:ok, strategy}
        end
    end
  end

  @doc """
  Extracts the supervision strategy, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = ~S'''
      ...> defmodule MySup do
      ...>   use Supervisor
      ...>   def init(_) do
      ...>     Supervisor.init([], strategy: :one_for_all)
      ...>   end
      ...> end
      ...> '''
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> strategy = SupervisorExtractor.extract_strategy!(body)
      iex> strategy.type
      :one_for_all
  """
  @spec extract_strategy!(Macro.t(), keyword()) :: Strategy.t()
  def extract_strategy!(body, opts \\ []) do
    case extract_strategy(body, opts) do
      {:ok, strategy} -> strategy
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Returns the strategy type from a module body.

  Returns `:one_for_one`, `:one_for_all`, `:rest_for_one`, or `nil`.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = ~S'''
      ...> defmodule MySup do
      ...>   use Supervisor
      ...>   def init(_) do
      ...>     Supervisor.init([], strategy: :rest_for_one)
      ...>   end
      ...> end
      ...> '''
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.strategy_type(body)
      :rest_for_one
  """
  @spec strategy_type(Macro.t()) :: Strategy.strategy_type() | nil
  def strategy_type(body) do
    case extract_strategy(body) do
      {:ok, strategy} -> strategy.type
      {:error, _} -> nil
    end
  end

  @doc """
  Checks if a strategy is one_for_one.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.Strategy
      iex> SupervisorExtractor.one_for_one?(%Strategy{type: :one_for_one})
      true

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.Strategy
      iex> SupervisorExtractor.one_for_one?(%Strategy{type: :one_for_all})
      false
  """
  @spec one_for_one?(Strategy.t()) :: boolean()
  def one_for_one?(%Strategy{type: :one_for_one}), do: true
  def one_for_one?(_), do: false

  @doc """
  Checks if a strategy is one_for_all.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.Strategy
      iex> SupervisorExtractor.one_for_all?(%Strategy{type: :one_for_all})
      true
  """
  @spec one_for_all?(Strategy.t()) :: boolean()
  def one_for_all?(%Strategy{type: :one_for_all}), do: true
  def one_for_all?(_), do: false

  @doc """
  Checks if a strategy is rest_for_one.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.Strategy
      iex> SupervisorExtractor.rest_for_one?(%Strategy{type: :rest_for_one})
      true
  """
  @spec rest_for_one?(Strategy.t()) :: boolean()
  def rest_for_one?(%Strategy{type: :rest_for_one}), do: true
  def rest_for_one?(_), do: false

  # ===========================================================================
  # Child Spec Extraction
  # ===========================================================================

  @doc """
  Extracts child specifications from a module body.

  Parses the `init/1` callback to find the children list.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = ~S'''
      ...> defmodule MySup do
      ...>   use Supervisor
      ...>   def init(_) do
      ...>     children = [
      ...>       {MyWorker, []}
      ...>     ]
      ...>     Supervisor.init(children, strategy: :one_for_one)
      ...>   end
      ...> end
      ...> '''
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, children} = SupervisorExtractor.extract_children(body)
      iex> length(children)
      1
      iex> hd(children).module
      MyWorker

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = "defmodule S do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.extract_children(body)
      {:ok, []}
  """
  @spec extract_children(Macro.t(), keyword()) :: {:ok, [ChildSpec.t()]} | {:error, String.t()}
  def extract_children(body, opts \\ []) do
    statements = Helpers.normalize_body(body)

    case find_init_callback(statements) do
      nil ->
        {:ok, []}

      init_ast ->
        children = extract_children_from_init(init_ast, opts)
        {:ok, children}
    end
  end

  @doc """
  Extracts child specifications, raising on error.
  """
  @spec extract_children!(Macro.t(), keyword()) :: [ChildSpec.t()]
  def extract_children!(body, opts \\ []) do
    {:ok, children} = extract_children(body, opts)
    children
  end

  @doc """
  Returns the number of children defined in a module body.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> code = ~S'''
      ...> defmodule MySup do
      ...>   use Supervisor
      ...>   def init(_) do
      ...>     children = [
      ...>       {Worker1, []},
      ...>       {Worker2, []}
      ...>     ]
      ...>     Supervisor.init(children, strategy: :one_for_one)
      ...>   end
      ...> end
      ...> '''
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> SupervisorExtractor.child_count(body)
      2
  """
  @spec child_count(Macro.t()) :: non_neg_integer()
  def child_count(body) do
    {:ok, children} = extract_children(body)
    length(children)
  end

  @doc """
  Checks if a child spec has permanent restart.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
      iex> SupervisorExtractor.permanent?(%ChildSpec{restart: :permanent})
      true

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
      iex> SupervisorExtractor.permanent?(%ChildSpec{restart: :temporary})
      false
  """
  @spec permanent?(ChildSpec.t()) :: boolean()
  def permanent?(%ChildSpec{restart: :permanent}), do: true
  def permanent?(_), do: false

  @doc """
  Checks if a child spec has temporary restart.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
      iex> SupervisorExtractor.temporary?(%ChildSpec{restart: :temporary})
      true
  """
  @spec temporary?(ChildSpec.t()) :: boolean()
  def temporary?(%ChildSpec{restart: :temporary}), do: true
  def temporary?(_), do: false

  @doc """
  Checks if a child spec has transient restart.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
      iex> SupervisorExtractor.transient?(%ChildSpec{restart: :transient})
      true
  """
  @spec transient?(ChildSpec.t()) :: boolean()
  def transient?(%ChildSpec{restart: :transient}), do: true
  def transient?(_), do: false

  # ===========================================================================
  # Strategy Extraction Helpers
  # ===========================================================================

  defp find_init_callback(statements) do
    Enum.find(statements, fn
      {:def, _, [{:init, _, _} | _]} -> true
      {:def, _, [{:when, _, [{:init, _, _} | _]} | _]} -> true
      _ -> false
    end)
  end

  defp extract_strategy_from_init({:def, _meta, [{:init, _, _}, body_clause]}, opts) do
    extract_strategy_from_body(body_clause, opts)
  end

  defp extract_strategy_from_init(
         {:def, _meta, [{:when, _, [{:init, _, _} | _]}, body_clause]},
         opts
       ) do
    extract_strategy_from_body(body_clause, opts)
  end

  defp extract_strategy_from_init(_, _opts), do: nil

  defp extract_strategy_from_body([do: body], opts), do: extract_strategy_from_body(body, opts)

  defp extract_strategy_from_body({:__block__, _, statements}, opts) do
    # Search through block for Supervisor.init call
    Enum.find_value(statements, fn stmt ->
      extract_strategy_from_statement(stmt, opts)
    end)
  end

  defp extract_strategy_from_body(body, opts) do
    extract_strategy_from_statement(body, opts)
  end

  # Supervisor.init(children, strategy: :one_for_one)
  defp extract_strategy_from_statement(
         {{:., _, [{:__aliases__, _, [:Supervisor]}, :init]}, meta, [_children, options]},
         opts
       ) do
    build_strategy_from_options(options, meta, :supervisor_init, opts)
  end

  # DynamicSupervisor.init(strategy: :one_for_one)
  defp extract_strategy_from_statement(
         {{:., _, [{:__aliases__, _, [:DynamicSupervisor]}, :init]}, meta, [options]},
         opts
       )
       when is_list(options) do
    build_strategy_from_options(options, meta, :dynamic_supervisor_init, opts)
  end

  # {:ok, {spec, children}} return format
  defp extract_strategy_from_statement(
         {:ok, {{strategy, max_restarts, max_seconds}, _children}},
         opts
       )
       when strategy in [:one_for_one, :one_for_all, :rest_for_one] do
    location = Helpers.extract_location_if(nil, opts)

    %Strategy{
      type: strategy,
      max_restarts: max_restarts,
      max_seconds: max_seconds,
      location: location,
      metadata: %{
        source: :tuple_return,
        has_max_restarts: true,
        has_max_seconds: true
      }
    }
  end

  defp extract_strategy_from_statement(_, _opts), do: nil

  # Common helper to build Strategy from keyword options
  defp build_strategy_from_options(options, meta, source, opts) do
    strategy = Keyword.get(options, :strategy, :one_for_one)
    max_restarts = Keyword.get(options, :max_restarts)
    max_seconds = Keyword.get(options, :max_seconds)
    location = Helpers.extract_location_if({:call, meta, []}, opts)

    %Strategy{
      type: strategy,
      max_restarts: max_restarts,
      max_seconds: max_seconds,
      location: location,
      metadata: %{
        source: source,
        has_max_restarts: max_restarts != nil,
        has_max_seconds: max_seconds != nil
      }
    }
  end

  # ===========================================================================
  # Child Spec Extraction Helpers
  # ===========================================================================

  defp extract_children_from_init({:def, _meta, [{:init, _, _}, body_clause]}, opts) do
    extract_children_from_body(body_clause, opts)
  end

  defp extract_children_from_init(
         {:def, _meta, [{:when, _, [{:init, _, _} | _]}, body_clause]},
         opts
       ) do
    extract_children_from_body(body_clause, opts)
  end

  defp extract_children_from_init(_, _opts), do: []

  defp extract_children_from_body([do: body], opts), do: extract_children_from_body(body, opts)

  defp extract_children_from_body({:__block__, _, statements}, opts) do
    # Look for children = [...] assignment or direct Supervisor.init call
    children_from_assignment = find_children_assignment(statements, opts)
    children_from_init = find_children_in_supervisor_init(statements, opts)

    (children_from_assignment ++ children_from_init)
    |> Enum.uniq_by(fn spec -> spec.id || spec.module end)
  end

  defp extract_children_from_body(body, opts) do
    find_children_in_supervisor_init([body], opts)
  end

  defp find_children_assignment(statements, opts) do
    Enum.find_value(statements, [], fn
      {:=, _, [{:children, _, _}, children_list]} when is_list(children_list) ->
        Enum.map(children_list, &parse_child_spec(&1, opts))

      {:=, _, [{:children, _, _}, {:__block__, _, _} = block]} ->
        # Handle case where children is assigned a block
        extract_children_list_from_block(block, opts)

      _ ->
        nil
    end)
  end

  defp extract_children_list_from_block({:__block__, _, items}, opts) do
    # If it's a list wrapped in a block
    case items do
      [list] when is_list(list) -> Enum.map(list, &parse_child_spec(&1, opts))
      _ -> []
    end
  end

  defp find_children_in_supervisor_init(statements, opts) do
    Enum.find_value(statements, [], fn
      # Supervisor.init(children_list, opts) where children_list is inline
      {{:., _, [{:__aliases__, _, [:Supervisor]}, :init]}, _, [children_list, _opts]}
      when is_list(children_list) ->
        Enum.map(children_list, &parse_child_spec(&1, opts))

      # Supervisor.init(children_var, opts) where children_var is a variable
      {{:., _, [{:__aliases__, _, [:Supervisor]}, :init]}, _, [{:children, _, _}, _opts]} ->
        # Already handled by find_children_assignment
        nil

      _ ->
        nil
    end)
  end

  # Parse {Module, args} tuple
  defp parse_child_spec({{:__aliases__, meta, module_parts}, args}, opts) do
    module = Module.concat(module_parts)
    location = Helpers.extract_location_if({:tuple, meta, []}, opts)

    # Extract options if args is a keyword list with restart/shutdown
    {restart, shutdown, type} = extract_child_options(args)

    %ChildSpec{
      id: module,
      module: module,
      restart: restart,
      shutdown: shutdown,
      type: type,
      location: location,
      metadata: %{
        format: :tuple,
        has_args: args != []
      }
    }
  end

  # Parse %{id: ..., start: ...} map spec
  defp parse_child_spec({:%{}, meta, pairs}, opts) when is_list(pairs) do
    location = Helpers.extract_location_if({:map, meta, []}, opts)
    id = Keyword.get(pairs, :id)
    start = Keyword.get(pairs, :start)
    restart = Keyword.get(pairs, :restart, :permanent)
    shutdown = Keyword.get(pairs, :shutdown)
    type = Keyword.get(pairs, :type, :worker)

    # Extract module from start tuple - AST tuple format must be checked first
    # because {:{}, meta, args} would match {module, _fun, _args} where :{} is an atom
    module =
      case start do
        # Handle AST tuple format {:{}, meta, [module, fun, args]}
        {:{}, _, [{:__aliases__, _, parts}, _fun, _args]} -> Module.concat(parts)
        {:{}, _, [module, _fun, _args]} when is_atom(module) -> module
        # Regular evaluated tuples
        {module, _fun, _args} when is_atom(module) -> module
        {{:__aliases__, _, parts}, _fun, _args} -> Module.concat(parts)
        _ -> nil
      end

    %ChildSpec{
      id: id,
      module: module,
      restart: restart,
      shutdown: shutdown,
      type: type,
      location: location,
      metadata: %{
        format: :map,
        has_start: start != nil
      }
    }
  end

  # Parse Module atom (shorthand)
  defp parse_child_spec({:__aliases__, meta, module_parts}, opts) do
    module = Module.concat(module_parts)
    location = Helpers.extract_location_if({:alias, meta, []}, opts)

    %ChildSpec{
      id: module,
      module: module,
      restart: :permanent,
      shutdown: nil,
      type: :worker,
      location: location,
      metadata: %{
        format: :module_only
      }
    }
  end

  # Fallback for unrecognized formats
  defp parse_child_spec(_ast, _opts) do
    %ChildSpec{
      id: :unknown,
      module: nil,
      restart: :permanent,
      shutdown: nil,
      type: :worker,
      location: nil,
      metadata: %{
        format: :unknown
      }
    }
  end

  defp extract_child_options(args) when is_list(args) do
    # Check if args is a keyword list with options
    if Keyword.keyword?(args) do
      restart = Keyword.get(args, :restart, :permanent)
      shutdown = Keyword.get(args, :shutdown)
      type = Keyword.get(args, :type, :worker)
      {restart, shutdown, type}
    else
      {:permanent, nil, :worker}
    end
  end

  defp extract_child_options(_), do: {:permanent, nil, :worker}
end
