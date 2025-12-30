defmodule ElixirOntologies.Extractors.Function do
  @moduledoc """
  Extracts function definitions from AST nodes.

  This module analyzes Elixir AST nodes representing function definitions and
  extracts their name, arity, visibility, type classification, and associated
  metadata. Supports the function-related classes from elixir-structure.ttl:

  - Function: Base class with `functionName`, `arity`
  - PublicFunction: `def` functions
  - PrivateFunction: `defp` functions
  - GuardFunction: `defguard`/`defguardp` functions
  - DelegatedFunction: `defdelegate` with `delegatesTo`

  ## Usage

      iex> alias ElixirOntologies.Extractors.Function
      iex> ast = quote do
      ...>   def hello(name), do: "Hello, \#{name}"
      ...> end
      iex> {:ok, result} = Function.extract(ast)
      iex> result.name
      :hello
      iex> result.arity
      1
      iex> result.visibility
      :public

      iex> alias ElixirOntologies.Extractors.Function
      iex> ast = {:def, [], [{:greet, [], nil}, [do: :ok]]}
      iex> {:ok, result} = Function.extract(ast)
      iex> result.name
      :greet
      iex> result.arity
      0
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of function extraction.

  - `:type` - Function type (:function, :guard, :delegate)
  - `:name` - Function name as atom
  - `:arity` - Total number of parameters
  - `:min_arity` - Minimum arity (considering default args)
  - `:visibility` - :public or :private
  - `:docstring` - Documentation from @doc (string, false, or nil)
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          type: :function | :guard | :delegate,
          name: atom(),
          arity: non_neg_integer(),
          min_arity: non_neg_integer(),
          visibility: :public | :private,
          docstring: String.t() | false | nil,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct [
    :type,
    :name,
    :arity,
    :min_arity,
    :visibility,
    :docstring,
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Function Definition Types
  # ===========================================================================

  @public_functions [:def]
  @private_functions [:defp]
  @public_guards [:defguard]
  @private_guards [:defguardp]
  @delegates [:defdelegate]

  @all_function_types @public_functions ++
                        @private_functions ++
                        @public_guards ++
                        @private_guards ++
                        @delegates

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a function definition.

  Recognizes def, defp, defguard, defguardp, and defdelegate.

  ## Examples

      iex> ElixirOntologies.Extractors.Function.function?({:def, [], [{:foo, [], nil}, [do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.Function.function?({:defp, [], [{:bar, [], nil}]})
      true

      iex> ElixirOntologies.Extractors.Function.function?({:defguard, [], [{:is_valid, [], [{:x, [], nil}]}]})
      true

      iex> ElixirOntologies.Extractors.Function.function?({:defdelegate, [], [{:foo, [], nil}, [to: SomeModule]]})
      true

      iex> ElixirOntologies.Extractors.Function.function?({:defmodule, [], [{:Foo, [], nil}]})
      false

      iex> ElixirOntologies.Extractors.Function.function?(:not_a_function)
      false
  """
  @spec function?(Macro.t()) :: boolean()
  def function?({type, _meta, _args}) when type in @all_function_types, do: true
  def function?(_), do: false

  @doc """
  Checks if an AST node represents a guard definition.

  ## Examples

      iex> ElixirOntologies.Extractors.Function.guard?({:defguard, [], [{:is_valid, [], [{:x, [], nil}]}]})
      true

      iex> ElixirOntologies.Extractors.Function.guard?({:defguardp, [], [{:is_ok, [], [{:x, [], nil}]}]})
      true

      iex> ElixirOntologies.Extractors.Function.guard?({:def, [], [{:foo, [], nil}]})
      false
  """
  @spec guard?(Macro.t()) :: boolean()
  def guard?({type, _meta, _args}) when type in @public_guards or type in @private_guards,
    do: true

  def guard?(_), do: false

  @doc """
  Checks if an AST node represents a delegated function.

  ## Examples

      iex> ElixirOntologies.Extractors.Function.delegate?({:defdelegate, [], [{:foo, [], nil}, [to: SomeModule]]})
      true

      iex> ElixirOntologies.Extractors.Function.delegate?({:def, [], [{:foo, [], nil}]})
      false
  """
  @spec delegate?(Macro.t()) :: boolean()
  def delegate?({type, _meta, _args}) when type in @delegates, do: true
  def delegate?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a function definition from an AST node.

  Returns `{:ok, %Function{}}` on success, or `{:error, reason}` if the node
  is not a function definition.

  ## Options

  - `:module` - Module name (list of atoms) for context
  - `:doc` - Documentation string from preceding @doc
  - `:spec` - Spec AST from associated @spec

  ## Examples

      iex> ast = {:def, [], [{:hello, [], [{:name, [], nil}]}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Function.extract(ast)
      iex> result.name
      :hello
      iex> result.arity
      1
      iex> result.visibility
      :public

      iex> ast = {:defp, [], [{:internal, [], nil}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Function.extract(ast)
      iex> result.visibility
      :private

      iex> ast = {:defguard, [], [{:when, [], [{:is_valid, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Function.extract(ast)
      iex> result.type
      :guard
      iex> result.name
      :is_valid

      iex> {:error, _} = ElixirOntologies.Extractors.Function.extract({:defmodule, [], []})
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  # Regular function with guard: def foo(x) when is_integer(x), do: x
  def extract({type, meta, [{:when, _, [{name, _, args}, _guard]}, _body]} = node, opts)
      when is_atom(name) and (type in @public_functions or type in @private_functions) do
    extract_regular_function(type, meta, name, args, node, opts, true)
  end

  # Regular function: def foo(x), do: x
  def extract({type, meta, [{name, _, args}, _body]} = node, opts)
      when is_atom(name) and (type in @public_functions or type in @private_functions) do
    extract_regular_function(type, meta, name, args, node, opts, false)
  end

  # Bodyless function with guard: def foo(x) when is_atom(x)
  # NOTE: This must come before the regular bodyless pattern to match :when correctly
  def extract({type, meta, [{:when, _, [{name, _, args}, _guard]}]} = node, opts)
      when is_atom(name) and (type in @public_functions or type in @private_functions) do
    extract_regular_function(type, meta, name, args, node, opts, true)
  end

  # Bodyless function (typically in protocols): def foo(x)
  def extract({type, meta, [{name, _, args}]} = node, opts)
      when is_atom(name) and (type in @public_functions or type in @private_functions) do
    extract_regular_function(type, meta, name, args, node, opts, false)
  end

  # Guard function: defguard is_valid(x) when x > 0
  def extract({type, meta, [{:when, _, [{name, _, args}, guard_expr]}]} = node, opts)
      when is_atom(name) and (type in @public_guards or type in @private_guards) do
    extract_guard_function(type, meta, name, args, guard_expr, node, opts)
  end

  # Guard function without when (unusual but valid): defguard is_ok(x)
  def extract({type, meta, [{name, _, args}]} = node, opts)
      when is_atom(name) and (type in @public_guards or type in @private_guards) do
    extract_guard_function(type, meta, name, args, nil, node, opts)
  end

  # Delegated function: defdelegate foo(x), to: Module
  def extract({:defdelegate, meta, [{name, _, args}, delegate_opts]} = node, opts)
      when is_atom(name) do
    extract_delegate_function(meta, name, args, delegate_opts, node, opts)
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Not a function definition", node)}
  end

  @doc """
  Extracts a function definition from an AST node, raising on error.

  ## Examples

      iex> ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      iex> result = ElixirOntologies.Extractors.Function.extract!(ast)
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
  # Helper Functions
  # ===========================================================================

  @doc """
  Generates a function identifier string.

  ## Examples

      iex> ast = {:def, [], [{:hello, [], [{:x, [], nil}]}, [do: :ok]]}
      iex> {:ok, func} = ElixirOntologies.Extractors.Function.extract(ast)
      iex> ElixirOntologies.Extractors.Function.function_id(func)
      "hello/1"

      iex> ast = {:def, [], [{:greet, [], nil}, [do: :ok]]}
      iex> {:ok, func} = ElixirOntologies.Extractors.Function.extract(ast)
      iex> ElixirOntologies.Extractors.Function.function_id(func)
      "greet/0"
  """
  @spec function_id(t()) :: String.t()
  def function_id(%__MODULE__{name: name, arity: arity}) do
    "#{name}/#{arity}"
  end

  @doc """
  Generates a fully qualified function identifier with module.

  ## Examples

      iex> ast = {:def, [], [{:hello, [], [{:x, [], nil}]}, [do: :ok]]}
      iex> {:ok, func} = ElixirOntologies.Extractors.Function.extract(ast, module: [:MyApp, :Greeter])
      iex> ElixirOntologies.Extractors.Function.qualified_id(func)
      "MyApp.Greeter.hello/1"

      iex> ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      iex> {:ok, func} = ElixirOntologies.Extractors.Function.extract(ast)
      iex> ElixirOntologies.Extractors.Function.qualified_id(func)
      "foo/0"
  """
  @spec qualified_id(t()) :: String.t()
  def qualified_id(%__MODULE__{name: name, arity: arity, metadata: %{module: module}})
      when is_list(module) and module != [] do
    module_str = Enum.join(module, ".")
    "#{module_str}.#{name}/#{arity}"
  end

  def qualified_id(%__MODULE__{} = func), do: function_id(func)

  @doc """
  Returns true if the function has hidden documentation (@doc false).

  ## Examples

      iex> ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      iex> {:ok, func} = ElixirOntologies.Extractors.Function.extract(ast, doc: false)
      iex> ElixirOntologies.Extractors.Function.doc_hidden?(func)
      true

      iex> ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      iex> {:ok, func} = ElixirOntologies.Extractors.Function.extract(ast, doc: "Some docs")
      iex> ElixirOntologies.Extractors.Function.doc_hidden?(func)
      false
  """
  @spec doc_hidden?(t()) :: boolean()
  def doc_hidden?(%__MODULE__{docstring: false}), do: true
  def doc_hidden?(%__MODULE__{metadata: %{doc_hidden: true}}), do: true
  def doc_hidden?(_), do: false

  @doc """
  Returns true if the function has default parameters.

  ## Examples

      iex> ast = quote do
      ...>   def greet(name \\\\ "World"), do: name
      ...> end
      iex> {:ok, func} = ElixirOntologies.Extractors.Function.extract(ast)
      iex> ElixirOntologies.Extractors.Function.has_defaults?(func)
      true

      iex> ast = {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: :ok]]}
      iex> {:ok, func} = ElixirOntologies.Extractors.Function.extract(ast)
      iex> ElixirOntologies.Extractors.Function.has_defaults?(func)
      false
  """
  @spec has_defaults?(t()) :: boolean()
  def has_defaults?(%__MODULE__{arity: arity, min_arity: min_arity}), do: min_arity < arity

  @doc """
  Returns the delegate target if this is a delegated function.

  ## Examples

      iex> ast = {:defdelegate, [], [{:foo, [], [{:x, [], nil}]}, [to: SomeModule]]}
      iex> {:ok, func} = ElixirOntologies.Extractors.Function.extract(ast)
      iex> ElixirOntologies.Extractors.Function.delegate_target(func)
      {SomeModule, :foo, 1}

      iex> ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      iex> {:ok, func} = ElixirOntologies.Extractors.Function.extract(ast)
      iex> ElixirOntologies.Extractors.Function.delegate_target(func)
      nil
  """
  @spec delegate_target(t()) :: {module(), atom(), non_neg_integer()} | nil
  def delegate_target(%__MODULE__{type: :delegate, metadata: %{delegates_to: target}}), do: target
  def delegate_target(_), do: nil

  # ===========================================================================
  # Private Helpers - Regular Functions
  # ===========================================================================

  defp extract_regular_function(type, meta, name, args, node, opts, has_guard) do
    {arity, min_arity, default_count} = calculate_arities(args)
    visibility = if type in @public_functions, do: :public, else: :private
    location = Helpers.extract_location(node)
    doc = Keyword.get(opts, :doc)
    spec = Keyword.get(opts, :spec)
    module = Keyword.get(opts, :module)

    {:ok,
     %__MODULE__{
       type: :function,
       name: name,
       arity: arity,
       min_arity: min_arity,
       visibility: visibility,
       docstring: extract_docstring(doc),
       location: location,
       metadata: %{
         module: module,
         doc_hidden: doc == false,
         spec: spec,
         has_guard: has_guard,
         default_args: default_count,
         line: Keyword.get(meta, :line)
       }
     }}
  end

  # ===========================================================================
  # Private Helpers - Guard Functions
  # ===========================================================================

  defp extract_guard_function(type, meta, name, args, guard_expr, node, opts) do
    {arity, min_arity, default_count} = calculate_arities(args)
    visibility = if type in @public_guards, do: :public, else: :private
    location = Helpers.extract_location(node)
    doc = Keyword.get(opts, :doc)
    module = Keyword.get(opts, :module)

    {:ok,
     %__MODULE__{
       type: :guard,
       name: name,
       arity: arity,
       min_arity: min_arity,
       visibility: visibility,
       docstring: extract_docstring(doc),
       location: location,
       metadata: %{
         module: module,
         doc_hidden: doc == false,
         guard_expression: guard_expr,
         default_args: default_count,
         line: Keyword.get(meta, :line)
       }
     }}
  end

  # ===========================================================================
  # Private Helpers - Delegate Functions
  # ===========================================================================

  defp extract_delegate_function(meta, name, args, delegate_opts, node, opts) do
    {arity, min_arity, default_count} = calculate_arities(args)
    location = Helpers.extract_location(node)
    doc = Keyword.get(opts, :doc)
    module = Keyword.get(opts, :module)

    target_module = extract_delegate_module(delegate_opts)
    target_function = Keyword.get(delegate_opts, :as, name)
    delegates_to = if target_module, do: {target_module, target_function, arity}, else: nil

    {:ok,
     %__MODULE__{
       type: :delegate,
       name: name,
       arity: arity,
       min_arity: min_arity,
       visibility: :public,
       docstring: extract_docstring(doc),
       location: location,
       metadata: %{
         module: module,
         doc_hidden: doc == false,
         delegates_to: delegates_to,
         default_args: default_count,
         line: Keyword.get(meta, :line)
       }
     }}
  end

  defp extract_delegate_module(delegate_opts) do
    case Keyword.get(delegate_opts, :to) do
      {:__aliases__, _, parts} -> Module.concat(parts)
      module when is_atom(module) -> module
      _ -> nil
    end
  end

  # ===========================================================================
  # Private Helpers - Arity Calculation
  # ===========================================================================

  defp calculate_arities(nil), do: {0, 0, 0}
  defp calculate_arities(args) when not is_list(args), do: {0, 0, 0}

  defp calculate_arities(args) when is_list(args) do
    arity = length(args)
    default_count = count_defaults(args)
    min_arity = arity - default_count
    {arity, min_arity, default_count}
  end

  defp count_defaults(args) do
    Enum.count(args, fn
      {:\\, _, _} -> true
      _ -> false
    end)
  end

  # ===========================================================================
  # Private Helpers - Documentation
  # ===========================================================================

  defp extract_docstring(nil), do: nil
  defp extract_docstring(false), do: false
  defp extract_docstring(doc) when is_binary(doc), do: doc
  defp extract_docstring(_), do: nil
end
