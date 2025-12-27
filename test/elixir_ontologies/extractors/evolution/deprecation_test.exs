defmodule ElixirOntologies.Extractors.Evolution.DeprecationTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Evolution.Deprecation

  alias ElixirOntologies.Extractors.Evolution.Deprecation.{
    DeprecationEvent,
    RemovalEvent,
    Replacement
  }

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

  # ===========================================================================
  # Element Types Tests
  # ===========================================================================

  describe "element_types/0" do
    test "returns all element types" do
      types = Deprecation.element_types()

      assert :function in types
      assert :module in types
      assert :macro in types
      assert :callback in types
      assert :type in types
    end
  end

  # ===========================================================================
  # Struct Tests
  # ===========================================================================

  describe "DeprecationEvent struct" do
    test "has default values" do
      event = %DeprecationEvent{}

      assert event.commit == nil
      assert event.file == nil
      assert event.line == nil
    end
  end

  describe "RemovalEvent struct" do
    test "has default values" do
      event = %RemovalEvent{}

      assert event.commit == nil
      assert event.file == nil
    end
  end

  describe "Replacement struct" do
    test "has default values" do
      replacement = %Replacement{}

      assert replacement.text == nil
      assert replacement.function == nil
      assert replacement.module == nil
    end
  end

  describe "Deprecation struct" do
    test "requires element_type, element_name, and message" do
      deprecation = %Deprecation{
        element_type: :function,
        element_name: "old_func",
        message: "Use new_func/1 instead"
      }

      assert deprecation.element_type == :function
      assert deprecation.element_name == "old_func"
      assert deprecation.message == "Use new_func/1 instead"
      assert deprecation.metadata == %{}
    end
  end

  # ===========================================================================
  # Replacement Parsing Tests
  # ===========================================================================

  describe "parse_replacement/1" do
    test "returns nil for nil input" do
      assert Deprecation.parse_replacement(nil) == nil
    end

    test "returns nil for empty string" do
      assert Deprecation.parse_replacement("") == nil
    end

    test "parses function/arity reference" do
      result = Deprecation.parse_replacement("Use new_func/2 instead")

      assert %Replacement{} = result
      assert result.text == "Use new_func/2 instead"
      assert result.function == {:new_func, 2}
      assert result.module == nil
    end

    test "parses Module.function/arity reference" do
      result = Deprecation.parse_replacement("See MyModule.other_func/1 for details")

      assert %Replacement{} = result
      assert result.text == "See MyModule.other_func/1 for details"
      assert result.function == {:other_func, 1}
      assert result.module == "MyModule"
    end

    test "parses nested module reference" do
      result = Deprecation.parse_replacement("Use My.Nested.Module.func/3")

      assert %Replacement{} = result
      assert result.module == "My.Nested.Module"
      assert result.function == {:func, 3}
    end

    test "parses Module.function without arity" do
      result = Deprecation.parse_replacement("Replaced by NewModule.new_func")

      assert %Replacement{} = result
      assert result.module == "NewModule"
      assert result.function == {:new_func, 0}
    end

    test "returns text only when no function reference found" do
      result = Deprecation.parse_replacement("This is deprecated")

      assert %Replacement{} = result
      assert result.text == "This is deprecated"
      assert result.function == nil
      assert result.module == nil
    end

    test "handles bang functions" do
      result = Deprecation.parse_replacement("Use new_func!/1")

      assert result.function == {:new_func!, 1}
    end

    test "handles question mark functions" do
      result = Deprecation.parse_replacement("Use valid?/1")

      assert result.function == {:valid?, 1}
    end
  end

  # ===========================================================================
  # Query Function Tests
  # ===========================================================================

  describe "has_replacement?/1" do
    test "returns true when replacement has function" do
      deprecation = %Deprecation{
        element_type: :function,
        element_name: "old",
        message: "test",
        replacement: %Replacement{text: "Use new/1", function: {:new, 1}}
      }

      assert Deprecation.has_replacement?(deprecation)
    end

    test "returns true when replacement has module" do
      deprecation = %Deprecation{
        element_type: :function,
        element_name: "old",
        message: "test",
        replacement: %Replacement{text: "See NewModule", module: "NewModule"}
      }

      assert Deprecation.has_replacement?(deprecation)
    end

    test "returns false when replacement is nil" do
      deprecation = %Deprecation{
        element_type: :function,
        element_name: "old",
        message: "test",
        replacement: nil
      }

      refute Deprecation.has_replacement?(deprecation)
    end

    test "returns false when replacement has only text" do
      deprecation = %Deprecation{
        element_type: :function,
        element_name: "old",
        message: "test",
        replacement: %Replacement{text: "Deprecated"}
      }

      refute Deprecation.has_replacement?(deprecation)
    end
  end

  describe "removed?/1" do
    test "returns true when removed_in is set" do
      deprecation = %Deprecation{
        element_type: :function,
        element_name: "old",
        message: "test",
        removed_in: %RemovalEvent{file: "lib/test.ex"}
      }

      assert Deprecation.removed?(deprecation)
    end

    test "returns false when removed_in is nil" do
      deprecation = %Deprecation{
        element_type: :function,
        element_name: "old",
        message: "test",
        removed_in: nil
      }

      refute Deprecation.removed?(deprecation)
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "detect_deprecations/2" do
    @tag :integration
    test "detects deprecations in HEAD commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, deprecations} = Deprecation.detect_deprecations(".", commit)

      assert is_list(deprecations)

      for deprecation <- deprecations do
        assert deprecation.element_type in Deprecation.element_types()
        assert is_binary(deprecation.element_name)
        assert is_binary(deprecation.message)
        assert %DeprecationEvent{} = deprecation.deprecated_in
      end
    end

    @tag :integration
    test "bang variant works" do
      commit = Commit.extract_commit!(".", "HEAD")
      deprecations = Deprecation.detect_deprecations!(".", commit)

      assert is_list(deprecations)
    end
  end

  describe "detect_removals/2" do
    @tag :integration
    test "detects removals in HEAD commit" do
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, removals} = Deprecation.detect_removals(".", commit)

      assert is_list(removals)

      for removal <- removals do
        assert removal.element_type in Deprecation.element_types()
        assert %RemovalEvent{} = removal.removed_in
      end
    end
  end

  describe "find_deprecation_commits/2" do
    @tag :integration
    test "finds commits with deprecations" do
      {:ok, commits} = Deprecation.find_deprecation_commits(".", limit: 5)

      assert is_list(commits)

      for commit <- commits do
        assert %Commit{} = commit
      end
    end
  end

  describe "track_deprecations/3" do
    @tag :integration
    test "tracks deprecations for a file" do
      # Use a file that exists in the repo
      {:ok, deprecations} =
        Deprecation.track_deprecations(".", "lib/elixir_ontologies.ex", limit: 10)

      assert is_list(deprecations)
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles various deprecation message formats" do
      messages = [
        {"Use new/1 instead", {:new, 1}},
        {"See Module.func/2", {:func, 2}},
        {"Replaced by other/0", {:other, 0}},
        {"This will be removed", nil}
      ]

      for {message, expected_func} <- messages do
        result = Deprecation.parse_replacement(message)

        if expected_func do
          assert result.function == expected_func,
                 "Expected #{inspect(expected_func)} for: #{message}"
        else
          assert result.function == nil, "Expected nil function for: #{message}"
        end
      end
    end

    test "handles underscore in function names" do
      result = Deprecation.parse_replacement("Use my_new_func/1")
      assert result.function == {:my_new_func, 1}
    end

    test "handles zero arity functions" do
      result = Deprecation.parse_replacement("Use get_value/0")
      assert result.function == {:get_value, 0}
    end

    test "handles high arity functions" do
      result = Deprecation.parse_replacement("Use complex_func/10")
      assert result.function == {:complex_func, 10}
    end
  end
end
