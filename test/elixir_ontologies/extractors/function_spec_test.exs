defmodule ElixirOntologies.Extractors.FunctionSpecTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.FunctionSpec

  doctest FunctionSpec

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "spec?/1" do
    test "returns true for @spec" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      assert FunctionSpec.spec?(ast)
    end

    test "returns true for @spec with when clause" do
      ast =
        {:@, [],
         [
           {:spec, [],
            [
              {:when, [],
               [
                 {:"::", [], [{:identity, [], [{:a, [], nil}]}, {:a, [], nil}]},
                 [a: {:var, [], nil}]
               ]}
            ]}
         ]}

      assert FunctionSpec.spec?(ast)
    end

    test "returns false for @type" do
      ast = {:@, [], [{:type, [], [{:"::", [], [{:t, [], nil}, :any]}]}]}
      refute FunctionSpec.spec?(ast)
    end

    test "returns false for @doc" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}
      refute FunctionSpec.spec?(ast)
    end

    test "returns false for nil" do
      refute FunctionSpec.spec?(nil)
    end

    test "returns false for def" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      refute FunctionSpec.spec?(ast)
    end
  end

  # ===========================================================================
  # Simple Spec Extraction Tests
  # ===========================================================================

  describe "extract/2 simple specs" do
    test "extracts spec with no parameters" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:now, [], []}, :ok]}]}]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :now
      assert result.arity == 0
      assert result.parameter_types == []
      assert result.return_type == :ok
    end

    test "extracts spec with one parameter" do
      ast =
        {:@, [],
         [{:spec, [], [{:"::", [], [{:double, [], [{:integer, [], []}]}, {:integer, [], []}]}]}]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :double
      assert result.arity == 1
      assert result.parameter_types == [{:integer, [], []}]
      assert result.return_type == {:integer, [], []}
    end

    test "extracts spec with multiple parameters" do
      ast =
        {:@, [],
         [
           {:spec, [],
            [
              {:"::", [],
               [{:add, [], [{:integer, [], []}, {:integer, [], []}]}, {:integer, [], []}]}
            ]}
         ]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :add
      assert result.arity == 2
      assert length(result.parameter_types) == 2
    end

    test "extracts spec with atom return type" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:status, [], []}, :ok]}]}]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.return_type == :ok
    end

    test "extracts spec with basic type call return" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:count, [], []}, {:integer, [], []}]}]}]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.return_type == {:integer, [], []}
    end
  end

  # ===========================================================================
  # Union Type Extraction Tests
  # ===========================================================================

  describe "extract/2 union types" do
    test "extracts spec with union return type" do
      # @spec fetch() :: :ok | :error
      return_type = {:|, [], [:ok, :error]}
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:fetch, [], []}, return_type]}]}]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.return_type == return_type
    end

    test "extracts spec with complex union return" do
      # @spec fetch(map()) :: {:ok, term()} | :error
      return_type = {:|, [], [{:ok, {:term, [], []}}, :error]}
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:fetch, [], [{:map, [], []}]}, return_type]}]}]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.return_type == return_type
    end

    test "extracts spec with nested union" do
      # @spec result() :: :ok | :error | :pending
      return_type = {:|, [], [:ok, {:|, [], [:error, :pending]}]}
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:result, [], []}, return_type]}]}]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.return_type == return_type
    end
  end

  # ===========================================================================
  # When Clause Extraction Tests
  # ===========================================================================

  describe "extract/2 when clauses" do
    test "extracts spec with single when constraint" do
      # @spec identity(a) :: a when a: var
      ast =
        {:@, [],
         [
           {:spec, [],
            [
              {:when, [],
               [
                 {:"::", [], [{:identity, [], [{:a, [], nil}]}, {:a, [], nil}]},
                 [a: {:var, [], nil}]
               ]}
            ]}
         ]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :identity
      assert result.arity == 1
      assert result.type_constraints == %{a: {:var, [], nil}}
      assert result.metadata.has_when_clause == true
    end

    test "extracts spec with multiple when constraints" do
      # @spec convert(a, b) :: {a, b} when a: atom(), b: integer()
      ast =
        {:@, [],
         [
           {:spec, [],
            [
              {:when, [],
               [
                 {:"::", [],
                  [
                    {:convert, [], [{:a, [], nil}, {:b, [], nil}]},
                    {{:a, [], nil}, {:b, [], nil}}
                  ]},
                 [a: {:atom, [], []}, b: {:integer, [], []}]
               ]}
            ]}
         ]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :convert
      assert result.arity == 2
      assert result.type_constraints == %{a: {:atom, [], []}, b: {:integer, [], []}}
    end

    test "spec without when clause has empty constraints" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.type_constraints == %{}
      assert result.metadata.has_when_clause == false
    end
  end

  # ===========================================================================
  # Bulk Extraction Tests
  # ===========================================================================

  describe "extract_all/1" do
    test "extracts all specs from block" do
      body =
        {:__block__, [],
         [
           {:@, [],
            [{:spec, [], [{:"::", [], [{:add, [], [{:integer, [], []}]}, {:integer, [], []}]}]}]},
           {:@, [],
            [{:spec, [], [{:"::", [], [{:sub, [], [{:integer, [], []}]}, {:integer, [], []}]}]}]},
           {:@, [], [{:doc, [], ["docs"]}]},
           {:@, [],
            [{:spec, [], [{:"::", [], [{:mul, [], [{:integer, [], []}]}, {:integer, [], []}]}]}]}
         ]}

      results = FunctionSpec.extract_all(body)
      assert length(results) == 3
      assert Enum.map(results, & &1.name) == [:add, :sub, :mul]
    end

    test "extracts single spec" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}

      results = FunctionSpec.extract_all(ast)
      assert length(results) == 1
      assert hd(results).name == :foo
    end

    test "returns empty list for nil" do
      assert FunctionSpec.extract_all(nil) == []
    end

    test "returns empty list for non-spec attribute" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}
      assert FunctionSpec.extract_all(ast) == []
    end

    test "returns empty list for def" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      assert FunctionSpec.extract_all(ast) == []
    end
  end

  # ===========================================================================
  # Helper Function Tests
  # ===========================================================================

  describe "has_when_clause?/1" do
    test "returns true for spec with when clause" do
      ast =
        {:@, [],
         [
           {:spec, [],
            [
              {:when, [],
               [
                 {:"::", [], [{:identity, [], [{:a, [], nil}]}, {:a, [], nil}]},
                 [a: {:var, [], nil}]
               ]}
            ]}
         ]}

      {:ok, result} = FunctionSpec.extract(ast)
      assert FunctionSpec.has_when_clause?(result)
    end

    test "returns false for spec without when clause" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      {:ok, result} = FunctionSpec.extract(ast)
      refute FunctionSpec.has_when_clause?(result)
    end
  end

  describe "spec_id/1" do
    test "returns name/arity for no-arg spec" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      {:ok, result} = FunctionSpec.extract(ast)
      assert FunctionSpec.spec_id(result) == "foo/0"
    end

    test "returns name/arity for multi-arg spec" do
      ast =
        {:@, [],
         [
           {:spec, [],
            [
              {:"::", [],
               [{:add, [], [{:integer, [], []}, {:integer, [], []}]}, {:integer, [], []}]}
            ]}
         ]}

      {:ok, result} = FunctionSpec.extract(ast)
      assert FunctionSpec.spec_id(result) == "add/2"
    end
  end

  describe "union_return?/1" do
    test "returns true for union return type" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:fetch, [], []}, {:|, [], [:ok, :error]}]}]}]}
      {:ok, result} = FunctionSpec.extract(ast)
      assert FunctionSpec.union_return?(result)
    end

    test "returns false for non-union return type" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      {:ok, result} = FunctionSpec.extract(ast)
      refute FunctionSpec.union_return?(result)
    end
  end

  describe "flatten_union_return/1" do
    test "flattens simple union" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:fetch, [], []}, {:|, [], [:ok, :error]}]}]}]}
      {:ok, result} = FunctionSpec.extract(ast)
      assert FunctionSpec.flatten_union_return(result) == [:ok, :error]
    end

    test "flattens nested union" do
      return_type = {:|, [], [:ok, {:|, [], [:error, :pending]}]}
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:result, [], []}, return_type]}]}]}
      {:ok, result} = FunctionSpec.extract(ast)
      assert FunctionSpec.flatten_union_return(result) == [:ok, :error, :pending]
    end

    test "returns single-element list for non-union" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      {:ok, result} = FunctionSpec.extract(ast)
      assert FunctionSpec.flatten_union_return(result) == [:ok]
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/2 error handling" do
    test "returns error for non-spec attribute" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}
      assert {:error, _} = FunctionSpec.extract(ast)
    end

    test "returns error for def" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      assert {:error, _} = FunctionSpec.extract(ast)
    end

    test "returns error for nil" do
      assert {:error, _} = FunctionSpec.extract(nil)
    end
  end

  describe "extract!/2" do
    test "returns result on success" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      result = FunctionSpec.extract!(ast)
      assert result.name == :foo
    end

    test "raises on error" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}

      assert_raise ArgumentError, fn ->
        FunctionSpec.extract!(ast)
      end
    end
  end

  # ===========================================================================
  # Integration Tests with quote
  # ===========================================================================

  describe "integration with quote" do
    test "extracts simple spec from quoted code" do
      {:@, _, [{:spec, _, _}]} =
        ast =
        quote do
          @spec add(integer(), integer()) :: integer()
        end

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :add
      assert result.arity == 2
    end

    test "extracts spec with when clause from quoted code" do
      {:@, _, [{:spec, _, _}]} =
        ast =
        quote do
          @spec identity(a) :: a when a: var
        end

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :identity
      assert result.arity == 1
      assert Map.has_key?(result.type_constraints, :a)
    end

    test "extracts spec with union return from quoted code" do
      {:@, _, [{:spec, _, _}]} =
        ast =
        quote do
          @spec fetch(map()) :: {:ok, term()} | :error
        end

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :fetch
      assert FunctionSpec.union_return?(result)
    end

    test "extracts spec with remote type from quoted code" do
      {:@, _, [{:spec, _, _}]} =
        ast =
        quote do
          @spec now() :: DateTime.t()
        end

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :now
      assert result.arity == 0
    end

    test "extracts spec with tuple types from quoted code" do
      {:@, _, [{:spec, _, _}]} =
        ast =
        quote do
          @spec pair(atom(), integer()) :: {atom(), integer()}
        end

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :pair
      assert result.arity == 2
    end

    test "extracts spec with list type from quoted code" do
      {:@, _, [{:spec, _, _}]} =
        ast =
        quote do
          @spec items() :: [atom()]
        end

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :items
      assert result.arity == 0
    end

    test "extracts spec with map type from quoted code" do
      {:@, _, [{:spec, _, _}]} =
        ast =
        quote do
          @spec config() :: %{atom() => term()}
        end

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :config
      assert result.arity == 0
    end
  end

  # ===========================================================================
  # Callback Detection Tests
  # ===========================================================================

  describe "callback?/1" do
    test "returns true for @callback" do
      ast = {:@, [], [{:callback, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      assert FunctionSpec.callback?(ast)
    end

    test "returns false for @spec" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      refute FunctionSpec.callback?(ast)
    end

    test "returns false for @macrocallback" do
      ast = {:@, [], [{:macrocallback, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      refute FunctionSpec.callback?(ast)
    end
  end

  describe "macrocallback?/1" do
    test "returns true for @macrocallback" do
      ast = {:@, [], [{:macrocallback, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      assert FunctionSpec.macrocallback?(ast)
    end

    test "returns false for @callback" do
      ast = {:@, [], [{:callback, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      refute FunctionSpec.macrocallback?(ast)
    end
  end

  describe "optional_callbacks?/1" do
    test "returns true for @optional_callbacks" do
      ast = {:@, [], [{:optional_callbacks, [], [[foo: 1, bar: 2]]}]}
      assert FunctionSpec.optional_callbacks?(ast)
    end

    test "returns false for @callback" do
      ast = {:@, [], [{:callback, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      refute FunctionSpec.optional_callbacks?(ast)
    end
  end

  describe "any_spec?/1" do
    test "returns true for @spec" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      assert FunctionSpec.any_spec?(ast)
    end

    test "returns true for @callback" do
      ast = {:@, [], [{:callback, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      assert FunctionSpec.any_spec?(ast)
    end

    test "returns true for @macrocallback" do
      ast = {:@, [], [{:macrocallback, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      assert FunctionSpec.any_spec?(ast)
    end

    test "returns false for @optional_callbacks" do
      ast = {:@, [], [{:optional_callbacks, [], [[foo: 1]]}]}
      refute FunctionSpec.any_spec?(ast)
    end

    test "returns false for @doc" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}
      refute FunctionSpec.any_spec?(ast)
    end
  end

  # ===========================================================================
  # Callback Extraction Tests
  # ===========================================================================

  describe "extract/2 @callback" do
    test "extracts simple callback" do
      ast = {:@, [], [{:callback, [], [{:"::", [], [{:init, [], [{:term, [], []}]}, :ok]}]}]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :init
      assert result.arity == 1
      assert result.spec_type == :callback
    end

    test "extracts callback with no parameters" do
      ast = {:@, [], [{:callback, [], [{:"::", [], [{:start, [], []}, {:pid, [], []}]}]}]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :start
      assert result.arity == 0
      assert result.spec_type == :callback
    end

    test "extracts callback with when clause" do
      ast =
        {:@, [],
         [
           {:callback, [],
            [
              {:when, [],
               [
                 {:"::", [], [{:handle_call, [], [{:request, [], nil}]}, {:reply, [], nil}]},
                 [request: {:term, [], []}, reply: {:term, [], []}]
               ]}
            ]}
         ]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :handle_call
      assert result.spec_type == :callback
      assert FunctionSpec.has_when_clause?(result)
    end

    test "callback from quoted code" do
      {:@, _, [{:callback, _, _}]} =
        ast =
        quote do
          @callback init(args :: term()) :: {:ok, state :: term()} | {:error, reason :: term()}
        end

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :init
      assert result.spec_type == :callback
    end
  end

  describe "extract/2 @macrocallback" do
    test "extracts simple macrocallback" do
      ast =
        {:@, [],
         [{:macrocallback, [], [{:"::", [], [{:__using__, [], [{:opts, [], nil}]}, :ok]}]}]}

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :__using__
      assert result.arity == 1
      assert result.spec_type == :macrocallback
    end

    test "macrocallback from quoted code" do
      {:@, _, [{:macrocallback, _, _}]} =
        ast =
        quote do
          @macrocallback __using__(opts :: keyword()) :: Macro.t()
        end

      assert {:ok, result} = FunctionSpec.extract(ast)
      assert result.name == :__using__
      assert result.spec_type == :macrocallback
    end
  end

  # ===========================================================================
  # Optional Callbacks Extraction Tests
  # ===========================================================================

  describe "extract_optional_callbacks/1" do
    test "extracts optional callbacks list" do
      ast = {:@, [], [{:optional_callbacks, [], [[foo: 1, bar: 2]]}]}

      assert {:ok, result} = FunctionSpec.extract_optional_callbacks(ast)
      assert result == [foo: 1, bar: 2]
    end

    test "returns error for non-optional_callbacks" do
      ast = {:@, [], [{:callback, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}

      assert {:error, _} = FunctionSpec.extract_optional_callbacks(ast)
    end
  end

  describe "extract_all_optional_callbacks/1" do
    test "extracts from module body" do
      body =
        {:__block__, [],
         [
           {:@, [], [{:optional_callbacks, [], [[foo: 1]]}]},
           {:@, [], [{:callback, [], [{:"::", [], [{:foo, [], [{:integer, [], []}]}, :ok]}]}]},
           {:@, [], [{:optional_callbacks, [], [[bar: 2]]}]}
         ]}

      result = FunctionSpec.extract_all_optional_callbacks(body)
      assert result == [foo: 1, bar: 2]
    end

    test "returns empty list when no optional_callbacks" do
      body =
        {:__block__, [],
         [
           {:@, [], [{:callback, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
         ]}

      assert FunctionSpec.extract_all_optional_callbacks(body) == []
    end
  end

  # ===========================================================================
  # Extract All with Callbacks Tests
  # ===========================================================================

  describe "extract_all/1 with callbacks" do
    test "extracts specs and callbacks" do
      body =
        {:__block__, [],
         [
           {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]},
           {:@, [], [{:callback, [], [{:"::", [], [{:bar, [], []}, :ok]}]}]},
           {:@, [], [{:doc, [], ["docs"]}]}
         ]}

      results = FunctionSpec.extract_all(body)
      assert length(results) == 2
      assert Enum.map(results, & &1.name) == [:foo, :bar]
      assert Enum.map(results, & &1.spec_type) == [:spec, :callback]
    end

    test "extracts all spec types" do
      body =
        {:__block__, [],
         [
           {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]},
           {:@, [], [{:callback, [], [{:"::", [], [{:bar, [], []}, :ok]}]}]},
           {:@, [], [{:macrocallback, [], [{:"::", [], [{:baz, [], [{:opts, [], nil}]}, :ok]}]}]}
         ]}

      results = FunctionSpec.extract_all(body)
      assert length(results) == 3
      assert Enum.map(results, & &1.spec_type) == [:spec, :callback, :macrocallback]
    end
  end

  # ===========================================================================
  # spec_type Field Tests
  # ===========================================================================

  describe "spec_type field" do
    test "defaults to :spec for @spec" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      {:ok, result} = FunctionSpec.extract(ast)
      assert result.spec_type == :spec
    end

    test "is :callback for @callback" do
      ast = {:@, [], [{:callback, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      {:ok, result} = FunctionSpec.extract(ast)
      assert result.spec_type == :callback
    end

    test "is :macrocallback for @macrocallback" do
      ast = {:@, [], [{:macrocallback, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      {:ok, result} = FunctionSpec.extract(ast)
      assert result.spec_type == :macrocallback
    end
  end
end
