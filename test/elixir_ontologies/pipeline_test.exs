defmodule ElixirOntologies.PipelineTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.{Pipeline, Config, Graph}
  alias ElixirOntologies.Analyzer.FileAnalyzer.ModuleAnalysis
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors.Module, as: ModuleExtractor
  alias ElixirOntologies.Extractors.Function, as: FunctionExtractor

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp build_test_context(opts \\ []) do
    Context.new(
      base_iri: Keyword.get(opts, :base_iri, "https://example.org/code#"),
      file_path: Keyword.get(opts, :file_path, nil)
    )
  end

  defp build_minimal_module_info(opts \\ []) do
    %ModuleExtractor{
      type: :module,
      name: Keyword.get(opts, :name, [:TestModule]),
      docstring: Keyword.get(opts, :docstring, nil),
      aliases: [],
      imports: [],
      requires: [],
      uses: [],
      functions: [],
      macros: [],
      types: [],
      location: nil,
      metadata: %{parent_module: nil, has_moduledoc: false, nested_modules: []}
    }
  end

  defp build_minimal_function_info(opts \\ []) do
    %FunctionExtractor{
      type: :function,
      name: Keyword.get(opts, :name, :test_function),
      arity: Keyword.get(opts, :arity, 0),
      min_arity: Keyword.get(opts, :arity, 0),
      visibility: Keyword.get(opts, :visibility, :public),
      docstring: nil,
      location: nil,
      metadata: %{module: Keyword.get(opts, :module, [:TestModule])}
    }
  end

  defp build_minimal_module_analysis(opts \\ []) do
    %ModuleAnalysis{
      name: Keyword.get(opts, :name, TestModule),
      module_info: Keyword.get(opts, :module_info, build_minimal_module_info()),
      functions: Keyword.get(opts, :functions, []),
      types: Keyword.get(opts, :types, []),
      specs: [],
      protocols: %{protocol: nil, implementations: []},
      behaviors: %{definition: nil, implementations: []},
      otp_patterns: %{genserver: nil, supervisor: nil, agent: nil, task: nil, ets: nil},
      attributes: [],
      macros: []
    }
  end

  # ===========================================================================
  # build_graph_for_modules/3 Tests
  # ===========================================================================

  describe "build_graph_for_modules/3" do
    test "builds graph for empty module list" do
      context = build_test_context()
      graph = Pipeline.build_graph_for_modules([], context)

      assert %Graph{} = graph
      assert Graph.empty?(graph)
    end

    test "builds graph for single module" do
      module_analysis = build_minimal_module_analysis()
      context = build_test_context()

      graph = Pipeline.build_graph_for_modules([module_analysis], context)

      assert %Graph{} = graph
      assert Graph.statement_count(graph) > 0
    end

    test "builds graph for multiple modules" do
      module1 = build_minimal_module_analysis(
        name: ModuleA,
        module_info: build_minimal_module_info(name: [:ModuleA])
      )
      module2 = build_minimal_module_analysis(
        name: ModuleB,
        module_info: build_minimal_module_info(name: [:ModuleB])
      )
      context = build_test_context()

      graph = Pipeline.build_graph_for_modules([module1, module2], context)

      assert %Graph{} = graph
      assert Graph.statement_count(graph) > 2
    end

    test "builds graph with functions" do
      func1 = build_minimal_function_info(name: :hello, arity: 0)
      func2 = build_minimal_function_info(name: :world, arity: 1)
      module_analysis = build_minimal_module_analysis(functions: [func1, func2])
      context = build_test_context()

      graph = Pipeline.build_graph_for_modules([module_analysis], context)

      assert Graph.statement_count(graph) > 3
    end

    test "builds graph with parallel: true" do
      module_analysis = build_minimal_module_analysis()
      context = build_test_context()

      graph = Pipeline.build_graph_for_modules([module_analysis], context, parallel: true)

      assert %Graph{} = graph
      assert Graph.statement_count(graph) > 0
    end

    test "builds graph with parallel: false" do
      module_analysis = build_minimal_module_analysis()
      context = build_test_context()

      graph = Pipeline.build_graph_for_modules([module_analysis], context, parallel: false)

      assert %Graph{} = graph
      assert Graph.statement_count(graph) > 0
    end

    test "parallel and sequential produce same result" do
      module_analysis = build_minimal_module_analysis()
      context = build_test_context()

      graph_parallel = Pipeline.build_graph_for_modules([module_analysis], context, parallel: true)
      graph_sequential = Pipeline.build_graph_for_modules([module_analysis], context, parallel: false)

      assert Graph.statement_count(graph_parallel) == Graph.statement_count(graph_sequential)
    end

    test "respects timeout option" do
      module_analysis = build_minimal_module_analysis()
      context = build_test_context()

      graph = Pipeline.build_graph_for_modules([module_analysis], context, timeout: 10_000)

      assert %Graph{} = graph
    end
  end

  # ===========================================================================
  # convert_module_analysis/1 Tests
  # ===========================================================================

  describe "convert_module_analysis/1" do
    test "converts basic module analysis" do
      module_analysis = build_minimal_module_analysis()

      result = Pipeline.convert_module_analysis(module_analysis)

      assert is_map(result)
      assert Map.has_key?(result, :module)
      assert Map.has_key?(result, :functions)
      assert Map.has_key?(result, :protocols)
      assert Map.has_key?(result, :behaviours)
      assert Map.has_key?(result, :types)
      assert Map.has_key?(result, :genservers)
      assert Map.has_key?(result, :supervisors)
      assert Map.has_key?(result, :agents)
      assert Map.has_key?(result, :tasks)
    end

    test "converts module with functions" do
      func1 = build_minimal_function_info(name: :hello)
      func2 = build_minimal_function_info(name: :world)
      module_analysis = build_minimal_module_analysis(functions: [func1, func2])

      result = Pipeline.convert_module_analysis(module_analysis)

      assert length(result.functions) == 2
    end

    test "handles nil module_info" do
      module_analysis = build_minimal_module_analysis(module_info: nil)

      result = Pipeline.convert_module_analysis(module_analysis)

      assert result.module == nil
    end

    test "handles empty OTP patterns" do
      module_analysis = build_minimal_module_analysis()

      result = Pipeline.convert_module_analysis(module_analysis)

      assert result.genservers == []
      assert result.supervisors == []
      assert result.agents == []
      assert result.tasks == []
    end
  end

  # ===========================================================================
  # analyze_string_and_build/3 Tests
  # ===========================================================================

  describe "analyze_string_and_build/3" do
    test "analyzes simple module string with function" do
      source = """
      defmodule TestModule do
        def hello, do: :world
      end
      """

      {:ok, result} = Pipeline.analyze_string_and_build(source)

      assert result.modules != []
      assert %Graph{} = result.graph
      # Should have module and function triples
      assert Graph.statement_count(result.graph) > 1
    end

    test "analyzes module with multiple functions" do
      source = """
      defmodule MyApp.Users do
        def get_user(id), do: {:ok, id}
        def create_user(attrs), do: {:ok, attrs}
        defp validate(attrs), do: attrs
      end
      """

      {:ok, result} = Pipeline.analyze_string_and_build(source)

      assert result.modules != []
      assert Graph.statement_count(result.graph) > 0
    end

    test "uses custom config" do
      source = "defmodule Test do end"
      config = Config.new(base_iri: "https://custom.org/code#")

      {:ok, result} = Pipeline.analyze_string_and_build(source, config)

      assert result.graph != nil
    end

    test "returns error for invalid syntax" do
      source = "defmodule Test do"

      result = Pipeline.analyze_string_and_build(source)

      assert {:error, _reason} = result
    end

    test "handles empty source" do
      source = ""

      {:ok, result} = Pipeline.analyze_string_and_build(source)

      assert result.modules == []
    end

    test "handles nested modules with functions" do
      source = """
      defmodule Outer do
        defmodule Inner do
          def nested, do: :inner
        end
        def outer, do: :outer
      end
      """

      {:ok, result} = Pipeline.analyze_string_and_build(source)

      # Should find both modules
      assert length(result.modules) >= 1
      assert Graph.statement_count(result.graph) > 0
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles module with no functions" do
      module_analysis = build_minimal_module_analysis(functions: [])
      context = build_test_context()

      graph = Pipeline.build_graph_for_modules([module_analysis], context)

      # Should still have module triples
      assert Graph.statement_count(graph) > 0
    end

    test "handles different base IRIs" do
      module_analysis = build_minimal_module_analysis()
      context = build_test_context(base_iri: "https://different.org/app#")

      graph = Pipeline.build_graph_for_modules([module_analysis], context)

      assert Graph.statement_count(graph) > 0
    end

    test "handles module with nested name" do
      module_analysis = build_minimal_module_analysis(
        name: MyApp.Services.UserManager,
        module_info: build_minimal_module_info(name: [:MyApp, :Services, :UserManager])
      )
      context = build_test_context()

      graph = Pipeline.build_graph_for_modules([module_analysis], context)

      assert Graph.statement_count(graph) > 0
    end

    test "handles large number of modules in parallel" do
      modules = for i <- 1..10 do
        build_minimal_module_analysis(
          name: :"Module#{i}",
          module_info: build_minimal_module_info(name: [:"Module#{i}"])
        )
      end
      context = build_test_context()

      graph = Pipeline.build_graph_for_modules(modules, context, parallel: true)

      # Should have triples for all modules
      assert Graph.statement_count(graph) >= 10
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "full pipeline produces valid RDF graph with functions" do
      source = """
      defmodule MyApp.Calculator do
        @moduledoc "A simple calculator"

        def add(a, b), do: a + b
        def subtract(a, b), do: a - b
        defp validate(n), do: n
      end
      """

      {:ok, result} = Pipeline.analyze_string_and_build(source)

      # Graph should have module and function triples
      assert Graph.statement_count(result.graph) > 3

      # Can serialize to Turtle
      {:ok, turtle} = Graph.to_turtle(result.graph)
      assert is_binary(turtle)
      assert String.contains?(turtle, "Module")
    end

    test "pipeline preserves module analysis metadata" do
      source = """
      defmodule Test do
        def hello, do: :world
      end
      """

      {:ok, result} = Pipeline.analyze_string_and_build(source)

      assert result.file_path == "<string>"
      assert result.metadata.module_count == 1
    end

    test "full pipeline with test helper functions" do
      # Using test helpers where we control the module context in function metadata
      func1 = build_minimal_function_info(name: :add, arity: 2)
      func2 = build_minimal_function_info(name: :subtract, arity: 2)
      module_analysis = build_minimal_module_analysis(
        name: :"MyApp.Calculator",
        module_info: build_minimal_module_info(name: [:MyApp, :Calculator]),
        functions: [func1, func2]
      )
      context = build_test_context()

      graph = Pipeline.build_graph_for_modules([module_analysis], context)

      # Graph should have module and function triples
      assert Graph.statement_count(graph) > 3

      # Can serialize to Turtle
      {:ok, turtle} = Graph.to_turtle(graph)
      assert is_binary(turtle)
      assert String.contains?(turtle, "Module")
    end

    test "functions have correct module context in graph" do
      source = """
      defmodule MyApp.Users do
        def get_user(id), do: {:ok, id}
      end
      """

      {:ok, result} = Pipeline.analyze_string_and_build(source)

      # Serialize and check for function IRI containing module name
      {:ok, turtle} = Graph.to_turtle(result.graph)
      assert String.contains?(turtle, "MyApp.Users")
    end
  end
end
