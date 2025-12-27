defmodule ElixirOntologies.Phase17IntegrationTest do
  @moduledoc """
  Integration tests for Phase 17: Call Graph and Control Flow.

  These tests verify end-to-end functionality of call extraction, control flow
  analysis, exception handling, and RDF generation working together through
  the Pipeline and Orchestrator.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.{Call, Conditional, Comprehension, Exception}
  alias ElixirOntologies.Extractors.Pipe
  alias ElixirOntologies.Extractors.CaseWith

  alias ElixirOntologies.Builders.{
    Context,
    CallGraphBuilder,
    ControlFlowBuilder,
    ExceptionBuilder
  }

  alias ElixirOntologies.NS.Core

  @moduletag :integration

  # ===========================================================================
  # Complete Call Graph Extraction Tests
  # ===========================================================================

  describe "complete call graph extraction" do
    test "extracts all call types from complex function" do
      code = """
      def process(data) do
        data
        |> validate()
        |> Enum.map(&transform/1)
        |> Enum.filter(fn x -> x != nil end)
        |> apply(Helper, :finalize, [])
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)

      # Extract all call types
      local_calls = Call.extract_local_calls(ast)
      remote_calls = Call.extract_remote_calls(ast)
      dynamic_calls = Call.extract_dynamic_calls(ast)
      pipe_chains = Pipe.extract_pipe_chains(ast)

      # Verify local calls found
      local_names = Enum.map(local_calls, & &1.name)
      assert :validate in local_names
      # Note: &transform/1 is a capture, not a direct local call

      # Verify remote calls found
      remote_modules = Enum.map(remote_calls, & &1.module)
      assert [:Enum] in remote_modules

      # Verify dynamic call (apply/4)
      assert length(dynamic_calls) >= 1

      # Verify pipe chain
      assert length(pipe_chains) == 1
      [chain] = pipe_chains
      assert chain.length >= 4
    end

    test "extracts nested calls within function arguments" do
      code = """
      def nested(x) do
        outer(inner(deep(x)))
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      calls = Call.extract_local_calls(ast)

      names = Enum.map(calls, & &1.name)
      assert :outer in names
      assert :inner in names
      assert :deep in names
    end
  end

  # ===========================================================================
  # Cross-Module Call Graph Tests
  # ===========================================================================

  describe "cross-module call graph" do
    test "identifies calls to multiple external modules" do
      code = """
      def multi_module_calls(data) do
        result = String.upcase(data)
        length = String.length(result)
        Enum.take(result, length)
        |> List.flatten()
        |> Map.new(fn x -> {x, true} end)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      calls = Call.extract_remote_calls(ast)

      modules =
        calls
        |> Enum.map(& &1.module)
        |> Enum.uniq()

      assert [:String] in modules
      assert [:Enum] in modules
      assert [:List] in modules
      assert [:Map] in modules
    end

    test "handles Erlang module calls" do
      code = """
      def erlang_calls(data) do
        :erlang.binary_to_list(data)
        |> :lists.reverse()
        |> :erlang.list_to_binary()
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      calls = Call.extract_remote_calls(ast)

      modules = Enum.map(calls, & &1.module)
      assert :erlang in modules
      assert :lists in modules
    end
  end

  # ===========================================================================
  # Control Flow Extraction Tests
  # ===========================================================================

  describe "control flow extraction accuracy" do
    test "extracts all conditional types" do
      code = """
      def all_conditionals(x, y) do
        if x > 0 do
          :positive
        else
          unless y < 0 do
            cond do
              x == y -> :equal
              x > y -> :greater
              true -> :less
            end
          end
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      conditionals = Conditional.extract_conditionals(ast)

      types = Enum.map(conditionals, & &1.type)
      assert :if in types
      assert :unless in types
      assert :cond in types
    end

    test "extracts case and with expressions" do
      code = """
      def pattern_matching(data) do
        case data do
          {:ok, value} -> value
          {:error, reason} -> raise reason
        end

        with {:ok, a} <- fetch_a(),
             {:ok, b} <- fetch_b(a) do
          {:ok, {a, b}}
        else
          {:error, reason} -> {:error, reason}
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)

      case_exprs = CaseWith.extract_case_expressions(ast)
      with_exprs = CaseWith.extract_with_expressions(ast)

      assert length(case_exprs) >= 1
      assert length(with_exprs) >= 1

      [case_expr] = case_exprs
      assert length(case_expr.clauses) == 2

      [with_expr] = with_exprs
      assert length(with_expr.clauses) >= 2
    end
  end

  # ===========================================================================
  # Exception Handling Tests
  # ===========================================================================

  describe "exception handling coverage" do
    test "extracts try with all clause types" do
      code = """
      def full_try(f) do
        try do
          f.()
        rescue
          ArgumentError -> :arg_error
          RuntimeError -> :runtime_error
        catch
          :throw, value -> {:thrown, value}
          :exit, reason -> {:exited, reason}
        else
          result -> {:ok, result}
        after
          cleanup()
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, try_expr} = Exception.extract_try(ast |> get_try_ast())

      assert try_expr.has_rescue
      assert try_expr.has_catch
      assert try_expr.has_else
      assert try_expr.has_after

      assert length(try_expr.rescue_clauses) == 2
      assert length(try_expr.catch_clauses) == 2
    end

    test "extracts raise and throw expressions" do
      code = """
      def error_handling(x) do
        if x < 0 do
          raise ArgumentError, "must be positive"
        end

        if x > 100 do
          throw {:too_large, x}
        end

        x
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)

      raises = Exception.extract_raises(ast)
      throws = Exception.extract_throws(ast)

      assert length(raises) >= 1
      assert length(throws) >= 1
    end
  end

  # ===========================================================================
  # RDF Builder Integration Tests
  # ===========================================================================

  describe "call graph RDF generation" do
    test "builds valid RDF triples for local call" do
      call = %Call.FunctionCall{
        type: :local,
        name: :helper,
        arity: 2,
        arguments: [:a, :b],
        location: %{line: 10}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {iri, triples} =
        CallGraphBuilder.build(call, context,
          containing_function: "MyApp/process/1",
          index: 0
        )

      assert %RDF.IRI{} = iri
      assert length(triples) >= 3

      # Verify type triple
      type_triple = Enum.find(triples, fn {_, p, _} -> p == RDF.type() end)
      assert elem(type_triple, 2) == Core.LocalCall
    end

    test "builds valid RDF triples for remote call" do
      call = %Call.FunctionCall{
        type: :remote,
        name: :map,
        arity: 2,
        module: [:Enum],
        arguments: [[], :fn],
        location: %{line: 15}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {iri, triples} =
        CallGraphBuilder.build(call, context,
          containing_function: "MyApp/process/1",
          index: 0
        )

      assert %RDF.IRI{} = iri
      assert length(triples) >= 4

      # Verify type triple
      type_triple = Enum.find(triples, fn {_, p, _} -> p == RDF.type() end)
      assert elem(type_triple, 2) == Core.RemoteCall
    end
  end

  describe "control flow RDF generation" do
    test "builds valid RDF for if expression" do
      {:ok, cond_struct} =
        Conditional.extract_if({:if, [line: 5], [{:x, [], nil}, [do: :ok, else: :error]]})

      context = Context.new(base_iri: "https://example.org/code#")

      {iri, triples} =
        ControlFlowBuilder.build_conditional(cond_struct, context,
          containing_function: "MyApp/check/1",
          index: 0
        )

      assert %RDF.IRI{} = iri
      assert length(triples) >= 2
    end

    test "builds valid RDF for case expression" do
      {:ok, case_struct} =
        CaseWith.extract_case(
          {:case, [line: 10], [{:x, [], nil}, [do: [{:->, [], [[:ok], :success]}]]]}
        )

      context = Context.new(base_iri: "https://example.org/code#")

      {iri, triples} =
        ControlFlowBuilder.build_case(case_struct, context,
          containing_function: "MyApp/handle/1",
          index: 0
        )

      assert %RDF.IRI{} = iri
      assert length(triples) >= 1
    end
  end

  describe "exception RDF generation" do
    test "builds valid RDF for try expression" do
      try_struct = %Exception{
        body: :ok,
        has_rescue: true,
        has_catch: false,
        has_else: false,
        has_after: true,
        rescue_clauses: [%Exception.RescueClause{body: :error, is_catch_all: true}],
        catch_clauses: [],
        else_clauses: [],
        after_body: :cleanup,
        location: %{line: 20}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {iri, triples} =
        ExceptionBuilder.build_try(try_struct, context,
          containing_function: "MyApp/safe/0",
          index: 0
        )

      assert %RDF.IRI{} = iri
      assert length(triples) >= 3
    end
  end

  # ===========================================================================
  # Pipe Chain Tests
  # ===========================================================================

  describe "pipe chain representation" do
    test "preserves pipe chain ordering" do
      code = """
      data
      |> step_one()
      |> step_two()
      |> step_three()
      |> step_four()
      """

      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, chain} = Pipe.extract_pipe_chain(ast)

      step_names = Enum.map(chain.steps, & &1.call.name)
      assert step_names == [:step_one, :step_two, :step_three, :step_four]

      indices = Enum.map(chain.steps, & &1.index)
      assert indices == [0, 1, 2, 3]
    end

    test "handles mixed local and remote calls in pipe" do
      code = """
      data
      |> local_transform()
      |> Enum.map(&process/1)
      |> another_local()
      |> String.trim()
      """

      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, chain} = Pipe.extract_pipe_chain(ast)

      types = Enum.map(chain.steps, & &1.call.type)
      assert types == [:local, :remote, :local, :remote]
    end
  end

  # ===========================================================================
  # Recursive Function Tests
  # ===========================================================================

  describe "recursive function detection" do
    test "detects direct recursion" do
      code = """
      def factorial(0), do: 1
      def factorial(n), do: n * factorial(n - 1)
      """

      {:ok, ast} = Code.string_to_quoted(code)
      calls = Call.extract_local_calls(ast)

      recursive_calls = Enum.filter(calls, &(&1.name == :factorial))
      assert length(recursive_calls) >= 1
    end

    test "detects tail recursion pattern" do
      code = """
      def sum_list([], acc), do: acc
      def sum_list([h | t], acc), do: sum_list(t, acc + h)
      """

      {:ok, ast} = Code.string_to_quoted(code)
      calls = Call.extract_local_calls(ast)

      recursive_calls = Enum.filter(calls, &(&1.name == :sum_list))
      assert length(recursive_calls) >= 1
    end
  end

  # ===========================================================================
  # Dynamic Call Tests
  # ===========================================================================

  describe "dynamic call handling" do
    test "extracts apply/3 with list args" do
      code = """
      def dynamic(mod, func) do
        apply(mod, func, [1, 2, 3])
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      calls = Call.extract_dynamic_calls(ast)

      # apply with variable module and list args
      assert length(calls) >= 1
      var_call = Enum.find(calls, &(&1.metadata[:module_variable] == :mod))
      assert var_call != nil
    end

    test "extracts anonymous function calls" do
      code = """
      def with_callback(callback) do
        result = callback.(1, 2)
        callback.(result)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      calls = Call.extract_dynamic_calls(ast)

      assert length(calls) >= 2

      anon_calls = Enum.filter(calls, &(&1.metadata[:dynamic_type] == :anonymous_call))
      assert length(anon_calls) >= 2
    end
  end

  # ===========================================================================
  # Receive Expression Tests
  # ===========================================================================

  describe "receive expression in GenServer" do
    test "extracts receive with after timeout" do
      code = """
      def wait_for_message do
        receive do
          {:msg, data} -> {:ok, data}
          :stop -> :stopped
        after
          5000 -> :timeout
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      receives = CaseWith.extract_receive_expressions(ast)

      assert length(receives) >= 1
      [recv] = receives
      assert recv.has_after
      assert length(recv.clauses) >= 2
    end
  end

  # ===========================================================================
  # Comprehension Tests
  # ===========================================================================

  describe "comprehension extraction" do
    test "extracts for comprehension with all features" do
      code = """
      def transform(list, map) do
        for x <- list,
            y <- Map.keys(map),
            x > 0,
            y != :skip,
            into: %{},
            do: {x, y}
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      comps = Comprehension.extract_for_loops(ast)

      assert length(comps) >= 1
      [comp] = comps

      assert comp.metadata.generator_count == 2
      assert comp.metadata.filter_count == 2
      assert comp.metadata.has_into
    end

    test "extracts nested comprehensions" do
      code = """
      def matrix(rows, cols) do
        for i <- 1..rows do
          for j <- 1..cols, do: {i, j}
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      comps = Comprehension.extract_for_loops(ast)

      assert length(comps) == 2
    end
  end

  # ===========================================================================
  # Nested Control Flow Tests
  # ===========================================================================

  describe "nested control flow structures" do
    test "extracts deeply nested conditionals" do
      code = """
      def deep(a, b, c) do
        if a do
          case b do
            :one ->
              cond do
                c > 0 -> :positive
                c < 0 -> :negative
                true -> :zero
              end
            :two ->
              unless c do
                :default
              end
          end
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)

      conditionals = Conditional.extract_conditionals(ast)
      cases = CaseWith.extract_case_expressions(ast)

      # Should find if, unless, cond
      cond_types = Enum.map(conditionals, & &1.type)
      assert :if in cond_types
      assert :unless in cond_types
      assert :cond in cond_types

      # Should find case
      assert length(cases) >= 1
    end
  end

  # ===========================================================================
  # Backward Compatibility Tests
  # ===========================================================================

  describe "backward compatibility" do
    test "call extraction works with existing module extractor patterns" do
      code = """
      defmodule TestModule do
        def public_func(x), do: helper(x)
        defp helper(x), do: x * 2
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)

      # Extract calls - should work on full module AST
      calls = Call.extract_all_calls(ast)

      # Should find the helper call from public_func
      helper_call = Enum.find(calls, &(&1.name == :helper))
      assert helper_call != nil
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "error handling for complex AST" do
    test "handles empty function body" do
      code = """
      def empty, do: nil
      """

      {:ok, ast} = Code.string_to_quoted(code)

      # Should not crash
      calls = Call.extract_all_calls(ast)
      assert is_list(calls)
    end

    test "handles malformed-looking but valid AST" do
      code = """
      def weird(x) do
        (fn -> x end).()
        (&(&1 + 1)).(5)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)

      # Should extract anonymous function calls
      calls = Call.extract_dynamic_calls(ast)
      assert is_list(calls)
    end
  end

  # ===========================================================================
  # Pipeline Integration Tests
  # ===========================================================================

  describe "Pipeline integration with Phase 17 extractors" do
    test "Pipeline.analyze_string_and_build extracts calls and control flow" do
      source = """
      defmodule TestModule do
        def process(x) do
          if x > 0 do
            helper(x)
          else
            Enum.map([x], &abs/1)
          end
        end

        defp helper(y), do: y * 2
      end
      """

      config = ElixirOntologies.Config.new(base_iri: "https://test.org/code#")
      {:ok, result} = ElixirOntologies.Pipeline.analyze_string_and_build(source, config)

      # Verify that the graph was built
      assert %ElixirOntologies.Graph{} = result.graph

      # Verify modules were analyzed
      assert length(result.modules) == 1
      [module_analysis] = result.modules

      # Verify Phase 17 data was extracted
      assert is_list(module_analysis.calls)
      assert is_map(module_analysis.control_flow)
      assert is_map(module_analysis.exceptions)

      # Verify calls were extracted
      assert length(module_analysis.calls) > 0

      # Verify conditionals were extracted
      assert length(module_analysis.control_flow.conditionals) > 0
    end

    test "Pipeline builds RDF with Phase 17 triples" do
      source = """
      defmodule SimpleModule do
        def test(x) do
          case x do
            :ok -> helper()
            :error -> raise "error"
          end
        end

        defp helper, do: :done
      end
      """

      config = ElixirOntologies.Config.new(base_iri: "https://test.org/code#")
      {:ok, result} = ElixirOntologies.Pipeline.analyze_string_and_build(source, config)

      # Check graph has triples (including Phase 17)
      graph = result.graph
      triple_count = ElixirOntologies.Graph.statement_count(graph)
      assert triple_count > 0
    end
  end

  # ===========================================================================
  # Orchestrator Coordination Tests
  # ===========================================================================

  describe "Orchestrator coordination with Phase 17 builders" do
    test "Orchestrator builds graph with call graph triples" do
      # Create minimal analysis data with Phase 17 structures
      analysis = %{
        module: %ElixirOntologies.Extractors.Module{
          type: :module,
          name: [:TestModule],
          docstring: nil,
          aliases: [],
          imports: [],
          requires: [],
          uses: [],
          functions: [],
          macros: [],
          types: [],
          location: nil,
          metadata: %{parent_module: nil, has_moduledoc: false, nested_modules: []}
        },
        functions: [],
        calls: [
          %Call.FunctionCall{
            type: :local,
            name: :helper,
            arity: 1,
            arguments: [:x],
            location: %{line: 10}
          }
        ],
        control_flow: %{
          conditionals: [],
          cases: [],
          withs: []
        },
        exceptions: %{
          tries: [],
          raises: [],
          throws: []
        }
      }

      context = Context.new(base_iri: "https://test.org/code#")
      {:ok, graph} = ElixirOntologies.Builders.Orchestrator.build_module_graph(analysis, context)

      # Verify graph was built
      assert %RDF.Graph{} = graph

      # Verify it contains triples (module + call triples)
      assert RDF.Graph.statement_count(graph) > 0

      # Find call triples (LocalCall type)
      triples = RDF.Graph.triples(graph)

      call_triples =
        Enum.filter(triples, fn {s, _p, _o} ->
          to_string(s) =~ "call/"
        end)

      assert length(call_triples) > 0
    end

    test "Orchestrator handles empty Phase 17 data gracefully" do
      # Analysis with no calls/control flow/exceptions
      analysis = %{
        module: %ElixirOntologies.Extractors.Module{
          type: :module,
          name: [:EmptyModule],
          docstring: nil,
          aliases: [],
          imports: [],
          requires: [],
          uses: [],
          functions: [],
          macros: [],
          types: [],
          location: nil,
          metadata: %{parent_module: nil, has_moduledoc: false, nested_modules: []}
        },
        functions: [],
        calls: [],
        control_flow: %{
          conditionals: [],
          cases: [],
          withs: []
        },
        exceptions: %{
          tries: [],
          raises: [],
          throws: []
        }
      }

      context = Context.new(base_iri: "https://test.org/code#")
      {:ok, graph} = ElixirOntologies.Builders.Orchestrator.build_module_graph(analysis, context)

      # Should succeed with just module triples
      assert %RDF.Graph{} = graph
      assert RDF.Graph.statement_count(graph) > 0
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp get_try_ast(ast) do
    case ast do
      {:def, _, [_, [do: body]]} -> get_try_from_body(body)
      {:try, _, _} = try_ast -> try_ast
      _ -> ast
    end
  end

  defp get_try_from_body({:try, _, _} = try_ast), do: try_ast
  defp get_try_from_body({:__block__, _, stmts}), do: Enum.find(stmts, &match?({:try, _, _}, &1))
  defp get_try_from_body(_), do: nil
end
