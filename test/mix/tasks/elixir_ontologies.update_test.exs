defmodule Mix.Tasks.ElixirOntologies.UpdateTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Mix.Tasks.ElixirOntologies.{Analyze, Update}

  @moduletag :mix_task

  setup do
    # Create temporary directory for test files
    temp_dir = System.tmp_dir!() |> Path.join("update_test_#{:rand.uniform(100_000)}")
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
      def project, do: [app: :test_project, version: "1.0.0"]
    end
    """)

    # Create initial module
    File.write!(Path.join(lib_dir, "foo.ex"), """
    defmodule Foo do
      def hello, do: :world
    end
    """)

    base_dir
  end

  defp analyze_project(project_dir, output_file) do
    capture_io(fn ->
      Analyze.run([project_dir, "--output", output_file, "--quiet"])
    end)
  end

  # ===========================================================================
  # Help and Documentation Tests
  # ===========================================================================

  describe "task documentation" do
    test "has short documentation" do
      assert Update.__info__(:attributes)[:shortdoc] == [
               "Update RDF knowledge graph with incremental analysis"
             ]
    end

    test "has module documentation" do
      {:docs_v1, _, :elixir, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Update)
      assert moduledoc =~ "Updates an existing RDF knowledge graph"
      assert moduledoc =~ "## Usage"
      assert moduledoc =~ "## Options"
    end
  end

  # ===========================================================================
  # Basic Update Tests
  # ===========================================================================

  describe "basic update functionality" do
    setup %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "graph.ttl")

      # Perform initial analysis
      analyze_project(project_dir, graph_file)

      {:ok, project_dir: project_dir, graph_file: graph_file}
    end

    test "requires --input option", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)

      assert catch_exit(
               capture_io(fn ->
                 Update.run([project_dir])
               end)
             ) == {:shutdown, 1}
    end

    test "updates graph with no changes", %{project_dir: project_dir, graph_file: graph_file} do
      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      assert output =~ "Loading existing graph"
      # Since state file doesn't have analysis, it falls back to full analysis
      assert output =~ "full analysis"
    end

    test "writes to input file by default", %{project_dir: project_dir, graph_file: graph_file} do
      # Modify file
      File.write!(Path.join(project_dir, "lib/foo.ex"), """
      defmodule Foo do
        def hello, do: :updated
      end
      """)

      capture_io(fn ->
        Update.run(["--input", graph_file, project_dir, "--quiet"])
      end)

      # Graph file should exist and be updated
      assert File.exists?(graph_file)
      content = File.read!(graph_file)
      assert content =~ "@prefix"
    end

    test "writes to custom output file", %{temp_dir: temp_dir, project_dir: project_dir, graph_file: graph_file} do
      output_file = Path.join(temp_dir, "updated.ttl")

      capture_io(fn ->
        Update.run(["--input", graph_file, "--output", output_file, project_dir, "--quiet"])
      end)

      assert File.exists?(output_file)
      assert File.exists?(output_file <> ".state")
    end
  end

  # ===========================================================================
  # State File Tests
  # ===========================================================================

  describe "state file management" do
    setup %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "graph.ttl")

      analyze_project(project_dir, graph_file)

      {:ok, project_dir: project_dir, graph_file: graph_file}
    end

    test "creates state file on update", %{project_dir: project_dir, graph_file: graph_file} do
      state_file = graph_file <> ".state"

      capture_io(fn ->
        Update.run(["--input", graph_file, project_dir, "--quiet"])
      end)

      assert File.exists?(state_file)

      # State should be valid JSON
      {:ok, state} = File.read(state_file) |> elem(1) |> Jason.decode()
      assert state["version"] == "1.0"
      assert is_map(state["project"])
      assert is_list(state["files"])
      assert is_map(state["metadata"])
    end

    test "loads state on subsequent update", %{project_dir: project_dir, graph_file: graph_file} do
      # First update
      capture_io(fn ->
        Update.run(["--input", graph_file, project_dir, "--quiet"])
      end)

      # Second update (should load state, but fall back to full analysis)
      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      assert output =~ "Loading analysis state"
      # Falls back to full analysis since state doesn't have FileAnalyzer.Result structs
      assert output =~ "full analysis"
    end

    test "falls back to full analysis when state missing", %{project_dir: project_dir, graph_file: graph_file} do
      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      # Warnings go to stderr, so just check for full analysis
      assert output =~ "full analysis"
    end
  end

  # ===========================================================================
  # File Change Tests
  # ===========================================================================

  describe "file changes" do
    setup %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "graph.ttl")

      analyze_project(project_dir, graph_file)

      {:ok, project_dir: project_dir, graph_file: graph_file}
    end

    test "updates when file is modified", %{project_dir: project_dir, graph_file: graph_file} do
      # Modify existing file
      File.write!(Path.join(project_dir, "lib/foo.ex"), """
      defmodule Foo do
        def hello, do: :modified
        def new_function, do: :added
      end
      """)

      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      assert output =~ "Loading existing graph"
      assert output =~ "full analysis"
    end

    test "updates when file is added", %{project_dir: project_dir, graph_file: graph_file} do
      # Add new file
      File.write!(Path.join(project_dir, "lib/bar.ex"), """
      defmodule Bar do
        def test, do: :ok
      end
      """)

      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      assert output =~ "Analyzed 2 files"
      assert output =~ "Found 2 modules"
    end

    test "updates when file is deleted", %{project_dir: project_dir, graph_file: graph_file} do
      # Delete existing file
      File.rm!(Path.join(project_dir, "lib/foo.ex"))

      # Deleting all files will cause no_source_files error, which is expected
      assert catch_exit(
               capture_io(fn ->
                 Update.run(["--input", graph_file, project_dir])
               end)
             ) == {:shutdown, 1}
    end
  end

  # ===========================================================================
  # Option Tests
  # ===========================================================================

  describe "command-line options" do
    setup %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "graph.ttl")

      analyze_project(project_dir, graph_file)

      {:ok, project_dir: project_dir, graph_file: graph_file}
    end

    test "accepts --input short form -i", %{project_dir: project_dir, graph_file: graph_file} do
      output =
        capture_io(fn ->
          Update.run(["-i", graph_file, project_dir])
        end)

      assert output =~ "Loading existing graph"
    end

    test "accepts --output short form -o", %{temp_dir: temp_dir, project_dir: project_dir, graph_file: graph_file} do
      output_file = Path.join(temp_dir, "out.ttl")

      capture_io(fn ->
        Update.run(["-i", graph_file, "-o", output_file, project_dir, "--quiet"])
      end)

      assert File.exists?(output_file)
    end

    test "accepts --quiet flag", %{project_dir: project_dir, graph_file: graph_file} do
      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir, "--quiet"])
        end)

      # Should not contain progress messages
      refute output =~ "Loading existing graph"
    end

    test "accepts --force-full flag", %{project_dir: project_dir, graph_file: graph_file} do
      # Create state first
      capture_io(fn ->
        Update.run(["--input", graph_file, project_dir, "--quiet"])
      end)

      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir, "--force-full"])
        end)

      # Warnings go to stderr, so just check that full analysis happens
      assert output =~ "full analysis"
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "error handling" do
    test "handles missing input file", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      missing_file = Path.join(temp_dir, "missing.ttl")

      assert catch_exit(
               capture_io(fn ->
                 Update.run(["--input", missing_file, project_dir])
               end)
             ) == {:shutdown, 1}
    end

    test "handles invalid project path", %{temp_dir: temp_dir} do
      graph_file = Path.join(temp_dir, "graph.ttl")
      File.write!(graph_file, "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .")

      assert catch_exit(
               capture_io(fn ->
                 Update.run(["--input", graph_file, "/nonexistent/path"])
               end)
             ) == {:shutdown, 1}
    end

    test "handles malformed graph file", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "bad.ttl")
      File.write!(graph_file, "this is not valid turtle")

      assert catch_exit(
               capture_io(fn ->
                 Update.run(["--input", graph_file, project_dir])
               end)
             ) == {:shutdown, 1}
    end

    test "handles too many arguments", %{temp_dir: temp_dir} do
      graph_file = Path.join(temp_dir, "graph.ttl")
      File.write!(graph_file, "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .")

      assert catch_exit(
               capture_io(fn ->
                 Update.run(["--input", graph_file, "arg1", "arg2"])
               end)
             ) == {:shutdown, 1}
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "end-to-end update workflow", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "project.ttl")

      # Step 1: Initial analysis
      capture_io(fn ->
        Analyze.run([project_dir, "--output", graph_file, "--quiet"])
      end)

      assert File.exists?(graph_file)

      # Step 2: First update (creates state)
      capture_io(fn ->
        Update.run(["--input", graph_file, project_dir, "--quiet"])
      end)

      assert File.exists?(graph_file <> ".state")

      # Step 3: Modify file
      File.write!(Path.join(project_dir, "lib/foo.ex"), """
      defmodule Foo do
        def hello, do: :updated
        def world, do: :new
      end
      """)

      # Step 4: Update (performs full analysis)
      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      assert output =~ "full analysis"
      assert output =~ "Full analysis complete"

      # Verify graph is valid Turtle
      {:ok, content} = File.read(graph_file)
      assert {:ok, _graph} = RDF.Turtle.read_string(content)
    end

    test "state persistence across multiple updates", %{temp_dir: temp_dir} do
      project_dir = create_test_project(temp_dir)
      graph_file = Path.join(temp_dir, "graph.ttl")

      # Initial analysis
      analyze_project(project_dir, graph_file)

      # First update
      capture_io(fn ->
        Update.run(["--input", graph_file, project_dir, "--quiet"])
      end)

      # Add file
      File.write!(Path.join(project_dir, "lib/one.ex"), "defmodule One, do: def f, do: 1")

      # Second update
      output =
        capture_io(fn ->
          Update.run(["--input", graph_file, project_dir])
        end)

      assert output =~ "Analyzed 2 files"
      assert output =~ "Found 2 modules"
    end
  end
end
