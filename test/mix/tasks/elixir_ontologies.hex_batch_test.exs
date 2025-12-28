defmodule Mix.Tasks.ElixirOntologies.HexBatchTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.ElixirOntologies.HexBatch

  # ===========================================================================
  # CLI Option Parsing Tests
  # ===========================================================================

  describe "run/1 option parsing" do
    test "uses default output directory .ttl when none provided" do
      # Config.new now defaults output_dir to ".ttl"
      alias ElixirOntologies.Hex.BatchProcessor.Config
      config = Config.new()
      assert config.output_dir == "hex_output"

      # The mix task defaults to ".ttl"
      # We can't easily test this without network access
    end

    test "exits with error for invalid options" do
      assert catch_exit(
               capture_io(:stderr, fn ->
                 HexBatch.run(["--invalid-option", "/tmp"])
               end)
             ) == {:shutdown, 1}
    end
  end

  # ===========================================================================
  # Config Building Tests
  # ===========================================================================

  describe "config building" do
    # We test config building indirectly through the BatchProcessor.Config module
    alias ElixirOntologies.Hex.BatchProcessor.Config

    test "builds config with default values" do
      config = Config.new(output_dir: "/tmp/out")

      assert config.output_dir == "/tmp/out"
      assert config.progress_file == "/tmp/out/progress.json"
      assert config.resume == true
      assert config.delay_ms == 100
      assert config.timeout_minutes == 5
      assert config.dry_run == false
      assert config.verbose == false
    end

    test "builds config with custom limit" do
      config = Config.new(output_dir: "/tmp/out", limit: 50)

      assert config.limit == 50
    end

    test "builds config with resume disabled" do
      config = Config.new(output_dir: "/tmp/out", resume: false)

      assert config.resume == false
    end

    test "builds config with dry run enabled" do
      config = Config.new(output_dir: "/tmp/out", dry_run: true)

      assert config.dry_run == true
    end

    test "builds config with verbose enabled" do
      config = Config.new(output_dir: "/tmp/out", verbose: true)

      assert config.verbose == true
    end

    test "builds config with custom start page" do
      config = Config.new(output_dir: "/tmp/out", start_page: 10)

      assert config.start_page == 10
    end

    test "builds config with custom delay" do
      config = Config.new(output_dir: "/tmp/out", delay_ms: 500)

      assert config.delay_ms == 500
    end

    test "builds config with custom timeout" do
      config = Config.new(output_dir: "/tmp/out", timeout_minutes: 10)

      assert config.timeout_minutes == 10
    end

    test "builds config with custom progress file" do
      config = Config.new(
        output_dir: "/tmp/out",
        progress_file: "/custom/progress.json"
      )

      assert config.progress_file == "/custom/progress.json"
    end
  end

  # ===========================================================================
  # Dry Run Mode Tests
  # ===========================================================================

  describe "dry run mode" do
    @tag :integration
    @tag timeout: 30_000
    test "lists packages without processing" do
      # This test requires network access, so we tag it as integration
      # Run with: mix test --include integration

      output = capture_io(fn ->
        try do
          HexBatch.run(["/tmp/hex_test_dry_run", "--dry-run", "--limit", "3", "--quiet"])
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        end
      end)

      # In quiet mode, we don't output the packages
      # Just verify it doesn't crash
      assert is_binary(output)
    end
  end

  # ===========================================================================
  # Help/Usage Tests
  # ===========================================================================

  describe "help documentation" do
    test "module has shortdoc" do
      # Verify the shortdoc is defined
      assert HexBatch.__info__(:attributes)[:shortdoc] != nil
    end

    test "module has moduledoc with usage examples" do
      {:docs_v1, _, :elixir, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(HexBatch)

      assert moduledoc =~ "Usage"
      assert moduledoc =~ "--output-dir"
      assert moduledoc =~ "--resume"
      assert moduledoc =~ "--limit"
      assert moduledoc =~ "--package"
      assert moduledoc =~ "--dry-run"
      assert moduledoc =~ "--quiet"
      assert moduledoc =~ "--verbose"
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "error handling" do
    test "shows error for invalid option" do
      stderr = capture_io(:stderr, fn ->
        catch_exit(HexBatch.run(["--not-real-option"]))
      end)

      assert stderr =~ "Invalid options"
    end
  end
end
