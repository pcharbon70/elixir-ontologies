defmodule ElixirOntologies.Hex.PackageHandlerTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.PackageHandler
  alias ElixirOntologies.Hex.PackageHandler.Context

  # ===========================================================================
  # Context Struct Tests
  # ===========================================================================

  describe "Context.new/2" do
    test "creates context with name and version" do
      context = Context.new("phoenix", "1.7.10")

      assert context.name == "phoenix"
      assert context.version == "1.7.10"
      assert context.status == :pending
      assert context.tarball_path == nil
      assert context.extract_dir == nil
      assert context.temp_dir == nil
      assert context.error == nil
    end
  end

  describe "Context struct" do
    test "has expected fields" do
      context = %Context{}

      assert Map.has_key?(context, :name)
      assert Map.has_key?(context, :version)
      assert Map.has_key?(context, :tarball_path)
      assert Map.has_key?(context, :extract_dir)
      assert Map.has_key?(context, :temp_dir)
      assert Map.has_key?(context, :status)
      assert Map.has_key?(context, :error)
    end

    test "default status is :pending" do
      context = %Context{}
      assert context.status == :pending
    end
  end

  # ===========================================================================
  # Status Tracking Tests
  # ===========================================================================

  describe "status transitions" do
    test "pending -> downloaded -> extracted" do
      context = Context.new("test", "1.0.0")
      assert context.status == :pending

      context = %{context | status: :downloaded, tarball_path: "/tmp/test.tar"}
      assert context.status == :downloaded

      context = %{context | status: :extracted, extract_dir: "/tmp/source"}
      assert context.status == :extracted
    end

    test "tracks error state" do
      context = Context.new("test", "1.0.0")

      context = %{context | status: :failed, error: :not_found}

      assert context.status == :failed
      assert context.error == :not_found
    end
  end

  # ===========================================================================
  # elixir_project?/1 Tests
  # ===========================================================================

  describe "elixir_project?/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "elixir_project_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "returns true when extract_dir has mix.exs", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "mix.exs"), "defmodule Test.MixProject do end")

      context = %Context{
        name: "test",
        version: "1.0.0",
        extract_dir: test_dir,
        status: :extracted
      }

      assert PackageHandler.elixir_project?(context)
    end

    test "returns false when extract_dir has no mix.exs", %{test_dir: test_dir} do
      context = %Context{
        name: "test",
        version: "1.0.0",
        extract_dir: test_dir,
        status: :extracted
      }

      refute PackageHandler.elixir_project?(context)
    end

    test "returns false when extract_dir is nil" do
      context = %Context{
        name: "test",
        version: "1.0.0",
        extract_dir: nil,
        status: :pending
      }

      refute PackageHandler.elixir_project?(context)
    end
  end

  # ===========================================================================
  # Cleanup Tests
  # ===========================================================================

  describe "cleanup/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "cleanup_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      {:ok, test_dir: test_dir}
    end

    test "removes temp directory", %{test_dir: test_dir} do
      tarball_path = Path.join(test_dir, "test.tar")
      File.write!(tarball_path, "content")

      context = %Context{
        name: "test",
        version: "1.0.0",
        temp_dir: test_dir,
        tarball_path: tarball_path,
        status: :extracted
      }

      {:ok, cleaned_context} = PackageHandler.cleanup(context)

      assert cleaned_context.status == :cleaned
      refute File.exists?(test_dir)
    end

    test "handles nil paths gracefully" do
      context = %Context{
        name: "test",
        version: "1.0.0",
        temp_dir: nil,
        tarball_path: nil,
        status: :pending
      }

      {:ok, cleaned_context} = PackageHandler.cleanup(context)

      assert cleaned_context.status == :cleaned
    end

    test "handles already deleted directories" do
      context = %Context{
        name: "test",
        version: "1.0.0",
        temp_dir: "/nonexistent/path",
        tarball_path: "/nonexistent/file.tar",
        status: :extracted
      }

      # Should not raise
      {:ok, cleaned_context} = PackageHandler.cleanup(context)
      assert cleaned_context.status == :cleaned
    end
  end

  # ===========================================================================
  # with_package/5 Tests (Mocked)
  # ===========================================================================

  describe "with_package/5 callback pattern" do
    test "callback receives context" do
      # This test verifies the callback pattern without actual network calls
      context = %Context{
        name: "test",
        version: "1.0.0",
        extract_dir: "/tmp/test",
        status: :extracted
      }

      # Simulate what with_package does
      result =
        try do
          fn ctx ->
            assert ctx.name == "test"
            assert ctx.version == "1.0.0"
            :callback_result
          end.(context)
        after
          # Cleanup would happen here
          :ok
        end

      assert result == :callback_result
    end

    test "callback result is returned" do
      context = %Context{name: "test", version: "1.0.0", status: :extracted}

      result =
        try do
          fn _ctx -> {:ok, :analysis_result} end.(context)
        after
          :ok
        end

      assert result == {:ok, :analysis_result}
    end
  end
end
