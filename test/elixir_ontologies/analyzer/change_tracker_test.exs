defmodule ElixirOntologies.Analyzer.ChangeTrackerTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.ChangeTracker
  alias ElixirOntologies.Analyzer.ChangeTracker.{State, FileInfo, Changes}

  doctest ElixirOntologies.Analyzer.ChangeTracker

  # ============================================================================
  # State Capture Tests
  # ============================================================================

  describe "capture_state/1" do
    test "captures file metadata for existing files" do
      # Use test files that exist
      files = [
        "mix.exs",
        "lib/elixir_ontologies.ex"
      ]

      state = ChangeTracker.capture_state(files)

      assert %State{} = state
      assert is_map(state.files)
      assert map_size(state.files) == 2
      assert is_integer(state.timestamp)

      # Check mix.exs info
      mix_info = state.files["mix.exs"]
      assert %FileInfo{} = mix_info
      assert mix_info.path == "mix.exs"
      assert is_integer(mix_info.mtime)
      assert mix_info.size > 0

      # Check lib file info
      lib_info = state.files["lib/elixir_ontologies.ex"]
      assert %FileInfo{} = lib_info
      assert lib_info.path == "lib/elixir_ontologies.ex"
      assert is_integer(lib_info.mtime)
      assert lib_info.size > 0
    end

    test "skips non-existent files" do
      files = [
        "mix.exs",
        "/nonexistent/file.ex"
      ]

      state = ChangeTracker.capture_state(files)

      # Should only capture mix.exs
      assert map_size(state.files) == 1
      assert Map.has_key?(state.files, "mix.exs")
      refute Map.has_key?(state.files, "/nonexistent/file.ex")
    end

    test "handles empty file list" do
      state = ChangeTracker.capture_state([])

      assert %State{} = state
      assert map_size(state.files) == 0
      assert is_integer(state.timestamp)
    end
  end

  # ============================================================================
  # Changed Files Detection Tests
  # ============================================================================

  describe "changed_files/2" do
    test "detects files with different mtime" do
      old_state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 100},
          "file2.ex" => %FileInfo{path: "file2.ex", mtime: 2000, size: 200}
        },
        timestamp: 1000
      }

      new_state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1500, size: 100},
          "file2.ex" => %FileInfo{path: "file2.ex", mtime: 2000, size: 200}
        },
        timestamp: 2000
      }

      changed = ChangeTracker.changed_files(old_state, new_state)

      assert changed == ["file1.ex"]
    end

    test "detects files with different size" do
      old_state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 100},
          "file2.ex" => %FileInfo{path: "file2.ex", mtime: 2000, size: 200}
        },
        timestamp: 1000
      }

      new_state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 150},
          "file2.ex" => %FileInfo{path: "file2.ex", mtime: 2000, size: 200}
        },
        timestamp: 2000
      }

      changed = ChangeTracker.changed_files(old_state, new_state)

      assert changed == ["file1.ex"]
    end

    test "returns empty list when no files changed" do
      state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 100}
        },
        timestamp: 1000
      }

      changed = ChangeTracker.changed_files(state, state)

      assert changed == []
    end
  end

  # ============================================================================
  # New Files Detection Tests
  # ============================================================================

  describe "new_files/2" do
    test "detects files added in new state" do
      old_state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 100}
        },
        timestamp: 1000
      }

      new_state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 100},
          "file2.ex" => %FileInfo{path: "file2.ex", mtime: 2000, size: 200},
          "file3.ex" => %FileInfo{path: "file3.ex", mtime: 3000, size: 300}
        },
        timestamp: 2000
      }

      new_files = ChangeTracker.new_files(old_state, new_state)

      assert new_files == ["file2.ex", "file3.ex"]
    end

    test "returns empty list when no new files" do
      state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 100}
        },
        timestamp: 1000
      }

      new_files = ChangeTracker.new_files(state, state)

      assert new_files == []
    end
  end

  # ============================================================================
  # Deleted Files Detection Tests
  # ============================================================================

  describe "deleted_files/2" do
    test "detects files removed in new state" do
      old_state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 100},
          "file2.ex" => %FileInfo{path: "file2.ex", mtime: 2000, size: 200},
          "file3.ex" => %FileInfo{path: "file3.ex", mtime: 3000, size: 300}
        },
        timestamp: 1000
      }

      new_state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 100}
        },
        timestamp: 2000
      }

      deleted = ChangeTracker.deleted_files(old_state, new_state)

      assert deleted == ["file2.ex", "file3.ex"]
    end

    test "returns empty list when no files deleted" do
      state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 100}
        },
        timestamp: 1000
      }

      deleted = ChangeTracker.deleted_files(state, state)

      assert deleted == []
    end
  end

  # ============================================================================
  # Unified Change Detection Tests
  # ============================================================================

  describe "detect_changes/2" do
    test "detects all types of changes" do
      old_state = %State{
        files: %{
          "unchanged.ex" => %FileInfo{path: "unchanged.ex", mtime: 1000, size: 100},
          "changed.ex" => %FileInfo{path: "changed.ex", mtime: 2000, size: 200},
          "deleted.ex" => %FileInfo{path: "deleted.ex", mtime: 3000, size: 300}
        },
        timestamp: 1000
      }

      new_state = %State{
        files: %{
          "unchanged.ex" => %FileInfo{path: "unchanged.ex", mtime: 1000, size: 100},
          "changed.ex" => %FileInfo{path: "changed.ex", mtime: 2500, size: 200},
          "new.ex" => %FileInfo{path: "new.ex", mtime: 4000, size: 400}
        },
        timestamp: 2000
      }

      changes = ChangeTracker.detect_changes(old_state, new_state)

      assert %Changes{} = changes
      assert changes.changed == ["changed.ex"]
      assert changes.new == ["new.ex"]
      assert changes.deleted == ["deleted.ex"]
      assert changes.unchanged == ["unchanged.ex"]
    end

    test "returns empty changes when states are identical" do
      state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 100}
        },
        timestamp: 1000
      }

      changes = ChangeTracker.detect_changes(state, state)

      assert changes.changed == []
      assert changes.new == []
      assert changes.deleted == []
      assert changes.unchanged == ["file1.ex"]
    end
  end

  # ============================================================================
  # Edge Cases Tests
  # ============================================================================

  describe "edge cases" do
    test "handles both states being empty" do
      empty_state = %State{files: %{}, timestamp: 1000}

      changes = ChangeTracker.detect_changes(empty_state, empty_state)

      assert changes.changed == []
      assert changes.new == []
      assert changes.deleted == []
      assert changes.unchanged == []
    end

    test "handles transition from empty to non-empty" do
      old_state = %State{files: %{}, timestamp: 1000}

      new_state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 2000, size: 200}
        },
        timestamp: 2000
      }

      changes = ChangeTracker.detect_changes(old_state, new_state)

      assert changes.changed == []
      assert changes.new == ["file1.ex"]
      assert changes.deleted == []
      assert changes.unchanged == []
    end

    test "handles transition from non-empty to empty" do
      old_state = %State{
        files: %{
          "file1.ex" => %FileInfo{path: "file1.ex", mtime: 1000, size: 100}
        },
        timestamp: 1000
      }

      new_state = %State{files: %{}, timestamp: 2000}

      changes = ChangeTracker.detect_changes(old_state, new_state)

      assert changes.changed == []
      assert changes.new == []
      assert changes.deleted == ["file1.ex"]
      assert changes.unchanged == []
    end
  end
end
