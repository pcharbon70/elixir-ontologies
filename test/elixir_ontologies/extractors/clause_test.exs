defmodule ElixirOntologies.Extractors.ClauseTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Clause

  doctest Clause

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "clause?/1" do
    test "returns true for def" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      assert Clause.clause?(ast)
    end

    test "returns true for defp" do
      ast = {:defp, [], [{:foo, [], nil}, [do: :ok]]}
      assert Clause.clause?(ast)
    end

    test "returns false for defmodule" do
      ast = {:defmodule, [], [{:__aliases__, [], [:Foo]}, [do: nil]]}
      refute Clause.clause?(ast)
    end

    test "returns false for non-AST values" do
      refute Clause.clause?(:not_a_clause)
      refute Clause.clause?(123)
    end
  end

  # ===========================================================================
  # Basic Extraction Tests
  # ===========================================================================

  describe "extract/2 basic clauses" do
    test "extracts simple public function clause" do
      ast = {:def, [], [{:hello, [], nil}, [do: :ok]]}

      assert {:ok, result} = Clause.extract(ast)
      assert result.name == :hello
      assert result.arity == 0
      assert result.visibility == :public
      assert result.order == 1
      assert result.body == :ok
    end

    test "extracts clause with one parameter" do
      ast = {:def, [], [{:greet, [], [{:name, [], nil}]}, [do: :ok]]}

      assert {:ok, result} = Clause.extract(ast)
      assert result.name == :greet
      assert result.arity == 1
      assert result.head.parameters == [{:name, [], nil}]
    end

    test "extracts clause with multiple parameters" do
      ast = {:def, [], [{:add, [], [{:a, [], nil}, {:b, [], nil}]}, [do: :ok]]}

      assert {:ok, result} = Clause.extract(ast)
      assert result.arity == 2
      assert length(result.head.parameters) == 2
    end

    test "extracts private function clause" do
      ast = {:defp, [], [{:internal, [], nil}, [do: :ok]]}

      assert {:ok, result} = Clause.extract(ast)
      assert result.visibility == :private
    end

    test "respects order option" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}

      assert {:ok, result} = Clause.extract(ast, order: 3)
      assert result.order == 3
    end
  end

  # ===========================================================================
  # Guard Clause Tests
  # ===========================================================================

  describe "extract/2 guard clauses" do
    test "extracts clause with guard" do
      ast =
        {:def, [],
         [{:when, [], [{:process, [], [{:x, [], nil}]}, {:is_integer, [], [{:x, [], nil}]}]}, [do: :ok]]}

      assert {:ok, result} = Clause.extract(ast)
      assert result.name == :process
      assert result.arity == 1
      assert result.head.guard != nil
      assert result.metadata.has_guard == true
    end

    test "has_guard? returns true for guarded clause" do
      ast =
        {:def, [],
         [{:when, [], [{:foo, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]}, [do: :ok]]}

      {:ok, clause} = Clause.extract(ast)
      assert Clause.has_guard?(clause)
    end

    test "has_guard? returns false for unguarded clause" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      {:ok, clause} = Clause.extract(ast)
      refute Clause.has_guard?(clause)
    end
  end

  # ===========================================================================
  # Bodyless Clause Tests
  # ===========================================================================

  describe "extract/2 bodyless clauses" do
    test "extracts bodyless public clause" do
      ast = {:def, [], [{:callback, [], [{:x, [], nil}]}]}

      assert {:ok, result} = Clause.extract(ast)
      assert result.name == :callback
      assert result.arity == 1
      assert result.body == nil
      assert result.metadata.bodyless == true
    end

    test "extracts bodyless private clause" do
      ast = {:defp, [], [{:internal, [], nil}]}

      assert {:ok, result} = Clause.extract(ast)
      assert result.name == :internal
      assert result.body == nil
    end

    test "extracts bodyless clause with guard" do
      ast = {:def, [], [{:when, [], [{:foo, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]}]}

      assert {:ok, result} = Clause.extract(ast)
      assert result.name == :foo
      assert result.body == nil
      assert result.head.guard != nil
    end

    test "bodyless? returns true for bodyless clause" do
      ast = {:def, [], [{:callback, [], [{:x, [], nil}]}]}
      {:ok, clause} = Clause.extract(ast)
      assert Clause.bodyless?(clause)
    end

    test "bodyless? returns false for clause with body" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      {:ok, clause} = Clause.extract(ast)
      refute Clause.bodyless?(clause)
    end
  end

  # ===========================================================================
  # Body Extraction Tests
  # ===========================================================================

  describe "extract/2 body extraction" do
    test "extracts simple body expression" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}

      assert {:ok, result} = Clause.extract(ast)
      assert result.body == :ok
    end

    test "extracts string body" do
      ast = {:def, [], [{:greet, [], nil}, [do: "hello"]]}

      assert {:ok, result} = Clause.extract(ast)
      assert result.body == "hello"
    end

    test "extracts complex body expression" do
      body = {:+, [], [1, 2]}
      ast = {:def, [], [{:add, [], nil}, [do: body]]}

      assert {:ok, result} = Clause.extract(ast)
      assert result.body == body
    end
  end

  # ===========================================================================
  # Bulk Extraction Tests
  # ===========================================================================

  describe "extract_all/1" do
    test "extracts all clauses from block" do
      body =
        {:__block__, [],
         [
           {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: 1]]},
           {:def, [], [{:bar, [], nil}, [do: 2]]},
           {:@, [], [{:doc, [], ["docs"]}]}
         ]}

      results = Clause.extract_all(body)
      assert length(results) == 2
      assert Enum.map(results, & &1.name) == [:foo, :bar]
    end

    test "extracts single clause" do
      body = {:def, [], [{:foo, [], nil}, [do: :ok]]}

      results = Clause.extract_all(body)
      assert length(results) == 1
      assert hd(results).name == :foo
    end

    test "returns empty list for nil" do
      assert Clause.extract_all(nil) == []
    end

    test "returns empty list for non-clause" do
      body = {:@, [], [{:doc, [], ["docs"]}]}
      assert Clause.extract_all(body) == []
    end

    test "maintains order in results" do
      body =
        {:__block__, [],
         [
           {:def, [], [{:first, [], nil}, [do: 1]]},
           {:def, [], [{:second, [], nil}, [do: 2]]},
           {:def, [], [{:third, [], nil}, [do: 3]]}
         ]}

      results = Clause.extract_all(body)
      assert Enum.map(results, & &1.name) == [:first, :second, :third]
      assert Enum.map(results, & &1.order) == [1, 2, 3]
    end
  end

  # ===========================================================================
  # Grouping Tests
  # ===========================================================================

  describe "group_clauses/1" do
    test "groups clauses by name and arity" do
      body =
        {:__block__, [],
         [
           {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: 1]]},
           {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: 2]]},
           {:def, [], [{:bar, [], nil}, [do: :ok]]}
         ]}

      clauses = Clause.extract_all(body)
      groups = Clause.group_clauses(clauses)

      assert Map.keys(groups) |> Enum.sort() == [{:bar, 0}, {:foo, 1}]
      assert length(groups[{:foo, 1}]) == 2
      assert length(groups[{:bar, 0}]) == 1
    end

    test "assigns correct order within groups" do
      body =
        {:__block__, [],
         [
           {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: 1]]},
           {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: 2]]},
           {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: 3]]}
         ]}

      clauses = Clause.extract_all(body)
      groups = Clause.group_clauses(clauses)

      foo_clauses = groups[{:foo, 1}]
      assert Enum.map(foo_clauses, & &1.order) == [1, 2, 3]
    end

    test "separates different arities" do
      body =
        {:__block__, [],
         [
           {:def, [], [{:foo, [], nil}, [do: 1]]},
           {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: 2]]}
         ]}

      clauses = Clause.extract_all(body)
      groups = Clause.group_clauses(clauses)

      assert Map.has_key?(groups, {:foo, 0})
      assert Map.has_key?(groups, {:foo, 1})
    end
  end

  describe "assign_order/1" do
    test "assigns sequential order to clauses" do
      clauses = [
        %Clause{name: :foo, arity: 1, order: 1, visibility: :public, head: %{parameters: [], guard: nil}, body: nil, metadata: %{}},
        %Clause{name: :foo, arity: 1, order: 1, visibility: :public, head: %{parameters: [], guard: nil}, body: nil, metadata: %{}}
      ]

      ordered = Clause.assign_order(clauses)
      assert Enum.map(ordered, & &1.order) == [1, 2]
    end
  end

  # ===========================================================================
  # Helper Function Tests
  # ===========================================================================

  describe "clause_id/1" do
    test "returns name/arity#order string" do
      ast = {:def, [], [{:hello, [], [{:x, [], nil}]}, [do: :ok]]}
      {:ok, clause} = Clause.extract(ast)

      assert Clause.clause_id(clause) == "hello/1#1"
    end

    test "includes order in id" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      {:ok, clause} = Clause.extract(ast, order: 3)

      assert Clause.clause_id(clause) == "foo/0#3"
    end
  end

  describe "parameter_count/1" do
    test "returns number of parameters" do
      ast = {:def, [], [{:foo, [], [{:a, [], nil}, {:b, [], nil}]}, [do: :ok]]}
      {:ok, clause} = Clause.extract(ast)

      assert Clause.parameter_count(clause) == 2
    end

    test "returns 0 for parameterless clause" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      {:ok, clause} = Clause.extract(ast)

      assert Clause.parameter_count(clause) == 0
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/2 error handling" do
    test "returns error for defmodule" do
      ast = {:defmodule, [], [{:__aliases__, [], [:Foo]}, [do: nil]]}
      assert {:error, message} = Clause.extract(ast)
      assert message =~ "Not a function clause"
    end

    test "returns error for non-AST" do
      assert {:error, _} = Clause.extract(:not_an_ast)
    end
  end

  describe "extract!/2" do
    test "returns result on success" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      result = Clause.extract!(ast)

      assert result.name == :foo
    end

    test "raises on error" do
      ast = {:defmodule, [], []}

      assert_raise ArgumentError, ~r/Not a function clause/, fn ->
        Clause.extract!(ast)
      end
    end
  end

  # ===========================================================================
  # Integration Tests with quote
  # ===========================================================================

  describe "integration with quote" do
    test "extracts clause from quoted code" do
      ast =
        quote do
          def hello(name), do: "Hello, #{name}"
        end

      assert {:ok, result} = Clause.extract(ast)
      assert result.name == :hello
      assert result.arity == 1
    end

    test "extracts guarded clause from quoted code" do
      ast =
        quote do
          def process(x) when is_integer(x), do: x * 2
        end

      assert {:ok, result} = Clause.extract(ast)
      assert result.head.guard != nil
    end

    test "extracts multiple clauses from quoted module body" do
      ast =
        quote do
          def foo(:ok), do: 1
          def foo(:error), do: 2
          def bar, do: :ok
        end

      results = Clause.extract_all(ast)
      assert length(results) == 3

      groups = Clause.group_clauses(results)
      assert length(groups[{:foo, 1}]) == 2
      assert length(groups[{:bar, 0}]) == 1
    end
  end
end
