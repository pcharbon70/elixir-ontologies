defmodule ElixirOntologies.Builders.MacroBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{MacroBuilder, Context}
  alias ElixirOntologies.Extractors.MacroInvocation
  alias ElixirOntologies.NS.{Structure, Core}
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  doctest MacroBuilder

  describe "build/2 basic macro invocation" do
    test "builds minimal Kernel macro invocation" do
      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :def,
        arity: 2,
        category: :definition,
        resolution_status: :kernel,
        arguments: [],
        location: nil,
        metadata: %{invocation_index: 0, module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {invocation_iri, triples} = MacroBuilder.build(invocation, context)

      # Verify IRI format
      assert to_string(invocation_iri) =~ "MyApp/invocation/"
      assert to_string(invocation_iri) =~ "Kernel.def"

      # Verify type triple
      assert {invocation_iri, RDF.type(), Structure.MacroInvocation} in triples

      # Verify macro name triple
      assert Enum.any?(triples, fn
               {^invocation_iri, pred, obj} ->
                 pred == Structure.macroName() and
                   RDF.Literal.value(obj) == "def"

               _ ->
                 false
             end)

      # Verify arity triple
      assert Enum.any?(triples, fn
               {^invocation_iri, pred, obj} ->
                 pred == Structure.macroArity() and
                   RDF.Literal.value(obj) == 2

               _ ->
                 false
             end)

      # Verify category triple
      assert Enum.any?(triples, fn
               {^invocation_iri, pred, obj} ->
                 pred == Structure.macroCategory() and
                   RDF.Literal.value(obj) == "definition"

               _ ->
                 false
             end)

      # Verify resolution status triple
      assert Enum.any?(triples, fn
               {^invocation_iri, pred, obj} ->
                 pred == Structure.resolutionStatus() and
                   RDF.Literal.value(obj) == "kernel"

               _ ->
                 false
             end)
    end

    test "builds control flow macro invocation" do
      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :if,
        arity: 2,
        category: :control_flow,
        resolution_status: :kernel,
        arguments: [],
        location: nil,
        metadata: %{invocation_index: 5, module: [:MyApp, :Utils]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {invocation_iri, triples} = MacroBuilder.build(invocation, context)

      # Verify nested module in IRI
      assert to_string(invocation_iri) =~ "MyApp.Utils"

      # Verify category
      assert Enum.any?(triples, fn
               {^invocation_iri, pred, obj} ->
                 pred == Structure.macroCategory() and
                   RDF.Literal.value(obj) == "control_flow"

               _ ->
                 false
             end)
    end

    test "builds library macro invocation" do
      invocation = %MacroInvocation{
        macro_module: Logger,
        macro_name: :debug,
        arity: 1,
        category: :library,
        resolution_status: :resolved,
        arguments: [],
        location: nil,
        metadata: %{invocation_index: 10, module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {invocation_iri, triples} = MacroBuilder.build(invocation, context)

      # Verify macro module triple
      assert Enum.any?(triples, fn
               {^invocation_iri, pred, obj} ->
                 pred == Structure.macroModule() and
                   RDF.Literal.value(obj) == "Logger"

               _ ->
                 false
             end)

      # Verify resolution status is resolved
      assert Enum.any?(triples, fn
               {^invocation_iri, pred, obj} ->
                 pred == Structure.resolutionStatus() and
                   RDF.Literal.value(obj) == "resolved"

               _ ->
                 false
             end)
    end
  end

  describe "build/2 with location" do
    test "builds invocation with source location" do
      location = %SourceLocation{
        start_line: 15,
        start_column: 5,
        end_line: 20,
        end_column: 8
      }

      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :defmodule,
        arity: 2,
        category: :definition,
        resolution_status: :kernel,
        arguments: [],
        location: location,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {invocation_iri, triples} = MacroBuilder.build(invocation, context)

      # Should have invokedAt triple
      assert Enum.any?(triples, fn
               {^invocation_iri, pred, _obj} ->
                 pred == Structure.invokedAt()

               _ ->
                 false
             end)

      # Location IRI should include line numbers
      location_triples =
        Enum.filter(triples, fn
          {_s, pred, _o} -> pred == Structure.invokedAt()
          _ -> false
        end)

      assert length(location_triples) == 1
      {_, _, location_iri} = hd(location_triples)

      assert to_string(location_iri) =~ "L15-20"

      # Location should have type triple
      assert {location_iri, RDF.type(), Core.SourceLocation} in triples
    end

    test "uses line number as invocation index when no index in metadata" do
      location = %SourceLocation{start_line: 42, start_column: 1, end_line: 42, end_column: 20}

      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :def,
        arity: 2,
        category: :definition,
        resolution_status: :kernel,
        arguments: [],
        location: location,
        metadata: %{module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {invocation_iri, _triples} = MacroBuilder.build(invocation, context)

      # IRI should use line 42 as index
      assert to_string(invocation_iri) =~ "/42"
    end
  end

  describe "build_macro_invocation/3 with options" do
    test "allows overriding index via options" do
      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :def,
        arity: 2,
        category: :definition,
        resolution_status: :kernel,
        arguments: [],
        location: nil,
        metadata: %{invocation_index: 0, module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {invocation_iri, _triples} =
        MacroBuilder.build_macro_invocation(invocation, context, index: 99)

      assert to_string(invocation_iri) =~ "/99"
    end
  end

  describe "build/2 edge cases" do
    test "handles unresolved macro" do
      invocation = %MacroInvocation{
        macro_module: nil,
        macro_name: :custom_macro,
        arity: 1,
        category: :custom,
        resolution_status: :unresolved,
        arguments: [],
        location: nil,
        metadata: %{invocation_index: 0, module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {invocation_iri, triples} = MacroBuilder.build(invocation, context)

      # Should still generate valid IRI
      assert to_string(invocation_iri) =~ "unknown.custom_macro"

      # Should have resolution status as unresolved
      assert Enum.any?(triples, fn
               {^invocation_iri, pred, obj} ->
                 pred == Structure.resolutionStatus() and
                   RDF.Literal.value(obj) == "unresolved"

               _ ->
                 false
             end)

      # Should NOT have macroModule triple (nil module)
      refute Enum.any?(triples, fn
               {^invocation_iri, pred, _obj} ->
                 pred == Structure.macroModule()

               _ ->
                 false
             end)
    end

    test "handles quote category" do
      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :quote,
        arity: 1,
        category: :quote,
        resolution_status: :kernel,
        arguments: [],
        location: nil,
        metadata: %{invocation_index: 0, module: [:MyApp]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {_invocation_iri, triples} = MacroBuilder.build(invocation, context)

      assert Enum.any?(triples, fn
               {_s, pred, obj} ->
                 pred == Structure.macroCategory() and
                   RDF.Literal.value(obj) == "quote"

               _ ->
                 false
             end)
    end

    test "handles nested module context" do
      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :def,
        arity: 2,
        category: :definition,
        resolution_status: :kernel,
        arguments: [],
        location: nil,
        metadata: %{invocation_index: 0, module: [:MyApp, :Users, :Admin, :Permissions]}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {invocation_iri, _triples} = MacroBuilder.build(invocation, context)

      assert to_string(invocation_iri) =~ "MyApp.Users.Admin.Permissions"
    end
  end
end
