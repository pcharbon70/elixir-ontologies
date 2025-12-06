defmodule ElixirOntologies.Extractors.Protocol do
  @moduledoc """
  Extracts protocol definitions and implementations from AST nodes.

  This module analyzes Elixir AST nodes representing `defprotocol` and `defimpl`
  constructs. Supports the protocol-related classes from elixir-structure.ttl:

  - Protocol: `defprotocol Enumerable do ... end`
  - ProtocolFunction: Function signatures defined in protocol
  - ProtocolImplementation: `defimpl Enumerable, for: List do ... end`

  ## Protocol Definition Usage

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> ast = quote do
      ...>   defprotocol Stringable do
      ...>     def to_string(data)
      ...>   end
      ...> end
      iex> {:ok, result} = Protocol.extract(ast)
      iex> result.name
      [:Stringable]
      iex> length(result.functions)
      1

  ## Protocol Implementation Usage

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> code = "defimpl String.Chars, for: Integer do def to_string(i), do: Integer.to_string(i) end"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, impl} = Protocol.extract_implementation(ast)
      iex> impl.protocol
      [:String, :Chars]
      iex> impl.for_type
      [:Integer]
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Protocol Definition Struct
  # ===========================================================================

  @typedoc """
  The result of protocol extraction.

  - `:name` - Protocol name as list of atoms (e.g., `[:Enumerable]`)
  - `:functions` - List of protocol function definitions
  - `:fallback_to_any` - Whether @fallback_to_any true is set
  - `:doc` - Protocol documentation from @moduledoc
  - `:typedoc` - Protocol @typedoc if present
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          name: [atom()],
          functions: [protocol_function()],
          fallback_to_any: boolean(),
          doc: String.t() | false | nil,
          typedoc: String.t() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @typedoc """
  A protocol function definition.

  - `:name` - Function name (atom)
  - `:arity` - Number of parameters
  - `:parameters` - Parameter names as atoms
  - `:doc` - Function @doc if present
  - `:spec` - Function @spec AST if present
  - `:location` - Source location
  """
  @type protocol_function :: %{
          name: atom(),
          arity: non_neg_integer(),
          parameters: [atom()],
          doc: String.t() | nil,
          spec: Macro.t() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  defstruct [
    :name,
    functions: [],
    fallback_to_any: false,
    doc: nil,
    typedoc: nil,
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Protocol Implementation Struct
  # ===========================================================================

  defmodule Implementation do
    @moduledoc """
    Represents a protocol implementation (`defimpl`).
    """

    @typedoc """
    The result of protocol implementation extraction.

    - `:protocol` - Protocol name as list of atoms
    - `:for_type` - Target type (list of atoms, atom, or special form)
    - `:functions` - List of implemented functions
    - `:is_any` - Whether this is a `for: Any` implementation
    - `:location` - Source location if available
    - `:metadata` - Additional information
    """
    @type t :: %__MODULE__{
            protocol: [atom()],
            for_type: [atom()] | atom(),
            functions: [impl_function()],
            is_any: boolean(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    @typedoc """
    An implemented function in a protocol implementation.
    """
    @type impl_function :: %{
            name: atom(),
            arity: non_neg_integer(),
            has_body: boolean(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
          }

    defstruct [
      :protocol,
      :for_type,
      functions: [],
      is_any: false,
      location: nil,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Derive Info Struct
  # ===========================================================================

  defmodule DeriveInfo do
    @moduledoc """
    Represents a `@derive` directive.
    """

    @typedoc """
    Information about a @derive directive.

    - `:protocols` - List of derived protocols (with options)
    - `:location` - Source location
    """
    @type t :: %__MODULE__{
            protocols: [derive_protocol()],
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
          }

    @typedoc """
    A protocol in a @derive directive.
    """
    @type derive_protocol :: %{
            protocol: [atom()] | atom(),
            options: keyword() | nil
          }

    defstruct [
      protocols: [],
      location: nil
    ]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a protocol definition.

  ## Examples

      iex> ElixirOntologies.Extractors.Protocol.protocol?({:defprotocol, [], [{:__aliases__, [], [:Foo]}, [do: nil]]})
      true

      iex> ElixirOntologies.Extractors.Protocol.protocol?({:defmodule, [], [{:__aliases__, [], [:Foo]}, [do: nil]]})
      false

      iex> ElixirOntologies.Extractors.Protocol.protocol?(:not_a_protocol)
      false
  """
  @spec protocol?(Macro.t()) :: boolean()
  def protocol?({:defprotocol, _meta, [_name | _rest]}), do: true
  def protocol?(_), do: false

  @doc """
  Checks if an AST node represents a protocol implementation.

  ## Examples

      iex> ElixirOntologies.Extractors.Protocol.implementation?({:defimpl, [], [{:__aliases__, [], [:Proto]}, [for: :atom], [do: nil]]})
      true

      iex> ElixirOntologies.Extractors.Protocol.implementation?({:defprotocol, [], [{:__aliases__, [], [:Proto]}, [do: nil]]})
      false

      iex> ElixirOntologies.Extractors.Protocol.implementation?(:not_impl)
      false
  """
  @spec implementation?(Macro.t()) :: boolean()
  def implementation?({:defimpl, _meta, _args}), do: true
  def implementation?(_), do: false

  # ===========================================================================
  # Protocol Definition Extraction
  # ===========================================================================

  @doc """
  Extracts protocol information from an AST node.

  Returns `{:ok, result}` with a `Protocol` struct containing the protocol's
  name, functions, and attributes.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> ast = {:defprotocol, [], [{:__aliases__, [], [:MyProtocol]}, [do: nil]]}
      iex> {:ok, result} = Protocol.extract(ast)
      iex> result.name
      [:MyProtocol]

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> Protocol.extract({:def, [], [{:foo, [], nil}]})
      {:error, "Not a protocol definition: {:def, [], [{:foo, [], nil}]}"}
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  def extract({:defprotocol, meta, [{:__aliases__, _alias_meta, name_parts}, body_opts]}, opts) do
    include_location = Keyword.get(opts, :include_location, true)
    body = Helpers.extract_do_body(body_opts)

    location =
      if include_location do
        Helpers.extract_location({:defprotocol, meta, []})
      else
        nil
      end

    {functions, _pending_doc, _pending_spec} = extract_protocol_functions(body)
    fallback_to_any = extract_fallback_to_any(body)
    doc = Helpers.extract_moduledoc(body)
    typedoc = extract_typedoc(body)

    {:ok,
     %__MODULE__{
       name: name_parts,
       functions: functions,
       fallback_to_any: fallback_to_any,
       doc: doc,
       typedoc: typedoc,
       location: location,
       metadata: %{}
     }}
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Not a protocol definition", node)}
  end

  @doc """
  Extracts protocol information, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> ast = {:defprotocol, [], [{:__aliases__, [], [:MyProtocol]}, [do: nil]]}
      iex> result = Protocol.extract!(ast)
      iex> result.name
      [:MyProtocol]
  """
  @spec extract!(Macro.t(), keyword()) :: t()
  def extract!(node, opts \\ []) do
    case extract(node, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Extracts all protocol definitions from a list of AST nodes.

  Non-protocol nodes are silently skipped.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> nodes = [
      ...>   {:defprotocol, [], [{:__aliases__, [], [:Proto1]}, [do: nil]]},
      ...>   {:defmodule, [], [{:__aliases__, [], [:Mod]}, [do: nil]]},
      ...>   {:defprotocol, [], [{:__aliases__, [], [:Proto2]}, [do: nil]]}
      ...> ]
      iex> results = Protocol.extract_all(nodes)
      iex> length(results)
      2
      iex> Enum.map(results, & &1.name)
      [[:Proto1], [:Proto2]]
  """
  @spec extract_all([Macro.t()], keyword()) :: [t()]
  def extract_all(nodes, opts \\ []) when is_list(nodes) do
    nodes
    |> Enum.filter(&protocol?/1)
    |> Enum.map(fn node ->
      case extract(node, opts) do
        {:ok, result} -> result
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ===========================================================================
  # Protocol Implementation Extraction
  # ===========================================================================

  @doc """
  Extracts protocol implementation information from a defimpl AST node.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> code = "defimpl String.Chars, for: Integer do def to_string(i), do: Integer.to_string(i) end"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, impl} = Protocol.extract_implementation(ast)
      iex> impl.protocol
      [:String, :Chars]
      iex> impl.for_type
      [:Integer]

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> code = "defimpl Enumerable, for: Any do def count(_), do: {:error, __MODULE__} end"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, impl} = Protocol.extract_implementation(ast)
      iex> impl.is_any
      true

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> Protocol.extract_implementation({:defmodule, [], []})
      {:error, "Not a protocol implementation: {:defmodule, [], []}"}
  """
  @spec extract_implementation(Macro.t(), keyword()) :: {:ok, Implementation.t()} | {:error, String.t()}
  def extract_implementation(node, opts \\ [])

  # Standard defimpl with for: option
  def extract_implementation(
        {:defimpl, meta, [{:__aliases__, _, protocol_parts}, [for: for_type_ast], body_opts]},
        opts
      ) do
    include_location = Keyword.get(opts, :include_location, true)
    body = Helpers.extract_do_body(body_opts)

    location =
      if include_location do
        Helpers.extract_location({:defimpl, meta, []})
      else
        nil
      end

    for_type = extract_type_name(for_type_ast)
    is_any = for_type == [:Any] or for_type == :Any
    functions = extract_impl_functions(body)

    {:ok,
     %Implementation{
       protocol: protocol_parts,
       for_type: for_type,
       functions: functions,
       is_any: is_any,
       location: location,
       metadata: %{}
     }}
  end

  # defimpl inside the target module (no for: option needed)
  def extract_implementation(
        {:defimpl, meta, [{:__aliases__, _, protocol_parts}, body_opts]},
        opts
      )
      when is_list(body_opts) do
    include_location = Keyword.get(opts, :include_location, true)
    body = Helpers.extract_do_body(body_opts)

    location =
      if include_location do
        Helpers.extract_location({:defimpl, meta, []})
      else
        nil
      end

    functions = extract_impl_functions(body)

    {:ok,
     %Implementation{
       protocol: protocol_parts,
       for_type: :__MODULE__,
       functions: functions,
       is_any: false,
       location: location,
       metadata: %{inline: true}
     }}
  end

  def extract_implementation(node, _opts) do
    {:error, Helpers.format_error("Not a protocol implementation", node)}
  end

  @doc """
  Extracts protocol implementation, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> code = "defimpl Proto, for: List do end"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> impl = Protocol.extract_implementation!(ast)
      iex> impl.protocol
      [:Proto]
  """
  @spec extract_implementation!(Macro.t(), keyword()) :: Implementation.t()
  def extract_implementation!(node, opts \\ []) do
    case extract_implementation(node, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Extracts all protocol implementations from a list of AST nodes.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> code1 = "defimpl P1, for: Integer do end"
      iex> code2 = "defimpl P2, for: String do end"
      iex> {:ok, ast1} = Code.string_to_quoted(code1)
      iex> {:ok, ast2} = Code.string_to_quoted(code2)
      iex> impls = Protocol.extract_all_implementations([ast1, ast2, :not_impl])
      iex> length(impls)
      2
  """
  @spec extract_all_implementations([Macro.t()], keyword()) :: [Implementation.t()]
  def extract_all_implementations(nodes, opts \\ []) when is_list(nodes) do
    nodes
    |> Enum.filter(&implementation?/1)
    |> Enum.map(fn node ->
      case extract_implementation(node, opts) do
        {:ok, result} -> result
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ===========================================================================
  # @derive Extraction
  # ===========================================================================

  @doc """
  Extracts @derive directives from a module body.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> code = "defmodule M do @derive [Inspect, Enumerable]; defstruct [:a] end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> derives = Protocol.extract_derives(body)
      iex> length(derives)
      1
      iex> hd(derives).protocols |> Enum.map(& &1.protocol)
      [[:Inspect], [:Enumerable]]
  """
  @spec extract_derives(Macro.t()) :: [DeriveInfo.t()]
  def extract_derives(body) do
    body
    |> Helpers.normalize_body()
    |> Enum.filter(&derive_attribute?/1)
    |> Enum.map(&extract_single_derive/1)
  end

  defp derive_attribute?({:@, _meta, [{:derive, _attr_meta, _args}]}), do: true
  defp derive_attribute?(_), do: false

  defp extract_single_derive({:@, meta, [{:derive, _attr_meta, [protocols]}]}) do
    location = Helpers.extract_location({:@, meta, []})
    protocol_list = normalize_derive_protocols(protocols)

    %DeriveInfo{
      protocols: protocol_list,
      location: location
    }
  end

  defp normalize_derive_protocols(protocols) when is_list(protocols) do
    Enum.map(protocols, &normalize_derive_protocol/1)
  end

  defp normalize_derive_protocols(single) do
    [normalize_derive_protocol(single)]
  end

  defp normalize_derive_protocol({:__aliases__, _, parts}) do
    %{protocol: parts, options: nil}
  end

  defp normalize_derive_protocol({{:__aliases__, _, parts}, opts}) when is_list(opts) do
    %{protocol: parts, options: opts}
  end

  defp normalize_derive_protocol(atom) when is_atom(atom) do
    %{protocol: atom, options: nil}
  end

  defp normalize_derive_protocol({atom, opts}) when is_atom(atom) and is_list(opts) do
    %{protocol: atom, options: opts}
  end

  # ===========================================================================
  # Protocol Function Extraction
  # ===========================================================================

  defp extract_protocol_functions(body) do
    {functions, pending_doc, pending_spec} =
      Enum.reduce(body, {[], nil, nil}, fn
        # @doc attribute - save for next function
        {:@, _meta, [{:doc, _doc_meta, [doc_value]}]}, {fns, _doc, spec} ->
          {fns, doc_value, spec}

        # @spec attribute - save for next function
        {:@, _meta, [{:spec, _spec_meta, [spec_value]}]}, {fns, doc, _spec} ->
          {fns, doc, spec_value}

        # Protocol function (def without body)
        {:def, meta, [{name, _call_meta, args}]}, {fns, doc, spec} when is_atom(name) ->
          params = extract_parameter_names(args)
          arity = length(params)

          location = Helpers.extract_location({:def, meta, []})

          fn_info = %{
            name: name,
            arity: arity,
            parameters: params,
            doc: doc,
            spec: spec,
            location: location
          }

          {[fn_info | fns], nil, nil}

        # Protocol function with when clause
        {:def, meta, [{:when, _, [{name, _call_meta, args} | _guards]}]}, {fns, doc, spec}
        when is_atom(name) ->
          params = extract_parameter_names(args)
          arity = length(params)

          location = Helpers.extract_location({:def, meta, []})

          fn_info = %{
            name: name,
            arity: arity,
            parameters: params,
            doc: doc,
            spec: spec,
            location: location
          }

          {[fn_info | fns], nil, nil}

        # Skip other nodes but preserve pending doc/spec
        _other, {fns, doc, spec} ->
          {fns, doc, spec}
      end)

    {Enum.reverse(functions), pending_doc, pending_spec}
  end

  defp extract_parameter_names(nil), do: []

  defp extract_parameter_names(args) when is_list(args) do
    Enum.map(args, fn
      {name, _meta, context} when is_atom(name) and is_atom(context) -> name
      {name, _meta, _args} when is_atom(name) -> name
      _ -> :_
    end)
  end

  # ===========================================================================
  # Implementation Function Extraction
  # ===========================================================================

  defp extract_impl_functions(body) do
    body
    |> Enum.filter(fn
      {:def, _, _} -> true
      {:defp, _, _} -> true
      _ -> false
    end)
    |> Enum.map(&extract_impl_function/1)
  end

  defp extract_impl_function({def_type, meta, [{name, _call_meta, args} | rest]}) when is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    has_body = has_function_body?(rest)
    location = Helpers.extract_location({def_type, meta, []})

    %{
      name: name,
      arity: arity,
      has_body: has_body,
      location: location
    }
  end

  defp extract_impl_function({def_type, meta, [{:when, _, [{name, _call_meta, args} | _]} | rest]})
       when is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    has_body = has_function_body?(rest)
    location = Helpers.extract_location({def_type, meta, []})

    %{
      name: name,
      arity: arity,
      has_body: has_body,
      location: location
    }
  end

  defp has_function_body?([[do: _body] | _]), do: true
  defp has_function_body?([{:do, _body} | _]), do: true
  defp has_function_body?(_), do: false

  # ===========================================================================
  # Type Name Extraction
  # ===========================================================================

  defp extract_type_name({:__aliases__, _, parts}), do: parts
  defp extract_type_name(atom) when is_atom(atom), do: atom
  defp extract_type_name(other), do: other

  # ===========================================================================
  # Attribute Extraction
  # ===========================================================================

  defp extract_fallback_to_any(body) do
    Enum.any?(body, fn
      {:@, _meta, [{:fallback_to_any, _attr_meta, [true]}]} -> true
      _ -> false
    end)
  end

  defp extract_typedoc(body) do
    Enum.find_value(body, nil, fn
      {:@, _meta, [{:typedoc, _doc_meta, [doc]}]} when is_binary(doc) -> doc
      _ -> nil
    end)
  end

  # ===========================================================================
  # Utility Functions
  # ===========================================================================

  @doc """
  Returns a list of function names defined in the protocol.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> ast = quote do
      ...>   defprotocol MyProtocol do
      ...>     def foo(data)
      ...>     def bar(data, opts)
      ...>   end
      ...> end
      iex> {:ok, proto} = Protocol.extract(ast)
      iex> Protocol.function_names(proto)
      [:foo, :bar]
  """
  @spec function_names(t()) :: [atom()]
  def function_names(%__MODULE__{functions: functions}) do
    Enum.map(functions, & &1.name)
  end

  @doc """
  Returns the function with the given name, or nil if not found.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> ast = quote do
      ...>   defprotocol MyProtocol do
      ...>     def foo(data)
      ...>     def bar(data, opts)
      ...>   end
      ...> end
      iex> {:ok, proto} = Protocol.extract(ast)
      iex> func = Protocol.get_function(proto, :bar)
      iex> func.arity
      2
  """
  @spec get_function(t(), atom()) :: protocol_function() | nil
  def get_function(%__MODULE__{functions: functions}, name) when is_atom(name) do
    Enum.find(functions, fn f -> f.name == name end)
  end

  @doc """
  Checks if the protocol has fallback to any enabled.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> code = "defprotocol P do @fallback_to_any true; def foo(x); end"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, proto} = Protocol.extract(ast)
      iex> Protocol.fallback_to_any?(proto)
      true

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> code = "defprotocol P do def foo(x); end"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, proto} = Protocol.extract(ast)
      iex> Protocol.fallback_to_any?(proto)
      false
  """
  @spec fallback_to_any?(t()) :: boolean()
  def fallback_to_any?(%__MODULE__{fallback_to_any: fallback}), do: fallback

  @doc """
  Returns a list of function names in an implementation.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Protocol
      iex> code = "defimpl P, for: Integer do def foo(x), do: x; def bar(x), do: x end"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, impl} = Protocol.extract_implementation(ast)
      iex> Protocol.implementation_function_names(impl)
      [:foo, :bar]
  """
  @spec implementation_function_names(Implementation.t()) :: [atom()]
  def implementation_function_names(%Implementation{functions: functions}) do
    Enum.map(functions, & &1.name)
  end
end
