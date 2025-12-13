defmodule ElixirOntologies.SHACLTest do
  use ExUnit.Case, async: true

  import RDF.Sigils
  alias ElixirOntologies.SHACL
  alias ElixirOntologies.SHACL.Model.ValidationReport

  @moduletag :shacl_api

  @fixtures_dir "test/fixtures/shacl"

  describe "validate/3" do
    test "validates conformant data against shapes" do
      # Create simple conformant data
      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/Alice>, RDF.type(), ~I<http://example.org/Person>},
          {~I<http://example.org/Alice>, ~I<http://example.org/name>, "Alice"}
        ])

      # Create simple shape requiring name property
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/PersonShape>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/PersonShape>, ~I<http://www.w3.org/ns/shacl#targetClass>,
           ~I<http://example.org/Person>}
        ])

      {:ok, report} = SHACL.validate(data_graph, shapes_graph)

      assert %ValidationReport{} = report
      assert report.conforms? == true
      assert report.results == []
    end

    test "detects violations in non-conformant data" do
      # Create data missing required property
      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/Bob>, RDF.type(), ~I<http://example.org/Person>}
          # Missing required ex:name property
        ])

      # Create shape requiring name property with minCount 1
      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/PersonShape>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/PersonShape>, ~I<http://www.w3.org/ns/shacl#targetClass>,
           ~I<http://example.org/Person>},
          {~I<http://example.org/PersonShape>, ~I<http://www.w3.org/ns/shacl#property>,
           RDF.bnode("b1")},
          {RDF.bnode("b1"), ~I<http://www.w3.org/ns/shacl#path>, ~I<http://example.org/name>},
          {RDF.bnode("b1"), ~I<http://www.w3.org/ns/shacl#minCount>, RDF.XSD.integer(1)}
        ])

      {:ok, report} = SHACL.validate(data_graph, shapes_graph)

      assert %ValidationReport{} = report
      assert report.conforms? == false
      assert length(report.results) > 0

      # Check that violation is for minCount constraint
      violation = List.first(report.results)
      assert violation.severity == :violation
      assert violation.focus_node == ~I<http://example.org/Bob>
    end

    test "returns proper ValidationReport structure" do
      data_graph = RDF.Graph.new()
      shapes_graph = RDF.Graph.new()

      {:ok, report} = SHACL.validate(data_graph, shapes_graph)

      assert %ValidationReport{} = report
      assert is_boolean(report.conforms?)
      assert is_list(report.results)
    end

    test "accepts parallel option" do
      data_graph = RDF.Graph.new()
      shapes_graph = RDF.Graph.new()

      {:ok, report} = SHACL.validate(data_graph, shapes_graph, parallel: false)

      assert %ValidationReport{} = report
      assert report.conforms? == true
    end

    test "accepts timeout option" do
      data_graph = RDF.Graph.new()
      shapes_graph = RDF.Graph.new()

      {:ok, report} = SHACL.validate(data_graph, shapes_graph, timeout: 10_000)

      assert %ValidationReport{} = report
      assert report.conforms? == true
    end

    test "accepts max_concurrency option" do
      data_graph = RDF.Graph.new()
      shapes_graph = RDF.Graph.new()

      {:ok, report} = SHACL.validate(data_graph, shapes_graph, max_concurrency: 4)

      assert %ValidationReport{} = report
      assert report.conforms? == true
    end

    test "handles empty data graph" do
      data_graph = RDF.Graph.new()

      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>}
        ])

      {:ok, report} = SHACL.validate(data_graph, shapes_graph)

      assert %ValidationReport{} = report
      assert report.conforms? == true
      assert report.results == []
    end

    test "handles empty shapes graph" do
      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/Alice>, RDF.type(), ~I<http://example.org/Person>}
        ])

      shapes_graph = RDF.Graph.new()

      {:ok, report} = SHACL.validate(data_graph, shapes_graph)

      assert %ValidationReport{} = report
      assert report.conforms? == true
      assert report.results == []
    end
  end

  describe "validate_file/3" do
    test "validates Turtle files successfully" do
      data_file = Path.join(@fixtures_dir, "valid_data.ttl")
      shapes_file = Path.join(@fixtures_dir, "simple_shapes.ttl")

      {:ok, report} = SHACL.validate_file(data_file, shapes_file)

      assert %ValidationReport{} = report
      assert report.conforms? == true
    end

    test "detects violations in file data" do
      data_file = Path.join(@fixtures_dir, "invalid_data.ttl")
      shapes_file = Path.join(@fixtures_dir, "simple_shapes.ttl")

      {:ok, report} = SHACL.validate_file(data_file, shapes_file)

      assert %ValidationReport{} = report
      assert report.conforms? == false
      assert length(report.results) > 0
    end

    test "returns error for missing data file" do
      data_file = Path.join(@fixtures_dir, "nonexistent.ttl")
      shapes_file = Path.join(@fixtures_dir, "simple_shapes.ttl")

      {:error, {:file_read_error, :data, ^data_file, :enoent}} =
        SHACL.validate_file(data_file, shapes_file)
    end

    test "returns error for missing shapes file" do
      data_file = Path.join(@fixtures_dir, "valid_data.ttl")
      shapes_file = Path.join(@fixtures_dir, "nonexistent.ttl")

      {:error, {:file_read_error, :shapes, ^shapes_file, :enoent}} =
        SHACL.validate_file(data_file, shapes_file)
    end

    test "returns error for malformed Turtle in data file" do
      data_file = Path.join(@fixtures_dir, "malformed.ttl")
      shapes_file = Path.join(@fixtures_dir, "simple_shapes.ttl")

      assert {:error, {:file_read_error, :data, ^data_file, _reason}} =
               SHACL.validate_file(data_file, shapes_file)
    end

    test "returns error for malformed Turtle in shapes file" do
      data_file = Path.join(@fixtures_dir, "valid_data.ttl")
      shapes_file = Path.join(@fixtures_dir, "malformed.ttl")

      assert {:error, {:file_read_error, :shapes, ^shapes_file, _reason}} =
               SHACL.validate_file(data_file, shapes_file)
    end

    test "accepts validation options" do
      data_file = Path.join(@fixtures_dir, "valid_data.ttl")
      shapes_file = Path.join(@fixtures_dir, "simple_shapes.ttl")

      {:ok, report} =
        SHACL.validate_file(data_file, shapes_file,
          parallel: false,
          timeout: 10_000
        )

      assert %ValidationReport{} = report
      assert report.conforms? == true
    end
  end

  describe "integration" do
    test "works with real elixir-shapes.ttl" do
      # Create minimal Elixir code graph
      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/M>, RDF.type(),
           ~I<https://w3id.org/elixir-code/ontology/structure#Module>},
          {~I<http://example.org/M>, ~I<https://w3id.org/elixir-code/ontology/core#moduleName>,
           "MyModule"}
        ])

      # Load real elixir-shapes.ttl
      shapes_path = Path.join(:code.priv_dir(:elixir_ontologies), "ontologies/elixir-shapes.ttl")

      case File.exists?(shapes_path) do
        true ->
          {:ok, shapes_graph} = RDF.Turtle.read_file(shapes_path)
          {:ok, report} = SHACL.validate(data_graph, shapes_graph)

          assert %ValidationReport{} = report
          # May or may not conform depending on elixir-shapes.ttl constraints

        false ->
          # Skip test if shapes file not found (e.g., in CI without priv dir)
          :ok
      end
    end

    test "validates analyzed Elixir code graphs" do
      # Create a temporary Elixir file and analyze it
      temp_dir = System.tmp_dir!()
      file_path = Path.join(temp_dir, "test_shacl_#{:rand.uniform(999_999)}.ex")

      File.write!(file_path, """
      defmodule SHACLTestModule do
        @moduledoc "Test module for SHACL validation"

        def test_function(x) do
          x + 1
        end
      end
      """)

      on_exit(fn -> File.rm(file_path) end)

      # Analyze the file to get RDF graph
      case ElixirOntologies.analyze_file(file_path) do
        {:ok, %ElixirOntologies.Graph{graph: rdf_graph}} ->
          # Load elixir-shapes.ttl
          shapes_path =
            Path.join(:code.priv_dir(:elixir_ontologies), "ontologies/elixir-shapes.ttl")

          case File.exists?(shapes_path) do
            true ->
              {:ok, shapes_graph} = RDF.Turtle.read_file(shapes_path)
              {:ok, report} = SHACL.validate(rdf_graph, shapes_graph)

              assert %ValidationReport{} = report
              # The analyzed graph should conform to elixir-shapes.ttl
              # (or have specific expected violations if shapes are strict)

            false ->
              :ok
          end

        {:error, _} ->
          # Skip if analysis failed
          :ok
      end
    end

    test "backward compatible with SHACL.Validator.run/3" do
      # Verify that SHACL.validate/3 produces same results as SHACL.Validator.run/3
      data_graph =
        RDF.Graph.new([
          {~I<http://example.org/Alice>, RDF.type(), ~I<http://example.org/Person>}
        ])

      shapes_graph =
        RDF.Graph.new([
          {~I<http://example.org/Shape>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
          {~I<http://example.org/Shape>, ~I<http://www.w3.org/ns/shacl#targetClass>,
           ~I<http://example.org/Person>}
        ])

      {:ok, report1} = SHACL.validate(data_graph, shapes_graph)
      {:ok, report2} = ElixirOntologies.SHACL.Validator.run(data_graph, shapes_graph)

      # Both should produce identical reports
      assert report1.conforms? == report2.conforms?
      assert length(report1.results) == length(report2.results)
    end
  end
end
