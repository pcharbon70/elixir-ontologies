defmodule ElixirOntologies.GraphTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Graph
  alias ElixirOntologies.NS.Structure

  doctest ElixirOntologies.Graph

  @subject_a ~I<https://example.org/code#MyApp.ModuleA>
  @subject_b ~I<https://example.org/code#MyApp.ModuleB>
  @subject_c ~I<https://example.org/code#MyApp.ModuleC>

  # ===========================================================================
  # Graph Creation Tests
  # ===========================================================================

  describe "new/0" do
    test "creates an empty graph" do
      graph = Graph.new()

      assert %Graph{} = graph
      assert graph.graph != nil
      assert Graph.empty?(graph)
    end

    test "creates graph with nil base_iri" do
      graph = Graph.new()
      assert graph.base_iri == nil
    end

    test "creates graph with zero statements" do
      graph = Graph.new()
      assert Graph.statement_count(graph) == 0
    end
  end

  describe "new/1" do
    test "accepts base_iri as string" do
      graph = Graph.new(base_iri: "https://example.org/code#")

      assert graph.base_iri == ~I<https://example.org/code#>
    end

    test "accepts base_iri as IRI" do
      iri = ~I<https://example.org/code#>
      graph = Graph.new(base_iri: iri)

      assert graph.base_iri == iri
    end

    test "applies default prefixes from NS.prefix_map/0" do
      graph = Graph.new()

      # Check that the prefixes were applied to the underlying RDF.Graph
      assert graph.graph.prefixes != nil
    end

    test "accepts custom prefixes" do
      custom_prefixes = [ex: "https://example.org/"]
      graph = Graph.new(prefixes: custom_prefixes)

      assert graph.graph.prefixes != nil
    end

    test "accepts graph name for named graphs" do
      name = ~I<https://example.org/graphs/my-graph>
      graph = Graph.new(name: name)

      assert graph.graph.name == name
    end

    test "accepts multiple options" do
      graph =
        Graph.new(
          base_iri: "https://example.org/",
          name: ~I<https://example.org/graphs/test>
        )

      assert graph.base_iri == ~I<https://example.org/>
      assert graph.graph.name == ~I<https://example.org/graphs/test>
    end
  end

  # ===========================================================================
  # Adding Statements Tests
  # ===========================================================================

  describe "add/2" do
    test "adds a single triple to the graph" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      assert Graph.statement_count(graph) == 1
    end

    test "adds multiple triples for the same subject" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> Graph.add({@subject_a, Structure.moduleName(), "MyApp.ModuleA"})

      assert Graph.statement_count(graph) == 2
    end

    test "adds triples for different subjects" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> Graph.add({@subject_b, RDF.type(), Structure.Module})

      assert Graph.statement_count(graph) == 2
    end

    test "adds RDF.Description" do
      description =
        RDF.description(@subject_a)
        |> RDF.Description.add({RDF.type(), Structure.Module})

      graph =
        Graph.new()
        |> Graph.add(description)

      assert Graph.statement_count(graph) == 1
    end

    test "returns updated graph struct" do
      original = Graph.new()
      updated = Graph.add(original, {@subject_a, RDF.type(), Structure.Module})

      # Original is unchanged (immutable)
      assert Graph.empty?(original)
      assert not Graph.empty?(updated)
    end
  end

  describe "add_all/2" do
    test "adds list of triples" do
      statements = [
        {@subject_a, RDF.type(), Structure.Module},
        {@subject_a, Structure.moduleName(), "MyApp.ModuleA"},
        {@subject_b, RDF.type(), Structure.Module}
      ]

      graph =
        Graph.new()
        |> Graph.add_all(statements)

      assert Graph.statement_count(graph) == 3
    end

    test "adds empty list without error" do
      graph =
        Graph.new()
        |> Graph.add_all([])

      assert Graph.empty?(graph)
    end

    test "adds RDF.Graph" do
      rdf_graph =
        RDF.Graph.new()
        |> RDF.Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> RDF.Graph.add({@subject_b, RDF.type(), Structure.Module})

      graph =
        Graph.new()
        |> Graph.add_all(rdf_graph)

      assert Graph.statement_count(graph) == 2
    end
  end

  # ===========================================================================
  # Merging Tests
  # ===========================================================================

  describe "merge/2" do
    test "merges two ElixirOntologies.Graph structs" do
      g1 =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      g2 =
        Graph.new()
        |> Graph.add({@subject_b, RDF.type(), Structure.Module})

      merged = Graph.merge(g1, g2)

      assert Graph.statement_count(merged) == 2
    end

    test "merges RDF.Graph into ElixirOntologies.Graph" do
      g1 =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      rdf_graph =
        RDF.Graph.new()
        |> RDF.Graph.add({@subject_b, RDF.type(), Structure.Module})

      merged = Graph.merge(g1, rdf_graph)

      assert Graph.statement_count(merged) == 2
    end

    test "preserves base_iri from first graph" do
      g1 = Graph.new(base_iri: "https://example.org/")
      g2 = Graph.new(base_iri: "https://other.org/")

      merged = Graph.merge(g1, g2)

      assert merged.base_iri == ~I<https://example.org/>
    end

    test "handles overlapping subjects" do
      g1 =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      g2 =
        Graph.new()
        |> Graph.add({@subject_a, Structure.moduleName(), "MyApp.ModuleA"})

      merged = Graph.merge(g1, g2)

      # Both statements for same subject should be present
      assert Graph.statement_count(merged) == 2
    end
  end

  # ===========================================================================
  # Query Operations Tests
  # ===========================================================================

  describe "subjects/1" do
    test "returns empty MapSet for empty graph" do
      graph = Graph.new()
      assert Graph.subjects(graph) == MapSet.new()
    end

    test "returns all unique subjects as MapSet" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> Graph.add({@subject_a, Structure.moduleName(), "A"})
        |> Graph.add({@subject_b, RDF.type(), Structure.Module})
        |> Graph.add({@subject_c, RDF.type(), Structure.Module})

      subjects = Graph.subjects(graph)

      assert MapSet.size(subjects) == 3
      assert MapSet.member?(subjects, @subject_a)
      assert MapSet.member?(subjects, @subject_b)
      assert MapSet.member?(subjects, @subject_c)
    end
  end

  describe "describe/2" do
    test "returns description for existing subject" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> Graph.add({@subject_a, Structure.moduleName(), "MyApp.ModuleA"})

      description = Graph.describe(graph, @subject_a)

      assert %RDF.Description{} = description
      assert RDF.Description.statement_count(description) == 2
    end

    test "returns empty description for non-existent subject" do
      graph = Graph.new()

      description = Graph.describe(graph, @subject_a)
      assert RDF.Description.empty?(description)
    end

    test "returns only statements for specified subject" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> Graph.add({@subject_b, RDF.type(), Structure.Module})

      description = Graph.describe(graph, @subject_a)

      assert RDF.Description.statement_count(description) == 1
    end
  end

  # ===========================================================================
  # SPARQL Query Tests
  # ===========================================================================

  describe "query/2" do
    test "executes SPARQL query when library is available" do
      # SPARQL is available in this project
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      result = Graph.query(graph, "SELECT ?s WHERE { ?s a struct:Module }")

      assert {:ok, %SPARQL.Query.Result{}} = result
    end

    test "returns results for matching query" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> Graph.add({@subject_b, RDF.type(), Structure.Module})

      {:ok, result} = Graph.query(graph, "SELECT ?s WHERE { ?s a struct:Module }")

      # Should return both subjects
      assert length(result.results) == 2
    end

    test "returns empty results for non-matching query" do
      graph = Graph.new()

      {:ok, result} = Graph.query(graph, "SELECT ?s WHERE { ?s a struct:Module }")

      assert result.results == []
    end

    test "uses default prefixes from NS.prefix_map/0" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      # This query uses the 'struct' prefix which should be available
      result = Graph.query(graph, "SELECT ?s WHERE { ?s a struct:Module }")

      assert {:ok, _} = result
    end

    test "accepts custom prefixes option" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, ~I<https://custom.org/type>, "value"})

      result =
        Graph.query(
          graph,
          "SELECT ?s WHERE { ?s custom:type ?o }",
          prefixes: [custom: "https://custom.org/"]
        )

      assert {:ok, %SPARQL.Query.Result{}} = result
    end
  end

  # ===========================================================================
  # Utility Functions Tests
  # ===========================================================================

  describe "statement_count/1" do
    test "returns 0 for empty graph" do
      assert Graph.statement_count(Graph.new()) == 0
    end

    test "returns correct count after adding statements" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> Graph.add({@subject_a, Structure.moduleName(), "A"})
        |> Graph.add({@subject_b, RDF.type(), Structure.Module})

      assert Graph.statement_count(graph) == 3
    end
  end

  describe "empty?/1" do
    test "returns true for new graph" do
      assert Graph.empty?(Graph.new())
    end

    test "returns false after adding statements" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      refute Graph.empty?(graph)
    end
  end

  describe "to_rdf_graph/1" do
    test "returns underlying RDF.Graph" do
      graph = Graph.new()
      rdf_graph = Graph.to_rdf_graph(graph)

      assert %RDF.Graph{} = rdf_graph
    end

    test "returns graph with all statements" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> Graph.add({@subject_b, RDF.type(), Structure.Module})

      rdf_graph = Graph.to_rdf_graph(graph)

      assert RDF.Graph.statement_count(rdf_graph) == 2
    end
  end

  describe "from_rdf_graph/2" do
    test "creates Graph from RDF.Graph" do
      rdf_graph =
        RDF.Graph.new()
        |> RDF.Graph.add({@subject_a, RDF.type(), Structure.Module})

      graph = Graph.from_rdf_graph(rdf_graph)

      assert %Graph{} = graph
      assert Graph.statement_count(graph) == 1
    end

    test "accepts base_iri option" do
      rdf_graph = RDF.Graph.new()
      graph = Graph.from_rdf_graph(rdf_graph, base_iri: "https://example.org/")

      assert graph.base_iri == ~I<https://example.org/>
    end
  end

  # ===========================================================================
  # Serialization Tests
  # ===========================================================================

  describe "to_turtle/1" do
    test "serializes empty graph to valid Turtle" do
      graph = Graph.new()
      {:ok, turtle} = Graph.to_turtle(graph)

      assert is_binary(turtle)
      # Empty graph should still have prefix declarations
      assert String.contains?(turtle, "@prefix")
    end

    test "serializes graph with statements" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> Graph.add({@subject_a, Structure.moduleName(), "MyApp.ModuleA"})

      {:ok, turtle} = Graph.to_turtle(graph)

      # Should contain the serialized triple using prefixes
      assert String.contains?(turtle, "struct:Module")
      assert String.contains?(turtle, "MyApp.ModuleA")
    end

    test "includes ontology prefixes in output" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      {:ok, turtle} = Graph.to_turtle(graph)

      # Should have our ontology prefixes
      assert String.contains?(turtle, "@prefix struct:")
      assert String.contains?(turtle, "@prefix core:")
      assert String.contains?(turtle, "@prefix rdf:")
    end

    test "produces parseable Turtle" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> Graph.add({@subject_a, Structure.moduleName(), "MyApp.ModuleA"})

      {:ok, turtle} = Graph.to_turtle(graph)

      # Should be parseable back
      {:ok, parsed_graph} = RDF.Turtle.read_string(turtle)
      assert RDF.Graph.statement_count(parsed_graph) == 2
    end
  end

  describe "to_turtle/2" do
    test "accepts custom prefixes" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      custom_prefixes = [ex: "https://example.org/"]
      {:ok, turtle} = Graph.to_turtle(graph, prefixes: custom_prefixes)

      assert String.contains?(turtle, "@prefix ex:")
    end

    test "accepts base IRI option" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      {:ok, turtle} = Graph.to_turtle(graph, base: "https://example.org/code#")

      assert String.contains?(turtle, "@base")
    end

    test "uses graph base_iri by default" do
      graph =
        Graph.new(base_iri: "https://example.org/code#")
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      {:ok, turtle} = Graph.to_turtle(graph, [])

      assert String.contains?(turtle, "@base")
    end
  end

  describe "to_turtle!/1" do
    test "returns turtle string on success" do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      turtle = Graph.to_turtle!(graph)

      assert is_binary(turtle)
      assert String.contains?(turtle, "struct:Module")
    end
  end

  describe "save/2 and save/3" do
    @tag :tmp_dir
    test "saves graph to file", %{tmp_dir: tmp_dir} do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      path = Path.join(tmp_dir, "test_graph.ttl")
      assert :ok = Graph.save(graph, path)

      # Verify file was created and contains valid Turtle
      assert File.exists?(path)
      content = File.read!(path)
      assert String.contains?(content, "struct:Module")
    end

    @tag :tmp_dir
    test "saves with format option", %{tmp_dir: tmp_dir} do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      path = Path.join(tmp_dir, "test_graph.ttl")
      assert :ok = Graph.save(graph, path, format: :turtle)

      assert File.exists?(path)
    end

    @tag :tmp_dir
    test "returns error for unsupported format", %{tmp_dir: tmp_dir} do
      graph = Graph.new()
      path = Path.join(tmp_dir, "test_graph.xml")

      assert {:error, {:unsupported_format, :rdf_xml}} = Graph.save(graph, path, format: :rdf_xml)
    end

    @tag :tmp_dir
    test "saves with custom prefixes", %{tmp_dir: tmp_dir} do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      path = Path.join(tmp_dir, "test_graph.ttl")
      custom_prefixes = [ex: "https://example.org/", struct: Structure.__base_iri__()]
      assert :ok = Graph.save(graph, path, prefixes: custom_prefixes)

      content = File.read!(path)
      assert String.contains?(content, "@prefix ex:")
    end

    test "returns error for invalid path" do
      graph = Graph.new()

      {:error, reason} = Graph.save(graph, "/nonexistent/directory/file.ttl")
      assert reason == :enoent
    end
  end

  describe "save!/2" do
    @tag :tmp_dir
    test "saves graph without error", %{tmp_dir: tmp_dir} do
      graph =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})

      path = Path.join(tmp_dir, "test_graph.ttl")
      assert :ok = Graph.save!(graph, path)

      assert File.exists?(path)
    end

    test "raises on error" do
      graph = Graph.new()

      assert_raise RuntimeError, ~r/Failed to save graph/, fn ->
        Graph.save!(graph, "/nonexistent/directory/file.ttl")
      end
    end
  end

  describe "round-trip serialization" do
    @tag :tmp_dir
    test "save and load produces equivalent graph", %{tmp_dir: tmp_dir} do
      original =
        Graph.new()
        |> Graph.add({@subject_a, RDF.type(), Structure.Module})
        |> Graph.add({@subject_a, Structure.moduleName(), "MyApp.ModuleA"})
        |> Graph.add({@subject_b, RDF.type(), Structure.Module})

      path = Path.join(tmp_dir, "roundtrip.ttl")
      :ok = Graph.save(original, path)

      # Load and verify
      {:ok, loaded_rdf} = RDF.Turtle.read_file(path)
      loaded = Graph.from_rdf_graph(loaded_rdf)

      assert Graph.statement_count(loaded) == Graph.statement_count(original)
    end
  end
end
