defmodule ElixirOntologies.Extractors.Struct do
  @moduledoc """
  Extracts struct and exception definitions from AST nodes.

  This module analyzes Elixir AST nodes representing `defstruct` and `defexception`
  constructs. Supports the struct-related classes from elixir-structure.ttl:

  - Struct: A module with defstruct
  - StructField: A field in the struct
  - EnforcedKey: A field marked in @enforce_keys
  - Exception: A module with defexception (subtype of Struct)

  ## Struct Usage

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defstruct [:name, :email, age: 0]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract(ast)
      iex> length(result.fields)
      3
      iex> Struct.field_names(result)
      [:name, :email, :age]

  ## Extracting from Module Body

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule User do @enforce_keys [:name]; defstruct [:name, :email] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_from_body(body)
      iex> result.enforce_keys
      [:name]

  ## Exception Usage

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defexception message: \\"not found\\""
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_exception(ast)
      iex> result.default_message
      "not found"
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of struct extraction.

  - `:fields` - List of struct field definitions
  - `:enforce_keys` - List of field names from @enforce_keys
  - `:derives` - List of @derive directives (from Helpers.DeriveInfo)
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          fields: [field()],
          enforce_keys: [atom()],
          derives: [Helpers.DeriveInfo.t()],
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @typedoc """
  A struct field definition.

  - `:name` - Field name as atom
  - `:has_default` - Whether the field has a default value
  - `:default_value` - The default value (nil if no default)
  - `:location` - Source location (typically nil for fields)
  """
  @type field :: %{
          name: atom(),
          has_default: boolean(),
          default_value: term() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  defstruct [
    fields: [],
    enforce_keys: [],
    derives: [],
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Exception Result Struct
  # ===========================================================================

  defmodule Exception do
    @moduledoc """
    Represents an extracted exception definition.

    Exceptions are a special form of struct with additional properties:
    - `has_custom_message` - Whether a custom `message/1` is defined
    - `default_message` - The default message value if present
    """

    @typedoc """
    The result of exception extraction.

    - `:fields` - List of exception field definitions
    - `:enforce_keys` - List of field names from @enforce_keys
    - `:derives` - List of @derive directives
    - `:has_custom_message` - Whether module defines custom message/1
    - `:default_message` - Default message string if present
    - `:location` - Source location if available
    - `:metadata` - Additional information
    """
    @type t :: %__MODULE__{
            fields: [ElixirOntologies.Extractors.Struct.field()],
            enforce_keys: [atom()],
            derives: [ElixirOntologies.Extractors.Helpers.DeriveInfo.t()],
            has_custom_message: boolean(),
            default_message: String.t() | nil,
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct [
      fields: [],
      enforce_keys: [],
      derives: [],
      has_custom_message: false,
      default_message: nil,
      location: nil,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a defstruct definition.

  ## Examples

      iex> ElixirOntologies.Extractors.Struct.struct?({:defstruct, [], [[:name, :email]]})
      true

      iex> ElixirOntologies.Extractors.Struct.struct?({:defmodule, [], [{:__aliases__, [], [:Foo]}, [do: nil]]})
      false

      iex> ElixirOntologies.Extractors.Struct.struct?(:not_a_struct)
      false
  """
  @spec struct?(Macro.t()) :: boolean()
  def struct?({:defstruct, _meta, _args}), do: true
  def struct?(_), do: false

  @doc """
  Checks if an AST node represents a defexception definition.

  ## Examples

      iex> ElixirOntologies.Extractors.Struct.exception?({:defexception, [], [[:message]]})
      true

      iex> ElixirOntologies.Extractors.Struct.exception?({:defstruct, [], [[:name]]})
      false

      iex> ElixirOntologies.Extractors.Struct.exception?(:not_exception)
      false
  """
  @spec exception?(Macro.t()) :: boolean()
  def exception?({:defexception, _meta, _args}), do: true
  def exception?(_), do: false

  # ===========================================================================
  # Direct Extraction (from defstruct node)
  # ===========================================================================

  @doc """
  Extracts struct information from a defstruct AST node.

  Returns `{:ok, result}` with a `Struct` struct containing the fields.
  Note: This extracts only from the defstruct node itself. Use `extract_from_body/2`
  to also get @enforce_keys and @derive from the module body.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defstruct [:name, :email]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract(ast)
      iex> length(result.fields)
      2

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defstruct name: nil, age: 0"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract(ast)
      iex> Enum.find(result.fields, & &1.name == :age).has_default
      true

      iex> alias ElixirOntologies.Extractors.Struct
      iex> Struct.extract({:def, [], [{:foo, [], nil}]})
      {:error, "Not a defstruct: {:def, [], [{:foo, [], nil}]}"}
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  def extract({:defstruct, meta, [fields_ast]}, opts) do
    location = Helpers.extract_location_if({:defstruct, meta, []}, opts)
    fields = extract_fields(fields_ast)
    fields_with_defaults = Enum.count(fields, & &1.has_default)

    {:ok,
     %__MODULE__{
       fields: fields,
       enforce_keys: [],
       derives: [],
       location: location,
       metadata: %{
         field_count: length(fields),
         fields_with_defaults: fields_with_defaults,
         line: Keyword.get(meta, :line)
       }
     }}
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Not a defstruct", node)}
  end

  @doc """
  Extracts struct information, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defstruct [:name]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> result = Struct.extract!(ast)
      iex> hd(result.fields).name
      :name
  """
  @spec extract!(Macro.t(), keyword()) :: t()
  def extract!(node, opts \\ []) do
    case extract(node, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ===========================================================================
  # Body Extraction (from module body)
  # ===========================================================================

  @doc """
  Extracts struct information from a module body.

  This extracts the defstruct along with @enforce_keys and @derive directives
  from the containing module body.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule User do @enforce_keys [:name]; defstruct [:name, :email] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_from_body(body)
      iex> result.enforce_keys
      [:name]
      iex> Struct.field_names(result)
      [:name, :email]

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule Plain do def foo, do: :ok end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Struct.extract_from_body(body)
      {:error, "No defstruct found in module body"}
  """
  @spec extract_from_body(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract_from_body(body, opts \\ []) do
    statements = Helpers.normalize_body(body)

    case find_defstruct(statements) do
      nil ->
        {:error, "No defstruct found in module body"}

      defstruct_node ->
        case extract(defstruct_node, opts) do
          {:ok, struct} ->
            enforce_keys = extract_enforce_keys(body)
            derives = Helpers.extract_derives(body)

            {:ok, %{struct | enforce_keys: enforce_keys, derives: derives}}

          error ->
            error
        end
    end
  end

  @doc """
  Extracts struct from module body, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule U do defstruct [:a] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Struct.extract_from_body!(body)
      iex> hd(result.fields).name
      :a
  """
  @spec extract_from_body!(Macro.t(), keyword()) :: t()
  def extract_from_body!(body, opts \\ []) do
    case extract_from_body(body, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Checks if a module body defines a struct.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule User do defstruct [:name] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Struct.defines_struct?(body)
      true

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule Plain do def foo, do: :ok end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Struct.defines_struct?(body)
      false
  """
  @spec defines_struct?(Macro.t()) :: boolean()
  def defines_struct?(body) do
    statements = Helpers.normalize_body(body)
    find_defstruct(statements) != nil
  end

  # ===========================================================================
  # Exception Extraction
  # ===========================================================================

  @doc """
  Extracts exception information from a defexception AST node.

  Returns `{:ok, result}` with an `Exception` struct containing the fields
  and default message if present.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defexception [:message]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_exception(ast)
      iex> length(result.fields)
      1

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defexception message: \\"not found\\""
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_exception(ast)
      iex> result.default_message
      "not found"

      iex> alias ElixirOntologies.Extractors.Struct
      iex> Struct.extract_exception({:defstruct, [], [[:name]]})
      {:error, "Not a defexception: {:defstruct, [], [[:name]]}"}
  """
  @spec extract_exception(Macro.t(), keyword()) :: {:ok, Exception.t()} | {:error, String.t()}
  def extract_exception(node, opts \\ [])

  def extract_exception({:defexception, meta, [fields_ast]}, opts) do
    location = Helpers.extract_location_if({:defexception, meta, []}, opts)
    fields = extract_fields(fields_ast)
    default_message = extract_default_message(fields)

    {:ok,
     %Exception{
       fields: fields,
       enforce_keys: [],
       derives: [],
       has_custom_message: false,
       default_message: default_message,
       location: location,
       metadata: %{
         field_count: length(fields),
         has_default_message: not is_nil(default_message),
         line: Keyword.get(meta, :line)
       }
     }}
  end

  def extract_exception(node, _opts) do
    {:error, Helpers.format_error("Not a defexception", node)}
  end

  @doc """
  Extracts exception information, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defexception [:message]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> result = Struct.extract_exception!(ast)
      iex> hd(result.fields).name
      :message
  """
  @spec extract_exception!(Macro.t(), keyword()) :: Exception.t()
  def extract_exception!(node, opts \\ []) do
    case extract_exception(node, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Extracts exception information from a module body.

  This extracts the defexception along with @enforce_keys, @derive, and
  detects custom message/1 implementations.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule MyError do defexception [:message] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_exception_from_body(body)
      iex> result.has_custom_message
      false

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule MyError do defexception [:field]; def message(%{field: f}), do: f end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_exception_from_body(body)
      iex> result.has_custom_message
      true

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule Plain do def foo, do: :ok end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Struct.extract_exception_from_body(body)
      {:error, "No defexception found in module body"}
  """
  @spec extract_exception_from_body(Macro.t(), keyword()) :: {:ok, Exception.t()} | {:error, String.t()}
  def extract_exception_from_body(body, opts \\ []) do
    statements = Helpers.normalize_body(body)

    case find_defexception(statements) do
      nil ->
        {:error, "No defexception found in module body"}

      defexception_node ->
        case extract_exception(defexception_node, opts) do
          {:ok, exception} ->
            enforce_keys = extract_enforce_keys(body)
            derives = Helpers.extract_derives(body)
            has_custom_message = has_custom_message?(statements)

            {:ok,
             %{exception |
               enforce_keys: enforce_keys,
               derives: derives,
               has_custom_message: has_custom_message
             }}

          error ->
            error
        end
    end
  end

  @doc """
  Extracts exception from module body, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule E do defexception [:a] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> result = Struct.extract_exception_from_body!(body)
      iex> hd(result.fields).name
      :a
  """
  @spec extract_exception_from_body!(Macro.t(), keyword()) :: Exception.t()
  def extract_exception_from_body!(body, opts \\ []) do
    case extract_exception_from_body(body, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Checks if a module body defines an exception.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule MyError do defexception [:message] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Struct.defines_exception?(body)
      true

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule Plain do defstruct [:name] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Struct.defines_exception?(body)
      false
  """
  @spec defines_exception?(Macro.t()) :: boolean()
  def defines_exception?(body) do
    statements = Helpers.normalize_body(body)
    find_defexception(statements) != nil
  end

  # ===========================================================================
  # Field Extraction
  # ===========================================================================

  defp extract_fields(fields_ast) when is_list(fields_ast) do
    Enum.map(fields_ast, &extract_single_field/1)
  end

  defp extract_fields(_), do: []

  # Field with default value: {:age, 0} or [age: 0]
  defp extract_single_field({name, default_value}) when is_atom(name) do
    %{
      name: name,
      has_default: true,
      default_value: default_value,
      location: nil
    }
  end

  # Field without default: :name
  defp extract_single_field(name) when is_atom(name) do
    %{
      name: name,
      has_default: false,
      default_value: nil,
      location: nil
    }
  end

  # Fallback for unexpected patterns
  defp extract_single_field(other) do
    %{
      name: :unknown,
      has_default: false,
      default_value: nil,
      location: nil,
      raw: other
    }
  end

  # ===========================================================================
  # Enforce Keys Extraction
  # ===========================================================================

  @doc """
  Extracts @enforce_keys from a module body.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule U do @enforce_keys [:a, :b]; defstruct [:a, :b, :c] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Struct.extract_enforce_keys(body)
      [:a, :b]

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule U do defstruct [:a] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> Struct.extract_enforce_keys(body)
      []
  """
  @spec extract_enforce_keys(Macro.t()) :: [atom()]
  def extract_enforce_keys(body) do
    statements = Helpers.normalize_body(body)

    Enum.reduce(statements, [], fn
      {:@, _meta, [{:enforce_keys, _attr_meta, [keys]}]}, acc when is_list(keys) ->
        acc ++ keys

      _, acc ->
        acc
    end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp find_defstruct(statements) do
    Enum.find(statements, &struct?/1)
  end

  defp find_defexception(statements) do
    Enum.find(statements, &exception?/1)
  end

  # Extract default message from fields (if :message field has a string default)
  defp extract_default_message(fields) do
    case Enum.find(fields, fn f -> f.name == :message end) do
      %{has_default: true, default_value: msg} when is_binary(msg) -> msg
      _ -> nil
    end
  end

  # Check if module has a custom message/1 function
  defp has_custom_message?(statements) do
    Enum.any?(statements, fn
      # def message(...)
      {:def, _meta, [{:message, _fn_meta, args} | _]} when is_list(args) and length(args) == 1 ->
        true

      # def message(...) when ...
      {:def, _meta, [{:when, _, [{:message, _fn_meta, args} | _]} | _]}
      when is_list(args) and length(args) == 1 ->
        true

      _ ->
        false
    end)
  end

  # ===========================================================================
  # Utility Functions
  # ===========================================================================

  @doc """
  Returns a list of field names from the struct.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defstruct [:name, :email, age: 0]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract(ast)
      iex> Struct.field_names(result)
      [:name, :email, :age]
  """
  @spec field_names(t()) :: [atom()]
  def field_names(%__MODULE__{fields: fields}) do
    Enum.map(fields, & &1.name)
  end

  @doc """
  Returns the field with the given name, or nil if not found.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defstruct [:name, age: 0]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract(ast)
      iex> Struct.get_field(result, :age)
      %{name: :age, has_default: true, default_value: 0, location: nil}
      iex> Struct.get_field(result, :unknown)
      nil
  """
  @spec get_field(t(), atom()) :: field() | nil
  def get_field(%__MODULE__{fields: fields}, name) when is_atom(name) do
    Enum.find(fields, fn f -> f.name == name end)
  end

  @doc """
  Checks if a field is in the enforce_keys list.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule U do @enforce_keys [:name]; defstruct [:name, :email] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_from_body(body)
      iex> Struct.enforced?(result, :name)
      true
      iex> Struct.enforced?(result, :email)
      false
  """
  @spec enforced?(t(), atom()) :: boolean()
  def enforced?(%__MODULE__{enforce_keys: keys}, name) when is_atom(name) do
    name in keys
  end

  @doc """
  Checks if a field has a default value.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defstruct [:name, age: 0]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract(ast)
      iex> Struct.has_default?(result, :age)
      true
      iex> Struct.has_default?(result, :name)
      false
      iex> Struct.has_default?(result, :unknown)
      false
  """
  @spec has_default?(t(), atom()) :: boolean()
  def has_default?(%__MODULE__{fields: fields}, name) when is_atom(name) do
    case Enum.find(fields, fn f -> f.name == name end) do
      %{has_default: true} -> true
      _ -> false
    end
  end

  @doc """
  Returns the default value for a field, or nil if no default.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defstruct [:name, age: 21]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract(ast)
      iex> Struct.default_value(result, :age)
      21
      iex> Struct.default_value(result, :name)
      nil
  """
  @spec default_value(t(), atom()) :: term()
  def default_value(%__MODULE__{fields: fields}, name) when is_atom(name) do
    case Enum.find(fields, fn f -> f.name == name end) do
      %{default_value: value} -> value
      _ -> nil
    end
  end

  @doc """
  Returns fields that have default values.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defstruct [:name, age: 0, active: true]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract(ast)
      iex> Struct.fields_with_defaults(result) |> Enum.map(& &1.name)
      [:age, :active]
  """
  @spec fields_with_defaults(t()) :: [field()]
  def fields_with_defaults(%__MODULE__{fields: fields}) do
    Enum.filter(fields, & &1.has_default)
  end

  @doc """
  Returns fields that are required (no default and enforced).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule U do @enforce_keys [:name]; defstruct [:name, :email, age: 0] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_from_body(body)
      iex> Struct.required_fields(result) |> Enum.map(& &1.name)
      [:name]
  """
  @spec required_fields(t()) :: [field()]
  def required_fields(%__MODULE__{fields: fields, enforce_keys: enforce_keys}) do
    Enum.filter(fields, fn f ->
      f.name in enforce_keys and not f.has_default
    end)
  end

  @doc """
  Checks if the struct has any @derive directives.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule U do @derive Inspect; defstruct [:a] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_from_body(body)
      iex> Struct.has_derives?(result)
      true

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule U do defstruct [:a] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_from_body(body)
      iex> Struct.has_derives?(result)
      false
  """
  @spec has_derives?(t()) :: boolean()
  def has_derives?(%__MODULE__{derives: derives}) do
    derives != []
  end

  @doc """
  Returns the list of derived protocol names.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Struct
      iex> code = "defmodule U do @derive [Inspect, Enumerable]; defstruct [:a] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> {:ok, result} = Struct.extract_from_body(body)
      iex> Struct.derived_protocols(result)
      [[:Inspect], [:Enumerable]]
  """
  @spec derived_protocols(t()) :: [[atom()] | atom()]
  def derived_protocols(%__MODULE__{derives: derives}) do
    derives
    |> Enum.flat_map(fn derive_info -> derive_info.protocols end)
    |> Enum.map(& &1.protocol)
  end
end
