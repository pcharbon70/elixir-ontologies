defmodule ElixirOntologies.Extractors.Parameter do
  @moduledoc """
  Extracts function parameters from AST nodes.

  This module analyzes Elixir AST nodes representing function parameters and
  extracts information including position, name, default values, and pattern
  expressions. Supports simple variables, default parameters, and pattern
  matching parameters.

  ## Ontology Classes

  From `elixir-structure.ttl`:
  - `Parameter` - Base parameter with `parameterPosition`, `parameterName`
  - `DefaultParameter` - Parameter with `hasDefaultValue`
  - `PatternParameter` - Parameter with `hasPatternExpression`

  ## Usage

      iex> alias ElixirOntologies.Extractors.Parameter
      iex> ast = {:x, [], nil}
      iex> {:ok, result} = Parameter.extract(ast, position: 0)
      iex> result.name
      :x
      iex> result.position
      0

      iex> alias ElixirOntologies.Extractors.Parameter
      iex> ast = {:\\\\, [], [{:x, [], nil}, 10]}
      iex> {:ok, result} = Parameter.extract(ast)
      iex> result.type
      :default
      iex> result.default_value
      10
  """

  require Logger

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of parameter extraction.

  - `:position` - 0-indexed position in parameter list
  - `:name` - Parameter name as atom (nil for patterns)
  - `:type` - Type of parameter (:simple, :default, :pattern, :pin)
  - `:expression` - Full parameter AST expression
  - `:default_value` - Default value expression (for default parameters)
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          position: non_neg_integer(),
          name: atom() | nil,
          type: :simple | :default | :pattern | :pin,
          expression: Macro.t(),
          default_value: Macro.t() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct [
    :position,
    :name,
    :type,
    :expression,
    default_value: nil,
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Pattern Types
  # ===========================================================================

  @pattern_forms [
    # tuple pattern
    :{},
    # map pattern
    :%{},
    # struct pattern
    :%,
    # cons pattern (list)
    :|,
    # binary pattern
    :<<>>,
    # match pattern (pin in pattern)
    :=
  ]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a function parameter.

  All valid Elixir expressions can technically be parameters, but this
  function identifies the common parameter forms.

  ## Examples

      iex> ElixirOntologies.Extractors.Parameter.parameter?({:x, [], nil})
      true

      iex> ElixirOntologies.Extractors.Parameter.parameter?({:\\\\, [], [{:x, [], nil}, 10]})
      true

      iex> ElixirOntologies.Extractors.Parameter.parameter?({:{}, [], [{:a, [], nil}, {:b, [], nil}]})
      true

      iex> ElixirOntologies.Extractors.Parameter.parameter?(nil)
      false
  """
  @spec parameter?(Macro.t()) :: boolean()
  def parameter?({:_, _, _}), do: true
  def parameter?({name, _, context}) when is_atom(name) and is_atom(context), do: true
  def parameter?({:\\, _, [_param, _default]}), do: true
  def parameter?({:^, _, [_var]}), do: true
  def parameter?({form, _, _}) when form in @pattern_forms, do: true
  # list literal pattern
  def parameter?([_ | _]), do: true
  # tagged tuple {:ok, val}
  def parameter?({tag, _value}) when is_atom(tag), do: true
  def parameter?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a parameter from an AST node.

  Returns `{:ok, %Parameter{}}` on success, or `{:error, reason}` if the node
  cannot be processed as a parameter.

  ## Options

  - `:position` - Parameter position (0-indexed, defaults to 0)

  ## Examples

      iex> ast = {:name, [], nil}
      iex> {:ok, result} = ElixirOntologies.Extractors.Parameter.extract(ast, position: 0)
      iex> result.name
      :name
      iex> result.type
      :simple

      iex> ast = {:\\\\, [], [{:timeout, [], nil}, 5000]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Parameter.extract(ast)
      iex> result.name
      :timeout
      iex> result.default_value
      5000
      iex> result.metadata.has_default
      true

      iex> ast = {:^, [], [{:x, [], nil}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Parameter.extract(ast)
      iex> result.type
      :pin

      iex> ast = {:{}, [], [{:a, [], nil}, {:b, [], nil}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Parameter.extract(ast)
      iex> result.type
      :pattern
      iex> result.metadata.pattern_type
      :tuple
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  # Default parameter: x \\ default_value
  def extract({:\\, meta, [param, default_value]} = node, opts) do
    position = Keyword.get(opts, :position, 0)
    name = extract_name(param)
    location = Helpers.extract_location({:\\, meta, [param, default_value]})

    {:ok,
     %__MODULE__{
       position: position,
       name: name,
       type: :default,
       expression: node,
       default_value: default_value,
       location: location,
       metadata: %{
         has_default: true,
         is_pattern: is_pattern?(param),
         is_ignored: is_ignored?(name),
         pattern_type: get_pattern_type(param)
       }
     }}
  end

  # Pin expression: ^x
  def extract({:^, meta, [{name, _, _} = var]} = node, opts) when is_atom(name) do
    position = Keyword.get(opts, :position, 0)
    location = Helpers.extract_location({:^, meta, [var]})

    {:ok,
     %__MODULE__{
       position: position,
       name: name,
       type: :pin,
       expression: node,
       default_value: nil,
       location: location,
       metadata: %{
         has_default: false,
         is_pattern: false,
         is_ignored: false,
         pattern_type: nil
       }
     }}
  end

  # Tuple pattern: {a, b}
  def extract({:{}, _, _} = node, opts) do
    extract_pattern(node, :tuple, opts)
  end

  # 2-tuple pattern: {a, b} (special AST form)
  # When left is not an atom, it's a regular 2-tuple pattern
  def extract({left, _right} = node, opts) when not is_atom(left) do
    extract_pattern(node, :tuple, opts)
  end

  # Tagged tuple pattern: {:ok, data} becomes {:ok, {:data, [], context}}
  # This is an atom-keyed 2-tuple (keyword-style) used in pattern matching
  def extract({tag, _value} = node, opts) when is_atom(tag) do
    extract_pattern(node, :tagged_tuple, opts)
  end

  # Map pattern: %{key: value}
  def extract({:%{}, _, _} = node, opts) do
    extract_pattern(node, :map, opts)
  end

  # Struct pattern: %Module{field: value}
  def extract({:%, _, _} = node, opts) do
    extract_pattern(node, :struct, opts)
  end

  # Cons pattern: [head | tail]
  def extract({:|, _, _} = node, opts) do
    extract_pattern(node, :cons, opts)
  end

  # Binary pattern: <<bytes::binary>>
  def extract({:<<>>, _, _} = node, opts) do
    extract_pattern(node, :binary, opts)
  end

  # Match pattern: pattern = value
  def extract({:=, _, _} = node, opts) do
    extract_pattern(node, :match, opts)
  end

  # List literal pattern: [a, b, c]
  # Note: 2-element tuples like {:ok, data} become keyword lists [ok: data] in AST
  def extract([_ | _] = node, opts) do
    pattern_type = if Keyword.keyword?(node), do: :keyword, else: :list
    extract_pattern(node, pattern_type, opts)
  end

  # Simple variable: x, name, etc.
  def extract({name, meta, context} = node, opts)
      when is_atom(name) and is_atom(context) do
    position = Keyword.get(opts, :position, 0)
    location = Helpers.extract_location({name, meta, context})

    {:ok,
     %__MODULE__{
       position: position,
       name: name,
       type: :simple,
       expression: node,
       default_value: nil,
       location: location,
       metadata: %{
         has_default: false,
         is_pattern: false,
         is_ignored: is_ignored?(name),
         pattern_type: nil
       }
     }}
  end

  # Literal values (atoms, numbers, strings) as pattern parameters
  def extract(literal, opts)
      when is_atom(literal) or is_number(literal) or is_binary(literal) do
    position = Keyword.get(opts, :position, 0)

    {:ok,
     %__MODULE__{
       position: position,
       name: nil,
       type: :pattern,
       expression: literal,
       default_value: nil,
       location: nil,
       metadata: %{
         has_default: false,
         is_pattern: true,
         is_ignored: false,
         pattern_type: :literal
       }
     }}
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Cannot extract parameter", node)}
  end

  @doc """
  Extracts a parameter from an AST node, raising on error.

  ## Examples

      iex> ast = {:foo, [], nil}
      iex> result = ElixirOntologies.Extractors.Parameter.extract!(ast)
      iex> result.name
      :foo
  """
  @spec extract!(Macro.t(), keyword()) :: t()
  def extract!(node, opts \\ []) do
    case extract(node, opts) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
  end

  # ===========================================================================
  # Bulk Extraction
  # ===========================================================================

  @doc """
  Extracts all parameters from a parameter list.

  Returns a list of extracted parameters with positions assigned.

  ## Examples

      iex> params = [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}]
      iex> results = ElixirOntologies.Extractors.Parameter.extract_all(params)
      iex> length(results)
      3
      iex> Enum.map(results, & &1.position)
      [0, 1, 2]
      iex> Enum.map(results, & &1.name)
      [:a, :b, :c]

      iex> ElixirOntologies.Extractors.Parameter.extract_all(nil)
      []

      iex> ElixirOntologies.Extractors.Parameter.extract_all([])
      []
  """
  @spec extract_all([Macro.t()] | nil) :: [t()]
  def extract_all(nil), do: []
  def extract_all([]), do: []

  def extract_all(params) when is_list(params) do
    params
    |> Enum.with_index()
    |> Enum.map(fn {param, index} ->
      case extract(param, position: index) do
        {:ok, result} ->
          result

        {:error, reason} ->
          Logger.warning("Failed to extract parameter at position #{index}: #{reason}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Returns true if the parameter has a default value.

  ## Examples

      iex> ast = {:\\\\, [], [{:x, [], nil}, 10]}
      iex> {:ok, param} = ElixirOntologies.Extractors.Parameter.extract(ast)
      iex> ElixirOntologies.Extractors.Parameter.has_default?(param)
      true

      iex> ast = {:x, [], nil}
      iex> {:ok, param} = ElixirOntologies.Extractors.Parameter.extract(ast)
      iex> ElixirOntologies.Extractors.Parameter.has_default?(param)
      false
  """
  @spec has_default?(t()) :: boolean()
  def has_default?(%__MODULE__{type: :default}), do: true
  def has_default?(%__MODULE__{metadata: %{has_default: true}}), do: true
  def has_default?(_), do: false

  @doc """
  Returns true if the parameter is a pattern (destructuring).

  ## Examples

      iex> ast = {:{}, [], [{:a, [], nil}, {:b, [], nil}]}
      iex> {:ok, param} = ElixirOntologies.Extractors.Parameter.extract(ast)
      iex> ElixirOntologies.Extractors.Parameter.is_pattern_param?(param)
      true

      iex> ast = {:x, [], nil}
      iex> {:ok, param} = ElixirOntologies.Extractors.Parameter.extract(ast)
      iex> ElixirOntologies.Extractors.Parameter.is_pattern_param?(param)
      false
  """
  @spec is_pattern_param?(t()) :: boolean()
  def is_pattern_param?(%__MODULE__{type: :pattern}), do: true
  def is_pattern_param?(%__MODULE__{metadata: %{is_pattern: true}}), do: true
  def is_pattern_param?(_), do: false

  @doc """
  Returns true if the parameter is ignored (starts with _).

  ## Examples

      iex> ast = {:_unused, [], nil}
      iex> {:ok, param} = ElixirOntologies.Extractors.Parameter.extract(ast)
      iex> ElixirOntologies.Extractors.Parameter.is_ignored?(param)
      true

      iex> ast = {:x, [], nil}
      iex> {:ok, param} = ElixirOntologies.Extractors.Parameter.extract(ast)
      iex> ElixirOntologies.Extractors.Parameter.is_ignored?(param)
      false
  """
  @spec is_ignored?(t() | atom()) :: boolean()
  def is_ignored?(%__MODULE__{metadata: %{is_ignored: ignored}}), do: ignored
  def is_ignored?(%__MODULE__{name: name}), do: is_ignored?(name)
  def is_ignored?(:_), do: true

  def is_ignored?(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("_")
  end

  def is_ignored?(_), do: false

  @doc """
  Returns the parameter name as a string identifier.

  ## Examples

      iex> ast = {:foo, [], nil}
      iex> {:ok, param} = ElixirOntologies.Extractors.Parameter.extract(ast, position: 2)
      iex> ElixirOntologies.Extractors.Parameter.param_id(param)
      "foo@2"

      iex> ast = {:{}, [], [{:a, [], nil}]}
      iex> {:ok, param} = ElixirOntologies.Extractors.Parameter.extract(ast, position: 0)
      iex> ElixirOntologies.Extractors.Parameter.param_id(param)
      "pattern@0"
  """
  @spec param_id(t()) :: String.t()
  def param_id(%__MODULE__{name: nil, position: pos}), do: "pattern@#{pos}"
  def param_id(%__MODULE__{name: name, position: pos}), do: "#{name}@#{pos}"

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp extract_pattern(node, pattern_type, opts) do
    position = Keyword.get(opts, :position, 0)
    location = extract_pattern_location(node)
    name = extract_name(node)

    {:ok,
     %__MODULE__{
       position: position,
       name: name,
       type: :pattern,
       expression: node,
       default_value: nil,
       location: location,
       metadata: %{
         has_default: false,
         is_pattern: true,
         is_ignored: is_ignored?(name),
         pattern_type: pattern_type
       }
     }}
  end

  defp extract_pattern_location({_form, meta, _args}) when is_list(meta) do
    Helpers.extract_location({nil, meta, nil})
  end

  defp extract_pattern_location(_), do: nil

  # Extract name from various parameter forms
  defp extract_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp extract_name({:\\, _, [param, _default]}), do: extract_name(param)
  defp extract_name({:^, _, [{name, _, _}]}) when is_atom(name), do: name
  defp extract_name(_), do: nil

  # Check if a parameter expression is a pattern
  defp is_pattern?({form, _, _}) when form in @pattern_forms, do: true
  defp is_pattern?([_ | _]), do: true
  defp is_pattern?({left, right}) when not is_atom(left) and not is_nil(right), do: true
  defp is_pattern?(_), do: false

  # Get the pattern type for a parameter
  defp get_pattern_type({:{}, _, _}), do: :tuple
  defp get_pattern_type({left, _right}) when not is_atom(left), do: :tuple
  defp get_pattern_type({tag, _value}) when is_atom(tag), do: :tagged_tuple
  defp get_pattern_type({:%{}, _, _}), do: :map
  defp get_pattern_type({:%, _, _}), do: :struct
  defp get_pattern_type({:|, _, _}), do: :cons
  defp get_pattern_type({:<<>>, _, _}), do: :binary
  defp get_pattern_type({:=, _, _}), do: :match
  defp get_pattern_type([_ | _] = list), do: if(Keyword.keyword?(list), do: :keyword, else: :list)
  defp get_pattern_type(_), do: nil
end
