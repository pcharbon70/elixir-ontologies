defmodule ElixirOntologies.KnowledgeGraph do
  @moduledoc """
  Knowledge graph operations using the embedded triple store.

  This module provides a convenient API for loading RDF data into a persistent
  triple store and querying it with SPARQL. It wraps the optional `triple_store`
  dependency.

  ## Requirements

  This module requires the `triple_store` dependency. Add it to your mix.exs:

      {:triple_store, path: "../triple_store"}

  ## Usage

      # Open a knowledge graph
      {:ok, kg} = ElixirOntologies.KnowledgeGraph.open("./my_knowledge_graph")

      # Load Turtle files
      {:ok, stats} = ElixirOntologies.KnowledgeGraph.load_files(kg, ["ontology.ttl", "data.ttl"])

      # Query with SPARQL
      {:ok, results} = ElixirOntologies.KnowledgeGraph.query(kg, "SELECT ?s WHERE { ?s a :Module }")

      # Close when done
      :ok = ElixirOntologies.KnowledgeGraph.close(kg)

  ## Glob Pattern Support

      # Load all TTL files from a directory
      {:ok, stats} = ElixirOntologies.KnowledgeGraph.load_glob(kg, "ontologies/**/*.ttl")
  """

  @type store :: map()
  @type load_result :: %{
          loaded: non_neg_integer(),
          failed: non_neg_integer(),
          triples: non_neg_integer(),
          errors: [{:error, Path.t(), term()}]
        }

  # ===========================================================================
  # Availability Check
  # ===========================================================================

  @doc """
  Checks if the triple_store dependency is available.

  Returns `true` if triple_store is installed and can be used.

  ## Examples

      iex> ElixirOntologies.KnowledgeGraph.available?()
      true  # or false if triple_store is not installed
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(TripleStore)
  end

  @doc """
  Ensures triple_store is available, raising an error if not.
  """
  @spec ensure_available!() :: :ok
  def ensure_available! do
    unless available?() do
      raise """
      The triple_store dependency is not available.

      To use KnowledgeGraph features, add triple_store to your dependencies:

          {:triple_store, path: "../triple_store"}

      Then run: mix deps.get
      """
    end

    :ok
  end

  # ===========================================================================
  # Store Lifecycle
  # ===========================================================================

  @doc """
  Opens or creates a knowledge graph at the given path.

  ## Options

    * `:create_if_missing` - Create the database if it doesn't exist (default: true)

  ## Examples

      {:ok, kg} = ElixirOntologies.KnowledgeGraph.open("./knowledge_graph")

      # With options
      {:ok, kg} = ElixirOntologies.KnowledgeGraph.open("./kg", create_if_missing: false)
  """
  @spec open(Path.t(), keyword()) :: {:ok, store()} | {:error, term()}
  def open(path, opts \\ []) do
    ensure_available!()
    TripleStore.open(path, opts)
  end

  @doc """
  Closes the knowledge graph and releases resources.

  ## Examples

      :ok = ElixirOntologies.KnowledgeGraph.close(kg)
  """
  @spec close(store()) :: :ok | {:error, term()}
  def close(store) do
    ensure_available!()
    TripleStore.close(store)
  end

  # ===========================================================================
  # Loading Data
  # ===========================================================================

  @doc """
  Loads one or more RDF files into the knowledge graph.

  Supports Turtle (.ttl), N-Triples (.nt), N-Quads (.nq), RDF/XML (.rdf),
  TriG (.trig), and JSON-LD (.jsonld) formats. Format is auto-detected
  from file extension.

  ## Options

    * `:batch_size` - Number of triples per batch (default: 1000)
    * `:format` - Force specific format instead of auto-detect

  ## Returns

  A map with loading statistics:

    * `:loaded` - Number of files successfully loaded
    * `:failed` - Number of files that failed
    * `:triples` - Total number of triples loaded
    * `:errors` - List of `{:error, path, reason}` tuples

  ## Examples

      {:ok, stats} = KnowledgeGraph.load_files(kg, ["ontology.ttl"])
      # => {:ok, %{loaded: 1, failed: 0, triples: 1234, errors: []}}

      {:ok, stats} = KnowledgeGraph.load_files(kg, ["a.ttl", "b.ttl", "missing.ttl"])
      # => {:ok, %{loaded: 2, failed: 1, triples: 500, errors: [{:error, "missing.ttl", :enoent}]}}
  """
  @spec load_files(store(), [Path.t()], keyword()) :: {:ok, load_result()} | {:error, term()}
  def load_files(store, paths, opts \\ []) when is_list(paths) do
    ensure_available!()

    results =
      Enum.map(paths, fn path ->
        case TripleStore.load(store, path, opts) do
          {:ok, count} -> {:ok, path, count}
          {:error, reason} -> {:error, path, reason}
        end
      end)

    successes = Enum.filter(results, &match?({:ok, _, _}, &1))
    failures = Enum.filter(results, &match?({:error, _, _}, &1))
    total = Enum.sum(for {:ok, _, c} <- successes, do: c)

    {:ok,
     %{
       loaded: length(successes),
       failed: length(failures),
       triples: total,
       errors: failures
     }}
  end

  @doc """
  Loads RDF files matching a glob pattern into the knowledge graph.

  ## Options

  Same as `load_files/3`.

  ## Examples

      # Load all Turtle files in a directory
      {:ok, stats} = KnowledgeGraph.load_glob(kg, "ontologies/*.ttl")

      # Load recursively
      {:ok, stats} = KnowledgeGraph.load_glob(kg, "data/**/*.ttl")
  """
  @spec load_glob(store(), String.t(), keyword()) :: {:ok, load_result()} | {:error, term()}
  def load_glob(store, pattern, opts \\ []) do
    paths = Path.wildcard(pattern)

    if Enum.empty?(paths) do
      {:ok,
       %{
         loaded: 0,
         failed: 0,
         triples: 0,
         errors: [],
         pattern: pattern,
         message: "No files matched"
       }}
    else
      load_files(store, paths, opts)
    end
  end

  @doc """
  Loads an RDF.Graph into the knowledge graph.

  This is useful for loading graphs produced by the ElixirOntologies pipeline.

  ## Examples

      # From pipeline output
      {:ok, result} = ElixirOntologies.analyze("/path/to/project")
      {:ok, count} = KnowledgeGraph.load_graph(kg, result.graph)
  """
  @spec load_graph(store(), RDF.Graph.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_graph(store, %RDF.Graph{} = graph) do
    ensure_available!()
    TripleStore.load_graph(store, graph)
  end

  @doc """
  Loads RDF from a string in the specified format.

  ## Formats

    * `:turtle` - Turtle format
    * `:ntriples` - N-Triples format
    * `:nquads` - N-Quads format
    * `:rdfxml` - RDF/XML format
    * `:jsonld` - JSON-LD format

  ## Options

    * `:base_iri` - Base IRI for relative references
    * `:batch_size` - Number of triples per batch (default: 1000)

  ## Examples

      ttl = \"""
      @prefix ex: <http://example.org/> .
      ex:alice ex:knows ex:bob .
      \"""
      {:ok, count} = KnowledgeGraph.load_string(kg, ttl, :turtle)
  """
  @spec load_string(store(), String.t(), atom(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def load_string(store, content, format, opts \\ []) do
    ensure_available!()
    TripleStore.load_string(store, content, format, opts)
  end

  # ===========================================================================
  # Querying
  # ===========================================================================

  @doc """
  Executes a SPARQL query against the knowledge graph.

  Supports SELECT, ASK, CONSTRUCT, and DESCRIBE queries.

  ## Options

    * `:timeout` - Query timeout in milliseconds (default: 30000)
    * `:explain` - Return query plan instead of executing (default: false)

  ## Returns

    * SELECT queries return `{:ok, [%{var => value, ...}, ...]}`
    * ASK queries return `{:ok, boolean()}`
    * CONSTRUCT/DESCRIBE queries return `{:ok, RDF.Graph.t()}`

  ## Examples

      # SELECT query
      {:ok, results} = KnowledgeGraph.query(kg, "SELECT ?m ?name WHERE { ?m a :Module ; :name ?name }")
      Enum.each(results, fn row -> IO.puts(row["name"]) end)

      # ASK query
      {:ok, exists} = KnowledgeGraph.query(kg, "ASK { ?s a :GenServer }")

      # CONSTRUCT query
      {:ok, graph} = KnowledgeGraph.query(kg, "CONSTRUCT { ?s ?p ?o } WHERE { ?s a :Module ; ?p ?o }")
  """
  @spec query(store(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def query(store, sparql, opts \\ []) do
    ensure_available!()
    TripleStore.query(store, sparql, opts)
  end

  @doc """
  Executes a SPARQL query, raising on error.
  """
  @spec query!(store(), String.t(), keyword()) :: term()
  def query!(store, sparql, opts \\ []) do
    case query(store, sparql, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Query failed: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Statistics
  # ===========================================================================

  @doc """
  Returns statistics about the knowledge graph.

  ## Examples

      {:ok, stats} = KnowledgeGraph.stats(kg)
      IO.puts("Total triples: \#{stats.triple_count}")
  """
  @spec stats(store()) :: {:ok, map()} | {:error, term()}
  def stats(store) do
    ensure_available!()

    # Get triple count via ASK or count query
    with {:ok, count_result} <-
           TripleStore.query(store, "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }") do
      count =
        case count_result do
          [%{"count" => c}] when is_integer(c) -> c
          [%{"count" => %RDF.Literal{} = lit}] -> RDF.Literal.value(lit)
          _ -> 0
        end

      {:ok, %{triple_count: count}}
    end
  end

  # ===========================================================================
  # Export
  # ===========================================================================

  @doc """
  Exports the knowledge graph as an RDF.Graph.

  ## Examples

      {:ok, graph} = KnowledgeGraph.export(kg)
      RDF.Turtle.write_file!(graph, "export.ttl")
  """
  @spec export(store()) :: {:ok, RDF.Graph.t()} | {:error, term()}
  def export(store) do
    ensure_available!()
    TripleStore.export(store, :graph)
  end

  @doc """
  Exports the knowledge graph to a file.

  Format is auto-detected from file extension.

  ## Examples

      {:ok, _bytes} = KnowledgeGraph.export_file(kg, "export.ttl")
      {:ok, _bytes} = KnowledgeGraph.export_file(kg, "export.nt")
  """
  @spec export_file(store(), Path.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def export_file(store, path, opts \\ []) do
    ensure_available!()
    format = detect_format(path)
    TripleStore.export(store, {:file, path, format}, opts)
  end

  # Detect RDF format from file extension
  @spec detect_format(Path.t()) :: atom()
  defp detect_format(path) do
    case Path.extname(path) do
      ".ttl" -> :turtle
      ".nt" -> :ntriples
      ".nq" -> :nquads
      ".trig" -> :trig
      ".rdf" -> :rdfxml
      ".xml" -> :rdfxml
      ".jsonld" -> :jsonld
      ".json" -> :jsonld
      _ -> :turtle
    end
  end

  # ===========================================================================
  # Reasoning (if available)
  # ===========================================================================

  @doc """
  Materializes inferred triples using OWL 2 RL reasoning.

  This adds entailed triples based on RDFS and OWL 2 RL rules.

  ## Options

    * `:profile` - Reasoning profile: `:rdfs`, `:owl2rl` (default: `:owl2rl`)

  ## Examples

      {:ok, stats} = KnowledgeGraph.materialize(kg)
      IO.puts("Added \#{stats.inferred_count} inferred triples")
  """
  @spec materialize(store(), keyword()) :: {:ok, map()} | {:error, term()}
  def materialize(store, opts \\ []) do
    ensure_available!()

    if function_exported?(TripleStore, :materialize, 2) do
      TripleStore.materialize(store, opts)
    else
      {:error, :reasoning_not_available}
    end
  end
end
