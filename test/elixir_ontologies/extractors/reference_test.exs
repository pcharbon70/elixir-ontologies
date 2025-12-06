defmodule ElixirOntologies.Extractors.ReferenceTest do
  @moduledoc """
  Tests for the Reference extractor module.

  These tests verify extraction of variables, module references, function captures,
  and function calls from AST nodes.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Reference

  doctest Reference

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "variable?/1" do
    test "returns true for simple variable" do
      assert Reference.variable?({:x, [], Elixir})
    end

    test "returns true for variable with nil context" do
      assert Reference.variable?({:my_var, [], nil})
    end

    test "returns false for special forms" do
      refute Reference.variable?({:def, [], nil})
      refute Reference.variable?({:if, [], nil})
      refute Reference.variable?({:case, [], nil})
    end

    test "returns false for underscore variables" do
      refute Reference.variable?({:_unused, [], nil})
      refute Reference.variable?({:_, [], nil})
    end

    test "returns false for atoms" do
      refute Reference.variable?(:x)
    end
  end

  describe "module_reference?/1" do
    test "returns true for single module" do
      assert Reference.module_reference?({:__aliases__, [], [:MyModule]})
    end

    test "returns true for nested module" do
      assert Reference.module_reference?({:__aliases__, [], [:MyApp, :Users, :Account]})
    end

    test "returns false for variable" do
      refute Reference.module_reference?({:x, [], nil})
    end
  end

  describe "function_capture?/1" do
    test "returns true for local capture" do
      ast = {:&, [], [{:/, [], [{:func, [], nil}, 2]}]}
      assert Reference.function_capture?(ast)
    end

    test "returns true for remote capture" do
      ast = quote do: &String.upcase/1
      assert Reference.function_capture?(ast)
    end

    test "returns true for anonymous capture" do
      ast = quote do: &(&1 + 1)
      assert Reference.function_capture?(ast)
    end

    test "returns false for non-capture" do
      refute Reference.function_capture?({:x, [], nil})
    end
  end

  describe "remote_call?/1" do
    test "returns true for module function call" do
      ast = quote do: String.upcase("hello")
      assert Reference.remote_call?(ast)
    end

    test "returns true for erlang module call" do
      ast = quote do: :erlang.now()
      assert Reference.remote_call?(ast)
    end

    test "returns false for local call" do
      ast = quote do: my_func(1)
      refute Reference.remote_call?(ast)
    end
  end

  describe "local_call?/1" do
    test "returns true for local function call" do
      ast = {:my_func, [], [1, 2]}
      assert Reference.local_call?(ast)
    end

    test "returns false for variable (no args)" do
      refute Reference.local_call?({:x, [], Elixir})
    end

    test "returns false for special forms" do
      refute Reference.local_call?({:if, [], [true, [do: 1]]})
    end
  end

  describe "binding?/1" do
    test "returns true for simple binding" do
      ast = {:=, [], [{:x, [], nil}, 1]}
      assert Reference.binding?(ast)
    end

    test "returns false for variable" do
      refute Reference.binding?({:x, [], nil})
    end
  end

  describe "pin?/1" do
    test "returns true for pin operator" do
      ast = {:^, [], [{:x, [], nil}]}
      assert Reference.pin?(ast)
    end

    test "returns false for variable" do
      refute Reference.pin?({:x, [], nil})
    end
  end

  describe "reference_type/1" do
    test "identifies variable" do
      assert Reference.reference_type({:x, [], Elixir}) == :variable
    end

    test "identifies module" do
      assert Reference.reference_type({:__aliases__, [], [:MyModule]}) == :module
    end

    test "identifies binding" do
      ast = {:=, [], [{:x, [], nil}, 1]}
      assert Reference.reference_type(ast) == :binding
    end

    test "identifies pin" do
      ast = {:^, [], [{:x, [], nil}]}
      assert Reference.reference_type(ast) == :pin
    end

    test "returns nil for non-reference" do
      assert Reference.reference_type(123) == nil
    end
  end

  # ===========================================================================
  # Variable Extraction Tests
  # ===========================================================================

  describe "extract/1 with variables" do
    test "extracts simple variable" do
      ast = {:my_var, [], Elixir}
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :variable
      assert result.name == :my_var
      assert result.metadata.context == Elixir
    end

    test "extracts variable with nil context" do
      ast = {:x, [line: 1], nil}
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :variable
      assert result.name == :x
    end
  end

  # ===========================================================================
  # Module Reference Extraction Tests
  # ===========================================================================

  describe "extract/1 with module references" do
    test "extracts single module" do
      ast = {:__aliases__, [], [:String]}
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :module
      assert result.name == [:String]
      assert result.module == [:String]
      assert result.metadata.full_name == "String"
    end

    test "extracts nested module" do
      ast = {:__aliases__, [], [:MyApp, :Users, :Account]}
      assert {:ok, result} = Reference.extract(ast)

      assert result.name == [:MyApp, :Users, :Account]
      assert result.metadata.full_name == "MyApp.Users.Account"
      assert result.metadata.depth == 3
    end
  end

  # ===========================================================================
  # Function Capture Extraction Tests
  # ===========================================================================

  describe "extract/1 with function captures" do
    test "extracts local function capture" do
      ast = {:&, [], [{:/, [], [{:my_func, [], nil}, 2]}]}
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :function_capture
      assert result.function == :my_func
      assert result.arity == 2
      assert result.module == nil
      assert result.metadata.capture_type == :local
      assert result.metadata.is_remote == false
    end

    test "extracts remote function capture" do
      ast = quote do: &String.upcase/1
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :function_capture
      assert result.function == :upcase
      assert result.arity == 1
      assert result.module == [:String]
      assert result.metadata.capture_type == :remote
      assert result.metadata.is_remote == true
    end

    test "extracts anonymous capture" do
      ast = quote do: &(&1 + 1)
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :function_capture
      assert result.metadata.capture_type == :anonymous
    end

    test "extracts erlang function capture" do
      # &:erlang.now/0
      ast = {:&, [], [{:/, [], [{{:., [], [:erlang, :now]}, [], []}, 0]}]}
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :function_capture
      assert result.module == :erlang
      assert result.function == :now
      assert result.arity == 0
    end
  end

  # ===========================================================================
  # Remote Call Extraction Tests
  # ===========================================================================

  describe "extract/1 with remote calls" do
    test "extracts module function call" do
      ast = quote do: String.upcase("hello")
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :remote_call
      assert result.module == [:String]
      assert result.function == :upcase
      assert result.arity == 1
      assert result.arguments == ["hello"]
      assert result.metadata.full_call == "String.upcase/1"
    end

    test "extracts erlang module call" do
      ast = quote do: :erlang.now()
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :remote_call
      assert result.module == :erlang
      assert result.function == :now
      assert result.arity == 0
      assert result.metadata.is_erlang == true
    end

    test "extracts call with multiple arguments" do
      ast = quote do: Enum.map([1, 2], fn x -> x end)
      assert {:ok, result} = Reference.extract(ast)

      assert result.function == :map
      assert result.arity == 2
      assert length(result.arguments) == 2
    end

    test "extracts nested module call" do
      ast = quote do: MyApp.Users.Account.get(1)
      assert {:ok, result} = Reference.extract(ast)

      assert result.module == [:MyApp, :Users, :Account]
      assert result.function == :get
      assert result.metadata.full_call == "MyApp.Users.Account.get/1"
    end
  end

  # ===========================================================================
  # Local Call Extraction Tests
  # ===========================================================================

  describe "extract/1 with local calls" do
    test "extracts local function call" do
      ast = {:my_func, [], [1, 2, 3]}
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :local_call
      assert result.function == :my_func
      assert result.arity == 3
      assert result.arguments == [1, 2, 3]
      assert result.metadata.full_call == "my_func/3"
    end

    test "extracts call with no arguments" do
      ast = {:get_value, [], []}
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :local_call
      assert result.function == :get_value
      assert result.arity == 0
    end
  end

  # ===========================================================================
  # Binding Extraction Tests
  # ===========================================================================

  describe "extract/1 with bindings" do
    test "extracts simple binding" do
      ast = {:=, [], [{:x, [], nil}, 42]}
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :binding
      assert result.name == :x
      assert result.value == 42
    end

    test "extracts binding with expression value" do
      value_ast = {:+, [], [1, 2]}
      ast = {:=, [], [{:result, [], nil}, value_ast]}
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :binding
      assert result.name == :result
      assert result.value == value_ast
    end

    test "extracts binding with complex pattern" do
      # {:ok, value} = result
      pattern = {:ok, {:value, [], nil}}
      ast = {:=, [], [pattern, {:result, [], nil}]}
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :binding
      assert result.metadata.pattern == pattern
    end
  end

  # ===========================================================================
  # Pin Extraction Tests
  # ===========================================================================

  describe "extract/1 with pins" do
    test "extracts pin operator" do
      ast = {:^, [], [{:x, [], nil}]}
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :pin
      assert result.name == :x
      assert result.metadata.pinned_variable == :x
    end
  end

  # ===========================================================================
  # Convenience Function Tests
  # ===========================================================================

  describe "remote?/1" do
    test "returns true for remote call" do
      ast = quote do: String.upcase("hi")
      {:ok, ref} = Reference.extract(ast)
      assert Reference.remote?(ref)
    end

    test "returns true for remote capture" do
      ast = quote do: &String.upcase/1
      {:ok, ref} = Reference.extract(ast)
      assert Reference.remote?(ref)
    end

    test "returns false for local call" do
      {:ok, ref} = Reference.extract({:my_func, [], [1]})
      refute Reference.remote?(ref)
    end

    test "returns false for variable" do
      {:ok, ref} = Reference.extract({:x, [], Elixir})
      refute Reference.remote?(ref)
    end
  end

  describe "call?/1" do
    test "returns true for local call" do
      {:ok, ref} = Reference.extract({:my_func, [], [1]})
      assert Reference.call?(ref)
    end

    test "returns true for remote call" do
      ast = quote do: String.upcase("hi")
      {:ok, ref} = Reference.extract(ast)
      assert Reference.call?(ref)
    end

    test "returns false for variable" do
      {:ok, ref} = Reference.extract({:x, [], Elixir})
      refute Reference.call?(ref)
    end
  end

  describe "module_string/1" do
    test "returns string for elixir module" do
      ast = quote do: MyApp.Users.get(1)
      {:ok, ref} = Reference.extract(ast)
      assert Reference.module_string(ref) == "MyApp.Users"
    end

    test "returns inspected atom for erlang module" do
      ast = quote do: :erlang.now()
      {:ok, ref} = Reference.extract(ast)
      assert Reference.module_string(ref) == ":erlang"
    end

    test "returns nil for local call" do
      {:ok, ref} = Reference.extract({:my_func, [], [1]})
      assert Reference.module_string(ref) == nil
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/1 error handling" do
    test "returns error for literal integer" do
      assert {:error, msg} = Reference.extract(123)
      assert msg =~ "Not a reference"
    end

    test "returns error for literal atom" do
      assert {:error, _} = Reference.extract(:atom)
    end

    test "extract! raises on error" do
      assert_raise ArgumentError, fn ->
        Reference.extract!(123)
      end
    end
  end

  # ===========================================================================
  # Edge Case Tests
  # ===========================================================================

  describe "edge cases" do
    test "handles qualified Kernel call" do
      ast = quote do: Kernel.+(1, 2)
      assert {:ok, result} = Reference.extract(ast)

      assert result.type == :remote_call
      assert result.module == [:Kernel]
      assert result.function == :+
    end

    test "distinguishes variable from local call" do
      # Variable (atom context, no args list)
      var_ast = {:x, [], Elixir}
      assert {:ok, var_ref} = Reference.extract(var_ast)
      assert var_ref.type == :variable

      # Local call (has args list, even if empty)
      call_ast = {:x, [], []}
      assert {:ok, call_ref} = Reference.extract(call_ast)
      assert call_ref.type == :local_call
    end

    test "handles deeply nested module" do
      ast = {:__aliases__, [], [:A, :B, :C, :D, :E]}
      assert {:ok, result} = Reference.extract(ast)

      assert result.metadata.depth == 5
      assert result.metadata.full_name == "A.B.C.D.E"
    end
  end
end
