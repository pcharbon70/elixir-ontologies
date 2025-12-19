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
  - **Other macros**: `quote`, `unquote`, `binding`, `var!`, etc.

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
  - `:category` - Category of macro (:definition, :control_flow, :import, :attribute, :other)
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          macro_module: module() | nil,
          macro_name: atom(),
          arity: non_neg_integer(),
          arguments: [Macro.t()],
          category: category(),
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @type category :: :definition | :control_flow | :import | :attribute | :quote | :other

  defstruct [
    :macro_module,
    :macro_name,
    :arity,
    :category,
    arguments: [],
    location: nil,
    metadata: %{}
  ]

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

  # ===========================================================================
  # Macro Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a macro invocation.

  Returns true for known macro calls from Kernel and for the `@` attribute
  operator.

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
  def macro_invocation?(_), do: false

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
       location: location,
       metadata: %{}
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
end
