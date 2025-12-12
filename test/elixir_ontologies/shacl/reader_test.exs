defmodule ElixirOntologies.SHACL.ReaderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Reader
  alias ElixirOntologies.SHACL.Model.{NodeShape, SPARQLConstraint}

  describe "parse_shapes/2 with real elixir-shapes.ttl" do
    setup do
      shapes_path = Path.join([File.cwd!(), "priv", "ontologies", "elixir-shapes.ttl"])
      {:ok, graph} = RDF.Turtle.read_file(shapes_path)
      {:ok, shapes} = Reader.parse_shapes(graph)
      %{graph: graph, shapes: shapes}
    end

    test "parses all node shapes from elixir-shapes.ttl", %{shapes: shapes} do
      # elixir-shapes.ttl contains 29 node shapes
      assert length(shapes) >= 25
      assert Enum.all?(shapes, &match?(%NodeShape{}, &1))
    end

    test "all node shapes have IDs", %{shapes: shapes} do
      assert Enum.all?(shapes, fn shape ->
               match?(%RDF.IRI{}, shape.id) || match?(%RDF.BlankNode{}, shape.id)
             end)
    end

    test "all node shapes have target classes or are standalone", %{shapes: shapes} do
      assert Enum.all?(shapes, fn shape ->
               is_list(shape.target_classes)
             end)
    end

    test "parses ModuleShape correctly", %{shapes: shapes} do
      module_shape =
        Enum.find(shapes, fn s ->
          s.id == ~I<https://w3id.org/elixir-code/shapes#ModuleShape>
        end)

      assert module_shape != nil
      assert ~I<https://w3id.org/elixir-code/structure#Module> in module_shape.target_classes
      assert length(module_shape.property_shapes) > 0
    end

    test "parses FunctionShape correctly", %{shapes: shapes} do
      function_shape =
        Enum.find(shapes, fn s ->
          s.id == ~I<https://w3id.org/elixir-code/shapes#FunctionShape>
        end)

      assert function_shape != nil
      assert ~I<https://w3id.org/elixir-code/structure#Function> in function_shape.target_classes
      assert length(function_shape.property_shapes) > 0
    end
  end

  describe "property shape parsing" do
    setup do
      shapes_path = Path.join([File.cwd!(), "priv", "ontologies", "elixir-shapes.ttl"])
      {:ok, graph} = RDF.Turtle.read_file(shapes_path)
      {:ok, shapes} = Reader.parse_shapes(graph)
      %{shapes: shapes}
    end

    test "parses cardinality constraints (minCount, maxCount)", %{shapes: shapes} do
      # Find a property shape with cardinality constraints
      cardinality_shapes =
        shapes
        |> Enum.flat_map(& &1.property_shapes)
        |> Enum.filter(&(&1.min_count != nil or &1.max_count != nil))

      assert length(cardinality_shapes) > 0

      # Verify values are non-negative integers
      Enum.each(cardinality_shapes, fn shape ->
        if shape.min_count, do: assert(is_integer(shape.min_count) and shape.min_count >= 0)
        if shape.max_count, do: assert(is_integer(shape.max_count) and shape.max_count >= 0)
      end)
    end

    test "parses datatype constraints", %{shapes: shapes} do
      datatype_shapes =
        shapes
        |> Enum.flat_map(& &1.property_shapes)
        |> Enum.filter(&(&1.datatype != nil))

      assert length(datatype_shapes) > 0

      # Verify all datatypes are IRIs
      Enum.each(datatype_shapes, fn shape ->
        assert match?(%RDF.IRI{}, shape.datatype)
      end)
    end

    test "parses class constraints", %{shapes: shapes} do
      class_shapes =
        shapes
        |> Enum.flat_map(& &1.property_shapes)
        |> Enum.filter(&(&1.class != nil))

      assert length(class_shapes) > 0

      # Verify all classes are IRIs
      Enum.each(class_shapes, fn shape ->
        assert match?(%RDF.IRI{}, shape.class)
      end)
    end

    test "parses and compiles pattern constraints", %{shapes: shapes} do
      pattern_shapes =
        shapes
        |> Enum.flat_map(& &1.property_shapes)
        |> Enum.filter(&(&1.pattern != nil))

      # elixir-shapes.ttl has 7 regex patterns
      assert length(pattern_shapes) >= 7

      # Verify all patterns are compiled Regex
      Enum.each(pattern_shapes, fn shape ->
        assert match?(%Regex{}, shape.pattern)
      end)
    end

    test "compiled patterns match expected values", %{shapes: shapes} do
      module_shape =
        Enum.find(shapes, fn s ->
          s.id == ~I<https://w3id.org/elixir-code/shapes#ModuleShape>
        end)

      # Find moduleName property shape
      module_name_shape =
        Enum.find(module_shape.property_shapes, fn ps ->
          ps.path == ~I<https://w3id.org/elixir-code/structure#moduleName>
        end)

      assert module_name_shape != nil
      assert module_name_shape.pattern != nil

      # Test the regex works
      assert Regex.match?(module_name_shape.pattern, "MyModule")
      assert Regex.match?(module_name_shape.pattern, "My.Nested.Module")
      refute Regex.match?(module_name_shape.pattern, "invalidModule")
      refute Regex.match?(module_name_shape.pattern, "123Invalid")
    end

    test "parses minLength constraints", %{shapes: shapes} do
      min_length_shapes =
        shapes
        |> Enum.flat_map(& &1.property_shapes)
        |> Enum.filter(&(&1.min_length != nil))

      # Verify values are non-negative integers
      Enum.each(min_length_shapes, fn shape ->
        assert is_integer(shape.min_length) and shape.min_length >= 0
      end)
    end

    test "parses sh:in value constraints as RDF lists", %{shapes: shapes} do
      in_shapes =
        shapes
        |> Enum.flat_map(& &1.property_shapes)
        |> Enum.filter(&(length(&1.in) > 0))

      # elixir-shapes.ttl has multiple sh:in constraints (supervisor strategies, etc.)
      assert length(in_shapes) > 0

      # Verify all in values are lists of RDF terms
      Enum.each(in_shapes, fn shape ->
        assert is_list(shape.in)
        assert length(shape.in) > 0
      end)
    end

    test "parses supervisor strategy enumeration correctly", %{shapes: shapes} do
      supervisor_shape =
        Enum.find(shapes, fn s ->
          s.id == ~I<https://w3id.org/elixir-code/shapes#SupervisorShape>
        end)

      if supervisor_shape do
        strategy_shape =
          Enum.find(supervisor_shape.property_shapes, fn ps ->
            ps.path == ~I<https://w3id.org/elixir-code/otp#supervisorStrategy>
          end)

        if strategy_shape do
          assert length(strategy_shape.in) >= 3

          # Should contain OneForOne, OneForAll, RestForOne
          assert Enum.any?(strategy_shape.in, fn term ->
                   to_string(term) =~ "OneForOne"
                 end)
        end
      end
    end

    test "parses hasValue constraints", %{shapes: shapes} do
      has_value_shapes =
        shapes
        |> Enum.flat_map(& &1.property_shapes)
        |> Enum.filter(&(&1.has_value != nil))

      # Verify all has_value constraints have RDF terms
      Enum.each(has_value_shapes, fn shape ->
        assert shape.has_value != nil
      end)
    end

    test "parses qualified constraints", %{shapes: shapes} do
      qualified_shapes =
        shapes
        |> Enum.flat_map(& &1.property_shapes)
        |> Enum.filter(&(&1.qualified_class != nil or &1.qualified_min_count != nil))

      # Verify qualified constraints structure
      Enum.each(qualified_shapes, fn shape ->
        if shape.qualified_class, do: assert(match?(%RDF.IRI{}, shape.qualified_class))

        if shape.qualified_min_count,
          do: assert(is_integer(shape.qualified_min_count) and shape.qualified_min_count >= 0)
      end)
    end

    test "parses message annotations", %{shapes: shapes} do
      message_shapes =
        shapes
        |> Enum.flat_map(& &1.property_shapes)
        |> Enum.filter(&(&1.message != nil))

      assert length(message_shapes) > 0

      # Verify all messages are strings
      Enum.each(message_shapes, fn shape ->
        assert is_binary(shape.message)
        assert String.length(shape.message) > 0
      end)
    end
  end

  describe "SPARQL constraint parsing" do
    setup do
      shapes_path = Path.join([File.cwd!(), "priv", "ontologies", "elixir-shapes.ttl"])
      {:ok, graph} = RDF.Turtle.read_file(shapes_path)
      {:ok, shapes} = Reader.parse_shapes(graph)
      %{shapes: shapes}
    end

    test "parses SPARQL constraints from shapes", %{shapes: shapes} do
      sparql_shapes =
        shapes
        |> Enum.filter(&(length(&1.sparql_constraints) > 0))

      # elixir-shapes.ttl has 3 SPARQL constraints
      assert length(sparql_shapes) >= 1
    end

    test "SPARQL constraints have required fields", %{shapes: shapes} do
      sparql_constraints =
        shapes
        |> Enum.flat_map(& &1.sparql_constraints)

      Enum.each(sparql_constraints, fn constraint ->
        assert match?(%SPARQLConstraint{}, constraint)
        assert match?(%RDF.IRI{}, constraint.source_shape_id)
        assert is_binary(constraint.select_query)
        assert String.length(constraint.select_query) > 0
      end)
    end

    test "SPARQL queries contain $this placeholder", %{shapes: shapes} do
      sparql_constraints =
        shapes
        |> Enum.flat_map(& &1.sparql_constraints)

      # At least some SPARQL constraints should have $this
      assert Enum.any?(sparql_constraints, fn c ->
               String.contains?(c.select_query, "$this")
             end)
    end

    test "parses SourceLocationShape SPARQL constraint", %{shapes: shapes} do
      source_location_shape =
        Enum.find(shapes, fn s ->
          String.contains?(to_string(s.id), "SourceLocation")
        end)

      if source_location_shape && length(source_location_shape.sparql_constraints) > 0 do
        constraint = hd(source_location_shape.sparql_constraints)
        assert String.contains?(constraint.select_query, "endLine")
        assert String.contains?(constraint.select_query, "startLine")
      end
    end

    test "parses FunctionArityMatchShape SPARQL constraint", %{shapes: shapes} do
      arity_match_shape =
        Enum.find(shapes, fn s ->
          String.contains?(to_string(s.id), "ArityMatch")
        end)

      if arity_match_shape && length(arity_match_shape.sparql_constraints) > 0 do
        constraint = hd(arity_match_shape.sparql_constraints)
        assert String.contains?(constraint.select_query, "arity")
        assert String.contains?(constraint.select_query, "COUNT")
      end
    end
  end

  describe "parse_shapes/2 with minimal test graphs" do
    test "parses simple node shape with target class" do
      graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/Shape1>, ~I<http://www.w3.org/ns/shacl#targetClass>,
           ~I<http://example.org/MyClass>}
        ])

      {:ok, shapes} = Reader.parse_shapes(graph)

      assert length(shapes) == 1
      shape = hd(shapes)
      assert shape.id == ~I<http://example.org/Shape1>
      assert ~I<http://example.org/MyClass> in shape.target_classes
      assert shape.property_shapes == []
      assert shape.sparql_constraints == []
    end

    test "parses node shape with cardinality property constraint" do
      prop_node = RDF.bnode("prop1")

      graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/Shape1>, ~I<http://www.w3.org/ns/shacl#property>, prop_node},
          {prop_node, ~I<http://www.w3.org/ns/shacl#path>, ~I<http://example.org/prop>},
          {prop_node, ~I<http://www.w3.org/ns/shacl#minCount>, RDF.literal(1)},
          {prop_node, ~I<http://www.w3.org/ns/shacl#maxCount>, RDF.literal(1)}
        ])

      {:ok, shapes} = Reader.parse_shapes(graph)

      assert length(shapes) == 1
      shape = hd(shapes)
      assert length(shape.property_shapes) == 1

      prop_shape = hd(shape.property_shapes)
      assert prop_shape.path == ~I<http://example.org/prop>
      assert prop_shape.min_count == 1
      assert prop_shape.max_count == 1
    end

    test "parses node shape with pattern constraint" do
      prop_node = RDF.bnode("prop1")

      graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/Shape1>, ~I<http://www.w3.org/ns/shacl#property>, prop_node},
          {prop_node, ~I<http://www.w3.org/ns/shacl#path>, ~I<http://example.org/name>},
          {prop_node, ~I<http://www.w3.org/ns/shacl#pattern>, RDF.literal("^[A-Z].*")}
        ])

      {:ok, shapes} = Reader.parse_shapes(graph)

      shape = hd(shapes)
      prop_shape = hd(shape.property_shapes)
      assert match?(%Regex{}, prop_shape.pattern)
      assert Regex.match?(prop_shape.pattern, "MyModule")
      refute Regex.match?(prop_shape.pattern, "myModule")
    end

    test "parses node shape with datatype constraint" do
      prop_node = RDF.bnode("prop1")

      graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/Shape1>, ~I<http://www.w3.org/ns/shacl#property>, prop_node},
          {prop_node, ~I<http://www.w3.org/ns/shacl#path>, ~I<http://example.org/age>},
          {prop_node, ~I<http://www.w3.org/ns/shacl#datatype>,
           ~I<http://www.w3.org/2001/XMLSchema#integer>}
        ])

      {:ok, shapes} = Reader.parse_shapes(graph)

      shape = hd(shapes)
      prop_shape = hd(shape.property_shapes)
      assert prop_shape.datatype == ~I<http://www.w3.org/2001/XMLSchema#integer>
    end

    test "parses node shape with class constraint" do
      prop_node = RDF.bnode("prop1")

      graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/Shape1>, ~I<http://www.w3.org/ns/shacl#property>, prop_node},
          {prop_node, ~I<http://www.w3.org/ns/shacl#path>, ~I<http://example.org/parent>},
          {prop_node, ~I<http://www.w3.org/ns/shacl#class>, ~I<http://example.org/Person>}
        ])

      {:ok, shapes} = Reader.parse_shapes(graph)

      shape = hd(shapes)
      prop_shape = hd(shape.property_shapes)
      assert prop_shape.class == ~I<http://example.org/Person>
    end

    test "parses node shape with sh:in enumeration constraint" do
      prop_node = RDF.bnode("prop1")
      list_1 = RDF.bnode("list1")
      list_2 = RDF.bnode("list2")
      list_3 = RDF.bnode("list3")

      graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/Shape1>, ~I<http://www.w3.org/ns/shacl#property>, prop_node},
          {prop_node, ~I<http://www.w3.org/ns/shacl#path>, ~I<http://example.org/status>},
          {prop_node, ~I<http://www.w3.org/ns/shacl#in>, list_1},
          {list_1, RDF.first(), ~I<http://example.org/Active>},
          {list_1, RDF.rest(), list_2},
          {list_2, RDF.first(), ~I<http://example.org/Inactive>},
          {list_2, RDF.rest(), list_3},
          {list_3, RDF.first(), ~I<http://example.org/Pending>},
          {list_3, RDF.rest(), RDF.nil()}
        ])

      {:ok, shapes} = Reader.parse_shapes(graph)

      shape = hd(shapes)
      prop_shape = hd(shape.property_shapes)
      assert length(prop_shape.in) == 3
      assert ~I<http://example.org/Active> in prop_shape.in
      assert ~I<http://example.org/Inactive> in prop_shape.in
      assert ~I<http://example.org/Pending> in prop_shape.in
    end

    test "parses node shape with SPARQL constraint" do
      sparql_node = RDF.bnode("sparql1")

      graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/Shape1>, ~I<http://www.w3.org/ns/shacl#sparql>, sparql_node},
          {sparql_node, ~I<http://www.w3.org/ns/shacl#select>,
           RDF.literal("SELECT $this WHERE { $this ?p ?o }")},
          {sparql_node, ~I<http://www.w3.org/ns/shacl#message>, RDF.literal("Test constraint")}
        ])

      {:ok, shapes} = Reader.parse_shapes(graph)

      shape = hd(shapes)
      assert length(shape.sparql_constraints) == 1

      constraint = hd(shape.sparql_constraints)
      assert constraint.source_shape_id == ~I<http://example.org/Shape1>
      assert constraint.select_query == "SELECT $this WHERE { $this ?p ?o }"
      assert constraint.message == "Test constraint"
    end
  end

  describe "error handling" do
    test "handles empty graph" do
      graph = RDF.Graph.new()
      {:ok, shapes} = Reader.parse_shapes(graph)
      assert shapes == []
    end

    test "handles property shape missing required path" do
      prop_node = RDF.bnode("prop1")

      graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/Shape1>, ~I<http://www.w3.org/ns/shacl#property>, prop_node},
          {prop_node, ~I<http://www.w3.org/ns/shacl#minCount>, RDF.literal(1)}
        ])

      {:error, reason} = Reader.parse_shapes(graph)
      assert reason =~ "Missing required property"
      assert reason =~ "sh:path"
    end

    test "handles invalid regex pattern" do
      prop_node = RDF.bnode("prop1")

      graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/Shape1>, ~I<http://www.w3.org/ns/shacl#property>, prop_node},
          {prop_node, ~I<http://www.w3.org/ns/shacl#path>, ~I<http://example.org/name>},
          {prop_node, ~I<http://www.w3.org/ns/shacl#pattern>, RDF.literal("[")}
        ])

      {:error, reason} = Reader.parse_shapes(graph)
      assert reason =~ "Failed to compile regex pattern"
    end

    test "handles SPARQL constraint missing required select query" do
      sparql_node = RDF.bnode("sparql1")

      graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/Shape1>, ~I<http://www.w3.org/ns/shacl#sparql>, sparql_node},
          {sparql_node, ~I<http://www.w3.org/ns/shacl#message>, RDF.literal("Missing query")}
        ])

      {:error, reason} = Reader.parse_shapes(graph)
      assert reason =~ "Missing required property"
      assert reason =~ "sh:select"
    end
  end
end
