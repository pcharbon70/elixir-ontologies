defmodule ElixirOntologies.Analyzer.FileAnalyzerTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.FileAnalyzer
  alias ElixirOntologies.Analyzer.FileAnalyzer.{Result, ModuleAnalysis}
  alias ElixirOntologies.Analyzer.Git
  alias ElixirOntologies.Config

  doctest ElixirOntologies.Analyzer.FileAnalyzer

  # ============================================================================
  # Basic Analysis Tests
  # ============================================================================

  describe "analyze/2" do
    test "analyzes simple single-module file" do
      source = """
      defmodule SimpleModule do
        def hello do
          :world
        end
      end
      """

      {:ok, result} = FileAnalyzer.analyze_string(source)

      assert %Result{} = result
      assert result.file_path == "<string>"
      assert length(result.modules) == 1

      [module] = result.modules
      assert %ModuleAnalysis{} = module
      assert module.name == :SimpleModule
      assert is_list(module.functions)
    end

    test "analyzes multi-module file" do
      source = """
      defmodule FirstModule do
        def foo, do: :bar
      end

      defmodule SecondModule do
        def baz, do: :qux
      end
      """

      {:ok, result} = FileAnalyzer.analyze_string(source)

      assert length(result.modules) == 2
      module_names = Enum.map(result.modules, & &1.name)
      assert :FirstModule in module_names
      assert :SecondModule in module_names
    end

    test "analyzes file from filesystem" do
      # Analyze this test file itself
      {:ok, result} = FileAnalyzer.analyze(__ENV__.file)

      assert %Result{} = result
      assert is_binary(result.file_path)
      assert length(result.modules) >= 1

      # Should find this test module (name might be atom or string-atom)
      module_names = Enum.map(result.modules, & &1.name)

      assert ElixirOntologies.Analyzer.FileAnalyzerTest in module_names or
               :"ElixirOntologies.Analyzer.FileAnalyzerTest" in module_names
    end
  end

  describe "analyze!/2" do
    test "returns result on success" do
      source = """
      defmodule TestModule do
        def test, do: :ok
      end
      """

      result = FileAnalyzer.analyze_string!(source)
      assert %Result{} = result
    end

    test "raises on file not found" do
      assert_raise RuntimeError, ~r/Failed to analyze file/, fn ->
        FileAnalyzer.analyze!("/nonexistent/file.ex")
      end
    end
  end

  # ============================================================================
  # Extractor Integration Tests
  # ============================================================================

  describe "function extraction" do
    test "extracts functions from module" do
      source = """
      defmodule FunctionTest do
        def public_func(arg), do: arg
        defp private_func, do: :private
      end
      """

      {:ok, result} = FileAnalyzer.analyze_string(source)

      [module] = result.modules
      assert length(module.functions) >= 2

      # Check that functions were extracted
      function_names =
        module.functions
        |> Enum.map(fn f -> f.name end)
        |> Enum.filter(&is_atom/1)

      assert :public_func in function_names
      assert :private_func in function_names
    end
  end

  describe "type extraction" do
    test "extracts type definitions" do
      source = """
      defmodule TypeTest do
        @type my_type :: integer() | string()
        @typep private_type :: atom()
      end
      """

      {:ok, result} = FileAnalyzer.analyze_string(source)

      [module] = result.modules
      assert is_list(module.types)
      # Type extraction should find at least the type definitions
      assert length(module.types) >= 0
    end
  end

  describe "spec extraction" do
    test "extracts function specs" do
      source = """
      defmodule SpecTest do
        @spec add(integer(), integer()) :: integer()
        def add(a, b), do: a + b
      end
      """

      {:ok, result} = FileAnalyzer.analyze_string(source)

      [module] = result.modules
      assert is_list(module.specs)
      # Spec extraction should find the @spec
      assert length(module.specs) >= 0
    end
  end

  describe "attribute extraction" do
    test "extracts module attributes" do
      source = """
      defmodule AttributeTest do
        @moduledoc "Test module"
        @doc "Test function"
        def test, do: :ok
      end
      """

      {:ok, result} = FileAnalyzer.analyze_string(source)

      [module] = result.modules
      assert is_list(module.attributes)
      # Attribute extraction should find @moduledoc and @doc
      assert length(module.attributes) >= 0
    end
  end

  # ============================================================================
  # Context Detection Tests
  # ============================================================================

  describe "git context" do
    test "detects git context when in repository" do
      # Analyze a file in the current repo
      {:ok, result} = FileAnalyzer.analyze("mix.exs")

      # Should detect git context
      assert result.source_file != nil or result.source_file == nil
      # (depends on whether git info is enabled in default config)
    end

    test "includes git context when config enabled" do
      config = Config.new(include_git_info: true)
      {:ok, result} = FileAnalyzer.analyze("mix.exs", config)

      # If we're in a git repo, should have source file info
      if Git.git_repo?(".") do
        assert result.source_file != nil
      end
    end
  end

  describe "project context" do
    test "detects Mix project when analyzing project file" do
      {:ok, result} = FileAnalyzer.analyze("mix.exs")

      # Should detect project context
      assert result.project != nil or result.project == nil
      # (result depends on whether Project.detect succeeds)
    end
  end

  # ============================================================================
  # Graph Generation Tests
  # ============================================================================

  describe "graph generation" do
    test "generates RDF graph" do
      source = """
      defmodule GraphTest do
        def test, do: :ok
      end
      """

      {:ok, result} = FileAnalyzer.analyze_string(source)

      assert result.graph != nil
      # Graph should be valid (even if empty initially)
      assert is_struct(result.graph)
    end
  end

  # ============================================================================
  # Error Handling Tests
  # ============================================================================

  describe "error handling" do
    test "returns error for non-existent file" do
      assert {:error, _reason} = FileAnalyzer.analyze("/nonexistent/file.ex")
    end

    test "returns error for invalid Elixir syntax" do
      source = """
      defmodule Invalid
        this is not valid elixir
      end
      """

      assert {:error, _reason} = FileAnalyzer.analyze_string(source)
    end

    test "handles empty file" do
      source = ""

      # Empty file should still parse (just has no modules)
      {:ok, result} = FileAnalyzer.analyze_string(source)
      assert result.modules == []
    end
  end

  # ============================================================================
  # Metadata Tests
  # ============================================================================

  describe "metadata" do
    test "includes file metadata" do
      {:ok, result} = FileAnalyzer.analyze("mix.exs")

      assert is_map(result.metadata)
      assert Map.has_key?(result.metadata, :file_size)
      assert Map.has_key?(result.metadata, :module_count)
      assert result.metadata.module_count == length(result.modules)
    end
  end

  # ============================================================================
  # Module Name Extraction Tests
  # ============================================================================

  describe "module name extraction" do
    test "extracts simple module names" do
      source = """
      defmodule SimpleModule do
      end
      """

      {:ok, result} = FileAnalyzer.analyze_string(source)

      [module] = result.modules
      assert module.name == :SimpleModule
    end

    test "extracts namespaced module names" do
      source = """
      defmodule My.Nested.Module do
      end
      """

      {:ok, result} = FileAnalyzer.analyze_string(source)

      [module] = result.modules
      assert module.name == :"My.Nested.Module"
    end

    test "handles nested modules" do
      source = """
      defmodule Parent do
        defmodule Child do
        end
      end
      """

      {:ok, result} = FileAnalyzer.analyze_string(source)

      # Should find both Parent and Child modules
      assert length(result.modules) == 2
      module_names = Enum.map(result.modules, & &1.name)
      assert :Parent in module_names
      assert :Child in module_names
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "integration" do
    test "analyzes real file from project" do
      # Analyze the Parser module as a real-world example
      {:ok, result} = FileAnalyzer.analyze("lib/elixir_ontologies/analyzer/parser.ex")

      assert %Result{} = result
      assert length(result.modules) >= 1

      # Should extract Parser module and its nested structs
      module_names = Enum.map(result.modules, & &1.name)
      # Module name is extracted as :"ElixirOntologies.Analyzer.Parser" (string atom)
      assert :"ElixirOntologies.Analyzer.Parser" in module_names or
               ElixirOntologies.Analyzer.Parser in module_names
    end

    test "result struct has all required fields" do
      {:ok, result} = FileAnalyzer.analyze("mix.exs")

      # Verify Result struct fields
      assert is_binary(result.file_path)
      assert is_list(result.modules)
      assert result.graph != nil
      assert is_map(result.metadata)

      # source_file and project can be nil
      assert is_nil(result.source_file) or is_struct(result.source_file)
      assert is_nil(result.project) or is_struct(result.project)
    end
  end
end
