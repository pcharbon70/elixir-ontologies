defmodule ElixirOntologies.Builders.DependencyBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{DependencyBuilder, Context}
  alias ElixirOntologies.Extractors.Directive.Alias.AliasDirective
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
end
