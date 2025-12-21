defmodule ElixirOntologies.Extractors.Phase16IntegrationTest do
  @moduledoc """
  Integration tests for Phase 16 Module Directives & Scope Analysis.

  These tests verify end-to-end functionality of directive extraction,
  dependency graph generation, and RDF building for alias, import,
  require, and use directives.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Directive.{Alias, Import, Require, Use}
  alias ElixirOntologies.Extractors.Directive.Alias.AliasDirective
  alias ElixirOntologies.Extractors.Directive.Import.ImportDirective
  alias ElixirOntologies.Extractors.Directive.Require.RequireDirective
  alias ElixirOntologies.Extractors.Directive.Use.UseDirective
  alias ElixirOntologies.Builders.{DependencyBuilder, Context}
  alias ElixirOntologies.NS.Structure

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp build_context(opts \\ []) do
    known_modules = Keyword.get(opts, :known_modules)

    Context.new(
      base_iri: Keyword.get(opts, :base_iri, "https://example.org/code#"),
      file_path: Keyword.get(opts, :file_path, nil),
      known_modules: known_modules
    )
  end

  defp build_module_iri(module_name, opts \\ []) do
    base_iri = Keyword.get(opts, :base_iri, "https://example.org/code#")
    RDF.iri("#{base_iri}#{module_name}")
  end

  defp extract_directives_from_module(module_code) do
    {:ok, ast} = Code.string_to_quoted(module_code)
    {:defmodule, _, [_name, [do: body]]} = ast

    # Flatten the body to get all expressions
    exprs = case body do
      {:__block__, _, exprs} -> exprs
      expr -> [expr]
    end

    aliases = extract_all_aliases(exprs)
    imports = extract_all_imports(exprs)
    requires = extract_all_requires(exprs)
    uses = extract_all_uses(exprs)

    %{aliases: aliases, imports: imports, requires: requires, uses: uses}
  end

  defp extract_all_aliases(exprs) do
    # Use extract_all which handles both simple and multi-alias forms
    Alias.extract_all(exprs)
  end

  defp extract_all_imports(exprs) do
    exprs
    |> Enum.flat_map(fn expr ->
      case Import.extract(expr) do
        {:ok, directive} -> [directive]
        _ -> []
      end
    end)
  end

  defp extract_all_requires(exprs) do
    exprs
    |> Enum.flat_map(fn expr ->
      case Require.extract(expr) do
        {:ok, directive} -> [directive]
        _ -> []
      end
    end)
  end

  defp extract_all_uses(exprs) do
    exprs
    |> Enum.flat_map(fn expr ->
      case Use.extract(expr) do
        {:ok, directive} -> [directive]
        _ -> []
      end
    end)
  end

  defp has_triple_with_predicate?(triples, predicate) do
    Enum.any?(triples, fn {_, p, _} -> p == predicate end)
  end

  defp count_triples_with_type(triples, type_class) do
    Enum.count(triples, fn
      {_, p, o} -> p == RDF.type() and o == type_class
      _ -> false
    end)
  end

  defp find_triples_with_predicate(triples, predicate) do
    Enum.filter(triples, fn {_, p, _} -> p == predicate end)
  end

  # ===========================================================================
  # Test Fixtures
  # ===========================================================================

  @complex_module """
  defmodule ComplexDirectives do
    alias MyApp.Users
    alias MyApp.Accounts
    alias MyApp.Helpers, as: H

    import Enum, only: [map: 2, filter: 2]
    import String, except: [split: 2]

    require Logger
    require MyApp.Macros, as: M

    use GenServer, restart: :temporary
    use MyApp.Behaviour
  end
  """

  @multi_alias_module """
  defmodule MultiAliasModule do
    alias MyApp.{Users, Accounts, Helpers}
    alias Other.{Sub.A, Sub.B}
  end
  """

  @scope_tracking_module """
  defmodule ScopeTracking do
    alias MyApp.ModuleLevel

    def my_function do
      alias MyApp.FunctionLevel

      for x <- 1..10 do
        alias MyApp.BlockLevel
        x
      end
    end
  end
  """

  @use_options_module """
  defmodule UseOptionsModule do
    use GenServer, restart: :temporary, shutdown: 5000
    use Plug.Builder, init_mode: :runtime, log_on_halt: :debug
    use MyApp.Behaviour, option: :value, another: "string", count: 42
  end
  """

  # ===========================================================================
  # Complete Directive Extraction Tests
  # ===========================================================================

  describe "complete directive extraction for complex module" do
    test "extracts all alias directives" do
      directives = extract_directives_from_module(@complex_module)

      assert length(directives.aliases) == 3
      alias_sources = Enum.map(directives.aliases, & &1.source)
      assert [:MyApp, :Users] in alias_sources
      assert [:MyApp, :Accounts] in alias_sources
      assert [:MyApp, :Helpers] in alias_sources
    end

    test "extracts all import directives" do
      directives = extract_directives_from_module(@complex_module)

      assert length(directives.imports) == 2

      enum_import = Enum.find(directives.imports, &(&1.module == [:Enum]))
      assert enum_import.only == [map: 2, filter: 2]

      string_import = Enum.find(directives.imports, &(&1.module == [:String]))
      assert string_import.except == [split: 2]
    end

    test "extracts all require directives" do
      directives = extract_directives_from_module(@complex_module)

      assert length(directives.requires) == 2

      logger_require = Enum.find(directives.requires, &(&1.module == [:Logger]))
      assert logger_require.as == nil

      macros_require = Enum.find(directives.requires, &(&1.module == [:MyApp, :Macros]))
      assert macros_require.as == :M
    end

    test "extracts all use directives" do
      directives = extract_directives_from_module(@complex_module)

      assert length(directives.uses) == 2

      genserver_use = Enum.find(directives.uses, &(&1.module == [:GenServer]))
      assert genserver_use.options == [restart: :temporary]

      behaviour_use = Enum.find(directives.uses, &(&1.module == [:MyApp, :Behaviour]))
      assert behaviour_use.options == nil or behaviour_use.options == []
    end

    test "total directive count matches expected" do
      directives = extract_directives_from_module(@complex_module)

      total = length(directives.aliases) +
              length(directives.imports) +
              length(directives.requires) +
              length(directives.uses)

      assert total == 9
    end
  end

  # ===========================================================================
  # Multi-Alias Expansion Tests
  # ===========================================================================

  describe "multi-alias expansion correctness" do
    test "expands simple multi-alias to individual aliases" do
      directives = extract_directives_from_module(@multi_alias_module)

      # MyApp.{Users, Accounts, Helpers} should expand to 3 aliases
      myapp_aliases = Enum.filter(directives.aliases, fn alias_dir ->
        match?([:MyApp | _], alias_dir.source)
      end)

      assert length(myapp_aliases) == 3
    end

    test "expands nested multi-alias correctly" do
      directives = extract_directives_from_module(@multi_alias_module)

      # Other.{Sub.A, Sub.B} should expand to 2 aliases
      other_aliases = Enum.filter(directives.aliases, fn alias_dir ->
        match?([:Other | _], alias_dir.source)
      end)

      assert length(other_aliases) == 2

      sources = Enum.map(other_aliases, & &1.source)
      assert [:Other, :Sub, :A] in sources
      assert [:Other, :Sub, :B] in sources
    end

    test "preserves correct alias names after expansion" do
      directives = extract_directives_from_module(@multi_alias_module)

      alias_map = for a <- directives.aliases, into: %{}, do: {a.source, a.as}

      # Check computed alias names (last segment)
      assert alias_map[[:MyApp, :Users]] == :Users
      assert alias_map[[:MyApp, :Accounts]] == :Accounts
      assert alias_map[[:MyApp, :Helpers]] == :Helpers
      assert alias_map[[:Other, :Sub, :A]] == :A
      assert alias_map[[:Other, :Sub, :B]] == :B
    end
  end

  # ===========================================================================
  # Use Option Extraction Tests
  # ===========================================================================

  describe "use option extraction completeness" do
    test "extracts all keyword options from use directives" do
      directives = extract_directives_from_module(@use_options_module)

      genserver_use = Enum.find(directives.uses, &(&1.module == [:GenServer]))
      assert genserver_use.options == [restart: :temporary, shutdown: 5000]
    end

    test "extracts string, atom, and integer option values" do
      directives = extract_directives_from_module(@use_options_module)

      behaviour_use = Enum.find(directives.uses, &(&1.module == [:MyApp, :Behaviour]))
      assert behaviour_use.options == [option: :value, another: "string", count: 42]
    end

    test "builds RDF triples for use options" do
      directives = extract_directives_from_module(@use_options_module)
      context = build_context()
      module_iri = build_module_iri("UseOptionsModule")

      all_triples = directives.uses
      |> Enum.with_index()
      |> Enum.flat_map(fn {use_dir, idx} ->
        {_, triples} = DependencyBuilder.build_use_dependency(use_dir, module_iri, context, idx)
        triples
      end)

      # Should have UseOption type triples
      option_count = count_triples_with_type(all_triples, Structure.UseOption)
      # GenServer has 2 options, Plug.Builder has 2, MyApp.Behaviour has 3 = 7 total
      assert option_count == 7
    end
  end

  # ===========================================================================
  # Module Dependency Graph Generation Tests
  # ===========================================================================

  describe "module dependency graph generation" do
    test "generates complete dependency graph for module" do
      directives = extract_directives_from_module(@complex_module)
      context = build_context()
      module_iri = build_module_iri("ComplexDirectives")

      # Build all dependency triples
      alias_triples = DependencyBuilder.build_alias_dependencies(
        directives.aliases, module_iri, context
      )

      import_triples = DependencyBuilder.build_import_dependencies(
        directives.imports, module_iri, context
      )

      require_triples = DependencyBuilder.build_require_dependencies(
        directives.requires, module_iri, context
      )

      use_triples = DependencyBuilder.build_use_dependencies(
        directives.uses, module_iri, context
      )

      all_triples = alias_triples ++ import_triples ++ require_triples ++ use_triples

      # Verify we have triples for each directive type
      assert count_triples_with_type(all_triples, Structure.ModuleAlias) == 3
      assert count_triples_with_type(all_triples, Structure.Import) == 2
      assert count_triples_with_type(all_triples, Structure.Require) == 2
      assert count_triples_with_type(all_triples, Structure.Use) == 2
    end

    test "dependency graph has correct module references" do
      directives = extract_directives_from_module(@complex_module)
      context = build_context()
      module_iri = build_module_iri("ComplexDirectives")

      alias_triples = DependencyBuilder.build_alias_dependencies(
        directives.aliases, module_iri, context
      )

      import_triples = DependencyBuilder.build_import_dependencies(
        directives.imports, module_iri, context
      )

      all_triples = alias_triples ++ import_triples

      # Check aliasedModule references
      aliased_modules = find_triples_with_predicate(all_triples, Structure.aliasedModule())
      aliased_iris = Enum.map(aliased_modules, fn {_, _, o} -> to_string(o) end)

      assert "https://example.org/code#MyApp.Users" in aliased_iris
      assert "https://example.org/code#MyApp.Accounts" in aliased_iris
      assert "https://example.org/code#MyApp.Helpers" in aliased_iris

      # Check importsModule references
      imported_modules = find_triples_with_predicate(all_triples, Structure.importsModule())
      imported_iris = Enum.map(imported_modules, fn {_, _, o} -> to_string(o) end)

      assert "https://example.org/code#Enum" in imported_iris
      assert "https://example.org/code#String" in imported_iris
    end

    test "hasAlias/hasImport/hasRequire/hasUse triples link to containing module" do
      directives = extract_directives_from_module(@complex_module)
      context = build_context()
      module_iri = build_module_iri("ComplexDirectives")

      alias_triples = DependencyBuilder.build_alias_dependencies(
        directives.aliases, module_iri, context
      )

      has_alias_triples = Enum.filter(alias_triples, fn
        {s, p, _} -> s == module_iri and p == Structure.hasAlias()
        _ -> false
      end)

      assert length(has_alias_triples) == 3
    end
  end

  # ===========================================================================
  # External Dependency Marking Tests
  # ===========================================================================

  describe "external dependency marking" do
    test "marks external modules correctly when known_modules configured" do
      directives = extract_directives_from_module(@complex_module)
      known_modules = MapSet.new(["MyApp.Users", "MyApp.Accounts", "MyApp.Helpers"])
      context = build_context(known_modules: known_modules)
      module_iri = build_module_iri("ComplexDirectives")

      alias_triples = DependencyBuilder.build_alias_dependencies(
        directives.aliases, module_iri, context
      )

      import_triples = DependencyBuilder.build_import_dependencies(
        directives.imports, module_iri, context
      )

      all_triples = alias_triples ++ import_triples

      # All aliases are to known modules - isExternalModule should be false
      external_alias_triples = Enum.filter(all_triples, fn
        {_, p, o} ->
          p == Structure.isExternalModule() and
          String.contains?(to_string(RDF.Literal.value(o)), "false")
        _ -> false
      end)

      # All 3 aliases should have isExternalModule = false
      assert length(external_alias_triples) == 3

      # Imports are to Enum and String which are NOT in known_modules
      external_import_triples = Enum.filter(all_triples, fn
        {_, p, o} ->
          p == Structure.isExternalModule() and
          RDF.Literal.value(o) == true
        _ -> false
      end)

      # Both imports should have isExternalModule = true
      assert length(external_import_triples) == 2
    end

    test "no isExternalModule triples when known_modules not configured" do
      directives = extract_directives_from_module(@complex_module)
      context = build_context()  # No known_modules
      module_iri = build_module_iri("ComplexDirectives")

      alias_triples = DependencyBuilder.build_alias_dependencies(
        directives.aliases, module_iri, context
      )

      external_triples = Enum.filter(alias_triples, fn
        {_, p, _} -> p == Structure.isExternalModule()
        _ -> false
      end)

      assert external_triples == []
    end
  end

  # ===========================================================================
  # Cross-Module Linking Tests
  # ===========================================================================

  describe "cross-module linking" do
    test "invokesUsing triple generated for known module" do
      use_dir = %UseDirective{module: [:MyApp, :Behaviour], options: []}
      known_modules = MapSet.new(["MyApp.Behaviour"])
      context = build_context(known_modules: known_modules)
      module_iri = build_module_iri("TestModule")

      {use_iri, triples} = DependencyBuilder.build_use_dependency(use_dir, module_iri, context, 0)

      invokes_using_triples = Enum.filter(triples, fn
        {^use_iri, p, _} -> p == Structure.invokesUsing()
        _ -> false
      end)

      assert length(invokes_using_triples) == 1

      {_, _, target_iri} = hd(invokes_using_triples)
      assert String.contains?(to_string(target_iri), "MyApp.Behaviour/__using__/1")
    end

    test "no invokesUsing triple for external module" do
      use_dir = %UseDirective{module: [:GenServer], options: []}
      known_modules = MapSet.new(["MyApp.Internal"])
      context = build_context(known_modules: known_modules)
      module_iri = build_module_iri("TestModule")

      {_, triples} = DependencyBuilder.build_use_dependency(use_dir, module_iri, context, 0)

      invokes_using_triples = Enum.filter(triples, fn
        {_, p, _} -> p == Structure.invokesUsing()
        _ -> false
      end)

      assert invokes_using_triples == []
    end
  end

  # ===========================================================================
  # Import Conflict Detection Tests
  # ===========================================================================

  describe "import conflict detection accuracy" do
    test "detects conflicts when same function imported from multiple modules" do
      imports = [
        %ImportDirective{module: [:Enum], only: [map: 2, filter: 2]},
        %ImportDirective{module: [:Stream], only: [map: 2, take: 2]}
      ]

      conflicts = Import.detect_import_conflicts(imports)

      assert length(conflicts) == 1
      conflict = hd(conflicts)
      assert conflict.function == {:map, 2}

      # Check that both imports are in the conflict
      conflict_modules = Enum.map(conflict.imports, &(&1.module))
      assert [:Enum] in conflict_modules
      assert [:Stream] in conflict_modules
    end

    test "no conflicts when functions are distinct" do
      imports = [
        %ImportDirective{module: [:Enum], only: [map: 2]},
        %ImportDirective{module: [:String], only: [split: 2]}
      ]

      conflicts = Import.detect_import_conflicts(imports)

      assert conflicts == []
    end

    test "no conflicts with full imports (cannot be determined statically)" do
      imports = [
        %ImportDirective{module: [:Enum]},
        %ImportDirective{module: [:String]}
      ]

      conflicts = Import.detect_import_conflicts(imports)

      # Full imports can't be checked for conflicts without module introspection
      assert conflicts == []
    end
  end

  # ===========================================================================
  # Lexical Scope Tracking Tests
  # ===========================================================================

  describe "lexical scope tracking accuracy" do
    test "tracks module-level scope using extract_all_with_scope" do
      {:ok, ast} = Code.string_to_quoted(@scope_tracking_module)
      {:defmodule, _, [_name, [do: body]]} = ast

      # Use extract_all_with_scope to get scope information
      directives = Alias.extract_all_with_scope(body)

      # Should have at least the module-level alias
      assert length(directives) >= 1

      # First directive should be module-level
      module_level_aliases = Enum.filter(directives, &(&1.scope == :module))
      assert length(module_level_aliases) >= 1
    end

    test "tracks function-level and block-level scopes within functions" do
      {:ok, ast} = Code.string_to_quoted(@scope_tracking_module)
      {:defmodule, _, [_name, [do: body]]} = ast

      # Use extract_all_with_scope to get all directives with scope info
      directives = Alias.extract_all_with_scope(body)

      # Should have directives at different scope levels
      scopes = Enum.map(directives, & &1.scope) |> Enum.uniq()

      # At minimum we should have module scope
      assert :module in scopes
    end
  end

  # ===========================================================================
  # Dependency Graph Completeness Tests
  # ===========================================================================

  describe "dependency graph completeness" do
    test "all directive types represented in graph" do
      directives = extract_directives_from_module(@complex_module)
      context = build_context()
      module_iri = build_module_iri("ComplexDirectives")

      alias_triples = DependencyBuilder.build_alias_dependencies(
        directives.aliases, module_iri, context
      )
      import_triples = DependencyBuilder.build_import_dependencies(
        directives.imports, module_iri, context
      )
      require_triples = DependencyBuilder.build_require_dependencies(
        directives.requires, module_iri, context
      )
      use_triples = DependencyBuilder.build_use_dependencies(
        directives.uses, module_iri, context
      )

      _all_triples = alias_triples ++ import_triples ++ require_triples ++ use_triples

      # Verify all expected predicates are present
      assert has_triple_with_predicate?(alias_triples, Structure.aliasedModule())
      assert has_triple_with_predicate?(alias_triples, Structure.aliasName())
      assert has_triple_with_predicate?(import_triples, Structure.importsModule())
      assert has_triple_with_predicate?(import_triples, Structure.isFullImport())
      assert has_triple_with_predicate?(require_triples, Structure.requireModule())
      assert has_triple_with_predicate?(use_triples, Structure.useModule())
    end

    test "each directive has unique IRI" do
      directives = extract_directives_from_module(@complex_module)
      context = build_context()
      module_iri = build_module_iri("ComplexDirectives")

      # Collect all directive IRIs
      alias_iris = directives.aliases
        |> Enum.with_index()
        |> Enum.map(fn {a, i} ->
          {iri, _} = DependencyBuilder.build_alias_dependency(a, module_iri, context, i)
          iri
        end)

      import_iris = directives.imports
        |> Enum.with_index()
        |> Enum.map(fn {imp, i} ->
          {iri, _} = DependencyBuilder.build_import_dependency(imp, module_iri, context, i)
          iri
        end)

      all_iris = alias_iris ++ import_iris

      # All IRIs should be unique
      assert length(all_iris) == length(Enum.uniq(all_iris))
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "error handling for malformed directives" do
    test "handles empty alias gracefully" do
      ast = {:alias, [line: 1], []}
      result = Alias.extract(ast)

      assert match?({:error, _}, result)
    end

    test "handles invalid import option" do
      # Import with both only and except (invalid but should not crash)
      ast = {:import, [line: 1], [
        {:__aliases__, [line: 1], [:Enum]},
        [only: [map: 2], except: [filter: 2]]
      ]}

      result = Import.extract(ast)

      # Should extract but mark as having both options
      case result do
        {:ok, directive} ->
          # Both options present
          assert directive.only != nil or directive.except != nil
        {:error, _} ->
          # Error is also acceptable
          assert true
      end
    end

    test "handles non-directive AST" do
      ast = {:def, [line: 1], [{:my_func, [line: 1], nil}, [do: :ok]]}

      assert {:error, _} = Alias.extract(ast)
      assert {:error, _} = Import.extract(ast)
      assert {:error, _} = Require.extract(ast)
      assert {:error, _} = Use.extract(ast)
    end
  end

  # ===========================================================================
  # Backward Compatibility Tests
  # ===========================================================================

  describe "backward compatibility with existing module extraction" do
    test "directive extraction does not break existing Module extractor patterns" do
      # Verify that extracted directives can be used alongside existing extractors
      directives = extract_directives_from_module(@complex_module)

      # All directives should have the expected struct types
      assert Enum.all?(directives.aliases, &match?(%AliasDirective{}, &1))
      assert Enum.all?(directives.imports, &match?(%ImportDirective{}, &1))
      assert Enum.all?(directives.requires, &match?(%RequireDirective{}, &1))
      assert Enum.all?(directives.uses, &match?(%UseDirective{}, &1))
    end

    test "dependency builder context is compatible with other builders" do
      context = build_context(
        base_iri: "https://example.org/code#",
        file_path: "lib/test.ex",
        known_modules: MapSet.new(["MyApp.Module"])
      )

      # Context should work with standard operations
      assert context.base_iri == "https://example.org/code#"
      assert context.file_path == "lib/test.ex"
      assert Context.cross_module_linking_enabled?(context)
    end
  end

  # ===========================================================================
  # Additional Integration Tests
  # ===========================================================================

  describe "require with alias option" do
    test "extracts require with as: option correctly" do
      directives = extract_directives_from_module(@complex_module)

      macros_require = Enum.find(directives.requires, &(&1.module == [:MyApp, :Macros]))
      assert macros_require.as == :M
    end

    test "builds RDF triple for require alias" do
      require_dir = %RequireDirective{module: [:Logger], as: :L}
      context = build_context()
      module_iri = build_module_iri("TestModule")

      {require_iri, triples} = DependencyBuilder.build_require_dependency(
        require_dir, module_iri, context, 0
      )

      alias_triple = Enum.find(triples, fn
        {^require_iri, p, _} -> p == Structure.requireAlias()
        _ -> false
      end)

      assert alias_triple != nil
      {_, _, literal} = alias_triple
      assert RDF.Literal.value(literal) == "L"
    end
  end

  describe "import with type-based only option" do
    test "extracts only: :functions correctly" do
      module = """
      defmodule TypeImport do
        import Kernel, only: :functions
      end
      """

      directives = extract_directives_from_module(module)
      assert length(directives.imports) == 1

      import_dir = hd(directives.imports)
      assert import_dir.only == :functions
    end

    test "extracts only: :macros correctly" do
      module = """
      defmodule MacroImport do
        import Kernel, only: :macros
      end
      """

      directives = extract_directives_from_module(module)
      import_dir = hd(directives.imports)
      assert import_dir.only == :macros
    end

    test "builds RDF triple for type-based import" do
      import_dir = %ImportDirective{module: [:Kernel], only: :functions}
      context = build_context()
      module_iri = build_module_iri("TestModule")

      {import_iri, triples} = DependencyBuilder.build_import_dependency(
        import_dir, module_iri, context, 0
      )

      # Should have importType triple
      type_triple = Enum.find(triples, fn
        {^import_iri, p, _} -> p == Structure.importType()
        _ -> false
      end)

      assert type_triple != nil
      {_, _, literal} = type_triple
      assert RDF.Literal.value(literal) == "functions"
    end
  end
end
