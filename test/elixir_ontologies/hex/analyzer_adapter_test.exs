defmodule ElixirOntologies.Hex.AnalyzerAdapterTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.AnalyzerAdapter

  @fixtures_path Path.expand("../../fixtures", __DIR__)

  # ===========================================================================
  # analyze_package/3 Tests
  # ===========================================================================

  describe "analyze_package/3" do
    test "analyzes package directory and returns graph with metadata" do
      config = %{
        base_iri_template: "https://elixir-code.org/:name/:version/",
        version: "1.0.0",
        timeout_minutes: 5
      }

      result = AnalyzerAdapter.analyze_package(@fixtures_path, "test_package", config)

      assert {:ok, graph, metadata} = result
      assert is_map(graph)
      assert is_integer(metadata.module_count)
      assert is_integer(metadata.file_count)
      assert is_integer(metadata.triple_count)
      assert is_integer(metadata.function_count)
      assert is_integer(metadata.error_count)
    end

    test "uses default base IRI when template not provided" do
      result = AnalyzerAdapter.analyze_package(@fixtures_path, "test_pkg", %{version: "1.2.3"})

      assert {:ok, _graph, _metadata} = result
    end

    test "returns error for non-existent directory" do
      result = AnalyzerAdapter.analyze_package("/nonexistent/path", "pkg", %{version: "1.0.0"})

      assert {:error, _reason} = result
    end

    test "substitutes name and version in base IRI template" do
      config = %{
        base_iri_template: "https://elixir-code.org/:name/:version/",
        version: "2.5.0",
        timeout_minutes: 5
      }

      result = AnalyzerAdapter.analyze_package(@fixtures_path, "my_package", config)

      # The generated base IRI should be https://elixir-code.org/my_package/2.5.0/
      assert {:ok, _graph, _metadata} = result
    end
  end

  # ===========================================================================
  # Timeout Wrapper Tests
  # ===========================================================================

  describe "with_timeout/2" do
    test "returns result when function completes in time" do
      result = AnalyzerAdapter.with_timeout(1000, fn ->
        {:ok, :completed}
      end)

      assert result == {:ok, :completed}
    end

    test "returns {:error, :timeout} when function exceeds timeout" do
      result = AnalyzerAdapter.with_timeout(10, fn ->
        Process.sleep(100)
        {:ok, :should_not_reach}
      end)

      assert result == {:error, :timeout}
    end

    test "propagates errors from function" do
      result = AnalyzerAdapter.with_timeout(1000, fn ->
        {:error, :some_error}
      end)

      assert result == {:error, :some_error}
    end

    test "handles exceptions in function" do
      result = AnalyzerAdapter.with_timeout(1000, fn ->
        raise "test error"
      end)

      assert {:error, {:task_exit, {:error, %RuntimeError{message: "test error"}}}} = result
    end

    test "handles throws in function" do
      result = AnalyzerAdapter.with_timeout(1000, fn ->
        throw(:deliberate_error)
      end)

      assert {:error, {:task_exit, {:throw, :deliberate_error}}} = result
    end
  end

  # ===========================================================================
  # Default Values Tests
  # ===========================================================================

  describe "default_timeout_minutes/0" do
    test "returns default timeout" do
      assert AnalyzerAdapter.default_timeout_minutes() == 5
    end
  end

  # ===========================================================================
  # Metadata Extraction Tests
  # ===========================================================================

  describe "extract_metadata/1" do
    test "extracts counts from result" do
      # Create a mock result structure
      result = %ElixirOntologies.Analyzer.ProjectAnalyzer.Result{
        project: nil,
        files: [
          %ElixirOntologies.Analyzer.ProjectAnalyzer.FileResult{
            file_path: "/test.ex",
            relative_path: "test.ex",
            analysis: %{
              result: %{
                modules: [
                  %{name: "Test", functions: [%{name: :foo}, %{name: :bar}]},
                  %{name: "Test2", functions: [%{name: :baz}]}
                ]
              }
            },
            status: :ok
          }
        ],
        graph: %{triples: [1, 2, 3, 4, 5]},
        errors: [{"/error.ex", :parse_error}]
      }

      metadata = AnalyzerAdapter.extract_metadata(result)

      assert metadata.module_count == 2
      assert metadata.function_count == 3
      assert metadata.triple_count == 5
      assert metadata.file_count == 1
      assert metadata.error_count == 1
    end

    test "handles empty result" do
      result = %ElixirOntologies.Analyzer.ProjectAnalyzer.Result{
        project: nil,
        files: [],
        graph: %{triples: []},
        errors: []
      }

      metadata = AnalyzerAdapter.extract_metadata(result)

      assert metadata.module_count == 0
      assert metadata.function_count == 0
      assert metadata.triple_count == 0
      assert metadata.file_count == 0
      assert metadata.error_count == 0
    end

    test "handles files with errors" do
      result = %ElixirOntologies.Analyzer.ProjectAnalyzer.Result{
        project: nil,
        files: [
          %ElixirOntologies.Analyzer.ProjectAnalyzer.FileResult{
            file_path: "/test.ex",
            relative_path: "test.ex",
            analysis: nil,
            status: :error,
            error: :parse_error
          }
        ],
        graph: %{triples: []},
        errors: []
      }

      metadata = AnalyzerAdapter.extract_metadata(result)

      assert metadata.module_count == 0
      assert metadata.file_count == 1
    end

    test "handles map-based triples" do
      result = %ElixirOntologies.Analyzer.ProjectAnalyzer.Result{
        project: nil,
        files: [],
        graph: %{triples: %{a: 1, b: 2, c: 3}},
        errors: []
      }

      metadata = AnalyzerAdapter.extract_metadata(result)

      assert metadata.triple_count == 3
    end
  end
end
