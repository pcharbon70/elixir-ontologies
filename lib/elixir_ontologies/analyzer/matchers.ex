defmodule ElixirOntologies.Analyzer.Matchers do
  @moduledoc """
  Pattern matchers for identifying specific AST node types.

  This module provides predicate functions for detecting various Elixir
  constructs in AST nodes. These matchers are designed to work with
  `ASTWalker.find_all/2` for collecting specific node types.

  ## Usage

      alias ElixirOntologies.Analyzer.{ASTWalker, Matchers}

      # Find all function definitions
      functions = ASTWalker.find_all(ast, &Matchers.function?/1)

      # Find all module attributes
      attrs = ASTWalker.find_all(ast, &Matchers.attribute?/1)

      # Combine matchers
      defs = ASTWalker.find_all(ast, fn node ->
        Matchers.function?(node) or Matchers.macro?(node)
      end)

  ## Categories

  The matchers are organized into categories:

  - **Definitions**: module?, function?, macro?, protocol?, implementation?
  - **Attributes**: behaviour?, struct?, type?, spec?, callback?, doc?, attribute?
  - **Dependencies**: use?, import?, alias?, require?
  """

  # ============================================================================
  # Module Definitions
  # ============================================================================

  @doc """
  Returns `true` if the node is a `defmodule` definition.

  ## Examples

      iex> ast = quote(do: defmodule(Foo, do: nil))
      iex> Matchers.module?(ast)
      true

      iex> Matchers.module?({:def, [], []})
      false

  """
  @spec module?(Macro.t()) :: boolean()
  def module?({:defmodule, _meta, _args}), do: true
  def module?(_), do: false

  # ============================================================================
  # Function Definitions
  # ============================================================================

  @doc """
  Returns `true` if the node is a function definition (`def` or `defp`).

  ## Examples

      iex> ast = quote(do: def(foo, do: :ok))
      iex> Matchers.function?(ast)
      true

      iex> ast = quote(do: defp(bar, do: :ok))
      iex> Matchers.function?(ast)
      true

      iex> Matchers.function?({:defmodule, [], []})
      false

  """
  @spec function?(Macro.t()) :: boolean()
  def function?({:def, _meta, _args}), do: true
  def function?({:defp, _meta, _args}), do: true
  def function?(_), do: false

  @doc """
  Returns `true` if the node is a public function definition (`def`).

  ## Examples

      iex> ast = quote(do: def(foo, do: :ok))
      iex> Matchers.public_function?(ast)
      true

      iex> ast = quote(do: defp(bar, do: :ok))
      iex> Matchers.public_function?(ast)
      false

  """
  @spec public_function?(Macro.t()) :: boolean()
  def public_function?({:def, _meta, _args}), do: true
  def public_function?(_), do: false

  @doc """
  Returns `true` if the node is a private function definition (`defp`).

  ## Examples

      iex> ast = quote(do: defp(foo, do: :ok))
      iex> Matchers.private_function?(ast)
      true

      iex> ast = quote(do: def(bar, do: :ok))
      iex> Matchers.private_function?(ast)
      false

  """
  @spec private_function?(Macro.t()) :: boolean()
  def private_function?({:defp, _meta, _args}), do: true
  def private_function?(_), do: false

  # ============================================================================
  # Macro Definitions
  # ============================================================================

  @doc """
  Returns `true` if the node is a macro definition (`defmacro` or `defmacrop`).

  ## Examples

      iex> ast = quote(do: defmacro(foo, do: :ok))
      iex> Matchers.macro?(ast)
      true

      iex> ast = quote(do: defmacrop(bar, do: :ok))
      iex> Matchers.macro?(ast)
      true

      iex> Matchers.macro?({:def, [], []})
      false

  """
  @spec macro?(Macro.t()) :: boolean()
  def macro?({:defmacro, _meta, _args}), do: true
  def macro?({:defmacrop, _meta, _args}), do: true
  def macro?(_), do: false

  @doc """
  Returns `true` if the node is a public macro definition (`defmacro`).

  ## Examples

      iex> ast = quote(do: defmacro(foo, do: :ok))
      iex> Matchers.public_macro?(ast)
      true

      iex> ast = quote(do: defmacrop(bar, do: :ok))
      iex> Matchers.public_macro?(ast)
      false

  """
  @spec public_macro?(Macro.t()) :: boolean()
  def public_macro?({:defmacro, _meta, _args}), do: true
  def public_macro?(_), do: false

  @doc """
  Returns `true` if the node is a private macro definition (`defmacrop`).

  ## Examples

      iex> ast = quote(do: defmacrop(foo, do: :ok))
      iex> Matchers.private_macro?(ast)
      true

      iex> ast = quote(do: defmacro(bar, do: :ok))
      iex> Matchers.private_macro?(ast)
      false

  """
  @spec private_macro?(Macro.t()) :: boolean()
  def private_macro?({:defmacrop, _meta, _args}), do: true
  def private_macro?(_), do: false

  # ============================================================================
  # Protocol Definitions
  # ============================================================================

  @doc """
  Returns `true` if the node is a protocol definition (`defprotocol`).

  ## Examples

      iex> ast = quote(do: defprotocol(MyProtocol, do: nil))
      iex> Matchers.protocol?(ast)
      true

      iex> Matchers.protocol?({:defmodule, [], []})
      false

  """
  @spec protocol?(Macro.t()) :: boolean()
  def protocol?({:defprotocol, _meta, _args}), do: true
  def protocol?(_), do: false

  @doc """
  Returns `true` if the node is a protocol implementation (`defimpl`).

  ## Examples

      iex> ast = quote(do: defimpl(MyProtocol, for: MyStruct, do: nil))
      iex> Matchers.implementation?(ast)
      true

      iex> Matchers.implementation?({:defmodule, [], []})
      false

  """
  @spec implementation?(Macro.t()) :: boolean()
  def implementation?({:defimpl, _meta, _args}), do: true
  def implementation?(_), do: false

  # ============================================================================
  # Module Attributes
  # ============================================================================

  @doc """
  Returns `true` if the node is any module attribute (`@attr`).

  ## Examples

      iex> ast = quote(do: @moduledoc("docs"))
      iex> Matchers.attribute?(ast)
      true

      iex> ast = quote(do: @custom_attr(:value))
      iex> Matchers.attribute?(ast)
      true

      iex> Matchers.attribute?({:def, [], []})
      false

  """
  @spec attribute?(Macro.t()) :: boolean()
  def attribute?({:@, _meta, [{_name, _attr_meta, _args}]}), do: true
  def attribute?(_), do: false

  @doc """
  Returns `true` if the node is a `@behaviour` declaration.

  ## Examples

      iex> ast = quote(do: @behaviour(GenServer))
      iex> Matchers.behaviour?(ast)
      true

      iex> ast = quote(do: @doc("docs"))
      iex> Matchers.behaviour?(ast)
      false

  """
  @spec behaviour?(Macro.t()) :: boolean()
  def behaviour?({:@, _meta, [{:behaviour, _attr_meta, _args}]}), do: true
  def behaviour?(_), do: false

  @doc """
  Returns `true` if the node is a `defstruct` definition.

  ## Examples

      iex> ast = quote(do: defstruct([:field1, :field2]))
      iex> Matchers.struct?(ast)
      true

      iex> ast = quote(do: defstruct(field1: nil, field2: nil))
      iex> Matchers.struct?(ast)
      true

      iex> Matchers.struct?({:def, [], []})
      false

  """
  @spec struct?(Macro.t()) :: boolean()
  def struct?({:defstruct, _meta, _args}), do: true
  def struct?(_), do: false

  # ============================================================================
  # Type Specifications
  # ============================================================================

  @doc """
  Returns `true` if the node is a type definition (`@type`, `@typep`, `@opaque`).

  ## Examples

      iex> ast = quote(do: @type(t :: term()))
      iex> Matchers.type?(ast)
      true

      iex> ast = quote(do: @typep(internal :: atom()))
      iex> Matchers.type?(ast)
      true

      iex> ast = quote(do: @opaque(hidden :: term()))
      iex> Matchers.type?(ast)
      true

      iex> ast = quote(do: @spec(foo() :: :ok))
      iex> Matchers.type?(ast)
      false

  """
  @spec type?(Macro.t()) :: boolean()
  def type?({:@, _meta, [{:type, _attr_meta, _args}]}), do: true
  def type?({:@, _meta, [{:typep, _attr_meta, _args}]}), do: true
  def type?({:@, _meta, [{:opaque, _attr_meta, _args}]}), do: true
  def type?(_), do: false

  @doc """
  Returns `true` if the node is a function spec (`@spec`).

  ## Examples

      iex> ast = quote(do: @spec(foo() :: :ok))
      iex> Matchers.spec?(ast)
      true

      iex> ast = quote(do: @type(t :: term()))
      iex> Matchers.spec?(ast)
      false

  """
  @spec spec?(Macro.t()) :: boolean()
  def spec?({:@, _meta, [{:spec, _attr_meta, _args}]}), do: true
  def spec?(_), do: false

  @doc """
  Returns `true` if the node is a callback definition (`@callback` or `@macrocallback`).

  ## Examples

      iex> ast = quote(do: @callback(init(term()) :: {:ok, term()}))
      iex> Matchers.callback?(ast)
      true

      iex> ast = quote(do: @macrocallback(my_macro(term()) :: Macro.t()))
      iex> Matchers.callback?(ast)
      true

      iex> ast = quote(do: @spec(foo() :: :ok))
      iex> Matchers.callback?(ast)
      false

  """
  @spec callback?(Macro.t()) :: boolean()
  def callback?({:@, _meta, [{:callback, _attr_meta, _args}]}), do: true
  def callback?({:@, _meta, [{:macrocallback, _attr_meta, _args}]}), do: true
  def callback?(_), do: false

  @doc """
  Returns `true` if the node is any type specification (`@type`, `@typep`, `@opaque`, `@spec`, `@callback`, `@macrocallback`).

  ## Examples

      iex> ast = quote(do: @spec(foo() :: :ok))
      iex> Matchers.type_spec?(ast)
      true

      iex> ast = quote(do: @type(t :: term()))
      iex> Matchers.type_spec?(ast)
      true

      iex> ast = quote(do: @callback(init(term()) :: {:ok, term()}))
      iex> Matchers.type_spec?(ast)
      true

      iex> ast = quote(do: @doc("docs"))
      iex> Matchers.type_spec?(ast)
      false

  """
  @spec type_spec?(Macro.t()) :: boolean()
  def type_spec?(node) do
    type?(node) or spec?(node) or callback?(node)
  end

  # ============================================================================
  # Documentation Attributes
  # ============================================================================

  @doc """
  Returns `true` if the node is a documentation attribute (`@doc`, `@moduledoc`, `@typedoc`).

  ## Examples

      iex> ast = quote(do: @doc("Function docs"))
      iex> Matchers.doc?(ast)
      true

      iex> ast = quote(do: @moduledoc("Module docs"))
      iex> Matchers.doc?(ast)
      true

      iex> ast = quote(do: @typedoc("Type docs"))
      iex> Matchers.doc?(ast)
      true

      iex> ast = quote(do: @spec(foo() :: :ok))
      iex> Matchers.doc?(ast)
      false

  """
  @spec doc?(Macro.t()) :: boolean()
  def doc?({:@, _meta, [{:doc, _attr_meta, _args}]}), do: true
  def doc?({:@, _meta, [{:moduledoc, _attr_meta, _args}]}), do: true
  def doc?({:@, _meta, [{:typedoc, _attr_meta, _args}]}), do: true
  def doc?(_), do: false

  # ============================================================================
  # Dependencies
  # ============================================================================

  @doc """
  Returns `true` if the node is a `use` declaration.

  ## Examples

      iex> ast = quote(do: use(GenServer))
      iex> Matchers.use?(ast)
      true

      iex> ast = quote(do: use(GenServer, restart: :temporary))
      iex> Matchers.use?(ast)
      true

      iex> Matchers.use?({:import, [], []})
      false

  """
  @spec use?(Macro.t()) :: boolean()
  def use?({:use, _meta, _args}), do: true
  def use?(_), do: false

  @doc """
  Returns `true` if the node is an `import` declaration.

  ## Examples

      iex> ast = quote(do: import(Enum))
      iex> Matchers.import?(ast)
      true

      iex> ast = quote(do: import(Enum, only: [map: 2]))
      iex> Matchers.import?(ast)
      true

      iex> Matchers.import?({:use, [], []})
      false

  """
  @spec import?(Macro.t()) :: boolean()
  def import?({:import, _meta, _args}), do: true
  def import?(_), do: false

  @doc """
  Returns `true` if the node is an `alias` declaration.

  ## Examples

      iex> ast = quote(do: alias(MyApp.MyModule))
      iex> Matchers.alias?(ast)
      true

      iex> ast = quote(do: alias(MyApp.MyModule, as: MM))
      iex> Matchers.alias?(ast)
      true

      iex> Matchers.alias?({:use, [], []})
      false

  """
  @spec alias?(Macro.t()) :: boolean()
  def alias?({:alias, _meta, _args}), do: true
  def alias?(_), do: false

  @doc """
  Returns `true` if the node is a `require` declaration.

  ## Examples

      iex> ast = quote(do: require(Logger))
      iex> Matchers.require?(ast)
      true

      iex> Matchers.require?({:use, [], []})
      false

  """
  @spec require?(Macro.t()) :: boolean()
  def require?({:require, _meta, _args}), do: true
  def require?(_), do: false

  @doc """
  Returns `true` if the node is any dependency declaration (`use`, `import`, `alias`, `require`).

  ## Examples

      iex> ast = quote(do: use(GenServer))
      iex> Matchers.dependency?(ast)
      true

      iex> ast = quote(do: import(Enum))
      iex> Matchers.dependency?(ast)
      true

      iex> Matchers.dependency?({:def, [], []})
      false

  """
  @spec dependency?(Macro.t()) :: boolean()
  def dependency?(node) do
    use?(node) or import?(node) or alias?(node) or require?(node)
  end

  # ============================================================================
  # Guards and Delegates
  # ============================================================================

  @doc """
  Returns `true` if the node is a `defguard` or `defguardp` definition.

  ## Examples

      iex> ast = quote(do: defguard(is_even(n), do: rem(n, 2) == 0))
      iex> Matchers.guard?(ast)
      true

      iex> ast = quote(do: defguardp(is_odd(n), do: rem(n, 2) == 1))
      iex> Matchers.guard?(ast)
      true

      iex> Matchers.guard?({:def, [], []})
      false

  """
  @spec guard?(Macro.t()) :: boolean()
  def guard?({:defguard, _meta, _args}), do: true
  def guard?({:defguardp, _meta, _args}), do: true
  def guard?(_), do: false

  @doc """
  Returns `true` if the node is a `defdelegate` definition.

  ## Examples

      iex> ast = quote(do: defdelegate(foo(x), to: Other))
      iex> Matchers.delegate?(ast)
      true

      iex> Matchers.delegate?({:def, [], []})
      false

  """
  @spec delegate?(Macro.t()) :: boolean()
  def delegate?({:defdelegate, _meta, _args}), do: true
  def delegate?(_), do: false

  @doc """
  Returns `true` if the node is an exception definition (`defexception`).

  ## Examples

      iex> ast = quote(do: defexception([:message]))
      iex> Matchers.exception?(ast)
      true

      iex> Matchers.exception?({:defstruct, [], []})
      false

  """
  @spec exception?(Macro.t()) :: boolean()
  def exception?({:defexception, _meta, _args}), do: true
  def exception?(_), do: false

  # ============================================================================
  # Composite Matchers
  # ============================================================================

  @doc """
  Returns `true` if the node is any kind of definition (module, function, macro, protocol, etc.).

  ## Examples

      iex> ast = quote(do: defmodule(Foo, do: nil))
      iex> Matchers.definition?(ast)
      true

      iex> ast = quote(do: def(foo, do: :ok))
      iex> Matchers.definition?(ast)
      true

      iex> ast = quote(do: @doc("docs"))
      iex> Matchers.definition?(ast)
      false

  """
  @spec definition?(Macro.t()) :: boolean()
  def definition?(node) do
    module?(node) or function?(node) or macro?(node) or protocol?(node) or
      implementation?(node) or struct?(node) or guard?(node) or delegate?(node) or
      exception?(node)
  end
end
