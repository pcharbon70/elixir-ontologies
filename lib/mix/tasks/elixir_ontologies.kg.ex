defmodule Mix.Tasks.ElixirOntologies.Kg do
  @shortdoc "Manage the Elixir ontologies knowledge graph"

  @moduledoc """
  Manage the Elixir ontologies knowledge graph.

  This task provides commands for loading RDF data into a persistent triple store
  and querying it with SPARQL.

  ## Requirements

  Requires the `triple_store` dependency. Add to mix.exs:

      {:triple_store, path: "../triple_store"}

  ## Commands

  ### load - Load RDF files

      mix elixir_ontologies.kg load --db ./knowledge_graph file1.ttl file2.ttl
      mix elixir_ontologies.kg load --db ./kg "ontologies/**/*.ttl"

  Options:
    * `--db PATH` - Path to knowledge graph database (required)
    * `--batch-size N` - Triples per batch (default: 1000)

  ### query - Execute SPARQL query

      mix elixir_ontologies.kg query --db ./kg "SELECT ?m WHERE { ?m a :Module }"
      mix elixir_ontologies.kg query --db ./kg --file query.sparql

  Options:
    * `--db PATH` - Path to knowledge graph database (required)
    * `--file PATH` - Read query from file instead of argument
    * `--format FORMAT` - Output format: table, json, csv (default: table)
    * `--timeout MS` - Query timeout in milliseconds (default: 30000)

  ### stats - Show statistics

      mix elixir_ontologies.kg stats --db ./knowledge_graph

  Options:
    * `--db PATH` - Path to knowledge graph database (required)

  ### export - Export to file

      mix elixir_ontologies.kg export --db ./kg output.ttl

  Options:
    * `--db PATH` - Path to knowledge graph database (required)

  ## Examples

      # Load all ontology files
      mix elixir_ontologies.kg load --db ./kg priv/ontologies/*.ttl

      # Load analyzed package data
      mix elixir_ontologies.kg load --db ./kg ".ttl-list/**/*.ttl"

      # Find all modules
      mix elixir_ontologies.kg query --db ./kg \\
        "PREFIX struct: <https://w3id.org/elixir-code/structure#>
         SELECT ?module WHERE { ?module a struct:Module }"

      # Count triples
      mix elixir_ontologies.kg stats --db ./kg
  """

  use Mix.Task

  alias ElixirOntologies.KnowledgeGraph

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    # Ensure triple_store is available
    unless KnowledgeGraph.available?() do
      Mix.raise("""
      The triple_store dependency is not available.

      Add to your mix.exs:
          {:triple_store, path: "../triple_store"}

      Then run: mix deps.get
      """)
    end

    case args do
      ["load" | rest] -> run_load(rest)
      ["query" | rest] -> run_query(rest)
      ["stats" | rest] -> run_stats(rest)
      ["export" | rest] -> run_export(rest)
      [] -> Mix.shell().info(@moduledoc)
      [cmd | _] -> Mix.raise("Unknown command: #{cmd}. Use: load, query, stats, export")
    end
  end

  # ===========================================================================
  # Load Command
  # ===========================================================================

  defp run_load(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [
          db: :string,
          batch_size: :integer
        ],
        aliases: [d: :db, b: :batch_size]
      )

    db_path = opts[:db] || Mix.raise("--db option is required")

    if Enum.empty?(files) do
      Mix.raise("No files specified. Usage: mix elixir_ontologies.kg load --db PATH files...")
    end

    # Expand glob patterns
    paths =
      files
      |> Enum.flat_map(fn pattern ->
        case Path.wildcard(pattern) do
          [] ->
            # Not a glob, treat as literal path
            if File.exists?(pattern), do: [pattern], else: []

          matches ->
            matches
        end
      end)
      |> Enum.uniq()

    if Enum.empty?(paths) do
      Mix.raise("No files found matching: #{Enum.join(files, ", ")}")
    end

    Mix.shell().info("Opening knowledge graph at: #{db_path}")

    {:ok, store} = KnowledgeGraph.open(db_path)

    load_opts = if opts[:batch_size], do: [batch_size: opts[:batch_size]], else: []

    Mix.shell().info("Loading #{length(paths)} file(s)...")

    start_time = System.monotonic_time(:millisecond)
    {:ok, stats} = KnowledgeGraph.load_files(store, paths, load_opts)
    elapsed = System.monotonic_time(:millisecond) - start_time

    :ok = KnowledgeGraph.close(store)

    # Report results
    Mix.shell().info("")
    Mix.shell().info("Loading complete:")
    Mix.shell().info("  Files loaded: #{stats.loaded}")
    Mix.shell().info("  Files failed: #{stats.failed}")
    Mix.shell().info("  Triples added: #{format_number(stats.triples)}")
    Mix.shell().info("  Time: #{format_duration(elapsed)}")

    if stats.failed > 0 do
      Mix.shell().info("")
      Mix.shell().info("Errors:")

      Enum.each(stats.errors, fn {:error, path, reason} ->
        Mix.shell().info("  #{path}: #{inspect(reason)}")
      end)
    end
  end

  # ===========================================================================
  # Query Command
  # ===========================================================================

  defp run_query(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [
          db: :string,
          file: :string,
          format: :string,
          timeout: :integer
        ],
        aliases: [d: :db, f: :file, o: :format, t: :timeout]
      )

    db_path = opts[:db] || Mix.raise("--db option is required")

    query =
      cond do
        opts[:file] ->
          File.read!(opts[:file])

        length(rest) > 0 ->
          Enum.join(rest, " ")

        true ->
          Mix.raise("No query specified. Use --file or pass query as argument")
      end

    format = opts[:format] || "table"
    query_opts = if opts[:timeout], do: [timeout: opts[:timeout]], else: []

    {:ok, store} = KnowledgeGraph.open(db_path, create_if_missing: false)

    start_time = System.monotonic_time(:millisecond)
    result = KnowledgeGraph.query(store, query, query_opts)
    elapsed = System.monotonic_time(:millisecond) - start_time

    :ok = KnowledgeGraph.close(store)

    case result do
      {:ok, rows} when is_list(rows) ->
        format_select_results(rows, format)
        Mix.shell().info("\n#{length(rows)} row(s) in #{format_duration(elapsed)}")

      {:ok, true} ->
        Mix.shell().info("true")

      {:ok, false} ->
        Mix.shell().info("false")

      {:ok, %RDF.Graph{} = graph} ->
        Mix.shell().info(RDF.Turtle.write_string!(graph))
        Mix.shell().info("\n#{RDF.Graph.triple_count(graph)} triple(s) in #{format_duration(elapsed)}")

      {:error, reason} ->
        Mix.raise("Query failed: #{inspect(reason)}")
    end
  end

  defp format_select_results([], _format) do
    Mix.shell().info("No results")
  end

  defp format_select_results(rows, "json") do
    # Simple JSON output
    json =
      rows
      |> Enum.map(fn row ->
        row
        |> Enum.map(fn {k, v} -> {k, format_term(v)} end)
        |> Map.new()
      end)
      |> Jason.encode!(pretty: true)

    Mix.shell().info(json)
  end

  defp format_select_results(rows, "csv") do
    [first | _] = rows
    headers = Map.keys(first) |> Enum.sort()

    # Header row
    Mix.shell().info(Enum.join(headers, ","))

    # Data rows
    Enum.each(rows, fn row ->
      values = Enum.map(headers, fn h -> format_term(row[h]) end)
      Mix.shell().info(Enum.join(values, ","))
    end)
  end

  defp format_select_results(rows, _table) do
    [first | _] = rows
    headers = Map.keys(first) |> Enum.sort()

    # Calculate column widths
    widths =
      Enum.map(headers, fn h ->
        max_value =
          rows
          |> Enum.map(fn row -> format_term(row[h]) |> String.length() end)
          |> Enum.max()

        max(String.length(h), max_value)
      end)

    # Header row
    header_line =
      Enum.zip(headers, widths)
      |> Enum.map(fn {h, w} -> String.pad_trailing(h, w) end)
      |> Enum.join(" | ")

    Mix.shell().info(header_line)
    Mix.shell().info(String.duplicate("-", String.length(header_line)))

    # Data rows
    Enum.each(rows, fn row ->
      line =
        Enum.zip(headers, widths)
        |> Enum.map(fn {h, w} -> String.pad_trailing(format_term(row[h]), w) end)
        |> Enum.join(" | ")

      Mix.shell().info(line)
    end)
  end

  defp format_term(nil), do: ""
  defp format_term(%RDF.IRI{} = iri), do: "<#{iri}>"
  defp format_term(%RDF.BlankNode{} = bn), do: "_:#{bn.value}"
  defp format_term(%RDF.Literal{} = lit), do: to_string(RDF.Literal.value(lit))
  defp format_term(other), do: to_string(other)

  # ===========================================================================
  # Stats Command
  # ===========================================================================

  defp run_stats(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [db: :string],
        aliases: [d: :db]
      )

    db_path = opts[:db] || Mix.raise("--db option is required")

    {:ok, store} = KnowledgeGraph.open(db_path, create_if_missing: false)
    {:ok, stats} = KnowledgeGraph.stats(store)
    :ok = KnowledgeGraph.close(store)

    Mix.shell().info("Knowledge Graph Statistics")
    Mix.shell().info("=" <> String.duplicate("=", 30))
    Mix.shell().info("  Database: #{db_path}")
    Mix.shell().info("  Triples: #{format_number(stats.triple_count)}")
  end

  # ===========================================================================
  # Export Command
  # ===========================================================================

  defp run_export(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [db: :string],
        aliases: [d: :db]
      )

    db_path = opts[:db] || Mix.raise("--db option is required")

    output_path =
      case rest do
        [path | _] -> path
        [] -> Mix.raise("No output file specified")
      end

    {:ok, store} = KnowledgeGraph.open(db_path, create_if_missing: false)

    Mix.shell().info("Exporting to: #{output_path}")

    start_time = System.monotonic_time(:millisecond)
    :ok = KnowledgeGraph.export_file(store, output_path)
    elapsed = System.monotonic_time(:millisecond) - start_time

    :ok = KnowledgeGraph.close(store)

    file_size = File.stat!(output_path).size
    Mix.shell().info("Exported #{format_bytes(file_size)} in #{format_duration(elapsed)}")
  end

  # ===========================================================================
  # Formatting Helpers
  # ===========================================================================

  defp format_number(n) when n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 2)}M"
  end

  defp format_number(n) when n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n), do: to_string(n)

  defp format_duration(ms) when ms >= 60_000 do
    "#{Float.round(ms / 60_000, 1)}m"
  end

  defp format_duration(ms) when ms >= 1_000 do
    "#{Float.round(ms / 1_000, 2)}s"
  end

  defp format_duration(ms), do: "#{ms}ms"

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 2)} MB"
  end

  defp format_bytes(bytes) when bytes >= 1_024 do
    "#{Float.round(bytes / 1_024, 1)} KB"
  end

  defp format_bytes(bytes), do: "#{bytes} bytes"
end
