defmodule ElixirOntologies.Extractors.Directive.Common do
  @moduledoc """
  Common utilities shared across directive extractors.

  This module provides helper functions used by all directive extractors
  (Alias, Import, Require, Use) to reduce code duplication and ensure
  consistent behavior.

  ## Shared Functionality

  - Location extraction from AST metadata
  - Module name extraction from `{:__aliases__, _, parts}` AST nodes
  - Module name string formatting
  - Common error formatting

  ## Usage

  These functions are used internally by directive extractors:

      alias ElixirOntologies.Extractors.Directive.Common

      # Extract location from AST node
      location = Common.extract_location(ast, opts)

      # Extract module parts from aliases AST
      {:ok, parts} = Common.extract_module_parts({:__aliases__, [], [:MyApp, :Users]})

      # Convert parts to string
      name = Common.module_parts_to_string([:MyApp, :Users])
      # => "MyApp.Users"
  """

  alias ElixirOntologies.Extractors.Helpers
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # ===========================================================================
  # Location Extraction
  # ===========================================================================

  @doc """
  Extracts source location from an AST node if requested by options.

  ## Options

  - `:include_location` - Whether to extract location (default: true)

  ## Examples

      iex> ast = {:alias, [line: 5, column: 3], [{:__aliases__, [], [:MyApp]}]}
      iex> location = ElixirOntologies.Extractors.Directive.Common.extract_location(ast, [])
      iex> location.start_line
      5

      iex> ast = {:alias, [line: 5], [{:__aliases__, [], [:MyApp]}]}
      iex> ElixirOntologies.Extractors.Directive.Common.extract_location(ast, include_location: false)
      nil
  """
  @spec extract_location(Macro.t(), keyword()) :: SourceLocation.t() | nil
  def extract_location(ast, opts) do
    Helpers.extract_location_if(ast, opts)
  end

  # ===========================================================================
  # Module Name Extraction
  # ===========================================================================

  @doc """
  Extracts module parts from an `{:__aliases__, _, parts}` AST node.

  Returns `{:ok, parts}` where parts is a list of atoms representing the module path,
  or `{:error, reason}` if the AST is not a valid module reference.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Common.extract_module_parts({:__aliases__, [], [:MyApp, :Users]})
      {:ok, [:MyApp, :Users]}

      iex> ElixirOntologies.Extractors.Directive.Common.extract_module_parts("not_a_module")
      {:error, :not_a_module_reference}

      iex> ElixirOntologies.Extractors.Directive.Common.extract_module_parts(:crypto)
      {:ok, [:crypto]}
  """
  @spec extract_module_parts(Macro.t()) :: {:ok, [atom()]} | {:error, atom()}
  def extract_module_parts({:__aliases__, _meta, parts}) when is_list(parts) do
    {:ok, parts}
  end

  def extract_module_parts(module) when is_atom(module) do
    {:ok, [module]}
  end

  def extract_module_parts(_) do
    {:error, :not_a_module_reference}
  end

  @doc """
  Extracts module parts from an AST node, raising on error.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Common.extract_module_parts!({:__aliases__, [], [:MyApp]})
      [:MyApp]
  """
  @spec extract_module_parts!(Macro.t()) :: [atom()]
  def extract_module_parts!(ast) do
    case extract_module_parts(ast) do
      {:ok, parts} -> parts
      {:error, reason} -> raise ArgumentError, "Not a module reference: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Module Name Formatting
  # ===========================================================================

  @doc """
  Converts a list of module name atoms to a dot-separated string.

  Handles both Elixir modules (UpperCamelCase) and Erlang modules (lowercase atoms).

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Common.module_parts_to_string([:MyApp, :Users, :Admin])
      "MyApp.Users.Admin"

      iex> ElixirOntologies.Extractors.Directive.Common.module_parts_to_string([:crypto])
      "crypto"

      iex> ElixirOntologies.Extractors.Directive.Common.module_parts_to_string([:Enum])
      "Enum"
  """
  @spec module_parts_to_string([atom()]) :: String.t()
  def module_parts_to_string([single]) when is_atom(single) do
    Atom.to_string(single)
  end

  def module_parts_to_string(parts) when is_list(parts) do
    Enum.map_join(parts, ".", &Atom.to_string/1)
  end

  # ===========================================================================
  # Error Formatting
  # ===========================================================================

  @doc """
  Formats an error with a descriptive message and the problematic AST.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Common.format_error("Not an alias", {:foo, [], []})
      "Not an alias: {:foo, [], []}"
  """
  @spec format_error(String.t(), Macro.t()) :: String.t()
  def format_error(message, ast) do
    Helpers.format_error(message, ast)
  end

  # ===========================================================================
  # Directive Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node is a directive of the given type.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Common.directive?({:alias, [], [{:__aliases__, [], [:Foo]}]}, :alias)
      true

      iex> ElixirOntologies.Extractors.Directive.Common.directive?({:import, [], [{:__aliases__, [], [:Enum]}]}, :alias)
      false
  """
  @spec directive?(Macro.t(), atom()) :: boolean()
  def directive?({directive_type, _meta, [_ | _]}, expected_type)
      when directive_type == expected_type,
      do: true

  def directive?(_, _), do: false

  # ===========================================================================
  # Scope Helpers
  # ===========================================================================

  @doc """
  Determines if an AST node represents a function definition.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Common.function_definition?({:def, [], [{:foo, [], nil}, [do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.Directive.Common.function_definition?({:defp, [], [{:bar, [], nil}, [do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.Directive.Common.function_definition?({:alias, [], [{:__aliases__, [], [:Foo]}]})
      false
  """
  @spec function_definition?(Macro.t()) :: boolean()
  def function_definition?({def_type, _meta, [{name, _, _args}, _body]})
      when def_type in [:def, :defp, :defmacro, :defmacrop] and is_atom(name),
      do: true

  def function_definition?({def_type, _meta, [{:when, _, [{name, _, _args}, _guard]}, _body]})
      when def_type in [:def, :defp, :defmacro, :defmacrop] and is_atom(name),
      do: true

  def function_definition?(_), do: false

  @doc """
  Determines if an AST node represents a block construct that changes scope.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Common.block_construct?({:if, [], [true, [do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.Directive.Common.block_construct?({:case, [], [:foo, [do: []]]})
      true

      iex> ElixirOntologies.Extractors.Directive.Common.block_construct?({:def, [], [{:foo, [], nil}, [do: :ok]]})
      false
  """
  @spec block_construct?(Macro.t()) :: boolean()
  def block_construct?({block_type, _meta, args})
      when block_type in [:if, :unless, :case, :cond, :with, :for, :try, :receive] and
             is_list(args),
      do: true

  def block_construct?(_), do: false

  @doc """
  Extracts the body from a function definition AST.

  ## Examples

      iex> ast = {:def, [], [{:foo, [], nil}, [do: {:__block__, [], [:ok]}]]}
      iex> ElixirOntologies.Extractors.Directive.Common.extract_function_body(ast)
      {:__block__, [], [:ok]}

      iex> ast = {:def, [], [{:foo, [], nil}, [do: nil]]}
      iex> ElixirOntologies.Extractors.Directive.Common.extract_function_body(ast)
      nil

      iex> ElixirOntologies.Extractors.Directive.Common.extract_function_body(:not_a_function)
      nil
  """
  @spec extract_function_body(Macro.t()) :: Macro.t() | nil
  def extract_function_body({def_type, _meta, [{_name, _, _args}, body_opts]})
      when def_type in [:def, :defp, :defmacro, :defmacrop] do
    Keyword.get(body_opts, :do, nil)
  end

  def extract_function_body(
        {def_type, _meta, [{:when, _, [{_name, _, _args}, _guard]}, body_opts]}
      )
      when def_type in [:def, :defp, :defmacro, :defmacrop] do
    Keyword.get(body_opts, :do, nil)
  end

  def extract_function_body(_), do: nil
end
