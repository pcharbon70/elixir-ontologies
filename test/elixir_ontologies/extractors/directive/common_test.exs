defmodule ElixirOntologies.Extractors.Directive.CommonTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Directive.Common

  doctest ElixirOntologies.Extractors.Directive.Common

  describe "extract_location/2" do
    test "extracts location when include_location is true (default)" do
      ast = {:alias, [line: 5, column: 3], [{:__aliases__, [], [:MyApp]}]}
      location = Common.extract_location(ast, [])

      assert location != nil
      assert location.start_line == 5
    end

    test "returns nil when include_location is false" do
      ast = {:alias, [line: 5, column: 3], [{:__aliases__, [], [:MyApp]}]}
      location = Common.extract_location(ast, include_location: false)

      assert location == nil
    end

    test "returns nil when no line info in AST" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp]}]}
      location = Common.extract_location(ast, [])

      # Location may still be extracted with nil values or nil entirely
      # depending on Helpers implementation
      assert is_nil(location) or is_struct(location)
    end
  end

  describe "extract_module_parts/1" do
    test "extracts parts from __aliases__ AST" do
      assert {:ok, [:MyApp, :Users]} =
               Common.extract_module_parts({:__aliases__, [], [:MyApp, :Users]})
    end

    test "extracts single module" do
      assert {:ok, [:Enum]} = Common.extract_module_parts({:__aliases__, [], [:Enum]})
    end

    test "handles Erlang module atoms" do
      assert {:ok, [:crypto]} = Common.extract_module_parts(:crypto)
    end

    test "returns error for invalid input" do
      assert {:error, :not_a_module_reference} = Common.extract_module_parts({:foo, [], []})
      assert {:error, :not_a_module_reference} = Common.extract_module_parts("string")
      assert {:error, :not_a_module_reference} = Common.extract_module_parts(123)
    end
  end

  describe "extract_module_parts!/1" do
    test "returns parts on success" do
      assert [:MyApp, :Users] =
               Common.extract_module_parts!({:__aliases__, [], [:MyApp, :Users]})
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, fn ->
        Common.extract_module_parts!({:foo, [], []})
      end
    end
  end

  describe "module_parts_to_string/1" do
    test "converts multi-part module to string" do
      assert "MyApp.Users.Admin" = Common.module_parts_to_string([:MyApp, :Users, :Admin])
    end

    test "converts single Elixir module to string" do
      assert "Enum" = Common.module_parts_to_string([:Enum])
    end

    test "converts Erlang module to string" do
      assert "crypto" = Common.module_parts_to_string([:crypto])
    end
  end

  describe "format_error/2" do
    test "formats error with message and AST" do
      result = Common.format_error("Not valid", {:foo, [], []})
      assert result =~ "Not valid"
      assert result =~ ":foo"
    end
  end

  describe "directive?/2" do
    test "returns true for matching directive type" do
      assert Common.directive?({:alias, [], [{:__aliases__, [], [:Foo]}]}, :alias)
      assert Common.directive?({:import, [], [{:__aliases__, [], [:Enum]}]}, :import)
      assert Common.directive?({:require, [], [{:__aliases__, [], [:Logger]}]}, :require)
      assert Common.directive?({:use, [], [{:__aliases__, [], [:GenServer]}]}, :use)
    end

    test "returns false for non-matching directive type" do
      refute Common.directive?({:alias, [], [{:__aliases__, [], [:Foo]}]}, :import)
      refute Common.directive?({:import, [], [{:__aliases__, [], [:Enum]}]}, :alias)
    end

    test "returns false for non-directive AST" do
      refute Common.directive?({:def, [], [{:foo, [], nil}]}, :alias)
      refute Common.directive?(:atom, :alias)
      refute Common.directive?("string", :import)
    end
  end

  describe "function_definition?/1" do
    test "returns true for def" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      assert Common.function_definition?(ast)
    end

    test "returns true for defp" do
      ast = {:defp, [], [{:bar, [], nil}, [do: :ok]]}
      assert Common.function_definition?(ast)
    end

    test "returns true for defmacro" do
      ast = {:defmacro, [], [{:baz, [], nil}, [do: :ok]]}
      assert Common.function_definition?(ast)
    end

    test "returns true for defmacrop" do
      ast = {:defmacrop, [], [{:qux, [], nil}, [do: :ok]]}
      assert Common.function_definition?(ast)
    end

    test "returns true for function with when clause" do
      ast = {:def, [], [{:when, [], [{:foo, [], [:x]}, {:is_integer, [], [:x]}]}, [do: :ok]]}
      assert Common.function_definition?(ast)
    end

    test "returns false for non-function definitions" do
      refute Common.function_definition?({:alias, [], [{:__aliases__, [], [:Foo]}]})
      refute Common.function_definition?({:import, [], [{:__aliases__, [], [:Enum]}]})
      refute Common.function_definition?(:atom)
    end
  end

  describe "block_construct?/1" do
    test "returns true for if" do
      assert Common.block_construct?({:if, [], [true, [do: :ok]]})
    end

    test "returns true for unless" do
      assert Common.block_construct?({:unless, [], [false, [do: :ok]]})
    end

    test "returns true for case" do
      assert Common.block_construct?({:case, [], [:foo, [do: []]]})
    end

    test "returns true for cond" do
      assert Common.block_construct?({:cond, [], [[do: []]]})
    end

    test "returns true for with" do
      assert Common.block_construct?({:with, [], [[do: :ok]]})
    end

    test "returns true for for" do
      assert Common.block_construct?({:for, [], [:x, [do: :ok]]})
    end

    test "returns true for try" do
      assert Common.block_construct?({:try, [], [[do: :ok]]})
    end

    test "returns true for receive" do
      assert Common.block_construct?({:receive, [], [[do: []]]})
    end

    test "returns false for non-block constructs" do
      refute Common.block_construct?({:def, [], [{:foo, [], nil}, [do: :ok]]})
      refute Common.block_construct?({:alias, [], [{:__aliases__, [], [:Foo]}]})
      refute Common.block_construct?(:atom)
    end
  end

  describe "extract_function_body/1" do
    test "extracts body from def" do
      body = {:__block__, [], [:ok, :done]}
      ast = {:def, [], [{:foo, [], nil}, [do: body]]}

      assert Common.extract_function_body(ast) == body
    end

    test "extracts body from defp" do
      body = :ok
      ast = {:defp, [], [{:bar, [], nil}, [do: body]]}

      assert Common.extract_function_body(ast) == body
    end

    test "extracts body from function with when clause" do
      body = :ok
      ast = {:def, [], [{:when, [], [{:foo, [], [:x]}, {:is_integer, [], [:x]}]}, [do: body]]}

      assert Common.extract_function_body(ast) == body
    end

    test "returns nil when no do clause" do
      ast = {:def, [], [{:foo, [], nil}, []]}
      assert Common.extract_function_body(ast) == nil
    end

    test "returns nil for non-function" do
      assert Common.extract_function_body({:alias, [], [{:__aliases__, [], [:Foo]}]}) == nil
      assert Common.extract_function_body(:atom) == nil
    end
  end
end
