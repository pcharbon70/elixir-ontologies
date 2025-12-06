defmodule ElixirOntologies.Extractors.TypeDefinitionTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.TypeDefinition

  doctest TypeDefinition

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "type_definition?/1" do
    test "returns true for @type" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      assert TypeDefinition.type_definition?(ast)
    end

    test "returns true for @typep" do
      ast = {:@, [], [{:typep, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      assert TypeDefinition.type_definition?(ast)
    end

    test "returns true for @opaque" do
      ast = {:@, [], [{:opaque, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      assert TypeDefinition.type_definition?(ast)
    end

    test "returns false for @doc" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}
      refute TypeDefinition.type_definition?(ast)
    end

    test "returns false for @spec" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      refute TypeDefinition.type_definition?(ast)
    end

    test "returns false for nil" do
      refute TypeDefinition.type_definition?(nil)
    end
  end

  # ===========================================================================
  # @type Extraction Tests
  # ===========================================================================

  describe "extract/2 @type" do
    test "extracts simple type" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :t
      assert result.arity == 0
      assert result.visibility == :public
      assert result.parameters == []
      assert result.expression == :any
    end

    test "extracts type with atom expression" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:status, [], nil}, :ok]}]}]}

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :status
      assert result.expression == :ok
    end

    test "extracts type with basic type expression" do
      # @type count :: integer()
      expr = {:integer, [], []}
      ast = {:@, [], [{:type, [], [{:"::", [], [{:count, [], nil}, expr]}]}]}

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :count
      assert result.expression == expr
    end

    test "extracts parameterized type" do
      # @type my_list(a) :: [a]
      ast = {:@, [], [{:type, [], [{:"::", [], [{:my_list, [], [{:a, [], nil}]}, [{:a, [], nil}]]}]}]}

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :my_list
      assert result.arity == 1
      assert result.parameters == [:a]
      assert result.metadata.is_parameterized == true
    end

    test "extracts multi-parameter type" do
      # @type pair(a, b) :: {a, b}
      ast =
        {:@, [],
         [
           {:type, [],
            [
              {:"::", [],
               [
                 {:pair, [], [{:a, [], nil}, {:b, [], nil}]},
                 {:{}, [], [{:a, [], nil}, {:b, [], nil}]}
               ]}
            ]}
         ]}

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :pair
      assert result.arity == 2
      assert result.parameters == [:a, :b]
    end

    test "extracts type with union expression" do
      # @type result :: :ok | :error
      expr = {:|, [], [:ok, :error]}
      ast = {:@, [], [{:type, [], [{:"::", [], [{:result, [], nil}, expr]}]}]}

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :result
      assert result.expression == expr
    end

    test "extracts type with tuple expression" do
      # @type response :: {:ok, any()} | {:error, term()}
      expr = {:|, [], [{:ok, {:any, [], []}}, {:error, {:term, [], []}}]}
      ast = {:@, [], [{:type, [], [{:"::", [], [{:response, [], nil}, expr]}]}]}

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :response
      assert result.expression == expr
    end
  end

  # ===========================================================================
  # @typep Extraction Tests
  # ===========================================================================

  describe "extract/2 @typep" do
    test "extracts private type" do
      ast = {:@, [], [{:typep, [], [{:"::", [], [{:internal, [], nil}, :atom]}]}]}

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :internal
      assert result.visibility == :private
      assert result.metadata.attribute == :typep
    end

    test "extracts parameterized private type" do
      ast =
        {:@, [],
         [{:typep, [], [{:"::", [], [{:state, [], [{:a, [], nil}]}, {:a, [], nil}]}]}]}

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :state
      assert result.visibility == :private
      assert result.arity == 1
    end
  end

  # ===========================================================================
  # @opaque Extraction Tests
  # ===========================================================================

  describe "extract/2 @opaque" do
    test "extracts opaque type" do
      ast = {:@, [], [{:opaque, [], [{:"::", [], [{:secret, [], nil}, :binary]}]}]}

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :secret
      assert result.visibility == :opaque
      assert result.metadata.attribute == :opaque
    end

    test "extracts parameterized opaque type" do
      ast =
        {:@, [],
         [{:opaque, [], [{:"::", [], [{:box, [], [{:a, [], nil}]}, {:%{}, [], [value: {:a, [], nil}]}]}]}]}

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :box
      assert result.visibility == :opaque
      assert result.arity == 1
    end
  end

  # ===========================================================================
  # Bulk Extraction Tests
  # ===========================================================================

  describe "extract_all/1" do
    test "extracts all type definitions from block" do
      body =
        {:__block__, [],
         [
           {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]},
           {:@, [], [{:typep, [], [{:"::", [], [{:internal, [], nil}, :atom]}]}]},
           {:@, [], [{:doc, [], ["docs"]}]},
           {:@, [], [{:opaque, [], [{:"::", [], [{:secret, [], nil}, :binary]}]}]}
         ]}

      results = TypeDefinition.extract_all(body)
      assert length(results) == 3
      assert Enum.map(results, & &1.name) == [:t, :internal, :secret]
      assert Enum.map(results, & &1.visibility) == [:public, :private, :opaque]
    end

    test "extracts single type definition" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}

      results = TypeDefinition.extract_all(ast)
      assert length(results) == 1
      assert hd(results).name == :t
    end

    test "returns empty list for nil" do
      assert TypeDefinition.extract_all(nil) == []
    end

    test "returns empty list for non-type attribute" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}
      assert TypeDefinition.extract_all(ast) == []
    end
  end

  # ===========================================================================
  # Helper Function Tests
  # ===========================================================================

  describe "parameterized?/1" do
    test "returns true for parameterized type" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:my_list, [], [{:a, [], nil}]}, [{:a, [], nil}]]}]}]}
      {:ok, result} = TypeDefinition.extract(ast)
      assert TypeDefinition.parameterized?(result)
    end

    test "returns false for non-parameterized type" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      {:ok, result} = TypeDefinition.extract(ast)
      refute TypeDefinition.parameterized?(result)
    end
  end

  describe "public?/1" do
    test "returns true for @type" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      {:ok, result} = TypeDefinition.extract(ast)
      assert TypeDefinition.public?(result)
    end

    test "returns false for @typep" do
      ast = {:@, [], [{:typep, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      {:ok, result} = TypeDefinition.extract(ast)
      refute TypeDefinition.public?(result)
    end
  end

  describe "private?/1" do
    test "returns true for @typep" do
      ast = {:@, [], [{:typep, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      {:ok, result} = TypeDefinition.extract(ast)
      assert TypeDefinition.private?(result)
    end

    test "returns false for @type" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      {:ok, result} = TypeDefinition.extract(ast)
      refute TypeDefinition.private?(result)
    end
  end

  describe "opaque?/1" do
    test "returns true for @opaque" do
      ast = {:@, [], [{:opaque, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      {:ok, result} = TypeDefinition.extract(ast)
      assert TypeDefinition.opaque?(result)
    end

    test "returns false for @type" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      {:ok, result} = TypeDefinition.extract(ast)
      refute TypeDefinition.opaque?(result)
    end
  end

  describe "type_id/1" do
    test "returns name/arity for non-parameterized type" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      {:ok, result} = TypeDefinition.extract(ast)
      assert TypeDefinition.type_id(result) == "t/0"
    end

    test "returns name/arity for parameterized type" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:my_list, [], [{:a, [], nil}]}, [{:a, [], nil}]]}]}]}
      {:ok, result} = TypeDefinition.extract(ast)
      assert TypeDefinition.type_id(result) == "my_list/1"
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/2 error handling" do
    test "returns error for non-type attribute" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}
      assert {:error, _} = TypeDefinition.extract(ast)
    end

    test "returns error for non-attribute" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      assert {:error, _} = TypeDefinition.extract(ast)
    end
  end

  describe "extract!/2" do
    test "returns result on success" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      result = TypeDefinition.extract!(ast)
      assert result.name == :t
    end

    test "raises on error" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}

      assert_raise ArgumentError, fn ->
        TypeDefinition.extract!(ast)
      end
    end
  end

  # ===========================================================================
  # Integration Tests with quote
  # ===========================================================================

  describe "integration with quote" do
    test "extracts simple type from quoted code" do
      {:@, _, [{:type, _, _}]} =
        ast =
        quote do
          @type t :: any()
        end

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :t
      assert result.visibility == :public
    end

    test "extracts parameterized type from quoted code" do
      {:@, _, [{:type, _, _}]} =
        ast =
        quote do
          @type my_list(a) :: [a]
        end

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :my_list
      assert result.arity == 1
      assert result.parameters == [:a]
    end

    test "extracts private type from quoted code" do
      {:@, _, [{:typep, _, _}]} =
        ast =
        quote do
          @typep internal :: atom()
        end

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :internal
      assert result.visibility == :private
    end

    test "extracts opaque type from quoted code" do
      {:@, _, [{:opaque, _, _}]} =
        ast =
        quote do
          @opaque secret :: binary()
        end

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :secret
      assert result.visibility == :opaque
    end

    test "extracts type with complex expression from quoted code" do
      {:@, _, [{:type, _, _}]} =
        ast =
        quote do
          @type result :: {:ok, any()} | {:error, term()}
        end

      assert {:ok, result} = TypeDefinition.extract(ast)
      assert result.name == :result
      # Expression should be a union type
      assert match?({:|, _, _}, result.expression)
    end
  end
end
