defmodule ElixirOntologies.KnowledgeGraphTest do
  use ExUnit.Case, async: false

  alias ElixirOntologies.KnowledgeGraph

  @moduletag :integration

  # Use a unique temp directory for each test
  setup do
    # Create a unique temp directory for this test
    test_dir = Path.join(System.tmp_dir!(), "kg_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)

    {:ok, test_dir: test_dir}
  end

  describe "availability" do
    test "available?/0 returns true when triple_store is installed" do
      assert KnowledgeGraph.available?() == true
    end
  end

  describe "open/close lifecycle" do
    test "opens and closes a knowledge graph", %{test_dir: test_dir} do
      kg_path = Path.join(test_dir, "test_kg")

      {:ok, store} = KnowledgeGraph.open(kg_path)
      assert is_map(store)
      assert :ok = KnowledgeGraph.close(store)
    end

    test "creates database if missing by default", %{test_dir: test_dir} do
      kg_path = Path.join(test_dir, "new_kg")
      refute File.exists?(kg_path)

      {:ok, store} = KnowledgeGraph.open(kg_path)
      assert File.dir?(kg_path)
      :ok = KnowledgeGraph.close(store)
    end
  end

  describe "loading data" do
    test "load_graph/2 loads an RDF.Graph", %{test_dir: test_dir} do
      kg_path = Path.join(test_dir, "graph_kg")
      {:ok, store} = KnowledgeGraph.open(kg_path)

      # Create a simple graph
      graph =
        RDF.Graph.new([
          {RDF.iri("http://example.org/alice"), RDF.iri("http://example.org/knows"),
           RDF.iri("http://example.org/bob")},
          {RDF.iri("http://example.org/alice"), RDF.type(),
           RDF.iri("http://example.org/Person")}
        ])

      {:ok, count} = KnowledgeGraph.load_graph(store, graph)
      assert count == 2

      :ok = KnowledgeGraph.close(store)
    end

    test "load_string/4 loads Turtle from string", %{test_dir: test_dir} do
      kg_path = Path.join(test_dir, "string_kg")
      {:ok, store} = KnowledgeGraph.open(kg_path)

      ttl = """
      @prefix ex: <http://example.org/> .
      ex:alice ex:knows ex:bob .
      ex:bob ex:knows ex:charlie .
      """

      {:ok, count} = KnowledgeGraph.load_string(store, ttl, :turtle)
      assert count == 2

      :ok = KnowledgeGraph.close(store)
    end

    test "load_files/3 loads multiple files", %{test_dir: test_dir} do
      kg_path = Path.join(test_dir, "files_kg")

      # Create temp TTL files
      ttl1_path = Path.join(test_dir, "file1.ttl")
      ttl2_path = Path.join(test_dir, "file2.ttl")

      File.write!(ttl1_path, """
      @prefix ex: <http://example.org/> .
      ex:a ex:b ex:c .
      """)

      File.write!(ttl2_path, """
      @prefix ex: <http://example.org/> .
      ex:d ex:e ex:f .
      """)

      {:ok, store} = KnowledgeGraph.open(kg_path)
      {:ok, stats} = KnowledgeGraph.load_files(store, [ttl1_path, ttl2_path])

      assert stats.loaded == 2
      assert stats.failed == 0
      assert stats.triples == 2
      assert stats.errors == []

      :ok = KnowledgeGraph.close(store)
    end

    test "load_glob/3 loads files matching pattern", %{test_dir: test_dir} do
      kg_path = Path.join(test_dir, "glob_kg")
      data_dir = Path.join(test_dir, "data")
      File.mkdir_p!(data_dir)

      # Create temp TTL files
      File.write!(Path.join(data_dir, "a.ttl"), """
      @prefix ex: <http://example.org/> .
      ex:a1 ex:b1 ex:c1 .
      """)

      File.write!(Path.join(data_dir, "b.ttl"), """
      @prefix ex: <http://example.org/> .
      ex:a2 ex:b2 ex:c2 .
      """)

      {:ok, store} = KnowledgeGraph.open(kg_path)
      {:ok, stats} = KnowledgeGraph.load_glob(store, Path.join(data_dir, "*.ttl"))

      assert stats.loaded == 2
      assert stats.triples == 2

      :ok = KnowledgeGraph.close(store)
    end
  end

  describe "querying" do
    test "query/3 executes SELECT query", %{test_dir: test_dir} do
      kg_path = Path.join(test_dir, "query_kg")
      {:ok, store} = KnowledgeGraph.open(kg_path)

      # Load test data
      ttl = """
      @prefix ex: <http://example.org/> .
      ex:alice a ex:Person ; ex:name "Alice" .
      ex:bob a ex:Person ; ex:name "Bob" .
      """

      {:ok, _} = KnowledgeGraph.load_string(store, ttl, :turtle)

      # Query
      {:ok, results} =
        KnowledgeGraph.query(store, """
        PREFIX ex: <http://example.org/>
        SELECT ?person ?name
        WHERE {
          ?person a ex:Person ;
                  ex:name ?name .
        }
        """)

      assert length(results) == 2

      # Extract names - handle both RDF.Literal and tuple formats
      names =
        results
        |> Enum.map(fn row ->
          case row["name"] do
            %RDF.Literal{} = lit -> RDF.Literal.value(lit)
            {:literal, _, value} -> value
            other -> to_string(other)
          end
        end)
        |> Enum.sort()

      assert names == ["Alice", "Bob"]

      :ok = KnowledgeGraph.close(store)
    end

    test "query/3 executes ASK query", %{test_dir: test_dir} do
      kg_path = Path.join(test_dir, "ask_kg")
      {:ok, store} = KnowledgeGraph.open(kg_path)

      ttl = """
      @prefix ex: <http://example.org/> .
      ex:alice a ex:Person .
      """

      {:ok, _} = KnowledgeGraph.load_string(store, ttl, :turtle)

      {:ok, exists} =
        KnowledgeGraph.query(store, """
        PREFIX ex: <http://example.org/>
        ASK { ?s a ex:Person }
        """)

      assert exists == true

      {:ok, not_exists} =
        KnowledgeGraph.query(store, """
        PREFIX ex: <http://example.org/>
        ASK { ?s a ex:Animal }
        """)

      assert not_exists == false

      :ok = KnowledgeGraph.close(store)
    end
  end

  describe "stats" do
    # Skip this test until triple_store supports COUNT(*)
    # The executor produces {:count_solutions, false} but only handles {:count, :star, _}
    @tag :skip
    test "stats/1 returns triple count", %{test_dir: test_dir} do
      kg_path = Path.join(test_dir, "stats_kg")
      {:ok, store} = KnowledgeGraph.open(kg_path)

      # Load some data
      graph =
        RDF.Graph.new([
          {RDF.iri("http://example.org/a"), RDF.iri("http://example.org/b"),
           RDF.iri("http://example.org/c")},
          {RDF.iri("http://example.org/d"), RDF.iri("http://example.org/e"),
           RDF.iri("http://example.org/f")}
        ])

      {:ok, _} = KnowledgeGraph.load_graph(store, graph)

      {:ok, stats} = KnowledgeGraph.stats(store)
      assert is_integer(stats.triple_count)
      assert stats.triple_count == 2

      :ok = KnowledgeGraph.close(store)
    end
  end

  describe "export" do
    test "export/1 returns RDF.Graph", %{test_dir: test_dir} do
      kg_path = Path.join(test_dir, "export_kg")
      {:ok, store} = KnowledgeGraph.open(kg_path)

      # Load some data
      original =
        RDF.Graph.new([
          {RDF.iri("http://example.org/x"), RDF.iri("http://example.org/y"),
           RDF.iri("http://example.org/z")}
        ])

      {:ok, _} = KnowledgeGraph.load_graph(store, original)

      {:ok, exported} = KnowledgeGraph.export(store)
      assert RDF.Graph.triple_count(exported) == 1

      :ok = KnowledgeGraph.close(store)
    end
  end
end
