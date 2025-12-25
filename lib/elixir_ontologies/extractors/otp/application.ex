defmodule ElixirOntologies.Extractors.OTP.Application do
  @moduledoc """
  Extracts Application modules and their root supervisor configuration from AST nodes.

  This module analyzes Elixir AST nodes to detect modules implementing the Application
  behaviour. It extracts the root supervisor started in the `start/2` callback.

  ## Detection Methods

  Application implementations can be detected via two patterns:

  1. `use Application` - Macro invocation that injects Application behaviour
  2. `@behaviour Application` - Direct behaviour declaration

  ## Supervisor Patterns

  Applications typically start a supervision tree in one of two ways:

  ### Pattern 1: Inline Supervisor (most common)

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [Worker1, Worker2]
          opts = [strategy: :one_for_one, name: MyApp.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end

  ### Pattern 2: Dedicated Supervisor Module

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          MyApp.Supervisor.start_link(name: MyApp.Supervisor)
        end
      end

  ## Usage

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule MyApp do use Application end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AppExtractor.application?(body)
      true

  ## Extracting Application Details

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = \"""
      ...> defmodule MyApp do
      ...>   use Application
      ...>   def start(_type, _args) do
      ...>     Supervisor.start_link([], strategy: :one_for_one, name: MyApp.Supervisor)
      ...>   end
      ...> end
      ...> \"""
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = AppExtractor.extract(body)
      iex> result.supervisor_name
      {:__aliases__, [line: 4], [:MyApp, :Supervisor]}
      iex> result.uses_inline_supervisor
      true
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # ApplicationSupervisor Struct
  # ===========================================================================

  @typedoc """
  Application supervisor extraction result.

  - `:app_module` - The Application module alias (from AST, if available)
  - `:supervisor_module` - The root supervisor module (if using dedicated module)
  - `:supervisor_name` - The :name option passed to Supervisor.start_link
  - `:supervisor_strategy` - Strategy if using inline supervisor
  - `:uses_inline_supervisor` - True if supervisor is started inline
  - `:detection_method` - How Application was detected (:use or :behaviour)
  - `:location` - Source location of the start/2 callback
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          app_module: atom() | nil,
          supervisor_module: atom() | tuple() | nil,
          supervisor_name: atom() | tuple() | nil,
          supervisor_strategy: atom() | nil,
          uses_inline_supervisor: boolean(),
          detection_method: :use | :behaviour,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct app_module: nil,
            supervisor_module: nil,
            supervisor_name: nil,
            supervisor_strategy: nil,
            uses_inline_supervisor: false,
            detection_method: :use,
            location: nil,
            metadata: %{}

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if a module body implements Application (via `use` or `@behaviour`).

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule MyApp do use Application end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AppExtractor.application?(body)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule MyApp do @behaviour Application end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AppExtractor.application?(body)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule MyApp do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AppExtractor.application?(body)
      false
  """
  @spec application?(Macro.t()) :: boolean()
  def application?(body) do
    uses_application?(body) or has_application_behaviour?(body)
  end

  @doc """
  Checks if a module body uses `use Application`.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule MyApp do use Application end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AppExtractor.uses_application?(body)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule MyApp do @behaviour Application end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AppExtractor.uses_application?(body)
      false
  """
  @spec uses_application?(Macro.t()) :: boolean()
  def uses_application?(body) do
    statements = Helpers.normalize_body(body)
    Enum.any?(statements, &use_application?/1)
  end

  @doc """
  Checks if a single AST node is a `use Application` invocation.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "use Application"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AppExtractor.use_application?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "use GenServer"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AppExtractor.use_application?(ast)
      false
  """
  @spec use_application?(Macro.t()) :: boolean()
  def use_application?(ast), do: Helpers.use_module?(ast, :Application)

  @doc """
  Checks if a module body has `@behaviour Application`.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule MyApp do @behaviour Application end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AppExtractor.has_application_behaviour?(body)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule MyApp do use Application end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AppExtractor.has_application_behaviour?(body)
      false
  """
  @spec has_application_behaviour?(Macro.t()) :: boolean()
  def has_application_behaviour?(body) do
    statements = Helpers.normalize_body(body)
    Enum.any?(statements, &behaviour_application?/1)
  end

  @doc """
  Checks if a single AST node is a `@behaviour Application` declaration.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "@behaviour Application"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AppExtractor.behaviour_application?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "@behaviour GenServer"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> AppExtractor.behaviour_application?(ast)
      false
  """
  @spec behaviour_application?(Macro.t()) :: boolean()
  def behaviour_application?(ast), do: Helpers.behaviour_module?(ast, :Application)

  # ===========================================================================
  # Extraction
  # ===========================================================================

  @doc """
  Extracts Application supervisor configuration from a module body.

  Returns `{:ok, %ApplicationSupervisor{}}` if the module implements Application,
  or `{:error, reason}` otherwise.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule MyApp do use Application end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = AppExtractor.extract(body)
      iex> result.detection_method
      :use

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule NotApp do use GenServer end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:error, msg} = AppExtractor.extract(body)
      iex> msg
      "Module does not implement Application"
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(body, opts \\ []) do
    cond do
      uses_application?(body) ->
        do_extract(body, :use, opts)

      has_application_behaviour?(body) ->
        do_extract(body, :behaviour, opts)

      true ->
        {:error, "Module does not implement Application"}
    end
  end

  @doc """
  Extracts Application supervisor configuration, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule MyApp do use Application end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = AppExtractor.extract!(body)
      iex> result.detection_method
      :use
  """
  @spec extract!(Macro.t(), keyword()) :: t()
  def extract!(body, opts \\ []) do
    case extract(body, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Failed to extract Application: #{reason}"
    end
  end

  # ===========================================================================
  # Start Callback Extraction
  # ===========================================================================

  @doc """
  Extracts the start/2 callback function from a module body.

  Returns the function AST if found, or nil if not present.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = \"""
      ...> defmodule MyApp do
      ...>   use Application
      ...>   def start(_type, _args), do: {:ok, self()}
      ...> end
      ...> \"""
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> start_fn = AppExtractor.extract_start_callback(body)
      iex> match?({:def, _, [{:start, _, _} | _]}, start_fn)
      true

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = "defmodule MyApp do use Application end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> AppExtractor.extract_start_callback(body)
      nil
  """
  @spec extract_start_callback(Macro.t()) :: Macro.t() | nil
  def extract_start_callback(body) do
    statements = Helpers.normalize_body(body)

    Enum.find(statements, fn
      # Pattern match for exactly 2 args (more efficient than length/1)
      {:def, _, [{:start, _, [_, _]} | _]} -> true
      _ -> false
    end)
  end

  @doc """
  Extracts all clauses of the start/2 callback function.

  Returns a list of function clause ASTs.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor
      iex> code = \"""
      ...> defmodule MyApp do
      ...>   use Application
      ...>   def start(:normal, args), do: do_start(args)
      ...>   def start(:takeover, args), do: do_takeover(args)
      ...> end
      ...> \"""
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> clauses = AppExtractor.extract_start_clauses(body)
      iex> length(clauses)
      2
  """
  @spec extract_start_clauses(Macro.t()) :: [Macro.t()]
  def extract_start_clauses(body) do
    statements = Helpers.normalize_body(body)

    Enum.filter(statements, fn
      # Pattern match for exactly 2 args (more efficient than length/1)
      {:def, _, [{:start, _, [_, _]} | _]} -> true
      _ -> false
    end)
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp do_extract(body, detection_method, opts) do
    start_callback = extract_start_callback(body)
    # Use Helpers.extract_location_if for consistent location extraction
    location = Helpers.extract_location_if(start_callback, opts)

    supervisor_info = extract_supervisor_info(start_callback)

    result = %__MODULE__{
      detection_method: detection_method,
      location: location,
      supervisor_module: supervisor_info[:supervisor_module],
      supervisor_name: supervisor_info[:supervisor_name],
      supervisor_strategy: supervisor_info[:supervisor_strategy],
      uses_inline_supervisor: supervisor_info[:uses_inline_supervisor] || false,
      metadata: %{
        has_start_callback: start_callback != nil
      }
    }

    {:ok, result}
  end

  defp extract_supervisor_info(nil), do: %{}

  defp extract_supervisor_info({:def, _, [_, body_clause]}) do
    # Extract the function body
    body =
      case body_clause do
        [do: body] -> body
        _ -> nil
      end

    analyze_start_body(body)
  end

  defp analyze_start_body(nil), do: %{}

  defp analyze_start_body({:__block__, _, statements}) do
    # Find the last expression (typically the return value)
    # Or find Supervisor.start_link call
    supervisor_call = find_supervisor_call(statements)
    analyze_supervisor_call(supervisor_call)
  end

  defp analyze_start_body(single_expr) do
    analyze_supervisor_call(single_expr)
  end

  defp find_supervisor_call(statements) when is_list(statements) do
    # Look for Supervisor.start_link or Module.start_link calls
    Enum.find(statements, fn stmt ->
      match_supervisor_call?(stmt)
    end) || List.last(statements)
  end

  defp match_supervisor_call?({{:., _, [{:__aliases__, _, [:Supervisor]}, :start_link]}, _, _}),
    do: true

  defp match_supervisor_call?({{:., _, [_, :start_link]}, _, _}), do: true
  defp match_supervisor_call?(_), do: false

  defp analyze_supervisor_call(nil), do: %{}

  # Supervisor.start_link(children, opts) - inline supervisor
  defp analyze_supervisor_call(
         {{:., _, [{:__aliases__, _, [:Supervisor]}, :start_link]}, _, [_children, opts]}
       ) do
    {name, strategy} = extract_supervisor_opts(opts)

    %{
      uses_inline_supervisor: true,
      supervisor_name: name,
      supervisor_strategy: strategy
    }
  end

  # Supervisor.start_link(children, opts) - with keyword list inline
  defp analyze_supervisor_call(
         {{:., _, [{:__aliases__, _, [:Supervisor]}, :start_link]}, _, [_children | rest]}
       )
       when is_list(rest) do
    opts = List.first(rest) || []
    {name, strategy} = extract_supervisor_opts(opts)

    %{
      uses_inline_supervisor: true,
      supervisor_name: name,
      supervisor_strategy: strategy
    }
  end

  # Module.start_link(...) - dedicated supervisor module
  defp analyze_supervisor_call({{:., _, [module_alias, :start_link]}, _, args}) do
    opts = extract_opts_from_args(args)
    {name, _strategy} = extract_supervisor_opts(opts)

    %{
      uses_inline_supervisor: false,
      supervisor_module: module_alias,
      supervisor_name: name
    }
  end

  # Simple function call or other patterns
  defp analyze_supervisor_call(_), do: %{}

  # Extract keyword options from function arguments
  defp extract_opts_from_args([]), do: []
  defp extract_opts_from_args([opts]) when is_list(opts), do: opts
  # Single non-list element - no options
  defp extract_opts_from_args([_single]), do: []
  # Multiple elements - recurse to find options in later args
  defp extract_opts_from_args([_ | rest]) when rest != [], do: extract_opts_from_args(rest)

  defp extract_supervisor_opts(opts) when is_list(opts) do
    name = Keyword.get(opts, :name)
    strategy = Keyword.get(opts, :strategy)
    {name, strategy}
  end

  defp extract_supervisor_opts(_), do: {nil, nil}
end
