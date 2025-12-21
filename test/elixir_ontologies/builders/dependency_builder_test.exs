defmodule ElixirOntologies.Builders.DependencyBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{DependencyBuilder, Context}
  alias ElixirOntologies.Extractors.Directive.Alias.AliasDirective
  alias ElixirOntologies.Extractors.Directive.Import.ImportDirective
  alias ElixirOntologies.Extractors.Directive.Require.RequireDirective
  alias ElixirOntologies.Extractors.Directive.Use.UseDirective
  alias ElixirOntologies.NS.Structure

  doctest ElixirOntologies.Builders.DependencyBuilder

  @base_iri "https://example.org/code#"

  describe "build_alias_dependency/4" do
    test "generates correct alias IRI" do
      alias_info = %AliasDirective{source: [:MyApp, :Users], as: :U}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {alias_iri, _triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)

      assert to_string(alias_iri) == "#{@base_iri}MyApp/alias/0"
    end

    test "generates correct alias IRI with index" do
      alias_info = %AliasDirective{source: [:String], as: :S}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {alias_iri, _triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 5)

      assert to_string(alias_iri) == "#{@base_iri}MyApp/alias/5"
    end

    test "generates rdf:type ModuleAlias triple" do
      alias_info = %AliasDirective{source: [:Enum], as: :E}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {alias_iri, triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)

      type_triple = {alias_iri, RDF.type(), Structure.ModuleAlias}
      assert type_triple in triples
    end

    test "generates aliasName triple with explicit as" do
      alias_info = %AliasDirective{source: [:MyApp, :Users], as: :U}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {alias_iri, triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)

      # Find aliasName triple
      alias_name_triple = Enum.find(triples, fn
        {^alias_iri, pred, _} -> pred == Structure.aliasName()
        _ -> false
      end)

      assert alias_name_triple != nil
      {_, _, literal} = alias_name_triple
      assert RDF.Literal.value(literal) == "U"
    end

    test "generates aliasName triple with implicit name (last module part)" do
      alias_info = %AliasDirective{source: [:MyApp, :Users], as: nil}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {alias_iri, triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)

      # Find aliasName triple
      alias_name_triple = Enum.find(triples, fn
        {^alias_iri, pred, _} -> pred == Structure.aliasName()
        _ -> false
      end)

      assert alias_name_triple != nil
      {_, _, literal} = alias_name_triple
      assert RDF.Literal.value(literal) == "Users"
    end

    test "generates aliasedModule triple" do
      alias_info = %AliasDirective{source: [:MyApp, :Users], as: :U}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {alias_iri, triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)

      aliased_module_iri = RDF.iri("#{@base_iri}MyApp.Users")
      aliased_triple = {alias_iri, Structure.aliasedModule(), aliased_module_iri}
      assert aliased_triple in triples
    end

    test "generates hasAlias triple linking module to alias" do
      alias_info = %AliasDirective{source: [:Enum], as: :E}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {alias_iri, triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)

      has_alias_triple = {module_iri, Structure.hasAlias(), alias_iri}
      assert has_alias_triple in triples
    end

    test "returns exactly 4 triples" do
      alias_info = %AliasDirective{source: [:MyApp, :Users], as: :U}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_alias_iri, triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)

      assert length(triples) == 4
    end

    test "handles single-part module names" do
      alias_info = %AliasDirective{source: [:Enum], as: nil}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {alias_iri, triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)

      aliased_module_iri = RDF.iri("#{@base_iri}Enum")
      aliased_triple = {alias_iri, Structure.aliasedModule(), aliased_module_iri}
      assert aliased_triple in triples

      # Alias name should be "Enum"
      alias_name_triple = Enum.find(triples, fn
        {^alias_iri, pred, _} -> pred == Structure.aliasName()
        _ -> false
      end)
      {_, _, literal} = alias_name_triple
      assert RDF.Literal.value(literal) == "Enum"
    end

    test "handles deep module names" do
      alias_info = %AliasDirective{source: [:MyApp, :Accounts, :Users, :Permissions], as: :P}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {alias_iri, triples} = DependencyBuilder.build_alias_dependency(alias_info, module_iri, context, 0)

      aliased_module_iri = RDF.iri("#{@base_iri}MyApp.Accounts.Users.Permissions")
      aliased_triple = {alias_iri, Structure.aliasedModule(), aliased_module_iri}
      assert aliased_triple in triples
    end
  end

  describe "build_alias_dependencies/3" do
    test "returns empty list for empty aliases" do
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_alias_dependencies([], module_iri, context)

      assert triples == []
    end

    test "generates triples for single alias" do
      aliases = [%AliasDirective{source: [:Enum], as: :E}]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_alias_dependencies(aliases, module_iri, context)

      assert length(triples) == 4
    end

    test "generates triples for multiple aliases" do
      aliases = [
        %AliasDirective{source: [:Enum], as: :E},
        %AliasDirective{source: [:String], as: :S},
        %AliasDirective{source: [:List], as: nil}
      ]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_alias_dependencies(aliases, module_iri, context)

      # 3 aliases * 4 triples each = 12 triples
      assert length(triples) == 12
    end

    test "assigns sequential indices to aliases" do
      aliases = [
        %AliasDirective{source: [:Enum], as: :E},
        %AliasDirective{source: [:String], as: :S}
      ]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_alias_dependencies(aliases, module_iri, context)

      # Check that we have alias/0 and alias/1
      alias_0_iri = RDF.iri("#{@base_iri}MyApp/alias/0")
      alias_1_iri = RDF.iri("#{@base_iri}MyApp/alias/1")

      has_alias_0 = Enum.any?(triples, fn {s, _, _} -> s == alias_0_iri end)
      has_alias_1 = Enum.any?(triples, fn {s, _, _} -> s == alias_1_iri end)

      assert has_alias_0
      assert has_alias_1
    end
  end

  # ===========================================================================
  # Import Dependency Tests
  # ===========================================================================

  describe "build_import_dependency/4" do
    test "generates correct import IRI" do
      import_info = %ImportDirective{module: [:Enum]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, _triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      assert to_string(import_iri) == "#{@base_iri}MyApp/import/0"
    end

    test "generates correct import IRI with index" do
      import_info = %ImportDirective{module: [:String]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, _triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 3)

      assert to_string(import_iri) == "#{@base_iri}MyApp/import/3"
    end

    test "generates rdf:type Import triple" do
      import_info = %ImportDirective{module: [:Enum]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      type_triple = {import_iri, RDF.type(), Structure.Import}
      assert type_triple in triples
    end

    test "generates importsModule triple" do
      import_info = %ImportDirective{module: [:Enum]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      imported_module_iri = RDF.iri("#{@base_iri}Enum")
      imports_module_triple = {import_iri, Structure.importsModule(), imported_module_iri}
      assert imports_module_triple in triples
    end

    test "generates hasImport triple linking module to import" do
      import_info = %ImportDirective{module: [:Enum]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      has_import_triple = {module_iri, Structure.hasImport(), import_iri}
      assert has_import_triple in triples
    end

    test "generates isFullImport true for full import" do
      import_info = %ImportDirective{module: [:Enum]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      full_import_triple = Enum.find(triples, fn
        {^import_iri, pred, _} -> pred == Structure.isFullImport()
        _ -> false
      end)

      assert full_import_triple != nil
      {_, _, literal} = full_import_triple
      assert RDF.Literal.value(literal) == true
    end

    test "generates isFullImport false for selective import" do
      import_info = %ImportDirective{module: [:Enum], only: [map: 2]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      full_import_triple = Enum.find(triples, fn
        {^import_iri, pred, _} -> pred == Structure.isFullImport()
        _ -> false
      end)

      assert full_import_triple != nil
      {_, _, literal} = full_import_triple
      assert RDF.Literal.value(literal) == false
    end

    test "returns 4 triples for full import" do
      import_info = %ImportDirective{module: [:Enum]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      assert length(triples) == 4
    end

    test "handles multi-part module names" do
      import_info = %ImportDirective{module: [:MyApp, :Accounts, :Users]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      imported_module_iri = RDF.iri("#{@base_iri}MyApp.Accounts.Users")
      imports_module_triple = {import_iri, Structure.importsModule(), imported_module_iri}
      assert imports_module_triple in triples
    end
  end

  describe "build_import_dependency/4 with only: [func: arity]" do
    test "generates importsFunction triples for each imported function" do
      import_info = %ImportDirective{module: [:Enum], only: [map: 2, filter: 2]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      map_func_iri = RDF.iri("#{@base_iri}Enum/map/2")
      filter_func_iri = RDF.iri("#{@base_iri}Enum/filter/2")

      map_triple = {import_iri, Structure.importsFunction(), map_func_iri}
      filter_triple = {import_iri, Structure.importsFunction(), filter_func_iri}

      assert map_triple in triples
      assert filter_triple in triples
    end

    test "returns 6 triples for import with 2 functions" do
      import_info = %ImportDirective{module: [:Enum], only: [map: 2, filter: 2]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      # 4 base + 2 function triples
      assert length(triples) == 6
    end

    test "handles single function import" do
      import_info = %ImportDirective{module: [:String], only: [upcase: 1]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      func_iri = RDF.iri("#{@base_iri}String/upcase/1")
      func_triple = {import_iri, Structure.importsFunction(), func_iri}

      assert func_triple in triples
    end
  end

  describe "build_import_dependency/4 with except:" do
    test "generates excludesFunction triples for each excluded function" do
      import_info = %ImportDirective{module: [:Enum], except: [reduce: 3, each: 2]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      reduce_func_iri = RDF.iri("#{@base_iri}Enum/reduce/3")
      each_func_iri = RDF.iri("#{@base_iri}Enum/each/2")

      reduce_triple = {import_iri, Structure.excludesFunction(), reduce_func_iri}
      each_triple = {import_iri, Structure.excludesFunction(), each_func_iri}

      assert reduce_triple in triples
      assert each_triple in triples
    end

    test "returns 6 triples for import with 2 excluded functions" do
      import_info = %ImportDirective{module: [:Enum], except: [reduce: 3, each: 2]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      # 4 base + 2 excluded function triples
      assert length(triples) == 6
    end

    test "isFullImport is false for except import" do
      import_info = %ImportDirective{module: [:Enum], except: [reduce: 3]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      full_import_triple = Enum.find(triples, fn
        {^import_iri, pred, _} -> pred == Structure.isFullImport()
        _ -> false
      end)

      {_, _, literal} = full_import_triple
      assert RDF.Literal.value(literal) == false
    end
  end

  describe "build_import_dependency/4 with type-based imports" do
    test "generates importType triple for :functions" do
      import_info = %ImportDirective{module: [:Kernel], only: :functions}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      type_triple = Enum.find(triples, fn
        {^import_iri, pred, _} -> pred == Structure.importType()
        _ -> false
      end)

      assert type_triple != nil
      {_, _, literal} = type_triple
      assert RDF.Literal.value(literal) == "functions"
    end

    test "generates importType triple for :macros" do
      import_info = %ImportDirective{module: [:Kernel], only: :macros}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      type_triple = Enum.find(triples, fn
        {^import_iri, pred, _} -> pred == Structure.importType()
        _ -> false
      end)

      assert type_triple != nil
      {_, _, literal} = type_triple
      assert RDF.Literal.value(literal) == "macros"
    end

    test "generates importType triple for :sigils" do
      import_info = %ImportDirective{module: [:Kernel], only: :sigils}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      type_triple = Enum.find(triples, fn
        {^import_iri, pred, _} -> pred == Structure.importType()
        _ -> false
      end)

      assert type_triple != nil
      {_, _, literal} = type_triple
      assert RDF.Literal.value(literal) == "sigils"
    end

    test "returns 5 triples for type-based import" do
      import_info = %ImportDirective{module: [:Kernel], only: :macros}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_import_iri, triples} = DependencyBuilder.build_import_dependency(import_info, module_iri, context, 0)

      # 4 base + 1 importType triple
      assert length(triples) == 5
    end
  end

  describe "build_import_dependencies/3" do
    test "returns empty list for empty imports" do
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_import_dependencies([], module_iri, context)

      assert triples == []
    end

    test "generates triples for single import" do
      imports = [%ImportDirective{module: [:Enum]}]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_import_dependencies(imports, module_iri, context)

      assert length(triples) == 4
    end

    test "generates triples for multiple imports" do
      imports = [
        %ImportDirective{module: [:Enum]},
        %ImportDirective{module: [:String]},
        %ImportDirective{module: [:List]}
      ]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_import_dependencies(imports, module_iri, context)

      # 3 imports * 4 triples each = 12 triples
      assert length(triples) == 12
    end

    test "assigns sequential indices to imports" do
      imports = [
        %ImportDirective{module: [:Enum]},
        %ImportDirective{module: [:String]}
      ]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_import_dependencies(imports, module_iri, context)

      # Check that we have import/0 and import/1
      import_0_iri = RDF.iri("#{@base_iri}MyApp/import/0")
      import_1_iri = RDF.iri("#{@base_iri}MyApp/import/1")

      has_import_0 = Enum.any?(triples, fn {s, _, _} -> s == import_0_iri end)
      has_import_1 = Enum.any?(triples, fn {s, _, _} -> s == import_1_iri end)

      assert has_import_0
      assert has_import_1
    end

    test "handles mixed import types" do
      imports = [
        %ImportDirective{module: [:Enum]},
        %ImportDirective{module: [:String], only: [upcase: 1]},
        %ImportDirective{module: [:Kernel], only: :macros}
      ]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_import_dependencies(imports, module_iri, context)

      # First import: 4 triples (full)
      # Second import: 5 triples (4 base + 1 function)
      # Third import: 5 triples (4 base + 1 importType)
      assert length(triples) == 14
    end
  end

  # ===========================================================================
  # Require Dependency Tests
  # ===========================================================================

  describe "build_require_dependency/4" do
    test "generates correct require IRI" do
      require_info = %RequireDirective{module: [:Logger]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {require_iri, _triples} = DependencyBuilder.build_require_dependency(require_info, module_iri, context, 0)

      assert to_string(require_iri) == "#{@base_iri}MyApp/require/0"
    end

    test "generates correct require IRI with index" do
      require_info = %RequireDirective{module: [:Logger]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {require_iri, _triples} = DependencyBuilder.build_require_dependency(require_info, module_iri, context, 2)

      assert to_string(require_iri) == "#{@base_iri}MyApp/require/2"
    end

    test "generates rdf:type Require triple" do
      require_info = %RequireDirective{module: [:Logger]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {require_iri, triples} = DependencyBuilder.build_require_dependency(require_info, module_iri, context, 0)

      type_triple = {require_iri, RDF.type(), Structure.Require}
      assert type_triple in triples
    end

    test "generates requireModule triple" do
      require_info = %RequireDirective{module: [:Logger]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {require_iri, triples} = DependencyBuilder.build_require_dependency(require_info, module_iri, context, 0)

      required_module_iri = RDF.iri("#{@base_iri}Logger")
      require_module_triple = {require_iri, Structure.requireModule(), required_module_iri}
      assert require_module_triple in triples
    end

    test "generates hasRequire triple linking module to require" do
      require_info = %RequireDirective{module: [:Logger]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {require_iri, triples} = DependencyBuilder.build_require_dependency(require_info, module_iri, context, 0)

      has_require_triple = {module_iri, Structure.hasRequire(), require_iri}
      assert has_require_triple in triples
    end

    test "returns 3 triples for require without alias" do
      require_info = %RequireDirective{module: [:Logger]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_require_iri, triples} = DependencyBuilder.build_require_dependency(require_info, module_iri, context, 0)

      assert length(triples) == 3
    end

    test "generates requireAlias triple when as: is present" do
      require_info = %RequireDirective{module: [:Logger], as: :L}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {require_iri, triples} = DependencyBuilder.build_require_dependency(require_info, module_iri, context, 0)

      alias_triple = Enum.find(triples, fn
        {^require_iri, pred, _} -> pred == Structure.requireAlias()
        _ -> false
      end)

      assert alias_triple != nil
      {_, _, literal} = alias_triple
      assert RDF.Literal.value(literal) == "L"
    end

    test "returns 4 triples for require with alias" do
      require_info = %RequireDirective{module: [:Logger], as: :L}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_require_iri, triples} = DependencyBuilder.build_require_dependency(require_info, module_iri, context, 0)

      assert length(triples) == 4
    end

    test "handles multi-part module names" do
      require_info = %RequireDirective{module: [:Ecto, :Query]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {require_iri, triples} = DependencyBuilder.build_require_dependency(require_info, module_iri, context, 0)

      required_module_iri = RDF.iri("#{@base_iri}Ecto.Query")
      require_module_triple = {require_iri, Structure.requireModule(), required_module_iri}
      assert require_module_triple in triples
    end
  end

  describe "build_require_dependencies/3" do
    test "returns empty list for empty requires" do
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_require_dependencies([], module_iri, context)

      assert triples == []
    end

    test "generates triples for single require" do
      requires = [%RequireDirective{module: [:Logger]}]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_require_dependencies(requires, module_iri, context)

      assert length(triples) == 3
    end

    test "generates triples for multiple requires" do
      requires = [
        %RequireDirective{module: [:Logger]},
        %RequireDirective{module: [:Ecto, :Query], as: :Q}
      ]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_require_dependencies(requires, module_iri, context)

      # First require: 3 triples
      # Second require: 4 triples (3 base + 1 alias)
      assert length(triples) == 7
    end

    test "assigns sequential indices to requires" do
      requires = [
        %RequireDirective{module: [:Logger]},
        %RequireDirective{module: [:Ecto, :Query]}
      ]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_require_dependencies(requires, module_iri, context)

      require_0_iri = RDF.iri("#{@base_iri}MyApp/require/0")
      require_1_iri = RDF.iri("#{@base_iri}MyApp/require/1")

      has_require_0 = Enum.any?(triples, fn {s, _, _} -> s == require_0_iri end)
      has_require_1 = Enum.any?(triples, fn {s, _, _} -> s == require_1_iri end)

      assert has_require_0
      assert has_require_1
    end
  end

  # ===========================================================================
  # Use Dependency Tests
  # ===========================================================================

  describe "build_use_dependency/4" do
    test "generates correct use IRI" do
      use_info = %UseDirective{module: [:GenServer]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {use_iri, _triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      assert to_string(use_iri) == "#{@base_iri}MyApp/use/0"
    end

    test "generates correct use IRI with index" do
      use_info = %UseDirective{module: [:GenServer]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {use_iri, _triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 3)

      assert to_string(use_iri) == "#{@base_iri}MyApp/use/3"
    end

    test "generates rdf:type Use triple" do
      use_info = %UseDirective{module: [:GenServer]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      type_triple = {use_iri, RDF.type(), Structure.Use}
      assert type_triple in triples
    end

    test "generates useModule triple" do
      use_info = %UseDirective{module: [:GenServer]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      used_module_iri = RDF.iri("#{@base_iri}GenServer")
      use_module_triple = {use_iri, Structure.useModule(), used_module_iri}
      assert use_module_triple in triples
    end

    test "generates hasUse triple linking module to use" do
      use_info = %UseDirective{module: [:GenServer]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      has_use_triple = {module_iri, Structure.hasUse(), use_iri}
      assert has_use_triple in triples
    end

    test "returns 3 triples for use without options" do
      use_info = %UseDirective{module: [:GenServer]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      assert length(triples) == 3
    end

    test "handles multi-part module names" do
      use_info = %UseDirective{module: [:Plug, :Builder]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      used_module_iri = RDF.iri("#{@base_iri}Plug.Builder")
      use_module_triple = {use_iri, Structure.useModule(), used_module_iri}
      assert use_module_triple in triples
    end
  end

  describe "build_use_dependency/4 with keyword options" do
    test "generates hasUseOption triple for each option" do
      use_info = %UseDirective{module: [:GenServer], options: [restart: :temporary]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      option_triples = Enum.filter(triples, fn
        {^use_iri, pred, _} -> pred == Structure.hasUseOption()
        _ -> false
      end)

      assert length(option_triples) == 1
    end

    test "generates UseOption type triple" do
      use_info = %UseDirective{module: [:GenServer], options: [restart: :temporary]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      option_iri = RDF.iri("#{@base_iri}MyApp/use/0/option/0")
      type_triple = {option_iri, RDF.type(), Structure.UseOption}
      assert type_triple in triples
    end

    test "generates optionKey triple" do
      use_info = %UseDirective{module: [:GenServer], options: [restart: :temporary]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      option_iri = RDF.iri("#{@base_iri}MyApp/use/0/option/0")
      key_triple = Enum.find(triples, fn
        {^option_iri, pred, _} -> pred == Structure.optionKey()
        _ -> false
      end)

      assert key_triple != nil
      {_, _, literal} = key_triple
      assert RDF.Literal.value(literal) == "restart"
    end

    test "generates optionValue triple for atom value" do
      use_info = %UseDirective{module: [:GenServer], options: [restart: :temporary]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      option_iri = RDF.iri("#{@base_iri}MyApp/use/0/option/0")
      value_triple = Enum.find(triples, fn
        {^option_iri, pred, _} -> pred == Structure.optionValue()
        _ -> false
      end)

      assert value_triple != nil
      {_, _, literal} = value_triple
      assert RDF.Literal.value(literal) == "temporary"
    end

    test "generates optionValueType triple" do
      use_info = %UseDirective{module: [:GenServer], options: [restart: :temporary]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      option_iri = RDF.iri("#{@base_iri}MyApp/use/0/option/0")
      type_triple = Enum.find(triples, fn
        {^option_iri, pred, _} -> pred == Structure.optionValueType()
        _ -> false
      end)

      assert type_triple != nil
      {_, _, literal} = type_triple
      assert RDF.Literal.value(literal) == "atom"
    end

    test "generates isDynamicOption triple as false for literal value" do
      use_info = %UseDirective{module: [:GenServer], options: [restart: :temporary]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      option_iri = RDF.iri("#{@base_iri}MyApp/use/0/option/0")
      dynamic_triple = Enum.find(triples, fn
        {^option_iri, pred, _} -> pred == Structure.isDynamicOption()
        _ -> false
      end)

      assert dynamic_triple != nil
      {_, _, literal} = dynamic_triple
      assert RDF.Literal.value(literal) == false
    end

    test "returns 8 triples for use with 1 option (3 base + 5 option)" do
      use_info = %UseDirective{module: [:GenServer], options: [restart: :temporary]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      # 3 base + 6 option triples (type, link, key, value, valueType, dynamic)
      assert length(triples) == 9
    end

    test "handles multiple options" do
      use_info = %UseDirective{module: [:Plug, :Builder], options: [init_mode: :runtime, log_on_halt: :debug]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      option_triples = Enum.filter(triples, fn
        {^use_iri, pred, _} -> pred == Structure.hasUseOption()
        _ -> false
      end)

      assert length(option_triples) == 2
    end

    test "handles integer option value" do
      use_info = %UseDirective{module: [:GenServer], options: [timeout: 5000]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      option_iri = RDF.iri("#{@base_iri}MyApp/use/0/option/0")

      value_triple = Enum.find(triples, fn
        {^option_iri, pred, _} -> pred == Structure.optionValue()
        _ -> false
      end)
      {_, _, literal} = value_triple
      assert RDF.Literal.value(literal) == "5000"

      type_triple = Enum.find(triples, fn
        {^option_iri, pred, _} -> pred == Structure.optionValueType()
        _ -> false
      end)
      {_, _, type_literal} = type_triple
      assert RDF.Literal.value(type_literal) == "integer"
    end

    test "handles string option value" do
      use_info = %UseDirective{module: [:GenServer], options: [name: "my_server"]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      option_iri = RDF.iri("#{@base_iri}MyApp/use/0/option/0")

      type_triple = Enum.find(triples, fn
        {^option_iri, pred, _} -> pred == Structure.optionValueType()
        _ -> false
      end)
      {_, _, type_literal} = type_triple
      assert RDF.Literal.value(type_literal) == "string"
    end

    test "handles boolean option value" do
      use_info = %UseDirective{module: [:GenServer], options: [debug: true]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      option_iri = RDF.iri("#{@base_iri}MyApp/use/0/option/0")

      type_triple = Enum.find(triples, fn
        {^option_iri, pred, _} -> pred == Structure.optionValueType()
        _ -> false
      end)
      {_, _, type_literal} = type_triple
      assert RDF.Literal.value(type_literal) == "boolean"
    end
  end

  describe "build_use_dependency/4 with positional options" do
    test "handles positional atom option" do
      # use MyApp.Web, :controller
      use_info = %UseDirective{module: [:MyApp, :Web], options: [:controller]}
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      {_use_iri, triples} = DependencyBuilder.build_use_dependency(use_info, module_iri, context, 0)

      option_iri = RDF.iri("#{@base_iri}MyApp/use/0/option/0")

      # Key should be empty for positional
      key_triple = Enum.find(triples, fn
        {^option_iri, pred, _} -> pred == Structure.optionKey()
        _ -> false
      end)
      {_, _, literal} = key_triple
      assert RDF.Literal.value(literal) == ""

      # Value should be the atom
      value_triple = Enum.find(triples, fn
        {^option_iri, pred, _} -> pred == Structure.optionValue()
        _ -> false
      end)
      {_, _, value_literal} = value_triple
      assert RDF.Literal.value(value_literal) == "controller"
    end
  end

  describe "build_use_dependencies/3" do
    test "returns empty list for empty uses" do
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_use_dependencies([], module_iri, context)

      assert triples == []
    end

    test "generates triples for single use" do
      uses = [%UseDirective{module: [:GenServer]}]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_use_dependencies(uses, module_iri, context)

      assert length(triples) == 3
    end

    test "generates triples for multiple uses" do
      uses = [
        %UseDirective{module: [:GenServer]},
        %UseDirective{module: [:Supervisor], options: [strategy: :one_for_one]}
      ]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_use_dependencies(uses, module_iri, context)

      # First use: 3 triples
      # Second use: 9 triples (3 base + 6 option)
      assert length(triples) == 12
    end

    test "assigns sequential indices to uses" do
      uses = [
        %UseDirective{module: [:GenServer]},
        %UseDirective{module: [:Supervisor]}
      ]
      module_iri = RDF.iri("#{@base_iri}MyApp")
      context = Context.new(base_iri: @base_iri)

      triples = DependencyBuilder.build_use_dependencies(uses, module_iri, context)

      use_0_iri = RDF.iri("#{@base_iri}MyApp/use/0")
      use_1_iri = RDF.iri("#{@base_iri}MyApp/use/1")

      has_use_0 = Enum.any?(triples, fn {s, _, _} -> s == use_0_iri end)
      has_use_1 = Enum.any?(triples, fn {s, _, _} -> s == use_1_iri end)

      assert has_use_0
      assert has_use_1
    end
  end
end
