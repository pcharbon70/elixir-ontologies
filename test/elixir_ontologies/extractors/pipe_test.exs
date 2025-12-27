defmodule ElixirOntologies.Extractors.PipeTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Pipe
  alias ElixirOntologies.Extractors.Pipe.{PipeChain, PipeStep}

  doctest Pipe

  # ===========================================================================
  # pipe_chain?/1 Tests
  # ===========================================================================

  describe "pipe_chain?/1" do
    test "returns true for single pipe" do
      ast = {:|>, [], [{:x, [], nil}, {:foo, [], []}]}
      assert Pipe.pipe_chain?(ast)
    end

    test "returns true for multi-step pipe chain" do
      ast =
        {:|>, [],
         [
           {:|>, [], [{:data, [], nil}, {:transform, [], []}]},
           {:output, [], []}
         ]}

      assert Pipe.pipe_chain?(ast)
    end

    test "returns true for long pipe chain" do
      # data |> a() |> b() |> c() |> d()
      ast =
        {:|>, [],
         [
           {:|>, [],
            [
              {:|>, [],
               [
                 {:|>, [], [{:data, [], nil}, {:a, [], []}]},
                 {:b, [], []}
               ]},
              {:c, [], []}
            ]},
           {:d, [], []}
         ]}

      assert Pipe.pipe_chain?(ast)
    end

    test "returns false for local function call" do
      ast = {:foo, [], []}
      refute Pipe.pipe_chain?(ast)
    end

    test "returns false for remote function call" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      refute Pipe.pipe_chain?(ast)
    end

    test "returns false for variable" do
      ast = {:x, [], nil}
      refute Pipe.pipe_chain?(ast)
    end

    test "returns false for literal" do
      refute Pipe.pipe_chain?([1, 2, 3])
      refute Pipe.pipe_chain?("string")
      refute Pipe.pipe_chain?(123)
    end

    test "returns false for non-tuple" do
      refute Pipe.pipe_chain?(:atom)
    end
  end

  # ===========================================================================
  # extract_pipe_chain/2 Tests
  # ===========================================================================

  describe "extract_pipe_chain/2" do
    test "extracts single pipe with local call" do
      ast = {:|>, [], [{:data, [], nil}, {:transform, [], []}]}

      assert {:ok, chain} = Pipe.extract_pipe_chain(ast)
      assert %PipeChain{} = chain
      assert chain.start_value == {:data, [], nil}
      assert chain.length == 1
      assert length(chain.steps) == 1

      [step] = chain.steps
      assert %PipeStep{} = step
      assert step.index == 0
      assert step.call.name == :transform
      assert step.call.type == :local
    end

    test "extracts two-step pipe chain" do
      ast =
        {:|>, [],
         [
           {:|>, [], [{:data, [], nil}, {:first, [], []}]},
           {:second, [], []}
         ]}

      assert {:ok, chain} = Pipe.extract_pipe_chain(ast)
      assert chain.start_value == {:data, [], nil}
      assert chain.length == 2

      [step1, step2] = chain.steps
      assert step1.index == 0
      assert step1.call.name == :first
      assert step2.index == 1
      assert step2.call.name == :second
    end

    test "extracts long pipe chain with correct ordering" do
      # data |> a() |> b() |> c() |> d()
      ast =
        {:|>, [],
         [
           {:|>, [],
            [
              {:|>, [],
               [
                 {:|>, [], [{:data, [], nil}, {:a, [], []}]},
                 {:b, [], []}
               ]},
              {:c, [], []}
            ]},
           {:d, [], []}
         ]}

      assert {:ok, chain} = Pipe.extract_pipe_chain(ast)
      assert chain.length == 4

      names = Enum.map(chain.steps, & &1.call.name)
      assert names == [:a, :b, :c, :d]

      indices = Enum.map(chain.steps, & &1.index)
      assert indices == [0, 1, 2, 3]
    end

    test "extracts pipe chain with remote calls" do
      # list |> Enum.map(fn x -> x end) |> Enum.sum()
      ast =
        {:|>, [],
         [
           {:|>, [],
            [
              {:list, [], nil},
              {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], [{:fn, [], []}]}
            ]},
           {{:., [], [{:__aliases__, [], [:Enum]}, :sum]}, [], []}
         ]}

      assert {:ok, chain} = Pipe.extract_pipe_chain(ast)
      assert chain.start_value == {:list, [], nil}
      assert chain.length == 2

      [step1, step2] = chain.steps
      assert step1.call.type == :remote
      assert step1.call.module == [:Enum]
      assert step1.call.name == :map
      assert step2.call.type == :remote
      assert step2.call.module == [:Enum]
      assert step2.call.name == :sum
    end

    test "extracts pipe chain with literal start value" do
      # [1, 2, 3] |> Enum.sum()
      ast =
        {:|>, [],
         [
           [1, 2, 3],
           {{:., [], [{:__aliases__, [], [:Enum]}, :sum]}, [], []}
         ]}

      assert {:ok, chain} = Pipe.extract_pipe_chain(ast)
      assert chain.start_value == [1, 2, 3]
      assert chain.length == 1
    end

    test "extracts explicit arguments for each step" do
      # x |> foo(1, 2) |> bar(3)
      ast =
        {:|>, [],
         [
           {:|>, [], [{:x, [], nil}, {:foo, [], [1, 2]}]},
           {:bar, [], [3]}
         ]}

      assert {:ok, chain} = Pipe.extract_pipe_chain(ast)

      [step1, step2] = chain.steps
      assert step1.explicit_args == [1, 2]
      assert step2.explicit_args == [3]
    end

    test "tracks arity including piped value" do
      # x |> foo() has arity 0 for explicit args, but func receives 1 arg
      ast = {:|>, [], [{:x, [], nil}, {:foo, [], []}]}

      assert {:ok, chain} = Pipe.extract_pipe_chain(ast)
      [step] = chain.steps
      assert step.call.arity == 0
      assert step.explicit_args == []
    end

    test "handles mixed local and remote calls" do
      # data |> local_func() |> String.upcase() |> another_local()
      ast =
        {:|>, [],
         [
           {:|>, [],
            [
              {:|>, [], [{:data, [], nil}, {:local_func, [], []}]},
              {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], []}
            ]},
           {:another_local, [], []}
         ]}

      assert {:ok, chain} = Pipe.extract_pipe_chain(ast)
      assert chain.length == 3

      types = Enum.map(chain.steps, & &1.call.type)
      assert types == [:local, :remote, :local]
    end

    test "includes location when available" do
      ast = {:|>, [line: 10, column: 5], [{:x, [line: 10], nil}, {:foo, [line: 10], []}]}

      assert {:ok, chain} = Pipe.extract_pipe_chain(ast)
      assert chain.location != nil
      assert chain.location.start_line == 10
    end

    test "respects include_location: false option" do
      ast = {:|>, [line: 10], [{:x, [], nil}, {:foo, [], []}]}

      assert {:ok, chain} = Pipe.extract_pipe_chain(ast, include_location: false)
      assert chain.location == nil
    end

    test "returns error for non-pipe" do
      ast = {:foo, [], []}
      assert {:error, {:not_a_pipe_chain, _msg}} = Pipe.extract_pipe_chain(ast)
    end

    test "returns error for variable" do
      ast = {:x, [], nil}
      assert {:error, {:not_a_pipe_chain, _msg}} = Pipe.extract_pipe_chain(ast)
    end
  end

  # ===========================================================================
  # extract_pipe_chain!/2 Tests
  # ===========================================================================

  describe "extract_pipe_chain!/2" do
    test "returns chain for valid input" do
      ast = {:|>, [], [{:x, [], nil}, {:foo, [], []}]}

      chain = Pipe.extract_pipe_chain!(ast)
      assert %PipeChain{} = chain
      assert chain.length == 1
    end

    test "raises for invalid input" do
      assert_raise ArgumentError, fn ->
        Pipe.extract_pipe_chain!({:foo, [], []})
      end
    end
  end

  # ===========================================================================
  # extract_pipe_chains/2 Tests
  # ===========================================================================

  describe "extract_pipe_chains/2" do
    test "extracts multiple pipe chains from list" do
      body = [
        {:|>, [], [{:x, [], nil}, {:foo, [], []}]},
        {:regular_call, [], []},
        {:|>, [], [{:y, [], nil}, {:bar, [], []}]}
      ]

      chains = Pipe.extract_pipe_chains(body)
      assert length(chains) == 2
    end

    test "extracts pipe chain from if expression" do
      ast =
        {:if, [],
         [
           true,
           [
             do: {:|>, [], [{:x, [], nil}, {:foo, [], []}]},
             else: {:bar, [], []}
           ]
         ]}

      chains = Pipe.extract_pipe_chains(ast)
      assert length(chains) == 1
    end

    test "extracts pipe chain from case expression" do
      ast =
        {:case, [],
         [
           {:value, [], nil},
           [
             do: [
               {:->, [], [[:ok], {:|>, [], [{:data, [], nil}, {:process, [], []}]}]},
               {:->, [], [[:error], {:handle_error, [], []}]}
             ]
           ]
         ]}

      chains = Pipe.extract_pipe_chains(ast)
      assert length(chains) == 1
    end

    test "extracts pipe chain from function body" do
      # def run, do: data |> transform() |> output()
      ast =
        {:def, [],
         [
           {:run, [], nil},
           [
             do:
               {:|>, [],
                [
                  {:|>, [], [{:data, [], nil}, {:transform, [], []}]},
                  {:output, [], []}
                ]}
           ]
         ]}

      chains = Pipe.extract_pipe_chains(ast)
      assert length(chains) == 1
      assert hd(chains).length == 2
    end

    test "extracts from __block__" do
      ast =
        {:__block__, [],
         [
           {:|>, [], [{:a, [], nil}, {:foo, [], []}]},
           {:|>, [], [{:b, [], nil}, {:bar, [], []}]}
         ]}

      chains = Pipe.extract_pipe_chains(ast)
      assert length(chains) == 2
    end

    test "returns empty list when no pipes" do
      body = [
        {:foo, [], []},
        {:bar, [], [1, 2]},
        {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], ["hello"]}
      ]

      chains = Pipe.extract_pipe_chains(body)
      assert chains == []
    end

    test "handles empty input" do
      assert Pipe.extract_pipe_chains([]) == []
    end

    test "respects max_depth option" do
      # Create deeply nested structure
      deep_ast =
        {:def, [],
         [
           {:run, [], nil},
           [
             do:
               {:if, [],
                [
                  true,
                  [
                    do:
                      {:case, [],
                       [
                         {:x, [], nil},
                         [do: [{:->, [], [[:ok], {:|>, [], [{:a, [], nil}, {:b, [], []}]}]}]]
                       ]}
                  ]
                ]}
           ]
         ]}

      # With max_depth 2, shouldn't reach the pipe
      chains = Pipe.extract_pipe_chains(deep_ast, max_depth: 2)
      assert chains == []

      # With higher depth, should find it
      chains = Pipe.extract_pipe_chains(deep_ast, max_depth: 10)
      assert length(chains) == 1
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "extracts pipe chains from real module code" do
      {:ok, ast} =
        Code.string_to_quoted("""
        defmodule Test do
          def run(data) do
            data
            |> validate()
            |> transform()
            |> output()
          end

          def process(list) do
            list
            |> Enum.map(&(&1 * 2))
            |> Enum.filter(&(&1 > 5))
            |> Enum.sum()
          end
        end
        """)

      {:defmodule, _, [_, [do: body]]} = ast
      chains = Pipe.extract_pipe_chains(body)

      assert length(chains) == 2

      # First chain: validate -> transform -> output
      chain1 = Enum.find(chains, &(&1.length == 3 && hd(&1.steps).call.name == :validate))
      assert chain1 != nil
      assert Enum.map(chain1.steps, & &1.call.name) == [:validate, :transform, :output]

      # Second chain: Enum.map -> Enum.filter -> Enum.sum
      chain2 = Enum.find(chains, &(hd(&1.steps).call.module == [:Enum]))
      assert chain2 != nil
      assert chain2.length == 3
      assert Enum.map(chain2.steps, & &1.call.name) == [:map, :filter, :sum]
    end

    test "step indices are sequential" do
      {:ok, ast} =
        Code.string_to_quoted("""
        data |> a() |> b() |> c() |> d() |> e()
        """)

      {:ok, chain} = Pipe.extract_pipe_chain(ast)
      indices = Enum.map(chain.steps, & &1.index)
      assert indices == [0, 1, 2, 3, 4]
    end

    test "start value is correctly identified" do
      test_cases = [
        # Variable start
        {"x |> foo()", {:x, [line: 1], nil}},
        # Literal start
        {"[1, 2, 3] |> Enum.sum()", [1, 2, 3]},
        # Function call start
        {"get_data() |> process()", {:get_data, [line: 1], []}}
      ]

      for {code, expected_start} <- test_cases do
        {:ok, ast} = Code.string_to_quoted(code)
        {:ok, chain} = Pipe.extract_pipe_chain(ast)
        assert chain.start_value == expected_start, "Failed for: #{code}"
      end
    end

    test "handles Erlang module calls in pipes" do
      ast =
        {:|>, [],
         [
           {:data, [], nil},
           {{:., [], [:erlang, :binary_to_list]}, [], []}
         ]}

      {:ok, chain} = Pipe.extract_pipe_chain(ast)
      [step] = chain.steps
      assert step.call.type == :remote
      assert step.call.module == :erlang
      assert step.call.name == :binary_to_list
    end
  end
end
