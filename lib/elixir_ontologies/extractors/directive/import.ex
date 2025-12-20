defmodule ElixirOntologies.Extractors.Directive.Import do
  @moduledoc """
  Extracts import directive information from Elixir AST.

  This module provides detailed extraction of import directives including the
  imported module, selective imports (only/except options), and source location.

  ## Import Forms

  Elixir supports several import forms:

      # Full import - imports all functions and macros
      import Enum

      # Selective import - only specific functions
      import Enum, only: [map: 2, filter: 2]

      # Exclusion import - all except specified
      import Enum, except: [reduce: 3]

      # Type-based import
      import Kernel, only: :functions
      import Kernel, only: :macros
      import Kernel, only: :sigils

      # Erlang module import
      import :lists

  ## Examples

      iex> ast = {:import, [line: 1], [{:__aliases__, [line: 1], [:Enum]}]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Import.extract(ast)
      iex> directive.module
      [:Enum]
      iex> directive.only
      nil

      iex> ast = {:import, [line: 1], [{:__aliases__, [line: 1], [:Enum]}, [only: [map: 2]]]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Import.extract(ast)
      iex> directive.only
      [map: 2]
  """

  alias ElixirOntologies.Extractors.Helpers
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # ===========================================================================
  # Struct Definition
  # ===========================================================================

  defmodule ImportDirective do
    @moduledoc """
    Represents an extracted import directive.

    ## Fields

    - `:module` - The module being imported as a list of atoms
    - `:only` - Selective import: list of `{name, arity}` tuples, or `:functions`/`:macros`/`:sigils`
    - `:except` - Exclusion list: `{name, arity}` tuples to exclude
    - `:location` - Source location of the directive
    - `:scope` - Lexical scope (:module, :function, :block)
    - `:metadata` - Additional metadata
    """

    @type import_selector ::
            [{atom(), non_neg_integer()}] | :functions | :macros | :sigils | nil

    @type t :: %__MODULE__{
            module: [atom()] | atom(),
            only: import_selector(),
            except: [{atom(), non_neg_integer()}] | nil,
            location: SourceLocation.t() | nil,
            scope: :module | :function | :block | nil,
            metadata: map()
          }

    @enforce_keys [:module]
    defstruct [:module, only: nil, except: nil, location: nil, scope: nil, metadata: %{}]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if the given AST node represents an import directive.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Import.import?({:import, [], [{:__aliases__, [], [:Enum]}]})
      true

      iex> ElixirOntologies.Extractors.Directive.Import.import?({:alias, [], [{:__aliases__, [], [:MyApp]}]})
      false

      iex> ElixirOntologies.Extractors.Directive.Import.import?(:not_an_import)
      false
  """
  @spec import?(Macro.t()) :: boolean()
  def import?({:import, _meta, [_ | _]}), do: true
  def import?(_), do: false

  # ===========================================================================
  # Extraction Functions
  # ===========================================================================

  @doc """
  Extracts import directive information from an AST node.

  Returns `{:ok, %ImportDirective{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:import, [line: 5], [{:__aliases__, [line: 5], [:Enum]}]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Import.extract(ast)
      iex> directive.module
      [:Enum]
      iex> directive.only
      nil
      iex> directive.except
      nil

      iex> ast = {:import, [], [{:__aliases__, [], [:Enum]}, [only: [map: 2, filter: 2]]]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Import.extract(ast)
      iex> directive.only
      [map: 2, filter: 2]

      iex> ast = {:import, [], [{:__aliases__, [], [:Enum]}, [except: [reduce: 3]]]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Import.extract(ast)
      iex> directive.except
      [reduce: 3]
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, ImportDirective.t()} | {:error, term()}
  def extract(ast, opts \\ [])

  # Basic import: import Module
  def extract({:import, _meta, [{:__aliases__, _, parts}]} = node, opts)
      when is_list(parts) do
    build_directive(parts, nil, nil, node, opts)
  end

  # Import with options: import Module, only: [...] or except: [...]
  def extract({:import, _meta, [{:__aliases__, _, parts}, import_opts]} = node, opts)
      when is_list(parts) and is_list(import_opts) do
    only = extract_only_option(import_opts)
    except = extract_except_option(import_opts)
    build_directive(parts, only, except, node, opts)
  end

  # Erlang module: import :lists
  def extract({:import, _meta, [module]} = node, opts) when is_atom(module) do
    build_directive([module], nil, nil, node, opts)
  end

  # Erlang module with options
  def extract({:import, _meta, [module, import_opts]} = node, opts)
      when is_atom(module) and is_list(import_opts) do
    only = extract_only_option(import_opts)
    except = extract_except_option(import_opts)
    build_directive([module], only, except, node, opts)
  end

  def extract(ast, _opts) do
    {:error, {:not_an_import, Helpers.format_error("Not an import directive", ast)}}
  end

  @doc """
  Extracts import directive information, raising on error.

  ## Examples

      iex> ast = {:import, [], [{:__aliases__, [], [:Enum]}]}
      iex> directive = ElixirOntologies.Extractors.Directive.Import.extract!(ast)
      iex> directive.module
      [:Enum]
  """
  @spec extract!(Macro.t(), keyword()) :: ImportDirective.t()
  def extract!(ast, opts \\ []) do
    case extract(ast, opts) do
      {:ok, directive} -> directive
      {:error, reason} -> raise ArgumentError, "Failed to extract import: #{inspect(reason)}"
    end
  end

  @doc """
  Extracts all import directives from a module body or list of statements.

  ## Examples

      iex> body = [
      ...>   {:import, [], [{:__aliases__, [], [:Enum]}]},
      ...>   {:import, [], [{:__aliases__, [], [:String]}]},
      ...>   {:def, [], [{:foo, [], nil}, [do: :ok]]}
      ...> ]
      iex> directives = ElixirOntologies.Extractors.Directive.Import.extract_all(body)
      iex> length(directives)
      2
      iex> Enum.map(directives, & &1.module)
      [[:Enum], [:String]]
  """
  @spec extract_all(Macro.t(), keyword()) :: [ImportDirective.t()]
  def extract_all(ast, opts \\ [])

  def extract_all(statements, opts) when is_list(statements) do
    statements
    |> Enum.filter(&import?/1)
    |> Enum.flat_map(&do_extract_all(&1, opts))
  end

  def extract_all({:__block__, _meta, statements}, opts) do
    extract_all(statements, opts)
  end

  def extract_all(ast, opts) do
    if import?(ast) do
      do_extract_all(ast, opts)
    else
      []
    end
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Returns the imported module as a dot-separated string.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Import.ImportDirective{
      ...>   module: [:Enum]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Import.module_name(directive)
      "Enum"

      iex> directive = %ElixirOntologies.Extractors.Directive.Import.ImportDirective{
      ...>   module: [:MyApp, :Utils, :Helpers]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Import.module_name(directive)
      "MyApp.Utils.Helpers"

      iex> directive = %ElixirOntologies.Extractors.Directive.Import.ImportDirective{
      ...>   module: [:lists]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Import.module_name(directive)
      "lists"
  """
  @spec module_name(ImportDirective.t()) :: String.t()
  def module_name(%ImportDirective{module: module}) do
    case module do
      [single] when is_atom(single) ->
        name = Atom.to_string(single)
        # Erlang modules are lowercase
        if String.starts_with?(name, ":") or name =~ ~r/^[a-z]/ do
          name
        else
          name
        end

      parts when is_list(parts) ->
        parts |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
    end
  end

  @doc """
  Checks if the import is a full import (no only/except restrictions).

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Import.ImportDirective{module: [:Enum]}
      iex> ElixirOntologies.Extractors.Directive.Import.full_import?(directive)
      true

      iex> directive = %ElixirOntologies.Extractors.Directive.Import.ImportDirective{module: [:Enum], only: [map: 2]}
      iex> ElixirOntologies.Extractors.Directive.Import.full_import?(directive)
      false
  """
  @spec full_import?(ImportDirective.t()) :: boolean()
  def full_import?(%ImportDirective{only: nil, except: nil}), do: true
  def full_import?(_), do: false

  @doc """
  Checks if the import uses type-based selection (:functions, :macros, :sigils).

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Import.ImportDirective{module: [:Kernel], only: :macros}
      iex> ElixirOntologies.Extractors.Directive.Import.type_import?(directive)
      true

      iex> directive = %ElixirOntologies.Extractors.Directive.Import.ImportDirective{module: [:Enum], only: [map: 2]}
      iex> ElixirOntologies.Extractors.Directive.Import.type_import?(directive)
      false
  """
  @spec type_import?(ImportDirective.t()) :: boolean()
  def type_import?(%ImportDirective{only: only}) when only in [:functions, :macros, :sigils],
    do: true

  def type_import?(_), do: false

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp build_directive(module_parts, only, except, node, opts) do
    location = Helpers.extract_location_if(node, opts)

    {:ok,
     %ImportDirective{
       module: module_parts,
       only: only,
       except: except,
       location: location,
       metadata: %{}
     }}
  end

  defp extract_only_option(opts) do
    case Keyword.get(opts, :only) do
      # Type-based imports
      :functions -> :functions
      :macros -> :macros
      :sigils -> :sigils
      # Function/arity list
      list when is_list(list) -> list
      _ -> nil
    end
  end

  defp extract_except_option(opts) do
    case Keyword.get(opts, :except) do
      list when is_list(list) -> list
      _ -> nil
    end
  end

  defp do_extract_all(ast, opts) do
    case extract(ast, opts) do
      {:ok, directive} -> [directive]
      {:error, _} -> []
    end
  end
end
