defmodule ElixirOntologies.Hex.BatchProcessorTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.BatchProcessor
  alias ElixirOntologies.Hex.BatchProcessor.Config

  # ===========================================================================
  # Config Tests
  # ===========================================================================

  describe "Config.new/1" do
    test "creates config with defaults" do
      config = Config.new()

      assert config.output_dir == "hex_output"
      assert config.progress_file == "hex_output/progress.json"
      assert config.start_page == 1
      assert config.delay_ms == 100
      assert config.api_delay_ms == 50
      assert config.timeout_minutes == 5
      assert config.resume == true
      assert config.dry_run == false
      assert config.verbose == false
      assert config.limit == nil
    end

    test "accepts custom output_dir" do
      config = Config.new(output_dir: "/custom/output")

      assert config.output_dir == "/custom/output"
      assert config.progress_file == "/custom/output/progress.json"
    end

    test "accepts custom progress_file" do
      config = Config.new(
        output_dir: "/output",
        progress_file: "/other/progress.json"
      )

      assert config.progress_file == "/other/progress.json"
    end

    test "accepts custom temp_dir" do
      config = Config.new(temp_dir: "/my/tmp")

      assert config.temp_dir == "/my/tmp"
    end

    test "accepts limit" do
      config = Config.new(limit: 100)

      assert config.limit == 100
    end

    test "accepts start_page" do
      config = Config.new(start_page: 5)

      assert config.start_page == 5
    end

    test "accepts delay_ms" do
      config = Config.new(delay_ms: 500)

      assert config.delay_ms == 500
    end

    test "accepts api_delay_ms" do
      config = Config.new(api_delay_ms: 200)

      assert config.api_delay_ms == 200
    end

    test "accepts timeout_minutes" do
      config = Config.new(timeout_minutes: 10)

      assert config.timeout_minutes == 10
    end

    test "accepts base_iri_template" do
      template = "https://example.com/pkg/:name#"
      config = Config.new(base_iri_template: template)

      assert config.base_iri_template == template
    end

    test "accepts resume flag" do
      config = Config.new(resume: false)

      assert config.resume == false
    end

    test "accepts dry_run flag" do
      config = Config.new(dry_run: true)

      assert config.dry_run == true
    end

    test "accepts verbose flag" do
      config = Config.new(verbose: true)

      assert config.verbose == true
    end
  end

  describe "Config.validate/1" do
    test "returns :ok for valid config" do
      config = Config.new(output_dir: "/output")

      assert :ok = Config.validate(config)
    end

    test "returns error for nil output_dir" do
      config = %Config{Config.new() | output_dir: nil}

      assert {:error, :output_dir_required} = Config.validate(config)
    end

    test "returns error for empty output_dir" do
      config = %Config{Config.new() | output_dir: ""}

      assert {:error, :output_dir_required} = Config.validate(config)
    end

    test "returns error for nil progress_file" do
      config = %Config{Config.new() | progress_file: nil}

      assert {:error, :progress_file_required} = Config.validate(config)
    end

    test "returns error for empty progress_file" do
      config = %Config{Config.new() | progress_file: ""}

      assert {:error, :progress_file_required} = Config.validate(config)
    end

    test "returns error for invalid timeout" do
      config = %Config{Config.new() | timeout_minutes: 0}

      assert {:error, :invalid_timeout} = Config.validate(config)
    end

    test "returns error for negative timeout" do
      config = %Config{Config.new() | timeout_minutes: -1}

      assert {:error, :invalid_timeout} = Config.validate(config)
    end
  end

  # ===========================================================================
  # Initialization Tests
  # ===========================================================================

  describe "init/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "batch_init_test_#{:rand.uniform(100_000)}")

      on_exit(fn ->
        File.rm_rf(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "initializes with valid config", %{test_dir: dir} do
      config = Config.new(output_dir: dir)

      assert {:ok, state} = BatchProcessor.init(config)

      assert state.config == config
      assert state.http_client != nil
      assert state.progress != nil
      assert state.rate_limiter != nil
      assert state.processed_count == 0
      assert state.interrupted == false
    end

    test "creates output directory", %{test_dir: dir} do
      config = Config.new(output_dir: dir)

      refute File.exists?(dir)

      {:ok, _state} = BatchProcessor.init(config)

      assert File.dir?(dir)
    end

    test "returns error for invalid config" do
      config = %Config{Config.new() | output_dir: nil}

      assert {:error, :output_dir_required} = BatchProcessor.init(config)
    end

    test "loads existing progress when resume is true", %{test_dir: dir} do
      progress_file = Path.join(dir, "progress.json")

      # Create existing progress file
      existing_progress = %{
        "started_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "updated_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "processed" => [
          %{"name" => "existing", "version" => "1.0.0", "status" => "completed"}
        ],
        "current_page" => 3,
        "config" => %{}
      }
      File.mkdir_p!(dir)
      File.write!(progress_file, Jason.encode!(existing_progress))

      config = Config.new(output_dir: dir, progress_file: progress_file, resume: true)

      {:ok, state} = BatchProcessor.init(config)

      assert length(state.progress.processed) == 1
      assert state.progress.current_page == 3
    end

    test "creates new progress when resume is false", %{test_dir: dir} do
      config = Config.new(output_dir: dir, resume: false)

      {:ok, state} = BatchProcessor.init(config)

      assert state.progress.processed == []
    end
  end

  # ===========================================================================
  # Run Tests
  # ===========================================================================

  describe "run/1" do
    test "returns error for invalid config" do
      config = %Config{Config.new() | output_dir: nil}

      assert {:error, :output_dir_required} = BatchProcessor.run(config)
    end
  end

  # ===========================================================================
  # Handle Interrupt Tests
  # ===========================================================================

  describe "handle_interrupt/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "interrupt_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "saves progress and sets interrupted flag", %{test_dir: dir} do
      config = Config.new(output_dir: dir)
      {:ok, state} = BatchProcessor.init(config)

      updated_state = BatchProcessor.handle_interrupt(state)

      assert updated_state.interrupted == true
      assert File.exists?(config.progress_file)
    end
  end
end
