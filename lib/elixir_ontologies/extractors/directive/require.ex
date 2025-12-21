defmodule ElixirOntologies.Extractors.Directive.Require do
  @moduledoc """
  Extracts require directive information from Elixir AST.

  This module provides detailed extraction of require directives which make
  a module's macros available at compile time.

  ## Architecture Note

  This extractor is designed for composable, on-demand directive analysis. It is
  intentionally **not** automatically invoked by the main Pipeline module. This
  separation allows:

  - Lightweight module extraction when directive details aren't needed
  - Targeted directive analysis when building dependency graphs
  - Flexibility to use extractors individually or in combination

  To extract directives during module analysis, either:
  1. Call this extractor directly on directive AST nodes
  2. Use `Module.extract/2` with the `:extract_directives` option (when available)

  ## Require Forms

  Elixir supports several require forms:

      # Basic require - makes Logger macros available
      require Logger

      # Require with alias
      require Logger, as: L

      # Erlang module require
      require :ets

      # Multi-part module
      require MyApp.Macros

  ## Examples

      iex> ast = {:require, [line: 1], [{:__aliases__, [line: 1], [:Logger]}]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Require.extract(ast)
      iex> directive.module
      [:Logger]
      iex> directive.as
      nil

      iex> ast = {:require, [line: 1], [{:__aliases__, [line: 1], [:Logger]}, [as: {:__aliases__, [], [:L]}]]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Require.extract(ast)
      iex> directive.as
      :L
  """

  alias ElixirOntologies.Extractors.Helpers
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # ===========================================================================
  # Struct Definition
  # ===========================================================================

  defmodule RequireDirective do
    @moduledoc """
    Represents an extracted require directive.

    ## Fields

    - `:module` - The module being required as a list of atoms
    - `:as` - Optional alias for the required module
    - `:location` - Source location of the directive
    - `:scope` - Lexical scope (:module, :function, :block)
    - `:metadata` - Additional metadata
    """

    @type t :: %__MODULE__{
            module: [atom()] | atom(),
            as: atom() | nil,
            location: SourceLocation.t() | nil,
            scope: :module | :function | :block | nil,
            metadata: map()
          }

    @enforce_keys [:module]
    defstruct [:module, :as, :location, :scope, metadata: %{}]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if the given AST node represents a require directive.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Require.require?({:require, [], [{:__aliases__, [], [:Logger]}]})
      true

      iex> ElixirOntologies.Extractors.Directive.Require.require?({:import, [], [{:__aliases__, [], [:Enum]}]})
      false

      iex> ElixirOntologies.Extractors.Directive.Require.require?(:not_a_require)
      false
  """
  @spec require?(Macro.t()) :: boolean()
  def require?({:require, _meta, [_ | _]}), do: true
  def require?(_), do: false

  # ===========================================================================
  # Extraction Functions
  # ===========================================================================

  @doc """
  Extracts require directive information from an AST node.

  Returns `{:ok, %RequireDirective{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:require, [line: 5], [{:__aliases__, [line: 5], [:Logger]}]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Require.extract(ast)
      iex> directive.module
      [:Logger]
      iex> directive.as
      nil

      iex> ast = {:require, [], [{:__aliases__, [], [:Logger]}, [as: {:__aliases__, [], [:L]}]]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Require.extract(ast)
      iex> directive.as
      :L
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, RequireDirective.t()} | {:error, term()}
  def extract(ast, opts \\ [])

  # Basic require: require Module
  def extract({:require, _meta, [{:__aliases__, _, parts}]} = node, opts)
      when is_list(parts) do
    build_directive(parts, nil, node, opts)
  end

  # Require with options: require Module, as: Short
  def extract({:require, _meta, [{:__aliases__, _, parts}, require_opts]} = node, opts)
      when is_list(parts) and is_list(require_opts) do
    as_name = extract_as_option(require_opts)
    build_directive(parts, as_name, node, opts)
  end

  # Erlang module: require :ets
  def extract({:require, _meta, [module]} = node, opts) when is_atom(module) do
    build_directive([module], nil, node, opts)
  end

  # Erlang module with options
  def extract({:require, _meta, [module, require_opts]} = node, opts)
      when is_atom(module) and is_list(require_opts) do
    as_name = extract_as_option(require_opts)
    build_directive([module], as_name, node, opts)
  end

  def extract(ast, _opts) do
    {:error, {:not_a_require, Helpers.format_error("Not a require directive", ast)}}
  end

  @doc """
  Extracts require directive information, raising on error.

  ## Examples

      iex> ast = {:require, [], [{:__aliases__, [], [:Logger]}]}
      iex> directive = ElixirOntologies.Extractors.Directive.Require.extract!(ast)
      iex> directive.module
      [:Logger]
  """
  @spec extract!(Macro.t(), keyword()) :: RequireDirective.t()
  def extract!(ast, opts \\ []) do
    case extract(ast, opts) do
      {:ok, directive} -> directive
      {:error, reason} -> raise ArgumentError, "Failed to extract require: #{inspect(reason)}"
    end
  end

  @doc """
  Extracts all require directives from a module body or list of statements.

  ## Examples

      iex> body = [
      ...>   {:require, [], [{:__aliases__, [], [:Logger]}]},
      ...>   {:require, [], [{:__aliases__, [], [:Macro]}]},
      ...>   {:def, [], [{:foo, [], nil}, [do: :ok]]}
      ...> ]
      iex> directives = ElixirOntologies.Extractors.Directive.Require.extract_all(body)
      iex> length(directives)
      2
      iex> Enum.map(directives, & &1.module)
      [[:Logger], [:Macro]]
  """
  @spec extract_all(Macro.t(), keyword()) :: [RequireDirective.t()]
  def extract_all(ast, opts \\ [])

  def extract_all(statements, opts) when is_list(statements) do
    statements
    |> Enum.filter(&require?/1)
    |> Enum.flat_map(&do_extract_all(&1, opts))
  end

  def extract_all({:__block__, _meta, statements}, opts) do
    extract_all(statements, opts)
  end

  def extract_all(ast, opts) do
    if require?(ast) do
      do_extract_all(ast, opts)
    else
      []
    end
  end

  # ===========================================================================
  # Scope-Aware Extraction
  # ===========================================================================

  @doc """
  Extracts all require directives from a module body with scope tracking.

  This function walks the AST and tracks the lexical scope of each require,
  setting the `:scope` field to `:module`, `:function`, or `:block`.

  ## Examples

      iex> {:defmodule, _, [_, [do: {:__block__, _, body}]]} = quote do
      ...>   defmodule Test do
      ...>     require Logger
      ...>     def foo do
      ...>       require Macro
      ...>     end
      ...>   end
      ...> end
      iex> directives = ElixirOntologies.Extractors.Directive.Require.extract_all_with_scope(body)
      iex> length(directives)
      2
      iex> [logger, macro] = directives
      iex> logger.scope
      :module
      iex> macro.scope
      :function
  """
  @spec extract_all_with_scope(Macro.t(), keyword()) :: [RequireDirective.t()]
  def extract_all_with_scope(ast, opts \\ []) do
    extract_with_scope(ast, :module, opts)
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Returns the required module as a dot-separated string.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Require.RequireDirective{
      ...>   module: [:Logger]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Require.module_name(directive)
      "Logger"

      iex> directive = %ElixirOntologies.Extractors.Directive.Require.RequireDirective{
      ...>   module: [:MyApp, :Macros]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Require.module_name(directive)
      "MyApp.Macros"

      iex> directive = %ElixirOntologies.Extractors.Directive.Require.RequireDirective{
      ...>   module: [:ets]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Require.module_name(directive)
      "ets"
  """
  @spec module_name(RequireDirective.t()) :: String.t()
  def module_name(%RequireDirective{module: module}) do
    case module do
      [single] when is_atom(single) ->
        Atom.to_string(single)

      parts when is_list(parts) ->
        parts |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
    end
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp build_directive(module_parts, as_name, node, opts) do
    location = Helpers.extract_location_if(node, opts)

    {:ok,
     %RequireDirective{
       module: module_parts,
       as: as_name,
       location: location,
       metadata: %{}
     }}
  end

  defp extract_as_option(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, [name]} when is_atom(name) -> name
      {:__aliases__, _, names} when is_list(names) -> List.last(names)
      name when is_atom(name) and not is_nil(name) -> name
      _ -> nil
    end
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

  # Extract requires with scope tracking
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

  # Handle require - extract with current scope
  defp extract_with_scope({:require, _meta, _args} = ast, current_scope, opts) do
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
