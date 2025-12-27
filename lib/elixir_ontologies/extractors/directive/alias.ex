defmodule ElixirOntologies.Extractors.Directive.Alias do
  @moduledoc """
  Extracts alias directive information from Elixir AST.

  This module provides detailed extraction of alias directives including the
  source module, alias name (explicit or computed), and source location.

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

  ## Alias Forms

  Elixir supports several alias forms:

      # Simple alias - aliased as last segment (Users)
      alias MyApp.Users

      # Explicit alias - aliased as U
      alias MyApp.Users, as: U

      # Erlang module alias
      alias :crypto, as: Crypto

      # Multi-alias - expands to multiple aliases
      alias MyApp.{Users, Accounts}

      # Nested multi-alias
      alias MyApp.{Sub.{A, B}, Other}

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

  defmodule MultiAliasGroup do
    @moduledoc """
    Represents a multi-alias group (e.g., `alias MyApp.{Users, Accounts}`).

    This struct preserves the relationship between the expanded aliases
    and their original grouped form.

    ## Fields

    - `:prefix` - The common prefix for all aliases in the group
    - `:aliases` - List of expanded AliasDirective structs
    - `:location` - Source location of the multi-alias directive
    - `:metadata` - Additional metadata
    """

    alias ElixirOntologies.Extractors.Directive.Alias.AliasDirective

    @type t :: %__MODULE__{
            prefix: [atom()],
            aliases: [AliasDirective.t()],
            location: SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct prefix: [], aliases: [], location: nil, metadata: %{}
  end

  defmodule LexicalScope do
    @moduledoc """
    Represents the lexical scope where an alias directive is defined.

    ## Fields

    - `:type` - The scope type: `:module`, `:function`, or `:block`
    - `:name` - The name of the function for function scope, nil otherwise
    - `:start_line` - Start line of the scope
    - `:end_line` - End line of the scope (nil if unknown)
    - `:parent` - Parent scope for nested scopes
    """

    @type scope_type :: :module | :function | :block

    @type t :: %__MODULE__{
            type: scope_type(),
            name: atom() | nil,
            start_line: pos_integer() | nil,
            end_line: pos_integer() | nil,
            parent: t() | nil
          }

    defstruct [:type, :name, :start_line, :end_line, :parent]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if the given AST node represents an alias directive (simple or multi-alias).

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

  @doc """
  Checks if the given AST node represents a multi-alias directive.

  Multi-alias uses the curly brace syntax: `alias MyApp.{Users, Accounts}`.

  ## Examples

      iex> ast = {:alias, [],
      ...>  [{{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [],
      ...>    [{:__aliases__, [], [:Users]}, {:__aliases__, [], [:Accounts]}]}]}
      iex> ElixirOntologies.Extractors.Directive.Alias.multi_alias?(ast)
      true

      iex> ElixirOntologies.Extractors.Directive.Alias.multi_alias?({:alias, [], [{:__aliases__, [], [:MyApp]}]})
      false
  """
  @spec multi_alias?(Macro.t()) :: boolean()
  def multi_alias?({:alias, _meta, [{{:., _, [_prefix, :{}]}, _, _suffixes}]}), do: true
  def multi_alias?(_), do: false

  @doc """
  Checks if the given AST node represents a simple (non-multi) alias directive.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Alias.simple_alias?({:alias, [], [{:__aliases__, [], [:MyApp]}]})
      true

      iex> ast = {:alias, [],
      ...>  [{{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [],
      ...>    [{:__aliases__, [], [:Users]}]}]}
      iex> ElixirOntologies.Extractors.Directive.Alias.simple_alias?(ast)
      false
  """
  @spec simple_alias?(Macro.t()) :: boolean()
  def simple_alias?(ast), do: alias?(ast) and not multi_alias?(ast)

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

  # ===========================================================================
  # Multi-Alias Extraction
  # ===========================================================================

  @default_max_nesting_depth 10

  @doc """
  Extracts a multi-alias directive into a list of individual AliasDirective structs.

  Returns `{:ok, [%AliasDirective{}]}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)
  - `:max_nesting_depth` - Maximum nesting depth for multi-alias expansion (default: 10).
    Prevents stack overflow from deeply nested or malicious input.

  ## Examples

      iex> ast = {:alias, [],
      ...>  [{{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [],
      ...>    [{:__aliases__, [], [:Users]}, {:__aliases__, [], [:Accounts]}]}]}
      iex> {:ok, directives} = ElixirOntologies.Extractors.Directive.Alias.extract_multi_alias(ast)
      iex> length(directives)
      2
      iex> Enum.map(directives, & &1.source)
      [[:MyApp, :Users], [:MyApp, :Accounts]]
  """
  @spec extract_multi_alias(Macro.t(), keyword()) ::
          {:ok, [AliasDirective.t()]} | {:error, term()}
  def extract_multi_alias(ast, opts \\ [])

  def extract_multi_alias(
        {:alias, _meta, [{{:., _, [{:__aliases__, _, prefix}, :{}]}, _, suffixes}]} = node,
        opts
      ) do
    location = Helpers.extract_location_if(node, opts)
    max_depth = Keyword.get(opts, :max_nesting_depth, @default_max_nesting_depth)

    case expand_multi_alias(prefix, suffixes, location, 0, 0, max_depth) do
      {:ok, directives} -> {:ok, directives}
      {:error, _} = error -> error
    end
  end

  def extract_multi_alias(ast, _opts) do
    {:error, {:not_a_multi_alias, Helpers.format_error("Not a multi-alias directive", ast)}}
  end

  @doc """
  Extracts a multi-alias directive into a MultiAliasGroup struct.

  This preserves the original group structure along with the expanded aliases.

  ## Examples

      iex> ast = {:alias, [],
      ...>  [{{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [],
      ...>    [{:__aliases__, [], [:Users]}, {:__aliases__, [], [:Accounts]}]}]}
      iex> {:ok, group} = ElixirOntologies.Extractors.Directive.Alias.extract_multi_alias_group(ast)
      iex> group.prefix
      [:MyApp]
      iex> length(group.aliases)
      2
  """
  @spec extract_multi_alias_group(Macro.t(), keyword()) ::
          {:ok, MultiAliasGroup.t()} | {:error, term()}
  def extract_multi_alias_group(ast, opts \\ [])

  def extract_multi_alias_group(
        {:alias, _meta, [{{:., _, [{:__aliases__, _, prefix}, :{}]}, _, suffixes}]} = node,
        opts
      ) do
    location = Helpers.extract_location_if(node, opts)
    max_depth = Keyword.get(opts, :max_nesting_depth, @default_max_nesting_depth)

    case expand_multi_alias(prefix, suffixes, location, 0, 0, max_depth) do
      {:ok, directives} ->
        {:ok,
         %MultiAliasGroup{
           prefix: prefix,
           aliases: directives,
           location: location,
           metadata: %{}
         }}

      {:error, _} = error ->
        error
    end
  end

  def extract_multi_alias_group(ast, _opts) do
    {:error, {:not_a_multi_alias, Helpers.format_error("Not a multi-alias directive", ast)}}
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
  # Scope-Aware Extraction
  # ===========================================================================

  @doc """
  Extracts all alias directives from a module body with scope tracking.

  This function walks the AST and tracks the lexical scope of each alias,
  setting the `:scope` field to `:module`, `:function`, or `:block`.

  ## Examples

      iex> {:defmodule, _, [_, [do: {:__block__, _, body}]]} = quote do
      ...>   defmodule Test do
      ...>     alias MyApp.Users
      ...>     def foo do
      ...>       alias MyApp.Accounts
      ...>     end
      ...>   end
      ...> end
      iex> directives = ElixirOntologies.Extractors.Directive.Alias.extract_all_with_scope(body)
      iex> length(directives)
      2
      iex> [users, accounts] = directives
      iex> users.scope
      :module
      iex> accounts.scope
      :function
  """
  @spec extract_all_with_scope(Macro.t(), keyword()) :: [AliasDirective.t()]
  def extract_all_with_scope(ast, opts \\ []) do
    extract_with_scope(ast, :module, opts)
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
    if multi_alias?(ast) do
      case extract_multi_alias(ast, opts) do
        {:ok, directives} -> directives
        {:error, _} -> []
      end
    else
      case extract(ast, opts) do
        {:ok, directive} -> [directive]
        {:error, _} -> []
      end
    end
  end

  # Expands multi-alias suffixes into individual AliasDirective structs
  # With depth limiting to prevent stack overflow from deeply nested input
  defp expand_multi_alias(prefix, suffixes, location, start_index, current_depth, max_depth) do
    if current_depth > max_depth do
      {:error, {:max_nesting_depth_exceeded, "Multi-alias nesting depth exceeded #{max_depth}"}}
    else
      result =
        Enum.reduce_while(suffixes, {:ok, [], start_index}, fn suffix, {:ok, acc, idx} ->
          case expand_suffix(prefix, suffix, location, idx, current_depth, max_depth) do
            {:simple, directive, new_idx} ->
              {:cont, {:ok, [directive | acc], new_idx}}

            {:nested, {:ok, nested_directives}, new_idx} ->
              {:cont, {:ok, Enum.reverse(nested_directives) ++ acc, new_idx}}

            {:nested, {:error, _} = error, _} ->
              {:halt, error}
          end
        end)

      case result do
        {:ok, directives, _} -> {:ok, Enum.reverse(directives)}
        {:error, _} = error -> error
      end
    end
  end

  # Handle simple suffix: {:__aliases__, _, parts}
  defp expand_suffix(prefix, {:__aliases__, _, suffix_parts}, location, idx, _depth, _max_depth) do
    full_source = prefix ++ suffix_parts
    alias_name = compute_alias_name(full_source)

    directive = %AliasDirective{
      source: full_source,
      as: alias_name,
      explicit_as: false,
      location: location,
      metadata: %{
        from_multi_alias: true,
        multi_alias_prefix: prefix,
        multi_alias_index: idx
      }
    }

    {:simple, directive, idx + 1}
  end

  # Handle nested multi-alias: {{:., _, [nested_prefix, :{}]}, _, nested_suffixes}
  defp expand_suffix(
         prefix,
         {{:., _, [{:__aliases__, _, nested_prefix_parts}, :{}]}, _, nested_suffixes},
         location,
         idx,
         current_depth,
         max_depth
       ) do
    # Combine the outer prefix with the nested prefix
    combined_prefix = prefix ++ nested_prefix_parts
    # Recursively expand the nested suffixes with incremented depth
    result =
      expand_multi_alias(
        combined_prefix,
        nested_suffixes,
        location,
        idx,
        current_depth + 1,
        max_depth
      )

    case result do
      {:ok, nested_directives} ->
        new_idx = idx + length(nested_directives)
        {:nested, {:ok, nested_directives}, new_idx}

      {:error, _} = error ->
        {:nested, error, idx}
    end
  end

  # ===========================================================================
  # Scope Tracking Helpers
  # ===========================================================================

  # Extract aliases with scope tracking
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

  # Handle alias - extract with current scope
  defp extract_with_scope({:alias, _meta, _args} = ast, current_scope, opts) do
    if multi_alias?(ast) do
      case extract_multi_alias(ast, opts) do
        {:ok, directives} ->
          Enum.map(directives, &%{&1 | scope: current_scope})

        {:error, _} ->
          []
      end
    else
      case extract(ast, opts) do
        {:ok, directive} ->
          [%{directive | scope: current_scope}]

        {:error, _} ->
          []
      end
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
