defmodule ElixirOntologies.Hex.FailureTrackerTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.FailureTracker
  alias ElixirOntologies.Hex.Progress
  alias ElixirOntologies.Hex.Progress.PackageResult

  # ===========================================================================
  # Error Classification Tests
  # ===========================================================================

  describe "classify_error/1" do
    test "classifies download errors" do
      assert FailureTracker.classify_error(:not_found) == :download_error
      assert FailureTracker.classify_error(:rate_limited) == :download_error
      assert FailureTracker.classify_error({:http_error, 500}) == :download_error
      assert FailureTracker.classify_error({:error, :not_found}) == :download_error
      assert FailureTracker.classify_error({:error, :rate_limited}) == :download_error
    end

    test "classifies extraction errors" do
      assert FailureTracker.classify_error(:invalid_tarball) == :extraction_error
      assert FailureTracker.classify_error(:no_contents) == :extraction_error
      assert FailureTracker.classify_error({:tar_extract, :eof}) == :extraction_error
      assert FailureTracker.classify_error({:decompress, :data_error}) == :extraction_error
    end

    test "classifies not elixir errors" do
      assert FailureTracker.classify_error(:not_elixir) == :not_elixir
      assert FailureTracker.classify_error(:no_mix_exs) == :not_elixir
      assert FailureTracker.classify_error({:error, :not_elixir}) == :not_elixir
    end

    test "classifies output errors" do
      assert FailureTracker.classify_error({:file_write, :enoent}) == :output_error
      assert FailureTracker.classify_error({:error, {:file_write, :enospc}}) == :output_error
    end

    test "classifies timeout" do
      assert FailureTracker.classify_error(:timeout) == :timeout
      assert FailureTracker.classify_error({:error, :timeout}) == :timeout
    end

    test "classifies exceptions as analysis errors" do
      error = %RuntimeError{message: "test"}
      assert FailureTracker.classify_error(error) == :analysis_error
    end

    test "returns unknown for unrecognized errors" do
      assert FailureTracker.classify_error(:some_random_error) == :unknown
      assert FailureTracker.classify_error("string error") == :unknown
    end
  end

  describe "error_types/0" do
    test "returns all defined error types" do
      types = FailureTracker.error_types()

      assert :download_error in types
      assert :extraction_error in types
      assert :analysis_error in types
      assert :output_error in types
      assert :timeout in types
      assert :not_elixir in types
      assert :unknown in types
    end
  end

  # ===========================================================================
  # Failure Recording Tests
  # ===========================================================================

  describe "record_failure/5" do
    test "creates failure result with classification" do
      result = FailureTracker.record_failure("pkg", "1.0.0", :not_found, nil)

      assert result.name == "pkg"
      assert result.version == "1.0.0"
      assert result.status == :failed
      assert result.error_type == :download_error
      assert result.error =~ ":not_found"
    end

    test "includes duration when provided" do
      result = FailureTracker.record_failure("pkg", "1.0.0", :timeout, nil, duration_ms: 5000)

      assert result.duration_ms == 5000
    end

    test "formats stacktrace when provided" do
      stacktrace = [
        {MyModule, :my_function, 2, [file: ~c"lib/my_module.ex", line: 42]},
        {AnotherModule, :another, 1, [file: ~c"lib/another.ex", line: 10]}
      ]

      result = FailureTracker.record_failure("pkg", "1.0.0", :some_error, stacktrace)

      assert result.error =~ "my_module.ex"
      assert result.error =~ "42"
    end
  end

  # ===========================================================================
  # Failure Analysis Tests
  # ===========================================================================

  describe "failures_by_type/1" do
    test "groups failures by error type" do
      results = [
        PackageResult.failure("p1", "1.0.0", error_type: :download_error),
        PackageResult.failure("p2", "1.0.0", error_type: :download_error),
        PackageResult.failure("p3", "1.0.0", error_type: :not_elixir),
        PackageResult.success("p4", "1.0.0")  # Should be excluded
      ]

      by_type = FailureTracker.failures_by_type(results)

      assert length(by_type[:download_error]) == 2
      assert length(by_type[:not_elixir]) == 1
      refute Map.has_key?(by_type, :completed)
    end

    test "returns empty map for no failures" do
      results = [PackageResult.success("p1", "1.0.0")]

      by_type = FailureTracker.failures_by_type(results)

      assert by_type == %{}
    end
  end

  describe "retry_candidates/1" do
    test "returns retryable failures" do
      results = [
        PackageResult.failure("p1", "1.0.0", error_type: :download_error),
        PackageResult.failure("p2", "1.0.0", error_type: :timeout),
        PackageResult.failure("p3", "1.0.0", error_type: :extraction_error),
        PackageResult.failure("p4", "1.0.0", error_type: :not_elixir),  # Not retryable
        PackageResult.failure("p5", "1.0.0", error_type: :analysis_error)  # Not retryable
      ]

      candidates = FailureTracker.retry_candidates(results)

      names = Enum.map(candidates, & &1.name)
      assert "p1" in names
      assert "p2" in names
      assert "p3" in names
      refute "p4" in names
      refute "p5" in names
    end

    test "excludes successful results" do
      results = [
        PackageResult.success("p1", "1.0.0"),
        PackageResult.failure("p2", "1.0.0", error_type: :download_error)
      ]

      candidates = FailureTracker.retry_candidates(results)

      assert length(candidates) == 1
      assert hd(candidates).name == "p2"
    end
  end

  describe "failure_counts/1" do
    test "returns counts by type" do
      results = [
        PackageResult.failure("p1", "1.0.0", error_type: :download_error),
        PackageResult.failure("p2", "1.0.0", error_type: :download_error),
        PackageResult.failure("p3", "1.0.0", error_type: :not_elixir)
      ]

      counts = FailureTracker.failure_counts(results)

      assert counts[:download_error] == 2
      assert counts[:not_elixir] == 1
    end
  end

  # ===========================================================================
  # Export Tests
  # ===========================================================================

  describe "export_failures/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "failures_#{:rand.uniform(100_000)}.json")

      on_exit(fn ->
        File.rm(test_file)
      end)

      {:ok, test_file: test_file}
    end

    test "exports failures to JSON file", %{test_file: file} do
      progress = Progress.new()
        |> Progress.add_result(PackageResult.failure("p1", "1.0.0", error_type: :download_error, error: "Connection failed"))
        |> Progress.add_result(PackageResult.failure("p2", "1.0.0", error_type: :not_elixir, error: "No mix.exs"))

      :ok = FailureTracker.export_failures(progress, file)

      assert File.exists?(file)
      {:ok, content} = File.read(file)
      {:ok, data} = Jason.decode(content)

      assert data["summary"]["total_failures"] == 2
      assert data["failures"]["download_error"] != nil
    end

    test "creates parent directories", %{test_file: file} do
      # Create a nested path under a unique directory
      base_dir = Path.join(Path.dirname(file), "nested_failures_#{:rand.uniform(100_000)}")
      nested = Path.join([base_dir, "subdir", "failures.json"])

      on_exit(fn ->
        File.rm_rf(base_dir)
      end)

      progress = Progress.new()

      :ok = FailureTracker.export_failures(progress, nested)

      assert File.exists?(nested)
    end
  end

  # ===========================================================================
  # Formatting Tests
  # ===========================================================================

  describe "format_failure_summary/1" do
    test "formats failure summary" do
      results = [
        PackageResult.failure("p1", "1.0.0", error_type: :download_error),
        PackageResult.failure("p2", "1.0.0", error_type: :download_error),
        PackageResult.failure("p3", "1.0.0", error_type: :not_elixir)
      ]

      summary = FailureTracker.format_failure_summary(results)

      assert summary =~ "3 total"
      assert summary =~ "download_error: 2"
      assert summary =~ "not_elixir: 1"
    end

    test "returns message for no failures" do
      results = [PackageResult.success("p1", "1.0.0")]

      summary = FailureTracker.format_failure_summary(results)

      assert summary == "No failures"
    end
  end
end
