defmodule ElixirOntologies.Graph do
  @moduledoc """
  A wrapper around `RDF.Graph` providing domain-specific API for Elixir ontology graphs.

  This module provides a clean, high-level interface for creating, manipulating,
  and querying RDF graphs containing Elixir code structure data. It integrates
  with the namespace definitions from `ElixirOntologies.NS` and supports
  optional SPARQL queries when the sparql library is available.

  ## Usage

      alias ElixirOntologies.Graph
      alias ElixirOntologies.NS.{Core, Structure}

      # Create a new graph
      graph = Graph.new()

      # Add statements
      graph =
        graph
        |> Graph.add({~I<https://example.org/code#MyApp>, RDF.type(), Structure.Module})
        |> Graph.add({~I<https://example.org/code#MyApp>, Structure.moduleName(), "MyApp"})

      # Query the graph
      subjects = Graph.subjects(graph)
      description = Graph.describe(graph, ~I<https://example.org/code#MyApp>)

  ## SPARQL Support

  When the `sparql` library is available, you can execute SPARQL queries:

      {:ok, results} = Graph.query(graph, "SELECT ?s WHERE { ?s a struct:Module }")

  ## Struct Fields

  - `:graph` - The underlying `RDF.Graph` struct
  - `:base_iri` - Optional base IRI for the graph
  """

  alias ElixirOntologies.NS

  defstruct [:graph, :base_iri]

  @type t :: %__MODULE__{
          graph: RDF.Graph.t(),
          base_iri: RDF.IRI.t() | nil
        }

  @type statement :: RDF.Statement.t()
  @type subject :: RDF.Statement.subject()

  # ===========================================================================
  # Graph Creation
  # ===========================================================================

  @doc """
  Creates a new empty graph.

  ## Examples

      iex> graph = ElixirOntologies.Graph.new()
      iex> %ElixirOntologies.Graph{} = graph
      iex> graph.graph |> RDF.Graph.statement_count()
      0
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      graph: RDF.Graph.new(),
      base_iri: nil
    }
  end

  @doc """
  Creates a new graph with options.

  ## Options

  - `:base_iri` - Sets the base IRI for the graph
  - `:prefixes` - Prefix map for serialization (defaults to `ElixirOntologies.NS.prefix_map/0`)
  - `:name` - Graph name (for named graphs)

  ## Examples

      iex> graph = ElixirOntologies.Graph.new(base_iri: "https://example.org/code#")
      iex> graph.base_iri
      ~I<https://example.org/code#>

      iex> graph = ElixirOntologies.Graph.new(name: ~I<https://example.org/graphs/my-graph>)
      iex> graph.graph.name
      ~I<https://example.org/graphs/my-graph>
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    base_iri = parse_base_iri(Keyword.get(opts, :base_iri))
    prefixes = Keyword.get(opts, :prefixes, NS.prefix_map())
    name = Keyword.get(opts, :name)

    graph_opts =
      [prefixes: prefixes]
      |> maybe_add_opt(:base_iri, base_iri)
      |> maybe_add_opt(:name, name)

    %__MODULE__{
      graph: RDF.Graph.new(graph_opts),
      base_iri: base_iri
    }
  end

  defp parse_base_iri(nil), do: nil
  defp parse_base_iri(%RDF.IRI{} = iri), do: iri
  defp parse_base_iri(iri) when is_binary(iri), do: RDF.iri(iri)

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  # ===========================================================================
  # Adding Statements
  # ===========================================================================

  @doc """
  Adds a statement (triple) to the graph.

  Accepts RDF triples as 3-tuples `{subject, predicate, object}` or
  `RDF.Description` structs.

  ## Examples

      iex> alias ElixirOntologies.NS.Structure
      iex> graph = ElixirOntologies.Graph.new()
      iex> graph = ElixirOntologies.Graph.add(graph, {~I<https://example.org/code#MyApp>, RDF.type(), Structure.Module})
      iex> graph.graph |> RDF.Graph.statement_count()
      1
  """
  @spec add(t(), statement() | RDF.Description.t()) :: t()
  def add(%__MODULE__{graph: graph} = wrapper, statement) do
    %{wrapper | graph: RDF.Graph.add(graph, statement)}
  end

  @doc """
  Adds multiple statements to the graph.

  Accepts a list of triples, a list of `RDF.Description` structs,
  or another `RDF.Graph`.

  ## Examples

      iex> alias ElixirOntologies.NS.Structure
      iex> statements = [
      ...>   {~I<https://example.org/code#MyApp>, RDF.type(), Structure.Module},
      ...>   {~I<https://example.org/code#MyApp>, Structure.moduleName(), "MyApp"}
      ...> ]
      iex> graph = ElixirOntologies.Graph.new() |> ElixirOntologies.Graph.add_all(statements)
      iex> graph.graph |> RDF.Graph.statement_count()
      2
  """
  @spec add_all(t(), [statement()] | RDF.Graph.t() | [RDF.Description.t()]) :: t()
  def add_all(%__MODULE__{graph: graph} = wrapper, statements) do
    %{wrapper | graph: RDF.Graph.add(graph, statements)}
  end

  # ===========================================================================
  # Merging Graphs
  # ===========================================================================

  @doc """
  Merges another graph into this one.

  The second argument can be another `ElixirOntologies.Graph`, an `RDF.Graph`,
  or a list of statements.

  ## Examples

      iex> alias ElixirOntologies.NS.Structure
      iex> g1 = ElixirOntologies.Graph.new() |> ElixirOntologies.Graph.add({~I<https://example.org/code#A>, RDF.type(), Structure.Module})
      iex> g2 = ElixirOntologies.Graph.new() |> ElixirOntologies.Graph.add({~I<https://example.org/code#B>, RDF.type(), Structure.Module})
      iex> merged = ElixirOntologies.Graph.merge(g1, g2)
      iex> merged.graph |> RDF.Graph.statement_count()
      2
  """
  @spec merge(t(), t() | RDF.Graph.t()) :: t()
  def merge(%__MODULE__{graph: graph} = wrapper, %__MODULE__{graph: other_graph}) do
    %{wrapper | graph: RDF.Graph.add(graph, other_graph)}
  end

  def merge(%__MODULE__{graph: graph} = wrapper, %RDF.Graph{} = other_graph) do
    %{wrapper | graph: RDF.Graph.add(graph, other_graph)}
  end

  # ===========================================================================
  # Query Operations
  # ===========================================================================

  @doc """
  Returns all unique subjects in the graph as a MapSet.

  ## Examples

      iex> alias ElixirOntologies.NS.Structure
      iex> graph = ElixirOntologies.Graph.new()
      ...>   |> ElixirOntologies.Graph.add({~I<https://example.org/code#A>, RDF.type(), Structure.Module})
      ...>   |> ElixirOntologies.Graph.add({~I<https://example.org/code#B>, RDF.type(), Structure.Module})
      iex> subjects = ElixirOntologies.Graph.subjects(graph)
      iex> MapSet.size(subjects)
      2
  """
  @spec subjects(t()) :: MapSet.t(subject())
  def subjects(%__MODULE__{graph: graph}) do
    RDF.Graph.subjects(graph)
  end

  @doc """
  Returns all statements about a given subject (its description).

  Returns an empty `RDF.Description` if the subject is not found in the graph.

  ## Examples

      iex> alias ElixirOntologies.NS.Structure
      iex> subject = ~I<https://example.org/code#MyApp>
      iex> graph = ElixirOntologies.Graph.new()
      ...>   |> ElixirOntologies.Graph.add({subject, RDF.type(), Structure.Module})
      ...>   |> ElixirOntologies.Graph.add({subject, Structure.moduleName(), "MyApp"})
      iex> description = ElixirOntologies.Graph.describe(graph, subject)
      iex> description |> RDF.Description.statement_count()
      2

      iex> graph = ElixirOntologies.Graph.new()
      iex> description = ElixirOntologies.Graph.describe(graph, ~I<https://example.org/nonexistent>)
      iex> RDF.Description.empty?(description)
      true
  """
  @spec describe(t(), subject()) :: RDF.Description.t()
  def describe(%__MODULE__{graph: graph}, subject) do
    RDF.Graph.description(graph, subject)
  end

  # ===========================================================================
  # SPARQL Queries
  # ===========================================================================

  @doc """
  Executes a SPARQL query against the graph.

  Requires the `sparql` library to be installed. Returns `{:error, :sparql_not_available}`
  if the library is not present.

  ## Options

  - `:prefixes` - Additional prefixes to use in the query (merged with graph prefixes)

  ## Examples

      # When sparql library is available:
      {:ok, results} = Graph.query(graph, "SELECT ?s WHERE { ?s a struct:Module }")

      # When sparql library is not available:
      {:error, :sparql_not_available} = Graph.query(graph, "SELECT ?s WHERE { ?s ?p ?o }")

  ## Notes

  The query automatically includes prefixes from `ElixirOntologies.NS.prefix_map/0`
  unless overridden.
  """
  @spec query(t(), String.t(), keyword()) ::
          {:ok, SPARQL.Query.Result.t()} | {:error, :sparql_not_available | term()}
  def query(graph, query_string, opts \\ [])

  def query(%__MODULE__{graph: rdf_graph}, query_string, opts) do
    if sparql_available?() do
      execute_sparql_query(rdf_graph, query_string, opts)
    else
      {:error, :sparql_not_available}
    end
  end

  defp sparql_available? do
    Code.ensure_loaded?(SPARQL)
  end

  defp execute_sparql_query(rdf_graph, query_string, opts) do
    default_prefixes = NS.prefix_map()
    custom_prefixes = Keyword.get(opts, :prefixes, [])
    all_prefixes = Keyword.merge(default_prefixes, custom_prefixes)

    # Build PREFIX declarations and prepend to query
    prefix_declarations = build_prefix_declarations(all_prefixes)
    full_query = prefix_declarations <> query_string

    try do
      result = SPARQL.execute_query(rdf_graph, full_query)
      {:ok, result}
    rescue
      e -> {:error, e}
    end
  end

  defp build_prefix_declarations(prefixes) do
    prefixes
    |> Enum.map(fn {prefix, iri} ->
      iri_str = if is_binary(iri), do: iri, else: to_string(iri)
      "PREFIX #{prefix}: <#{iri_str}>\n"
    end)
    |> Enum.join()
  end

  # ===========================================================================
  # Utility Functions
  # ===========================================================================

  @doc """
  Returns the number of statements in the graph.

  ## Examples

      iex> ElixirOntologies.Graph.new() |> ElixirOntologies.Graph.statement_count()
      0
  """
  @spec statement_count(t()) :: non_neg_integer()
  def statement_count(%__MODULE__{graph: graph}) do
    RDF.Graph.statement_count(graph)
  end

  @doc """
  Checks if the graph is empty.

  ## Examples

      iex> ElixirOntologies.Graph.new() |> ElixirOntologies.Graph.empty?()
      true
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{graph: graph}) do
    RDF.Graph.empty?(graph)
  end

  @doc """
  Returns the underlying `RDF.Graph` struct.

  Useful for interoperating with RDF.ex functions not wrapped by this module.

  ## Examples

      iex> graph = ElixirOntologies.Graph.new()
      iex> %RDF.Graph{} = ElixirOntologies.Graph.to_rdf_graph(graph)
  """
  @spec to_rdf_graph(t()) :: RDF.Graph.t()
  def to_rdf_graph(%__MODULE__{graph: graph}) do
    graph
  end

  @doc """
  Creates an `ElixirOntologies.Graph` from an existing `RDF.Graph`.

  ## Examples

      iex> rdf_graph = RDF.Graph.new()
      iex> %ElixirOntologies.Graph{} = ElixirOntologies.Graph.from_rdf_graph(rdf_graph)
  """
  @spec from_rdf_graph(RDF.Graph.t(), keyword()) :: t()
  def from_rdf_graph(%RDF.Graph{} = rdf_graph, opts \\ []) do
    base_iri = parse_base_iri(Keyword.get(opts, :base_iri))

    %__MODULE__{
      graph: rdf_graph,
      base_iri: base_iri
    }
  end

  # ===========================================================================
  # Serialization
  # ===========================================================================

  @doc """
  Serializes the graph to Turtle format.

  Uses default prefixes from `ElixirOntologies.NS.prefix_map/0` for compact output.

  ## Examples

      iex> alias ElixirOntologies.NS.Structure
      iex> graph = ElixirOntologies.Graph.new()
      ...>   |> ElixirOntologies.Graph.add({~I<https://example.org/code#MyApp>, RDF.type(), Structure.Module})
      iex> {:ok, turtle} = ElixirOntologies.Graph.to_turtle(graph)
      iex> String.contains?(turtle, "struct:Module")
      true
  """
  @spec to_turtle(t()) :: {:ok, String.t()} | {:error, term()}
  def to_turtle(%__MODULE__{} = graph) do
    to_turtle(graph, [])
  end

  @doc """
  Serializes the graph to Turtle format with options.

  ## Options

  - `:prefixes` - Custom prefix map (defaults to `ElixirOntologies.NS.prefix_map/0`)
  - `:base` - Base IRI for the document (defaults to graph's base_iri)
  - `:implicit_base` - If true, omit @base declaration but use for relative IRIs
  - `:indent` - Indentation width (default: 4)

  ## Examples

      iex> alias ElixirOntologies.NS.Structure
      iex> graph = ElixirOntologies.Graph.new(base_iri: "https://example.org/code#")
      ...>   |> ElixirOntologies.Graph.add({~I<https://example.org/code#MyApp>, RDF.type(), Structure.Module})
      iex> {:ok, turtle} = ElixirOntologies.Graph.to_turtle(graph, base: "https://example.org/code#")
      iex> String.contains?(turtle, "@base")
      true
  """
  @spec to_turtle(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def to_turtle(%__MODULE__{graph: rdf_graph, base_iri: graph_base_iri}, opts) do
    prefixes = Keyword.get(opts, :prefixes, NS.prefix_map())
    base = Keyword.get(opts, :base, graph_base_iri)

    turtle_opts =
      [prefixes: prefixes]
      |> maybe_add_opt(:base, base)
      |> maybe_add_opt(:implicit_base, Keyword.get(opts, :implicit_base))
      |> maybe_add_opt(:indent, Keyword.get(opts, :indent))

    RDF.Turtle.write_string(rdf_graph, turtle_opts)
  end

  @doc """
  Serializes the graph to Turtle format, raising on error.

  ## Examples

      iex> alias ElixirOntologies.NS.Structure
      iex> graph = ElixirOntologies.Graph.new()
      ...>   |> ElixirOntologies.Graph.add({~I<https://example.org/code#MyApp>, RDF.type(), Structure.Module})
      iex> turtle = ElixirOntologies.Graph.to_turtle!(graph)
      iex> is_binary(turtle)
      true
  """
  @spec to_turtle!(t(), keyword()) :: String.t()
  def to_turtle!(%__MODULE__{} = graph, opts \\ []) do
    case to_turtle(graph, opts) do
      {:ok, turtle} -> turtle
      {:error, reason} -> raise "Failed to serialize graph to Turtle: #{inspect(reason)}"
    end
  end

  @doc """
  Saves the graph to a file in Turtle format.

  ## Examples

      graph = Graph.new() |> Graph.add({subject, predicate, object})
      :ok = Graph.save(graph, "/path/to/output.ttl")
  """
  @spec save(t(), Path.t()) :: :ok | {:error, term()}
  def save(%__MODULE__{} = graph, path) when is_binary(path) do
    save(graph, path, [])
  end

  @doc """
  Saves the graph to a file with options.

  ## Options

  - `:format` - Output format (`:turtle` default, future: `:ntriples`, `:json_ld`)
  - `:prefixes` - Custom prefix map for serialization
  - `:base` - Base IRI for the document

  ## Examples

      graph = Graph.new() |> Graph.add({subject, predicate, object})
      :ok = Graph.save(graph, "/path/to/output.ttl", format: :turtle)
  """
  @spec save(t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def save(%__MODULE__{} = graph, path, opts) when is_binary(path) and is_list(opts) do
    format = Keyword.get(opts, :format, :turtle)
    serialization_opts = Keyword.drop(opts, [:format])

    case format do
      :turtle -> save_as_turtle(graph, path, serialization_opts)
      other -> {:error, {:unsupported_format, other}}
    end
  end

  defp save_as_turtle(graph, path, opts) do
    case to_turtle(graph, opts) do
      {:ok, content} -> File.write(path, content)
      {:error, _} = error -> error
    end
  end

  @doc """
  Saves the graph to a file, raising on error.

  ## Examples

      graph = Graph.new() |> Graph.add({subject, predicate, object})
      Graph.save!(graph, "/path/to/output.ttl")
  """
  @spec save!(t(), Path.t(), keyword()) :: :ok
  def save!(%__MODULE__{} = graph, path, opts \\ []) do
    case save(graph, path, opts) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to save graph to #{path}: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Loading
  # ===========================================================================

  @doc """
  Loads a graph from a file.

  The format is auto-detected from the file extension:
  - `.ttl` → Turtle format

  ## Examples

      {:ok, graph} = Graph.load("/path/to/graph.ttl")
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) when is_binary(path) do
    load(path, [])
  end

  @doc """
  Loads a graph from a file with options.

  ## Options

  - `:format` - Explicitly specify format (`:turtle`). If not provided, auto-detected from extension.
  - `:base_iri` - Base IRI for the loaded graph

  ## Examples

      {:ok, graph} = Graph.load("/path/to/graph.ttl", format: :turtle)
      {:ok, graph} = Graph.load("/path/to/graph.ttl", base_iri: "https://example.org/")
  """
  @spec load(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(path, opts) when is_binary(path) and is_list(opts) do
    format = Keyword.get(opts, :format) || detect_format(path)
    base_iri = Keyword.get(opts, :base_iri)

    case format do
      :turtle -> load_turtle_file(path, base_iri)
      nil -> {:error, {:unknown_format, Path.extname(path)}}
      other -> {:error, {:unsupported_format, other}}
    end
  end

  defp detect_format(path) do
    case Path.extname(path) do
      ".ttl" -> :turtle
      ".turtle" -> :turtle
      _ -> nil
    end
  end

  defp load_turtle_file(path, base_iri) do
    case File.read(path) do
      {:ok, content} -> from_turtle(content, base_iri: base_iri)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Loads a graph from a file, raising on error.

  ## Examples

      graph = Graph.load!("/path/to/graph.ttl")
  """
  @spec load!(Path.t(), keyword()) :: t()
  def load!(path, opts \\ []) do
    case load(path, opts) do
      {:ok, graph} -> graph
      {:error, reason} -> raise "Failed to load graph from #{path}: #{format_load_error(reason)}"
    end
  end

  @doc """
  Parses a Turtle string into a graph.

  ## Options

  - `:base_iri` - Base IRI for the graph

  ## Examples

      iex> turtle = \"""
      ...> @prefix struct: <https://w3id.org/elixir-code/structure#> .
      ...> <https://example.org/code#MyApp> a struct:Module .
      ...> \"""
      iex> {:ok, graph} = ElixirOntologies.Graph.from_turtle(turtle)
      iex> ElixirOntologies.Graph.statement_count(graph)
      1
  """
  @spec from_turtle(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_turtle(turtle_string, opts \\ []) when is_binary(turtle_string) do
    base_iri = Keyword.get(opts, :base_iri)

    case RDF.Turtle.read_string(turtle_string) do
      {:ok, rdf_graph} ->
        graph = from_rdf_graph(rdf_graph, base_iri: base_iri)
        {:ok, graph}

      {:error, reason} ->
        {:error, {:parse_error, format_parse_error(reason)}}
    end
  end

  @doc """
  Parses a Turtle string into a graph, raising on error.

  ## Examples

      turtle = \"""
      @prefix struct: <https://w3id.org/elixir-code/structure#> .
      <https://example.org/code#MyApp> a struct:Module .
      \"""
      graph = Graph.from_turtle!(turtle)
  """
  @spec from_turtle!(String.t(), keyword()) :: t()
  def from_turtle!(turtle_string, opts \\ []) do
    case from_turtle(turtle_string, opts) do
      {:ok, graph} -> graph
      {:error, reason} -> raise "Failed to parse Turtle: #{format_load_error(reason)}"
    end
  end

  defp format_parse_error(reason) when is_binary(reason), do: reason

  defp format_parse_error(%{message: message, line: line}) do
    "Line #{line}: #{message}"
  end

  defp format_parse_error(reason), do: inspect(reason)

  defp format_load_error({:parse_error, details}), do: "Parse error: #{details}"
  defp format_load_error({:unsupported_format, format}), do: "Unsupported format: #{format}"
  defp format_load_error({:unknown_format, ext}), do: "Unknown file format for extension: #{ext}"
  defp format_load_error(:enoent), do: "File not found"
  defp format_load_error(reason), do: inspect(reason)
end
