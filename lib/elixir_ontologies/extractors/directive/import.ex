defmodule ElixirOntologies.Extractors.Directive.Import do
  @moduledoc """
  Extracts import directive information from Elixir AST.

  This module provides detailed extraction of import directives including the
  imported module, selective imports (only/except options), and source location.

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

  defmodule ImportConflict do
    @moduledoc """
    Represents a detected import conflict where multiple imports bring the same function into scope.

    ## Fields

    - `:function` - The conflicting function as `{name, arity}` tuple
    - `:imports` - List of ImportDirective structs that conflict
    - `:conflict_type` - `:explicit` for known conflicts, `:potential` for possible conflicts
    - `:location` - Location of first conflicting import (for error reporting)
    """

    alias ElixirOntologies.Extractors.Directive.Import.ImportDirective
    alias ElixirOntologies.Analyzer.Location.SourceLocation

    @type conflict_type :: :explicit | :potential

    @type t :: %__MODULE__{
            function: {atom(), non_neg_integer()},
            imports: [ImportDirective.t()],
            conflict_type: conflict_type(),
            location: SourceLocation.t() | nil
          }

    @enforce_keys [:function]
    defstruct [:function, :location, imports: [], conflict_type: :explicit]
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
  # Conflict Detection
  # ===========================================================================

  @doc """
  Detects import conflicts where multiple imports bring the same function into scope.

  This function analyzes a list of import directives and identifies cases where
  the same function (name/arity) is explicitly imported from multiple modules.

  Note: Only explicit conflicts are detected (where `only:` specifies the same function).
  Full imports cannot be analyzed without knowing what each module exports.

  ## Examples

      iex> imports = [
      ...>   %ElixirOntologies.Extractors.Directive.Import.ImportDirective{
      ...>     module: [:Enum],
      ...>     only: [map: 2]
      ...>   },
      ...>   %ElixirOntologies.Extractors.Directive.Import.ImportDirective{
      ...>     module: [:Stream],
      ...>     only: [map: 2]
      ...>   }
      ...> ]
      iex> conflicts = ElixirOntologies.Extractors.Directive.Import.detect_import_conflicts(imports)
      iex> length(conflicts)
      1
      iex> hd(conflicts).function
      {:map, 2}

      iex> imports = [
      ...>   %ElixirOntologies.Extractors.Directive.Import.ImportDirective{
      ...>     module: [:Enum],
      ...>     only: [map: 2]
      ...>   },
      ...>   %ElixirOntologies.Extractors.Directive.Import.ImportDirective{
      ...>     module: [:String],
      ...>     only: [upcase: 1]
      ...>   }
      ...> ]
      iex> ElixirOntologies.Extractors.Directive.Import.detect_import_conflicts(imports)
      []
  """
  @spec detect_import_conflicts([ImportDirective.t()]) :: [ImportConflict.t()]
  def detect_import_conflicts(imports) when is_list(imports) do
    # Build a map of function -> list of imports that explicitly import it
    imports
    |> Enum.flat_map(fn directive ->
      directive
      |> explicit_imports()
      |> Enum.map(fn func -> {func, directive} end)
    end)
    |> Enum.group_by(fn {func, _} -> func end, fn {_, directive} -> directive end)
    |> Enum.filter(fn {_func, directives} -> length(directives) > 1 end)
    |> Enum.map(fn {func, directives} ->
      # Get location from first directive
      first_location =
        directives
        |> Enum.map(& &1.location)
        |> Enum.find(&(&1 != nil))

      %ImportConflict{
        function: func,
        imports: directives,
        conflict_type: :explicit,
        location: first_location
      }
    end)
    |> Enum.sort_by(fn conflict -> conflict.function end)
  end

  @doc """
  Returns the list of explicitly imported functions from an import directive.

  For imports with `only: [func: arity, ...]`, returns the function list.
  For full imports or type-based imports, returns an empty list since we cannot
  determine what functions are imported without analyzing the target module.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Import.ImportDirective{
      ...>   module: [:Enum],
      ...>   only: [map: 2, filter: 2]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Import.explicit_imports(directive)
      [{:map, 2}, {:filter, 2}]

      iex> directive = %ElixirOntologies.Extractors.Directive.Import.ImportDirective{
      ...>   module: [:Enum]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Import.explicit_imports(directive)
      []

      iex> directive = %ElixirOntologies.Extractors.Directive.Import.ImportDirective{
      ...>   module: [:Kernel],
      ...>   only: :macros
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Import.explicit_imports(directive)
      []
  """
  @spec explicit_imports(ImportDirective.t()) :: [{atom(), non_neg_integer()}]
  def explicit_imports(%ImportDirective{only: only}) when is_list(only) do
    # Convert keyword list to tuple list for consistent representation
    Enum.map(only, fn
      {name, arity} when is_atom(name) and is_integer(arity) -> {name, arity}
    end)
  end

  def explicit_imports(%ImportDirective{}), do: []

  # ===========================================================================
  # Scope-Aware Extraction
  # ===========================================================================

  @doc """
  Extracts all import directives from a module body with scope tracking.

  This function walks the AST and tracks the lexical scope of each import,
  setting the `:scope` field to `:module`, `:function`, or `:block`.

  ## Examples

      iex> {:defmodule, _, [_, [do: {:__block__, _, body}]]} = quote do
      ...>   defmodule Test do
      ...>     import Enum
      ...>     def foo do
      ...>       import String
      ...>     end
      ...>   end
      ...> end
      iex> directives = ElixirOntologies.Extractors.Directive.Import.extract_all_with_scope(body)
      iex> length(directives)
      2
      iex> [enum_import, string_import] = directives
      iex> enum_import.scope
      :module
      iex> string_import.scope
      :function
  """
  @spec extract_all_with_scope(Macro.t(), keyword()) :: [ImportDirective.t()]
  def extract_all_with_scope(ast, opts \\ []) do
    extract_with_scope(ast, :module, opts)
  end

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

  # ===========================================================================
  # Scope Tracking Helpers
  # ===========================================================================

  # Extract imports with scope tracking
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

  # Handle import - extract with current scope
  defp extract_with_scope({:import, _meta, _args} = ast, current_scope, opts) do
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
