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
      assert length(result.elements) == 1
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
      {:ok, result} = TypeExpression.parse({:{}, [], [{:atom, [], []}, {:integer, [], []}, {:binary, [], []}]})
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
      {:ok, result} = TypeExpression.parse({:%{}, [], [{{:required, [], [{:atom, [], []}]}, {:term, [], []}}]})
      assert result.kind == :map
      pair = hd(result.elements)
      assert pair.required == true
    end

    test "parses optional key" do
      {:ok, result} = TypeExpression.parse({:%{}, [], [{{:optional, [], [{:atom, [], []}]}, {:term, [], []}}]})
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
      {:ok, result} = TypeExpression.parse([{:->, [], [[{:integer, [], []}, {:atom, [], []}], {:binary, [], []}]}])
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
      assert length(result.elements) == 1
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
