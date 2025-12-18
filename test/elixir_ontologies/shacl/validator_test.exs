defmodule ElixirOntologies.SHACL.ValidatorTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Validator

  doctest ElixirOntologies.SHACL.Validator

  # Helper to create SHACL namespace IRIs
  defp sh(term), do: RDF.iri("http://www.w3.org/ns/shacl##{term}")

  describe "run/3 basic functionality" do
    test "validates conformant graph with no constraints" do
      # Shape targets Module class but has no property constraints
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#ModuleShape>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#ModuleShape>, sh("targetClass"),
           ~I<http://example.org/Module>}
        ])

      # Conformant data: has the target class
      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>}
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      assert report.conforms? == true
      assert report.results == []
    end

    test "detects violations in non-conformant graph" do
      # Shape requires Module to have name property (minCount=1)
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#ModuleShape>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#ModuleShape>, sh("targetClass"),
           ~I<http://example.org/Module>},
          {~I<http://example.org/shapes#ModuleShape>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/name>},
          {RDF.bnode("b1"), sh("minCount"), RDF.XSD.integer(1)}
        ])

      # Non-conformant data: Module missing name
      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>}
          # Missing name property!
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      assert report.conforms? == false
      assert length(report.results) == 1

      [violation] = report.results
      assert violation.severity == :violation
      assert violation.focus_node == ~I<http://example.org/M1>
      assert violation.path == ~I<http://example.org/name>
    end

    test "validates multiple nodes against same shape" do
      # Shape with minCount constraint
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>},
          {~I<http://example.org/shapes#S1>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/name>},
          {RDF.bnode("b1"), sh("minCount"), RDF.XSD.integer(1)}
        ])

      # Data with 3 modules: 2 conformant, 1 non-conformant
      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>},
          {~I<http://example.org/M1>, ~I<http://example.org/name>, "Module1"},
          {~I<http://example.org/M2>, RDF.type(), ~I<http://example.org/Module>},
          {~I<http://example.org/M2>, ~I<http://example.org/name>, "Module2"},
          {~I<http://example.org/M3>, RDF.type(), ~I<http://example.org/Module>}
          # M3 missing name
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      assert report.conforms? == false
      assert length(report.results) == 1

      [violation] = report.results
      assert violation.focus_node == ~I<http://example.org/M3>
    end

    test "validates multiple shapes independently" do
      # Two shapes: ModuleShape and FunctionShape
      shapes_graph =
        RDF.Graph.new([
          # ModuleShape
          {~I<http://example.org/shapes#ModuleShape>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#ModuleShape>, sh("targetClass"),
           ~I<http://example.org/Module>},
          {~I<http://example.org/shapes#ModuleShape>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/moduleName>},
          {RDF.bnode("b1"), sh("minCount"), RDF.XSD.integer(1)},
          # FunctionShape
          {~I<http://example.org/shapes#FunctionShape>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#FunctionShape>, sh("targetClass"),
           ~I<http://example.org/Function>},
          {~I<http://example.org/shapes#FunctionShape>, sh("property"), RDF.bnode("b2")},
          {RDF.bnode("b2"), sh("path"), ~I<http://example.org/arity>},
          {RDF.bnode("b2"), sh("minCount"), RDF.XSD.integer(1)}
        ])

      # Data violates both shapes
      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>},
          # Missing moduleName
          {~I<http://example.org/F1>, RDF.type(), ~I<http://example.org/Function>}
          # Missing arity
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      assert report.conforms? == false
      # Should have 2 violations (one per shape)
      assert length(report.results) == 2
    end

    test "returns conformant report for empty data graph" do
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>}
        ])

      # Empty data graph
      data_graph = RDF.Graph.new([])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      # No target nodes = vacuously valid
      assert report.conforms? == true
      assert report.results == []
    end
  end

  describe "target node selection" do
    test "selects nodes matching single target class" do
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>},
          {~I<http://example.org/shapes#S1>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/name>},
          {RDF.bnode("b1"), sh("minCount"), RDF.XSD.integer(1)}
        ])

      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>},
          # Missing name - should violate
          {~I<http://example.org/M2>, RDF.type(), ~I<http://example.org/Module>},
          # Missing name - should violate
          {~I<http://example.org/F1>, RDF.type(), ~I<http://example.org/Function>}
          # Different class - should NOT be validated
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      # Should have 2 violations (M1 and M2), not F1
      assert length(report.results) == 2

      focus_nodes = Enum.map(report.results, & &1.focus_node) |> Enum.sort()

      assert focus_nodes == Enum.sort([~I<http://example.org/M1>, ~I<http://example.org/M2>])
    end

    test "selects nodes matching any of multiple target classes" do
      # Shape targets both Module and Function classes
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Function>},
          {~I<http://example.org/shapes#S1>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/name>},
          {RDF.bnode("b1"), sh("minCount"), RDF.XSD.integer(1)}
        ])

      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>},
          # Missing name
          {~I<http://example.org/F1>, RDF.type(), ~I<http://example.org/Function>},
          # Missing name
          {~I<http://example.org/C1>, RDF.type(), ~I<http://example.org/Class>}
          # Different class - not validated
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      # Should have 2 violations (M1 and F1), not C1
      assert length(report.results) == 2
    end

    test "handles shapes with no target classes" do
      # Shape without target class (won't match any nodes)
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          # No targetClass specified
          {~I<http://example.org/shapes#S1>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/name>},
          {RDF.bnode("b1"), sh("minCount"), RDF.XSD.integer(1)}
        ])

      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>}
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      # No target nodes = no validation
      assert report.conforms? == true
      assert report.results == []
    end

    test "handles data nodes with no rdf:type" do
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>}
        ])

      # Data without rdf:type
      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, ~I<http://example.org/name>, "SomeName"}
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      # Node without rdf:type is not selected
      assert report.conforms? == true
      assert report.results == []
    end
  end

  describe "constraint validator integration" do
    test "detects cardinality violations" do
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>},
          {~I<http://example.org/shapes#S1>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/name>},
          {RDF.bnode("b1"), sh("minCount"), RDF.XSD.integer(1)},
          {RDF.bnode("b1"), sh("maxCount"), RDF.XSD.integer(1)}
        ])

      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>},
          {~I<http://example.org/M1>, ~I<http://example.org/name>, "Name1"},
          {~I<http://example.org/M1>, ~I<http://example.org/name>, "Name2"}
          # Too many names!
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      assert report.conforms? == false
      assert length(report.results) == 1

      [violation] = report.results

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#MaxCountConstraintComponent>
    end

    test "detects type violations (datatype)" do
      xsd_string = ~I<http://www.w3.org/2001/XMLSchema#string>

      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>},
          {~I<http://example.org/shapes#S1>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/name>},
          {RDF.bnode("b1"), sh("datatype"), xsd_string}
        ])

      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>},
          {~I<http://example.org/M1>, ~I<http://example.org/name>,
           ~I<http://example.org/NotAString>}
          # IRI instead of string literal
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      assert report.conforms? == false
      assert length(report.results) == 1

      [violation] = report.results

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#DatatypeConstraintComponent>
    end

    test "detects string pattern violations" do
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>},
          {~I<http://example.org/shapes#S1>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/name>},
          {RDF.bnode("b1"), sh("pattern"), "^[A-Z]"}
          # Must start with uppercase
        ])

      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>},
          {~I<http://example.org/M1>, ~I<http://example.org/name>, "badName"}
          # Starts with lowercase!
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      assert report.conforms? == false
      assert length(report.results) == 1

      [violation] = report.results

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#PatternConstraintComponent>
    end

    test "detects value enumeration violations" do
      strategy_one_for_one = ~I<http://example.org/OneForOne>
      strategy_one_for_all = ~I<http://example.org/OneForAll>
      invalid_strategy = ~I<http://example.org/InvalidStrategy>

      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Supervisor>},
          {~I<http://example.org/shapes#S1>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/strategy>},
          {RDF.bnode("b1"), sh("in"), RDF.bnode("list")},
          # Create RDF list for sh:in
          {RDF.bnode("list"), RDF.first(), strategy_one_for_one},
          {RDF.bnode("list"), RDF.rest(), RDF.bnode("list2")},
          {RDF.bnode("list2"), RDF.first(), strategy_one_for_all},
          {RDF.bnode("list2"), RDF.rest(), RDF.nil()}
        ])

      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/S1>, RDF.type(), ~I<http://example.org/Supervisor>},
          {~I<http://example.org/S1>, ~I<http://example.org/strategy>, invalid_strategy}
          # Not in allowed list!
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      assert report.conforms? == false
      assert length(report.results) == 1

      [violation] = report.results

      assert violation.details.constraint_component ==
               ~I<http://www.w3.org/ns/shacl#InConstraintComponent>
    end

    test "detects multiple constraint violations on same property" do
      xsd_string = ~I<http://www.w3.org/2001/XMLSchema#string>

      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>},
          {~I<http://example.org/shapes#S1>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/name>},
          {RDF.bnode("b1"), sh("minCount"), RDF.XSD.integer(1)},
          {RDF.bnode("b1"), sh("datatype"), xsd_string},
          {RDF.bnode("b1"), sh("pattern"), "^[A-Z]"},
          {RDF.bnode("b1"), sh("minLength"), RDF.XSD.integer(3)}
        ])

      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>},
          {~I<http://example.org/M1>, ~I<http://example.org/name>,
           RDF.Literal.new("ab", datatype: xsd_string)}
          # Violates pattern (lowercase) and minLength (2 < 3)
        ])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      assert report.conforms? == false
      # Should have 2 violations (pattern + minLength)
      assert length(report.results) == 2

      constraint_components =
        Enum.map(report.results, & &1.details.constraint_component) |> Enum.sort()

      assert ~I<http://www.w3.org/ns/shacl#PatternConstraintComponent> in constraint_components

      assert ~I<http://www.w3.org/ns/shacl#MinLengthConstraintComponent> in constraint_components
    end
  end

  describe "parallel validation" do
    test "parallel validation produces same results as sequential" do
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>},
          {~I<http://example.org/shapes#S1>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/name>},
          {RDF.bnode("b1"), sh("minCount"), RDF.XSD.integer(1)}
        ])

      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>},
          {~I<http://example.org/M1>, ~I<http://example.org/name>, "Module1"},
          {~I<http://example.org/M2>, RDF.type(), ~I<http://example.org/Module>}
          # M2 missing name
        ])

      {:ok, report_parallel} = Validator.run(data_graph, shapes_graph, parallel: true)
      {:ok, report_sequential} = Validator.run(data_graph, shapes_graph, parallel: false)

      # Same conformance status
      assert report_parallel.conforms? == report_sequential.conforms?

      # Same number of violations
      assert length(report_parallel.results) == length(report_sequential.results)

      # Same violation details (order may differ)
      parallel_sorted = Enum.sort_by(report_parallel.results, &{&1.focus_node, &1.path})
      sequential_sorted = Enum.sort_by(report_sequential.results, &{&1.focus_node, &1.path})
      assert parallel_sorted == sequential_sorted
    end

    test "respects max_concurrency option" do
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>}
        ])

      data_graph = RDF.Graph.new([])

      # Should not crash with max_concurrency option
      {:ok, report} = Validator.run(data_graph, shapes_graph, parallel: true, max_concurrency: 2)

      assert report.conforms? == true
    end

    test "respects timeout option" do
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>}
        ])

      data_graph = RDF.Graph.new([])

      # Should not crash with timeout option
      {:ok, report} = Validator.run(data_graph, shapes_graph, parallel: true, timeout: 10_000)

      assert report.conforms? == true
    end
  end

  describe "error handling" do
    test "returns error for invalid shapes graph" do
      # Invalid shapes graph (missing required properties)
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")}
          # Missing required properties for valid shape
        ])

      data_graph = RDF.Graph.new([])

      # Reader should successfully parse (empty target_classes is valid)
      {:ok, report} = Validator.run(data_graph, shapes_graph)
      assert report.conforms? == true
    end

    test "handles empty shapes graph" do
      shapes_graph = RDF.Graph.new([])
      data_graph = RDF.Graph.new([])

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      # No shapes = vacuously valid
      assert report.conforms? == true
      assert report.results == []
    end

    test "handles large number of nodes" do
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/shapes#S1>, RDF.type(), sh("NodeShape")},
          {~I<http://example.org/shapes#S1>, sh("targetClass"), ~I<http://example.org/Module>},
          {~I<http://example.org/shapes#S1>, sh("property"), RDF.bnode("b1")},
          {RDF.bnode("b1"), sh("path"), ~I<http://example.org/name>},
          {RDF.bnode("b1"), sh("minCount"), RDF.XSD.integer(1)}
        ])

      # Generate 50 modules with names
      module_triples =
        Enum.flat_map(1..50, fn i ->
          module_iri = RDF.iri("http://example.org/M#{i}")

          [
            {module_iri, RDF.type(), ~I<http://example.org/Module>},
            {module_iri, ~I<http://example.org/name>, "Module#{i}"}
          ]
        end)

      data_graph = RDF.Graph.new(module_triples)

      {:ok, report} = Validator.run(data_graph, shapes_graph)

      # All conformant
      assert report.conforms? == true
      assert report.results == []
    end
  end
end
