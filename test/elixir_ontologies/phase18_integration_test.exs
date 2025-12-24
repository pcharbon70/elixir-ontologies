defmodule ElixirOntologies.Phase18IntegrationTest do
  @moduledoc """
  Integration tests for Phase 18: Anonymous Functions & Closures.

  These tests verify end-to-end functionality of anonymous function extraction,
  closure analysis, capture operators, and RDF generation working together
  through the Pipeline and Orchestrator.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.{AnonymousFunction, Capture, Closure}

  alias ElixirOntologies.Builders.{
    Context,
    AnonymousFunctionBuilder,
    ClosureBuilder,
    CaptureBuilder
  }

  alias ElixirOntologies.NS.{Structure, Core}

  @moduletag :integration

  # ===========================================================================
  # Complete Anonymous Function Extraction Tests
  # ===========================================================================

  describe "complete anonymous function extraction" do
    test "extracts multiple anonymous functions from complex module" do
      code = """
      def process(data) do
        mapper = fn x -> x * 2 end
        filter = fn x -> x > 0 end
        reducer = fn acc, x -> acc + x end

        data
        |> Enum.map(mapper)
        |> Enum.filter(filter)
        |> Enum.reduce(0, reducer)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      anon_funcs = AnonymousFunction.extract_all(ast)

      assert length(anon_funcs) == 3

      arities = Enum.map(anon_funcs, & &1.arity)
      assert 1 in arities
      assert 2 in arities
    end

    test "extracts zero-arity anonymous function" do
      code = """
      def get_constant do
        fn -> 42 end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      [anon] = AnonymousFunction.extract_all(ast)

      assert anon.arity == 0
      assert length(anon.clauses) == 1
    end

    test "extracts multi-arity anonymous function" do
      code = """
      def calculator do
        fn a, b, c, d -> a + b + c + d end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      [anon] = AnonymousFunction.extract_all(ast)

      assert anon.arity == 4
    end
  end

  # ===========================================================================
  # Closure Variable Tracking Tests
  # ===========================================================================

  describe "closure variable tracking accuracy" do
    test "detects free variables in closures" do
      code = """
      def make_adder(n) do
        fn x -> x + n end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      [anon] = AnonymousFunction.extract_all(ast)

      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      assert length(analysis.free_variables) == 1

      [free_var] = analysis.free_variables
      assert free_var.name == :n
    end

    test "detects multiple captured variables" do
      code = """
      def make_calculator(a, b, c) do
        fn x -> x + a + b + c end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      [anon] = AnonymousFunction.extract_all(ast)

      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      assert length(analysis.free_variables) == 3

      names = Enum.map(analysis.free_variables, & &1.name)
      assert :a in names
      assert :b in names
      assert :c in names
    end

    test "distinguishes bound from free variables" do
      code = """
      def processor(config) do
        fn x, y -> x + y + config end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      [anon] = AnonymousFunction.extract_all(ast)

      {:ok, analysis} = Closure.analyze_closure(anon)

      # x and y are bound, only config is free
      assert analysis.has_captures == true
      assert length(analysis.free_variables) == 1

      [free_var] = analysis.free_variables
      assert free_var.name == :config
    end

    test "handles non-closure (no captures)" do
      code = """
      def identity do
        fn x -> x end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      [anon] = AnonymousFunction.extract_all(ast)

      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == false
      assert analysis.free_variables == []
    end
  end

  # ===========================================================================
  # Capture Operator Coverage Tests
  # ===========================================================================

  describe "capture operator coverage" do
    test "extracts named local captures" do
      code = """
      def with_capture do
        Enum.map(list, &double/1)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      captures = Capture.extract_all(ast)

      assert length(captures) >= 1

      local_captures = Enum.filter(captures, &(&1.type == :named_local))
      assert length(local_captures) >= 1

      [capture] = local_captures
      assert capture.function == :double
      assert capture.arity == 1
    end

    test "extracts named remote captures" do
      code = """
      def with_remote_capture do
        list
        |> Enum.map(&String.upcase/1)
        |> Enum.filter(&String.valid?/1)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      captures = Capture.extract_all(ast)

      remote_captures = Enum.filter(captures, &(&1.type == :named_remote))
      assert length(remote_captures) >= 2

      modules = Enum.map(remote_captures, & &1.module)
      assert Enum.all?(modules, fn m -> m == String end)
    end

    test "extracts shorthand captures" do
      code = """
      def with_shorthand do
        Enum.map(list, &(&1 * 2))
        Enum.reduce(list, 0, &(&1 + &2))
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      captures = Capture.extract_all(ast)

      shorthand_captures = Enum.filter(captures, &(&1.type == :shorthand))
      assert length(shorthand_captures) >= 2

      # Check arity from placeholder analysis
      arities = Enum.map(shorthand_captures, & &1.arity)
      assert 1 in arities
      assert 2 in arities
    end

    test "handles Erlang module captures" do
      code = """
      def erlang_capture do
        Enum.map(data, &:erlang.abs/1)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      captures = Capture.extract_all(ast)

      remote_captures = Enum.filter(captures, &(&1.type == :named_remote))
      assert length(remote_captures) >= 1

      [capture] = remote_captures
      assert capture.module == :erlang
      assert capture.function == :abs
    end
  end

  # ===========================================================================
  # Nested Anonymous Functions Tests
  # ===========================================================================

  describe "nested anonymous functions" do
    test "extracts anonymous function containing another" do
      code = """
      def nested_fns do
        fn x ->
          inner = fn y -> y * 2 end
          inner.(x) + 1
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      anon_funcs = AnonymousFunction.extract_all(ast)

      # Should find both outer and inner functions
      assert length(anon_funcs) >= 2
    end

    test "extracts capture inside anonymous function" do
      code = """
      def fn_with_capture do
        fn list ->
          Enum.map(list, &to_string/1)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)

      anon_funcs = AnonymousFunction.extract_all(ast)
      captures = Capture.extract_all(ast)

      assert length(anon_funcs) >= 1
      assert length(captures) >= 1
    end

    test "handles deeply nested closures" do
      code = """
      def deep_nesting(a) do
        fn b ->
          fn c ->
            fn d -> a + b + c + d end
          end
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      anon_funcs = AnonymousFunction.extract_all(ast)

      # Should find all 3 nested functions
      assert length(anon_funcs) >= 3

      # The innermost should capture a, b, c (d is bound)
      # Find innermost (4 captured - a, b, c and uses d as param)
      innermost =
        Enum.find(anon_funcs, fn anon ->
          {:ok, analysis} = Closure.analyze_closure(anon)
          length(analysis.free_variables) == 3
        end)

      assert innermost != nil
    end
  end

  # ===========================================================================
  # Closures in Comprehensions Tests
  # ===========================================================================

  describe "closures in comprehensions" do
    test "extracts closure in for comprehension" do
      code = """
      def comprehension_closure(multiplier) do
        for x <- 1..10 do
          fn y -> y * multiplier * x end
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      anon_funcs = AnonymousFunction.extract_all(ast)

      assert length(anon_funcs) >= 1

      [anon] = anon_funcs
      {:ok, analysis} = Closure.analyze_closure(anon)

      # Should capture both multiplier and x
      assert analysis.has_captures == true
      names = Enum.map(analysis.free_variables, & &1.name)
      assert :multiplier in names
      assert :x in names
    end

    test "extracts anonymous function used in comprehension filter" do
      code = """
      def filtered_comprehension do
        filter_fn = fn x -> rem(x, 2) == 0 end
        for x <- 1..10, filter_fn.(x), do: x * 2
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      anon_funcs = AnonymousFunction.extract_all(ast)

      assert length(anon_funcs) >= 1
    end
  end

  # ===========================================================================
  # Captures in Pipe Chains Tests
  # ===========================================================================

  describe "captures in pipe chains" do
    test "extracts captures in Enum.map pipe" do
      code = """
      def pipe_with_capture(data) do
        data
        |> Enum.map(&transform/1)
        |> Enum.filter(&valid?/1)
        |> Enum.sort(&compare/2)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      captures = Capture.extract_all(ast)

      assert length(captures) >= 3

      functions = Enum.map(captures, & &1.function)
      assert :transform in functions
      assert :valid? in functions
      assert :compare in functions
    end

    test "extracts anonymous functions in pipe chain" do
      code = """
      def pipe_with_anon(data) do
        data
        |> Enum.map(fn x -> x * 2 end)
        |> Enum.filter(fn x -> x > 10 end)
        |> Enum.reduce(0, fn x, acc -> x + acc end)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      anon_funcs = AnonymousFunction.extract_all(ast)

      assert length(anon_funcs) >= 3

      arities = Enum.map(anon_funcs, & &1.arity)
      assert 1 in arities
      assert 2 in arities
    end

    test "extracts mixed captures and anonymous functions in pipe" do
      code = """
      def mixed_pipe(data) do
        data
        |> Enum.map(&String.upcase/1)
        |> Enum.filter(fn x -> String.length(x) > 3 end)
        |> Enum.sort(&>=/2)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)

      anon_funcs = AnonymousFunction.extract_all(ast)
      captures = Capture.extract_all(ast)

      assert length(anon_funcs) >= 1
      assert length(captures) >= 2
    end
  end

  # ===========================================================================
  # Multi-Clause Anonymous Function Tests
  # ===========================================================================

  describe "multi-clause anonymous function handling" do
    test "extracts multi-clause anonymous function" do
      code = """
      def multi_clause do
        fn
          0 -> :zero
          n when n > 0 -> :positive
          n -> :negative
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      [anon] = AnonymousFunction.extract_all(ast)

      assert length(anon.clauses) == 3
      assert anon.arity == 1
    end

    test "extracts guards from multi-clause function" do
      code = """
      def guarded do
        fn
          x when is_integer(x) and x > 0 -> :positive_int
          x when is_integer(x) -> :non_positive_int
          x when is_float(x) -> :float
          _ -> :other
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      [anon] = AnonymousFunction.extract_all(ast)

      assert length(anon.clauses) == 4

      # Check that guards are detected
      guarded_clauses = Enum.filter(anon.clauses, &(&1.guard != nil))
      assert length(guarded_clauses) >= 3
    end

    test "handles complex patterns in multi-clause" do
      code = """
      def pattern_matching_fn do
        fn
          {:ok, value} -> {:success, value}
          {:error, reason} -> {:failure, reason}
          %{status: :pending} -> :waiting
          [head | _tail] -> head
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      [anon] = AnonymousFunction.extract_all(ast)

      assert length(anon.clauses) == 4
    end
  end

  # ===========================================================================
  # RDF Builder Integration Tests
  # ===========================================================================

  describe "RDF builder integration" do
    test "generates RDF for anonymous function" do
      ast = quote do: fn x -> x + 1 end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Verify IRI generated
      assert to_string(anon_iri) =~ "MyApp/anon/0"

      # Verify type triple
      type_triples = Enum.filter(triples, fn {_s, p, _o} -> p == RDF.type() end)
      assert length(type_triples) >= 1

      # Verify arity triple
      arity_triples =
        Enum.filter(triples, fn {_s, p, _o} -> p == Structure.arity() end)

      assert length(arity_triples) >= 1
    end

    test "generates RDF for closure with captured variables" do
      ast = quote do: fn -> x + y end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      anon_iri = RDF.iri("https://example.org/code#MyApp/anon/0")
      triples = ClosureBuilder.build_closure(anon, anon_iri, context)

      # Should have capturesVariable triples
      capture_triples =
        Enum.filter(triples, fn {_s, p, _o} -> p == Core.capturesVariable() end)

      assert length(capture_triples) >= 2
    end

    test "generates RDF for capture expression" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      # Verify IRI generated
      assert to_string(capture_iri) =~ "MyApp/&/0"

      # Verify type triple
      type_triples = Enum.filter(triples, fn {_s, p, _o} -> p == RDF.type() end)
      assert length(type_triples) >= 1
    end
  end

  # ===========================================================================
  # Backward Compatibility Tests
  # ===========================================================================

  describe "backward compatibility" do
    test "existing function extractor still works" do
      code = """
      def regular_function(x, y) do
        x + y
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)

      # Anonymous function extraction should not affect regular functions
      anon_funcs = AnonymousFunction.extract_all(ast)
      assert anon_funcs == []
    end

    test "module with mixed constructs extracts correctly" do
      code = """
      def mixed_module(data) do
        result = data |> Enum.map(&process/1)

        handler = fn
          {:ok, val} -> val
          {:error, _} -> nil
        end

        Enum.map(result, handler)
        |> Enum.filter(fn x -> x != nil end)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)

      anon_funcs = AnonymousFunction.extract_all(ast)
      captures = Capture.extract_all(ast)

      # Should find 2 anonymous functions (handler and filter fn)
      assert length(anon_funcs) >= 2

      # Should find 1 capture (&process/1)
      assert length(captures) >= 1
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "error handling for complex patterns" do
    test "handles empty anonymous function body" do
      ast = quote do: fn -> nil end
      result = AnonymousFunction.extract(ast)

      assert {:ok, anon} = result
      assert anon.arity == 0
    end

    test "handles anonymous function with only guard" do
      ast =
        quote do
          fn x when is_integer(x) -> x end
        end

      result = AnonymousFunction.extract(ast)

      assert {:ok, anon} = result
      assert length(anon.clauses) == 1
      assert hd(anon.clauses).guard != nil
    end

    test "handles deeply nested capture placeholders" do
      code = """
      def deep_placeholders do
        &((&1 + &2) * (&1 - &2))
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      captures = Capture.extract_all(ast)

      # Should find the shorthand capture
      shorthand = Enum.find(captures, &(&1.type == :shorthand))
      assert shorthand != nil
      assert shorthand.arity == 2
    end

    test "closure analysis handles no body references" do
      ast = quote do: fn _x -> :constant end
      {:ok, anon} = AnonymousFunction.extract(ast)

      {:ok, analysis} = Closure.analyze_closure(anon)
      assert analysis.has_captures == false
    end
  end
end
