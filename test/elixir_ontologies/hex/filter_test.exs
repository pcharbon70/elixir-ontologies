defmodule ElixirOntologies.Hex.FilterTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.Filter
  alias ElixirOntologies.Hex.Api.Package

  # ===========================================================================
  # Metadata-Based Filtering Tests
  # ===========================================================================

  describe "likely_elixir_package?/1" do
    test "returns true for package with Elixir name pattern" do
      package = %Package{name: "ex_doc", meta: %{}}
      assert Filter.likely_elixir_package?(package) == true

      package = %Package{name: "phoenix_live_view", meta: %{}}
      assert Filter.likely_elixir_package?(package) == true

      package = %Package{name: "ecto_sql", meta: %{}}
      assert Filter.likely_elixir_package?(package) == true
    end

    test "returns true for package with Elixir GitHub link" do
      package = %Package{
        name: "some_lib",
        meta: %{
          "links" => %{
            "GitHub" => "https://github.com/elixir-lang/elixir"
          }
        }
      }

      assert Filter.likely_elixir_package?(package) == true
    end

    test "returns true for package with Elixir in description" do
      package = %Package{
        name: "some_lib",
        meta: %{
          "description" => "An Elixir library for doing things"
        }
      }

      assert Filter.likely_elixir_package?(package) == true
    end

    test "returns false for known Erlang packages" do
      for name <- ["cowboy", "cowlib", "ranch", "jsx", "jiffy"] do
        package = %Package{name: name, meta: %{}}
        assert Filter.likely_elixir_package?(package) == false
      end
    end

    test "returns false for Erlang name patterns" do
      package = %Package{name: "erl_term", meta: %{}}
      assert Filter.likely_elixir_package?(package) == false

      package = %Package{name: "rebar3_hex", meta: %{}}
      assert Filter.likely_elixir_package?(package) == false
    end

    test "returns :unknown for ambiguous packages" do
      package = %Package{name: "httpoison", meta: %{}}
      assert Filter.likely_elixir_package?(package) == :unknown

      package = %Package{name: "jason", meta: %{}}
      assert Filter.likely_elixir_package?(package) == :unknown
    end

    test "handles nil meta gracefully" do
      package = %Package{name: "test", meta: nil}
      # Should not crash, returns based on name only
      result = Filter.likely_elixir_package?(package)
      assert result in [true, false, :unknown]
    end
  end

  # ===========================================================================
  # Source-Based Filtering Tests
  # ===========================================================================

  describe "has_elixir_source?/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "filter_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "returns true when .ex files exist", %{test_dir: test_dir} do
      lib_dir = Path.join(test_dir, "lib")
      File.mkdir_p!(lib_dir)
      File.write!(Path.join(lib_dir, "my_module.ex"), "defmodule MyModule do end")

      assert Filter.has_elixir_source?(test_dir) == true
    end

    test "returns false when no .ex files exist", %{test_dir: test_dir} do
      src_dir = Path.join(test_dir, "src")
      File.mkdir_p!(src_dir)
      File.write!(Path.join(src_dir, "my_module.erl"), "-module(my_module).")

      assert Filter.has_elixir_source?(test_dir) == false
    end

    test "finds nested .ex files", %{test_dir: test_dir} do
      nested_dir = Path.join([test_dir, "lib", "my_app", "controllers"])
      File.mkdir_p!(nested_dir)
      File.write!(Path.join(nested_dir, "user_controller.ex"), "defmodule UserController do end")

      assert Filter.has_elixir_source?(test_dir) == true
    end
  end

  describe "has_mix_project?/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "mix_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "returns true when mix.exs exists", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "mix.exs"), "defmodule MyApp.MixProject do end")

      assert Filter.has_mix_project?(test_dir) == true
    end

    test "returns false when mix.exs does not exist", %{test_dir: test_dir} do
      assert Filter.has_mix_project?(test_dir) == false
    end
  end

  describe "has_erlang_source?/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "erlang_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "returns true when .erl files exist", %{test_dir: test_dir} do
      src_dir = Path.join(test_dir, "src")
      File.mkdir_p!(src_dir)
      File.write!(Path.join(src_dir, "my_module.erl"), "-module(my_module).")

      assert Filter.has_erlang_source?(test_dir) == true
    end

    test "returns false when no .erl files exist", %{test_dir: test_dir} do
      lib_dir = Path.join(test_dir, "lib")
      File.mkdir_p!(lib_dir)
      File.write!(Path.join(lib_dir, "my_module.ex"), "defmodule MyModule do end")

      assert Filter.has_erlang_source?(test_dir) == false
    end
  end

  describe "erlang_only?/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "erlang_only_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "returns true for Erlang-only package", %{test_dir: test_dir} do
      src_dir = Path.join(test_dir, "src")
      File.mkdir_p!(src_dir)
      File.write!(Path.join(src_dir, "my_module.erl"), "-module(my_module).")

      assert Filter.erlang_only?(test_dir) == true
    end

    test "returns false for Elixir package", %{test_dir: test_dir} do
      lib_dir = Path.join(test_dir, "lib")
      File.mkdir_p!(lib_dir)
      File.write!(Path.join(lib_dir, "my_module.ex"), "defmodule MyModule do end")

      assert Filter.erlang_only?(test_dir) == false
    end

    test "returns false for mixed package", %{test_dir: test_dir} do
      lib_dir = Path.join(test_dir, "lib")
      src_dir = Path.join(test_dir, "src")
      File.mkdir_p!(lib_dir)
      File.mkdir_p!(src_dir)
      File.write!(Path.join(lib_dir, "my_module.ex"), "defmodule MyModule do end")
      File.write!(Path.join(src_dir, "nif.erl"), "-module(nif).")

      assert Filter.erlang_only?(test_dir) == false
    end
  end

  # ===========================================================================
  # Stream Filtering Tests
  # ===========================================================================

  describe "filter_likely_elixir/1" do
    test "passes through Elixir packages" do
      packages = [
        %Package{name: "phoenix", meta: %{}},
        %Package{name: "ex_doc", meta: %{}}
      ]

      result = packages |> Filter.filter_likely_elixir() |> Enum.to_list()

      assert length(result) == 2
    end

    test "rejects known Erlang packages" do
      packages = [
        %Package{name: "phoenix", meta: %{}},
        %Package{name: "cowboy", meta: %{}},
        %Package{name: "ex_doc", meta: %{}}
      ]

      result = packages |> Filter.filter_likely_elixir() |> Enum.to_list()

      # phoenix and ex_doc should pass, cowboy should be rejected
      assert length(result) == 2
      names = Enum.map(result, & &1.name)
      assert "phoenix" in names
      assert "ex_doc" in names
      refute "cowboy" in names
    end

    test "passes through unknown packages for later verification" do
      packages = [
        %Package{name: "jason", meta: %{}},
        %Package{name: "httpoison", meta: %{}}
      ]

      result = packages |> Filter.filter_likely_elixir() |> Enum.to_list()

      # Unknown packages should pass through
      assert length(result) == 2
    end

    test "works with streams" do
      stream =
        Stream.iterate(1, &(&1 + 1))
        |> Stream.take(3)
        |> Stream.map(fn i -> %Package{name: "pkg_#{i}", meta: %{}} end)

      result = stream |> Filter.filter_likely_elixir() |> Enum.to_list()

      assert length(result) == 3
    end
  end

  # ===========================================================================
  # Utility Tests
  # ===========================================================================

  describe "known_erlang_packages/0" do
    test "returns list of known Erlang packages" do
      packages = Filter.known_erlang_packages()

      assert is_list(packages)
      assert "cowboy" in packages
      assert "ranch" in packages
    end
  end
end
