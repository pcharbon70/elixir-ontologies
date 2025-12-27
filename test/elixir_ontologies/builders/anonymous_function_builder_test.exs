defmodule ElixirOntologies.Builders.AnonymousFunctionBuilderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.{AnonymousFunctionBuilder, Context}
  alias ElixirOntologies.Extractors.AnonymousFunction
  alias ElixirOntologies.NS.{Structure, Core}

  doctest AnonymousFunctionBuilder

  describe "build/3 basic anonymous function" do
    test "builds minimal anonymous function with required fields" do
      ast = quote do: fn -> :ok end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Verify IRI format
      assert to_string(anon_iri) == "https://example.org/code#MyApp/anon/0"

      # Verify type triple
      assert {anon_iri, RDF.type(), Structure.AnonymousFunction} in triples

      # Verify arity triple
      assert Enum.any?(triples, fn
               {^anon_iri, pred, obj} ->
                 pred == Structure.arity() and
                   RDF.Literal.value(obj) == 0

               _ ->
                 false
             end)

      # Should have at least type, arity, and clause triples
      assert length(triples) >= 4
    end

    test "builds anonymous function with arity 1" do
      ast = quote do: fn x -> x + 1 end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Verify arity is 1
      assert Enum.any?(triples, fn
               {^anon_iri, pred, obj} ->
                 pred == Structure.arity() and
                   RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)
    end

    test "builds anonymous function with arity 2" do
      ast = quote do: fn x, y -> x + y end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Verify arity is 2
      assert Enum.any?(triples, fn
               {^anon_iri, pred, obj} ->
                 pred == Structure.arity() and
                   RDF.Literal.value(obj) == 2

               _ ->
                 false
             end)
    end
  end

  describe "build/3 clause triples" do
    test "generates clause IRI with correct format" do
      ast = quote do: fn x -> x end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Find clause IRI
      clause_iri = ~I<https://example.org/code#MyApp/anon/0/clause/0>

      # Verify clause has type FunctionClause
      assert {clause_iri, RDF.type(), Structure.FunctionClause} in triples

      # Verify hasClause relationship
      assert {anon_iri, Structure.hasClause(), clause_iri} in triples
    end

    test "generates clause order triple (1-indexed)" do
      ast = quote do: fn x -> x end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {_anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      clause_iri = ~I<https://example.org/code#MyApp/anon/0/clause/0>

      # Verify clauseOrder is 1 (1-indexed)
      assert Enum.any?(triples, fn
               {^clause_iri, pred, obj} ->
                 pred == Structure.clauseOrder() and
                   RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)
    end
  end

  describe "build/3 multi-clause anonymous functions" do
    test "builds triples for multi-clause anonymous function" do
      ast =
        quote do
          fn
            0 -> :zero
            n -> n
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      clause0_iri = ~I<https://example.org/code#MyApp/anon/0/clause/0>
      clause1_iri = ~I<https://example.org/code#MyApp/anon/0/clause/1>

      # Both clauses should exist
      assert {clause0_iri, RDF.type(), Structure.FunctionClause} in triples
      assert {clause1_iri, RDF.type(), Structure.FunctionClause} in triples

      # Both should have hasClause relationships
      assert {anon_iri, Structure.hasClause(), clause0_iri} in triples
      assert {anon_iri, Structure.hasClause(), clause1_iri} in triples

      # Clause orders should be 1 and 2 (1-indexed)
      assert Enum.any?(triples, fn
               {^clause0_iri, pred, obj} ->
                 pred == Structure.clauseOrder() and
                   RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)

      assert Enum.any?(triples, fn
               {^clause1_iri, pred, obj} ->
                 pred == Structure.clauseOrder() and
                   RDF.Literal.value(obj) == 2

               _ ->
                 false
             end)
    end

    test "generates hasClauses list for multi-clause function" do
      ast =
        quote do
          fn
            0 -> :zero
            n -> n
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Should have hasClauses property (linking to an RDF list)
      assert Enum.any?(triples, fn
               {^anon_iri, pred, _obj} ->
                 pred == Structure.hasClauses()

               _ ->
                 false
             end)
    end
  end

  describe "build/3 context variations" do
    test "uses file path context when no module available" do
      ast = quote do: fn x -> x end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", file_path: "lib/my_app.ex")

      {anon_iri, _triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # IRI should use file path
      assert to_string(anon_iri) == "https://example.org/code#file/lib/my_app.ex/anon/0"
    end

    test "uses parent_module context when available" do
      ast = quote do: fn x -> x end
      {:ok, anon} = AnonymousFunction.extract(ast)

      parent_iri = ~I<https://example.org/code#MyApp.Server>
      context = Context.new(base_iri: "https://example.org/code#", parent_module: parent_iri)

      {anon_iri, _triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # IRI should use parent module
      assert to_string(anon_iri) == "https://example.org/code#MyApp.Server/anon/0"
    end

    test "uses different index for unique IRIs" do
      ast = quote do: fn x -> x end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {anon_iri_0, _} = AnonymousFunctionBuilder.build(anon, context, 0)
      {anon_iri_1, _} = AnonymousFunctionBuilder.build(anon, context, 1)
      {anon_iri_2, _} = AnonymousFunctionBuilder.build(anon, context, 2)

      # All IRIs should be different
      assert to_string(anon_iri_0) == "https://example.org/code#MyApp/anon/0"
      assert to_string(anon_iri_1) == "https://example.org/code#MyApp/anon/1"
      assert to_string(anon_iri_2) == "https://example.org/code#MyApp/anon/2"
    end
  end

  describe "build/3 with guards" do
    test "includes guard triple when clause has guard" do
      ast =
        quote do
          fn
            n when n > 0 -> :positive
            _ -> :other
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {_anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      clause0_iri = ~I<https://example.org/code#MyApp/anon/0/clause/0>

      # First clause should have guard = true
      assert Enum.any?(triples, fn
               {^clause0_iri, pred, obj} ->
                 pred == Core.hasGuard() and
                   RDF.Literal.value(obj) == true

               _ ->
                 false
             end)
    end
  end

  describe "build/3 source location" do
    test "includes location triple when location and file_path available" do
      ast = quote do: fn x -> x end
      {:ok, anon} = AnonymousFunction.extract(ast)

      # Add location to the struct
      anon = %{anon | location: %{start_line: 10, end_line: 10}}

      context =
        Context.new(
          base_iri: "https://example.org/code#",
          file_path: "lib/my_app.ex",
          metadata: %{module: [:MyApp]}
        )

      {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Should have location triple
      assert Enum.any?(triples, fn
               {^anon_iri, pred, _obj} ->
                 pred == Core.hasSourceLocation()

               _ ->
                 false
             end)
    end

    test "skips location triple when no file_path" do
      ast = quote do: fn x -> x end
      {:ok, anon} = AnonymousFunction.extract(ast)

      # Add location but no file_path
      anon = %{anon | location: %{start_line: 10, end_line: 10}}

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Should NOT have location triple
      refute Enum.any?(triples, fn
               {^anon_iri, pred, _obj} ->
                 pred == Core.hasSourceLocation()

               _ ->
                 false
             end)
    end
  end

  # ===========================================================================
  # RDF Triple Validation Tests
  # ===========================================================================

  describe "build/3 RDF validation" do
    test "all subjects are valid RDF.IRI structs" do
      ast = quote do: fn x, y -> x + y end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {_anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Every triple subject must be an IRI or BlankNode
      Enum.each(triples, fn {subject, _pred, _obj} ->
        assert is_struct(subject, RDF.IRI) or is_struct(subject, RDF.BlankNode),
               "Subject must be IRI or BlankNode, got: #{inspect(subject)}"
      end)
    end

    test "all predicates are valid RDF.IRI structs" do
      ast = quote do: fn x -> x + 1 end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {_anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Every predicate must be an IRI
      Enum.each(triples, fn {_subj, predicate, _obj} ->
        assert is_struct(predicate, RDF.IRI),
               "Predicate must be IRI, got: #{inspect(predicate)}"
      end)
    end

    test "type triples reference valid ontology classes" do
      ast =
        quote do
          fn
            0 -> :zero
            n -> n
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {_anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Filter for rdf:type triples
      type_triples = Enum.filter(triples, fn {_s, p, _o} -> p == RDF.type() end)

      # Should have at least one type triple (for AnonymousFunction)
      assert length(type_triples) >= 1

      # All type objects should be RDF-compatible terms (IRI or NS module)
      Enum.each(type_triples, fn {_subj, _pred, obj} ->
        # The object can be an RDF.IRI or an RDF vocabulary term (module)
        # Convert to IRI to get the string representation
        iri = RDF.IRI.new(obj)
        iri_string = iri.value

        # Should be from the elixir-code ontology or W3C namespace
        assert String.contains?(iri_string, "elixir-code") or
                 String.contains?(iri_string, "w3.org"),
               "Type should be from elixir-code or W3C namespace, got: #{iri_string}"
      end)
    end

    test "arity literals have correct xsd:nonNegativeInteger datatype" do
      ast = quote do: fn x, y, z -> x + y + z end
      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Find the arity triple
      arity_triple =
        Enum.find(triples, fn
          {^anon_iri, pred, _obj} -> pred == Structure.arity()
          _ -> false
        end)

      assert arity_triple != nil, "Arity triple should exist"

      {_s, _p, arity_literal} = arity_triple

      # Verify it's a literal with correct value
      assert is_struct(arity_literal, RDF.Literal)
      assert RDF.Literal.value(arity_literal) == 3

      # Verify datatype is xsd:nonNegativeInteger
      datatype_id = RDF.Literal.datatype_id(arity_literal)
      assert datatype_id == RDF.XSD.NonNegativeInteger.id()
    end

    test "clauseOrder literals have correct xsd:positiveInteger datatype" do
      ast =
        quote do
          fn
            0 -> :zero
            n -> n
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {_anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Find clauseOrder triples
      order_triples =
        Enum.filter(triples, fn
          {_s, pred, _obj} -> pred == Structure.clauseOrder()
          _ -> false
        end)

      # Should have 2 clause order triples (for 2 clauses)
      assert length(order_triples) == 2

      # Verify datatypes and values
      Enum.each(order_triples, fn {_s, _p, order_literal} ->
        assert is_struct(order_literal, RDF.Literal)
        assert RDF.Literal.datatype_id(order_literal) == RDF.XSD.PositiveInteger.id()

        # Values should be 1 or 2 (1-indexed)
        value = RDF.Literal.value(order_literal)
        assert value in [1, 2]
      end)
    end

    test "guard literals have correct xsd:boolean datatype" do
      ast =
        quote do
          fn
            n when n > 0 -> :positive
            _ -> :other
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})

      {_anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Find hasGuard triple
      guard_triple =
        Enum.find(triples, fn
          {_s, pred, _obj} -> pred == Core.hasGuard()
          _ -> false
        end)

      assert guard_triple != nil, "Guard triple should exist for guarded clause"

      {_s, _p, guard_literal} = guard_triple

      assert is_struct(guard_literal, RDF.Literal)
      assert RDF.Literal.value(guard_literal) == true
      assert RDF.Literal.datatype_id(guard_literal) == RDF.XSD.Boolean.id()
    end

    test "all triples form valid RDF graph" do
      ast =
        quote do
          fn
            0 -> :zero
            n when n > 0 -> :positive
            n -> n
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)

      context =
        Context.new(
          base_iri: "https://example.org/code#",
          file_path: "lib/my_app.ex",
          metadata: %{module: [:MyApp]}
        )

      anon = %{anon | location: %{start_line: 1, end_line: 5}}

      {_anon_iri, triples} = AnonymousFunctionBuilder.build(anon, context, 0)

      # Create an RDF graph from the triples
      graph = RDF.Graph.new(triples)

      # Graph should not be empty
      assert RDF.Graph.triple_count(graph) > 0

      # Triples should match the input
      assert RDF.Graph.triple_count(graph) == length(Enum.uniq(triples))
    end
  end
end
