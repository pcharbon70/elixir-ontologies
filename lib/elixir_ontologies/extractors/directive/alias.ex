defmodule ElixirOntologies.Extractors.Directive.Alias do
  @moduledoc """
  Extracts alias directive information from Elixir AST.

  This module provides detailed extraction of alias directives including the
  source module, alias name (explicit or computed), and source location.

  ## Alias Forms

  Elixir supports several alias forms:

      # Simple alias - aliased as last segment (Users)
      alias MyApp.Users

      # Explicit alias - aliased as U
      alias MyApp.Users, as: U

      # Erlang module alias
      alias :crypto, as: Crypto

  ## Examples

      iex> ast = {:alias, [line: 1], [{:__aliases__, [line: 1], [:MyApp, :Users]}]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Alias.extract(ast)
      iex> directive.source
      [:MyApp, :Users]
      iex> directive.as
      :Users

      iex> ast = {:alias, [line: 1], [{:__aliases__, [line: 1], [:MyApp, :Users]}, [as: {:__aliases__, [], [:U]}]]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Alias.extract(ast)
      iex> directive.as
      :U
      iex> directive.explicit_as
      true
  """

  alias ElixirOntologies.Extractors.Helpers
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # ===========================================================================
  # Struct Definition
  # ===========================================================================

  defmodule AliasDirective do
    @moduledoc """
    Represents an extracted alias directive.

    ## Fields

    - `:source` - The full module path being aliased as a list of atoms
    - `:as` - The alias name (explicit or computed from last segment)
    - `:explicit_as` - Whether the alias name was explicitly provided via `as:`
    - `:location` - Source location of the directive
    - `:scope` - Lexical scope (reserved for 16.1.3)
    - `:metadata` - Additional metadata
    """

    @type t :: %__MODULE__{
            source: [atom()] | atom(),
            as: atom(),
            explicit_as: boolean(),
            location: SourceLocation.t() | nil,
            scope: :module | :function | :block | nil,
            metadata: map()
          }

    @enforce_keys [:source, :as]
    defstruct [:source, :as, explicit_as: false, location: nil, scope: nil, metadata: %{}]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if the given AST node represents an alias directive.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Alias.alias?({:alias, [], [{:__aliases__, [], [:MyApp]}]})
      true

      iex> ElixirOntologies.Extractors.Directive.Alias.alias?({:import, [], [{:__aliases__, [], [:MyApp]}]})
      false

      iex> ElixirOntologies.Extractors.Directive.Alias.alias?(:not_an_alias)
      false
  """
  @spec alias?(Macro.t()) :: boolean()
  def alias?({:alias, _meta, [_ | _]}), do: true
  def alias?(_), do: false

  # ===========================================================================
  # Extraction Functions
  # ===========================================================================

  @doc """
  Extracts alias directive information from an AST node.

  Returns `{:ok, %AliasDirective{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:alias, [line: 5], [{:__aliases__, [line: 5], [:MyApp, :Users]}]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Alias.extract(ast)
      iex> directive.source
      [:MyApp, :Users]
      iex> directive.as
      :Users
      iex> directive.explicit_as
      false

      iex> ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}, [as: {:__aliases__, [], [:U]}]]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Alias.extract(ast)
      iex> directive.as
      :U
      iex> directive.explicit_as
      true
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, AliasDirective.t()} | {:error, term()}
  def extract(ast, opts \\ [])

  # Simple alias: alias Module.Name
  def extract({:alias, _meta, [{:__aliases__, _, parts}]} = node, opts)
      when is_list(parts) do
    build_directive(parts, nil, false, node, opts)
  end

  # Alias with options: alias Module.Name, as: Short
  def extract({:alias, _meta, [{:__aliases__, _, parts}, alias_opts]} = node, opts)
      when is_list(parts) and is_list(alias_opts) do
    explicit_as = extract_as_option(alias_opts)
    build_directive(parts, explicit_as, explicit_as != nil, node, opts)
  end

  # Erlang module: alias :crypto
  def extract({:alias, _meta, [module]} = node, opts) when is_atom(module) do
    build_directive([module], nil, false, node, opts)
  end

  # Erlang module with as: alias :crypto, as: Crypto
  def extract({:alias, _meta, [module, alias_opts]} = node, opts)
      when is_atom(module) and is_list(alias_opts) do
    explicit_as = extract_as_option(alias_opts)
    build_directive([module], explicit_as, explicit_as != nil, node, opts)
  end

  def extract(ast, _opts) do
    {:error, {:not_an_alias, Helpers.format_error("Not an alias directive", ast)}}
  end

  @doc """
  Extracts alias directive information, raising on error.

  ## Examples

      iex> ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}]}
      iex> directive = ElixirOntologies.Extractors.Directive.Alias.extract!(ast)
      iex> directive.source
      [:MyApp, :Users]
  """
  @spec extract!(Macro.t(), keyword()) :: AliasDirective.t()
  def extract!(ast, opts \\ []) do
    case extract(ast, opts) do
      {:ok, directive} -> directive
      {:error, reason} -> raise ArgumentError, "Failed to extract alias: #{inspect(reason)}"
    end
  end

  @doc """
  Extracts all alias directives from a module body or list of statements.

  ## Examples

      iex> body = [
      ...>   {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}]},
      ...>   {:alias, [], [{:__aliases__, [], [:MyApp, :Accounts]}]},
      ...>   {:def, [], [{:foo, [], nil}, [do: :ok]]}
      ...> ]
      iex> directives = ElixirOntologies.Extractors.Directive.Alias.extract_all(body)
      iex> length(directives)
      2
      iex> Enum.map(directives, & &1.as)
      [:Users, :Accounts]
  """
  @spec extract_all(Macro.t(), keyword()) :: [AliasDirective.t()]
  def extract_all(ast, opts \\ [])

  def extract_all(statements, opts) when is_list(statements) do
    statements
    |> Enum.filter(&alias?/1)
    |> Enum.flat_map(&do_extract_all(&1, opts))
  end

  def extract_all({:__block__, _meta, statements}, opts) do
    extract_all(statements, opts)
  end

  def extract_all(ast, opts) do
    if alias?(ast) do
      do_extract_all(ast, opts)
    else
      []
    end
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Returns the source module as a dot-separated string.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Alias.AliasDirective{
      ...>   source: [:MyApp, :Users, :Admin],
      ...>   as: :Admin
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Alias.source_module_name(directive)
      "MyApp.Users.Admin"

      iex> directive = %ElixirOntologies.Extractors.Directive.Alias.AliasDirective{
      ...>   source: [:crypto],
      ...>   as: :Crypto
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Alias.source_module_name(directive)
      "crypto"
  """
  @spec source_module_name(AliasDirective.t()) :: String.t()
  def source_module_name(%AliasDirective{source: source}) do
    case source do
      [single] when is_atom(single) ->
        # Erlang module - use lowercase atom name
        Atom.to_string(single)

      parts when is_list(parts) ->
        parts |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
    end
  end

  @doc """
  Returns the alias name as a string.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Alias.AliasDirective{
      ...>   source: [:MyApp, :Users],
      ...>   as: :U
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Alias.alias_name(directive)
      "U"
  """
  @spec alias_name(AliasDirective.t()) :: String.t()
  def alias_name(%AliasDirective{as: as_name}) do
    Atom.to_string(as_name)
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp build_directive(parts, explicit_as, is_explicit, node, opts) do
    computed_as = compute_alias_name(parts)
    as_name = explicit_as || computed_as
    location = Helpers.extract_location_if(node, opts)

    {:ok,
     %AliasDirective{
       source: parts,
       as: as_name,
       explicit_as: is_explicit,
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

  defp compute_alias_name(parts) when is_list(parts) do
    # The alias name is the last segment of the module path
    # e.g., MyApp.Users.Admin -> Admin
    List.last(parts)
  end

  defp do_extract_all(ast, opts) do
    case extract(ast, opts) do
      {:ok, directive} -> [directive]
      {:error, _} -> []
    end
  end
end
