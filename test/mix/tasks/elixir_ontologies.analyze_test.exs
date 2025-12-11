defmodule Mix.Tasks.ElixirOntologies.AnalyzeTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Mix.Tasks.ElixirOntologies.Analyze

  @moduletag :mix_task

  setup do
    # Create temporary directory for test files
    temp_dir = System.tmp_dir!() |> Path.join("analyze_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir}
  end

  # ===========================================================================
  # Help and Documentation Tests
  # ===========================================================================

  describe "task documentation" do
    test "has short documentation" do
      # @shortdoc is a module attribute, not a function
      assert Analyze.__info__(:attributes)[:shortdoc] == [
               "Analyze Elixir code and generate RDF knowledge graph"
             ]
    end

    test "has module documentation" do
      {:docs_v1, _, :elixir, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Analyze)
      assert moduledoc =~ "Analyzes Elixir source code"
      assert moduledoc =~ "## Usage"
      assert moduledoc =~ "## Options"
    end
  end

  # ===========================================================================
  # Single File Analysis Tests
  # ===========================================================================

  describe "single file analysis" do
    setup %{temp_dir: temp_dir} do
      # Create a simple test file
      test_file = Path.join(temp_dir, "sample.ex")

      File.write!(test_file, """
      defmodule Sample do
        def hello(name), do: "Hello, \#{name}!"
      end
      """)

      {:ok, test_file: test_file}
    end

    test "analyzes single file to stdout", %{test_file: test_file} do
      output =
        capture_io(fn ->
          Analyze.run([test_file, "--quiet"])
        end)

      # Should output Turtle format
      assert output =~ "@prefix"
      assert output =~ "rdf:"
      assert output =~ "rdfs:"
    end

    test "displays progress without --quiet flag", %{test_file: test_file} do
      output =
        capture_io(fn ->
          Analyze.run([test_file])
        end)

      # Should show progress messages
      assert output =~ "Analyzing file"
      assert output =~ "Found"
      assert output =~ "module"
    end

    test "analyzes file with custom base IRI", %{test_file: test_file} do
      output =
        capture_io(fn ->
          Analyze.run([test_file, "--base-iri", "https://example.com/", "--quiet"])
        end)

      assert output =~ "@prefix"
    end

    test "writes output to file", %{test_file: test_file, temp_dir: temp_dir} do
      output_file = Path.join(temp_dir, "output.ttl")

      capture_io(fn ->
        Analyze.run([test_file, "--output", output_file, "--quiet"])
      end)

      # Output file should exist and contain Turtle
      assert File.exists?(output_file)
      content = File.read!(output_file)
      assert content =~ "@prefix"
    end

    test "handles non-existent file gracefully", %{temp_dir: temp_dir} do
      non_existent = Path.join(temp_dir, "does_not_exist.ex")

      assert catch_exit(
               capture_io(fn ->
                 Analyze.run([non_existent])
               end)
             ) == {:shutdown, 1}
    end
  end

  # ===========================================================================
  # Project Analysis Tests
  # ===========================================================================

  describe "project analysis" do
    setup %{temp_dir: temp_dir} do
      # Create a minimal project structure
      lib_dir = Path.join(temp_dir, "lib")
      File.mkdir_p!(lib_dir)

      # Create mix.exs
      File.write!(Path.join(temp_dir, "mix.exs"), """
      defmodule TestProject.MixProject do
        use Mix.Project
        def project, do: [app: :test_project, version: "1.0.0"]
      end
      """)

      # Create a module file
      File.write!(Path.join(lib_dir, "foo.ex"), """
      defmodule Foo do
        def bar, do: :baz
      end
      """)

      {:ok, project_dir: temp_dir}
    end

    test "analyzes project directory", %{project_dir: project_dir} do
      output =
        capture_io(fn ->
          Analyze.run([project_dir, "--quiet"])
        end)

      assert output =~ "@prefix"
    end

    test "analyzes current directory when no path given" do
      # This test analyzes the actual elixir_ontologies project
      output =
        capture_io(fn ->
          Analyze.run(["--quiet"])
        end)

      assert output =~ "@prefix"
    end

    test "displays project progress", %{project_dir: project_dir} do
      output =
        capture_io(fn ->
          Analyze.run([project_dir])
        end)

      assert output =~ "Analyzing project"
      assert output =~ "Analyzed"
      assert output =~ "files"
    end

    test "excludes tests by default", %{project_dir: project_dir} do
      # Create test directory
      test_dir = Path.join(project_dir, "test")
      File.mkdir_p!(test_dir)

      File.write!(Path.join(test_dir, "foo_test.exs"), """
      defmodule FooTest do
        use ExUnit.Case
        test "works", do: assert true
      end
      """)

      output =
        capture_io(fn ->
          Analyze.run([project_dir])
        end)

      # Should analyze 1 file (not the test file)
      assert output =~ "Analyzed 1"
    end

    test "includes tests with --no-exclude-tests", %{project_dir: project_dir} do
      # Create test directory
      test_dir = Path.join(project_dir, "test")
      File.mkdir_p!(test_dir)

      File.write!(Path.join(test_dir, "foo_test.exs"), """
      defmodule FooTest do
        use ExUnit.Case
      end
      """)

      output =
        capture_io(fn ->
          Analyze.run([project_dir, "--no-exclude-tests"])
        end)

      # Should analyze 2 files (including test)
      assert output =~ "Analyzed 2"
    end

    test "writes project analysis to file", %{project_dir: project_dir, temp_dir: temp_dir} do
      output_file = Path.join(temp_dir, "project_output.ttl")

      capture_io(fn ->
        Analyze.run([project_dir, "--output", output_file, "--quiet"])
      end)

      assert File.exists?(output_file)
      content = File.read!(output_file)
      assert content =~ "@prefix"
    end
  end

  # ===========================================================================
  # Option Parsing Tests
  # ===========================================================================

  describe "option parsing" do
    setup %{temp_dir: temp_dir} do
      test_file = Path.join(temp_dir, "simple.ex")

      File.write!(test_file, """
      defmodule Simple do
        def test, do: :ok
      end
      """)

      {:ok, test_file: test_file}
    end

    test "parses --output with short alias -o", %{test_file: test_file, temp_dir: temp_dir} do
      output_file = Path.join(temp_dir, "short_alias.ttl")

      capture_io(fn ->
        Analyze.run([test_file, "-o", output_file, "--quiet"])
      end)

      assert File.exists?(output_file)
    end

    test "parses --base-iri with short alias -b", %{test_file: test_file} do
      output =
        capture_io(fn ->
          Analyze.run([test_file, "-b", "https://test.org/", "--quiet"])
        end)

      assert output =~ "@prefix"
    end

    test "parses --quiet with short alias -q", %{test_file: test_file} do
      output =
        capture_io(fn ->
          Analyze.run([test_file, "-q"])
        end)

      # Should not contain progress messages
      refute output =~ "Analyzing"
    end

    test "handles invalid options", %{test_file: test_file} do
      assert catch_exit(
               capture_io(fn ->
                 Analyze.run([test_file, "--invalid-option"])
               end)
             ) == {:shutdown, 1}
    end

    test "handles too many arguments" do
      assert catch_exit(
               capture_io(fn ->
                 Analyze.run(["arg1", "arg2", "arg3"])
               end)
             ) == {:shutdown, 1}
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "error handling" do
    test "handles malformed Elixir file gracefully", %{temp_dir: temp_dir} do
      malformed_file = Path.join(temp_dir, "malformed.ex")

      File.write!(malformed_file, """
      defmodule Broken do
        def bad(x
      """)

      assert catch_exit(
               capture_io(fn ->
                 Analyze.run([malformed_file])
               end)
             ) == {:shutdown, 1}
    end

    test "handles project without mix.exs", %{temp_dir: temp_dir} do
      # Create directory without mix.exs
      empty_dir = Path.join(temp_dir, "no_mix")
      File.mkdir_p!(empty_dir)

      assert catch_exit(
               capture_io(fn ->
                 Analyze.run([empty_dir])
               end)
             ) == {:shutdown, 1}
    end

    test "handles write permission errors", %{temp_dir: temp_dir} do
      test_file = Path.join(temp_dir, "test.ex")

      File.write!(test_file, """
      defmodule Test do
      end
      """)

      # Try to write to a directory (not a file)
      assert catch_exit(
               capture_io(fn ->
                 Analyze.run([test_file, "--output", temp_dir, "--quiet"])
               end)
             ) == {:shutdown, 1}
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "analyzes actual project file" do
      # Analyze a real file from the project
      config_file = "lib/elixir_ontologies/config.ex"

      output =
        capture_io(fn ->
          Analyze.run([config_file, "--quiet"])
        end)

      # Should produce valid Turtle
      assert output =~ "@prefix rdf:"
      assert output =~ "@prefix rdfs:"

      # Turtle should be parseable
      assert {:ok, _graph} = RDF.Turtle.read_string(output)
    end

    test "full project analysis produces valid Turtle" do
      output =
        capture_io(fn ->
          Analyze.run(["--quiet"])
        end)

      # Should produce valid Turtle
      assert output =~ "@prefix"

      # Turtle should be parseable
      assert {:ok, _graph} = RDF.Turtle.read_string(output)
    end
  end

  # ===========================================================================
  # Validation Tests
  # ===========================================================================

  describe "validation with --validate flag" do
    setup %{temp_dir: temp_dir} do
      # Create a simple test file
      test_file = Path.join(temp_dir, "validation_test.ex")

      File.write!(test_file, """
      defmodule ValidationTest do
        def test, do: :ok
      end
      """)

      {:ok, test_file: test_file}
    end

    @tag :requires_pyshacl
    test "validates graph when --validate flag provided", %{test_file: test_file} do
      if ElixirOntologies.Validator.available?() do
        output =
          capture_io(fn ->
            Analyze.run([test_file, "--validate", "--quiet"])
          end)

        # Should include validation output
        assert output =~ "Graph conforms" or output =~ "Validation"
      else
        # Should show installation instructions if pySHACL not available
        assert catch_exit(
                 capture_io(fn ->
                   Analyze.run([test_file, "--validate"])
                 end)
               ) == {:shutdown, 1}
      end
    end

    @tag :requires_pyshacl
    test "validation error shown when pySHACL not available", %{test_file: test_file} do
      unless ElixirOntologies.Validator.available?() do
        output =
          capture_io(fn ->
            catch_exit(Analyze.run([test_file, "--validate"]))
          end)

        assert output =~ "pySHACL is not available" or output =~ "pip install pyshacl"
      end
    end

    test "--validate flag is recognized as valid option", %{test_file: test_file} do
      # Test that the option is accepted without causing option parsing errors
      output =
        capture_io(fn ->
          # May exit if pySHACL not available, but shouldn't show "Invalid options"
          catch_exit(Analyze.run([test_file, "--validate", "--quiet"]))
        end)

      refute output =~ "Invalid options"
    end

    @tag :requires_pyshacl
    test "short flag -v works for validation", %{test_file: test_file} do
      # Test the -v alias
      output =
        capture_io(fn ->
          catch_exit(Analyze.run([test_file, "-v", "--quiet"]))
        end)

      # Should not show "Invalid options"
      refute output =~ "Invalid options"
    end
  end
end
