defmodule ElixirOntologies.Analyzer.MatchersTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.Matchers

  # ============================================================================
  # module?/1 Tests
  # ============================================================================

  describe "module?/1" do
    test "returns true for defmodule" do
      ast = quote(do: defmodule(Foo, do: nil))
      assert Matchers.module?(ast)
    end

    test "returns true for defmodule with body" do
      ast =
        quote do
          defmodule Foo do
            def bar, do: :ok
          end
        end

      assert Matchers.module?(ast)
    end

    test "returns false for def" do
      ast = quote(do: def(foo, do: :ok))
      refute Matchers.module?(ast)
    end

    test "returns false for non-AST" do
      refute Matchers.module?(:atom)
      refute Matchers.module?("string")
      refute Matchers.module?(123)
    end
  end

  # ============================================================================
  # function?/1 Tests
  # ============================================================================

  describe "function?/1" do
    test "returns true for def" do
      ast = quote(do: def(foo, do: :ok))
      assert Matchers.function?(ast)
    end

    test "returns true for defp" do
      ast = quote(do: defp(foo, do: :ok))
      assert Matchers.function?(ast)
    end

    test "returns true for def with args" do
      ast = quote(do: def(foo(x, y), do: x + y))
      assert Matchers.function?(ast)
    end

    test "returns true for multi-clause function" do
      ast = quote(do: def(foo(1), do: :one))
      assert Matchers.function?(ast)
    end

    test "returns false for defmacro" do
      ast = quote(do: defmacro(foo, do: :ok))
      refute Matchers.function?(ast)
    end

    test "returns false for defmodule" do
      ast = quote(do: defmodule(Foo, do: nil))
      refute Matchers.function?(ast)
    end
  end

  describe "public_function?/1" do
    test "returns true for def" do
      ast = quote(do: def(foo, do: :ok))
      assert Matchers.public_function?(ast)
    end

    test "returns false for defp" do
      ast = quote(do: defp(foo, do: :ok))
      refute Matchers.public_function?(ast)
    end
  end

  describe "private_function?/1" do
    test "returns true for defp" do
      ast = quote(do: defp(foo, do: :ok))
      assert Matchers.private_function?(ast)
    end

    test "returns false for def" do
      ast = quote(do: def(foo, do: :ok))
      refute Matchers.private_function?(ast)
    end
  end

  # ============================================================================
  # macro?/1 Tests
  # ============================================================================

  describe "macro?/1" do
    test "returns true for defmacro" do
      ast = quote(do: defmacro(foo, do: :ok))
      assert Matchers.macro?(ast)
    end

    test "returns true for defmacrop" do
      ast = quote(do: defmacrop(foo, do: :ok))
      assert Matchers.macro?(ast)
    end

    test "returns false for def" do
      ast = quote(do: def(foo, do: :ok))
      refute Matchers.macro?(ast)
    end
  end

  describe "public_macro?/1" do
    test "returns true for defmacro" do
      ast = quote(do: defmacro(foo, do: :ok))
      assert Matchers.public_macro?(ast)
    end

    test "returns false for defmacrop" do
      ast = quote(do: defmacrop(foo, do: :ok))
      refute Matchers.public_macro?(ast)
    end
  end

  describe "private_macro?/1" do
    test "returns true for defmacrop" do
      ast = quote(do: defmacrop(foo, do: :ok))
      assert Matchers.private_macro?(ast)
    end

    test "returns false for defmacro" do
      ast = quote(do: defmacro(foo, do: :ok))
      refute Matchers.private_macro?(ast)
    end
  end

  # ============================================================================
  # protocol?/1 Tests
  # ============================================================================

  describe "protocol?/1" do
    test "returns true for defprotocol" do
      ast = quote(do: defprotocol(MyProtocol, do: nil))
      assert Matchers.protocol?(ast)
    end

    test "returns false for defmodule" do
      ast = quote(do: defmodule(Foo, do: nil))
      refute Matchers.protocol?(ast)
    end
  end

  describe "implementation?/1" do
    test "returns true for defimpl" do
      ast = quote(do: defimpl(MyProtocol, for: MyStruct, do: nil))
      assert Matchers.implementation?(ast)
    end

    test "returns false for defmodule" do
      ast = quote(do: defmodule(Foo, do: nil))
      refute Matchers.implementation?(ast)
    end
  end

  # ============================================================================
  # attribute?/1 Tests
  # ============================================================================

  describe "attribute?/1" do
    test "returns true for @moduledoc" do
      ast = quote(do: @moduledoc("docs"))
      assert Matchers.attribute?(ast)
    end

    test "returns true for @doc" do
      ast = quote(do: @doc("docs"))
      assert Matchers.attribute?(ast)
    end

    test "returns true for custom attribute" do
      ast = quote(do: @custom_attr(:value))
      assert Matchers.attribute?(ast)
    end

    test "returns false for def" do
      ast = quote(do: def(foo, do: :ok))
      refute Matchers.attribute?(ast)
    end
  end

  # ============================================================================
  # behaviour?/1 Tests
  # ============================================================================

  describe "behaviour?/1" do
    test "returns true for @behaviour" do
      ast = quote(do: @behaviour(GenServer))
      assert Matchers.behaviour?(ast)
    end

    test "returns false for @doc" do
      ast = quote(do: @doc("docs"))
      refute Matchers.behaviour?(ast)
    end

    test "returns false for def" do
      ast = quote(do: def(foo, do: :ok))
      refute Matchers.behaviour?(ast)
    end
  end

  # ============================================================================
  # struct?/1 Tests
  # ============================================================================

  describe "struct?/1" do
    test "returns true for defstruct with list" do
      ast = quote(do: defstruct([:field1, :field2]))
      assert Matchers.struct?(ast)
    end

    test "returns true for defstruct with keyword" do
      ast = quote(do: defstruct(field1: nil, field2: nil))
      assert Matchers.struct?(ast)
    end

    test "returns false for def" do
      ast = quote(do: def(foo, do: :ok))
      refute Matchers.struct?(ast)
    end
  end

  # ============================================================================
  # Type Specification Tests
  # ============================================================================

  describe "type?/1" do
    test "returns true for @type" do
      ast = quote(do: @type(t :: term()))
      assert Matchers.type?(ast)
    end

    test "returns true for @typep" do
      ast = quote(do: @typep(internal :: atom()))
      assert Matchers.type?(ast)
    end

    test "returns true for @opaque" do
      ast = quote(do: @opaque(hidden :: term()))
      assert Matchers.type?(ast)
    end

    test "returns false for @spec" do
      ast = quote(do: @spec(foo() :: :ok))
      refute Matchers.type?(ast)
    end
  end

  describe "spec?/1" do
    test "returns true for @spec" do
      ast = quote(do: @spec(foo() :: :ok))
      assert Matchers.spec?(ast)
    end

    test "returns true for @spec with args" do
      ast = quote(do: @spec(foo(integer(), string()) :: :ok))
      assert Matchers.spec?(ast)
    end

    test "returns false for @type" do
      ast = quote(do: @type(t :: term()))
      refute Matchers.spec?(ast)
    end
  end

  describe "callback?/1" do
    test "returns true for @callback" do
      ast = quote(do: @callback(init(term()) :: {:ok, term()}))
      assert Matchers.callback?(ast)
    end

    test "returns true for @macrocallback" do
      ast = quote(do: @macrocallback(my_macro(term()) :: Macro.t()))
      assert Matchers.callback?(ast)
    end

    test "returns false for @spec" do
      ast = quote(do: @spec(foo() :: :ok))
      refute Matchers.callback?(ast)
    end
  end

  describe "type_spec?/1" do
    test "returns true for @type" do
      ast = quote(do: @type(t :: term()))
      assert Matchers.type_spec?(ast)
    end

    test "returns true for @spec" do
      ast = quote(do: @spec(foo() :: :ok))
      assert Matchers.type_spec?(ast)
    end

    test "returns true for @callback" do
      ast = quote(do: @callback(init(term()) :: {:ok, term()}))
      assert Matchers.type_spec?(ast)
    end

    test "returns false for @doc" do
      ast = quote(do: @doc("docs"))
      refute Matchers.type_spec?(ast)
    end
  end

  # ============================================================================
  # doc?/1 Tests
  # ============================================================================

  describe "doc?/1" do
    test "returns true for @doc" do
      ast = quote(do: @doc("Function docs"))
      assert Matchers.doc?(ast)
    end

    test "returns true for @moduledoc" do
      ast = quote(do: @moduledoc("Module docs"))
      assert Matchers.doc?(ast)
    end

    test "returns true for @typedoc" do
      ast = quote(do: @typedoc("Type docs"))
      assert Matchers.doc?(ast)
    end

    test "returns true for @doc false" do
      ast = quote(do: @doc(false))
      assert Matchers.doc?(ast)
    end

    test "returns false for @spec" do
      ast = quote(do: @spec(foo() :: :ok))
      refute Matchers.doc?(ast)
    end
  end

  # ============================================================================
  # Dependency Tests
  # ============================================================================

  describe "use?/1" do
    test "returns true for use" do
      ast = quote(do: use(GenServer))
      assert Matchers.use?(ast)
    end

    test "returns true for use with opts" do
      ast = quote(do: use(GenServer, restart: :temporary))
      assert Matchers.use?(ast)
    end

    test "returns false for import" do
      ast = quote(do: import(Enum))
      refute Matchers.use?(ast)
    end
  end

  describe "import?/1" do
    test "returns true for import" do
      ast = quote(do: import(Enum))
      assert Matchers.import?(ast)
    end

    test "returns true for import with only" do
      ast = quote(do: import(Enum, only: [map: 2]))
      assert Matchers.import?(ast)
    end

    test "returns false for use" do
      ast = quote(do: use(GenServer))
      refute Matchers.import?(ast)
    end
  end

  describe "alias?/1" do
    test "returns true for alias" do
      ast = quote(do: alias(MyApp.MyModule))
      assert Matchers.alias?(ast)
    end

    test "returns true for alias with as" do
      ast = quote(do: alias(MyApp.MyModule, as: MM))
      assert Matchers.alias?(ast)
    end

    test "returns false for import" do
      ast = quote(do: import(Enum))
      refute Matchers.alias?(ast)
    end
  end

  describe "require?/1" do
    test "returns true for require" do
      ast = quote(do: require(Logger))
      assert Matchers.require?(ast)
    end

    test "returns false for import" do
      ast = quote(do: import(Enum))
      refute Matchers.require?(ast)
    end
  end

  describe "dependency?/1" do
    test "returns true for use" do
      ast = quote(do: use(GenServer))
      assert Matchers.dependency?(ast)
    end

    test "returns true for import" do
      ast = quote(do: import(Enum))
      assert Matchers.dependency?(ast)
    end

    test "returns true for alias" do
      ast = quote(do: alias(MyApp.MyModule))
      assert Matchers.dependency?(ast)
    end

    test "returns true for require" do
      ast = quote(do: require(Logger))
      assert Matchers.dependency?(ast)
    end

    test "returns false for def" do
      ast = quote(do: def(foo, do: :ok))
      refute Matchers.dependency?(ast)
    end
  end

  # ============================================================================
  # Guard and Delegate Tests
  # ============================================================================

  describe "guard?/1" do
    test "returns true for defguard" do
      ast = quote(do: defguard(is_even(n), do: rem(n, 2) == 0))
      assert Matchers.guard?(ast)
    end

    test "returns true for defguardp" do
      ast = quote(do: defguardp(is_odd(n), do: rem(n, 2) == 1))
      assert Matchers.guard?(ast)
    end

    test "returns false for def" do
      ast = quote(do: def(foo, do: :ok))
      refute Matchers.guard?(ast)
    end
  end

  describe "delegate?/1" do
    test "returns true for defdelegate" do
      ast = quote(do: defdelegate(foo(x), to: Other))
      assert Matchers.delegate?(ast)
    end

    test "returns false for def" do
      ast = quote(do: def(foo, do: :ok))
      refute Matchers.delegate?(ast)
    end
  end

  describe "exception?/1" do
    test "returns true for defexception" do
      ast = quote(do: defexception([:message]))
      assert Matchers.exception?(ast)
    end

    test "returns false for defstruct" do
      ast = quote(do: defstruct([:field]))
      refute Matchers.exception?(ast)
    end
  end

  # ============================================================================
  # definition?/1 Tests
  # ============================================================================

  describe "definition?/1" do
    test "returns true for defmodule" do
      ast = quote(do: defmodule(Foo, do: nil))
      assert Matchers.definition?(ast)
    end

    test "returns true for def" do
      ast = quote(do: def(foo, do: :ok))
      assert Matchers.definition?(ast)
    end

    test "returns true for defmacro" do
      ast = quote(do: defmacro(foo, do: :ok))
      assert Matchers.definition?(ast)
    end

    test "returns true for defprotocol" do
      ast = quote(do: defprotocol(MyProtocol, do: nil))
      assert Matchers.definition?(ast)
    end

    test "returns true for defstruct" do
      ast = quote(do: defstruct([:field]))
      assert Matchers.definition?(ast)
    end

    test "returns false for @doc" do
      ast = quote(do: @doc("docs"))
      refute Matchers.definition?(ast)
    end

    test "returns false for use" do
      ast = quote(do: use(GenServer))
      refute Matchers.definition?(ast)
    end
  end

  # ============================================================================
  # Integration with ASTWalker
  # ============================================================================

  describe "integration with ASTWalker" do
    alias ElixirOntologies.Analyzer.ASTWalker

    test "finds all functions in module" do
      ast =
        quote do
          defmodule Foo do
            def bar, do: :ok
            defp baz, do: :error
          end
        end

      functions = ASTWalker.find_all(ast, &Matchers.function?/1)

      assert length(functions) == 2
    end

    test "finds all dependencies in module" do
      ast =
        quote do
          defmodule Foo do
            use GenServer
            import Enum
            alias MyApp.Helper
            require Logger
          end
        end

      deps = ASTWalker.find_all(ast, &Matchers.dependency?/1)

      assert length(deps) == 4
    end
  end

  # ============================================================================
  # Doctest
  # ============================================================================

  doctest ElixirOntologies.Analyzer.Matchers
end
