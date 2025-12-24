defmodule ElixirOntologies.Extractors.MacroInvocation do
  @moduledoc """
  Extracts macro invocations from AST nodes.

  This module analyzes Elixir AST nodes to detect macro invocations - calls to
  macros from Kernel, standard library, or other modules. It distinguishes
  macro invocations from regular function calls.

  ## Ontology Classes

  From `elixir-structure.ttl`:
  - `MacroInvocation` - Represents a call to a macro
  - `invokesMacro` - Links invocation to macro definition
  - `invokedAt` - Source location of invocation

  ## Macro Categories

  The extractor recognizes several categories of macros:

  - **Definition macros**: `def`, `defp`, `defmacro`, `defmodule`, etc.
  - **Control flow macros**: `if`, `unless`, `case`, `cond`, `with`, `for`, etc.
  - **Import macros**: `import`, `require`, `use`, `alias`
  - **Attribute macro**: `@` for module attributes
  - **Library macros**: `Logger.debug`, `Ecto.Query.from`, etc.
  - **Other macros**: `quote`, `unquote`, `binding`, `var!`, etc.

  ## Custom Macro Support

  In addition to Kernel macros, this module detects:

  - **Qualified calls**: `Logger.debug("msg")`, `Ecto.Query.from(q in Q, ...)`
  - **Known library macros**: Common macros from Logger, Ecto, Phoenix, etc.
  - **Import tracking**: Macros available via `import Module`
  - **Require tracking**: Macros available via `require Module`

  ## Usage

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:if, [], [true, [do: :ok]]}
      iex> {:ok, result} = MacroInvocation.extract(ast)
      iex> result.macro_name
      :if
      iex> result.macro_module
      Kernel

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:def, [], [{:foo, [], []}, [do: :ok]]}
      iex> {:ok, result} = MacroInvocation.extract(ast)
      iex> result.macro_name
      :def
      iex> result.category
      :definition
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of macro invocation extraction.

  - `:macro_module` - Module containing the macro (e.g., Kernel, Logger)
  - `:macro_name` - Macro name as atom
  - `:arity` - Number of arguments
  - `:arguments` - List of argument AST nodes
  - `:category` - Category of macro (:definition, :control_flow, :import, :attribute, :library, :custom, :other)
  - `:resolution_status` - Whether macro module was resolved (:resolved, :unresolved, :kernel)
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          macro_module: module() | nil,
          macro_name: atom(),
          arity: non_neg_integer(),
          arguments: [Macro.t()],
          category: category(),
          resolution_status: resolution_status(),
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @type category ::
          :definition
          | :control_flow
          | :import
          | :attribute
          | :quote
          | :library
          | :custom
          | :other
  @type resolution_status :: :resolved | :unresolved | :kernel

  defstruct [
    :macro_module,
    :macro_name,
    :arity,
    :category,
    resolution_status: :kernel,
    arguments: [],
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Import/Require Tracking Structs
  # ===========================================================================

  @typedoc """
  Represents an import statement with optional filtering.
  """
  @type import_info :: %{
          module: module(),
          only: [{atom(), non_neg_integer()}] | nil,
          except: [{atom(), non_neg_integer()}] | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  @typedoc """
  Represents a require statement.
  """
  @type require_info :: %{
          module: module(),
          as: module() | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  # ===========================================================================
  # Macro Expansion Context
  # ===========================================================================

  defmodule MacroContext do
    @moduledoc """
    Represents the expansion context of a macro invocation.

    Captures information about where and how a macro is being expanded,
    similar to what `__CALLER__` provides at compile time.

    ## Fields

    - `:module` - The module where the macro is being expanded
    - `:file` - The file path where expansion occurs
    - `:line` - The line number of the invocation
    - `:function` - The function context if inside a function `{name, arity}` or `nil`
    - `:aliases` - Aliases in scope `[{alias, module}]`

    ## Usage

        iex> alias ElixirOntologies.Extractors.MacroInvocation.MacroContext
        iex> ctx = MacroContext.new(module: MyModule, file: "lib/my_module.ex", line: 10)
        iex> ctx.module
        MyModule
        iex> ctx.line
        10
    """

    @type t :: %__MODULE__{
            module: module() | nil,
            file: String.t() | nil,
            line: non_neg_integer() | nil,
            function: {atom(), non_neg_integer()} | nil,
            aliases: [{module(), module()}]
          }

    defstruct [
      :module,
      :file,
      :line,
      :function,
      aliases: []
    ]

    @doc """
    Creates a new MacroContext with the given options.

    ## Options

    - `:module` - The module where expansion occurs
    - `:file` - The file path
    - `:line` - The line number
    - `:function` - Function context `{name, arity}`
    - `:aliases` - Aliases in scope

    ## Examples

        iex> alias ElixirOntologies.Extractors.MacroInvocation.MacroContext
        iex> ctx = MacroContext.new(module: MyModule, line: 42)
        iex> ctx.line
        42

        iex> alias ElixirOntologies.Extractors.MacroInvocation.MacroContext
        iex> ctx = MacroContext.new(file: "lib/foo.ex", function: {:bar, 2})
        iex> ctx.function
        {:bar, 2}
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        module: Keyword.get(opts, :module),
        file: Keyword.get(opts, :file),
        line: Keyword.get(opts, :line),
        function: Keyword.get(opts, :function),
        aliases: Keyword.get(opts, :aliases, [])
      }
    end

    @doc """
    Creates a MacroContext from AST metadata.

    Extracts available context information from the AST node's metadata.

    ## Examples

        iex> alias ElixirOntologies.Extractors.MacroInvocation.MacroContext
        iex> ctx = MacroContext.from_meta([line: 10, column: 5, file: "lib/test.ex"])
        iex> ctx.line
        10
        iex> ctx.file
        "lib/test.ex"
    """
    @spec from_meta(keyword()) :: t()
    def from_meta(meta) when is_list(meta) do
      %__MODULE__{
        module: nil,
        file: Keyword.get(meta, :file),
        line: Keyword.get(meta, :line),
        function: nil,
        aliases: []
      }
    end

    @doc """
    Merges context options into an existing MacroContext.

    ## Examples

        iex> alias ElixirOntologies.Extractors.MacroInvocation.MacroContext
        iex> ctx = MacroContext.new(line: 10)
        iex> ctx = MacroContext.merge(ctx, module: MyModule)
        iex> ctx.module
        MyModule
        iex> ctx.line
        10
    """
    @spec merge(t(), keyword()) :: t()
    def merge(%__MODULE__{} = ctx, opts) when is_list(opts) do
      %__MODULE__{
        module: Keyword.get(opts, :module, ctx.module),
        file: Keyword.get(opts, :file, ctx.file),
        line: Keyword.get(opts, :line, ctx.line),
        function: Keyword.get(opts, :function, ctx.function),
        aliases: Keyword.get(opts, :aliases, ctx.aliases)
      }
    end

    @doc """
    Checks if the context has any meaningful information.

    Returns true if at least one field is populated.

    ## Examples

        iex> alias ElixirOntologies.Extractors.MacroInvocation.MacroContext
        iex> MacroContext.populated?(MacroContext.new(line: 10))
        true

        iex> alias ElixirOntologies.Extractors.MacroInvocation.MacroContext
        iex> MacroContext.populated?(MacroContext.new())
        false
    """
    @spec populated?(t()) :: boolean()
    def populated?(%__MODULE__{} = ctx) do
      ctx.module != nil or ctx.file != nil or ctx.line != nil or
        ctx.function != nil or ctx.aliases != []
    end
  end

  @type macro_context :: MacroContext.t()

  # ===========================================================================
  # Macro Classification Constants
  # ===========================================================================

  @definition_macros [
    :def,
    :defp,
    :defmacro,
    :defmacrop,
    :defmodule,
    :defprotocol,
    :defimpl,
    :defstruct,
    :defexception,
    :defdelegate,
    :defguard,
    :defguardp,
    :defoverridable
  ]

  @control_flow_macros [
    :if,
    :unless,
    :case,
    :cond,
    :with,
    :for,
    :try,
    :receive,
    :raise,
    :throw,
    :reraise
  ]

  @import_macros [
    :import,
    :require,
    :use,
    :alias
  ]

  @quote_macros [
    :quote,
    :unquote,
    :unquote_splicing
  ]

  @other_kernel_macros [
    :and,
    :or,
    :not,
    :in,
    :binding,
    :var!,
    :match?,
    :destructure,
    :get_and_update_in,
    :put_in,
    :update_in,
    :get_in,
    :pop_in,
    :sigil_C,
    :sigil_c,
    :sigil_D,
    :sigil_N,
    :sigil_R,
    :sigil_r,
    :sigil_S,
    :sigil_s,
    :sigil_T,
    :sigil_U,
    :sigil_W,
    :sigil_w
  ]

  @all_kernel_macros @definition_macros ++
                       @control_flow_macros ++
                       @import_macros ++
                       @quote_macros ++
                       @other_kernel_macros

  # ===========================================================================
  # Known Library Macros
  # ===========================================================================

  # Logger macros (require Logger)
  @logger_macros [:debug, :info, :notice, :warning, :warn, :error, :critical, :alert, :emergency]

  # Ecto.Query macros
  @ecto_query_macros [
    :from,
    :where,
    :select,
    :join,
    :order_by,
    :group_by,
    :having,
    :limit,
    :offset,
    :preload,
    :distinct,
    :update,
    :exclude,
    :lock,
    :windows,
    :combinations,
    :with_cte,
    :recursive_ctes,
    :subquery,
    :dynamic,
    :fragment,
    :type,
    :field,
    :as,
    :parent_as
  ]

  # Phoenix macros
  @phoenix_macros [
    :get,
    :post,
    :put,
    :patch,
    :delete,
    :options,
    :head,
    :connect,
    :trace,
    :resources,
    :resource,
    :scope,
    :pipe_through,
    :pipeline,
    :forward,
    :live,
    :plug,
    :socket,
    :channel
  ]

  # ExUnit macros
  @exunit_macros [
    :test,
    :describe,
    :setup,
    :setup_all,
    :assert,
    :refute,
    :assert_raise,
    :assert_receive,
    :refute_receive,
    :assert_received,
    :refute_received,
    :flunk,
    :doctest
  ]

  # Map of known library modules to their macros
  @known_library_macros %{
    Logger => @logger_macros,
    Ecto.Query => @ecto_query_macros,
    Phoenix.Router => @phoenix_macros,
    ExUnit.Case => @exunit_macros
  }

  # Flattened list of all known library macro names (for quick lookup)
  @all_known_library_macro_names @logger_macros ++
                                   @ecto_query_macros ++
                                   @phoenix_macros ++
                                   @exunit_macros

  # ===========================================================================
  # Public API - Classification
  # ===========================================================================

  @doc """
  Returns the list of definition macros.

  ## Examples

      iex> :def in ElixirOntologies.Extractors.MacroInvocation.definition_macros()
      true

      iex> :if in ElixirOntologies.Extractors.MacroInvocation.definition_macros()
      false
  """
  @spec definition_macros() :: [atom()]
  def definition_macros, do: @definition_macros

  @doc """
  Returns the list of control flow macros.

  ## Examples

      iex> :if in ElixirOntologies.Extractors.MacroInvocation.control_flow_macros()
      true

      iex> :def in ElixirOntologies.Extractors.MacroInvocation.control_flow_macros()
      false
  """
  @spec control_flow_macros() :: [atom()]
  def control_flow_macros, do: @control_flow_macros

  @doc """
  Returns the list of import/require/use/alias macros.

  ## Examples

      iex> :import in ElixirOntologies.Extractors.MacroInvocation.import_macros()
      true

      iex> :require in ElixirOntologies.Extractors.MacroInvocation.import_macros()
      true
  """
  @spec import_macros() :: [atom()]
  def import_macros, do: @import_macros

  @doc """
  Returns the list of quote-related macros.

  ## Examples

      iex> :quote in ElixirOntologies.Extractors.MacroInvocation.quote_macros()
      true

      iex> :unquote in ElixirOntologies.Extractors.MacroInvocation.quote_macros()
      true
  """
  @spec quote_macros() :: [atom()]
  def quote_macros, do: @quote_macros

  @doc """
  Returns all known Kernel macros.

  ## Examples

      iex> length(ElixirOntologies.Extractors.MacroInvocation.all_kernel_macros()) > 30
      true
  """
  @spec all_kernel_macros() :: [atom()]
  def all_kernel_macros, do: @all_kernel_macros

  @doc """
  Returns the map of known library modules to their macros.

  ## Examples

      iex> macros = ElixirOntologies.Extractors.MacroInvocation.known_library_macros()
      iex> :debug in macros[Logger]
      true
  """
  @spec known_library_macros() :: %{module() => [atom()]}
  def known_library_macros, do: @known_library_macros

  @doc """
  Checks if a macro name is a known library macro.

  ## Examples

      iex> ElixirOntologies.Extractors.MacroInvocation.known_library_macro?(:debug)
      true

      iex> ElixirOntologies.Extractors.MacroInvocation.known_library_macro?(:from)
      true

      iex> ElixirOntologies.Extractors.MacroInvocation.known_library_macro?(:unknown)
      false
  """
  @spec known_library_macro?(atom()) :: boolean()
  def known_library_macro?(name) when is_atom(name), do: name in @all_known_library_macro_names
  def known_library_macro?(_), do: false

  @doc """
  Returns the Logger macros.

  ## Examples

      iex> :debug in ElixirOntologies.Extractors.MacroInvocation.logger_macros()
      true
  """
  @spec logger_macros() :: [atom()]
  def logger_macros, do: @logger_macros

  @doc """
  Returns the Ecto.Query macros.

  ## Examples

      iex> :from in ElixirOntologies.Extractors.MacroInvocation.ecto_query_macros()
      true
  """
  @spec ecto_query_macros() :: [atom()]
  def ecto_query_macros, do: @ecto_query_macros

  # ===========================================================================
  # Macro Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a macro invocation.

  Returns true for known macro calls from Kernel, the `@` attribute operator,
  and qualified calls to known library macros.

  ## Examples

      iex> ElixirOntologies.Extractors.MacroInvocation.macro_invocation?({:if, [], [true, [do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.MacroInvocation.macro_invocation?({:def, [], [{:foo, [], []}, [do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.MacroInvocation.macro_invocation?({:@, [], [{:doc, [], ["test"]}]})
      true

      iex> ElixirOntologies.Extractors.MacroInvocation.macro_invocation?({:some_function, [], [1, 2]})
      false

      iex> ElixirOntologies.Extractors.MacroInvocation.macro_invocation?(nil)
      false
  """
  @spec macro_invocation?(Macro.t()) :: boolean()
  def macro_invocation?({:@, _, _}), do: true
  def macro_invocation?({name, _, _}) when name in @all_kernel_macros, do: true

  # Qualified calls: Module.macro(args) - e.g., Logger.debug("msg")
  def macro_invocation?({{:., _, [_module, _name]}, _, _args}), do: true

  def macro_invocation?(_), do: false

  @doc """
  Checks if an AST node is a qualified macro call (Module.macro form).

  ## Examples

      iex> ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [], ["msg"]}
      iex> ElixirOntologies.Extractors.MacroInvocation.qualified_call?(ast)
      true

      iex> ElixirOntologies.Extractors.MacroInvocation.qualified_call?({:if, [], [true, [do: :ok]]})
      false
  """
  @spec qualified_call?(Macro.t()) :: boolean()
  def qualified_call?({{:., _, [_module, name]}, _, _args}) when is_atom(name), do: true
  def qualified_call?(_), do: false

  @doc """
  Checks if a macro name is a Kernel macro.

  ## Examples

      iex> ElixirOntologies.Extractors.MacroInvocation.kernel_macro?(:def)
      true

      iex> ElixirOntologies.Extractors.MacroInvocation.kernel_macro?(:if)
      true

      iex> ElixirOntologies.Extractors.MacroInvocation.kernel_macro?(:my_macro)
      false
  """
  @spec kernel_macro?(atom()) :: boolean()
  def kernel_macro?(name) when is_atom(name), do: name in @all_kernel_macros
  def kernel_macro?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a macro invocation from an AST node.

  Returns `{:ok, %MacroInvocation{}}` on success, or `{:error, reason}` if
  the node is not a recognized macro invocation.

  ## Examples

      iex> ast = {:if, [line: 1], [true, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> result.macro_name
      :if
      iex> result.macro_module
      Kernel
      iex> result.category
      :control_flow

      iex> ast = {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: {:x, [], nil}]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> result.macro_name
      :def
      iex> result.arity
      2
      iex> result.category
      :definition

      iex> ast = {:@, [line: 5], [{:doc, [], ["Some doc"]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> result.macro_name
      :@
      iex> result.category
      :attribute

      iex> ast = {:my_function, [], [1, 2]}
      iex> ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      {:error, "Not a recognized macro invocation: {:my_function, [], [1, 2]}"}
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  # Handle @ attribute macro
  def extract({:@, _meta, args} = node, opts) when is_list(args) do
    location = Helpers.extract_location_if(node, opts)

    {:ok,
     %__MODULE__{
       macro_module: Kernel,
       macro_name: :@,
       arity: length(args),
       arguments: args,
       category: :attribute,
       resolution_status: :kernel,
       location: location,
       metadata: %{attribute_name: extract_attribute_name(args)}
     }}
  end

  # Handle Kernel macros
  def extract({name, _meta, args} = node, opts) when name in @all_kernel_macros do
    location = Helpers.extract_location_if(node, opts)
    category = categorize_macro(name)
    actual_args = normalize_args(args)

    {:ok,
     %__MODULE__{
       macro_module: Kernel,
       macro_name: name,
       arity: length(actual_args),
       arguments: actual_args,
       category: category,
       resolution_status: :kernel,
       location: location,
       metadata: %{}
     }}
  end

  # Handle qualified macro calls: Module.macro(args)
  def extract({{:., _, [module_ast, name]}, _meta, args} = node, opts)
      when is_atom(name) and is_list(args) do
    location = Helpers.extract_location_if(node, opts)
    module = extract_module(module_ast)
    category = categorize_qualified_macro(module, name)

    {:ok,
     %__MODULE__{
       macro_module: module,
       macro_name: name,
       arity: length(args),
       arguments: args,
       category: category,
       resolution_status: :resolved,
       location: location,
       metadata: %{qualified: true}
     }}
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Not a recognized macro invocation", node)}
  end

  @doc """
  Extracts a macro invocation from an AST node, raising on error.

  ## Examples

      iex> ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:_], :ok]}]]]}
      iex> result = ElixirOntologies.Extractors.MacroInvocation.extract!(ast)
      iex> result.macro_name
      :case
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
  Extracts all macro invocations from a module body.

  Returns a list of extracted macro invocations in the order they appear.
  This performs a shallow extraction - it does not recurse into macro bodies.

  ## Examples

      iex> body = {:__block__, [], [
      ...>   {:def, [], [{:foo, [], []}, [do: :ok]]},
      ...>   {:if, [], [true, [do: :ok]]},
      ...>   {:some_call, [], [1, 2]}
      ...> ]}
      iex> results = ElixirOntologies.Extractors.MacroInvocation.extract_all(body)
      iex> length(results)
      2
      iex> Enum.map(results, & &1.macro_name)
      [:def, :if]
  """
  @spec extract_all(Macro.t(), keyword()) :: [t()]
  def extract_all(body, opts \\ [])

  def extract_all(nil, _opts), do: []

  def extract_all({:__block__, _, statements}, opts) when is_list(statements) do
    statements
    |> Enum.filter(&macro_invocation?/1)
    |> Enum.map(fn node ->
      case extract(node, opts) do
        {:ok, result} -> result
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def extract_all(statement, opts) do
    if macro_invocation?(statement) do
      case extract(statement, opts) do
        {:ok, result} -> [result]
        {:error, _} -> []
      end
    else
      []
    end
  end

  @doc """
  Recursively extracts all macro invocations from an AST tree.

  Unlike `extract_all/2`, this function traverses the entire AST tree to
  find macro invocations at any depth.

  ## Examples

      iex> body = {:def, [], [{:foo, [], []}, [do: {:if, [], [true, [do: :ok]]}]]}
      iex> results = ElixirOntologies.Extractors.MacroInvocation.extract_all_recursive(body)
      iex> length(results)
      2
      iex> Enum.map(results, & &1.macro_name) |> Enum.sort()
      [:def, :if]
  """
  @spec extract_all_recursive(Macro.t(), keyword()) :: [t()]
  def extract_all_recursive(ast, opts \\ []) do
    {_, invocations} =
      Macro.prewalk(ast, [], fn
        node, acc when is_tuple(node) and tuple_size(node) == 3 ->
          if macro_invocation?(node) do
            case extract(node, opts) do
              {:ok, result} -> {node, [result | acc]}
              {:error, _} -> {node, acc}
            end
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(invocations)
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Returns the category of a macro invocation.

  ## Examples

      iex> ast = {:def, [], [{:foo, [], []}, [do: :ok]]}
      iex> {:ok, inv} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> ElixirOntologies.Extractors.MacroInvocation.definition?(inv)
      true

      iex> ast = {:if, [], [true, [do: :ok]]}
      iex> {:ok, inv} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> ElixirOntologies.Extractors.MacroInvocation.definition?(inv)
      false
  """
  @spec definition?(t()) :: boolean()
  def definition?(%__MODULE__{category: :definition}), do: true
  def definition?(_), do: false

  @doc """
  Checks if the invocation is a control flow macro.

  ## Examples

      iex> ast = {:if, [], [true, [do: :ok]]}
      iex> {:ok, inv} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> ElixirOntologies.Extractors.MacroInvocation.control_flow?(inv)
      true
  """
  @spec control_flow?(t()) :: boolean()
  def control_flow?(%__MODULE__{category: :control_flow}), do: true
  def control_flow?(_), do: false

  @doc """
  Checks if the invocation is an import/require/use/alias macro.

  ## Examples

      iex> ast = {:import, [], [{:__aliases__, [], [:Enum]}]}
      iex> {:ok, inv} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> ElixirOntologies.Extractors.MacroInvocation.import?(inv)
      true
  """
  @spec import?(t()) :: boolean()
  def import?(%__MODULE__{category: :import}), do: true
  def import?(_), do: false

  @doc """
  Checks if the invocation is a module attribute.

  ## Examples

      iex> ast = {:@, [], [{:doc, [], ["test"]}]}
      iex> {:ok, inv} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> ElixirOntologies.Extractors.MacroInvocation.attribute?(inv)
      true
  """
  @spec attribute?(t()) :: boolean()
  def attribute?(%__MODULE__{category: :attribute}), do: true
  def attribute?(_), do: false

  @doc """
  Returns a string identifier for the macro invocation.

  ## Examples

      iex> ast = {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: :ok]]}
      iex> {:ok, inv} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> ElixirOntologies.Extractors.MacroInvocation.invocation_id(inv)
      "Kernel.def/2"
  """
  @spec invocation_id(t()) :: String.t()
  def invocation_id(%__MODULE__{macro_module: module, macro_name: name, arity: arity}) do
    module_str = if module, do: "#{inspect(module)}.", else: ""
    "#{module_str}#{name}/#{arity}"
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp categorize_macro(name) when name in @definition_macros, do: :definition
  defp categorize_macro(name) when name in @control_flow_macros, do: :control_flow
  defp categorize_macro(name) when name in @import_macros, do: :import
  defp categorize_macro(name) when name in @quote_macros, do: :quote
  defp categorize_macro(_), do: :other

  defp normalize_args(nil), do: []
  defp normalize_args(args) when is_list(args), do: args
  defp normalize_args(atom) when is_atom(atom), do: []

  defp extract_attribute_name([{attr_name, _, _} | _]) when is_atom(attr_name), do: attr_name
  defp extract_attribute_name(_), do: nil

  # Extract module from AST
  defp extract_module({:__aliases__, _, parts}) when is_list(parts) do
    Module.concat(parts)
  end

  defp extract_module(atom) when is_atom(atom), do: atom
  defp extract_module(_), do: nil

  # Categorize qualified macro calls
  defp categorize_qualified_macro(Logger, name) when name in @logger_macros, do: :library
  defp categorize_qualified_macro(Ecto.Query, name) when name in @ecto_query_macros, do: :library

  defp categorize_qualified_macro(module, name) do
    if known_library_macro_for_module?(module, name) do
      :library
    else
      :custom
    end
  end

  defp known_library_macro_for_module?(module, name) do
    case Map.get(@known_library_macros, module) do
      nil -> false
      macros -> name in macros
    end
  end

  # ===========================================================================
  # Import/Require Extraction
  # ===========================================================================

  @doc """
  Extracts all import statements from a module body.

  Returns a list of import info maps with module, only, except filters.

  ## Examples

      iex> code = "import Enum, only: [map: 2]"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> [import_info] = ElixirOntologies.Extractors.MacroInvocation.extract_imports({:__block__, [], [ast]})
      iex> import_info.module
      Enum
      iex> import_info.only
      [map: 2]
  """
  @spec extract_imports(Macro.t()) :: [import_info()]
  def extract_imports(body) do
    body
    |> Helpers.normalize_body()
    |> Enum.filter(&import_statement?/1)
    |> Enum.map(&extract_single_import/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Extracts all require statements from a module body.

  Returns a list of require info maps with module and optional alias.

  ## Examples

      iex> code = "require Logger"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> [require_info] = ElixirOntologies.Extractors.MacroInvocation.extract_requires({:__block__, [], [ast]})
      iex> require_info.module
      Logger
  """
  @spec extract_requires(Macro.t()) :: [require_info()]
  def extract_requires(body) do
    body
    |> Helpers.normalize_body()
    |> Enum.filter(&require_statement?/1)
    |> Enum.map(&extract_single_require/1)
    |> Enum.reject(&is_nil/1)
  end

  defp import_statement?({:import, _, _}), do: true
  defp import_statement?(_), do: false

  defp require_statement?({:require, _, _}), do: true
  defp require_statement?(_), do: false

  defp extract_single_import({:import, meta, [module_ast]}) do
    %{
      module: extract_module(module_ast),
      only: nil,
      except: nil,
      location: Helpers.extract_location({:import, meta, []})
    }
  end

  defp extract_single_import({:import, meta, [module_ast, opts]}) when is_list(opts) do
    %{
      module: extract_module(module_ast),
      only: Keyword.get(opts, :only),
      except: Keyword.get(opts, :except),
      location: Helpers.extract_location({:import, meta, []})
    }
  end

  defp extract_single_import(_), do: nil

  defp extract_single_require({:require, meta, [module_ast]}) do
    %{
      module: extract_module(module_ast),
      as: nil,
      location: Helpers.extract_location({:require, meta, []})
    }
  end

  defp extract_single_require({:require, meta, [module_ast, opts]}) when is_list(opts) do
    %{
      module: extract_module(module_ast),
      as: Keyword.get(opts, :as) |> extract_module_if_ast(),
      location: Helpers.extract_location({:require, meta, []})
    }
  end

  defp extract_single_require(_), do: nil

  defp extract_module_if_ast(nil), do: nil
  defp extract_module_if_ast({:__aliases__, _, _} = ast), do: extract_module(ast)
  defp extract_module_if_ast(atom) when is_atom(atom), do: atom

  # ===========================================================================
  # Resolution Helpers
  # ===========================================================================

  @doc """
  Checks if a macro invocation is resolved.

  ## Examples

      iex> ast = {:if, [], [true, [do: :ok]]}
      iex> {:ok, inv} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> ElixirOntologies.Extractors.MacroInvocation.resolved?(inv)
      true
  """
  @spec resolved?(t()) :: boolean()
  def resolved?(%__MODULE__{resolution_status: :resolved}), do: true
  def resolved?(%__MODULE__{resolution_status: :kernel}), do: true
  def resolved?(_), do: false

  @doc """
  Checks if a macro invocation is unresolved.

  ## Examples

      iex> inv = %ElixirOntologies.Extractors.MacroInvocation{
      ...>   macro_name: :custom,
      ...>   macro_module: nil,
      ...>   arity: 0,
      ...>   category: :custom,
      ...>   resolution_status: :unresolved
      ...> }
      iex> ElixirOntologies.Extractors.MacroInvocation.unresolved?(inv)
      true
  """
  @spec unresolved?(t()) :: boolean()
  def unresolved?(%__MODULE__{resolution_status: :unresolved}), do: true
  def unresolved?(_), do: false

  @doc """
  Checks if a macro invocation is a qualified call (Module.function form).

  ## Examples

      iex> ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [], ["msg"]}
      iex> {:ok, inv} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> ElixirOntologies.Extractors.MacroInvocation.qualified?(inv)
      true

      iex> ast = {:if, [], [true, [do: :ok]]}
      iex> {:ok, inv} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> ElixirOntologies.Extractors.MacroInvocation.qualified?(inv)
      false
  """
  @spec qualified?(t()) :: boolean()
  def qualified?(%__MODULE__{metadata: %{qualified: true}}), do: true
  def qualified?(_), do: false

  @doc """
  Checks if a macro invocation is a library macro.

  ## Examples

      iex> ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [], ["msg"]}
      iex> {:ok, inv} = ElixirOntologies.Extractors.MacroInvocation.extract(ast)
      iex> ElixirOntologies.Extractors.MacroInvocation.library?(inv)
      true
  """
  @spec library?(t()) :: boolean()
  def library?(%__MODULE__{category: :library}), do: true
  def library?(_), do: false

  @doc """
  Filters a list of invocations to only unresolved ones.

  ## Examples

      iex> invs = [
      ...>   %ElixirOntologies.Extractors.MacroInvocation{macro_name: :if, resolution_status: :kernel, arity: 2, category: :control_flow},
      ...>   %ElixirOntologies.Extractors.MacroInvocation{macro_name: :custom, resolution_status: :unresolved, arity: 0, category: :custom}
      ...> ]
      iex> unresolved = ElixirOntologies.Extractors.MacroInvocation.filter_unresolved(invs)
      iex> length(unresolved)
      1
      iex> hd(unresolved).macro_name
      :custom
  """
  @spec filter_unresolved([t()]) :: [t()]
  def filter_unresolved(invocations) do
    Enum.filter(invocations, &unresolved?/1)
  end

  # ===========================================================================
  # Context-Aware Extraction
  # ===========================================================================

  @doc """
  Extracts a macro invocation with expansion context.

  Accepts context options that are merged with AST metadata to create
  a `MacroContext` that's stored in the invocation's metadata.

  ## Options

  - `:module` - The module where the macro is being expanded
  - `:file` - The file path
  - `:function` - The function context `{name, arity}` if inside a function
  - `:aliases` - Aliases in scope `[{alias, module}]`

  ## Examples

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:if, [line: 10], [true, [do: :ok]]}
      iex> {:ok, inv} = MacroInvocation.extract_with_context(ast, module: MyModule)
      iex> inv.macro_name
      :if
      iex> MacroInvocation.has_context?(inv)
      true
      iex> MacroInvocation.get_context(inv).module
      MyModule
      iex> MacroInvocation.get_context(inv).line
      10

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:def, [line: 5, file: "lib/foo.ex"], [{:bar, [], []}, [do: :ok]]}
      iex> {:ok, inv} = MacroInvocation.extract_with_context(ast, function: {:baz, 2})
      iex> ctx = MacroInvocation.get_context(inv)
      iex> ctx.line
      5
      iex> ctx.file
      "lib/foo.ex"
      iex> ctx.function
      {:baz, 2}
  """
  @spec extract_with_context(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract_with_context(node, context_opts) when is_list(context_opts) do
    case extract(node) do
      {:ok, invocation} ->
        context = build_context(node, context_opts)
        updated = %{invocation | metadata: Map.put(invocation.metadata, :context, context)}
        {:ok, updated}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Extracts a macro invocation with expansion context, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:case, [line: 15], [{:x, [], nil}, [do: [{:->, [], [[:_], :ok]}]]]}
      iex> inv = MacroInvocation.extract_with_context!(ast, module: TestMod)
      iex> MacroInvocation.get_context(inv).module
      TestMod
  """
  @spec extract_with_context!(Macro.t(), keyword()) :: t()
  def extract_with_context!(node, context_opts) do
    case extract_with_context(node, context_opts) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc """
  Recursively extracts all macro invocations with context.

  Similar to `extract_all_recursive/2` but includes context information
  for each invocation.

  ## Examples

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> body = {:def, [line: 1], [{:foo, [], []}, [do: {:if, [line: 2], [true, [do: :ok]]}]]}
      iex> results = MacroInvocation.extract_all_recursive_with_context(body, module: MyMod)
      iex> length(results)
      2
      iex> Enum.all?(results, &MacroInvocation.has_context?/1)
      true
  """
  @spec extract_all_recursive_with_context(Macro.t(), keyword()) :: [t()]
  def extract_all_recursive_with_context(ast, context_opts \\ []) do
    {_, invocations} =
      Macro.prewalk(ast, [], fn
        node, acc when is_tuple(node) and tuple_size(node) == 3 ->
          if macro_invocation?(node) do
            case extract_with_context(node, context_opts) do
              {:ok, result} -> {node, [result | acc]}
              {:error, _} -> {node, acc}
            end
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(invocations)
  end

  # Build context from AST metadata and provided options
  defp build_context({_, meta, _}, opts) when is_list(meta) do
    MacroContext.from_meta(meta)
    |> MacroContext.merge(opts)
  end

  defp build_context(_, opts) do
    MacroContext.new(opts)
  end

  # ===========================================================================
  # Context Helper Functions
  # ===========================================================================

  @doc """
  Checks if a macro invocation has context information.

  ## Examples

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:if, [line: 10], [true, [do: :ok]]}
      iex> {:ok, inv} = MacroInvocation.extract_with_context(ast, module: MyModule)
      iex> MacroInvocation.has_context?(inv)
      true

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:if, [], [true, [do: :ok]]}
      iex> {:ok, inv} = MacroInvocation.extract(ast)
      iex> MacroInvocation.has_context?(inv)
      false
  """
  @spec has_context?(t()) :: boolean()
  def has_context?(%__MODULE__{metadata: %{context: %MacroContext{} = ctx}}) do
    MacroContext.populated?(ctx)
  end

  def has_context?(_), do: false

  @doc """
  Gets the context from a macro invocation.

  Returns `nil` if no context is present.

  ## Examples

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:if, [line: 10], [true, [do: :ok]]}
      iex> {:ok, inv} = MacroInvocation.extract_with_context(ast, module: MyModule)
      iex> ctx = MacroInvocation.get_context(inv)
      iex> ctx.module
      MyModule

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:if, [], [true, [do: :ok]]}
      iex> {:ok, inv} = MacroInvocation.extract(ast)
      iex> MacroInvocation.get_context(inv)
      nil
  """
  @spec get_context(t()) :: MacroContext.t() | nil
  def get_context(%__MODULE__{metadata: %{context: %MacroContext{} = ctx}}), do: ctx
  def get_context(_), do: nil

  @doc """
  Gets the module from the context of a macro invocation.

  Returns `nil` if no context or no module in context.

  ## Examples

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:if, [line: 10], [true, [do: :ok]]}
      iex> {:ok, inv} = MacroInvocation.extract_with_context(ast, module: MyModule)
      iex> MacroInvocation.context_module(inv)
      MyModule

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:if, [], [true, [do: :ok]]}
      iex> {:ok, inv} = MacroInvocation.extract(ast)
      iex> MacroInvocation.context_module(inv)
      nil
  """
  @spec context_module(t()) :: module() | nil
  def context_module(%__MODULE__{metadata: %{context: %MacroContext{module: module}}}), do: module
  def context_module(_), do: nil

  @doc """
  Gets the file path from the context of a macro invocation.

  Returns `nil` if no context or no file in context.

  ## Examples

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:if, [line: 10, file: "lib/test.ex"], [true, [do: :ok]]}
      iex> {:ok, inv} = MacroInvocation.extract_with_context(ast, [])
      iex> MacroInvocation.context_file(inv)
      "lib/test.ex"
  """
  @spec context_file(t()) :: String.t() | nil
  def context_file(%__MODULE__{metadata: %{context: %MacroContext{file: file}}}), do: file
  def context_file(_), do: nil

  @doc """
  Gets the line number from the context of a macro invocation.

  Returns `nil` if no context or no line in context.

  ## Examples

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:if, [line: 42], [true, [do: :ok]]}
      iex> {:ok, inv} = MacroInvocation.extract_with_context(ast, [])
      iex> MacroInvocation.context_line(inv)
      42
  """
  @spec context_line(t()) :: non_neg_integer() | nil
  def context_line(%__MODULE__{metadata: %{context: %MacroContext{line: line}}}), do: line
  def context_line(_), do: nil

  @doc """
  Gets the function context from a macro invocation.

  Returns `nil` if no context or not inside a function.

  ## Examples

      iex> alias ElixirOntologies.Extractors.MacroInvocation
      iex> ast = {:if, [line: 10], [true, [do: :ok]]}
      iex> {:ok, inv} = MacroInvocation.extract_with_context(ast, function: {:my_func, 2})
      iex> MacroInvocation.context_function(inv)
      {:my_func, 2}
  """
  @spec context_function(t()) :: {atom(), non_neg_integer()} | nil
  def context_function(%__MODULE__{metadata: %{context: %MacroContext{function: func}}}), do: func
  def context_function(_), do: nil
end
