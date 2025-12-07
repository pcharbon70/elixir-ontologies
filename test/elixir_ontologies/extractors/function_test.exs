defmodule ElixirOntologies.Extractors.FunctionTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Function

  doctest Function

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "function?/1" do
    test "returns true for def" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      assert Function.function?(ast)
    end

    test "returns true for defp" do
      ast = {:defp, [], [{:foo, [], nil}, [do: :ok]]}
      assert Function.function?(ast)
    end

    test "returns true for defguard" do
      ast = {:defguard, [], [{:when, [], [{:is_valid, [], [{:x, [], nil}]}, true]}]}
      assert Function.function?(ast)
    end

    test "returns true for defguardp" do
      ast = {:defguardp, [], [{:when, [], [{:is_valid, [], [{:x, [], nil}]}, true]}]}
      assert Function.function?(ast)
    end

    test "returns true for defdelegate" do
      ast = {:defdelegate, [], [{:foo, [], nil}, [to: SomeModule]]}
      assert Function.function?(ast)
    end

    test "returns false for defmodule" do
      ast = {:defmodule, [], [{:__aliases__, [], [:Foo]}, [do: nil]]}
      refute Function.function?(ast)
    end

    test "returns false for non-AST values" do
      refute Function.function?(:not_a_function)
      refute Function.function?(123)
      refute Function.function?("string")
    end
  end

  describe "guard?/1" do
    test "returns true for defguard" do
      ast = {:defguard, [], [{:when, [], [{:is_valid, [], [{:x, [], nil}]}, true]}]}
      assert Function.guard?(ast)
    end

    test "returns true for defguardp" do
      ast = {:defguardp, [], [{:when, [], [{:is_valid, [], [{:x, [], nil}]}, true]}]}
      assert Function.guard?(ast)
    end

    test "returns false for def" do
      ast = {:def, [], [{:foo, [], nil}]}
      refute Function.guard?(ast)
    end
  end

  describe "delegate?/1" do
    test "returns true for defdelegate" do
      ast = {:defdelegate, [], [{:foo, [], nil}, [to: SomeModule]]}
      assert Function.delegate?(ast)
    end

    test "returns false for def" do
      ast = {:def, [], [{:foo, [], nil}]}
      refute Function.delegate?(ast)
    end
  end

  # ===========================================================================
  # Basic Extraction Tests
  # ===========================================================================

  describe "extract/2 public functions" do
    test "extracts simple public function" do
      ast = {:def, [], [{:hello, [], nil}, [do: :ok]]}

      assert {:ok, result} = Function.extract(ast)
      assert result.type == :function
      assert result.name == :hello
      assert result.arity == 0
      assert result.visibility == :public
    end

    test "extracts public function with one argument" do
      ast = {:def, [], [{:greet, [], [{:name, [], nil}]}, [do: :ok]]}

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :greet
      assert result.arity == 1
    end

    test "extracts public function with multiple arguments" do
      ast = {:def, [], [{:add, [], [{:a, [], nil}, {:b, [], nil}]}, [do: :ok]]}

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :add
      assert result.arity == 2
    end

    test "extracts public function with guard" do
      ast =
        {:def, [],
         [
           {:when, [], [{:process, [], [{:x, [], nil}]}, {:is_integer, [], [{:x, [], nil}]}]},
           [do: :ok]
         ]}

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :process
      assert result.arity == 1
      assert result.metadata.has_guard == true
    end
  end

  describe "extract/2 private functions" do
    test "extracts simple private function" do
      ast = {:defp, [], [{:internal, [], nil}, [do: :ok]]}

      assert {:ok, result} = Function.extract(ast)
      assert result.type == :function
      assert result.name == :internal
      assert result.visibility == :private
    end

    test "extracts private function with arguments" do
      ast = {:defp, [], [{:helper, [], [{:x, [], nil}, {:y, [], nil}]}, [do: :ok]]}

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :helper
      assert result.arity == 2
      assert result.visibility == :private
    end

    test "extracts private function with guard" do
      ast =
        {:defp, [],
         [
           {:when, [], [{:validate, [], [{:x, [], nil}]}, {:is_binary, [], [{:x, [], nil}]}]},
           [do: :ok]
         ]}

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :validate
      assert result.visibility == :private
      assert result.metadata.has_guard == true
    end
  end

  # ===========================================================================
  # Guard Function Tests
  # ===========================================================================

  describe "extract/2 guard functions" do
    test "extracts public guard" do
      ast =
        {:defguard, [],
         [{:when, [], [{:is_valid, [], [{:x, [], nil}]}, {:>, [], [{:x, [], nil}, 0]}]}]}

      assert {:ok, result} = Function.extract(ast)
      assert result.type == :guard
      assert result.name == :is_valid
      assert result.arity == 1
      assert result.visibility == :public
      assert result.metadata.guard_expression != nil
    end

    test "extracts private guard" do
      ast =
        {:defguardp, [],
         [{:when, [], [{:is_ok, [], [{:x, [], nil}]}, {:==, [], [{:x, [], nil}, :ok]}]}]}

      assert {:ok, result} = Function.extract(ast)
      assert result.type == :guard
      assert result.name == :is_ok
      assert result.visibility == :private
    end

    test "extracts guard with multiple parameters" do
      ast =
        {:defguard, [],
         [{:when, [], [{:in_range, [], [{:x, [], nil}, {:min, [], nil}, {:max, [], nil}]}, true]}]}

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :in_range
      assert result.arity == 3
    end
  end

  # ===========================================================================
  # Delegate Function Tests
  # ===========================================================================

  describe "extract/2 delegate functions" do
    test "extracts simple delegate" do
      ast = {:defdelegate, [], [{:foo, [], nil}, [to: SomeModule]]}

      assert {:ok, result} = Function.extract(ast)
      assert result.type == :delegate
      assert result.name == :foo
      assert result.arity == 0
      assert result.visibility == :public
    end

    test "extracts delegate with arguments" do
      ast = {:defdelegate, [], [{:process, [], [{:x, [], nil}]}, [to: Handler]]}

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :process
      assert result.arity == 1
      assert result.metadata.delegates_to == {Handler, :process, 1}
    end

    test "extracts delegate with :as option" do
      ast = {:defdelegate, [], [{:my_func, [], [{:x, [], nil}]}, [to: Target, as: :other_func]]}

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :my_func
      assert result.metadata.delegates_to == {Target, :other_func, 1}
    end

    test "extracts delegate with aliased module" do
      ast = {:defdelegate, [], [{:foo, [], nil}, [to: {:__aliases__, [], [:My, :Module]}]]}

      assert {:ok, result} = Function.extract(ast)
      assert result.metadata.delegates_to == {My.Module, :foo, 0}
    end

    test "delegate_target returns target for delegate" do
      ast = {:defdelegate, [], [{:foo, [], [{:x, [], nil}]}, [to: Target]]}
      {:ok, func} = Function.extract(ast)

      assert Function.delegate_target(func) == {Target, :foo, 1}
    end

    test "delegate_target returns nil for non-delegate" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      {:ok, func} = Function.extract(ast)

      assert Function.delegate_target(func) == nil
    end
  end

  # ===========================================================================
  # Default Parameter Tests
  # ===========================================================================

  describe "extract/2 default parameters" do
    test "detects function with one default parameter" do
      ast =
        quote do
          def greet(name \\ "World"), do: name
        end

      assert {:ok, result} = Function.extract(ast)
      assert result.arity == 1
      assert result.min_arity == 0
      assert result.metadata.default_args == 1
    end

    test "detects function with multiple default parameters" do
      ast =
        quote do
          def call(a, b \\ 1, c \\ 2), do: {a, b, c}
        end

      assert {:ok, result} = Function.extract(ast)
      assert result.arity == 3
      assert result.min_arity == 1
      assert result.metadata.default_args == 2
    end

    test "has_defaults? returns true for functions with defaults" do
      ast =
        quote do
          def greet(name \\ "World"), do: name
        end

      {:ok, func} = Function.extract(ast)
      assert Function.has_defaults?(func)
    end

    test "has_defaults? returns false for functions without defaults" do
      ast = {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: :ok]]}
      {:ok, func} = Function.extract(ast)

      refute Function.has_defaults?(func)
    end
  end

  # ===========================================================================
  # Documentation Tests
  # ===========================================================================

  describe "extract/2 with documentation" do
    test "stores docstring from :doc option" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}

      assert {:ok, result} = Function.extract(ast, doc: "This is documentation")
      assert result.docstring == "This is documentation"
    end

    test "stores false for @doc false" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}

      assert {:ok, result} = Function.extract(ast, doc: false)
      assert result.docstring == false
      assert result.metadata.doc_hidden == true
    end

    test "doc_hidden? returns true for @doc false" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      {:ok, func} = Function.extract(ast, doc: false)

      assert Function.doc_hidden?(func)
    end

    test "doc_hidden? returns false for documented function" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      {:ok, func} = Function.extract(ast, doc: "docs")

      refute Function.doc_hidden?(func)
    end
  end

  # ===========================================================================
  # Spec Association Tests
  # ===========================================================================

  describe "extract/2 with spec" do
    test "stores spec from :spec option" do
      spec_ast = {:"::", [], [{:foo, [], [{:integer, [], nil}]}, {:integer, [], nil}]}
      ast = {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: :ok]]}

      assert {:ok, result} = Function.extract(ast, spec: spec_ast)
      assert result.metadata.spec == spec_ast
    end
  end

  # ===========================================================================
  # Module Context Tests
  # ===========================================================================

  describe "extract/2 with module context" do
    test "stores module from :module option" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}

      assert {:ok, result} = Function.extract(ast, module: [:MyApp, :Users])
      assert result.metadata.module == [:MyApp, :Users]
    end

    test "function_id returns name/arity string" do
      ast = {:def, [], [{:hello, [], [{:x, [], nil}]}, [do: :ok]]}
      {:ok, func} = Function.extract(ast)

      assert Function.function_id(func) == "hello/1"
    end

    test "qualified_id returns full path with module" do
      ast = {:def, [], [{:hello, [], [{:x, [], nil}]}, [do: :ok]]}
      {:ok, func} = Function.extract(ast, module: [:MyApp, :Greeter])

      assert Function.qualified_id(func) == "MyApp.Greeter.hello/1"
    end

    test "qualified_id returns just name/arity without module" do
      ast = {:def, [], [{:hello, [], nil}, [do: :ok]]}
      {:ok, func} = Function.extract(ast)

      assert Function.qualified_id(func) == "hello/0"
    end
  end

  # ===========================================================================
  # Bodyless Function Tests
  # ===========================================================================

  describe "extract/2 bodyless functions" do
    test "extracts bodyless public function" do
      ast = {:def, [], [{:callback, [], [{:x, [], nil}]}]}

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :callback
      assert result.arity == 1
    end

    test "extracts bodyless private function" do
      ast = {:defp, [], [{:internal, [], nil}]}

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :internal
      assert result.arity == 0
    end

    test "extracts bodyless function with guard" do
      ast =
        {:def, [], [{:when, [], [{:foo, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]}]}

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :foo
      assert result.arity == 1
      assert result.metadata.has_guard == true
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/2 error handling" do
    test "returns error for defmodule" do
      ast = {:defmodule, [], [{:__aliases__, [], [:Foo]}, [do: nil]]}
      assert {:error, message} = Function.extract(ast)
      assert message =~ "Not a function definition"
    end

    test "returns error for non-AST" do
      assert {:error, _} = Function.extract(:not_an_ast)
      assert {:error, _} = Function.extract(123)
    end
  end

  describe "extract!/2" do
    test "returns result on success" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      result = Function.extract!(ast)

      assert result.name == :foo
    end

    test "raises on error" do
      ast = {:defmodule, [], []}

      assert_raise ArgumentError, ~r/Not a function definition/, fn ->
        Function.extract!(ast)
      end
    end
  end

  # ===========================================================================
  # Integration Tests with quote
  # ===========================================================================

  describe "integration with quote" do
    test "extracts function from quoted code" do
      ast =
        quote do
          def hello(name), do: "Hello, #{name}"
        end

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :hello
      assert result.arity == 1
    end

    test "extracts function with guard from quoted code" do
      ast =
        quote do
          def process(x) when is_integer(x), do: x * 2
        end

      assert {:ok, result} = Function.extract(ast)
      assert result.name == :process
      assert result.metadata.has_guard == true
    end

    test "extracts guard from quoted code" do
      ast =
        quote do
          defguard is_positive(x) when is_integer(x) and x > 0
        end

      assert {:ok, result} = Function.extract(ast)
      assert result.type == :guard
      assert result.name == :is_positive
    end

    test "extracts delegate from quoted code" do
      ast =
        quote do
          defdelegate fetch(key), to: Map
        end

      assert {:ok, result} = Function.extract(ast)
      assert result.type == :delegate
      assert result.metadata.delegates_to == {Map, :fetch, 1}
    end
  end
end
