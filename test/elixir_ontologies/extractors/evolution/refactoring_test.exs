defmodule ElixirOntologies.Extractors.Evolution.RefactoringTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.Refactoring
  alias ElixirOntologies.Extractors.Evolution.Refactoring.{Source, Target, DiffHunk}
  alias ElixirOntologies.Extractors.Evolution.Commit

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp create_commit(opts \\ []) do
    %Commit{
      sha: Keyword.get(opts, :sha, "abc123def456abc123def456abc123def456abc1"),
      short_sha: Keyword.get(opts, :short_sha, "abc123d"),
      message: Keyword.get(opts, :message),
      subject: Keyword.get(opts, :subject),
      body: Keyword.get(opts, :body),
      author_name: Keyword.get(opts, :author_name),
      author_email: Keyword.get(opts, :author_email),
      author_date: Keyword.get(opts, :author_date),
      committer_name: Keyword.get(opts, :committer_name),
      committer_email: Keyword.get(opts, :committer_email),
      commit_date: Keyword.get(opts, :commit_date),
      parents: Keyword.get(opts, :parents, []),
      is_merge: Keyword.get(opts, :is_merge, false),
      tree_sha: Keyword.get(opts, :tree_sha),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp create_diff_hunk(opts) do
    %DiffHunk{
      file: Keyword.get(opts, :file, "lib/test.ex"),
      old_file: Keyword.get(opts, :old_file),
      status: Keyword.get(opts, :status, :modified),
      additions: Keyword.get(opts, :additions, []),
      deletions: Keyword.get(opts, :deletions, []),
      similarity: Keyword.get(opts, :similarity)
    }
  end

  # ===========================================================================
  # Refactoring Types Tests
  # ===========================================================================

  describe "refactoring_types/0" do
    test "returns all refactoring types" do
      types = Refactoring.refactoring_types()

      assert :extract_function in types
      assert :extract_module in types
      assert :rename_function in types
      assert :rename_module in types
      assert :rename_variable in types
      assert :inline_function in types
      assert :move_function in types
    end
  end

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "Source struct" do
    test "has default values" do
      source = %Source{}

      assert source.file == nil
      assert source.module == nil
      assert source.function == nil
      assert source.line_range == nil
      assert source.code == nil
    end
  end

  describe "Target struct" do
    test "has default values" do
      target = %Target{}

      assert target.file == nil
      assert target.module == nil
      assert target.function == nil
      assert target.line_range == nil
      assert target.code == nil
    end
  end

  describe "DiffHunk struct" do
    test "has default values" do
      hunk = %DiffHunk{}

      assert hunk.file == nil
      assert hunk.old_file == nil
      assert hunk.status == :modified
      assert hunk.additions == []
      assert hunk.deletions == []
      assert hunk.similarity == nil
    end
  end

  describe "Refactoring struct" do
    test "requires type and commit" do
      commit = create_commit()

      refactoring = %Refactoring{
        type: :extract_function,
        commit: commit
      }

      assert refactoring.type == :extract_function
      assert refactoring.commit == commit
      assert refactoring.confidence == :medium
      assert refactoring.metadata == %{}
    end
  end

  # ===========================================================================
  # Function Extraction Detection Tests
  # ===========================================================================

  describe "detect_function_extractions/3" do
    test "detects new function with call to it" do
      commit = create_commit()

      hunk =
        create_diff_hunk(
          file: "lib/my_module.ex",
          additions: [
            {10, "  defp calculate_total(items) do"},
            {11, "    Enum.sum(items)"},
            {12, "  end"},
            {20, "    total = calculate_total(order.items)"}
          ],
          deletions: [
            {20, "    total = Enum.sum(order.items)"}
          ]
        )

      refactorings = Refactoring.detect_function_extractions(".", commit, [hunk])

      assert length(refactorings) >= 1
      refactoring = List.first(refactorings)
      assert refactoring.type == :extract_function
      assert refactoring.confidence == :high
      assert refactoring.target.function == {:calculate_total, 1}
    end

    test "detects new function with similar deleted code" do
      commit = create_commit()

      hunk =
        create_diff_hunk(
          file: "lib/my_module.ex",
          additions: [
            {10, "  defp process_data(data) do"},
            {11, "    data |> transform() |> validate()"},
            {12, "  end"}
          ],
          deletions: [
            {25, "    result = data |> transform() |> validate()"}
          ]
        )

      refactorings = Refactoring.detect_function_extractions(".", commit, [hunk])

      assert length(refactorings) >= 1
      refactoring = List.first(refactorings)
      assert refactoring.type == :extract_function
    end

    test "returns empty list for non-elixir files" do
      commit = create_commit()

      hunk =
        create_diff_hunk(
          file: "README.md",
          additions: [{1, "# Title"}],
          deletions: []
        )

      refactorings = Refactoring.detect_function_extractions(".", commit, [hunk])
      assert refactorings == []
    end
  end

  # ===========================================================================
  # Module Extraction Detection Tests
  # ===========================================================================

  describe "detect_module_extractions/3" do
    test "detects new module with moved functions" do
      commit = create_commit()

      new_module_hunk =
        create_diff_hunk(
          file: "lib/my_app/helpers.ex",
          status: :added,
          additions: [
            {1, "defmodule MyApp.Helpers do"},
            {2, "  def format_date(date) do"},
            {3, "    Date.to_string(date)"},
            {4, "  end"},
            {5, "end"}
          ]
        )

      modified_hunk =
        create_diff_hunk(
          file: "lib/my_app/main.ex",
          status: :modified,
          deletions: [
            {10, "  def format_date(date) do"},
            {11, "    Date.to_string(date)"},
            {12, "  end"}
          ]
        )

      refactorings =
        Refactoring.detect_module_extractions(".", commit, [new_module_hunk, modified_hunk])

      assert length(refactorings) == 1
      refactoring = List.first(refactorings)
      assert refactoring.type == :extract_module
      assert refactoring.confidence == :high
      assert refactoring.target.module == "MyApp.Helpers"
    end

    test "returns empty list when no matching functions" do
      commit = create_commit()

      new_module_hunk =
        create_diff_hunk(
          file: "lib/my_app/new.ex",
          status: :added,
          additions: [
            {1, "defmodule MyApp.New do"},
            {2, "  def new_function() do"},
            {3, "    :ok"},
            {4, "  end"},
            {5, "end"}
          ]
        )

      refactorings = Refactoring.detect_module_extractions(".", commit, [new_module_hunk])
      assert refactorings == []
    end
  end

  # ===========================================================================
  # Rename Detection Tests
  # ===========================================================================

  describe "detect_function_renames/3" do
    test "detects function rename with same body" do
      commit = create_commit()

      hunk =
        create_diff_hunk(
          file: "lib/my_module.ex",
          deletions: [
            {10, "  def old_name(data, options) do"},
            {11, "    result = process_data(data)"},
            {12, "    format_output(result, options)"},
            {13, "  end"}
          ],
          additions: [
            {10, "  def new_name(data, options) do"},
            {11, "    result = process_data(data)"},
            {12, "    format_output(result, options)"},
            {13, "  end"}
          ]
        )

      refactorings = Refactoring.detect_function_renames(".", commit, [hunk])

      assert length(refactorings) == 1
      refactoring = List.first(refactorings)
      assert refactoring.type == :rename_function
      assert refactoring.source.function == {:old_name, 2}
      assert refactoring.target.function == {:new_name, 2}
      assert refactoring.confidence == :high
    end

    test "does not detect rename for different arities" do
      commit = create_commit()

      hunk =
        create_diff_hunk(
          file: "lib/my_module.ex",
          deletions: [
            {10, "  def func(x) do"},
            {11, "    x"},
            {12, "  end"}
          ],
          additions: [
            {10, "  def func(x, y) do"},
            {11, "    x + y"},
            {12, "  end"}
          ]
        )

      refactorings = Refactoring.detect_function_renames(".", commit, [hunk])
      assert refactorings == []
    end
  end

  describe "detect_module_renames/3" do
    test "detects module rename from file rename" do
      commit = create_commit()

      hunk =
        create_diff_hunk(
          file: "lib/my_app/new_name.ex",
          old_file: "lib/my_app/old_name.ex",
          status: :renamed,
          similarity: 95
        )

      refactorings = Refactoring.detect_module_renames(".", commit, [hunk])

      assert length(refactorings) == 1
      refactoring = List.first(refactorings)
      assert refactoring.type == :rename_module
      assert refactoring.source.file == "lib/my_app/old_name.ex"
      assert refactoring.target.file == "lib/my_app/new_name.ex"
      assert refactoring.confidence == :high
    end

    test "medium confidence for lower similarity" do
      commit = create_commit()

      hunk =
        create_diff_hunk(
          file: "lib/new.ex",
          old_file: "lib/old.ex",
          status: :renamed,
          similarity: 80
        )

      refactorings = Refactoring.detect_module_renames(".", commit, [hunk])

      assert length(refactorings) == 1
      refactoring = List.first(refactorings)
      assert refactoring.confidence == :medium
    end
  end

  # ===========================================================================
  # Inline Detection Tests
  # ===========================================================================

  describe "detect_function_inlines/3" do
    test "detects inlined function" do
      commit = create_commit()

      hunk =
        create_diff_hunk(
          file: "lib/my_module.ex",
          deletions: [
            {10, "  defp helper(x) do"},
            {11, "    x * 2 + 1"},
            {12, "  end"}
          ],
          additions: [
            {20, "    result = x * 2 + 1"}
          ]
        )

      refactorings = Refactoring.detect_function_inlines(".", commit, [hunk])

      assert length(refactorings) >= 1
      refactoring = List.first(refactorings)
      assert refactoring.type == :inline_function
      assert refactoring.source.function == {:helper, 1}
    end
  end

  # ===========================================================================
  # Move Function Detection Tests
  # ===========================================================================

  describe "detect_function_moves/3" do
    test "detects function moved between modules" do
      commit = create_commit()

      source_hunk =
        create_diff_hunk(
          file: "lib/source.ex",
          deletions: [
            {10, "  def shared_func(a, b) do"},
            {11, "    a + b"},
            {12, "  end"}
          ]
        )

      target_hunk =
        create_diff_hunk(
          file: "lib/target.ex",
          additions: [
            {20, "  def shared_func(a, b) do"},
            {21, "    a + b"},
            {22, "  end"}
          ]
        )

      refactorings = Refactoring.detect_function_moves(".", commit, [source_hunk, target_hunk])

      assert length(refactorings) == 1
      refactoring = List.first(refactorings)
      assert refactoring.type == :move_function
      assert refactoring.source.file == "lib/source.ex"
      assert refactoring.target.file == "lib/target.ex"
      assert refactoring.source.function == {:shared_func, 2}
    end

    test "does not detect move within same file" do
      commit = create_commit()

      hunk =
        create_diff_hunk(
          file: "lib/same.ex",
          deletions: [
            {10, "  def func(x) do"},
            {11, "    x"},
            {12, "  end"}
          ],
          additions: [
            {50, "  def func(x) do"},
            {51, "    x"},
            {52, "  end"}
          ]
        )

      refactorings = Refactoring.detect_function_moves(".", commit, [hunk])
      assert refactorings == []
    end
  end

  # ===========================================================================
  # Main Detection Function Tests
  # ===========================================================================

  describe "detect_refactorings/3" do
    @tag :integration
    test "detects refactorings in HEAD commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, refactorings} = Refactoring.detect_refactorings(".", commit)

      assert is_list(refactorings)

      for refactoring <- refactorings do
        assert refactoring.type in Refactoring.refactoring_types()
        assert %Source{} = refactoring.source
        assert %Target{} = refactoring.target
        assert refactoring.confidence in [:high, :medium, :low]
      end
    end

    @tag :integration
    test "can filter by refactoring types" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")

      {:ok, renames} =
        Refactoring.detect_refactorings(".", commit, types: [:rename_function, :rename_module])

      for refactoring <- renames do
        assert refactoring.type in [:rename_function, :rename_module]
      end
    end

    @tag :integration
    test "bang variant works" do
      commit = Commit.extract_commit!(".", "HEAD")
      refactorings = Refactoring.detect_refactorings!(".", commit)

      assert is_list(refactorings)
    end
  end

  describe "detect_refactorings_in_commits/3" do
    @tag :integration
    test "detects refactorings across multiple commits" do
      {:ok, commits} = Commit.extract_commits(".", limit: 3)
      {:ok, results} = Refactoring.detect_refactorings_in_commits(".", commits)

      assert length(results) == length(commits)

      for {commit, refactorings} <- results do
        assert %Commit{} = commit
        assert is_list(refactorings)
      end
    end
  end

  # ===========================================================================
  # Diff Parsing Tests
  # ===========================================================================

  describe "get_commit_diff/2" do
    @tag :integration
    test "extracts diff from commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, hunks} = Refactoring.get_commit_diff(".", commit)

      assert is_list(hunks)

      for hunk <- hunks do
        assert %DiffHunk{} = hunk
        assert is_binary(hunk.file)
        assert hunk.status in [:added, :deleted, :modified, :renamed]
      end
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles empty diff hunks" do
      commit = create_commit()
      refactorings = Refactoring.detect_function_extractions(".", commit, [])
      assert refactorings == []
    end

    test "handles hunk with no elixir files" do
      commit = create_commit()

      hunks = [
        create_diff_hunk(file: "package.json", additions: [{1, "{}"}]),
        create_diff_hunk(file: "README.md", additions: [{1, "# Title"}])
      ]

      refactorings = Refactoring.detect_function_extractions(".", commit, hunks)
      assert refactorings == []
    end

    test "handles nil file in hunk" do
      commit = create_commit()
      hunk = create_diff_hunk(file: nil)

      refactorings = Refactoring.detect_function_extractions(".", commit, [hunk])
      assert refactorings == []
    end
  end
end
