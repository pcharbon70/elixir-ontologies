defmodule ElixirOntologies.Analyzer.ProjectTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.Project
  alias ElixirOntologies.Analyzer.Project.Project, as: ProjectStruct

  doctest ElixirOntologies.Analyzer.Project

  # ============================================================================
  # Project Detection Tests
  # ============================================================================

  describe "detect/1" do
    test "detects Mix project from current directory" do
      {:ok, project} = Project.detect(".")
      assert %ProjectStruct{} = project
      assert is_atom(project.name)
      assert is_binary(project.path)
      assert String.ends_with?(project.mix_file, "mix.exs")
    end

    test "detects Mix project from subdirectory" do
      {:ok, project} = Project.detect("lib")
      assert %ProjectStruct{} = project
      assert is_atom(project.name)
      assert File.dir?(project.path)
    end

    test "returns error for non-Mix directory" do
      assert {:error, :not_found} = Project.detect("/tmp")
    end

    test "returns error for non-existent path" do
      assert {:error, :invalid_path} = Project.detect("/nonexistent/path")
    end
  end

  describe "detect!/1" do
    test "returns project for valid Mix project" do
      project = Project.detect!(".")
      assert %ProjectStruct{} = project
      assert is_atom(project.name)
    end

    test "raises for non-Mix directory" do
      assert_raise RuntimeError, ~r/Failed to detect Mix project/, fn ->
        Project.detect!("/tmp")
      end
    end
  end

  describe "mix_project?/1" do
    test "returns true for Mix project" do
      assert Project.mix_project?(".")
    end

    test "returns false for non-Mix directory" do
      refute Project.mix_project?("/tmp")
    end
  end

  # ============================================================================
  # Find Mix File Tests
  # ============================================================================

  describe "find_mix_file/1" do
    test "finds mix.exs in current directory" do
      {:ok, mix_file} = Project.find_mix_file(".")
      assert String.ends_with?(mix_file, "mix.exs")
      assert File.regular?(mix_file)
    end

    test "finds mix.exs from subdirectory" do
      {:ok, mix_file} = Project.find_mix_file("lib")
      assert String.ends_with?(mix_file, "mix.exs")
    end

    test "returns error for directory without mix.exs" do
      assert {:error, :not_found} = Project.find_mix_file("/tmp")
    end
  end

  # ============================================================================
  # Metadata Extraction Tests
  # ============================================================================

  describe "project metadata extraction" do
    test "extracts project name" do
      {:ok, project} = Project.detect(".")
      assert project.name == :elixir_ontologies
    end

    test "extracts project version" do
      {:ok, project} = Project.detect(".")
      # Version might be nil if it's a module attribute or complex expression
      # Our safe parser only extracts literal values
      assert is_binary(project.version) or is_nil(project.version) or is_atom(project.version)
    end

    test "extracts Elixir version requirement" do
      {:ok, project} = Project.detect(".")
      # Elixir version might be a string like "~> 1.14" or nil
      assert is_binary(project.elixir_version) or is_nil(project.elixir_version)
    end

    test "extracts dependencies list" do
      {:ok, project} = Project.detect(".")
      assert is_list(project.deps)

      # Deps can be atoms or {atom, version} tuples
      Enum.each(project.deps, fn dep ->
        assert is_atom(dep) or match?({atom, _} when is_atom(atom), dep)
      end)
    end

    test "handles project with no dependencies" do
      # Create a temporary minimal project
      tmp_dir = create_temp_project("test_no_deps", [deps: false])

      try do
        {:ok, project} = Project.detect(tmp_dir)
        assert project.deps == []
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "handles project with missing optional fields" do
      # Create a minimal project with only required fields
      tmp_dir = create_minimal_project("test_minimal")

      try do
        {:ok, project} = Project.detect(tmp_dir)
        assert project.name == :test_minimal
        # Version is optional, should be nil or a string
        assert is_nil(project.version) or is_binary(project.version)
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  # ============================================================================
  # Umbrella Project Detection Tests
  # ============================================================================

  describe "umbrella project detection" do
    test "detects current project is not umbrella" do
      {:ok, project} = Project.detect(".")
      refute project.umbrella?
      assert project.apps == []
    end

    test "detects umbrella project structure" do
      # Create a temporary umbrella project
      tmp_dir = create_umbrella_project("test_umbrella")

      try do
        {:ok, project} = Project.detect(tmp_dir)
        assert project.umbrella?
        assert length(project.apps) > 0

        # Verify apps are directories with mix.exs
        Enum.each(project.apps, fn app_path ->
          assert File.dir?(app_path)
          assert File.regular?(Path.join(app_path, "mix.exs"))
        end)
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  # ============================================================================
  # Source Directories Tests
  # ============================================================================

  describe "source directories" do
    test "finds lib/ and test/ directories for regular project" do
      {:ok, project} = Project.detect(".")
      assert is_list(project.source_dirs)

      # Current project should have lib/
      lib_dir = Enum.find(project.source_dirs, &String.ends_with?(&1, "/lib"))
      assert lib_dir
      assert File.dir?(lib_dir)
    end

    test "finds app directories for umbrella project" do
      tmp_dir = create_umbrella_project("test_umbrella_dirs")

      try do
        {:ok, project} = Project.detect(tmp_dir)
        assert project.umbrella?

        # Should include app source directories
        app_dirs = Enum.filter(project.source_dirs, &String.contains?(&1, "/apps/"))
        assert length(app_dirs) > 0
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "only includes directories that exist" do
      {:ok, project} = Project.detect(".")

      # All source directories should actually exist
      Enum.each(project.source_dirs, fn dir ->
        assert File.dir?(dir), "Expected #{dir} to be a directory"
      end)
    end
  end

  # ============================================================================
  # Edge Cases and Error Handling Tests
  # ============================================================================

  describe "edge cases" do
    test "handles invalid mix.exs syntax" do
      tmp_dir = create_invalid_mix_project("test_invalid")

      try do
        result = Project.detect(tmp_dir)
        # Should return error, not crash
        assert {:error, _reason} = result
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "handles mix.exs with no project function" do
      tmp_dir = create_no_project_function("test_no_project")

      try do
        result = Project.detect(tmp_dir)
        assert {:error, :no_project_function} = result
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "handles mix.exs with no app name" do
      tmp_dir = create_no_app_name("test_no_app")

      try do
        result = Project.detect(tmp_dir)
        assert {:error, :no_app_name} = result
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "integration" do
    test "full detection on current project" do
      {:ok, project} = Project.detect(".")

      # Verify all fields are populated correctly
      assert project.name == :elixir_ontologies
      assert is_binary(project.path)
      assert is_binary(project.mix_file)
      assert is_boolean(project.umbrella?)
      assert is_list(project.apps)
      assert is_list(project.deps)
      assert is_list(project.source_dirs)
      assert is_map(project.metadata)

      # Verify path is absolute
      assert project.path == Path.expand(project.path)

      # Verify mix_file points to actual file
      assert File.regular?(project.mix_file)
    end

    test "detect! variant works correctly" do
      project = Project.detect!(".")
      assert %ProjectStruct{} = project
      assert project.name == :elixir_ontologies
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_temp_project(name, opts) do
    tmp_dir = Path.join(System.tmp_dir!(), "project_test_#{name}_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    deps_clause =
      if Keyword.get(opts, :deps, true) do
        """
        defp deps do
          [
            {:ex_doc, "~> 0.29", only: :dev, runtime: false}
          ]
        end
        """
      else
        """
        defp deps, do: []
        """
      end

    mix_content = """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{name},
          version: "0.1.0",
          elixir: "~> 1.14",
          deps: deps()
        ]
      end

      #{deps_clause}
    end
    """

    File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)
    File.mkdir_p!(Path.join(tmp_dir, "lib"))
    File.mkdir_p!(Path.join(tmp_dir, "test"))

    tmp_dir
  end

  defp create_minimal_project(name) do
    tmp_dir = Path.join(System.tmp_dir!(), "project_test_#{name}_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    # Minimal mix.exs with only app name
    mix_content = """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{name}
        ]
      end
    end
    """

    File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)
    File.mkdir_p!(Path.join(tmp_dir, "lib"))

    tmp_dir
  end

  defp create_umbrella_project(name) do
    tmp_dir = Path.join(System.tmp_dir!(), "project_test_#{name}_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    # Create umbrella mix.exs
    mix_content = """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{name},
          apps_path: "apps",
          version: "0.1.0",
          deps: deps()
        ]
      end

      defp deps, do: []
    end
    """

    File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)

    # Create apps directory with two child apps
    apps_dir = Path.join(tmp_dir, "apps")
    File.mkdir_p!(apps_dir)

    # Create first child app
    app1_dir = Path.join(apps_dir, "app1")
    File.mkdir_p!(app1_dir)
    File.mkdir_p!(Path.join(app1_dir, "lib"))

    app1_mix = """
    defmodule App1.MixProject do
      use Mix.Project
      def project, do: [app: :app1, version: "0.1.0"]
    end
    """

    File.write!(Path.join(app1_dir, "mix.exs"), app1_mix)

    # Create second child app
    app2_dir = Path.join(apps_dir, "app2")
    File.mkdir_p!(app2_dir)
    File.mkdir_p!(Path.join(app2_dir, "lib"))
    File.mkdir_p!(Path.join(app2_dir, "test"))

    app2_mix = """
    defmodule App2.MixProject do
      use Mix.Project
      def project, do: [app: :app2, version: "0.1.0"]
    end
    """

    File.write!(Path.join(app2_dir, "mix.exs"), app2_mix)

    tmp_dir
  end

  defp create_invalid_mix_project(name) do
    tmp_dir = Path.join(System.tmp_dir!(), "project_test_#{name}_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    # Invalid Elixir syntax
    mix_content = """
    defmodule InvalidSyntax do
      this is not valid elixir code!
    end
    """

    File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)

    tmp_dir
  end

  defp create_no_project_function(name) do
    tmp_dir = Path.join(System.tmp_dir!(), "project_test_#{name}_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    # Valid Elixir but no project function
    mix_content = """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project

      # Missing def project function!
    end
    """

    File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)

    tmp_dir
  end

  defp create_no_app_name(name) do
    tmp_dir = Path.join(System.tmp_dir!(), "project_test_#{name}_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    # Valid project function but missing :app key
    mix_content = """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project

      def project do
        [
          version: "0.1.0"
        ]
      end
    end
    """

    File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)

    tmp_dir
  end
end
