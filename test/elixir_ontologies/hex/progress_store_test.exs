defmodule ElixirOntologies.Hex.ProgressStoreTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.Progress
  alias ElixirOntologies.Hex.Progress.PackageResult
  alias ElixirOntologies.Hex.ProgressStore

  # ===========================================================================
  # Serialization Tests
  # ===========================================================================

  describe "to_json/1" do
    test "serializes progress to JSON" do
      progress = Progress.new(%{output_dir: "/tmp"})
        |> Progress.add_result(PackageResult.success("phoenix", "1.7.10"))

      json = ProgressStore.to_json(progress)

      assert is_binary(json)
      assert json =~ "phoenix"
      assert json =~ "output_dir"
    end

    test "serializes DateTimes as ISO 8601" do
      progress = Progress.new()
      json = ProgressStore.to_json(progress)

      # ISO 8601 format
      assert json =~ ~r/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
    end
  end

  describe "from_json/1" do
    test "deserializes JSON to progress" do
      original = Progress.new(%{output_dir: "/tmp"})
        |> Progress.add_result(PackageResult.success("phoenix", "1.7.10"))

      json = ProgressStore.to_json(original)
      {:ok, restored} = ProgressStore.from_json(json)

      assert restored.config["output_dir"] == "/tmp"
      assert length(restored.processed) == 1
      assert hd(restored.processed).name == "phoenix"
    end

    test "handles invalid JSON" do
      result = ProgressStore.from_json("not valid json")

      assert {:error, {:invalid_json, _}} = result
    end

    test "roundtrips DateTimes correctly" do
      original = Progress.new()
      json = ProgressStore.to_json(original)
      {:ok, restored} = ProgressStore.from_json(json)

      # Within 1 second due to ISO 8601 precision
      assert DateTime.diff(restored.started_at, original.started_at) == 0
    end

    test "roundtrips PackageResult structs" do
      result = PackageResult.failure("test", "1.0.0",
        error: "Connection failed",
        error_type: :download_error,
        duration_ms: 500
      )

      original = Progress.new() |> Progress.add_result(result)
      json = ProgressStore.to_json(original)
      {:ok, restored} = ProgressStore.from_json(json)

      restored_result = hd(restored.processed)
      assert restored_result.name == "test"
      assert restored_result.status == :failed
      assert restored_result.error_type == :download_error
      assert restored_result.duration_ms == 500
    end
  end

  # ===========================================================================
  # File Operations Tests
  # ===========================================================================

  describe "save/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "progress_save_test_#{:rand.uniform(100_000)}.json")

      on_exit(fn ->
        File.rm(test_file)
      end)

      {:ok, test_file: test_file}
    end

    test "saves progress to file", %{test_file: file} do
      progress = Progress.new(%{test: true})

      assert :ok = ProgressStore.save(progress, file)
      assert File.exists?(file)
    end

    test "creates parent directories", %{test_file: file} do
      nested_file = Path.join([Path.dirname(file), "nested", "dir", "progress.json"])

      on_exit(fn ->
        File.rm_rf!(Path.dirname(Path.dirname(nested_file)))
      end)

      progress = Progress.new()

      assert :ok = ProgressStore.save(progress, nested_file)
      assert File.exists?(nested_file)
    end

    test "uses atomic write (temp file then rename)" do
      # This is tested indirectly - if atomic write fails,
      # we shouldn't have partial files
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "atomic_test_#{:rand.uniform(100_000)}.json")

      on_exit(fn ->
        File.rm(test_file)
      end)

      progress = Progress.new()
      :ok = ProgressStore.save(progress, test_file)

      # File should be valid JSON
      {:ok, content} = File.read(test_file)
      assert {:ok, _} = Jason.decode(content)
    end
  end

  describe "load/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "progress_load_test_#{:rand.uniform(100_000)}.json")

      {:ok, test_file: test_file}
    end

    test "loads progress from file", %{test_file: file} do
      original = Progress.new(%{test: "value"})
      :ok = ProgressStore.save(original, file)

      {:ok, loaded} = ProgressStore.load(file)

      assert loaded.config["test"] == "value"

      File.rm(file)
    end

    test "returns error for missing file", %{test_file: file} do
      result = ProgressStore.load(file)

      assert result == {:error, :not_found}
    end

    test "returns error for invalid JSON", %{test_file: file} do
      File.write!(file, "not json")

      result = ProgressStore.load(file)

      assert {:error, {:invalid_json, _}} = result

      File.rm(file)
    end
  end

  describe "load_or_create/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "progress_loc_test_#{:rand.uniform(100_000)}.json")

      on_exit(fn ->
        File.rm(test_file)
      end)

      {:ok, test_file: test_file}
    end

    test "creates new progress when file doesn't exist", %{test_file: file} do
      config = %{output_dir: "/tmp"}

      {:ok, progress, status} = ProgressStore.load_or_create(file, config)

      assert status == :new
      assert progress.config == config
    end

    test "resumes from existing file", %{test_file: file} do
      original = Progress.new(%{"original" => true})
        |> Progress.add_result(PackageResult.success("pkg", "1.0.0"))
      :ok = ProgressStore.save(original, file)

      {:ok, progress, status} = ProgressStore.load_or_create(file, %{"new" => true})

      assert status == :resumed
      assert length(progress.processed) == 1
      # Config should be merged
      assert progress.config["new"] == true
      assert progress.config["original"] == true
    end

    test "handles corrupted file gracefully", %{test_file: file} do
      File.write!(file, "corrupted data")

      {:ok, progress, status} = ProgressStore.load_or_create(file, %{})

      assert status == :new
      assert progress.processed == []
    end
  end

  # ===========================================================================
  # Checkpoint Tests
  # ===========================================================================

  describe "should_checkpoint?/1" do
    test "returns true at checkpoint interval" do
      # Add exactly checkpoint_interval results
      progress = Enum.reduce(1..10, Progress.new(), fn i, acc ->
        Progress.add_result(acc, PackageResult.success("pkg#{i}", "1.0.0"))
      end)

      assert ProgressStore.should_checkpoint?(progress)
    end

    test "returns false between intervals" do
      progress = Enum.reduce(1..5, Progress.new(), fn i, acc ->
        Progress.add_result(acc, PackageResult.success("pkg#{i}", "1.0.0"))
      end)

      refute ProgressStore.should_checkpoint?(progress)
    end

    test "returns false for empty progress" do
      progress = Progress.new()

      refute ProgressStore.should_checkpoint?(progress)
    end
  end

  describe "checkpoint/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "checkpoint_test_#{:rand.uniform(100_000)}.json")

      on_exit(fn ->
        File.rm(test_file)
      end)

      {:ok, test_file: test_file}
    end

    test "saves and returns updated progress", %{test_file: file} do
      progress = Progress.new()

      {:ok, updated} = ProgressStore.checkpoint(progress, file)

      assert File.exists?(file)
      assert DateTime.compare(updated.updated_at, progress.updated_at) in [:gt, :eq]
    end
  end

  describe "maybe_checkpoint/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "maybe_cp_test_#{:rand.uniform(100_000)}.json")

      on_exit(fn ->
        File.rm(test_file)
      end)

      {:ok, test_file: test_file}
    end

    test "saves when at interval", %{test_file: file} do
      progress = Enum.reduce(1..10, Progress.new(), fn i, acc ->
        Progress.add_result(acc, PackageResult.success("pkg#{i}", "1.0.0"))
      end)

      {:ok, _} = ProgressStore.maybe_checkpoint(progress, file)

      assert File.exists?(file)
    end

    test "skips when not at interval", %{test_file: file} do
      progress = Enum.reduce(1..5, Progress.new(), fn i, acc ->
        Progress.add_result(acc, PackageResult.success("pkg#{i}", "1.0.0"))
      end)

      {:ok, _} = ProgressStore.maybe_checkpoint(progress, file)

      refute File.exists?(file)
    end
  end

  describe "checkpoint_interval/0" do
    test "returns configured interval" do
      assert ProgressStore.checkpoint_interval() == 10
    end
  end
end
