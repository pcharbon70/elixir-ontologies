defmodule ElixirOntologies.Extractors.TypeExpressionTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.TypeExpression

  doctest TypeExpression

  # ===========================================================================
  # Basic Type Tests
  # ===========================================================================

  describe "parse/1 basic types" do
    test "parses atom()" do
      {:ok, result} = TypeExpression.parse({:atom, [], []})
      assert result.kind == :basic
      assert result.name == :atom
    end

    test "parses integer()" do
      {:ok, result} = TypeExpression.parse({:integer, [], []})
      assert result.kind == :basic
      assert result.name == :integer
    end

    test "parses binary()" do
      {:ok, result} = TypeExpression.parse({:binary, [], []})
      assert result.kind == :basic
      assert result.name == :binary
    end

    test "parses any()" do
      {:ok, result} = TypeExpression.parse({:any, [], []})
      assert result.kind == :basic
      assert result.name == :any
    end

    test "parses term()" do
      {:ok, result} = TypeExpression.parse({:term, [], []})
      assert result.kind == :basic
      assert result.name == :term
    end

    test "parses boolean()" do
      {:ok, result} = TypeExpression.parse({:boolean, [], []})
      assert result.kind == :basic
      assert result.name == :boolean
    end

    test "parses float()" do
      {:ok, result} = TypeExpression.parse({:float, [], []})
      assert result.kind == :basic
      assert result.name == :float
    end

    test "parses parameterized list(element)" do
      {:ok, result} = TypeExpression.parse({:list, [], [{:atom, [], []}]})
      assert result.kind == :basic
      assert result.name == :list
      assert result.metadata.parameterized == true
      assert result.metadata.param_count == 1
      assert length(result.elements) == 1
    end

    test "parameterized type parameters have position tracking" do
      {:ok, result} = TypeExpression.parse({:list, [], [{:integer, [], []}]})
      assert result.metadata.param_count == 1
      param = hd(result.elements)
      assert param.metadata.param_position == 0
    end

    test "parses map(key, value) with two parameters" do
      {:ok, result} = TypeExpression.parse({:map, [], [{:atom, [], []}, {:term, [], []}]})
      assert result.kind == :basic
      assert result.name == :map
      assert result.metadata.parameterized == true
      assert result.metadata.param_count == 2
      assert length(result.elements) == 2

      [key_param, value_param] = result.elements
      assert key_param.metadata.param_position == 0
      assert key_param.name == :atom
      assert value_param.metadata.param_position == 1
      assert value_param.name == :term
    end

    test "parses keyword(value) parameterized type" do
      {:ok, result} = TypeExpression.parse({:keyword, [], [{:binary, [], []}]})
      assert result.kind == :basic
      assert result.name == :keyword
      assert result.metadata.parameterized == true
      assert result.metadata.param_count == 1
      param = hd(result.elements)
      assert param.name == :binary
      assert param.metadata.param_position == 0
    end

    test "parses nested parameterized types list(map(k, v))" do
      # list(map(atom(), integer()))
      inner_map = {:map, [], [{:atom, [], []}, {:integer, [], []}]}
      {:ok, result} = TypeExpression.parse({:list, [], [inner_map]})

      assert result.kind == :basic
      assert result.name == :list
      assert result.metadata.parameterized == true
      assert result.metadata.param_count == 1

      # Check the inner map
      inner = hd(result.elements)
      assert inner.kind == :basic
      assert inner.name == :map
      assert inner.metadata.parameterized == true
      assert inner.metadata.param_count == 2
      assert inner.metadata.param_position == 0

      # Check inner map parameters
      [key, value] = inner.elements
      assert key.name == :atom
      assert key.metadata.param_position == 0
      assert value.name == :integer
      assert value.metadata.param_position == 1
    end

    test "non-parameterized basic type has no param_count" do
      {:ok, result} = TypeExpression.parse({:atom, [], []})
      assert result.kind == :basic
      refute Map.has_key?(result.metadata, :parameterized)
      refute Map.has_key?(result.metadata, :param_count)
    end
  end

  # ===========================================================================
  # Literal Type Tests
  # ===========================================================================

  describe "parse/1 literal types" do
    test "parses literal atom :ok" do
      {:ok, result} = TypeExpression.parse(:ok)
      assert result.kind == :literal
      assert result.name == :ok
      assert result.metadata.literal_type == :atom
    end

    test "parses literal atom :error" do
      {:ok, result} = TypeExpression.parse(:error)
      assert result.kind == :literal
      assert result.name == :error
    end

    test "parses literal true" do
      {:ok, result} = TypeExpression.parse(true)
      assert result.kind == :literal
      assert result.name == true
    end

    test "parses literal false" do
      {:ok, result} = TypeExpression.parse(false)
      assert result.kind == :literal
      assert result.name == false
    end

    test "parses literal nil" do
      {:ok, result} = TypeExpression.parse(nil)
      assert result.kind == :literal
      assert result.name == nil
    end

    test "parses literal integer" do
      {:ok, result} = TypeExpression.parse(42)
      assert result.kind == :literal
      assert result.name == 42
      assert result.metadata.literal_type == :integer
    end

    test "parses literal float" do
      {:ok, result} = TypeExpression.parse(3.14)
      assert result.kind == :literal
      assert result.name == 3.14
      assert result.metadata.literal_type == :float
    end
  end

  # ===========================================================================
  # Union Type Tests
  # ===========================================================================

  describe "parse/1 union types" do
    test "parses simple union :ok | :error" do
      {:ok, result} = TypeExpression.parse({:|, [], [:ok, :error]})
      assert result.kind == :union
      assert length(result.elements) == 2
      assert Enum.at(result.elements, 0).name == :ok
      assert Enum.at(result.elements, 1).name == :error
    end

    test "parses nested union :ok | :error | :pending" do
      {:ok, result} = TypeExpression.parse({:|, [], [:ok, {:|, [], [:error, :pending]}]})
      assert result.kind == :union
      assert length(result.elements) == 3
    end

    test "parses union with basic types" do
      union = {:|, [], [{:atom, [], []}, {:integer, [], []}]}
      {:ok, result} = TypeExpression.parse(union)
      assert result.kind == :union
      assert Enum.at(result.elements, 0).kind == :basic
      assert Enum.at(result.elements, 1).kind == :basic
    end

    test "union metadata includes element count" do
      {:ok, result} = TypeExpression.parse({:|, [], [:ok, :error]})
      assert result.metadata.element_count == 2
    end

    test "union members have position tracking" do
      {:ok, result} = TypeExpression.parse({:|, [], [:ok, :error]})
      assert Enum.at(result.elements, 0).metadata.union_position == 0
      assert Enum.at(result.elements, 1).metadata.union_position == 1
    end

    test "nested union members have correct positions after flattening" do
      # :a | :b | :c | :d parsed as nested unions
      {:ok, result} =
        TypeExpression.parse({:|, [], [:a, {:|, [], [:b, {:|, [], [:c, :d]}]}]})

      assert result.metadata.element_count == 4
      assert Enum.at(result.elements, 0).metadata.union_position == 0
      assert Enum.at(result.elements, 0).name == :a
      assert Enum.at(result.elements, 1).metadata.union_position == 1
      assert Enum.at(result.elements, 1).name == :b
      assert Enum.at(result.elements, 2).metadata.union_position == 2
      assert Enum.at(result.elements, 2).name == :c
      assert Enum.at(result.elements, 3).metadata.union_position == 3
      assert Enum.at(result.elements, 3).name == :d
    end

    test "union with 5+ members preserves all positions" do
      # Build a deeply nested union: :a | :b | :c | :d | :e
      union =
        {:|, [],
         [
           :a,
           {:|, [], [:b, {:|, [], [:c, {:|, [], [:d, :e]}]}]}
         ]}

      {:ok, result} = TypeExpression.parse(union)
      assert result.metadata.element_count == 5

      Enum.each(0..4, fn i ->
        assert Enum.at(result.elements, i).metadata.union_position == i
      end)
    end
  end

  # ===========================================================================
  # Tuple Type Tests
  # ===========================================================================

  describe "parse/1 tuple types" do
    test "parses 2-tuple {atom(), integer()}" do
      {:ok, result} = TypeExpression.parse({{:atom, [], []}, {:integer, [], []}})
      assert result.kind == :tuple
      assert length(result.elements) == 2
      assert result.metadata.arity == 2
    end

    test "parses tagged tuple {:ok, term()}" do
      {:ok, result} = TypeExpression.parse({:ok, {:term, [], []}})
      assert result.kind == :tuple
      assert length(result.elements) == 2
      assert result.metadata.tagged == true
      assert result.metadata.tag == :ok
    end

    test "parses empty tuple {}" do
      {:ok, result} = TypeExpression.parse({:{}, [], []})
      assert result.kind == :tuple
      assert result.elements == []
      assert result.metadata.arity == 0
    end

    test "parses 3-tuple" do
      {:ok, result} =
        TypeExpression.parse({:{}, [], [{:atom, [], []}, {:integer, [], []}, {:binary, [], []}]})

      assert result.kind == :tuple
      assert length(result.elements) == 3
      assert result.metadata.arity == 3
    end
  end

  # ===========================================================================
  # List Type Tests
  # ===========================================================================

  describe "parse/1 list types" do
    test "parses list type [atom()]" do
      {:ok, result} = TypeExpression.parse([{:atom, [], []}])
      assert result.kind == :list
      assert length(result.elements) == 1
      assert Enum.at(result.elements, 0).kind == :basic
    end

    test "parses empty list []" do
      {:ok, result} = TypeExpression.parse([])
      assert result.kind == :list
      assert result.elements == []
      assert result.metadata.empty == true
    end

    test "parses nonempty list [...]" do
      {:ok, result} = TypeExpression.parse([{:..., [], nil}])
      assert result.kind == :list
      assert result.metadata.nonempty == true
    end
  end

  # ===========================================================================
  # Map Type Tests
  # ===========================================================================

  describe "parse/1 map types" do
    test "parses empty map %{}" do
      {:ok, result} = TypeExpression.parse({:%{}, [], []})
      assert result.kind == :map
      assert result.elements == []
      assert result.metadata.empty == true
    end

    test "parses map with arrow syntax %{atom() => term()}" do
      {:ok, result} = TypeExpression.parse({:%{}, [], [{{:atom, [], []}, {:term, [], []}}]})
      assert result.kind == :map
      assert length(result.elements) == 1
    end

    test "parses map with keyword syntax %{key: atom()}" do
      {:ok, result} = TypeExpression.parse({:%{}, [], [key: {:atom, [], []}]})
      assert result.kind == :map
      assert length(result.elements) == 1
      pair = hd(result.elements)
      assert pair.keyword_style == true
    end

    test "parses required key" do
      {:ok, result} =
        TypeExpression.parse({:%{}, [], [{{:required, [], [{:atom, [], []}]}, {:term, [], []}}]})

      assert result.kind == :map
      pair = hd(result.elements)
      assert pair.required == true
    end

    test "parses optional key" do
      {:ok, result} =
        TypeExpression.parse({:%{}, [], [{{:optional, [], [{:atom, [], []}]}, {:term, [], []}}]})

      assert result.kind == :map
      pair = hd(result.elements)
      assert pair.required == false
    end
  end

  # ===========================================================================
  # Function Type Tests
  # ===========================================================================

  describe "parse/1 function types" do
    test "parses function type (integer() -> atom())" do
      {:ok, result} = TypeExpression.parse([{:->, [], [[{:integer, [], []}], {:atom, [], []}]}])
      assert result.kind == :function
      assert length(result.param_types) == 1
      assert result.return_type.kind == :basic
    end

    test "parses zero-arity function (-> atom())" do
      {:ok, result} = TypeExpression.parse([{:->, [], [[], {:atom, [], []}]}])
      assert result.kind == :function
      assert result.param_types == []
      assert result.metadata.arity == 0
    end

    test "parses multi-param function" do
      {:ok, result} =
        TypeExpression.parse([
          {:->, [], [[{:integer, [], []}, {:atom, [], []}], {:binary, [], []}]}
        ])

      assert result.kind == :function
      assert length(result.param_types) == 2
      assert result.metadata.arity == 2
    end

    test "parses any-arity function (... -> atom())" do
      {:ok, result} = TypeExpression.parse([{:->, [], [[{:..., [], nil}], {:atom, [], []}]}])
      assert result.kind == :function
      assert result.param_types == :any
      assert result.metadata.arity == :any
    end

    test "parses union of function types (multiple arities)" do
      # (-> atom()) | (integer() -> atom())
      ast =
        {:|, [],
         [
           [{:->, [], [[], {:atom, [], []}]}],
           [{:->, [], [[{:integer, [], []}], {:atom, [], []}]}]
         ]}

      {:ok, result} = TypeExpression.parse(ast)

      assert result.kind == :union
      assert length(result.elements) == 2

      [zero_arity, one_arity] = result.elements

      assert zero_arity.kind == :function
      assert TypeExpression.function_arity(zero_arity) == 0

      assert one_arity.kind == :function
      assert TypeExpression.function_arity(one_arity) == 1
    end

    test "parses nested function type (function returning function)" do
      # (integer() -> (atom() -> binary()))
      inner_func = [{:->, [], [[{:atom, [], []}], {:binary, [], []}]}]
      ast = [{:->, [], [[{:integer, [], []}], inner_func]}]

      {:ok, result} = TypeExpression.parse(ast)

      assert result.kind == :function
      assert length(result.param_types) == 1
      assert hd(result.param_types).kind == :basic
      assert hd(result.param_types).name == :integer

      # Return type is also a function
      assert result.return_type.kind == :function
      assert TypeExpression.function_arity(result.return_type) == 1
      assert result.return_type.return_type.name == :binary
    end

    test "parses function type with complex parameter types" do
      # ({integer(), atom()} -> [binary()])
      tuple_param = {{:integer, [], []}, {:atom, [], []}}
      list_return = [{:binary, [], []}]
      ast = [{:->, [], [[tuple_param], list_return]}]

      {:ok, result} = TypeExpression.parse(ast)

      assert result.kind == :function
      [param] = result.param_types
      assert param.kind == :tuple
      assert length(param.elements) == 2

      assert result.return_type.kind == :list
    end

    test "parses function type with union parameter" do
      # (integer() | atom() -> binary())
      union_param = {:|, [], [{:integer, [], []}, {:atom, [], []}]}
      ast = [{:->, [], [[union_param], {:binary, [], []}]}]

      {:ok, result} = TypeExpression.parse(ast)

      assert result.kind == :function
      [param] = result.param_types
      assert param.kind == :union
      assert length(param.elements) == 2
    end

    test "parses function type with union return" do
      # (integer() -> :ok | :error)
      ast = [{:->, [], [[{:integer, [], []}], {:|, [], [:ok, :error]}]}]

      {:ok, result} = TypeExpression.parse(ast)

      assert result.kind == :function
      assert result.return_type.kind == :union
      assert length(result.return_type.elements) == 2
    end
  end

  describe "function type helpers" do
    test "param_types/1 returns parameter list for function" do
      {:ok, result} =
        TypeExpression.parse([
          {:->, [], [[{:integer, [], []}, {:atom, [], []}], {:binary, [], []}]}
        ])

      params = TypeExpression.param_types(result)
      assert length(params) == 2
      assert Enum.at(params, 0).name == :integer
      assert Enum.at(params, 1).name == :atom
    end

    test "param_types/1 returns :any for any-arity function" do
      {:ok, result} = TypeExpression.parse([{:->, [], [[{:..., [], nil}], {:atom, [], []}]}])
      assert TypeExpression.param_types(result) == :any
    end

    test "param_types/1 returns nil for non-function" do
      {:ok, result} = TypeExpression.parse({:atom, [], []})
      assert TypeExpression.param_types(result) == nil
    end

    test "return_type/1 returns return type for function" do
      {:ok, result} = TypeExpression.parse([{:->, [], [[{:integer, [], []}], {:atom, [], []}]}])
      return = TypeExpression.return_type(result)
      assert return.kind == :basic
      assert return.name == :atom
    end

    test "return_type/1 returns nil for non-function" do
      {:ok, result} = TypeExpression.parse({:atom, [], []})
      assert TypeExpression.return_type(result) == nil
    end

    test "function_arity/1 returns arity for fixed-arity function" do
      {:ok, result} =
        TypeExpression.parse([
          {:->, [], [[{:integer, [], []}, {:atom, [], []}], {:binary, [], []}]}
        ])

      assert TypeExpression.function_arity(result) == 2
    end

    test "function_arity/1 returns 0 for zero-arity function" do
      {:ok, result} = TypeExpression.parse([{:->, [], [[], {:atom, [], []}]}])
      assert TypeExpression.function_arity(result) == 0
    end

    test "function_arity/1 returns :any for any-arity function" do
      {:ok, result} = TypeExpression.parse([{:->, [], [[{:..., [], nil}], {:atom, [], []}]}])
      assert TypeExpression.function_arity(result) == :any
    end

    test "function_arity/1 returns nil for non-function" do
      {:ok, result} = TypeExpression.parse({:atom, [], []})
      assert TypeExpression.function_arity(result) == nil
    end
  end

  # ===========================================================================
  # Remote Type Tests
  # ===========================================================================

  describe "parse/1 remote types" do
    test "parses String.t()" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :remote
      assert result.name == :t
      assert result.module == [:String]
    end

    test "parses GenServer.on_start()" do
      ast = {{:., [], [{:__aliases__, [], [:GenServer]}, :on_start]}, [], []}
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :remote
      assert result.name == :on_start
      assert result.module == [:GenServer]
    end

    test "parses nested module type MyApp.Accounts.User.t()" do
      ast = {{:., [], [{:__aliases__, [], [:MyApp, :Accounts, :User]}, :t]}, [], []}
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :remote
      assert result.name == :t
      assert result.module == [:MyApp, :Accounts, :User]
    end

    test "parses parameterized remote type Enumerable.t(element)" do
      ast = {{:., [], [{:__aliases__, [], [:Enumerable]}, :t]}, [], [{:element, [], nil}]}
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :remote
      assert result.name == :t
      assert result.metadata.parameterized == true
      assert result.metadata.param_count == 1
      assert length(result.elements) == 1
      param = hd(result.elements)
      assert param.metadata.param_position == 0
    end

    test "non-parameterized remote type has parameterized: false" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}
      {:ok, result} = TypeExpression.parse(ast)
      assert result.metadata.parameterized == false
      refute Map.has_key?(result.metadata, :param_count)
    end

    test "parses remote type with multiple parameters" do
      # Map.t(key, value) equivalent
      ast =
        {{:., [], [{:__aliases__, [], [:Map]}, :t]}, [],
         [{:key, [], nil}, {:value, [], nil}]}

      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :remote
      assert result.name == :t
      assert result.metadata.parameterized == true
      assert result.metadata.param_count == 2

      [key_param, value_param] = result.elements
      assert key_param.name == :key
      assert key_param.metadata.param_position == 0
      assert value_param.name == :value
      assert value_param.metadata.param_position == 1
    end

    test "non-parameterized remote type has arity 0" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}
      {:ok, result} = TypeExpression.parse(ast)
      assert result.metadata.arity == 0
    end

    test "parameterized remote type has arity equal to param_count" do
      ast = {{:., [], [{:__aliases__, [], [:Enumerable]}, :t]}, [], [{:element, [], nil}]}
      {:ok, result} = TypeExpression.parse(ast)
      assert result.metadata.arity == 1
      assert result.metadata.arity == result.metadata.param_count
    end

    test "multi-param remote type has correct arity" do
      ast =
        {{:., [], [{:__aliases__, [], [:Map]}, :t]}, [],
         [{:key, [], nil}, {:value, [], nil}]}

      {:ok, result} = TypeExpression.parse(ast)
      assert result.metadata.arity == 2
    end

    test "module_iri/1 returns IRI for simple module" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}
      {:ok, result} = TypeExpression.parse(ast)
      assert TypeExpression.module_iri(result) == "Elixir.String"
    end

    test "module_iri/1 returns IRI for nested module" do
      ast = {{:., [], [{:__aliases__, [], [:MyApp, :Accounts, :User]}, :t]}, [], []}
      {:ok, result} = TypeExpression.parse(ast)
      assert TypeExpression.module_iri(result) == "Elixir.MyApp.Accounts.User"
    end

    test "module_iri/1 returns nil for non-remote types" do
      {:ok, result} = TypeExpression.parse({:atom, [], []})
      assert TypeExpression.module_iri(result) == nil
    end

    test "type_iri/1 returns IRI for non-parameterized type" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}
      {:ok, result} = TypeExpression.parse(ast)
      assert TypeExpression.type_iri(result) == "Elixir.String#t/0"
    end

    test "type_iri/1 returns IRI with arity for parameterized type" do
      ast = {{:., [], [{:__aliases__, [], [:Enumerable]}, :t]}, [], [{:element, [], nil}]}
      {:ok, result} = TypeExpression.parse(ast)
      assert TypeExpression.type_iri(result) == "Elixir.Enumerable#t/1"
    end

    test "type_iri/1 handles multi-param types" do
      ast =
        {{:., [], [{:__aliases__, [], [:Map]}, :t]}, [],
         [{:key, [], nil}, {:value, [], nil}]}

      {:ok, result} = TypeExpression.parse(ast)
      assert TypeExpression.type_iri(result) == "Elixir.Map#t/2"
    end

    test "type_iri/1 handles nested module with non-t type" do
      ast = {{:., [], [{:__aliases__, [], [:GenServer]}, :on_start]}, [], []}
      {:ok, result} = TypeExpression.parse(ast)
      assert TypeExpression.type_iri(result) == "Elixir.GenServer#on_start/0"
    end

    test "type_iri/1 returns nil for non-remote types" do
      {:ok, result} = TypeExpression.parse({:atom, [], []})
      assert TypeExpression.type_iri(result) == nil
    end
  end

  # ===========================================================================
  # Struct Type Tests
  # ===========================================================================

  describe "parse/1 struct types" do
    test "parses %User{}" do
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :struct
      assert result.module == [:User]
    end

    test "parses %MyApp.Accounts.User{}" do
      ast = {:%, [], [{:__aliases__, [], [:MyApp, :Accounts, :User]}, {:%{}, [], []}]}
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :struct
      assert result.module == [:MyApp, :Accounts, :User]
    end
  end

  # ===========================================================================
  # Type Variable Tests
  # ===========================================================================

  describe "parse/1 type variables" do
    test "parses type variable a" do
      {:ok, result} = TypeExpression.parse({:a, [], nil})
      assert result.kind == :variable
      assert result.name == :a
    end

    test "parses type variable element" do
      {:ok, result} = TypeExpression.parse({:element, [], nil})
      assert result.kind == :variable
      assert result.name == :element
    end

    test "parses type variable with Elixir context" do
      {:ok, result} = TypeExpression.parse({:t, [], Elixir})
      assert result.kind == :variable
      assert result.name == :t
    end
  end

  # ===========================================================================
  # Type Variable Constraint Tests
  # ===========================================================================

  describe "parse_with_constraints/2" do
    test "parses type variable with constraint" do
      constraints = %{a: {:integer, [], []}}
      {:ok, result} = TypeExpression.parse_with_constraints({:a, [], nil}, constraints)

      assert result.kind == :variable
      assert result.name == :a
      assert result.metadata.constrained == true
      assert result.metadata.constraint.kind == :basic
      assert result.metadata.constraint.name == :integer
    end

    test "parses type variable without matching constraint" do
      constraints = %{a: {:integer, [], []}}
      {:ok, result} = TypeExpression.parse_with_constraints({:b, [], nil}, constraints)

      assert result.kind == :variable
      assert result.name == :b
      assert result.metadata.constrained == false
      refute Map.has_key?(result.metadata, :constraint)
    end

    test "parses basic type unchanged with constraints" do
      constraints = %{a: {:integer, [], []}}
      {:ok, result} = TypeExpression.parse_with_constraints({:atom, [], []}, constraints)

      assert result.kind == :basic
      assert result.name == :atom
    end

    test "propagates constraints through union types" do
      constraints = %{a: {:integer, [], []}, b: {:atom, [], []}}
      ast = {:|, [], [{:a, [], nil}, {:b, [], nil}]}
      {:ok, result} = TypeExpression.parse_with_constraints(ast, constraints)

      assert result.kind == :union
      [first, second] = result.elements

      assert first.kind == :variable
      assert first.metadata.constrained == true
      assert first.metadata.constraint.name == :integer

      assert second.kind == :variable
      assert second.metadata.constrained == true
      assert second.metadata.constraint.name == :atom
    end

    test "propagates constraints through tuple types" do
      constraints = %{a: {:integer, [], []}}
      ast = {{:a, [], nil}, {:string, [], []}}
      {:ok, result} = TypeExpression.parse_with_constraints(ast, constraints)

      assert result.kind == :tuple
      [first, second] = result.elements

      assert first.kind == :variable
      assert first.metadata.constrained == true

      assert second.kind == :basic
      assert second.name == :string
    end

    test "propagates constraints through list types" do
      constraints = %{element: {:integer, [], []}}
      ast = [{:element, [], nil}]
      {:ok, result} = TypeExpression.parse_with_constraints(ast, constraints)

      assert result.kind == :list
      [element] = result.elements

      assert element.kind == :variable
      assert element.metadata.constrained == true
      assert element.metadata.constraint.name == :integer
    end

    test "propagates constraints through function types" do
      constraints = %{a: {:integer, [], []}, b: {:atom, [], []}}
      # (a) -> b
      ast = [{:->, [], [[{:a, [], nil}], {:b, [], nil}]}]
      {:ok, result} = TypeExpression.parse_with_constraints(ast, constraints)

      assert result.kind == :function
      [param] = result.param_types

      assert param.kind == :variable
      assert param.metadata.constrained == true
      assert param.metadata.constraint.name == :integer

      assert result.return_type.kind == :variable
      assert result.return_type.metadata.constrained == true
      assert result.return_type.metadata.constraint.name == :atom
    end

    test "propagates constraints through parameterized types" do
      constraints = %{a: {:integer, [], []}}
      # list(a)
      ast = {:list, [], [{:a, [], nil}]}
      {:ok, result} = TypeExpression.parse_with_constraints(ast, constraints)

      assert result.kind == :basic
      assert result.name == :list
      [param] = result.elements

      assert param.kind == :variable
      assert param.metadata.constrained == true
      assert param.metadata.constraint.name == :integer
    end

    test "handles empty constraints map" do
      {:ok, result} = TypeExpression.parse_with_constraints({:a, [], nil}, %{})

      assert result.kind == :variable
      assert result.name == :a
      # Empty constraints map delegates to regular parse
    end

    test "parses remote type with constrained parameters" do
      constraints = %{element: {:integer, [], []}}
      # Enumerable.t(element)
      ast = {{:., [], [{:__aliases__, [], [:Enumerable]}, :t]}, [], [{:element, [], nil}]}
      {:ok, result} = TypeExpression.parse_with_constraints(ast, constraints)

      assert result.kind == :remote
      assert result.name == :t
      [param] = result.elements

      assert param.kind == :variable
      assert param.metadata.constrained == true
      assert param.metadata.constraint.name == :integer
    end

    test "constraint type can be a union" do
      # when a: atom() | integer()
      constraints = %{a: {:|, [], [{:atom, [], []}, {:integer, [], []}]}}
      {:ok, result} = TypeExpression.parse_with_constraints({:a, [], nil}, constraints)

      assert result.kind == :variable
      assert result.metadata.constrained == true
      assert result.metadata.constraint.kind == :union
      assert length(result.metadata.constraint.elements) == 2
    end

    test "constraint type can be a remote type" do
      # when a: String.t()
      constraints = %{a: {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}}
      {:ok, result} = TypeExpression.parse_with_constraints({:a, [], nil}, constraints)

      assert result.kind == :variable
      assert result.metadata.constrained == true
      assert result.metadata.constraint.kind == :remote
      assert result.metadata.constraint.name == :t
      assert result.metadata.constraint.module == [:String]
    end
  end

  describe "constrained?/1" do
    test "returns true for constrained type variable" do
      constraints = %{a: {:integer, [], []}}
      {:ok, result} = TypeExpression.parse_with_constraints({:a, [], nil}, constraints)
      assert TypeExpression.constrained?(result)
    end

    test "returns false for unconstrained type variable" do
      {:ok, result} = TypeExpression.parse_with_constraints({:b, [], nil}, %{a: {:integer, [], []}})
      refute TypeExpression.constrained?(result)
    end

    test "returns false for regular parse" do
      {:ok, result} = TypeExpression.parse({:a, [], nil})
      refute TypeExpression.constrained?(result)
    end

    test "returns false for non-variable types" do
      {:ok, result} = TypeExpression.parse({:atom, [], []})
      refute TypeExpression.constrained?(result)
    end
  end

  describe "constraint_type/1" do
    test "returns constraint for constrained type variable" do
      constraints = %{a: {:integer, [], []}}
      {:ok, result} = TypeExpression.parse_with_constraints({:a, [], nil}, constraints)
      constraint = TypeExpression.constraint_type(result)

      assert constraint.kind == :basic
      assert constraint.name == :integer
    end

    test "returns nil for unconstrained type variable" do
      {:ok, result} = TypeExpression.parse_with_constraints({:b, [], nil}, %{a: {:integer, [], []}})
      assert TypeExpression.constraint_type(result) == nil
    end

    test "returns nil for regular parse" do
      {:ok, result} = TypeExpression.parse({:a, [], nil})
      assert TypeExpression.constraint_type(result) == nil
    end

    test "returns nil for non-variable types" do
      {:ok, result} = TypeExpression.parse({:atom, [], []})
      assert TypeExpression.constraint_type(result) == nil
    end
  end

  # ===========================================================================
  # Helper Function Tests
  # ===========================================================================

  describe "helper functions" do
    test "basic?/1" do
      {:ok, result} = TypeExpression.parse({:atom, [], []})
      assert TypeExpression.basic?(result)
    end

    test "union?/1" do
      {:ok, result} = TypeExpression.parse({:|, [], [:ok, :error]})
      assert TypeExpression.union?(result)
    end

    test "tuple?/1" do
      {:ok, result} = TypeExpression.parse({{:atom, [], []}, {:integer, [], []}})
      assert TypeExpression.tuple?(result)
    end

    test "list?/1" do
      {:ok, result} = TypeExpression.parse([{:atom, [], []}])
      assert TypeExpression.list?(result)
    end

    test "map?/1" do
      {:ok, result} = TypeExpression.parse({:%{}, [], []})
      assert TypeExpression.map?(result)
    end

    test "function?/1" do
      {:ok, result} = TypeExpression.parse([{:->, [], [[{:integer, [], []}], {:atom, [], []}]}])
      assert TypeExpression.function?(result)
    end

    test "remote?/1" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}
      {:ok, result} = TypeExpression.parse(ast)
      assert TypeExpression.remote?(result)
    end

    test "struct?/1" do
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], []}]}
      {:ok, result} = TypeExpression.parse(ast)
      assert TypeExpression.struct?(result)
    end

    test "variable?/1" do
      {:ok, result} = TypeExpression.parse({:a, [], nil})
      assert TypeExpression.variable?(result)
    end

    test "parameterized?/1 returns true for parameterized basic type" do
      {:ok, result} = TypeExpression.parse({:list, [], [{:integer, [], []}]})
      assert TypeExpression.parameterized?(result)
    end

    test "parameterized?/1 returns true for parameterized remote type" do
      ast = {{:., [], [{:__aliases__, [], [:Enumerable]}, :t]}, [], [{:element, [], nil}]}
      {:ok, result} = TypeExpression.parse(ast)
      assert TypeExpression.parameterized?(result)
    end

    test "parameterized?/1 returns false for non-parameterized types" do
      {:ok, result} = TypeExpression.parse({:atom, [], []})
      refute TypeExpression.parameterized?(result)
    end

    test "literal?/1" do
      {:ok, result} = TypeExpression.parse(:ok)
      assert TypeExpression.literal?(result)
    end

    test "basic_type_names/0 includes common types" do
      names = TypeExpression.basic_type_names()
      assert :atom in names
      assert :integer in names
      assert :binary in names
      assert :any in names
      assert :term in names
    end
  end

  # ===========================================================================
  # Complex/Nested Type Tests
  # ===========================================================================

  describe "complex nested types" do
    test "parses {:ok, term()} | {:error, String.t()}" do
      error_tuple = {:error, {{:., [], [{:__aliases__, [], [:String]}, :t]}, [], []}}
      union = {:|, [], [{:ok, {:term, [], []}}, error_tuple]}
      {:ok, result} = TypeExpression.parse(union)

      assert result.kind == :union
      assert length(result.elements) == 2

      ok_tuple = Enum.at(result.elements, 0)
      assert ok_tuple.kind == :tuple
      assert ok_tuple.metadata.tag == :ok

      error_part = Enum.at(result.elements, 1)
      assert error_part.kind == :tuple
    end

    test "parses [%{atom() => term()}]" do
      map_type = {:%{}, [], [{{:atom, [], []}, {:term, [], []}}]}
      {:ok, result} = TypeExpression.parse([map_type])

      assert result.kind == :list
      assert length(result.elements) == 1
      assert Enum.at(result.elements, 0).kind == :map
    end

    test "parses (atom(), integer() -> {:ok, term()} | :error)" do
      return_type = {:|, [], [{:ok, {:term, [], []}}, :error]}
      func = [{:->, [], [[{:atom, [], []}, {:integer, [], []}], return_type]}]
      {:ok, result} = TypeExpression.parse(func)

      assert result.kind == :function
      assert length(result.param_types) == 2
      assert result.return_type.kind == :union
    end
  end

  # ===========================================================================
  # Integration Tests with quote
  # ===========================================================================

  describe "integration with quote" do
    test "parses quoted atom() type" do
      ast = quote(do: atom())
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :basic
      assert result.name == :atom
    end

    test "parses quoted union type" do
      ast = quote(do: :ok | :error)
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :union
    end

    test "parses quoted tuple type" do
      ast = quote(do: {atom(), integer()})
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :tuple
    end

    test "parses quoted list type" do
      ast = quote(do: [atom()])
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :list
    end

    test "parses quoted map type" do
      ast = quote(do: %{atom() => term()})
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :map
    end

    test "parses quoted remote type" do
      ast = quote(do: String.t())
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :remote
    end

    test "parses quoted function type" do
      ast = quote(do: (integer() -> atom()))
      {:ok, result} = TypeExpression.parse(ast)
      assert result.kind == :function
    end
  end
end
