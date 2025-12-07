defmodule ElixirOntologies.Extractors.Module do
  @moduledoc """
  Extracts module definitions from AST nodes.

  This module analyzes Elixir AST nodes representing `defmodule` constructs and
  extracts their name, documentation, directives, and contained definitions.
  Supports the module-related classes from elixir-structure.ttl:

  - Module: `defmodule MyApp.Users do ... end`
  - NestedModule: Module defined inside another module
  - ModuleAlias: `alias MyApp.Users, as: U`
  - Import: `import Enum, only: [map: 2]`
  - Require: `require Logger`
  - Use: `use GenServer`

  ## Usage

      iex> alias ElixirOntologies.Extractors.Module
      iex> ast = quote do
      ...>   defmodule MyApp.Users do
      ...>     @moduledoc "User management"
      ...>     def list, do: []
      ...>   end
      ...> end
      iex> {:ok, result} = Module.extract(ast)
      iex> result.name
      [:MyApp, :Users]
      iex> result.docstring
      "User management"

      iex> alias ElixirOntologies.Extractors.Module
      iex> ast = {:defmodule, [], [{:__aliases__, [], [:Simple]}, [do: nil]]}
      iex> {:ok, result} = Module.extract(ast)
      iex> result.type
      :module
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of module extraction.

  - `:type` - Either `:module` or `:nested_module`
  - `:name` - Module name as list of atoms (e.g., `[:MyApp, :Users]`)
  - `:docstring` - Module documentation from @moduledoc (string, false, or nil)
  - `:aliases` - List of alias directives
  - `:imports` - List of import directives with :only/:except
  - `:requires` - List of require directives
  - `:uses` - List of use directives with options
  - `:functions` - List of function definitions found
  - `:macros` - List of macro definitions found
  - `:types` - List of type definitions found
  - `:location` - Source location if available
  - `:metadata` - Additional information (parent_module, etc.)
  """
  @type t :: %__MODULE__{
          type: :module | :nested_module,
          name: [atom()],
          docstring: String.t() | false | nil,
          aliases: [alias_info()],
          imports: [import_info()],
          requires: [require_info()],
          uses: [use_info()],
          functions: [function_info()],
          macros: [macro_info()],
          types: [type_info()],
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @type alias_info :: %{
          module: [atom()],
          as: atom() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  @type import_info :: %{
          module: [atom()] | atom(),
          only: keyword() | nil,
          except: keyword() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  @type require_info :: %{
          module: [atom()] | atom(),
          as: atom() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  @type use_info :: %{
          module: [atom()] | atom(),
          opts: keyword() | Macro.t(),
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  @type function_info :: %{
          name: atom(),
          arity: non_neg_integer(),
          visibility: :public | :private
        }

  @type macro_info :: %{
          name: atom(),
          arity: non_neg_integer(),
          visibility: :public | :private
        }

  @type type_info :: %{
          name: atom(),
          arity: non_neg_integer(),
          visibility: :public | :private | :opaque
        }

  defstruct [
    :type,
    :name,
    :docstring,
    aliases: [],
    imports: [],
    requires: [],
    uses: [],
    functions: [],
    macros: [],
    types: [],
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a module definition.

  ## Examples

      iex> ElixirOntologies.Extractors.Module.module?({:defmodule, [], [{:__aliases__, [], [:Foo]}, [do: nil]]})
      true

      iex> ElixirOntologies.Extractors.Module.module?({:def, [], [{:foo, [], nil}]})
      false

      iex> ElixirOntologies.Extractors.Module.module?(:not_a_module)
      false
  """
  @spec module?(Macro.t()) :: boolean()
  def module?({:defmodule, _meta, [_name, _body]}), do: true
  def module?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a module definition from an AST node.

  Returns `{:ok, %Module{}}` on success, or `{:error, reason}` if the node
  is not a module definition.

  ## Options

  - `:parent_module` - Parent module name (list of atoms) if this is a nested module

  ## Examples

      iex> ast = {:defmodule, [], [{:__aliases__, [], [:MyModule]}, [do: nil]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Module.extract(ast)
      iex> result.name
      [:MyModule]
      iex> result.type
      :module

      iex> ast = {:defmodule, [], [{:__aliases__, [], [:Child]}, [do: nil]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Module.extract(ast, parent_module: [:Parent])
      iex> result.type
      :nested_module
      iex> result.metadata.parent_module
      [:Parent]

      iex> {:error, _} = ElixirOntologies.Extractors.Module.extract({:def, [], []})
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  def extract({:defmodule, meta, [{:__aliases__, _, name_parts}, body_opts]} = node, opts)
      when is_list(name_parts) do
    parent_module = Keyword.get(opts, :parent_module)
    body = extract_body(body_opts)

    module_type = if parent_module, do: :nested_module, else: :module

    {:ok,
     %__MODULE__{
       type: module_type,
       name: name_parts,
       docstring: extract_moduledoc(body),
       aliases: extract_aliases(body),
       imports: extract_imports(body),
       requires: extract_requires(body),
       uses: extract_uses(body),
       functions: extract_functions(body),
       macros: extract_macros(body),
       types: extract_types(body),
       location: Helpers.extract_location(node),
       metadata: build_metadata(parent_module, body, meta)
     }}
  end

  # Handle single atom module name (rare but valid)
  def extract({:defmodule, meta, [name, body_opts]} = node, opts) when is_atom(name) do
    parent_module = Keyword.get(opts, :parent_module)
    body = extract_body(body_opts)

    module_type = if parent_module, do: :nested_module, else: :module

    {:ok,
     %__MODULE__{
       type: module_type,
       name: [name],
       docstring: extract_moduledoc(body),
       aliases: extract_aliases(body),
       imports: extract_imports(body),
       requires: extract_requires(body),
       uses: extract_uses(body),
       functions: extract_functions(body),
       macros: extract_macros(body),
       types: extract_types(body),
       location: Helpers.extract_location(node),
       metadata: build_metadata(parent_module, body, meta)
     }}
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Not a module definition", node)}
  end

  @doc """
  Extracts a module definition, raising on error.

  ## Examples

      iex> ast = {:defmodule, [], [{:__aliases__, [], [:MyModule]}, [do: nil]]}
      iex> result = ElixirOntologies.Extractors.Module.extract!(ast)
      iex> result.name
      [:MyModule]
  """
  @spec extract!(Macro.t(), keyword()) :: t()
  def extract!(node, opts \\ []) do
    case extract(node, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Returns the full module name as a string.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Module
      iex> ast = {:defmodule, [], [{:__aliases__, [], [:MyApp, :Users]}, [do: nil]]}
      iex> {:ok, result} = Module.extract(ast)
      iex> Module.module_name_string(result)
      "MyApp.Users"
  """
  @spec module_name_string(t()) :: String.t()
  def module_name_string(%__MODULE__{name: name}) when is_list(name) do
    Enum.join(name, ".")
  end

  @doc """
  Returns the full module name as an atom (Elixir module format).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Module
      iex> ast = {:defmodule, [], [{:__aliases__, [], [:MyApp, :Users]}, [do: nil]]}
      iex> {:ok, result} = Module.extract(ast)
      iex> Module.module_name_atom(result)
      MyApp.Users
  """
  @spec module_name_atom(t()) :: atom()
  def module_name_atom(%__MODULE__{name: name}) when is_list(name) do
    Module.concat(name)
  end

  @doc """
  Checks if the module has documentation.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Module
      iex> ast = quote do
      ...>   defmodule Documented do
      ...>     @moduledoc "Has docs"
      ...>   end
      ...> end
      iex> {:ok, result} = Module.extract(ast)
      iex> Module.has_docs?(result)
      true

      iex> alias ElixirOntologies.Extractors.Module
      iex> ast = {:defmodule, [], [{:__aliases__, [], [:NoDoc]}, [do: nil]]}
      iex> {:ok, result} = Module.extract(ast)
      iex> Module.has_docs?(result)
      false
  """
  @spec has_docs?(t()) :: boolean()
  def has_docs?(%__MODULE__{docstring: nil}), do: false
  def has_docs?(%__MODULE__{docstring: false}), do: false
  def has_docs?(%__MODULE__{docstring: _}), do: true

  @doc """
  Checks if documentation is explicitly hidden with `@moduledoc false`.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Module
      iex> ast = quote do
      ...>   defmodule Hidden do
      ...>     @moduledoc false
      ...>   end
      ...> end
      iex> {:ok, result} = Module.extract(ast)
      iex> Module.docs_hidden?(result)
      true
  """
  @spec docs_hidden?(t()) :: boolean()
  def docs_hidden?(%__MODULE__{docstring: false}), do: true
  def docs_hidden?(%__MODULE__{}), do: false

  # ===========================================================================
  # Private Helpers - Body Extraction
  # ===========================================================================

  defp extract_body(do: body), do: body
  defp extract_body([{:do, body} | _rest]), do: body
  defp extract_body(body_opts) when is_list(body_opts), do: Keyword.get(body_opts, :do)
  defp extract_body(_), do: nil

  defp build_metadata(parent_module, body, _meta) do
    %{
      parent_module: parent_module,
      has_moduledoc: has_moduledoc?(body),
      nested_modules: extract_nested_module_names(body)
    }
  end

  # ===========================================================================
  # Private Helpers - Moduledoc Extraction
  # ===========================================================================

  defp extract_moduledoc(nil), do: nil

  defp extract_moduledoc({:__block__, _, statements}) when is_list(statements) do
    find_moduledoc(statements)
  end

  defp extract_moduledoc(statement) do
    find_moduledoc([statement])
  end

  defp find_moduledoc(statements) do
    Enum.reduce_while(statements, nil, fn
      {:@, _, [{:moduledoc, _, [content]}]}, _acc ->
        {:halt, extract_doc_content(content)}

      _, acc ->
        {:cont, acc}
    end)
  end

  defp has_moduledoc?(body) do
    case extract_moduledoc(body) do
      nil -> false
      # @moduledoc false still counts as having a moduledoc
      false -> true
      _ -> true
    end
  end

  defp extract_doc_content(false), do: false
  defp extract_doc_content(content) when is_binary(content), do: content
  # Handle heredoc format
  defp extract_doc_content({:sigil_S, _, [{:<<>>, _, [content]}, []]}), do: content
  defp extract_doc_content({:<<>>, _, parts}), do: extract_binary_parts(parts)
  defp extract_doc_content(_), do: nil

  defp extract_binary_parts(parts) when is_list(parts) do
    Enum.map_join(parts, "", fn
      part when is_binary(part) -> part
      _ -> ""
    end)
  end

  # ===========================================================================
  # Private Helpers - Alias Extraction
  # ===========================================================================

  defp extract_aliases(nil), do: []

  defp extract_aliases({:__block__, _, statements}) when is_list(statements) do
    Enum.flat_map(statements, &extract_alias_from_statement/1)
  end

  defp extract_aliases(statement) do
    extract_alias_from_statement(statement)
  end

  defp extract_alias_from_statement({:alias, meta, args}) do
    [parse_alias(args, meta)]
  end

  defp extract_alias_from_statement(_), do: []

  defp parse_alias([{:__aliases__, _, parts}], meta) do
    %{
      module: parts,
      as: nil,
      location: Helpers.extract_location({:alias, meta, []})
    }
  end

  defp parse_alias([{:__aliases__, _, parts}, opts], meta) when is_list(opts) do
    as_opt =
      case Keyword.get(opts, :as) do
        {:__aliases__, _, [as_name]} -> as_name
        as_name when is_atom(as_name) -> as_name
        _ -> nil
      end

    %{
      module: parts,
      as: as_opt,
      location: Helpers.extract_location({:alias, meta, []})
    }
  end

  defp parse_alias(_, meta) do
    %{module: [], as: nil, location: Helpers.extract_location({:alias, meta, []})}
  end

  # ===========================================================================
  # Private Helpers - Import Extraction
  # ===========================================================================

  defp extract_imports(nil), do: []

  defp extract_imports({:__block__, _, statements}) when is_list(statements) do
    Enum.flat_map(statements, &extract_import_from_statement/1)
  end

  defp extract_imports(statement) do
    extract_import_from_statement(statement)
  end

  defp extract_import_from_statement({:import, meta, args}) do
    [parse_import(args, meta)]
  end

  defp extract_import_from_statement(_), do: []

  defp parse_import([{:__aliases__, _, parts}], meta) do
    %{
      module: parts,
      only: nil,
      except: nil,
      location: Helpers.extract_location({:import, meta, []})
    }
  end

  defp parse_import([{:__aliases__, _, parts}, opts], meta) when is_list(opts) do
    %{
      module: parts,
      only: Keyword.get(opts, :only),
      except: Keyword.get(opts, :except),
      location: Helpers.extract_location({:import, meta, []})
    }
  end

  # Handle erlang module import (atom)
  defp parse_import([module], meta) when is_atom(module) do
    %{
      module: module,
      only: nil,
      except: nil,
      location: Helpers.extract_location({:import, meta, []})
    }
  end

  defp parse_import([module, opts], meta) when is_atom(module) and is_list(opts) do
    %{
      module: module,
      only: Keyword.get(opts, :only),
      except: Keyword.get(opts, :except),
      location: Helpers.extract_location({:import, meta, []})
    }
  end

  defp parse_import(_, meta) do
    %{module: [], only: nil, except: nil, location: Helpers.extract_location({:import, meta, []})}
  end

  # ===========================================================================
  # Private Helpers - Require Extraction
  # ===========================================================================

  defp extract_requires(nil), do: []

  defp extract_requires({:__block__, _, statements}) when is_list(statements) do
    Enum.flat_map(statements, &extract_require_from_statement/1)
  end

  defp extract_requires(statement) do
    extract_require_from_statement(statement)
  end

  defp extract_require_from_statement({:require, meta, args}) do
    [parse_require(args, meta)]
  end

  defp extract_require_from_statement(_), do: []

  defp parse_require([{:__aliases__, _, parts}], meta) do
    %{
      module: parts,
      as: nil,
      location: Helpers.extract_location({:require, meta, []})
    }
  end

  defp parse_require([{:__aliases__, _, parts}, opts], meta) when is_list(opts) do
    as_opt =
      case Keyword.get(opts, :as) do
        {:__aliases__, _, [as_name]} -> as_name
        as_name when is_atom(as_name) -> as_name
        _ -> nil
      end

    %{
      module: parts,
      as: as_opt,
      location: Helpers.extract_location({:require, meta, []})
    }
  end

  # Handle erlang module require
  defp parse_require([module], meta) when is_atom(module) do
    %{
      module: module,
      as: nil,
      location: Helpers.extract_location({:require, meta, []})
    }
  end

  defp parse_require(_, meta) do
    %{module: [], as: nil, location: Helpers.extract_location({:require, meta, []})}
  end

  # ===========================================================================
  # Private Helpers - Use Extraction
  # ===========================================================================

  defp extract_uses(nil), do: []

  defp extract_uses({:__block__, _, statements}) when is_list(statements) do
    Enum.flat_map(statements, &extract_use_from_statement/1)
  end

  defp extract_uses(statement) do
    extract_use_from_statement(statement)
  end

  defp extract_use_from_statement({:use, meta, args}) do
    [parse_use(args, meta)]
  end

  defp extract_use_from_statement(_), do: []

  defp parse_use([{:__aliases__, _, parts}], meta) do
    %{
      module: parts,
      opts: [],
      location: Helpers.extract_location({:use, meta, []})
    }
  end

  defp parse_use([{:__aliases__, _, parts}, opts], meta) do
    %{
      module: parts,
      opts: opts,
      location: Helpers.extract_location({:use, meta, []})
    }
  end

  # Handle erlang module use (rare)
  defp parse_use([module], meta) when is_atom(module) do
    %{
      module: module,
      opts: [],
      location: Helpers.extract_location({:use, meta, []})
    }
  end

  defp parse_use([module, opts], meta) when is_atom(module) do
    %{
      module: module,
      opts: opts,
      location: Helpers.extract_location({:use, meta, []})
    }
  end

  defp parse_use(_, meta) do
    %{module: [], opts: [], location: Helpers.extract_location({:use, meta, []})}
  end

  # ===========================================================================
  # Private Helpers - Function Extraction
  # ===========================================================================

  defp extract_functions(nil), do: []

  defp extract_functions({:__block__, _, statements}) when is_list(statements) do
    statements
    |> Enum.flat_map(&extract_function_from_statement/1)
    |> Enum.uniq_by(fn %{name: n, arity: a} -> {n, a} end)
  end

  defp extract_functions(statement) do
    extract_function_from_statement(statement)
  end

  defp extract_function_from_statement({:def, _, [{:when, _, [{name, _, args}, _guard]}, _body]})
       when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :public}]
  end

  defp extract_function_from_statement({:def, _, [{name, _, args}, _body]}) when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :public}]
  end

  defp extract_function_from_statement({:def, _, [{name, _, args}]}) when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :public}]
  end

  defp extract_function_from_statement({:defp, _, [{:when, _, [{name, _, args}, _guard]}, _body]})
       when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :private}]
  end

  defp extract_function_from_statement({:defp, _, [{name, _, args}, _body]}) when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :private}]
  end

  defp extract_function_from_statement({:defp, _, [{name, _, args}]}) when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :private}]
  end

  defp extract_function_from_statement(_), do: []

  # ===========================================================================
  # Private Helpers - Macro Extraction
  # ===========================================================================

  defp extract_macros(nil), do: []

  defp extract_macros({:__block__, _, statements}) when is_list(statements) do
    statements
    |> Enum.flat_map(&extract_macro_from_statement/1)
    |> Enum.uniq_by(fn %{name: n, arity: a} -> {n, a} end)
  end

  defp extract_macros(statement) do
    extract_macro_from_statement(statement)
  end

  defp extract_macro_from_statement(
         {:defmacro, _, [{:when, _, [{name, _, args}, _guard]}, _body]}
       )
       when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :public}]
  end

  defp extract_macro_from_statement({:defmacro, _, [{name, _, args}, _body]})
       when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :public}]
  end

  defp extract_macro_from_statement({:defmacro, _, [{name, _, args}]}) when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :public}]
  end

  defp extract_macro_from_statement(
         {:defmacrop, _, [{:when, _, [{name, _, args}, _guard]}, _body]}
       )
       when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :private}]
  end

  defp extract_macro_from_statement({:defmacrop, _, [{name, _, args}, _body]})
       when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :private}]
  end

  defp extract_macro_from_statement({:defmacrop, _, [{name, _, args}]}) when is_atom(name) do
    [%{name: name, arity: args_length(args), visibility: :private}]
  end

  defp extract_macro_from_statement(_), do: []

  # ===========================================================================
  # Private Helpers - Type Extraction
  # ===========================================================================

  defp extract_types(nil), do: []

  defp extract_types({:__block__, _, statements}) when is_list(statements) do
    statements
    |> Enum.flat_map(&extract_type_from_statement/1)
    |> Enum.uniq_by(fn %{name: n, arity: a} -> {n, a} end)
  end

  defp extract_types(statement) do
    extract_type_from_statement(statement)
  end

  defp extract_type_from_statement({:@, _, [{type_kind, _, [type_def]}]})
       when type_kind in [:type, :typep, :opaque] do
    case extract_type_info(type_def) do
      nil -> []
      info -> [Map.put(info, :visibility, type_visibility(type_kind))]
    end
  end

  defp extract_type_from_statement(_), do: []

  defp extract_type_info({:"::", _, [{name, _, args}, _type_expr]}) when is_atom(name) do
    %{name: name, arity: args_length(args)}
  end

  defp extract_type_info({name, _, args}) when is_atom(name) do
    %{name: name, arity: args_length(args)}
  end

  defp extract_type_info(_), do: nil

  defp type_visibility(:type), do: :public
  defp type_visibility(:typep), do: :private
  defp type_visibility(:opaque), do: :opaque

  # ===========================================================================
  # Private Helpers - Nested Module Extraction
  # ===========================================================================

  defp extract_nested_module_names(nil), do: []

  defp extract_nested_module_names({:__block__, _, statements}) when is_list(statements) do
    Enum.flat_map(statements, &extract_nested_module_name/1)
  end

  defp extract_nested_module_names(statement) do
    extract_nested_module_name(statement)
  end

  defp extract_nested_module_name({:defmodule, _, [{:__aliases__, _, parts}, _body]}) do
    [parts]
  end

  defp extract_nested_module_name(_), do: []

  # ===========================================================================
  # Private Helpers - Utility
  # ===========================================================================

  # In Elixir AST, args can be a list of arguments or an atom (the context)
  # when there are no arguments. This helper handles both cases.
  defp args_length(args) when is_list(args), do: length(args)
  defp args_length(_), do: 0
end
