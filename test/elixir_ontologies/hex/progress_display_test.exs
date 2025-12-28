defmodule ElixirOntologies.Hex.ProgressDisplayTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias ElixirOntologies.Hex.Progress
  alias ElixirOntologies.Hex.Progress.PackageResult
  alias ElixirOntologies.Hex.ProgressDisplay

  # ===========================================================================
  # Status Line Tests
  # ===========================================================================

  describe "status_line/3" do
    test "formats status with total" do
      progress = Progress.new()
        |> Progress.set_total(1000)
        |> Progress.add_result(PackageResult.success("p1", "1.0.0"))

      line = ProgressDisplay.status_line(progress, "phoenix", "1.7.10")

      assert line =~ "[1/1000]"
      assert line =~ "phoenix v1.7.10"
      assert line =~ "0.1% complete"
    end

    test "formats status without total" do
      progress = Progress.new()
        |> Progress.add_result(PackageResult.success("p1", "1.0.0"))

      line = ProgressDisplay.status_line(progress, "ecto", "3.11.0")

      assert line =~ "[1]"
      assert line =~ "ecto v3.11.0"
      refute line =~ "complete"
    end

    test "handles empty progress" do
      progress = Progress.new()

      line = ProgressDisplay.status_line(progress, "phoenix", "1.7.10")

      assert line =~ "[0]"
      assert line =~ "phoenix v1.7.10"
    end
  end

  describe "print_status/3" do
    test "outputs status line" do
      progress = Progress.new()

      output = capture_io(fn ->
        ProgressDisplay.print_status(progress, "phoenix", "1.7.10")
      end)

      assert output =~ "phoenix v1.7.10"
    end
  end

  # ===========================================================================
  # ETA Tests
  # ===========================================================================

  describe "calculate_eta/1" do
    test "calculates ETA from average duration" do
      progress = Progress.new()
        |> Progress.set_total(100)
        |> Progress.add_result(PackageResult.success("p1", "1.0.0", duration_ms: 1000))
        |> Progress.add_result(PackageResult.success("p2", "1.0.0", duration_ms: 2000))

      eta = ProgressDisplay.calculate_eta(progress)

      # Average is 1500ms, 98 remaining = 147 seconds
      assert eta == 147
    end

    test "returns nil when no total" do
      progress = Progress.new()
        |> Progress.add_result(PackageResult.success("p1", "1.0.0", duration_ms: 1000))

      eta = ProgressDisplay.calculate_eta(progress)

      assert eta == nil
    end

    test "returns nil when no packages processed" do
      progress = Progress.new()
        |> Progress.set_total(100)

      eta = ProgressDisplay.calculate_eta(progress)

      assert eta == nil
    end

    test "returns nil when all packages processed" do
      progress = Progress.new()
        |> Progress.set_total(1)
        |> Progress.add_result(PackageResult.success("p1", "1.0.0", duration_ms: 1000))

      eta = ProgressDisplay.calculate_eta(progress)

      assert eta == nil
    end
  end

  describe "format_eta/1" do
    test "formats nil as calculating" do
      assert ProgressDisplay.format_eta(nil) == "calculating..."
    end

    test "formats seconds" do
      assert ProgressDisplay.format_eta(30) == "30s"
    end

    test "formats minutes and seconds" do
      assert ProgressDisplay.format_eta(90) == "1m 30s"
    end

    test "formats hours and minutes" do
      assert ProgressDisplay.format_eta(7500) == "2h 5m"
    end
  end

  # ===========================================================================
  # Stats Line Tests
  # ===========================================================================

  describe "stats_line/1" do
    test "formats success/fail/skip counts" do
      progress = Progress.new()
        |> Progress.add_result(PackageResult.success("p1", "1.0.0"))
        |> Progress.add_result(PackageResult.success("p2", "1.0.0"))
        |> Progress.add_result(PackageResult.failure("p3", "1.0.0"))
        |> Progress.add_result(PackageResult.skipped("p4", "1.0.0"))

      line = ProgressDisplay.stats_line(progress)

      # Check for counts regardless of color codes
      assert line =~ "2"  # success
      assert line =~ "1"  # fail and skip
    end

    test "handles all zeros" do
      progress = Progress.new()

      line = ProgressDisplay.stats_line(progress)

      assert line =~ "0"
    end
  end

  describe "supports_color?/0" do
    test "returns boolean" do
      result = ProgressDisplay.supports_color?()
      assert is_boolean(result)
    end
  end

  # ===========================================================================
  # Logging Tests
  # ===========================================================================

  describe "log_start/2" do
    test "outputs package start message" do
      output = capture_io(fn ->
        ProgressDisplay.log_start("phoenix", "1.7.10")
      end)

      assert output =~ "Starting: phoenix v1.7.10"
      # Should have timestamp
      assert output =~ ~r/\[\d{2}:\d{2}:\d{2}\]/
    end
  end

  describe "log_complete/3" do
    test "outputs complete message with duration" do
      output = capture_io(fn ->
        ProgressDisplay.log_complete("phoenix", "1.7.10", 1500)
      end)

      assert output =~ "Complete: phoenix v1.7.10"
      assert output =~ "1.5s"
    end
  end

  describe "log_error/3" do
    test "outputs error message" do
      output = capture_io(fn ->
        ProgressDisplay.log_error("broken", "1.0.0", :connection_failed)
      end)

      assert output =~ "broken v1.0.0"
      assert output =~ "connection_failed"
    end
  end

  describe "log_skip/3" do
    test "outputs skip message" do
      output = capture_io(fn ->
        ProgressDisplay.log_skip("erlang_pkg", "1.0.0", "not Elixir")
      end)

      assert output =~ "erlang_pkg v1.0.0"
      assert output =~ "not Elixir"
    end
  end

  # ===========================================================================
  # Summary Display Tests
  # ===========================================================================

  describe "display_summary/2" do
    test "displays summary output" do
      progress = Progress.new()
        |> Progress.add_result(PackageResult.success("p1", "1.0.0"))
        |> Progress.add_result(PackageResult.failure("p2", "1.0.0"))

      output = capture_io(fn ->
        ProgressDisplay.display_summary(progress, %{output_dir: "/tmp/out"})
      end)

      assert output =~ "Batch Processing Complete"
      assert output =~ "Total processed: 2"
      assert output =~ "Succeeded:       1"
      assert output =~ "Failed:          1"
      assert output =~ "/tmp/out"
    end

    test "suggests retry for failures" do
      progress = Progress.new()
        |> Progress.add_result(PackageResult.failure("p1", "1.0.0"))

      output = capture_io(fn ->
        ProgressDisplay.display_summary(progress)
      end)

      assert output =~ "retry failed packages"
    end
  end

  describe "display_banner/1" do
    test "displays startup banner" do
      config = %{
        output_dir: "/tmp/output",
        limit: 100,
        resume: true
      }

      output = capture_io(fn ->
        ProgressDisplay.display_banner(config)
      end)

      assert output =~ "Hex.pm Batch Analyzer"
      assert output =~ "/tmp/output"
      assert output =~ "100"
      assert output =~ "Resume mode"
    end
  end

  # ===========================================================================
  # Dry Run Display Tests
  # ===========================================================================

  describe "print_dry_run_package/3" do
    test "outputs indexed package line" do
      output = capture_io(fn ->
        ProgressDisplay.print_dry_run_package("phoenix", "1.7.10", 42)
      end)

      assert output =~ "42. phoenix v1.7.10"
    end
  end

  describe "display_dry_run_summary/1" do
    test "outputs package count" do
      output = capture_io(fn ->
        ProgressDisplay.display_dry_run_summary(150)
      end)

      assert output =~ "Total Elixir packages found: 150"
      assert output =~ "without --dry-run"
    end
  end
end
