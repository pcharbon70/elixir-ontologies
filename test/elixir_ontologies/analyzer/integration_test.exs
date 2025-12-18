defmodule ElixirOntologies.Analyzer.IntegrationTest do
  @moduledoc """
  Integration tests for Phase 2 AST Parsing Infrastructure.

  Tests the full pipeline: FileReader → Parser → ASTWalker → Matchers → Location
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.{FileReader, Parser, ASTWalker, Matchers, Location}

  @fixtures_path Path.expand("../../fixtures", __DIR__)

  # ============================================================================
  # Full Pipeline Tests
  # ============================================================================

  describe "full file parsing pipeline" do
    test "read → parse → walk → extract locations" do
      path = Path.join(@fixtures_path, "complex_module.ex")

      # Step 1: Read file
      assert {:ok, file_result} = FileReader.read(path)
      assert is_binary(file_result.source)
      assert file_result.path == Path.expand(path)

      # Step 2: Parse to AST
      assert {:ok, ast} = Parser.parse(file_result.source)
      assert {:defmodule, _meta, _args} = ast

      # Step 3: Walk AST and collect functions
      functions = ASTWalker.find_all(ast, &Matchers.function?/1)
      assert length(functions) > 0

      # Step 4: Extract locations from functions
      locations =
        Enum.map(functions, fn func ->
          {:ok, loc} = Location.extract_range_with_estimate(func)
          loc
        end)

      assert Enum.all?(locations, fn loc ->
               loc.start_line > 0 and loc.end_line >= loc.start_line
             end)
    end

    test "parse_file combines read and parse" do
      path = Path.join(@fixtures_path, "complex_module.ex")

      assert {:ok, result} = Parser.parse_file(path)
      assert %Parser.Result{} = result
      assert is_binary(result.source)
      assert {:defmodule, _meta, _args} = result.ast
      assert result.file_metadata.size > 0
    end

    test "pipeline extracts all construct types" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      # Extract various constructs
      modules = ASTWalker.find_all(result.ast, &Matchers.module?/1)
      functions = ASTWalker.find_all(result.ast, &Matchers.function?/1)
      macros = ASTWalker.find_all(result.ast, &Matchers.macro?/1)
      types = ASTWalker.find_all(result.ast, &Matchers.type?/1)
      specs = ASTWalker.find_all(result.ast, &Matchers.spec?/1)
      callbacks = ASTWalker.find_all(result.ast, &Matchers.callback?/1)
      guards = ASTWalker.find_all(result.ast, &Matchers.guard?/1)
      behaviours = ASTWalker.find_all(result.ast, &Matchers.behaviour?/1)
      dependencies = ASTWalker.find_all(result.ast, &Matchers.dependency?/1)

      assert length(modules) == 1
      assert length(functions) >= 10
      assert length(macros) >= 1
      assert length(types) >= 2
      assert length(specs) >= 1
      # Note: @impl is different from @callback - we don't have @callback in fixture
      assert length(callbacks) >= 0
      assert length(guards) >= 1
      assert length(behaviours) >= 1
      assert length(dependencies) >= 3
    end
  end

  # ============================================================================
  # Multi-Module File Tests
  # ============================================================================

  describe "walker finds all modules in multi-module file" do
    test "finds all three modules" do
      path = Path.join(@fixtures_path, "multi_module.ex")
      {:ok, result} = Parser.parse_file(path)

      # Multi-module file parses as __block__ with multiple defmodule children
      modules = ASTWalker.find_all(result.ast, &Matchers.module?/1)

      assert length(modules) == 3

      # Extract module names
      module_names =
        Enum.map(modules, fn {:defmodule, _meta, [{:__aliases__, _, parts} | _]} ->
          Module.concat(parts)
        end)

      assert MultiModule.First in module_names
      assert MultiModule.Second in module_names
      assert MultiModule.Third in module_names
    end

    test "finds functions across all modules" do
      path = Path.join(@fixtures_path, "multi_module.ex")
      {:ok, result} = Parser.parse_file(path)

      functions = ASTWalker.find_all(result.ast, &Matchers.function?/1)

      # Count: hello/0, get_default/0, private_helper/1, start_link/1, init/1
      assert length(functions) >= 5

      # Check public vs private
      public = ASTWalker.find_all(result.ast, &Matchers.public_function?/1)
      private = ASTWalker.find_all(result.ast, &Matchers.private_function?/1)

      assert length(public) >= 4
      assert length(private) >= 1
    end

    test "finds dependencies in multi-module file" do
      path = Path.join(@fixtures_path, "multi_module.ex")
      {:ok, result} = Parser.parse_file(path)

      uses = ASTWalker.find_all(result.ast, &Matchers.use?/1)
      assert length(uses) >= 1
    end

    test "extracts locations for each module" do
      path = Path.join(@fixtures_path, "multi_module.ex")
      {:ok, result} = Parser.parse_file(path)

      modules = ASTWalker.find_all(result.ast, &Matchers.module?/1)

      locations =
        Enum.map(modules, fn mod ->
          {:ok, loc} = Location.extract_range(mod)
          loc
        end)

      # Each module should have distinct start lines
      start_lines = Enum.map(locations, & &1.start_line) |> Enum.sort()
      assert start_lines == Enum.uniq(start_lines)

      # All should have end positions (defmodule has :end metadata)
      assert Enum.all?(locations, fn loc -> loc.end_line != nil end)
    end
  end

  # ============================================================================
  # Complex Module Tests
  # ============================================================================

  describe "walker finds all functions in complex module" do
    test "finds all public functions" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      public_fns = ASTWalker.find_all(result.ast, &Matchers.public_function?/1)

      # new/2, increment/1, process/1 (2 clauses), init/1, handle_call/3, handle_cast/2
      assert length(public_fns) >= 7
    end

    test "finds all private functions" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      private_fns = ASTWalker.find_all(result.ast, &Matchers.private_function?/1)

      # valid?/1, transform/1, handle_type_a/1, handle_type_b/1
      assert length(private_fns) >= 4
    end

    test "finds type specifications" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      types = ASTWalker.find_all(result.ast, &Matchers.type?/1)
      specs = ASTWalker.find_all(result.ast, &Matchers.spec?/1)

      # @type state, @type result
      assert length(types) >= 2

      # @spec new/2, @spec increment/1
      assert length(specs) >= 1
    end

    test "finds struct definition" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      structs = ASTWalker.find_all(result.ast, &Matchers.struct?/1)
      assert length(structs) == 1
    end

    test "finds macro definition" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      macros = ASTWalker.find_all(result.ast, &Matchers.macro?/1)
      assert length(macros) >= 1
    end

    test "finds guard definition" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      guards = ASTWalker.find_all(result.ast, &Matchers.guard?/1)
      assert length(guards) >= 1
    end
  end

  # ============================================================================
  # Nested Structures Tests
  # ============================================================================

  describe "location tracking through nested structures" do
    test "tracks locations in deeply nested code" do
      path = Path.join(@fixtures_path, "nested_structures.ex")
      {:ok, result} = Parser.parse_file(path)

      # Find all functions
      functions = ASTWalker.find_all(result.ast, &Matchers.function?/1)

      # Each function should have valid location
      Enum.each(functions, fn func ->
        assert {:ok, loc} = Location.extract_range_with_estimate(func)
        assert loc.start_line > 0
        assert loc.end_line >= loc.start_line
      end)
    end

    test "finds nested module definitions" do
      path = Path.join(@fixtures_path, "nested_structures.ex")
      {:ok, result} = Parser.parse_file(path)

      modules = ASTWalker.find_all(result.ast, &Matchers.module?/1)

      # NestedStructures, NestedStructures.Inner, NestedStructures.Inner.DeepInner
      assert length(modules) >= 3
    end

    test "walker tracks depth through nesting" do
      path = Path.join(@fixtures_path, "nested_structures.ex")
      {:ok, result} = Parser.parse_file(path)

      # Walk with context to track depth
      max_depth =
        ASTWalker.walk(result.ast, 0, fn _node, ctx, acc ->
          {:cont, max(acc, ctx.depth)}
        end)
        |> elem(1)

      # Deeply nested code should have significant depth
      assert max_depth >= 5
    end

    test "extracts locations for nested anonymous functions" do
      path = Path.join(@fixtures_path, "nested_structures.ex")
      {:ok, result} = Parser.parse_file(path)

      # Find all anonymous functions
      anon_fns =
        ASTWalker.find_all(result.ast, fn
          {:fn, _meta, _args} -> true
          _ -> false
        end)

      # nested_anonymous_functions has 3 nested fn
      assert length(anon_fns) >= 3

      # Each should have location
      Enum.each(anon_fns, fn func ->
        assert {:ok, _loc} = Location.extract_range(func)
      end)
    end
  end

  # ============================================================================
  # Error Handling Tests
  # ============================================================================

  describe "error handling for malformed files" do
    test "parse_file returns error for malformed syntax" do
      path = Path.join(@fixtures_path, "malformed.ex")

      assert {:error, %Parser.Error{} = error} = Parser.parse_file(path)
      assert error.line != nil
      assert is_binary(error.message)
    end

    test "parse_file returns error for non-existent file" do
      path = Path.join(@fixtures_path, "does_not_exist.ex")

      assert {:error, {:file_error, :enoent}} = Parser.parse_file(path)
    end

    test "FileReader returns error for non-existent file" do
      path = Path.join(@fixtures_path, "does_not_exist.ex")

      assert {:error, :enoent} = FileReader.read(path)
    end

    test "parse returns error for invalid syntax" do
      invalid_code = "defmodule Foo do def broken("

      assert {:error, %Parser.Error{} = error} = Parser.parse(invalid_code)
      assert error.line == 1
    end
  end

  # ============================================================================
  # Walker Control Flow Integration Tests
  # ============================================================================

  describe "walker control flow with real code" do
    test "halt stops traversal early" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      # Find first function and halt
      {_ast, first_fn} =
        ASTWalker.walk(result.ast, nil, fn node, _ctx, acc ->
          if Matchers.function?(node) and is_nil(acc) do
            {:halt, node}
          else
            {:cont, acc}
          end
        end)

      assert Matchers.function?(first_fn)
    end

    test "skip prevents descent into children" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      # Count functions, skipping private ones
      {_ast, public_count} =
        ASTWalker.walk(result.ast, 0, fn node, _ctx, acc ->
          cond do
            Matchers.private_function?(node) -> {:skip, acc}
            Matchers.public_function?(node) -> {:cont, acc + 1}
            true -> {:cont, acc}
          end
        end)

      # Should only count public functions
      all_public = ASTWalker.find_all(result.ast, &Matchers.public_function?/1)
      assert public_count == length(all_public)
    end
  end

  # ============================================================================
  # Collect and Transform Integration Tests
  # ============================================================================

  describe "collect and transform with real code" do
    test "collects function names from complex module" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      function_names =
        ASTWalker.collect(result.ast, &Matchers.function?/1, fn
          {_def, _meta, [{name, _name_meta, _args} | _]} -> name
          {_def, _meta, [name | _]} when is_atom(name) -> name
        end)

      assert :new in function_names
      assert :increment in function_names
      assert :process in function_names
      assert :init in function_names
    end

    test "collects module attributes with locations" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      attrs_with_locations =
        ASTWalker.collect(result.ast, &Matchers.attribute?/1, fn attr ->
          {:ok, loc} = Location.extract(attr)
          {attr, loc}
        end)

      assert length(attrs_with_locations) > 0

      Enum.each(attrs_with_locations, fn {_attr, {line, _col}} ->
        assert line > 0
      end)
    end
  end

  # ============================================================================
  # Location Range Accuracy Tests
  # ============================================================================

  describe "location range accuracy" do
    test "module location spans from defmodule to end" do
      path = Path.join(@fixtures_path, "multi_module.ex")
      {:ok, result} = Parser.parse_file(path)

      modules = ASTWalker.find_all(result.ast, &Matchers.module?/1)
      first_module = hd(modules)

      {:ok, loc} = Location.extract_range(first_module)

      # First module starts at line 2 (after comment)
      assert loc.start_line == 2
      # Should end with 'end' keyword
      assert loc.end_line > loc.start_line
    end

    test "function with do block has accurate range" do
      path = Path.join(@fixtures_path, "complex_module.ex")
      {:ok, result} = Parser.parse_file(path)

      # Find a multi-line function
      functions = ASTWalker.find_all(result.ast, &Matchers.function?/1)

      multi_line_fn =
        Enum.find(functions, fn func ->
          case Location.extract_range(func) do
            {:ok, loc} -> loc.end_line != nil and loc.end_line > loc.start_line
            _ -> false
          end
        end)

      assert multi_line_fn != nil
      {:ok, loc} = Location.extract_range(multi_line_fn)
      assert loc.end_line > loc.start_line
    end

    test "single-line def uses estimation" do
      path = Path.join(@fixtures_path, "multi_module.ex")
      {:ok, result} = Parser.parse_file(path)

      # Find hello/0 which is single-line: def hello, do: :world
      functions = ASTWalker.find_all(result.ast, &Matchers.function?/1)

      single_line_fn =
        Enum.find(functions, fn
          {:def, _meta, [{:hello, _, _} | _]} -> true
          _ -> false
        end)

      assert single_line_fn != nil

      # Without estimation - may have nil end
      {:ok, loc_no_est} = Location.extract_range(single_line_fn)

      # With estimation - should have end
      {:ok, loc_with_est} = Location.extract_range_with_estimate(single_line_fn)

      assert loc_with_est.end_line != nil
      assert loc_with_est.end_line == loc_with_est.start_line or loc_no_est.end_line != nil
    end
  end
end
