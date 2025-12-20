defmodule ElixirOntologies.Extractors.Directive.Use do
  @moduledoc """
  Extracts use directive information from Elixir AST.

  This module provides detailed extraction of use directives which invoke
  the `__using__/1` macro of a module, allowing modules to inject code at compile time.

  ## Use Forms

  Elixir supports several use forms:

      # Basic use - invokes GenServer.__using__([])
      use GenServer

      # Use with keyword options - passed to __using__/1
      use GenServer, restart: :temporary

      # Use with multiple keyword options
      use Plug.Builder, init_mode: :runtime, log_on_halt: :debug

      # Use with non-keyword option (common in Phoenix)
      use MyApp.Web, :controller

  ## Examples

      iex> ast = {:use, [line: 1], [{:__aliases__, [line: 1], [:GenServer]}]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Use.extract(ast)
      iex> directive.module
      [:GenServer]
      iex> directive.options
      nil

      iex> ast = {:use, [line: 1], [{:__aliases__, [line: 1], [:GenServer]}, [restart: :temporary]]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Use.extract(ast)
      iex> directive.options
      [restart: :temporary]
  """

  alias ElixirOntologies.Extractors.Helpers
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # ===========================================================================
  # Struct Definition
  # ===========================================================================

  defmodule UseDirective do
    @moduledoc """
    Represents an extracted use directive.

    ## Fields

    - `:module` - The module being used as a list of atoms
    - `:options` - Options passed to `__using__/1` (keyword list, single value, or nil)
    - `:location` - Source location of the directive
    - `:scope` - Lexical scope (:module, :function, :block)
    - `:metadata` - Additional metadata
    """

    @type use_options :: keyword() | term() | nil

    @type t :: %__MODULE__{
            module: [atom()] | atom(),
            options: use_options(),
            location: SourceLocation.t() | nil,
            scope: :module | :function | :block | nil,
            metadata: map()
          }

    @enforce_keys [:module]
    defstruct [:module, :options, :location, :scope, metadata: %{}]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if the given AST node represents a use directive.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Use.use?({:use, [], [{:__aliases__, [], [:GenServer]}]})
      true

      iex> ElixirOntologies.Extractors.Directive.Use.use?({:require, [], [{:__aliases__, [], [:Logger]}]})
      false

      iex> ElixirOntologies.Extractors.Directive.Use.use?(:not_a_use)
      false
  """
  @spec use?(Macro.t()) :: boolean()
  def use?({:use, _meta, [_ | _]}), do: true
  def use?(_), do: false

  # ===========================================================================
  # Extraction Functions
  # ===========================================================================

  @doc """
  Extracts use directive information from an AST node.

  Returns `{:ok, %UseDirective{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:use, [line: 5], [{:__aliases__, [line: 5], [:GenServer]}]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Use.extract(ast)
      iex> directive.module
      [:GenServer]
      iex> directive.options
      nil

      iex> ast = {:use, [], [{:__aliases__, [], [:GenServer]}, [restart: :temporary]]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Use.extract(ast)
      iex> directive.options
      [restart: :temporary]

      iex> ast = {:use, [], [{:__aliases__, [], [:MyApp, :Web]}, :controller]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Use.extract(ast)
      iex> directive.options
      :controller
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, UseDirective.t()} | {:error, term()}
  def extract(ast, opts \\ [])

  # Basic use: use Module
  def extract({:use, _meta, [{:__aliases__, _, parts}]} = node, opts)
      when is_list(parts) do
    build_directive(parts, nil, node, opts)
  end

  # Use with options: use Module, options
  def extract({:use, _meta, [{:__aliases__, _, parts}, use_opts]} = node, opts)
      when is_list(parts) do
    build_directive(parts, use_opts, node, opts)
  end

  # Erlang module: use :module (rare but possible)
  def extract({:use, _meta, [module]} = node, opts) when is_atom(module) do
    build_directive([module], nil, node, opts)
  end

  # Erlang module with options
  def extract({:use, _meta, [module, use_opts]} = node, opts)
      when is_atom(module) do
    build_directive([module], use_opts, node, opts)
  end

  def extract(ast, _opts) do
    {:error, {:not_a_use, Helpers.format_error("Not a use directive", ast)}}
  end

  @doc """
  Extracts use directive information, raising on error.

  ## Examples

      iex> ast = {:use, [], [{:__aliases__, [], [:GenServer]}]}
      iex> directive = ElixirOntologies.Extractors.Directive.Use.extract!(ast)
      iex> directive.module
      [:GenServer]
  """
  @spec extract!(Macro.t(), keyword()) :: UseDirective.t()
  def extract!(ast, opts \\ []) do
    case extract(ast, opts) do
      {:ok, directive} -> directive
      {:error, reason} -> raise ArgumentError, "Failed to extract use: #{inspect(reason)}"
    end
  end

  @doc """
  Extracts all use directives from a module body or list of statements.

  ## Examples

      iex> body = [
      ...>   {:use, [], [{:__aliases__, [], [:GenServer]}]},
      ...>   {:use, [], [{:__aliases__, [], [:Supervisor]}]},
      ...>   {:def, [], [{:foo, [], nil}, [do: :ok]]}
      ...> ]
      iex> directives = ElixirOntologies.Extractors.Directive.Use.extract_all(body)
      iex> length(directives)
      2
      iex> Enum.map(directives, & &1.module)
      [[:GenServer], [:Supervisor]]
  """
  @spec extract_all(Macro.t(), keyword()) :: [UseDirective.t()]
  def extract_all(ast, opts \\ [])

  def extract_all(statements, opts) when is_list(statements) do
    statements
    |> Enum.filter(&use?/1)
    |> Enum.flat_map(&do_extract_all(&1, opts))
  end

  def extract_all({:__block__, _meta, statements}, opts) do
    extract_all(statements, opts)
  end

  def extract_all(ast, opts) do
    if use?(ast) do
      do_extract_all(ast, opts)
    else
      []
    end
  end

  # ===========================================================================
  # Scope-Aware Extraction
  # ===========================================================================

  @doc """
  Extracts all use directives from a module body with scope tracking.

  This function walks the AST and tracks the lexical scope of each use,
  setting the `:scope` field to `:module`, `:function`, or `:block`.

  Note: `use` is typically only valid at module level, but this function
  tracks scope for completeness.

  ## Examples

      iex> {:defmodule, _, [_, [do: {:__block__, _, body}]]} = quote do
      ...>   defmodule Test do
      ...>     use GenServer
      ...>     use Supervisor
      ...>   end
      ...> end
      iex> directives = ElixirOntologies.Extractors.Directive.Use.extract_all_with_scope(body)
      iex> length(directives)
      2
      iex> Enum.all?(directives, & &1.scope == :module)
      true
  """
  @spec extract_all_with_scope(Macro.t(), keyword()) :: [UseDirective.t()]
  def extract_all_with_scope(ast, opts \\ []) do
    extract_with_scope(ast, :module, opts)
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Returns the used module as a dot-separated string.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{
      ...>   module: [:GenServer]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Use.module_name(directive)
      "GenServer"

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{
      ...>   module: [:Plug, :Builder]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Use.module_name(directive)
      "Plug.Builder"
  """
  @spec module_name(UseDirective.t()) :: String.t()
  def module_name(%UseDirective{module: module}) do
    case module do
      [single] when is_atom(single) ->
        Atom.to_string(single)

      parts when is_list(parts) ->
        parts |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
    end
  end

  @doc """
  Checks if the use directive has options.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{module: [:GenServer]}
      iex> ElixirOntologies.Extractors.Directive.Use.has_options?(directive)
      false

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{module: [:GenServer], options: [restart: :temporary]}
      iex> ElixirOntologies.Extractors.Directive.Use.has_options?(directive)
      true

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{module: [:MyApp, :Web], options: :controller}
      iex> ElixirOntologies.Extractors.Directive.Use.has_options?(directive)
      true
  """
  @spec has_options?(UseDirective.t()) :: boolean()
  def has_options?(%UseDirective{options: nil}), do: false
  def has_options?(%UseDirective{options: []}), do: false
  def has_options?(%UseDirective{}), do: true

  @doc """
  Checks if the use directive has keyword options.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{module: [:GenServer], options: [restart: :temporary]}
      iex> ElixirOntologies.Extractors.Directive.Use.keyword_options?(directive)
      true

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{module: [:MyApp, :Web], options: :controller}
      iex> ElixirOntologies.Extractors.Directive.Use.keyword_options?(directive)
      false
  """
  @spec keyword_options?(UseDirective.t()) :: boolean()
  def keyword_options?(%UseDirective{options: opts}) when is_list(opts) and opts != [],
    do: Keyword.keyword?(opts)

  def keyword_options?(%UseDirective{}), do: false

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp build_directive(module_parts, use_opts, node, opts) do
    location = Helpers.extract_location_if(node, opts)

    {:ok,
     %UseDirective{
       module: module_parts,
       options: use_opts,
       location: location,
       metadata: %{}
     }}
  end

  defp do_extract_all(ast, opts) do
    case extract(ast, opts) do
      {:ok, directive} -> [directive]
      {:error, _} -> []
    end
  end

  # ===========================================================================
  # Scope Tracking Helpers
  # ===========================================================================

  # Extract uses with scope tracking
  defp extract_with_scope(ast, current_scope, opts)

  # Handle list of statements
  defp extract_with_scope(statements, current_scope, opts) when is_list(statements) do
    Enum.flat_map(statements, &extract_with_scope(&1, current_scope, opts))
  end

  # Handle __block__
  defp extract_with_scope({:__block__, _meta, statements}, current_scope, opts) do
    extract_with_scope(statements, current_scope, opts)
  end

  # Handle function definitions - switch to function scope
  defp extract_with_scope({def_type, _meta, [{name, _, _args}, body_opts]}, _current_scope, opts)
       when def_type in [:def, :defp, :defmacro, :defmacrop] and is_atom(name) do
    body = Keyword.get(body_opts, :do, nil)

    if body do
      extract_with_scope(body, :function, opts)
    else
      []
    end
  end

  # Handle function definitions with when clause
  defp extract_with_scope(
         {def_type, _meta, [{:when, _, [{name, _, _args}, _guard]}, body_opts]},
         _current_scope,
         opts
       )
       when def_type in [:def, :defp, :defmacro, :defmacrop] and is_atom(name) do
    body = Keyword.get(body_opts, :do, nil)

    if body do
      extract_with_scope(body, :function, opts)
    else
      []
    end
  end

  # Handle block constructs - switch to block scope
  defp extract_with_scope({block_type, _meta, args}, current_scope, opts)
       when block_type in [:if, :unless, :case, :cond, :with, :for, :try, :receive] and
              is_list(args) do
    # For block constructs inside module scope, they're still module scope
    # For block constructs inside function scope, switch to block scope
    new_scope = if current_scope == :module, do: :module, else: :block

    # Extract from all parts of the block construct
    args
    |> Enum.flat_map(fn
      clauses when is_list(clauses) ->
        Enum.flat_map(clauses, fn
          {_key, body} -> extract_with_scope(body, new_scope, opts)
          other -> extract_with_scope(other, new_scope, opts)
        end)

      other ->
        extract_with_scope(other, new_scope, opts)
    end)
  end

  # Handle use - extract with current scope
  defp extract_with_scope({:use, _meta, _args} = ast, current_scope, opts) do
    case extract(ast, opts) do
      {:ok, directive} ->
        [%{directive | scope: current_scope}]

      {:error, _} ->
        []
    end
  end

  # Handle other tuple forms - recurse into arguments
  defp extract_with_scope({_form, _meta, args}, current_scope, opts) when is_list(args) do
    extract_with_scope(args, current_scope, opts)
  end

  # Ignore atoms, literals, and other non-tuple forms
  defp extract_with_scope(_other, _current_scope, _opts) do
    []
  end
end
