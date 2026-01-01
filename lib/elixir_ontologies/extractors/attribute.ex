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
  # AttributeValue Struct
  # ===========================================================================

  defmodule AttributeValue do
    @moduledoc """
    Represents a typed attribute value with classification and evaluation.

    This struct captures the value assigned to a module attribute with type
    information and evaluation status.

    ## Fields

    - `:type` - The value type classification
    - `:value` - The extracted/evaluated value (for literals and simple structures)
    - `:raw_ast` - Original AST for complex expressions
    - `:accumulated` - Whether this attribute accumulates values

    ## Value Types

    - `:literal` - Atoms, integers, floats, strings, booleans
    - `:list` - Regular lists `[a, b, c]`
    - `:map` - Maps `%{key: value}`
    - `:keyword_list` - Keyword lists `[key: value]`
    - `:module_ref` - Module references `SomeModule`
    - `:tuple` - Tuples `{a, b}`
    - `:ast` - Complex AST expressions

    ## Usage

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> val = AttributeValue.new(value: 42, type: :literal)
        iex> val.type
        :literal
        iex> val.value
        42
    """

    @type value_type ::
            :literal
            | :list
            | :map
            | :keyword_list
            | :module_ref
            | :tuple
            | :ast
            | nil

    @type t :: %__MODULE__{
            type: value_type(),
            value: term(),
            raw_ast: Macro.t() | nil,
            accumulated: boolean()
          }

    defstruct [
      :type,
      :value,
      :raw_ast,
      accumulated: false
    ]

    @doc """
    Creates a new AttributeValue with the given options.

    ## Options

    - `:type` - The value type (required)
    - `:value` - The extracted value
    - `:raw_ast` - The original AST
    - `:accumulated` - Whether the attribute accumulates (default: false)

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> val = AttributeValue.new(type: :literal, value: "hello")
        iex> val.type
        :literal
        iex> val.value
        "hello"

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> val = AttributeValue.new(type: :list, value: [1, 2, 3], accumulated: true)
        iex> val.accumulated
        true
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        type: Keyword.get(opts, :type),
        value: Keyword.get(opts, :value),
        raw_ast: Keyword.get(opts, :raw_ast),
        accumulated: Keyword.get(opts, :accumulated, false)
      }
    end

    @doc """
    Checks if the value is a literal type.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> AttributeValue.literal?(AttributeValue.new(type: :literal, value: 42))
        true

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> AttributeValue.literal?(AttributeValue.new(type: :list, value: [1, 2]))
        false
    """
    @spec literal?(t()) :: boolean()
    def literal?(%__MODULE__{type: :literal}), do: true
    def literal?(_), do: false

    @doc """
    Checks if the value is a list type.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> AttributeValue.list?(AttributeValue.new(type: :list, value: [1, 2]))
        true
    """
    @spec list?(t()) :: boolean()
    def list?(%__MODULE__{type: :list}), do: true
    def list?(_), do: false

    @doc """
    Checks if the value is a keyword list type.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> AttributeValue.keyword_list?(AttributeValue.new(type: :keyword_list, value: [a: 1]))
        true
    """
    @spec keyword_list?(t()) :: boolean()
    def keyword_list?(%__MODULE__{type: :keyword_list}), do: true
    def keyword_list?(_), do: false

    @doc """
    Checks if the value is a map type.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> AttributeValue.map?(AttributeValue.new(type: :map, value: %{a: 1}))
        true
    """
    @spec map?(t()) :: boolean()
    def map?(%__MODULE__{type: :map}), do: true
    def map?(_), do: false

    @doc """
    Checks if the value is a module reference.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> AttributeValue.module_ref?(AttributeValue.new(type: :module_ref, value: MyModule))
        true
    """
    @spec module_ref?(t()) :: boolean()
    def module_ref?(%__MODULE__{type: :module_ref}), do: true
    def module_ref?(_), do: false

    @doc """
    Checks if the value is a complex AST that couldn't be evaluated.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> AttributeValue.ast?(AttributeValue.new(type: :ast, raw_ast: {:foo, [], []}))
        true
    """
    @spec ast?(t()) :: boolean()
    def ast?(%__MODULE__{type: :ast}), do: true
    def ast?(_), do: false

    @doc """
    Checks if the value can be evaluated to a concrete term.

    Returns true for literals, lists, maps, keyword lists, tuples, and module refs.
    Returns false for complex AST expressions.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> AttributeValue.evaluable?(AttributeValue.new(type: :literal, value: 42))
        true

        iex> alias ElixirOntologies.Extractors.Attribute.AttributeValue
        iex> AttributeValue.evaluable?(AttributeValue.new(type: :ast, raw_ast: {:foo, [], []}))
        false
    """
    @spec evaluable?(t()) :: boolean()
    def evaluable?(%__MODULE__{type: :ast}), do: false
    def evaluable?(%__MODULE__{type: nil}), do: false
    def evaluable?(_), do: true
  end

  # ===========================================================================
  # DocContent Struct
  # ===========================================================================

  defmodule DocContent do
    @moduledoc """
    Represents extracted documentation content from @doc, @moduledoc, or @typedoc.

    This struct captures the documentation text along with format information
    and hidden status.

    ## Fields

    - `:content` - The documentation text (string or nil)
    - `:format` - The documentation format (:string, :heredoc, :sigil, :false, :nil)
    - `:sigil_type` - For sigil format, the sigil character (:S, :s, etc.)
    - `:hidden` - Whether the documentation is hidden (@doc false)

    ## Usage

        iex> alias ElixirOntologies.Extractors.Attribute.DocContent
        iex> doc = DocContent.new(content: "Hello", format: :string)
        iex> doc.content
        "Hello"
        iex> doc.hidden
        false
    """

    @type format :: :string | :heredoc | :sigil | false | nil
    @type sigil_type :: :S | :s | :D | :W | :w | nil

    @type t :: %__MODULE__{
            content: String.t() | nil,
            format: format(),
            sigil_type: sigil_type(),
            hidden: boolean()
          }

    defstruct [
      :content,
      :format,
      :sigil_type,
      hidden: false
    ]

    @doc """
    Creates a new DocContent with the given options.

    ## Options

    - `:content` - The documentation text
    - `:format` - The format (:string, :heredoc, :sigil, :false, :nil)
    - `:sigil_type` - For sigils, the type (:S, :s, etc.)
    - `:hidden` - Whether hidden (default: false)

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.DocContent
        iex> doc = DocContent.new(content: "My docs", format: :string)
        iex> doc.format
        :string

        iex> alias ElixirOntologies.Extractors.Attribute.DocContent
        iex> doc = DocContent.new(format: :false, hidden: true)
        iex> doc.hidden
        true
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        content: Keyword.get(opts, :content),
        format: Keyword.get(opts, :format),
        sigil_type: Keyword.get(opts, :sigil_type),
        hidden: Keyword.get(opts, :hidden, false)
      }
    end

    @doc """
    Checks if the documentation has content.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.DocContent
        iex> DocContent.has_content?(DocContent.new(content: "docs", format: :string))
        true

        iex> alias ElixirOntologies.Extractors.Attribute.DocContent
        iex> DocContent.has_content?(DocContent.new(format: :false, hidden: true))
        false
    """
    @spec has_content?(t()) :: boolean()
    def has_content?(%__MODULE__{content: nil}), do: false
    def has_content?(%__MODULE__{content: ""}), do: false
    def has_content?(%__MODULE__{}), do: true

    @doc """
    Checks if the documentation is a sigil format.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.DocContent
        iex> DocContent.sigil?(DocContent.new(format: :sigil, sigil_type: :S))
        true

        iex> alias ElixirOntologies.Extractors.Attribute.DocContent
        iex> DocContent.sigil?(DocContent.new(format: :string))
        false
    """
    @spec sigil?(t()) :: boolean()
    def sigil?(%__MODULE__{format: :sigil}), do: true
    def sigil?(_), do: false
  end

  # ===========================================================================
  # CompileOptions Struct
  # ===========================================================================

  defmodule CompileOptions do
    @moduledoc """
    Represents parsed @compile directive options.

    This struct normalizes the various formats of @compile directives into
    a structured representation.

    ## Fields

    - `:inline` - Functions to inline (list of `{name, arity}`) or `true` for all
    - `:no_warn_undefined` - Modules/MFAs to suppress undefined warnings
    - `:warnings_as_errors` - Whether to treat warnings as errors
    - `:debug_info` - Whether to include debug info
    - `:raw_options` - The original options for reference

    ## Usage

        iex> alias ElixirOntologies.Extractors.Attribute.CompileOptions
        iex> opts = CompileOptions.new(inline: [{:foo, 1}], debug_info: true)
        iex> opts.inline
        [{:foo, 1}]
        iex> opts.debug_info
        true
    """

    @type t :: %__MODULE__{
            inline: [{atom(), non_neg_integer()}] | true | nil,
            no_warn_undefined: [module()] | [{module(), atom(), non_neg_integer()}] | true | nil,
            warnings_as_errors: boolean() | nil,
            debug_info: boolean() | nil,
            raw_options: keyword() | [atom()]
          }

    defstruct [
      :inline,
      :no_warn_undefined,
      :warnings_as_errors,
      :debug_info,
      raw_options: []
    ]

    @doc """
    Creates a new CompileOptions with the given options.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.CompileOptions
        iex> opts = CompileOptions.new(inline: true, raw_options: [:inline])
        iex> opts.inline
        true

        iex> alias ElixirOntologies.Extractors.Attribute.CompileOptions
        iex> opts = CompileOptions.new(no_warn_undefined: [SomeModule])
        iex> opts.no_warn_undefined
        [SomeModule]
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        inline: Keyword.get(opts, :inline),
        no_warn_undefined: Keyword.get(opts, :no_warn_undefined),
        warnings_as_errors: Keyword.get(opts, :warnings_as_errors),
        debug_info: Keyword.get(opts, :debug_info),
        raw_options: Keyword.get(opts, :raw_options, [])
      }
    end

    @doc """
    Checks if inline compilation is enabled.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.CompileOptions
        iex> CompileOptions.inline?(CompileOptions.new(inline: true))
        true

        iex> alias ElixirOntologies.Extractors.Attribute.CompileOptions
        iex> CompileOptions.inline?(CompileOptions.new(inline: [{:foo, 1}]))
        true

        iex> alias ElixirOntologies.Extractors.Attribute.CompileOptions
        iex> CompileOptions.inline?(CompileOptions.new())
        false
    """
    @spec inline?(t()) :: boolean()
    def inline?(%__MODULE__{inline: nil}), do: false
    def inline?(%__MODULE__{inline: []}), do: false
    def inline?(%__MODULE__{}), do: true
  end

  # ===========================================================================
  # CallbackSpec Struct
  # ===========================================================================

  defmodule CallbackSpec do
    @moduledoc """
    Represents a callback specification for @on_definition, @before_compile, @after_compile.

    This struct captures the target module and optional function for compile-time callbacks.

    ## Fields

    - `:module` - The target module (atom or `__MODULE__`)
    - `:function` - The function name (atom) if specified
    - `:is_current_module` - Whether it references `__MODULE__`

    ## Usage

        iex> alias ElixirOntologies.Extractors.Attribute.CallbackSpec
        iex> spec = CallbackSpec.new(module: MyModule, function: :on_def)
        iex> spec.module
        MyModule
        iex> spec.function
        :on_def
    """

    @type t :: %__MODULE__{
            module: module() | nil,
            function: atom() | nil,
            is_current_module: boolean()
          }

    defstruct [
      :module,
      :function,
      is_current_module: false
    ]

    @doc """
    Creates a new CallbackSpec with the given options.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.CallbackSpec
        iex> spec = CallbackSpec.new(module: SomeModule)
        iex> spec.module
        SomeModule

        iex> alias ElixirOntologies.Extractors.Attribute.CallbackSpec
        iex> spec = CallbackSpec.new(is_current_module: true, function: :callback)
        iex> spec.is_current_module
        true
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        module: Keyword.get(opts, :module),
        function: Keyword.get(opts, :function),
        is_current_module: Keyword.get(opts, :is_current_module, false)
      }
    end

    @doc """
    Checks if the callback has a specific function specified.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Attribute.CallbackSpec
        iex> CallbackSpec.has_function?(CallbackSpec.new(module: M, function: :foo))
        true

        iex> alias ElixirOntologies.Extractors.Attribute.CallbackSpec
        iex> CallbackSpec.has_function?(CallbackSpec.new(module: M))
        false
    """
    @spec has_function?(t()) :: boolean()
    def has_function?(%__MODULE__{function: nil}), do: false
    def has_function?(%__MODULE__{}), do: true
  end

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

  # ===========================================================================
  # Typed Value Extraction
  # ===========================================================================

  @doc """
  Extracts a typed AttributeValue from an attribute's raw value.

  Analyzes the value AST and returns an `AttributeValue` struct with
  type classification and evaluated value where possible.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> val = Attribute.extract_typed_value(42)
      iex> val.type
      :literal
      iex> val.value
      42

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> val = Attribute.extract_typed_value("hello")
      iex> val.type
      :literal
      iex> val.value
      "hello"

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> val = Attribute.extract_typed_value([1, 2, 3])
      iex> val.type
      :list
      iex> val.value
      [1, 2, 3]

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> val = Attribute.extract_typed_value([a: 1, b: 2])
      iex> val.type
      :keyword_list
      iex> val.value
      [a: 1, b: 2]

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> val = Attribute.extract_typed_value({:__aliases__, [], [:MyModule]})
      iex> val.type
      :module_ref
      iex> val.value
      MyModule
  """
  @spec extract_typed_value(term()) :: AttributeValue.t()
  def extract_typed_value(nil) do
    AttributeValue.new(type: nil, value: nil)
  end

  def extract_typed_value(value) when is_atom(value) do
    AttributeValue.new(type: :literal, value: value)
  end

  def extract_typed_value(value) when is_binary(value) do
    AttributeValue.new(type: :literal, value: value)
  end

  def extract_typed_value(value) when is_integer(value) do
    AttributeValue.new(type: :literal, value: value)
  end

  def extract_typed_value(value) when is_float(value) do
    AttributeValue.new(type: :literal, value: value)
  end

  def extract_typed_value(value) when is_boolean(value) do
    AttributeValue.new(type: :literal, value: value)
  end

  # Module reference: {:__aliases__, _, [:Module, :Name]}
  def extract_typed_value({:__aliases__, _, parts}) when is_list(parts) do
    module = Module.concat(parts)
    AttributeValue.new(type: :module_ref, value: module, raw_ast: {:__aliases__, [], parts})
  end

  # Map literal: %{...}
  def extract_typed_value({:%{}, _, pairs}) when is_list(pairs) do
    case try_evaluate_map(pairs) do
      {:ok, map} ->
        AttributeValue.new(type: :map, value: map, raw_ast: {:%{}, [], pairs})

      :error ->
        AttributeValue.new(type: :ast, raw_ast: {:%{}, [], pairs})
    end
  end

  # Tuple: {a, b, c}
  def extract_typed_value({:{}, _, elements}) when is_list(elements) do
    case try_evaluate_list(elements) do
      {:ok, evaluated} ->
        AttributeValue.new(
          type: :tuple,
          value: List.to_tuple(evaluated),
          raw_ast: {:{}, [], elements}
        )

      :error ->
        AttributeValue.new(type: :ast, raw_ast: {:{}, [], elements})
    end
  end

  # Two-element tuple
  def extract_typed_value({a, b}) do
    case {try_evaluate_value(a), try_evaluate_value(b)} do
      {{:ok, va}, {:ok, vb}} ->
        AttributeValue.new(type: :tuple, value: {va, vb}, raw_ast: {a, b})

      _ ->
        AttributeValue.new(type: :ast, raw_ast: {a, b})
    end
  end

  # List (including keyword lists)
  def extract_typed_value(list) when is_list(list) do
    cond do
      list == [] ->
        AttributeValue.new(type: :list, value: [])

      keyword_list?(list) ->
        case try_evaluate_keyword_list(list) do
          {:ok, kw} ->
            AttributeValue.new(type: :keyword_list, value: kw)

          :error ->
            AttributeValue.new(type: :ast, raw_ast: list)
        end

      true ->
        case try_evaluate_list(list) do
          {:ok, evaluated} ->
            AttributeValue.new(type: :list, value: evaluated)

          :error ->
            AttributeValue.new(type: :ast, raw_ast: list)
        end
    end
  end

  # Complex AST (function calls, etc.)
  def extract_typed_value(ast) do
    AttributeValue.new(type: :ast, raw_ast: ast)
  end

  @doc """
  Checks if a term is a keyword list (list of {atom, value} tuples).

  ## Examples

      iex> ElixirOntologies.Extractors.Attribute.keyword_list?([a: 1, b: 2])
      true

      iex> ElixirOntologies.Extractors.Attribute.keyword_list?([1, 2, 3])
      false

      iex> ElixirOntologies.Extractors.Attribute.keyword_list?([])
      false

      iex> ElixirOntologies.Extractors.Attribute.keyword_list?([{:a, 1}])
      true
  """
  @spec keyword_list?(term()) :: boolean()
  def keyword_list?([]), do: false

  def keyword_list?(list) when is_list(list) do
    Enum.all?(list, fn
      {key, _value} when is_atom(key) -> true
      _ -> false
    end)
  end

  def keyword_list?(_), do: false

  @doc """
  Gets the typed value information for an extracted attribute.

  Returns an `AttributeValue` struct from the attribute's value field.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:my_attr, [], [42]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> val_info = Attribute.value_info(attr)
      iex> val_info.type
      :literal
      iex> val_info.value
      42
  """
  @spec value_info(t()) :: AttributeValue.t()
  def value_info(%__MODULE__{value: value}) do
    extract_typed_value(value)
  end

  @doc """
  Extracts all register_attribute calls from a module body.

  Returns a list of attribute names that are registered with `accumulate: true`.

  ## Examples

      iex> code = "Module.register_attribute(__MODULE__, :my_attr, accumulate: true)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> ElixirOntologies.Extractors.Attribute.extract_accumulated_attributes({:__block__, [], [ast]})
      [:my_attr]

      iex> code = "Module.register_attribute(__MODULE__, :other, [])"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> ElixirOntologies.Extractors.Attribute.extract_accumulated_attributes({:__block__, [], [ast]})
      []
  """
  @spec extract_accumulated_attributes(Macro.t()) :: [atom()]
  def extract_accumulated_attributes(body) do
    body
    |> Helpers.normalize_body()
    |> Enum.flat_map(&extract_register_attribute_call/1)
    |> Enum.filter(fn {_name, accumulated} -> accumulated end)
    |> Enum.map(fn {name, _} -> name end)
  end

  @doc """
  Checks if an attribute name is accumulated based on register_attribute calls.

  ## Examples

      iex> code = "Module.register_attribute(__MODULE__, :items, accumulate: true)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> body = {:__block__, [], [ast]}
      iex> ElixirOntologies.Extractors.Attribute.accumulated?(:items, body)
      true

      iex> ElixirOntologies.Extractors.Attribute.accumulated?(:other, {:__block__, [], []})
      false
  """
  @spec accumulated?(atom(), Macro.t()) :: boolean()
  def accumulated?(attr_name, body) do
    attr_name in extract_accumulated_attributes(body)
  end

  # ===========================================================================
  # Documentation Content Extraction
  # ===========================================================================

  @doc """
  Extracts documentation content from a documentation attribute.

  Takes an extracted Attribute struct and returns a `DocContent` struct
  with the parsed documentation text and format information.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], ["Simple documentation"]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> doc = Attribute.extract_doc_content(attr)
      iex> doc.content
      "Simple documentation"
      iex> doc.format
      :string

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], [false]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> doc = Attribute.extract_doc_content(attr)
      iex> doc.hidden
      true
      iex> doc.format
      :false

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:custom, [], [42]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.extract_doc_content(attr)
      nil
  """
  @spec extract_doc_content(t()) :: DocContent.t() | nil
  def extract_doc_content(%__MODULE__{name: name, value: value})
      when name in [:doc, :moduledoc, :typedoc] do
    parse_doc_value(value)
  end

  def extract_doc_content(_), do: nil

  @doc """
  Gets the documentation content string from an attribute.

  Returns the documentation text or nil if not a doc attribute or if hidden.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], ["Hello world"]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.doc_content(attr)
      "Hello world"

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], [false]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.doc_content(attr)
      nil
  """
  @spec doc_content(t()) :: String.t() | nil
  def doc_content(%__MODULE__{} = attr) do
    case extract_doc_content(attr) do
      %DocContent{content: content} -> content
      nil -> nil
    end
  end

  @doc """
  Checks if a documentation attribute is hidden (@doc false).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], [false]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.doc_hidden?(attr)
      true

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], ["visible"]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.doc_hidden?(attr)
      false

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:custom, [], [42]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.doc_hidden?(attr)
      false
  """
  @spec doc_hidden?(t()) :: boolean()
  def doc_hidden?(%__MODULE__{} = attr) do
    case extract_doc_content(attr) do
      %DocContent{hidden: true} -> true
      _ -> false
    end
  end

  @doc """
  Checks if an attribute has documentation content.

  Returns true if the attribute is a doc attribute with non-empty content.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], ["Some docs"]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.has_doc?(attr)
      true

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], [false]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.has_doc?(attr)
      false

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:custom, [], [42]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.has_doc?(attr)
      false
  """
  @spec has_doc?(t()) :: boolean()
  def has_doc?(%__MODULE__{} = attr) do
    case extract_doc_content(attr) do
      %DocContent{} = doc -> DocContent.has_content?(doc)
      nil -> false
    end
  end

  @doc """
  Gets the documentation format from an attribute.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], ["docs"]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.doc_format(attr)
      :string

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], [false]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.doc_format(attr)
      :false
  """
  @spec doc_format(t()) :: DocContent.format() | nil
  def doc_format(%__MODULE__{} = attr) do
    case extract_doc_content(attr) do
      %DocContent{format: format} -> format
      nil -> nil
    end
  end

  # Parse documentation value into DocContent
  defp parse_doc_value(false) do
    DocContent.new(format: false, hidden: true)
  end

  defp parse_doc_value(nil) do
    DocContent.new(format: nil)
  end

  defp parse_doc_value(content) when is_binary(content) do
    format = detect_doc_format(content)
    DocContent.new(content: content, format: format)
  end

  # Handle sigil AST: {:sigil_S, _, [{:<<>>, _, [content]}, []]}
  defp parse_doc_value({sigil, _, [{:<<>>, _, [content]}, _modifiers]})
       when sigil in [:sigil_S, :sigil_s] and is_binary(content) do
    sigil_type = sigil_to_type(sigil)
    DocContent.new(content: content, format: :sigil, sigil_type: sigil_type)
  end

  # Handle other sigil forms
  defp parse_doc_value({sigil, _, [content, _modifiers]})
       when sigil in [:sigil_S, :sigil_s] and is_binary(content) do
    sigil_type = sigil_to_type(sigil)
    DocContent.new(content: content, format: :sigil, sigil_type: sigil_type)
  end

  # Handle complex/unknown values
  defp parse_doc_value(_) do
    DocContent.new(format: nil)
  end

  # Detect if content is heredoc format (contains newlines suggesting multi-line)
  defp detect_doc_format(content) when is_binary(content) do
    if String.contains?(content, "\n") do
      :heredoc
    else
      :string
    end
  end

  @spec sigil_to_type(:sigil_S | :sigil_s) :: :S | :s
  defp sigil_to_type(:sigil_S), do: :S
  defp sigil_to_type(:sigil_s), do: :s

  # ===========================================================================
  # Compile Options Extraction
  # ===========================================================================

  @doc """
  Extracts compile options from a @compile attribute.

  Takes an extracted Attribute struct and returns a `CompileOptions` struct
  with parsed compile directive values.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:compile, [], [:inline]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> opts = Attribute.extract_compile_options(attr)
      iex> opts.inline
      true

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:compile, [], [[inline: [{:foo, 1}, {:bar, 2}]]]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> opts = Attribute.extract_compile_options(attr)
      iex> opts.inline
      [{:foo, 1}, {:bar, 2}]

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:compile, [], [:debug_info]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> opts = Attribute.extract_compile_options(attr)
      iex> opts.debug_info
      true

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], ["docs"]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.extract_compile_options(attr)
      nil
  """
  @spec extract_compile_options(t()) :: CompileOptions.t() | nil
  def extract_compile_options(%__MODULE__{type: :compile_attribute, value: value}) do
    parse_compile_options(value)
  end

  def extract_compile_options(_), do: nil

  @doc """
  Checks if an attribute has inline compilation enabled.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:compile, [], [:inline]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.compile_inline?(attr)
      true

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:compile, [], [:debug_info]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.compile_inline?(attr)
      false
  """
  @spec compile_inline?(t()) :: boolean()
  def compile_inline?(%__MODULE__{} = attr) do
    case extract_compile_options(attr) do
      %CompileOptions{} = opts -> CompileOptions.inline?(opts)
      nil -> false
    end
  end

  @doc """
  Gets the inline functions list from a compile attribute.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:compile, [], [[inline: [{:foo, 1}]]]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.compile_inline_functions(attr)
      [{:foo, 1}]

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:compile, [], [:inline]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.compile_inline_functions(attr)
      true
  """
  @spec compile_inline_functions(t()) :: [{atom(), non_neg_integer()}] | true | nil
  def compile_inline_functions(%__MODULE__{} = attr) do
    case extract_compile_options(attr) do
      %CompileOptions{inline: inline} -> inline
      nil -> nil
    end
  end

  # Parse @compile value into CompileOptions struct
  defp parse_compile_options(value) do
    raw_options = normalize_compile_options(value)

    CompileOptions.new(
      inline: extract_inline_option(raw_options),
      no_warn_undefined: extract_no_warn_undefined_option(raw_options),
      warnings_as_errors: extract_boolean_option(raw_options, :warnings_as_errors),
      debug_info: extract_boolean_option(raw_options, :debug_info),
      raw_options: raw_options
    )
  end

  # Normalize compile options to a consistent format
  defp normalize_compile_options(value) when is_atom(value), do: [value]
  defp normalize_compile_options(value) when is_list(value), do: List.flatten(value)
  defp normalize_compile_options({_key, _value} = tuple), do: [tuple]
  defp normalize_compile_options(_), do: []

  # Extract :inline option
  defp extract_inline_option(options) do
    cond do
      :inline in options -> true
      Keyword.has_key?(options, :inline) -> Keyword.get(options, :inline)
      true -> nil
    end
  end

  # Extract :no_warn_undefined option
  defp extract_no_warn_undefined_option(options) do
    cond do
      :no_warn_undefined in options ->
        true

      Keyword.has_key?(options, :no_warn_undefined) ->
        Keyword.get(options, :no_warn_undefined)

      true ->
        # Check for tuple format {:no_warn_undefined, ...}
        Enum.find_value(options, fn
          {:no_warn_undefined, value} -> normalize_no_warn_value(value)
          _ -> nil
        end)
    end
  end

  defp normalize_no_warn_value(value) when is_list(value), do: value
  defp normalize_no_warn_value(value) when is_atom(value), do: [value]
  defp normalize_no_warn_value({_m, _f, _a} = mfa), do: [mfa]
  defp normalize_no_warn_value(_), do: nil

  # Extract boolean options like :debug_info, :warnings_as_errors
  defp extract_boolean_option(options, key) do
    cond do
      key in options -> true
      Keyword.has_key?(options, key) -> Keyword.get(options, key)
      true -> nil
    end
  end

  # ===========================================================================
  # Callback Spec Extraction
  # ===========================================================================

  @doc """
  Extracts callback specification from @on_definition, @before_compile, or @after_compile.

  Takes an extracted Attribute struct and returns a `CallbackSpec` struct
  with the target module and function.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:before_compile, [], [{:__aliases__, [], [:MyHooks]}]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> spec = Attribute.extract_callback_spec(attr)
      iex> spec.module
      MyHooks

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:on_definition, [], [{{:__aliases__, [], [:MyMod]}, :track}]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> spec = Attribute.extract_callback_spec(attr)
      iex> spec.module
      MyMod
      iex> spec.function
      :track

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:after_compile, [], [{:__MODULE__, :validate}]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> spec = Attribute.extract_callback_spec(attr)
      iex> spec.is_current_module
      true
      iex> spec.function
      :validate

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], ["docs"]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.extract_callback_spec(attr)
      nil
  """
  @spec extract_callback_spec(t()) :: CallbackSpec.t() | nil
  def extract_callback_spec(%__MODULE__{type: type, value: value})
      when type in [:on_definition_attribute, :before_compile_attribute, :after_compile_attribute] do
    parse_callback_spec(value)
  end

  def extract_callback_spec(_), do: nil

  @doc """
  Gets the callback module from a callback attribute.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:before_compile, [], [{:__aliases__, [], [:Hooks]}]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.callback_module(attr)
      Hooks
  """
  @spec callback_module(t()) :: module() | nil
  def callback_module(%__MODULE__{} = attr) do
    case extract_callback_spec(attr) do
      %CallbackSpec{module: mod} -> mod
      nil -> nil
    end
  end

  @doc """
  Gets the callback function from a callback attribute.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:on_definition, [], [{{:__aliases__, [], [:M]}, :track}]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.callback_function(attr)
      :track
  """
  @spec callback_function(t()) :: atom() | nil
  def callback_function(%__MODULE__{} = attr) do
    case extract_callback_spec(attr) do
      %CallbackSpec{function: func} -> func
      nil -> nil
    end
  end

  @doc """
  Checks if a callback references __MODULE__.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:before_compile, [], [{:__MODULE__, :hook}]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.callback_is_current_module?(attr)
      true
  """
  @spec callback_is_current_module?(t()) :: boolean()
  def callback_is_current_module?(%__MODULE__{} = attr) do
    case extract_callback_spec(attr) do
      %CallbackSpec{is_current_module: true} -> true
      _ -> false
    end
  end

  # Parse callback value into CallbackSpec struct
  # Format: Module
  defp parse_callback_spec({:__aliases__, _, parts}) when is_list(parts) do
    CallbackSpec.new(module: Module.concat(parts))
  end

  # Format: {Module, :function}
  defp parse_callback_spec({{:__aliases__, _, parts}, func})
       when is_list(parts) and is_atom(func) do
    CallbackSpec.new(module: Module.concat(parts), function: func)
  end

  # Format: __MODULE__
  defp parse_callback_spec({:__MODULE__, _, _}) do
    CallbackSpec.new(is_current_module: true)
  end

  # Format: {:__MODULE__, :function}
  defp parse_callback_spec({{:__MODULE__, _, _}, func}) when is_atom(func) do
    CallbackSpec.new(is_current_module: true, function: func)
  end

  # Format: module atom directly
  defp parse_callback_spec(module) when is_atom(module) and module != nil do
    if module == :__MODULE__ do
      CallbackSpec.new(is_current_module: true)
    else
      CallbackSpec.new(module: module)
    end
  end

  # Format: {module_atom, :function}
  defp parse_callback_spec({module, func}) when is_atom(module) and is_atom(func) do
    if module == :__MODULE__ do
      CallbackSpec.new(is_current_module: true, function: func)
    else
      CallbackSpec.new(module: module, function: func)
    end
  end

  defp parse_callback_spec(_), do: CallbackSpec.new()

  # ===========================================================================
  # External Resource Extraction
  # ===========================================================================

  @doc """
  Extracts all @external_resource file paths from a module body.

  Returns a list of file path strings from all @external_resource attributes.

  ## Examples

      iex> body = {:__block__, [], [
      ...>   {:@, [], [{:external_resource, [], ["priv/data.json"]}]},
      ...>   {:@, [], [{:external_resource, [], ["priv/config.yml"]}]},
      ...>   {:def, [], [{:foo, [], nil}]}
      ...> ]}
      iex> ElixirOntologies.Extractors.Attribute.extract_external_resources(body)
      ["priv/data.json", "priv/config.yml"]

      iex> body = {:__block__, [], []}
      iex> ElixirOntologies.Extractors.Attribute.extract_external_resources(body)
      []
  """
  @spec extract_external_resources(Macro.t()) :: [String.t()]
  def extract_external_resources(body) do
    body
    |> extract_all()
    |> Enum.filter(fn attr -> attr.type == :external_resource_attribute end)
    |> Enum.map(fn attr -> attr.metadata[:path] end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Gets the file path from an @external_resource attribute.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:external_resource, [], ["priv/data.json"]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.external_resource_path(attr)
      "priv/data.json"

      iex> alias ElixirOntologies.Extractors.Attribute
      iex> ast = {:@, [], [{:doc, [], ["docs"]}]}
      iex> {:ok, attr} = Attribute.extract(ast)
      iex> Attribute.external_resource_path(attr)
      nil
  """
  @spec external_resource_path(t()) :: String.t() | nil
  def external_resource_path(%__MODULE__{type: :external_resource_attribute, metadata: meta}) do
    meta[:path]
  end

  def external_resource_path(_), do: nil

  # ===========================================================================
  # Private Helpers - Value Evaluation
  # ===========================================================================

  defp try_evaluate_value(value) when is_atom(value), do: {:ok, value}
  defp try_evaluate_value(value) when is_binary(value), do: {:ok, value}
  defp try_evaluate_value(value) when is_integer(value), do: {:ok, value}
  defp try_evaluate_value(value) when is_float(value), do: {:ok, value}
  defp try_evaluate_value(value) when is_boolean(value), do: {:ok, value}

  defp try_evaluate_value({:__aliases__, _, parts}) when is_list(parts) do
    {:ok, Module.concat(parts)}
  end

  defp try_evaluate_value(list) when is_list(list) do
    try_evaluate_list(list)
  end

  defp try_evaluate_value({:%{}, _, pairs}) when is_list(pairs) do
    try_evaluate_map(pairs)
  end

  defp try_evaluate_value({:{}, _, elements}) when is_list(elements) do
    case try_evaluate_list(elements) do
      {:ok, evaluated} -> {:ok, List.to_tuple(evaluated)}
      :error -> :error
    end
  end

  defp try_evaluate_value({a, b}) do
    case {try_evaluate_value(a), try_evaluate_value(b)} do
      {{:ok, va}, {:ok, vb}} -> {:ok, {va, vb}}
      _ -> :error
    end
  end

  defp try_evaluate_value(_), do: :error

  defp try_evaluate_list(list) do
    results = Enum.map(list, &try_evaluate_value/1)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, v} -> v end)}
    else
      :error
    end
  end

  defp try_evaluate_keyword_list(list) do
    results =
      Enum.map(list, fn
        {key, value} when is_atom(key) ->
          case try_evaluate_value(value) do
            {:ok, v} -> {:ok, {key, v}}
            :error -> :error
          end

        _ ->
          :error
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, kv} -> kv end)}
    else
      :error
    end
  end

  defp try_evaluate_map(pairs) do
    results =
      Enum.map(pairs, fn
        {key, value} ->
          case {try_evaluate_value(key), try_evaluate_value(value)} do
            {{:ok, k}, {:ok, v}} -> {:ok, {k, v}}
            _ -> :error
          end
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      map = Enum.into(Enum.map(results, fn {:ok, kv} -> kv end), %{})
      {:ok, map}
    else
      :error
    end
  end

  # ===========================================================================
  # Private Helpers - Register Attribute Extraction
  # ===========================================================================

  # Module.register_attribute(__MODULE__, :attr_name, accumulate: true)
  defp extract_register_attribute_call(
         {{:., _, [{:__aliases__, _, [:Module]}, :register_attribute]}, _,
          [_module, attr_name, opts]}
       )
       when is_atom(attr_name) and is_list(opts) do
    accumulated = Keyword.get(opts, :accumulate, false)
    [{attr_name, accumulated}]
  end

  defp extract_register_attribute_call(_), do: []
end
