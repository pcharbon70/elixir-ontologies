defmodule ElixirOntologies.Builders.HelpersTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.Helpers
  alias ElixirOntologies.NS.Structure

  describe "type_triple/2" do
    test "generates rdf:type triple" do
      subject = ~I<https://example.org/code#MyApp>
      {s, p, o} = Helpers.type_triple(subject, Structure.Module)

      assert s == subject
      assert p == RDF.type()
      assert o == Structure.Module
    end

    test "works with blank nodes" do
      subject = RDF.bnode()
      {s, p, o} = Helpers.type_triple(subject, Structure.FunctionHead)

      assert s == subject
      assert p == RDF.type()
      assert o == Structure.FunctionHead
    end
  end

  describe "datatype_property/4" do
    test "generates datatype property triple with explicit datatype" do
      subject = ~I<https://example.org/code#MyApp>
      {s, p, o} = Helpers.datatype_property(subject, Structure.moduleName(), "MyApp", RDF.XSD.String)

      assert s == subject
      assert p == Structure.moduleName()
      assert RDF.Literal.value(o) == "MyApp"
    end

    test "generates integer datatype property" do
      subject = ~I<https://example.org/code#MyApp/hello/0>
      {_s, _p, o} = Helpers.datatype_property(subject, Structure.arity(), 0, RDF.XSD.NonNegativeInteger)

      assert RDF.Literal.value(o) == 0
    end

    test "uses default datatype when not specified" do
      subject = ~I<https://example.org/code#MyApp>
      {_s, _p, o} = Helpers.datatype_property(subject, Structure.moduleName(), "MyApp")

      assert RDF.Literal.value(o) == "MyApp"
    end

    test "handles boolean values" do
      subject = ~I<https://example.org/code#MyApp>
      prop = ~I<http://example.org/isPublic>
      {_s, _p, o} = Helpers.datatype_property(subject, prop, true, RDF.XSD.Boolean)

      assert RDF.Literal.value(o) == true
    end
  end

  describe "object_property/3" do
    test "generates object property triple" do
      function_iri = ~I<https://example.org/code#MyApp/hello/0>
      module_iri = ~I<https://example.org/code#MyApp>

      {s, p, o} = Helpers.object_property(function_iri, Structure.belongsTo(), module_iri)

      assert s == function_iri
      assert p == Structure.belongsTo()
      assert o == module_iri
    end

    test "works with blank nodes" do
      subject = RDF.bnode()
      object = RDF.bnode()

      {s, p, o} = Helpers.object_property(subject, Structure.hasHead(), object)

      assert s == subject
      assert p == Structure.hasHead()
      assert o == object
    end
  end

  describe "build_rdf_list/1" do
    test "builds empty list" do
      {head, triples} = Helpers.build_rdf_list([])

      assert head == RDF.nil()
      assert triples == []
    end

    test "builds single item list" do
      item = ~I<https://example.org/code#param1>
      {head, triples} = Helpers.build_rdf_list([item])

      assert is_struct(head, RDF.BlankNode)
      assert length(triples) == 2  # first + rest

      # Check structure
      {_s, p1, o1} = Enum.at(triples, 0)
      assert p1 == RDF.first()
      assert o1 == item

      {_s, p2, o2} = Enum.at(triples, 1)
      assert p2 == RDF.rest()
      assert o2 == RDF.nil()
    end

    test "builds multi-item list" do
      items = [
        ~I<https://example.org/code#param1>,
        ~I<https://example.org/code#param2>,
        ~I<https://example.org/code#param3>
      ]

      {head, triples} = Helpers.build_rdf_list(items)

      assert is_struct(head, RDF.BlankNode)
      # 3 items: each has first + rest triple = 6 triples
      assert length(triples) == 6

      # All triples should use either rdf:first or rdf:rest
      Enum.each(triples, fn {_s, p, _o} ->
        assert p in [RDF.first(), RDF.rest()]
      end)
    end

    test "list terminates with rdf:nil" do
      items = [~I<https://example.org/code#item>]
      {_head, triples} = Helpers.build_rdf_list(items)

      # Last triple should be rdf:rest → rdf:nil
      rest_triples = Enum.filter(triples, fn {_s, p, _o} -> p == RDF.rest() end)
      {_s, _p, o} = List.last(rest_triples)
      assert o == RDF.nil()
    end
  end

  describe "blank_node/1" do
    test "creates blank node without label" do
      node = Helpers.blank_node()

      assert is_struct(node, RDF.BlankNode)
    end

    test "creates blank node with label" do
      node = Helpers.blank_node("function_head")

      assert is_struct(node, RDF.BlankNode)
    end

    test "different blank nodes are unique" do
      node1 = Helpers.blank_node()
      node2 = Helpers.blank_node()

      refute node1 == node2
    end
  end

  describe "to_literal/1" do
    test "converts integer" do
      literal = Helpers.to_literal(42)
      assert RDF.Literal.value(literal) == 42
    end

    test "converts float" do
      literal = Helpers.to_literal(3.14)
      assert RDF.Literal.value(literal) == 3.14
    end

    test "converts boolean" do
      literal_true = Helpers.to_literal(true)
      literal_false = Helpers.to_literal(false)

      assert RDF.Literal.value(literal_true) == true
      assert RDF.Literal.value(literal_false) == false
    end

    test "converts string" do
      literal = Helpers.to_literal("hello")
      assert RDF.Literal.value(literal) == "hello"
    end

    test "converts Date" do
      date = ~D[2025-01-15]
      literal = Helpers.to_literal(date)
      assert RDF.Literal.value(literal) == date
    end

    test "converts DateTime" do
      datetime = ~U[2025-01-15 10:30:00Z]
      literal = Helpers.to_literal(datetime)
      assert RDF.Literal.value(literal) == datetime
    end
  end

  describe "deduplicate_triples/1" do
    test "removes duplicate triples" do
      triple = {~I<http://example.org/s>, ~I<http://example.org/p>, ~I<http://example.org/o>}

      triples = [[triple], [triple], [triple]]
      result = Helpers.deduplicate_triples(triples)

      assert length(result) == 1
      assert hd(result) == triple
    end

    test "flattens nested lists" do
      triple1 = {~I<http://example.org/s1>, ~I<http://example.org/p>, ~I<http://example.org/o>}
      triple2 = {~I<http://example.org/s2>, ~I<http://example.org/p>, ~I<http://example.org/o>}

      triples = [[triple1], [triple2]]
      result = Helpers.deduplicate_triples(triples)

      assert length(result) == 2
      assert triple1 in result
      assert triple2 in result
    end

    test "handles empty lists" do
      assert Helpers.deduplicate_triples([]) == []
      assert Helpers.deduplicate_triples([[]]) == []
    end
  end

  describe "filter_by_subject/2" do
    test "filters triples by subject" do
      subject = ~I<http://example.org/s>
      other = ~I<http://example.org/other>

      triples = [
        {subject, ~I<http://example.org/p1>, ~I<http://example.org/o1>},
        {other, ~I<http://example.org/p2>, ~I<http://example.org/o2>},
        {subject, ~I<http://example.org/p3>, ~I<http://example.org/o3>}
      ]

      result = Helpers.filter_by_subject(triples, subject)

      assert length(result) == 2
      Enum.each(result, fn {s, _p, _o} -> assert s == subject end)
    end

    test "returns empty list when no matches" do
      subject = ~I<http://example.org/s>
      other = ~I<http://example.org/other>

      triples = [
        {other, ~I<http://example.org/p>, ~I<http://example.org/o>}
      ]

      result = Helpers.filter_by_subject(triples, subject)

      assert result == []
    end
  end

  describe "in_namespace?/2" do
    test "returns true for IRI in namespace" do
      iri = ~I<https://w3id.org/elixir-code/structure#Module>
      namespace = "https://w3id.org/elixir-code/structure#"

      assert Helpers.in_namespace?(iri, namespace) == true
    end

    test "returns false for IRI not in namespace" do
      iri = ~I<https://example.org/code#MyApp>
      namespace = "https://w3id.org/elixir-code/structure#"

      assert Helpers.in_namespace?(iri, namespace) == false
    end

    test "returns false for non-IRI values" do
      assert Helpers.in_namespace?(nil, "https://example.org/") == false
      assert Helpers.in_namespace?("string", "https://example.org/") == false
    end
  end
end
