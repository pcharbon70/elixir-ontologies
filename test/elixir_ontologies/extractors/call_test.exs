defmodule ElixirOntologies.Extractors.CallTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Call
  alias ElixirOntologies.Extractors.Call.FunctionCall

  doctest Call

  # ===========================================================================
  # local_call?/1 Tests
  # ===========================================================================

  describe "local_call?/1" do
    test "returns true for simple function call with no args" do
      ast = {:foo, [], []}
      assert Call.local_call?(ast)
    end

    test "returns true for function call with arguments" do
      ast = {:bar, [line: 1], [1, 2, 3]}
      assert Call.local_call?(ast)
    end

    test "returns true for function call with variable arguments" do
      ast = {:process, [], [{:x, [], nil}, {:y, [], nil}]}
      assert Call.local_call?(ast)
    end

    test "returns false for variable reference (nil context)" do
      ast = {:x, [], nil}
      refute Call.local_call?(ast)
    end

    test "returns false for variable reference (Elixir context)" do
      ast = {:x, [], Elixir}
      refute Call.local_call?(ast)
    end

    test "returns false for def special form" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      refute Call.local_call?(ast)
    end

    test "returns false for defp special form" do
      ast = {:defp, [], [{:helper, [], nil}, [do: :ok]]}
      refute Call.local_call?(ast)
    end

    test "returns false for if special form" do
      ast = {:if, [], [true, [do: 1, else: 2]]}
      refute Call.local_call?(ast)
    end

    test "returns false for case special form" do
      ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[1], :one]}]]]}
      refute Call.local_call?(ast)
    end

    test "returns false for import directive" do
      ast = {:import, [], [{:__aliases__, [], [:Enum]}]}
      refute Call.local_call?(ast)
    end

    test "returns false for require directive" do
      ast = {:require, [], [{:__aliases__, [], [:Logger]}]}
      refute Call.local_call?(ast)
    end

    test "returns false for use directive" do
      ast = {:use, [], [{:__aliases__, [], [:GenServer]}]}
      refute Call.local_call?(ast)
    end

    test "returns false for alias directive" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Module]}]}
      refute Call.local_call?(ast)
    end

    test "returns false for fn special form" do
      ast = {:fn, [], [{:->, [], [[], :ok]}]}
      refute Call.local_call?(ast)
    end

    test "returns false for quote special form" do
      ast = {:quote, [], [[do: {:x, [], nil}]]}
      refute Call.local_call?(ast)
    end

    test "returns false for arithmetic operators" do
      ast = {:+, [], [1, 2]}
      refute Call.local_call?(ast)
    end

    test "returns false for comparison operators" do
      ast = {:==, [], [{:x, [], nil}, 1]}
      refute Call.local_call?(ast)
    end

    test "returns false for logical operators" do
      ast = {:and, [], [true, false]}
      refute Call.local_call?(ast)
    end

    test "returns false for non-tuple" do
      refute Call.local_call?(:atom)
      refute Call.local_call?("string")
      refute Call.local_call?(123)
      refute Call.local_call?([1, 2, 3])
    end
  end

  # ===========================================================================
  # extract/2 Tests
  # ===========================================================================

  describe "extract/2" do
    test "extracts simple function call" do
      ast = {:foo, [], []}
      assert {:ok, call} = Call.extract(ast)
      assert %FunctionCall{} = call
      assert call.type == :local
      assert call.name == :foo
      assert call.arity == 0
      assert call.arguments == []
    end

    test "extracts function call with arguments" do
      ast = {:bar, [], [1, 2, 3]}
      assert {:ok, call} = Call.extract(ast)
      assert call.name == :bar
      assert call.arity == 3
      assert call.arguments == [1, 2, 3]
    end

    test "extracts function call with variable arguments" do
      ast = {:process, [], [{:x, [], nil}, {:y, [], nil}]}
      assert {:ok, call} = Call.extract(ast)
      assert call.name == :process
      assert call.arity == 2
      assert length(call.arguments) == 2
    end

    test "includes location when available" do
      ast = {:foo, [line: 10, column: 5], []}
      assert {:ok, call} = Call.extract(ast)
      assert call.location != nil
      assert call.location.start_line == 10
      assert call.location.start_column == 5
    end

    test "respects include_location: false option" do
      ast = {:foo, [line: 10], []}
      assert {:ok, call} = Call.extract(ast, include_location: false)
      assert call.location == nil
    end

    test "returns error for variable reference" do
      ast = {:x, [], nil}
      assert {:error, {:not_a_local_call, _msg}} = Call.extract(ast)
    end

    test "returns error for special form" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      assert {:error, {:not_a_local_call, _msg}} = Call.extract(ast)
    end

    test "returns error for non-tuple" do
      assert {:error, {:not_a_local_call, _msg}} = Call.extract(:atom)
    end
  end

  # ===========================================================================
  # extract!/2 Tests
  # ===========================================================================

  describe "extract!/2" do
    test "returns call for valid input" do
      ast = {:foo, [], [1, 2]}
      call = Call.extract!(ast)
      assert call.name == :foo
      assert call.arity == 2
    end

    test "raises for invalid input" do
      assert_raise ArgumentError, fn ->
        Call.extract!({:x, [], nil})
      end
    end
  end

  # ===========================================================================
  # extract_local_calls/2 Tests
  # ===========================================================================

  describe "extract_local_calls/2" do
    test "extracts calls from list of statements" do
      body = [
        {:foo, [], []},
        {:bar, [], [1, 2]},
        {:baz, [], [{:x, [], nil}]}
      ]

      calls = Call.extract_local_calls(body)
      names = Enum.map(calls, & &1.name)
      assert names == [:foo, :bar, :baz]
    end

    test "extracts calls from __block__" do
      ast = {:__block__, [], [{:foo, [], []}, {:bar, [], []}]}
      calls = Call.extract_local_calls(ast)
      names = Enum.map(calls, & &1.name)
      assert names == [:foo, :bar]
    end

    test "extracts calls from function body" do
      # def test, do: foo()
      ast = {:def, [], [{:test, [], nil}, [do: {:foo, [], []}]]}
      calls = Call.extract_local_calls(ast)
      assert length(calls) == 1
      assert hd(calls).name == :foo
    end

    test "extracts calls from if expression" do
      ast = {:if, [], [{:condition, [], []}, [do: {:foo, [], []}, else: {:bar, [], []}]]}
      calls = Call.extract_local_calls(ast)
      names = Enum.map(calls, & &1.name)
      assert :condition in names
      assert :foo in names
      assert :bar in names
    end

    test "extracts calls from case expression" do
      ast =
        {:case, [],
         [
           {:get_value, [], []},
           [
             do: [
               {:->, [], [[:ok], {:handle_ok, [], []}]},
               {:->, [], [[:error], {:handle_error, [], []}]}
             ]
           ]
         ]}

      calls = Call.extract_local_calls(ast)
      names = Enum.map(calls, & &1.name)
      assert :get_value in names
      assert :handle_ok in names
      assert :handle_error in names
    end

    test "extracts nested calls in arguments" do
      # outer(inner())
      ast = {:outer, [], [{:inner, [], []}]}
      calls = Call.extract_local_calls(ast)
      names = Enum.map(calls, & &1.name)
      assert :outer in names
      assert :inner in names
    end

    test "extracts deeply nested calls" do
      # a(b(c()))
      ast = {:a, [], [{:b, [], [{:c, [], []}]}]}
      calls = Call.extract_local_calls(ast)
      names = Enum.map(calls, & &1.name)
      assert length(calls) == 3
      assert :a in names
      assert :b in names
      assert :c in names
    end

    test "does not extract variable references" do
      body = [
        {:foo, [], [{:x, [], nil}]},
        {:y, [], nil}
      ]

      calls = Call.extract_local_calls(body)
      names = Enum.map(calls, & &1.name)
      assert names == [:foo]
      refute :x in names
      refute :y in names
    end

    test "does not extract special forms as calls" do
      body = [
        {:def, [], [{:test, [], nil}, [do: {:foo, [], []}]]},
        {:if, [], [true, [do: {:bar, [], []}]]}
      ]

      calls = Call.extract_local_calls(body)
      names = Enum.map(calls, & &1.name)
      assert :foo in names
      assert :bar in names
      refute :def in names
      refute :if in names
    end

    test "handles empty input" do
      assert Call.extract_local_calls([]) == []
      assert Call.extract_local_calls({:__block__, [], []}) == []
    end

    test "handles single call" do
      ast = {:foo, [], []}
      calls = Call.extract_local_calls(ast)
      assert length(calls) == 1
      assert hd(calls).name == :foo
    end

    test "respects max_depth option" do
      # Create deeply nested call that exceeds default depth
      # We'll test with a shallow max_depth
      deep_ast =
        Enum.reduce(1..5, {:innermost, [], []}, fn n, inner ->
          {String.to_atom("level_#{n}"), [], [inner]}
        end)

      # With max_depth of 3, should only extract outer calls
      calls = Call.extract_local_calls(deep_ast, max_depth: 3)
      assert length(calls) < 6
    end

    test "extracts calls from with expression" do
      ast =
        {:with, [],
         [
           {:<-, [], [{:ok, {:a, [], nil}}, {:get_a, [], []}]},
           {:<-, [], [{:ok, {:b, [], nil}}, {:get_b, [], []}]},
           [do: {:process, [], [{:a, [], nil}, {:b, [], nil}]}]
         ]}

      calls = Call.extract_local_calls(ast)
      names = Enum.map(calls, & &1.name)
      assert :get_a in names
      assert :get_b in names
      assert :process in names
    end

    test "extracts calls from try expression" do
      ast =
        {:try, [],
         [
           [
             do: {:risky_operation, [], []},
             rescue: [{:->, [], [[{:e, [], nil}], {:handle_error, [], [{:e, [], nil}]}]}],
             after: {:cleanup, [], []}
           ]
         ]}

      calls = Call.extract_local_calls(ast)
      names = Enum.map(calls, & &1.name)
      assert :risky_operation in names
      assert :handle_error in names
      assert :cleanup in names
    end

    test "extracts calls from for comprehension" do
      ast =
        {:for, [],
         [
           {:<-, [], [{:x, [], nil}, {:get_list, [], []}]},
           [do: {:process_item, [], [{:x, [], nil}]}]
         ]}

      calls = Call.extract_local_calls(ast)
      names = Enum.map(calls, & &1.name)
      assert :get_list in names
      assert :process_item in names
    end

    test "extracts calls from pipe chain" do
      # data |> transform() |> output()
      ast =
        {:|>, [],
         [
           {:|>, [], [{:data, [], nil}, {:transform, [], []}]},
           {:output, [], []}
         ]}

      calls = Call.extract_local_calls(ast)
      names = Enum.map(calls, & &1.name)
      # Note: pipe operator is excluded, but the function calls inside should be extracted
      assert :transform in names
      assert :output in names
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "extracts calls from real module body" do
      {:ok, ast} =
        Code.string_to_quoted("""
        defmodule Test do
          def run do
            data = get_data()
            processed = process(data)
            save(processed)
          end

          defp process(data) do
            validate(data)
            transform(data)
          end
        end
        """)

      {:defmodule, _, [_, [do: body]]} = ast
      calls = Call.extract_local_calls(body)
      names = Enum.map(calls, & &1.name)

      assert :get_data in names
      assert :process in names
      assert :save in names
      assert :validate in names
      assert :transform in names
    end

    test "preserves arity information" do
      body = [
        {:foo, [], []},
        {:foo, [], [1]},
        {:foo, [], [1, 2]},
        {:foo, [], [1, 2, 3]}
      ]

      calls = Call.extract_local_calls(body)
      arities = Enum.map(calls, & &1.arity)
      assert arities == [0, 1, 2, 3]
    end

    test "location tracking works correctly" do
      {:ok, ast} =
        Code.string_to_quoted(
          """
          foo()
          bar(1)
          """,
          columns: true
        )

      calls = Call.extract_local_calls(ast)
      assert length(calls) == 2

      [foo_call, bar_call] = calls
      assert foo_call.location.start_line == 1
      assert bar_call.location.start_line == 2
    end
  end

  # ===========================================================================
  # remote_call?/1 Tests
  # ===========================================================================

  describe "remote_call?/1" do
    test "returns true for Elixir module call" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      assert Call.remote_call?(ast)
    end

    test "returns true for nested module call" do
      ast = {{:., [], [{:__aliases__, [], [:MyApp, :Services, :User]}, :create]}, [], [%{}]}
      assert Call.remote_call?(ast)
    end

    test "returns true for Erlang module call" do
      ast = {{:., [], [:ets, :new]}, [], [:table, []]}
      assert Call.remote_call?(ast)
    end

    test "returns true for __MODULE__ call" do
      ast = {{:., [], [{:__MODULE__, [], Elixir}, :helper]}, [], []}
      assert Call.remote_call?(ast)
    end

    test "returns true for variable receiver (dynamic)" do
      ast = {{:., [], [{:mod, [], Elixir}, :func]}, [], [{:x, [], Elixir}]}
      assert Call.remote_call?(ast)
    end

    test "returns false for local call" do
      ast = {:foo, [], []}
      refute Call.remote_call?(ast)
    end

    test "returns false for non-tuple" do
      refute Call.remote_call?(:atom)
      refute Call.remote_call?("string")
    end
  end

  # ===========================================================================
  # extract_remote/2 Tests
  # ===========================================================================

  describe "extract_remote/2" do
    test "extracts Elixir module call" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      assert {:ok, call} = Call.extract_remote(ast)
      assert %FunctionCall{} = call
      assert call.type == :remote
      assert call.name == :upcase
      assert call.module == [:String]
      assert call.arity == 1
    end

    test "extracts nested module call" do
      ast = {{:., [], [{:__aliases__, [], [:MyApp, :Services, :User]}, :create]}, [], [%{}]}
      assert {:ok, call} = Call.extract_remote(ast)
      assert call.module == [:MyApp, :Services, :User]
      assert call.name == :create
    end

    test "extracts Erlang module call" do
      ast = {{:., [], [:ets, :new]}, [], [:table, []]}
      assert {:ok, call} = Call.extract_remote(ast)
      assert call.module == :ets
      assert call.name == :new
      assert call.arity == 2
      assert call.metadata.erlang_module == true
    end

    test "extracts __MODULE__ call with metadata" do
      ast = {{:., [], [{:__MODULE__, [], Elixir}, :helper]}, [], [1, 2]}
      assert {:ok, call} = Call.extract_remote(ast)
      assert call.module == :__MODULE__
      assert call.name == :helper
      assert call.arity == 2
      assert call.metadata.current_module == true
    end

    test "extracts dynamic receiver call with metadata" do
      ast = {{:., [], [{:mod, [], Elixir}, :func]}, [], [{:x, [], Elixir}]}
      assert {:ok, call} = Call.extract_remote(ast)
      assert call.module == :mod
      assert call.name == :func
      assert call.metadata.dynamic_receiver == true
      assert call.metadata.receiver_variable == :mod
    end

    test "includes location when available" do
      ast = {{:., [line: 10], [{:__aliases__, [line: 10], [:String]}, :upcase]}, [line: 10, column: 5], ["hello"]}
      assert {:ok, call} = Call.extract_remote(ast)
      assert call.location != nil
    end

    test "respects include_location: false option" do
      ast = {{:., [line: 10], [{:__aliases__, [], [:String]}, :upcase]}, [line: 10], ["hello"]}
      assert {:ok, call} = Call.extract_remote(ast, include_location: false)
      assert call.location == nil
    end

    test "returns error for local call" do
      ast = {:foo, [], []}
      assert {:error, {:not_a_remote_call, _msg}} = Call.extract_remote(ast)
    end
  end

  # ===========================================================================
  # extract_remote!/2 Tests
  # ===========================================================================

  describe "extract_remote!/2" do
    test "returns call for valid input" do
      ast = {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], [[1, 2], {:fn, [], []}]}
      call = Call.extract_remote!(ast)
      assert call.name == :map
      assert call.module == [:Enum]
    end

    test "raises for invalid input" do
      assert_raise ArgumentError, fn ->
        Call.extract_remote!({:foo, [], []})
      end
    end
  end

  # ===========================================================================
  # extract_remote_calls/2 Tests
  # ===========================================================================

  describe "extract_remote_calls/2" do
    test "extracts remote calls from list" do
      body = [
        {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]},
        {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], [[1, 2], {:fn, [], []}]}
      ]

      calls = Call.extract_remote_calls(body)
      assert length(calls) == 2
      names = Enum.map(calls, & &1.name)
      assert :upcase in names
      assert :map in names
    end

    test "extracts nested remote calls" do
      # String.upcase(Enum.join(list, ","))
      ast =
        {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [],
         [{{:., [], [{:__aliases__, [], [:Enum]}, :join]}, [], [{:list, [], nil}, ","]}]}

      calls = Call.extract_remote_calls(ast)
      assert length(calls) == 2
      modules = Enum.map(calls, & &1.module)
      assert [:String] in modules
      assert [:Enum] in modules
    end

    test "ignores local calls" do
      body = [
        {:foo, [], []},
        {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      ]

      calls = Call.extract_remote_calls(body)
      assert length(calls) == 1
      assert hd(calls).name == :upcase
    end

    test "extracts from control flow" do
      ast =
        {:if, [],
         [
           true,
           [
             do: {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["yes"]},
             else: {{:., [], [{:__aliases__, [], [:String]}, :downcase]}, [], ["no"]}
           ]
         ]}

      calls = Call.extract_remote_calls(ast)
      assert length(calls) == 2
      names = Enum.map(calls, & &1.name)
      assert :upcase in names
      assert :downcase in names
    end
  end

  # ===========================================================================
  # extract_all_calls/2 Tests
  # ===========================================================================

  describe "extract_all_calls/2" do
    test "extracts both local and remote calls" do
      body = [
        {:foo, [], []},
        {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      ]

      calls = Call.extract_all_calls(body)
      assert length(calls) == 2
      types = Enum.map(calls, & &1.type)
      assert :local in types
      assert :remote in types
    end

    test "extracts nested mixed calls" do
      # process(String.upcase(data))
      ast =
        {:process, [],
         [{{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], [{:data, [], nil}]}]}

      calls = Call.extract_all_calls(ast)
      assert length(calls) == 2
      assert Enum.any?(calls, &(&1.name == :process and &1.type == :local))
      assert Enum.any?(calls, &(&1.name == :upcase and &1.type == :remote))
    end

    test "extracts from real module code" do
      {:ok, ast} =
        Code.string_to_quoted("""
        defmodule Test do
          def run(data) do
            result = process(data)
            String.upcase(result)
          end

          defp process(data) do
            validated = validate(data)
            Enum.map(validated, fn x -> x end)
          end
        end
        """)

      {:defmodule, _, [_, [do: body]]} = ast
      calls = Call.extract_all_calls(body)

      local_names = calls |> Enum.filter(&(&1.type == :local)) |> Enum.map(& &1.name)
      remote_names = calls |> Enum.filter(&(&1.type == :remote)) |> Enum.map(& &1.name)

      assert :process in local_names
      assert :validate in local_names
      assert :upcase in remote_names
      assert :map in remote_names
    end

    test "handles Erlang module calls" do
      body = [
        {{:., [], [:ets, :new]}, [], [:table, []]},
        {{:., [], [:ets, :insert]}, [], [:table, {:key, :value}]}
      ]

      calls = Call.extract_all_calls(body)
      assert length(calls) == 2
      assert Enum.all?(calls, &(&1.module == :ets))
    end

    test "handles __MODULE__ calls" do
      body = [
        {{:., [], [{:__MODULE__, [], Elixir}, :helper]}, [], []},
        {:local_func, [], []}
      ]

      calls = Call.extract_all_calls(body)
      assert length(calls) == 2

      mod_call = Enum.find(calls, &(&1.module == :__MODULE__))
      assert mod_call.metadata.current_module == true
    end
  end
end
