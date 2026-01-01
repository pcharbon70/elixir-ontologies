defmodule ElixirOntologies.Hex.ProgressTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.Progress
  alias ElixirOntologies.Hex.Progress.PackageResult

  # ===========================================================================
  # Progress Struct Tests
  # ===========================================================================

  describe "Progress.new/1" do
    test "creates progress with config" do
      config = %{output_dir: "/tmp/output"}
      progress = Progress.new(config)

      assert %Progress{} = progress
      assert progress.config == config
      assert progress.current_page == 1
      assert progress.processed == []
      assert %DateTime{} = progress.started_at
      assert %DateTime{} = progress.updated_at
    end

    test "creates progress with empty config" do
      progress = Progress.new()

      assert progress.config == %{}
    end
  end

  # ===========================================================================
  # PackageResult Struct Tests
  # ===========================================================================

  describe "PackageResult.success/3" do
    test "creates successful result" do
      result =
        PackageResult.success("phoenix", "1.7.10",
          output_path: "/tmp/phoenix.ttl",
          duration_ms: 1500,
          module_count: 42
        )

      assert result.name == "phoenix"
      assert result.version == "1.7.10"
      assert result.status == :completed
      assert result.output_path == "/tmp/phoenix.ttl"
      assert result.duration_ms == 1500
      assert result.module_count == 42
      assert result.error == nil
      assert %DateTime{} = result.processed_at
    end
  end

  describe "PackageResult.failure/3" do
    test "creates failure result" do
      result =
        PackageResult.failure("broken", "1.0.0",
          error: "Connection refused",
          error_type: :download_error,
          duration_ms: 500
        )

      assert result.name == "broken"
      assert result.version == "1.0.0"
      assert result.status == :failed
      assert result.error == "Connection refused"
      assert result.error_type == :download_error
      assert result.duration_ms == 500
    end
  end

  describe "PackageResult.skipped/3" do
    test "creates skipped result" do
      result =
        PackageResult.skipped("erlang_pkg", "2.0.0",
          reason: "Erlang-only package",
          error_type: :not_elixir
        )

      assert result.name == "erlang_pkg"
      assert result.version == "2.0.0"
      assert result.status == :skipped
      assert result.error == "Erlang-only package"
      assert result.error_type == :not_elixir
      assert result.duration_ms == 0
    end
  end

  # ===========================================================================
  # Progress Manipulation Tests
  # ===========================================================================

  describe "add_result/2" do
    test "adds result to processed list" do
      progress = Progress.new()
      result = PackageResult.success("phoenix", "1.7.10")

      updated = Progress.add_result(progress, result)

      assert length(updated.processed) == 1
      assert hd(updated.processed).name == "phoenix"
    end

    test "prepends to list (most recent first)" do
      progress = Progress.new()
      result1 = PackageResult.success("first", "1.0.0")
      result2 = PackageResult.success("second", "1.0.0")

      updated =
        progress
        |> Progress.add_result(result1)
        |> Progress.add_result(result2)

      assert hd(updated.processed).name == "second"
    end

    test "updates updated_at timestamp" do
      progress = Progress.new()
      result = PackageResult.success("test", "1.0.0")

      # Small delay to ensure timestamp difference
      :timer.sleep(10)
      updated = Progress.add_result(progress, result)

      assert DateTime.compare(updated.updated_at, progress.updated_at) in [:gt, :eq]
    end
  end

  describe "update_page/2" do
    test "updates current page" do
      progress = Progress.new()
      updated = Progress.update_page(progress, 5)

      assert updated.current_page == 5
    end
  end

  describe "set_total/2" do
    test "sets total package count" do
      progress = Progress.new()
      updated = Progress.set_total(progress, 18_000)

      assert updated.total_packages == 18_000
    end
  end

  # ===========================================================================
  # Query Tests
  # ===========================================================================

  describe "is_processed?/2" do
    test "returns true for processed package" do
      progress =
        Progress.new()
        |> Progress.add_result(PackageResult.success("phoenix", "1.7.10"))

      assert Progress.is_processed?(progress, "phoenix")
    end

    test "returns false for unprocessed package" do
      progress =
        Progress.new()
        |> Progress.add_result(PackageResult.success("phoenix", "1.7.10"))

      refute Progress.is_processed?(progress, "ecto")
    end
  end

  describe "count functions" do
    setup do
      progress =
        Progress.new()
        |> Progress.add_result(PackageResult.success("p1", "1.0.0"))
        |> Progress.add_result(PackageResult.success("p2", "1.0.0"))
        |> Progress.add_result(PackageResult.failure("p3", "1.0.0"))
        |> Progress.add_result(PackageResult.skipped("p4", "1.0.0"))

      {:ok, progress: progress}
    end

    test "processed_count returns total", %{progress: progress} do
      assert Progress.processed_count(progress) == 4
    end

    test "success_count returns completed", %{progress: progress} do
      assert Progress.success_count(progress) == 2
    end

    test "failed_count returns failed", %{progress: progress} do
      assert Progress.failed_count(progress) == 1
    end

    test "skipped_count returns skipped", %{progress: progress} do
      assert Progress.skipped_count(progress) == 1
    end
  end

  describe "processed_names/1" do
    test "returns set of processed names" do
      progress =
        Progress.new()
        |> Progress.add_result(PackageResult.success("p1", "1.0.0"))
        |> Progress.add_result(PackageResult.success("p2", "1.0.0"))

      names = Progress.processed_names(progress)

      assert MapSet.member?(names, "p1")
      assert MapSet.member?(names, "p2")
      refute MapSet.member?(names, "p3")
    end
  end

  # ===========================================================================
  # Summary Tests
  # ===========================================================================

  describe "summary/1" do
    test "returns correct statistics" do
      progress =
        Progress.new()
        |> Progress.add_result(PackageResult.success("p1", "1.0.0", duration_ms: 1000))
        |> Progress.add_result(PackageResult.success("p2", "1.0.0", duration_ms: 2000))
        |> Progress.add_result(PackageResult.failure("p3", "1.0.0", duration_ms: 500))

      summary = Progress.summary(progress)

      assert summary.total_processed == 3
      assert summary.succeeded == 2
      assert summary.failed == 1
      assert summary.skipped == 0
      # (1000 + 2000 + 500) / 3
      assert summary.avg_duration_ms == 1166
      assert_in_delta summary.success_rate, 66.67, 0.1
    end

    test "handles empty progress" do
      progress = Progress.new()
      summary = Progress.summary(progress)

      assert summary.total_processed == 0
      assert summary.succeeded == 0
      assert summary.avg_duration_ms == 0
      assert summary.success_rate == 0.0
    end

    test "includes estimated remaining when total known" do
      progress =
        Progress.new()
        |> Progress.set_total(100)
        |> Progress.add_result(PackageResult.success("p1", "1.0.0", duration_ms: 1000))

      summary = Progress.summary(progress)

      assert summary.estimated_remaining_seconds != nil
    end
  end

  describe "format_summary/1" do
    test "returns formatted string" do
      progress =
        Progress.new()
        |> Progress.add_result(PackageResult.success("p1", "1.0.0"))

      summary_str = Progress.format_summary(progress)

      assert summary_str =~ "Progress Summary"
      assert summary_str =~ "Processed: 1"
      assert summary_str =~ "Succeeded: 1"
    end
  end
end
