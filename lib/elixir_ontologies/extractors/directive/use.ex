defmodule ElixirOntologies.Extractors.Directive.Use do
  @moduledoc """
  Extracts use directive information from Elixir AST.

  This module provides detailed extraction of use directives which invoke
  the `__using__/1` macro of a module, allowing modules to inject code at compile time.

  ## Architecture Note

  This extractor is designed for composable, on-demand directive analysis. It is
  intentionally **not** automatically invoked by the main Pipeline module. This
  separation allows:

  - Lightweight module extraction when directive details aren't needed
  - Targeted directive analysis when building dependency graphs
  - Flexibility to use extractors individually or in combination

  To extract directives during module analysis, either:
  1. Call this extractor directly on directive AST nodes
  2. Use Module.extract/2 with the :extract_directives option (when available)

  ## Use Forms

  Elixir supports several use forms:

      # Basic use - invokes GenServer.__using__([])
      use GenServer

      # Use with keyword options - passed to __using__/1
      use GenServer, restart: :temporary

      # Use with multiple keyword options
      use Plug.Builder, init_mode: :runtime, log_on_halt: :debug

      # Use with non-keyword option (common in Phoenix)
      use MyApp.Web, :controller

  ## Examples

      iex> ast = {:use, [line: 1], [{:__aliases__, [line: 1], [:GenServer]}]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Use.extract(ast)
      iex> directive.module
      [:GenServer]
      iex> directive.options
      nil

      iex> ast = {:use, [line: 1], [{:__aliases__, [line: 1], [:GenServer]}, [restart: :temporary]]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Use.extract(ast)
      iex> directive.options
      [restart: :temporary]
  """

  alias ElixirOntologies.Extractors.Helpers
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # ===========================================================================
  # Struct Definition
  # ===========================================================================

  defmodule UseDirective do
    @moduledoc """
    Represents an extracted use directive.

    ## Fields

    - `:module` - The module being used as a list of atoms
    - `:options` - Options passed to `__using__/1` (keyword list, single value, or nil)
    - `:location` - Source location of the directive
    - `:scope` - Lexical scope (:module, :function, :block)
    - `:metadata` - Additional metadata
    """

    @type use_options :: keyword() | term() | nil

    @type t :: %__MODULE__{
            module: [atom()] | atom(),
            options: use_options(),
            location: SourceLocation.t() | nil,
            scope: :module | :function | :block | nil,
            metadata: map()
          }

    @enforce_keys [:module]
    defstruct [:module, :options, :location, :scope, metadata: %{}]
  end

  defmodule UseOption do
    @moduledoc """
    Represents an analyzed use option.

    ## Fields

    - `:key` - The option key (atom)
    - `:value` - The extracted value (literal or AST for dynamic)
    - `:value_type` - Type classification of the value
    - `:dynamic` - Whether the value is dynamic (not resolvable at analysis time)
    - `:source_kind` - The source of the value: `:literal`, `:variable`, `:function_call`,
      `:module_attribute`, or `:other`
    - `:raw_ast` - The original AST for the value (useful for dynamic values)
    """

    @type value_type ::
            :atom
            | :string
            | :integer
            | :float
            | :boolean
            | nil
            | :list
            | :tuple
            | :module
            | :dynamic

    @type source_kind :: :literal | :variable | :function_call | :module_attribute | :other

    @type t :: %__MODULE__{
            key: atom() | nil,
            value: term(),
            value_type: value_type(),
            dynamic: boolean(),
            source_kind: source_kind(),
            raw_ast: Macro.t() | nil
          }

    defstruct [:key, :value, :value_type, :raw_ast, dynamic: false, source_kind: :literal]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if the given AST node represents a use directive.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Use.use?({:use, [], [{:__aliases__, [], [:GenServer]}]})
      true

      iex> ElixirOntologies.Extractors.Directive.Use.use?({:require, [], [{:__aliases__, [], [:Logger]}]})
      false

      iex> ElixirOntologies.Extractors.Directive.Use.use?(:not_a_use)
      false
  """
  @spec use?(Macro.t()) :: boolean()
  def use?({:use, _meta, [_ | _]}), do: true
  def use?(_), do: false

  # ===========================================================================
  # Extraction Functions
  # ===========================================================================

  @doc """
  Extracts use directive information from an AST node.

  Returns `{:ok, %UseDirective{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:use, [line: 5], [{:__aliases__, [line: 5], [:GenServer]}]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Use.extract(ast)
      iex> directive.module
      [:GenServer]
      iex> directive.options
      nil

      iex> ast = {:use, [], [{:__aliases__, [], [:GenServer]}, [restart: :temporary]]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Use.extract(ast)
      iex> directive.options
      [restart: :temporary]

      iex> ast = {:use, [], [{:__aliases__, [], [:MyApp, :Web]}, :controller]}
      iex> {:ok, directive} = ElixirOntologies.Extractors.Directive.Use.extract(ast)
      iex> directive.options
      :controller
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, UseDirective.t()} | {:error, term()}
  def extract(ast, opts \\ [])

  # Basic use: use Module
  def extract({:use, _meta, [{:__aliases__, _, parts}]} = node, opts)
      when is_list(parts) do
    build_directive(parts, nil, node, opts)
  end

  # Use with options: use Module, options
  def extract({:use, _meta, [{:__aliases__, _, parts}, use_opts]} = node, opts)
      when is_list(parts) do
    build_directive(parts, use_opts, node, opts)
  end

  # Erlang module: use :module (rare but possible)
  def extract({:use, _meta, [module]} = node, opts) when is_atom(module) do
    build_directive([module], nil, node, opts)
  end

  # Erlang module with options
  def extract({:use, _meta, [module, use_opts]} = node, opts)
      when is_atom(module) do
    build_directive([module], use_opts, node, opts)
  end

  def extract(ast, _opts) do
    {:error, {:not_a_use, Helpers.format_error("Not a use directive", ast)}}
  end

  @doc """
  Extracts use directive information, raising on error.

  ## Examples

      iex> ast = {:use, [], [{:__aliases__, [], [:GenServer]}]}
      iex> directive = ElixirOntologies.Extractors.Directive.Use.extract!(ast)
      iex> directive.module
      [:GenServer]
  """
  @spec extract!(Macro.t(), keyword()) :: UseDirective.t()
  def extract!(ast, opts \\ []) do
    case extract(ast, opts) do
      {:ok, directive} -> directive
      {:error, reason} -> raise ArgumentError, "Failed to extract use: #{inspect(reason)}"
    end
  end

  @doc """
  Extracts all use directives from a module body or list of statements.

  ## Examples

      iex> body = [
      ...>   {:use, [], [{:__aliases__, [], [:GenServer]}]},
      ...>   {:use, [], [{:__aliases__, [], [:Supervisor]}]},
      ...>   {:def, [], [{:foo, [], nil}, [do: :ok]]}
      ...> ]
      iex> directives = ElixirOntologies.Extractors.Directive.Use.extract_all(body)
      iex> length(directives)
      2
      iex> Enum.map(directives, & &1.module)
      [[:GenServer], [:Supervisor]]
  """
  @spec extract_all(Macro.t(), keyword()) :: [UseDirective.t()]
  def extract_all(ast, opts \\ [])

  def extract_all(statements, opts) when is_list(statements) do
    statements
    |> Enum.filter(&use?/1)
    |> Enum.flat_map(&do_extract_all(&1, opts))
  end

  def extract_all({:__block__, _meta, statements}, opts) do
    extract_all(statements, opts)
  end

  def extract_all(ast, opts) do
    if use?(ast) do
      do_extract_all(ast, opts)
    else
      []
    end
  end

  # ===========================================================================
  # Scope-Aware Extraction
  # ===========================================================================

  @doc """
  Extracts all use directives from a module body with scope tracking.

  This function walks the AST and tracks the lexical scope of each use,
  setting the `:scope` field to `:module`, `:function`, or `:block`.

  Note: `use` is typically only valid at module level, but this function
  tracks scope for completeness.

  ## Examples

      iex> {:defmodule, _, [_, [do: {:__block__, _, body}]]} = quote do
      ...>   defmodule Test do
      ...>     use GenServer
      ...>     use Supervisor
      ...>   end
      ...> end
      iex> directives = ElixirOntologies.Extractors.Directive.Use.extract_all_with_scope(body)
      iex> length(directives)
      2
      iex> Enum.all?(directives, & &1.scope == :module)
      true
  """
  @spec extract_all_with_scope(Macro.t(), keyword()) :: [UseDirective.t()]
  def extract_all_with_scope(ast, opts \\ []) do
    extract_with_scope(ast, :module, opts)
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Returns the used module as a dot-separated string.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{
      ...>   module: [:GenServer]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Use.module_name(directive)
      "GenServer"

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{
      ...>   module: [:Plug, :Builder]
      ...> }
      iex> ElixirOntologies.Extractors.Directive.Use.module_name(directive)
      "Plug.Builder"
  """
  @spec module_name(UseDirective.t()) :: String.t()
  def module_name(%UseDirective{module: module}) do
    case module do
      [single] when is_atom(single) ->
        Atom.to_string(single)

      parts when is_list(parts) ->
        Enum.map_join(parts, ".", &Atom.to_string/1)
    end
  end

  @doc """
  Checks if the use directive has options.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{module: [:GenServer]}
      iex> ElixirOntologies.Extractors.Directive.Use.has_options?(directive)
      false

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{module: [:GenServer], options: [restart: :temporary]}
      iex> ElixirOntologies.Extractors.Directive.Use.has_options?(directive)
      true

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{module: [:MyApp, :Web], options: :controller}
      iex> ElixirOntologies.Extractors.Directive.Use.has_options?(directive)
      true
  """
  @spec has_options?(UseDirective.t()) :: boolean()
  def has_options?(%UseDirective{options: nil}), do: false
  def has_options?(%UseDirective{options: []}), do: false
  def has_options?(%UseDirective{}), do: true

  @doc """
  Checks if the use directive has keyword options.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{module: [:GenServer], options: [restart: :temporary]}
      iex> ElixirOntologies.Extractors.Directive.Use.keyword_options?(directive)
      true

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{module: [:MyApp, :Web], options: :controller}
      iex> ElixirOntologies.Extractors.Directive.Use.keyword_options?(directive)
      false
  """
  @spec keyword_options?(UseDirective.t()) :: boolean()
  def keyword_options?(%UseDirective{options: opts}) when is_list(opts) and opts != [],
    do: Keyword.keyword?(opts)

  def keyword_options?(%UseDirective{}), do: false

  # ===========================================================================
  # Option Analysis
  # ===========================================================================

  @doc """
  Analyzes the options from a UseDirective into structured UseOption structs.

  For keyword options, each key-value pair becomes a UseOption.
  For non-keyword options (single value), returns a single UseOption with key=nil.

  ## Examples

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{
      ...>   module: [:GenServer],
      ...>   options: [restart: :temporary, max_restarts: 3]
      ...> }
      iex> options = ElixirOntologies.Extractors.Directive.Use.analyze_options(directive)
      iex> length(options)
      2
      iex> [first, second] = options
      iex> first.key
      :restart
      iex> first.value
      :temporary
      iex> second.key
      :max_restarts
      iex> second.value
      3

      iex> directive = %ElixirOntologies.Extractors.Directive.Use.UseDirective{
      ...>   module: [:MyApp, :Web],
      ...>   options: :controller
      ...> }
      iex> [option] = ElixirOntologies.Extractors.Directive.Use.analyze_options(directive)
      iex> option.key
      nil
      iex> option.value
      :controller
  """
  @spec analyze_options(UseDirective.t()) :: [UseOption.t()]
  def analyze_options(%UseDirective{options: nil}), do: []
  def analyze_options(%UseDirective{options: []}), do: []

  def analyze_options(%UseDirective{options: opts}) when is_list(opts) do
    if Keyword.keyword?(opts) do
      Enum.map(opts, &parse_option/1)
    else
      # Non-keyword list, treat as single value
      [analyze_value(nil, opts)]
    end
  end

  def analyze_options(%UseDirective{options: value}) do
    [analyze_value(nil, value)]
  end

  @doc """
  Parses a single keyword option tuple into a UseOption struct.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Use.parse_option({:restart, :temporary})
      %ElixirOntologies.Extractors.Directive.Use.UseOption{
        key: :restart,
        value: :temporary,
        value_type: :atom,
        dynamic: false,
        source_kind: :literal,
        raw_ast: nil
      }

      iex> ElixirOntologies.Extractors.Directive.Use.parse_option({:count, 5})
      %ElixirOntologies.Extractors.Directive.Use.UseOption{
        key: :count,
        value: 5,
        value_type: :integer,
        dynamic: false,
        source_kind: :literal,
        raw_ast: nil
      }
  """
  @spec parse_option({atom(), term()}) :: UseOption.t()
  def parse_option({key, value}) when is_atom(key) do
    analyze_value(key, value)
  end

  @doc """
  Checks if an AST value is dynamic (not resolvable at analysis time).

  Dynamic values include:
  - Variable references
  - Function calls
  - Macro calls
  - Any AST tuple that isn't a literal structure

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Use.dynamic_value?(:atom)
      false

      iex> ElixirOntologies.Extractors.Directive.Use.dynamic_value?(42)
      false

      iex> ElixirOntologies.Extractors.Directive.Use.dynamic_value?({:some_var, [], Elixir})
      true

      iex> ElixirOntologies.Extractors.Directive.Use.dynamic_value?({{:., [], [{:__aliases__, [], [:String]}, :to_atom]}, [], ["temp"]})
      true
  """
  @spec dynamic_value?(term()) :: boolean()
  # Literals are not dynamic
  def dynamic_value?(value) when is_atom(value), do: false
  def dynamic_value?(value) when is_binary(value), do: false
  def dynamic_value?(value) when is_integer(value), do: false
  def dynamic_value?(value) when is_float(value), do: false
  def dynamic_value?(value) when is_boolean(value), do: false

  # Module reference is not dynamic
  def dynamic_value?({:__aliases__, _, parts}) when is_list(parts), do: false

  # List - check if any element is dynamic
  def dynamic_value?(value) when is_list(value) do
    Enum.any?(value, &dynamic_value?/1)
  end

  # Two-element tuple that looks like a keyword pair
  def dynamic_value?({key, val}) when is_atom(key), do: dynamic_value?(val)

  # Two-element tuple that's a literal pair
  def dynamic_value?({a, b}), do: dynamic_value?(a) or dynamic_value?(b)

  # Function call - dynamic
  def dynamic_value?({{:., _, _}, _, _}), do: true

  # Variable reference - dynamic (3-tuple with atom name and context)
  def dynamic_value?({name, meta, context})
      when is_atom(name) and is_list(meta) and is_atom(context),
      do: true

  # Other 3-tuples might be AST nodes - check recursively
  def dynamic_value?({_, _, args}) when is_list(args), do: true

  # Fallback for anything else
  def dynamic_value?(_), do: false

  @doc """
  Determines the type classification of a value.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Use.value_type(:atom)
      :atom

      iex> ElixirOntologies.Extractors.Directive.Use.value_type("string")
      :string

      iex> ElixirOntologies.Extractors.Directive.Use.value_type(42)
      :integer

      iex> ElixirOntologies.Extractors.Directive.Use.value_type(3.14)
      :float

      iex> ElixirOntologies.Extractors.Directive.Use.value_type(true)
      :boolean

      iex> ElixirOntologies.Extractors.Directive.Use.value_type(nil)
      :nil

      iex> ElixirOntologies.Extractors.Directive.Use.value_type([:a, :b])
      :list

      iex> ElixirOntologies.Extractors.Directive.Use.value_type({:a, :b})
      :tuple

      iex> ElixirOntologies.Extractors.Directive.Use.value_type({:__aliases__, [], [:MyApp, :Web]})
      :module

      iex> ElixirOntologies.Extractors.Directive.Use.value_type({:some_var, [], Elixir})
      :dynamic
  """
  @spec value_type(term()) :: UseOption.value_type()
  def value_type(nil), do: nil
  def value_type(value) when is_boolean(value), do: :boolean
  def value_type(value) when is_atom(value), do: :atom
  def value_type(value) when is_binary(value), do: :string
  def value_type(value) when is_integer(value), do: :integer
  def value_type(value) when is_float(value), do: :float
  def value_type(value) when is_list(value), do: :list
  def value_type({:__aliases__, _, parts}) when is_list(parts), do: :module

  def value_type({a, b}) when not is_list(a) and not is_list(b) do
    if dynamic_value?({a, b}), do: :dynamic, else: :tuple
  end

  def value_type(value) when is_tuple(value) do
    if dynamic_value?(value), do: :dynamic, else: :tuple
  end

  def value_type(_), do: :dynamic

  @doc """
  Extracts the literal value from an AST node if possible.

  Returns `{:ok, value}` for literal values that can be extracted,
  or `{:dynamic, ast}` for values that cannot be resolved at analysis time.

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Use.extract_literal_value(:temporary)
      {:ok, :temporary}

      iex> ElixirOntologies.Extractors.Directive.Use.extract_literal_value(42)
      {:ok, 42}

      iex> ElixirOntologies.Extractors.Directive.Use.extract_literal_value({:__aliases__, [], [:MyApp, :Web]})
      {:ok, [:MyApp, :Web]}

      iex> ElixirOntologies.Extractors.Directive.Use.extract_literal_value({:some_var, [], Elixir})
      {:dynamic, {:some_var, [], Elixir}}
  """
  @spec extract_literal_value(term()) :: {:ok, term()} | {:dynamic, Macro.t()}
  def extract_literal_value(nil), do: {:ok, nil}
  def extract_literal_value(value) when is_atom(value), do: {:ok, value}
  def extract_literal_value(value) when is_binary(value), do: {:ok, value}
  def extract_literal_value(value) when is_integer(value), do: {:ok, value}
  def extract_literal_value(value) when is_float(value), do: {:ok, value}
  def extract_literal_value(value) when is_boolean(value), do: {:ok, value}

  def extract_literal_value({:__aliases__, _, parts}) when is_list(parts) do
    {:ok, parts}
  end

  def extract_literal_value(value) when is_list(value) do
    if dynamic_value?(value) do
      {:dynamic, value}
    else
      extracted =
        Enum.map(value, fn
          {k, v} when is_atom(k) ->
            case extract_literal_value(v) do
              {:ok, val} -> {k, val}
              {:dynamic, _} -> {k, v}
            end

          item ->
            case extract_literal_value(item) do
              {:ok, val} -> val
              {:dynamic, _} -> item
            end
        end)

      {:ok, extracted}
    end
  end

  def extract_literal_value({a, b}) do
    if dynamic_value?({a, b}) do
      {:dynamic, {a, b}}
    else
      case {extract_literal_value(a), extract_literal_value(b)} do
        {{:ok, va}, {:ok, vb}} -> {:ok, {va, vb}}
        _ -> {:dynamic, {a, b}}
      end
    end
  end

  def extract_literal_value(value) when is_tuple(value) do
    if dynamic_value?(value) do
      {:dynamic, value}
    else
      # Convert tuple to list, extract, convert back
      list = Tuple.to_list(value)

      case extract_literal_value(list) do
        {:ok, extracted} -> {:ok, List.to_tuple(extracted)}
        {:dynamic, _} -> {:dynamic, value}
      end
    end
  end

  def extract_literal_value(value), do: {:dynamic, value}

  @doc """
  Determines the source kind of a value (where it comes from).

  ## Source Kinds

  - `:literal` - A literal value (atom, string, integer, list of literals, etc.)
  - `:variable` - A variable reference
  - `:function_call` - A function or macro call
  - `:module_attribute` - A module attribute reference (@something)
  - `:other` - Unknown or unclassifiable source

  ## Examples

      iex> ElixirOntologies.Extractors.Directive.Use.source_kind(:temporary)
      :literal

      iex> ElixirOntologies.Extractors.Directive.Use.source_kind(42)
      :literal

      iex> ElixirOntologies.Extractors.Directive.Use.source_kind({:some_var, [], Elixir})
      :variable

      iex> ElixirOntologies.Extractors.Directive.Use.source_kind({:@, [], [{:config, [], nil}]})
      :module_attribute
  """
  @spec source_kind(term()) :: UseOption.source_kind()
  # Literals
  def source_kind(value) when is_atom(value), do: :literal
  def source_kind(value) when is_binary(value), do: :literal
  def source_kind(value) when is_integer(value), do: :literal
  def source_kind(value) when is_float(value), do: :literal
  def source_kind(value) when is_boolean(value), do: :literal

  # Module reference is a literal
  def source_kind({:__aliases__, _, parts}) when is_list(parts), do: :literal

  # Module attribute: @foo
  def source_kind({:@, _, [{_name, _, _}]}), do: :module_attribute

  # Function call (remote): Module.func(...)
  def source_kind({{:., _, _}, _, _}), do: :function_call

  # Variable reference: 3-tuple with atom name and atom context
  def source_kind({name, meta, context})
      when is_atom(name) and is_list(meta) and is_atom(context) do
    # Could be a variable or a function call (if it has args)
    # Check if name looks like a variable (lowercase first char, no parens in most cases)
    cond do
      # Common macro/function calls
      name in [:if, :unless, :case, :cond, :with, :for, :try, :receive, :quote, :unquote] ->
        :function_call

      # Looks like a variable (lowercase, no args list in context)
      context == Elixir or context == nil ->
        :variable

      true ->
        :other
    end
  end

  # Other 3-tuples are typically function calls or macro calls
  def source_kind({_name, _meta, args}) when is_list(args), do: :function_call

  # List - check if all elements are literals
  def source_kind(value) when is_list(value) do
    if Enum.all?(value, &(source_kind(&1) == :literal)) do
      :literal
    else
      :other
    end
  end

  # Two-element tuple - check if literal
  def source_kind({a, b}) do
    if source_kind(a) == :literal and source_kind(b) == :literal do
      :literal
    else
      :other
    end
  end

  def source_kind(_), do: :other

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp analyze_value(key, value) do
    is_dynamic = dynamic_value?(value)
    vtype = value_type(value)
    skind = source_kind(value)

    {extracted_value, raw} =
      case extract_literal_value(value) do
        {:ok, v} -> {v, nil}
        {:dynamic, ast} -> {ast, ast}
      end

    %UseOption{
      key: key,
      value: extracted_value,
      value_type: vtype,
      dynamic: is_dynamic,
      source_kind: skind,
      raw_ast: raw
    }
  end

  defp build_directive(module_parts, use_opts, node, opts) do
    location = Helpers.extract_location_if(node, opts)

    {:ok,
     %UseDirective{
       module: module_parts,
       options: use_opts,
       location: location,
       metadata: %{}
     }}
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

  # Extract uses with scope tracking
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

  # Handle use - extract with current scope
  defp extract_with_scope({:use, _meta, _args} = ast, current_scope, opts) do
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
