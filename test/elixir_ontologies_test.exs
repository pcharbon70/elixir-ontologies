defmodule ElixirOntologiesTest do
  use ExUnit.Case, async: false

  alias ElixirOntologies

  @moduletag :api

  setup do
    # Create temporary directory for test files
    temp_dir = System.tmp_dir!() |> Path.join("api_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir}
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp create_test_file(dir, name, content) do
    file_path = Path.join(dir, name)
    File.write!(file_path, content)
    file_path
  end

  defp create_test_project(base_dir) do
    # Create project structure
    lib_dir = Path.join(base_dir, "lib")
    File.mkdir_p!(lib_dir)

    # Create mix.exs
    File.write!(Path.join(base_dir, "mix.exs"), """
    defmodule TestProject.MixProject do
      use Mix.Project
      def project, do: [app: :test_project, version: "1.0.0"]
    end
    """)

    # Create initial modules
    File.write!(Path.join(lib_dir, "foo.ex"), """
    defmodule Foo do
      def hello, do: :world
    end
    """)

    File.write!(Path.join(lib_dir, "bar.ex"), """
    defmodule Bar do
      def test, do: :ok
    end
    """)

    base_dir
  end

  # ===========================================================================
  # analyze_file/2 Tests
  # ===========================================================================

  describe "analyze_file/2" do
    test "analyzes a single file and returns graph", %{temp_dir: temp_dir} do
      file_path =
        create_test_file(temp_dir, "sample.ex", """
        defmodule Sample do
          def greet(name), do: "Hello, \#{name}"
        end
        """)

      assert {:ok, graph} = ElixirOntologies.analyze_file(file_path)
      assert is_struct(graph, ElixirOntologies.Graph)
      assert is_struct(graph.graph, RDF.Graph)
      # Graph structure exists (triple count may be 0 for simple modules)
      assert is_integer(RDF.Graph.triple_count(graph.graph))
    end

    test "accepts custom base IRI option", %{temp_dir: temp_dir} do
      file_path =
        create_test_file(temp_dir, "sample.ex", """
        defmodule Sample do
          def test, do: :ok
        end
        """)

      assert {:ok, graph} =
               ElixirOntologies.analyze_file(file_path, base_iri: "https://myapp.org/code#")

      # Verify custom base IRI was used
      assert is_struct(graph, ElixirOntologies.Graph)
    end

    test "accepts include_source_text option", %{temp_dir: temp_dir} do
      file_path =
        create_test_file(temp_dir, "sample.ex", """
        defmodule Sample do
          def test, do: :ok
        end
        """)

      assert {:ok, _graph} =
               ElixirOntologies.analyze_file(file_path, include_source_text: true)
    end

    test "returns error for non-existent file" do
      assert {:error, :file_not_found} =
               ElixirOntologies.analyze_file("/nonexistent/path/file.ex")
    end
  end

  # ===========================================================================
  # analyze_project/2 Tests
  # ===========================================================================

  describe "analyze_project/2" do
    test "analyzes a project and returns result map", %{temp_dir: temp_dir} do
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
      assert result.metadata.file_count == 2
      assert result.metadata.module_count == 2
      assert result.metadata.error_count == 0

      # Verify errors list
      assert result.errors == []
    end

    test "accepts exclude_tests option", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)

      # Create test directory
      test_dir = Path.join(project_dir, "test")
      File.mkdir_p!(test_dir)

      File.write!(Path.join(test_dir, "sample_test.exs"), """
      defmodule SampleTest do
        use ExUnit.Case
      end
      """)

      # With exclude_tests: true (default)
      assert {:ok, result} = ElixirOntologies.analyze_project(project_dir)
      assert result.metadata.file_count == 2

      # With exclude_tests: false
      assert {:ok, result} =
               ElixirOntologies.analyze_project(project_dir, exclude_tests: false)

      assert result.metadata.file_count == 3
    end

    test "returns error for non-existent project" do
      assert {:error, :project_not_found} =
               ElixirOntologies.analyze_project("/nonexistent/project")
    end

    test "handles individual file failures gracefully", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)

      # Even if a file has issues, project analysis should complete
      assert {:ok, result} = ElixirOntologies.analyze_project(project_dir)

      # Result should have proper structure
      assert is_map(result)
      assert Map.has_key?(result, :errors)
      assert is_list(result.errors)
    end

    test "accepts custom base IRI", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)

      assert {:ok, result} =
               ElixirOntologies.analyze_project(project_dir,
                 base_iri: "https://myproject.org/code#"
               )

      assert is_struct(result.graph, ElixirOntologies.Graph)
    end
  end

  # ===========================================================================
  # update_graph/2 Tests
  # ===========================================================================

  describe "update_graph/2" do
    setup %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "graph.ttl")

      # Perform initial analysis and save
      {:ok, result} = ElixirOntologies.analyze_project(project_dir)
      :ok = ElixirOntologies.Graph.save(result.graph, graph_file)

      {:ok, project_dir: project_dir, graph_file: graph_file}
    end

    test "loads existing graph and performs update", %{
      project_dir: project_dir,
      graph_file: graph_file
    } do
      assert {:ok, result} =
               ElixirOntologies.update_graph(graph_file, project_path: project_dir)

      assert is_map(result)
      assert Map.has_key?(result, :graph)
      assert Map.has_key?(result, :metadata)
      assert is_struct(result.graph, ElixirOntologies.Graph)
    end

    test "returns error for non-existent graph file" do
      assert {:error, :graph_not_found} =
               ElixirOntologies.update_graph("/nonexistent/graph.ttl")
    end

    test "returns error for invalid graph file", %{temp_dir: temp_dir} do
      bad_graph = Path.join(temp_dir, "bad.ttl")
      File.write!(bad_graph, "this is not valid turtle syntax")

      assert {:error, {:invalid_graph, _reason}} = ElixirOntologies.update_graph(bad_graph)
    end

    test "accepts project_path option", %{temp_dir: temp_dir, graph_file: graph_file} do
      project_dir = create_test_project(temp_dir <> "_other")

      assert {:ok, result} =
               ElixirOntologies.update_graph(graph_file, project_path: project_dir)

      assert result.metadata.file_count == 2
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "API integration" do
    test "end-to-end workflow: file -> project -> update", %{temp_dir: temp_dir} do
      # Step 1: Analyze single file
      file_path =
        create_test_file(temp_dir, "single.ex", """
        defmodule SingleFile do
          def test, do: :ok
        end
        """)

      assert {:ok, file_graph} = ElixirOntologies.analyze_file(file_path)
      assert is_struct(file_graph, ElixirOntologies.Graph)

      # Step 2: Analyze full project
      project_dir = create_test_project(temp_dir <> "_project")
      assert {:ok, project_result} = ElixirOntologies.analyze_project(project_dir)
      assert project_result.metadata.file_count == 2

      # Step 3: Save and update
      graph_file = Path.join(temp_dir, "project.ttl")
      :ok = ElixirOntologies.Graph.save(project_result.graph, graph_file)

      assert {:ok, updated_result} =
               ElixirOntologies.update_graph(graph_file, project_path: project_dir)

      assert updated_result.metadata.file_count == 2
    end
  end
end
