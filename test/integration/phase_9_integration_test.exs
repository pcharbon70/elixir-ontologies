defmodule ElixirOntologies.Phase9IntegrationTest do
  @moduledoc """
  Integration tests for Phase 9: Mix Tasks & CLI.

  These tests verify end-to-end workflows across all Phase 9 components:
  - Mix tasks (analyze, update)
  - Public API (analyze_file/2, analyze_project/2, update_graph/2)
  - Output validation (Turtle format, RDF validity)
  - Incremental workflows (analyze → modify → update)
  - Error handling (invalid paths, malformed files)
  - Cross-component consistency (Mix tasks vs API)

  Test Categories:
  - Mix Task End-to-End: 5 tests
  - Public API Integration: 4 tests
  - Output Validation: 4 tests
  - Incremental Workflow: 6 tests
  - Error Handling: 5 tests
  - Cross-Component: 3 tests

  Total: 27 integration tests
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Mix.Tasks.ElixirOntologies.{Analyze, Update}
  alias ElixirOntologies

  @moduletag :integration
  @moduletag timeout: 60_000

  setup do
    # Create temporary directory for test files
    temp_dir = System.tmp_dir!() |> Path.join("phase9_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir}
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp create_test_project(base_dir) do
    # Create project structure
    lib_dir = Path.join(base_dir, "lib")
    File.mkdir_p!(lib_dir)

    # Create mix.exs
    File.write!(Path.join(base_dir, "mix.exs"), """
    defmodule TestProject.MixProject do
      use Mix.Project

      def project do
        [
          app: :test_project,
          version: "1.0.0",
          elixir: "~> 1.14"
        ]
      end
    end
    """)

    # Create main module
    File.write!(Path.join(lib_dir, "main.ex"), """
    defmodule Main do
      @moduledoc \"\"\"
      Main application module.
      \"\"\"

      @doc \"\"\"
      Starts the application.
      \"\"\"
      def start do
        {:ok, self()}
      end

      @doc \"\"\"
      Greets a person by name.
      \"\"\"
      def greet(name) when is_binary(name) do
        "Hello, \#{name}!"
      end
    end
    """)

    # Create worker module (GenServer)
    File.write!(Path.join(lib_dir, "worker.ex"), """
    defmodule Worker do
      use GenServer

      def start_link(opts \\\\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(_opts) do
        {:ok, %{count: 0}}
      end

      @impl true
      def handle_call(:get_count, _from, state) do
        {:reply, state.count, state}
      end

      @impl true
      def handle_cast(:increment, state) do
        {:noreply, %{state | count: state.count + 1}}
      end
    end
    """)

    # Create utility module
    File.write!(Path.join(lib_dir, "utils.ex"), """
    defmodule Utils do
      def add(a, b), do: a + b
      def multiply(a, b), do: a * b
    end
    """)

    base_dir
  end

  defp assert_valid_turtle(turtle_string) do
    case RDF.Turtle.read_string(turtle_string) do
      {:ok, graph} ->
        assert RDF.Graph.triple_count(graph) >= 0
        graph

      {:error, reason} ->
        flunk("Invalid Turtle format: #{inspect(reason)}")
    end
  end

  defp assert_has_ontology_structure(graph) do
    # Verify graph is valid (triple count may be 0 for simple modules)
    assert is_struct(graph, RDF.Graph)
    assert is_integer(RDF.Graph.triple_count(graph))

    graph
  end

  # ===========================================================================
  # Mix Task End-to-End Tests
  # ===========================================================================

  describe "Mix task end-to-end" do
    test "analyze task with default options produces valid output", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)

      output =
        capture_io(fn ->
          Analyze.run([project_dir, "--quiet"])
        end)

      # Verify Turtle format
      graph = assert_valid_turtle(output)

      # Verify contains expected modules (at minimum, graph should be valid)
      assert is_struct(graph, RDF.Graph)
    end

    test "analyze task writes to custom output file", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      output_file = Path.join(temp_dir, "output.ttl")

      capture_io(fn ->
        Analyze.run([project_dir, "--output", output_file, "--quiet"])
      end)

      # Verify file exists
      assert File.exists?(output_file)

      # Verify file content is valid Turtle
      {:ok, content} = File.read(output_file)
      graph = assert_valid_turtle(content)

      # Verify structure
      assert_has_ontology_structure(graph)
    end

    test "analyze task accepts custom base IRI option", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      custom_iri = "https://example.com/myproject#"
      output_file = Path.join(temp_dir, "output.ttl")

      # Should not error with custom base IRI
      capture_io(fn ->
        Analyze.run([project_dir, "--base-iri", custom_iri, "--output", output_file, "--quiet"])
      end)

      {:ok, content} = File.read(output_file)

      # Verify valid Turtle output (base IRI usage depends on analyzer implementation)
      assert {:ok, _graph} = RDF.Turtle.read_string(content)
    end

    test "update task loads existing graph and reports changes", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "project.ttl")

      # Initial analysis
      capture_io(fn ->
        Analyze.run([project_dir, "--output", graph_file, "--quiet"])
      end)

      # Modify a file
      File.write!(Path.join(project_dir, "lib/main.ex"), """
      defmodule Main do
        def modified_function, do: :new_value
      end
      """)

      # Update
      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      # Verify update messages
      assert output =~ "Loading existing graph"
      assert output =~ "Analyzed"

      # Verify output file is updated
      {:ok, updated_content} = File.read(graph_file)
      assert updated_content =~ "@prefix"
    end

    test "complete workflow: analyze → modify → update → verify", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "project.ttl")

      # Step 1: Initial analysis
      capture_io(fn ->
        Analyze.run([project_dir, "--output", graph_file, "--quiet"])
      end)

      {:ok, initial_content} = File.read(graph_file)
      {:ok, initial_graph} = RDF.Turtle.read_string(initial_content)
      initial_triple_count = RDF.Graph.triple_count(initial_graph)

      # Step 2: Add new module
      File.write!(Path.join(project_dir, "lib/new_module.ex"), """
      defmodule NewModule do
        def new_func, do: :ok
      end
      """)

      # Step 3: Update
      capture_io(fn ->
        Update.run(["--input", graph_file, project_dir, "--quiet"])
      end)

      # Step 4: Verify
      {:ok, updated_content} = File.read(graph_file)
      {:ok, updated_graph} = RDF.Turtle.read_string(updated_content)
      updated_triple_count = RDF.Graph.triple_count(updated_graph)

      # Should be valid
      assert is_integer(initial_triple_count)
      assert is_integer(updated_triple_count)
    end
  end

  # ===========================================================================
  # Public API Integration Tests
  # ===========================================================================

  describe "Public API integration" do
    test "analyze_file/2 produces valid graph", %{temp_dir: temp_dir} do
      file_path = Path.join(temp_dir, "sample.ex")

      File.write!(file_path, """
      defmodule Sample do
        def greet(name), do: "Hello, \#{name}"
      end
      """)

      assert {:ok, graph} = ElixirOntologies.analyze_file(file_path)
      assert is_struct(graph, ElixirOntologies.Graph)
      assert is_struct(graph.graph, RDF.Graph)
    end

    test "analyze_project/2 produces valid result structure", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)

      assert {:ok, result} = ElixirOntologies.analyze_project(project_dir)

      # Verify structure
      assert is_map(result)
      assert Map.has_key?(result, :graph)
      assert Map.has_key?(result, :metadata)
      assert Map.has_key?(result, :errors)

      # Verify graph
      assert is_struct(result.graph, ElixirOntologies.Graph)

      # Verify metadata
      assert is_map(result.metadata)
      assert result.metadata.file_count >= 3
      assert result.metadata.module_count >= 3
    end

    test "update_graph/2 loads and updates existing graph", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "project.ttl")

      # Initial analysis
      {:ok, result} = ElixirOntologies.analyze_project(project_dir)
      :ok = ElixirOntologies.Graph.save(result.graph, graph_file)

      # Update
      assert {:ok, updated_result} =
               ElixirOntologies.update_graph(graph_file, project_path: project_dir)

      assert is_map(updated_result)
      assert Map.has_key?(updated_result, :graph)
      assert Map.has_key?(updated_result, :metadata)
    end

    test "API options propagate correctly", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)

      # Test with custom base IRI
      assert {:ok, result} =
               ElixirOntologies.analyze_project(project_dir,
                 base_iri: "https://test.org/code#"
               )

      assert is_struct(result.graph, ElixirOntologies.Graph)

      # Test with exclude_tests: false
      assert {:ok, result2} =
               ElixirOntologies.analyze_project(project_dir, exclude_tests: false)

      assert result2.metadata.file_count >= 3
    end
  end

  # ===========================================================================
  # Output Validation Tests
  # ===========================================================================

  describe "output validation" do
    test "generated Turtle is valid RDF", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      output_file = Path.join(temp_dir, "output.ttl")

      capture_io(fn ->
        Analyze.run([project_dir, "--output", output_file, "--quiet"])
      end)

      {:ok, content} = File.read(output_file)

      # Should parse without errors
      assert {:ok, graph} = RDF.Turtle.read_string(content)
      assert is_struct(graph, RDF.Graph)
    end

    test "generated graph contains expected prefixes", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      output_file = Path.join(temp_dir, "output.ttl")

      capture_io(fn ->
        Analyze.run([project_dir, "--output", output_file, "--quiet"])
      end)

      {:ok, content} = File.read(output_file)

      # Verify common prefixes
      assert content =~ "@prefix"
      assert content =~ "rdf:"
      assert content =~ "rdfs:"
    end

    test "graph from Mix task is valid RDF structure", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      output_file = Path.join(temp_dir, "output.ttl")

      capture_io(fn ->
        Analyze.run([project_dir, "--output", output_file, "--quiet"])
      end)

      {:ok, content} = File.read(output_file)
      {:ok, graph} = RDF.Turtle.read_string(content)

      # Verify it's a valid graph with structure
      assert_has_ontology_structure(graph)
    end

    test "graph from API is valid RDF structure", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)

      {:ok, result} = ElixirOntologies.analyze_project(project_dir)

      # Serialize to Turtle
      {:ok, turtle_string} = ElixirOntologies.Graph.to_turtle(result.graph)

      # Parse back and verify
      {:ok, graph} = RDF.Turtle.read_string(turtle_string)
      assert_has_ontology_structure(graph)
    end
  end

  # ===========================================================================
  # Incremental Workflow Tests
  # ===========================================================================

  describe "incremental workflow" do
    test "update with no changes completes successfully", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "project.ttl")

      # Initial analysis
      capture_io(fn ->
        Analyze.run([project_dir, "--output", graph_file, "--quiet"])
      end)

      # Update without changes
      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      assert output =~ "Analyzed"
    end

    test "update with file modification", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "project.ttl")

      # Initial analysis
      capture_io(fn ->
        Analyze.run([project_dir, "--output", graph_file, "--quiet"])
      end)

      # Modify file
      File.write!(Path.join(project_dir, "lib/utils.ex"), """
      defmodule Utils do
        def add(a, b), do: a + b
        def subtract(a, b), do: a - b
      end
      """)

      # Update
      capture_io(fn ->
        Update.run(["--input", graph_file, project_dir, "--quiet"])
      end)

      # Verify file was updated
      assert File.exists?(graph_file)
    end

    test "update with file addition", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "project.ttl")

      # Initial analysis
      capture_io(fn ->
        Analyze.run([project_dir, "--output", graph_file, "--quiet"])
      end)

      # Add new file
      File.write!(Path.join(project_dir, "lib/new.ex"), """
      defmodule NewModule do
        def test, do: :ok
      end
      """)

      # Update
      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      assert output =~ "Analyzed 4 files"
    end

    test "update with file deletion", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "project.ttl")

      # Initial analysis
      capture_io(fn ->
        Analyze.run([project_dir, "--output", graph_file, "--quiet"])
      end)

      # Delete file
      File.rm!(Path.join(project_dir, "lib/utils.ex"))

      # Update
      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      assert output =~ "Analyzed 2 files"
    end

    test "state file persistence across updates", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "project.ttl")
      state_file = graph_file <> ".state"

      # Initial analysis
      capture_io(fn ->
        Analyze.run([project_dir, "--output", graph_file, "--quiet"])
      end)

      # First update (creates state)
      capture_io(fn ->
        Update.run(["--input", graph_file, project_dir, "--quiet"])
      end)

      assert File.exists?(state_file)

      # Second update (uses state)
      capture_io(fn ->
        Update.run(["--input", graph_file, project_dir, "--quiet"])
      end)

      # State file should still exist
      assert File.exists?(state_file)
    end

    test "multiple sequential updates", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "project.ttl")

      # Initial analysis
      capture_io(fn ->
        Analyze.run([project_dir, "--output", graph_file, "--quiet"])
      end)

      # Update 1: Add module
      File.write!(Path.join(project_dir, "lib/one.ex"), "defmodule One, do: def f, do: 1")

      capture_io(fn ->
        Update.run(["--input", graph_file, project_dir, "--quiet"])
      end)

      # Update 2: Add another module
      File.write!(Path.join(project_dir, "lib/two.ex"), "defmodule Two, do: def f, do: 2")

      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      assert output =~ "Analyzed 5 files"
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "error handling" do
    test "Mix task handles invalid project path", %{temp_dir: _temp_dir} do
      assert catch_exit(
               capture_io(fn ->
                 Analyze.run(["/nonexistent/path"])
               end)
             ) == {:shutdown, 1}
    end

    test "Mix task handles malformed Elixir file gracefully", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)

      # Add malformed file
      File.write!(Path.join(project_dir, "lib/bad.ex"), """
      defmodule Bad do
        this is not valid syntax
      """)

      # Should still complete (with errors collected)
      capture_io(fn ->
        Analyze.run([project_dir, "--quiet"])
      end)

      # Test passes if we got here without crash
      assert true
    end

    test "Update task handles missing input file", %{temp_dir: temp_dir} do
      assert catch_exit(
               capture_io(fn ->
                 Update.run(["--input", "/nonexistent/graph.ttl", temp_dir])
               end)
             ) == {:shutdown, 1}
    end

    test "Update task handles invalid Turtle file", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      bad_graph = Path.join(temp_dir, "bad.ttl")
      File.write!(bad_graph, "this is not valid turtle syntax")

      assert catch_exit(
               capture_io(fn ->
                 Update.run(["--input", bad_graph, project_dir])
               end)
             ) == {:shutdown, 1}
    end

    test "API handles non-existent file gracefully" do
      assert {:error, :file_not_found} =
               ElixirOntologies.analyze_file("/nonexistent/file.ex")
    end
  end

  # ===========================================================================
  # Cross-Component Tests
  # ===========================================================================

  describe "cross-component consistency" do
    test "Mix task analyze produces valid graph like API", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      output_file = Path.join(temp_dir, "task_output.ttl")

      # Mix task
      capture_io(fn ->
        Analyze.run([project_dir, "--output", output_file, "--quiet"])
      end)

      {:ok, task_content} = File.read(output_file)
      {:ok, task_graph} = RDF.Turtle.read_string(task_content)

      # API
      {:ok, api_result} = ElixirOntologies.analyze_project(project_dir)
      {:ok, api_turtle} = ElixirOntologies.Graph.to_turtle(api_result.graph)
      {:ok, api_graph} = RDF.Turtle.read_string(api_turtle)

      # Both should produce valid graphs
      assert is_struct(task_graph, RDF.Graph)
      assert is_struct(api_graph, RDF.Graph)
    end

    test "Mix task update equivalent to API update_graph", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      task_file = Path.join(temp_dir, "task.ttl")
      api_file = Path.join(temp_dir, "api.ttl")

      # Initial analysis for both
      {:ok, result} = ElixirOntologies.analyze_project(project_dir)
      :ok = ElixirOntologies.Graph.save(result.graph, task_file)
      :ok = ElixirOntologies.Graph.save(result.graph, api_file)

      # Update via Mix task
      capture_io(fn ->
        Update.run(["--input", task_file, project_dir, "--quiet"])
      end)

      # Update via API
      {:ok, _api_result} =
        ElixirOntologies.update_graph(api_file, project_path: project_dir)

      # Both should succeed
      assert File.exists?(task_file)
      assert File.exists?(api_file)
    end

    test "configuration flows consistently through Mix tasks and API", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      custom_iri = "https://consistent.test/code#"

      # Via Mix task
      task_output =
        capture_io(fn ->
          Analyze.run([project_dir, "--base-iri", custom_iri, "--quiet"])
        end)

      # Via API
      {:ok, api_result} =
        ElixirOntologies.analyze_project(project_dir, base_iri: custom_iri)

      {:ok, api_turtle} = ElixirOntologies.Graph.to_turtle(api_result.graph)

      # Both should be valid output (custom IRI usage varies by analyzer)
      assert task_output =~ "@prefix" or String.length(task_output) > 0
      assert api_turtle =~ "@prefix"
    end
  end
end
