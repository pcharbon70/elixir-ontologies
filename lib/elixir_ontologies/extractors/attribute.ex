defmodule ElixirOntologies.Extractors.Attribute do
  @moduledoc """
  Extracts module attributes from AST nodes.

  This module analyzes Elixir AST nodes representing `@attribute` constructs and
  extracts their name, value, and classifies them into appropriate types.
  Supports the attribute-related classes from elixir-structure.ttl:

  - ModuleAttribute: Generic `@attr value`
  - DocAttribute: `@doc`, `@moduledoc`, `@typedoc`
  - DeprecatedAttribute: `@deprecated "message"`
  - SinceAttribute: `@since "version"`
  - ExternalResourceAttribute: `@external_resource "path"`
  - CompileAttribute: `@compile options`
  - BehaviourDeclaration: `@behaviour Module`

  ## Usage

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], ["Function documentation"]}]}
      iex> {:ok, result} = Attribute.extract(ast)
      iex> result.type
      :doc_attribute
      iex> result.name
      :doc
      iex> result.value
      "Function documentation"

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:behaviour, [], [{:__aliases__, [], [:GenServer]}]}]}
      iex> {:ok, result} = Attribute.extract(ast)
      iex> result.type
      :behaviour_declaration
      iex> result.metadata.module
      [:GenServer]
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of attribute extraction.

  - `:type` - The attribute type classification
  - `:name` - Attribute name as atom (e.g., `:doc`, `:deprecated`)
  - `:value` - The raw attribute value
  - `:location` - Source location if available
  - `:metadata` - Type-specific additional information
  """
  @type t :: %__MODULE__{
          type: attribute_type(),
          name: atom(),
          value: term(),
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @type attribute_type ::
          :attribute
          | :doc_attribute
          | :moduledoc_attribute
          | :typedoc_attribute
          | :deprecated_attribute
          | :since_attribute
          | :external_resource_attribute
          | :compile_attribute
          | :behaviour_declaration
          | :callback_attribute
          | :optional_callbacks_attribute
          | :derive_attribute
          | :enforce_keys_attribute
          | :impl_attribute
          | :dialyzer_attribute
          | :on_load_attribute
          | :on_definition_attribute
          | :before_compile_attribute
          | :after_compile_attribute
          | :vsn_attribute

  defstruct [
    :type,
    :name,
    :value,
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Known Attributes
  # ===========================================================================

  # Documentation attributes
  @doc_attributes [:doc, :moduledoc, :typedoc]

  # Metadata attributes
  @deprecated_attribute :deprecated
  @since_attribute :since

  # Compilation attributes
  @external_resource_attribute :external_resource
  @compile_attribute :compile

  # Behaviour/callback attributes
  @behaviour_attributes [:behaviour, :behavior]
  @callback_attribute :callback
  @optional_callbacks_attribute :optional_callbacks

  # Struct-related attributes
  @derive_attribute :derive
  @enforce_keys_attribute :enforce_keys

  # Implementation attributes
  @impl_attribute :impl

  # Dialyzer attribute
  @dialyzer_attribute :dialyzer

  # Lifecycle attributes
  @on_load_attribute :on_load
  @on_definition_attribute :on_definition
  @before_compile_attribute :before_compile
  @after_compile_attribute :after_compile

  # Version attribute
  @vsn_attribute :vsn

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a module attribute.

  ## Examples

      iex> ElixirOntologies.Extractors.Attribute.attribute?({:@, [], [{:doc, [], ["doc"]}]})
      true

      iex> ElixirOntologies.Extractors.Attribute.attribute?({:@, [], [{:custom, [], [42]}]})
      true

      iex> ElixirOntologies.Extractors.Attribute.attribute?({:def, [], [{:foo, [], nil}]})
      false

      iex> ElixirOntologies.Extractors.Attribute.attribute?(:not_an_attribute)
      false
  """
  @spec attribute?(Macro.t()) :: boolean()
  def attribute?({:@, _meta, [{name, _, _}]}) when is_atom(name), do: true
  def attribute?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts an attribute from an AST node.

  Returns `{:ok, %Attribute{}}` on success, or `{:error, reason}` if the node
  is not an attribute.

  ## Examples

      iex> ast = {:@, [], [{:doc, [], ["Function documentation"]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Attribute.extract(ast)
      iex> result.type
      :doc_attribute
      iex> result.value
      "Function documentation"

      iex> ast = {:@, [], [{:deprecated, [], ["Use new_func/1 instead"]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Attribute.extract(ast)
      iex> result.type
      :deprecated_attribute
      iex> result.metadata.message
      "Use new_func/1 instead"

      iex> ast = {:@, [], [{:since, [], ["1.2.0"]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Attribute.extract(ast)
      iex> result.type
      :since_attribute
      iex> result.metadata.version
      "1.2.0"

      iex> {:error, _} = ElixirOntologies.Extractors.Attribute.extract({:def, [], []})
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  def extract({:@, meta, [{name, _, args}]} = _node, _opts) when is_atom(name) do
    value = extract_value(args)
    type = classify_attribute(name, value)
    location = Helpers.extract_location({:@, meta, [{name, [], args}]})

    {:ok,
     %__MODULE__{
       type: type,
       name: name,
       value: value,
       location: location,
       metadata: build_metadata(type, name, value)
     }}
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Not an attribute", node)}
  end

  @doc """
  Extracts an attribute from an AST node, raising on error.

  ## Examples

      iex> ast = {:@, [], [{:custom, [], [42]}]}
      iex> result = ElixirOntologies.Extractors.Attribute.extract!(ast)
      iex> result.name
      :custom
      iex> result.value
      42
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
  Extracts all attributes from a module body.

  Returns a list of extracted attributes in the order they appear.

  ## Examples

      iex> body = {:__block__, [], [
      ...>   {:@, [], [{:moduledoc, [], ["Module docs"]}]},
      ...>   {:@, [], [{:doc, [], ["Function docs"]}]},
      ...>   {:def, [], [{:foo, [], nil}]}
      ...> ]}
      iex> results = ElixirOntologies.Extractors.Attribute.extract_all(body)
      iex> length(results)
      2
      iex> Enum.map(results, & &1.name)
      [:moduledoc, :doc]
  """
  @spec extract_all(Macro.t()) :: [t()]
  def extract_all(nil), do: []

  def extract_all({:__block__, _, statements}) when is_list(statements) do
    statements
    |> Enum.filter(&attribute?/1)
    |> Enum.map(fn node ->
      case extract(node) do
        {:ok, result} -> result
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def extract_all(statement) do
    if attribute?(statement) do
      case extract(statement) do
        {:ok, result} -> [result]
        {:error, _} -> []
      end
    else
      []
    end
  end

  # ===========================================================================
  # Classification Helpers
  # ===========================================================================

  @doc """
  Returns true if the attribute is a documentation attribute.

  ## Examples

      iex> ast = {:@, [], [{:doc, [], ["docs"]}]}
      iex> {:ok, attr} = ElixirOntologies.Extractors.Attribute.extract(ast)
      iex> ElixirOntologies.Extractors.Attribute.doc_attribute?(attr)
      true

      iex> ast = {:@, [], [{:custom, [], [1]}]}
      iex> {:ok, attr} = ElixirOntologies.Extractors.Attribute.extract(ast)
      iex> ElixirOntologies.Extractors.Attribute.doc_attribute?(attr)
      false
  """
  @spec doc_attribute?(t()) :: boolean()
  def doc_attribute?(%__MODULE__{type: type}) do
    type in [:doc_attribute, :moduledoc_attribute, :typedoc_attribute]
  end

  @doc """
  Returns true if the attribute has documentation hidden (`@doc false`).

  ## Examples

      iex> ast = {:@, [], [{:doc, [], [false]}]}
      iex> {:ok, attr} = ElixirOntologies.Extractors.Attribute.extract(ast)
      iex> ElixirOntologies.Extractors.Attribute.hidden?(attr)
      true

      iex> ast = {:@, [], [{:doc, [], ["visible docs"]}]}
      iex> {:ok, attr} = ElixirOntologies.Extractors.Attribute.extract(ast)
      iex> ElixirOntologies.Extractors.Attribute.hidden?(attr)
      false
  """
  @spec hidden?(t()) :: boolean()
  def hidden?(%__MODULE__{metadata: %{hidden: true}}), do: true
  def hidden?(_), do: false

  @doc """
  Returns true if the attribute is a behaviour declaration.

  ## Examples

      iex> ast = {:@, [], [{:behaviour, [], [{:__aliases__, [], [:GenServer]}]}]}
      iex> {:ok, attr} = ElixirOntologies.Extractors.Attribute.extract(ast)
      iex> ElixirOntologies.Extractors.Attribute.behaviour?(attr)
      true

      iex> ast = {:@, [], [{:doc, [], ["docs"]}]}
      iex> {:ok, attr} = ElixirOntologies.Extractors.Attribute.extract(ast)
      iex> ElixirOntologies.Extractors.Attribute.behaviour?(attr)
      false
  """
  @spec behaviour?(t()) :: boolean()
  def behaviour?(%__MODULE__{type: :behaviour_declaration}), do: true
  def behaviour?(_), do: false

  @doc """
  Returns the behaviour module if this is a behaviour declaration.

  ## Examples

      iex> ast = {:@, [], [{:behaviour, [], [{:__aliases__, [], [:GenServer]}]}]}
      iex> {:ok, attr} = ElixirOntologies.Extractors.Attribute.extract(ast)
      iex> ElixirOntologies.Extractors.Attribute.behaviour_module(attr)
      [:GenServer]

      iex> ast = {:@, [], [{:doc, [], ["docs"]}]}
      iex> {:ok, attr} = ElixirOntologies.Extractors.Attribute.extract(ast)
      iex> ElixirOntologies.Extractors.Attribute.behaviour_module(attr)
      nil
  """
  @spec behaviour_module(t()) :: [atom()] | atom() | nil
  def behaviour_module(%__MODULE__{type: :behaviour_declaration, metadata: %{module: module}}) do
    module
  end

  def behaviour_module(_), do: nil

  # ===========================================================================
  # Private Helpers - Value Extraction
  # ===========================================================================

  defp extract_value(nil), do: nil
  defp extract_value([]), do: nil
  defp extract_value([value]), do: extract_single_value(value)
  defp extract_value(args) when is_list(args), do: args

  defp extract_single_value(value) when is_binary(value), do: value
  defp extract_single_value(value) when is_boolean(value), do: value
  defp extract_single_value(value) when is_number(value), do: value
  defp extract_single_value(value) when is_atom(value), do: value
  defp extract_single_value(value), do: value

  # ===========================================================================
  # Private Helpers - Classification
  # ===========================================================================

  defp classify_attribute(name, _value) when name in @doc_attributes do
    case name do
      :doc -> :doc_attribute
      :moduledoc -> :moduledoc_attribute
      :typedoc -> :typedoc_attribute
    end
  end

  defp classify_attribute(@deprecated_attribute, _value), do: :deprecated_attribute
  defp classify_attribute(@since_attribute, _value), do: :since_attribute
  defp classify_attribute(@external_resource_attribute, _value), do: :external_resource_attribute
  defp classify_attribute(@compile_attribute, _value), do: :compile_attribute

  defp classify_attribute(name, _value) when name in @behaviour_attributes do
    :behaviour_declaration
  end

  defp classify_attribute(@callback_attribute, _value), do: :callback_attribute

  defp classify_attribute(@optional_callbacks_attribute, _value),
    do: :optional_callbacks_attribute

  defp classify_attribute(@derive_attribute, _value), do: :derive_attribute
  defp classify_attribute(@enforce_keys_attribute, _value), do: :enforce_keys_attribute
  defp classify_attribute(@impl_attribute, _value), do: :impl_attribute
  defp classify_attribute(@dialyzer_attribute, _value), do: :dialyzer_attribute
  defp classify_attribute(@on_load_attribute, _value), do: :on_load_attribute
  defp classify_attribute(@on_definition_attribute, _value), do: :on_definition_attribute
  defp classify_attribute(@before_compile_attribute, _value), do: :before_compile_attribute
  defp classify_attribute(@after_compile_attribute, _value), do: :after_compile_attribute
  defp classify_attribute(@vsn_attribute, _value), do: :vsn_attribute
  defp classify_attribute(_name, _value), do: :attribute

  # ===========================================================================
  # Private Helpers - Metadata Building
  # ===========================================================================

  defp build_metadata(type, _name, value)
       when type in [:doc_attribute, :moduledoc_attribute, :typedoc_attribute] do
    %{hidden: value == false}
  end

  defp build_metadata(:deprecated_attribute, _name, value) do
    %{message: extract_message(value)}
  end

  defp build_metadata(:since_attribute, _name, value) do
    %{version: extract_version(value)}
  end

  defp build_metadata(:behaviour_declaration, _name, value) do
    %{module: extract_module_name(value)}
  end

  defp build_metadata(:external_resource_attribute, _name, value) do
    %{path: extract_path(value)}
  end

  defp build_metadata(:compile_attribute, _name, value) do
    %{options: value}
  end

  defp build_metadata(:impl_attribute, _name, value) do
    %{value: value}
  end

  defp build_metadata(:callback_attribute, _name, value) do
    %{spec: value}
  end

  defp build_metadata(:derive_attribute, _name, value) do
    %{protocols: extract_derive_protocols(value)}
  end

  defp build_metadata(:enforce_keys_attribute, _name, value) do
    %{keys: value}
  end

  defp build_metadata(_type, _name, _value), do: %{}

  # ===========================================================================
  # Private Helpers - Value Extraction for Metadata
  # ===========================================================================

  defp extract_message(message) when is_binary(message), do: message
  defp extract_message(_), do: nil

  defp extract_version(version) when is_binary(version), do: version
  defp extract_version(_), do: nil

  defp extract_path(path) when is_binary(path), do: path
  defp extract_path(_), do: nil

  defp extract_module_name({:__aliases__, _, parts}) when is_list(parts), do: parts
  defp extract_module_name(atom) when is_atom(atom), do: atom
  defp extract_module_name(_), do: nil

  defp extract_derive_protocols(protocols) when is_list(protocols), do: protocols
  defp extract_derive_protocols({:__aliases__, _, parts}), do: [parts]
  defp extract_derive_protocols(protocol), do: [protocol]
end
