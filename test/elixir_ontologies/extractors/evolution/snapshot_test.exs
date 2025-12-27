defmodule ElixirOntologies.Extractors.Evolution.SnapshotTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.Snapshot

  # ===========================================================================
  # Test Setup
  # ===========================================================================

  # Tests run against the actual repository we're in
  # This ensures real git functionality is tested

  # ===========================================================================
  # extract_snapshot/2 Tests
  # ===========================================================================

  describe "extract_snapshot/2" do
    test "extracts snapshot at HEAD" do
      assert {:ok, snapshot} = Snapshot.extract_snapshot(".")
      assert %Snapshot{} = snapshot
    end

    test "snapshot has required struct fields" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      assert is_binary(snapshot.snapshot_id)
      assert String.starts_with?(snapshot.snapshot_id, "snapshot:")
      assert is_binary(snapshot.commit_sha)
      assert String.length(snapshot.commit_sha) == 40
      assert is_binary(snapshot.short_sha)
      assert String.length(snapshot.short_sha) >= 7
    end

    test "snapshot has project information" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      assert snapshot.project_name == :elixir_ontologies
      # Version may be a string, nil, or an atom (from AST parsing of @version)
      assert is_binary(snapshot.project_version) or is_nil(snapshot.project_version) or
               is_atom(snapshot.project_version)
    end

    test "snapshot has timestamp" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      assert %DateTime{} = snapshot.timestamp
    end

    test "snapshot has modules list" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      assert is_list(snapshot.modules)
      assert length(snapshot.modules) > 0
      assert Enum.all?(snapshot.modules, &is_binary/1)
    end

    test "snapshot has files list" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      assert is_list(snapshot.files)
      assert length(snapshot.files) > 0
      assert Enum.all?(snapshot.files, &is_binary/1)

      assert Enum.all?(
               snapshot.files,
               &(String.ends_with?(&1, ".ex") or String.ends_with?(&1, ".exs"))
             )
    end

    test "snapshot has stats map" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      assert is_map(snapshot.stats)
      assert is_integer(snapshot.stats.module_count)
      assert is_integer(snapshot.stats.function_count)
      assert is_integer(snapshot.stats.macro_count)
      assert is_integer(snapshot.stats.protocol_count)
      assert is_integer(snapshot.stats.behaviour_count)
      assert is_integer(snapshot.stats.line_count)
      assert is_integer(snapshot.stats.file_count)
    end

    test "stats are non-negative" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      assert snapshot.stats.module_count >= 0
      assert snapshot.stats.function_count >= 0
      assert snapshot.stats.macro_count >= 0
      assert snapshot.stats.protocol_count >= 0
      assert snapshot.stats.behaviour_count >= 0
      assert snapshot.stats.line_count >= 0
      assert snapshot.stats.file_count >= 0
    end

    test "returns error for invalid repository path" do
      # Git.detect_repo returns :not_found, Project.detect returns :invalid_path
      assert {:error, reason} = Snapshot.extract_snapshot("/nonexistent")
      assert reason in [:not_found, :invalid_path]
    end

    test "returns error for invalid commit ref" do
      assert {:error, _} =
               Snapshot.extract_snapshot(".", "invalid_ref_that_does_not_exist_xyz123")
    end

    test "modules list contains expected modules" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      # Should contain this test's module (or at least modules from the project)
      assert Enum.any?(snapshot.modules, &String.starts_with?(&1, "ElixirOntologies"))
    end

    test "files list contains lib/ files only" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      assert Enum.all?(snapshot.files, fn file ->
               String.starts_with?(file, "lib/") or
                 Regex.match?(~r/^apps\/[^\/]+\/lib\//, file)
             end)
    end
  end

  # ===========================================================================
  # extract_snapshot!/2 Tests
  # ===========================================================================

  describe "extract_snapshot!/2" do
    test "returns snapshot for valid path" do
      snapshot = Snapshot.extract_snapshot!(".")
      assert %Snapshot{} = snapshot
    end

    test "raises for invalid path" do
      assert_raise ArgumentError, fn ->
        Snapshot.extract_snapshot!("/nonexistent")
      end
    end
  end

  # ===========================================================================
  # extract_current_snapshot/1 Tests
  # ===========================================================================

  describe "extract_current_snapshot/1" do
    test "extracts snapshot at HEAD" do
      {:ok, snapshot} = Snapshot.extract_current_snapshot(".")
      assert %Snapshot{} = snapshot

      # Compare with explicit HEAD call
      {:ok, head_snapshot} = Snapshot.extract_snapshot(".", "HEAD")
      assert snapshot.commit_sha == head_snapshot.commit_sha
    end
  end

  # ===========================================================================
  # list_elixir_files_at_commit/2 Tests
  # ===========================================================================

  describe "list_elixir_files_at_commit/2" do
    test "lists elixir files at HEAD" do
      {:ok, files} = Snapshot.list_elixir_files_at_commit(".", "HEAD")

      assert is_list(files)
      assert length(files) > 0
    end

    test "all returned files have .ex or .exs extension" do
      {:ok, files} = Snapshot.list_elixir_files_at_commit(".", "HEAD")

      assert Enum.all?(files, fn file ->
               String.ends_with?(file, ".ex") or String.ends_with?(file, ".exs")
             end)
    end

    test "files are from lib/ directory" do
      {:ok, files} = Snapshot.list_elixir_files_at_commit(".", "HEAD")

      assert Enum.all?(files, fn file ->
               String.starts_with?(file, "lib/") or
                 Regex.match?(~r/^apps\/[^\/]+\/lib\//, file)
             end)
    end

    test "returns error for invalid commit" do
      {:error, reason} = Snapshot.list_elixir_files_at_commit(".", "invalid_sha_xyz")
      assert reason == :command_failed
    end
  end

  # ===========================================================================
  # extract_module_names_at_commit/3 Tests
  # ===========================================================================

  describe "extract_module_names_at_commit/3" do
    test "extracts module names from files" do
      {:ok, files} = Snapshot.list_elixir_files_at_commit(".", "HEAD")
      {:ok, modules} = Snapshot.extract_module_names_at_commit(".", "HEAD", files)

      assert is_list(modules)
      assert length(modules) > 0
    end

    test "module names are strings" do
      {:ok, files} = Snapshot.list_elixir_files_at_commit(".", "HEAD")
      {:ok, modules} = Snapshot.extract_module_names_at_commit(".", "HEAD", files)

      assert Enum.all?(modules, &is_binary/1)
    end

    test "returns unique module names" do
      {:ok, files} = Snapshot.list_elixir_files_at_commit(".", "HEAD")
      {:ok, modules} = Snapshot.extract_module_names_at_commit(".", "HEAD", files)

      assert modules == Enum.uniq(modules)
    end

    test "returns empty list for empty file list" do
      {:ok, modules} = Snapshot.extract_module_names_at_commit(".", "HEAD", [])
      assert modules == []
    end
  end

  # ===========================================================================
  # count_lines_at_commit/3 Tests
  # ===========================================================================

  describe "count_lines_at_commit/3" do
    test "counts lines in files" do
      {:ok, files} = Snapshot.list_elixir_files_at_commit(".", "HEAD")
      line_count = Snapshot.count_lines_at_commit(".", "HEAD", files)

      assert is_integer(line_count)
      assert line_count > 0
    end

    test "returns 0 for empty file list" do
      line_count = Snapshot.count_lines_at_commit(".", "HEAD", [])
      assert line_count == 0
    end
  end

  # ===========================================================================
  # Statistics Tests
  # ===========================================================================

  describe "calculate_statistics/4" do
    test "calculates statistics correctly" do
      {:ok, files} = Snapshot.list_elixir_files_at_commit(".", "HEAD")
      {:ok, modules} = Snapshot.extract_module_names_at_commit(".", "HEAD", files)
      {:ok, stats} = Snapshot.calculate_statistics(".", "HEAD", files, modules)

      assert stats.module_count == length(modules)
      assert stats.file_count == length(files)
      assert stats.function_count >= 0
      assert stats.macro_count >= 0
      assert stats.protocol_count >= 0
      assert stats.behaviour_count >= 0
      assert stats.line_count >= 0
    end

    test "function count is positive for real codebase" do
      {:ok, files} = Snapshot.list_elixir_files_at_commit(".", "HEAD")
      {:ok, modules} = Snapshot.extract_module_names_at_commit(".", "HEAD", files)
      {:ok, stats} = Snapshot.calculate_statistics(".", "HEAD", files, modules)

      # A real Elixir codebase should have functions
      assert stats.function_count > 0
    end
  end

  # ===========================================================================
  # Snapshot ID Tests
  # ===========================================================================

  describe "snapshot_id format" do
    test "snapshot_id follows expected format" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      assert String.starts_with?(snapshot.snapshot_id, "snapshot:")
      # After "snapshot:" should be the short SHA
      [_, sha_part] = String.split(snapshot.snapshot_id, ":", parts: 2)
      assert sha_part == snapshot.short_sha
    end

    test "snapshot_id is deterministic for same commit" do
      {:ok, snapshot1} = Snapshot.extract_snapshot(".")
      {:ok, snapshot2} = Snapshot.extract_snapshot(".")

      assert snapshot1.snapshot_id == snapshot2.snapshot_id
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    @tag :integration
    test "snapshot captures real codebase state" do
      {:ok, snapshot} = Snapshot.extract_snapshot(".")

      # Verify the snapshot reflects a real Elixir project
      assert snapshot.project_name == :elixir_ontologies
      # Should have many modules
      assert length(snapshot.modules) > 10
      # Should have many files
      assert length(snapshot.files) > 10
      # Should have many functions
      assert snapshot.stats.function_count > 50
      # Should have substantial code
      assert snapshot.stats.line_count > 1000
    end

    @tag :integration
    test "snapshot at different commits may differ" do
      # Get current HEAD
      {:ok, head_snapshot} = Snapshot.extract_snapshot(".", "HEAD")

      # Get parent commit if it exists
      case Snapshot.extract_snapshot(".", "HEAD~1") do
        {:ok, parent_snapshot} ->
          # Parent and HEAD should have different SHAs
          assert parent_snapshot.commit_sha != head_snapshot.commit_sha
          assert parent_snapshot.snapshot_id != head_snapshot.snapshot_id

        {:error, _} ->
          # This might be the first commit, which is fine
          :ok
      end
    end
  end
end
