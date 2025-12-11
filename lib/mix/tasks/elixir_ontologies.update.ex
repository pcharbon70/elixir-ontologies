defmodule Mix.Tasks.ElixirOntologies.Update do
  @moduledoc """
  Updates an existing RDF knowledge graph with incremental analysis.

  ## Usage

      # Update graph from file
      mix elixir_ontologies.update --input my_project.ttl

      # Specify output file
      mix elixir_ontologies.update --input old.ttl --output new.ttl

      # Update specific project
      mix elixir_ontologies.update --input graph.ttl /path/to/project

  ## Options

    * `--input`, `-i` - Input graph file (required)
    * `--output`, `-o` - Output file path (default: overwrites input)
    * `--force-full` - Force full re-analysis instead of incremental
    * `--base-iri`, `-b` - Base IRI for generated resources
    * `--include-source` - Include source code text in graph
    * `--include-git` - Include git provenance information (default: true)
    * `--exclude-tests` - Exclude test files from analysis (default: true)
    * `--quiet`, `-q` - Suppress progress output

  ## Examples

      # Update graph in place
      mix elixir_ontologies.update --input my_project.ttl

      # Update and save to new file
      mix elixir_ontologies.update -i old.ttl -o new.ttl

      # Force full re-analysis
      mix elixir_ontologies.update -i graph.ttl --force-full

  ## State Files

  This task requires a state file (`.state` suffix) alongside the input graph
  to enable incremental updates. If the state file is missing, a full
  re-analysis will be performed automatically.
  """

  use Mix.Task

  alias ElixirOntologies.Analyzer.ProjectAnalyzer
  alias ElixirOntologies.Config

  @shortdoc "Update RDF knowledge graph with incremental analysis"
  @requirements ["compile"]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    # Parse command-line options
    {opts, remaining_args, invalid} = parse_options(args)

    # Handle invalid options
    if invalid != [] do
      error("Invalid options: #{inspect(invalid)}")
      Mix.Task.run("help", ["elixir_ontologies.update"])
      exit({:shutdown, 1})
    end

    # Validate required --input option
    unless Keyword.has_key?(opts, :input) do
      error("The --input option is required")
      Mix.Task.run("help", ["elixir_ontologies.update"])
      exit({:shutdown, 1})
    end

    input_file = Keyword.get(opts, :input)
    output_file = Keyword.get(opts, :output, input_file)
    quiet = Keyword.get(opts, :quiet, false)

    # Determine project path
    project_path =
      case remaining_args do
        [] ->
          "."

        [path] ->
          path

        _ ->
          error("Expected 0 or 1 argument, got #{length(remaining_args)}")
          exit({:shutdown, 1})
      end

    # Verify project path exists
    unless File.dir?(project_path) do
      error("Project path not found: #{project_path}")
      exit({:shutdown, 1})
    end

    # Verify input file exists
    unless File.exists?(input_file) do
      error("Input file not found: #{input_file}")
      exit({:shutdown, 1})
    end

    # Load existing graph
    progress(quiet, "Loading existing graph from #{input_file}")

    case load_existing_graph(input_file) do
      {:ok, graph} ->
        progress(quiet, "Loaded #{RDF.Graph.triple_count(graph.graph)} triples")

        # Try to load state
        force_full = Keyword.get(opts, :force_full, false)

        if force_full do
          warning("--force-full specified, performing full re-analysis")
          perform_full_and_save(project_path, opts, output_file, quiet)
        else
          case load_state(input_file) do
            {:ok, state} ->
              # State exists, perform incremental update
              perform_incremental_and_save(state, graph, project_path, opts, output_file, quiet)

            {:error, :not_found} ->
              warning("State file not found, performing full analysis")
              perform_full_and_save(project_path, opts, output_file, quiet)

            {:error, reason} ->
              warning("Failed to load state (#{format_error(reason)}), performing full analysis")
              perform_full_and_save(project_path, opts, output_file, quiet)
          end
        end

      {:error, reason} ->
        error("Failed to load graph: #{format_error(reason)}")
        exit({:shutdown, 1})
    end
  end

  # ===========================================================================
  # Private - Main Workflow Functions
  # ===========================================================================

  defp perform_incremental_and_save(state, graph, project_path, opts, output_file, quiet) do
    progress(quiet, "Loading analysis state")

    case state_to_result(state, graph, project_path) do
      {:ok, result} ->
        # Check if we have analysis for files (needed for incremental update)
        has_analysis = Enum.any?(result.files, fn file -> not is_nil(file.analysis) end)

        if has_analysis do
          do_incremental_update_and_save(result, project_path, opts, output_file, quiet)
        else
          warning("State file does not contain analysis results, performing full analysis")
          perform_full_and_save(project_path, opts, output_file, quiet)
        end

      {:error, reason} ->
        error("Failed to reconstruct analysis state: #{format_error(reason)}")
        error("Hint: Try using --force-full to perform full re-analysis")
        exit({:shutdown, 1})
    end
  end

  defp do_incremental_update_and_save(result, project_path, opts, output_file, quiet) do
    progress(quiet, "Detecting file changes...")

    case perform_incremental_update(result, project_path, opts, quiet) do
      {:ok, update_result} ->
        # Report changes
        report_changes(update_result.changes, quiet)

        # Check if there were any errors
        if update_result.errors != [] do
          warning("#{length(update_result.errors)} file(s) had errors:")

          for {file, error} <- Enum.take(update_result.errors, 5) do
            warning("  #{file}: #{format_error(error)}")
          end

          if length(update_result.errors) > 5 do
            warning("  ... and #{length(update_result.errors) - 5} more")
          end
        end

        # Write output
        case write_output(update_result.graph, update_result, output_file, quiet) do
          :ok ->
            progress(quiet, "")
            progress(quiet, "Update complete!")
            :ok

          {:error, reason} ->
            error("Failed to write output: #{format_error(reason)}")
            exit({:shutdown, 1})
        end

      {:error, reason} ->
        error("Failed to perform incremental update: #{format_error(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp perform_full_and_save(project_path, opts, output_file, quiet) do
    case perform_full_analysis(project_path, opts, quiet) do
      {:ok, result} ->
        progress(quiet, "Analyzed #{result.metadata.file_count} files")
        progress(quiet, "Found #{result.metadata.module_count} modules")

        # Check if there were any errors
        if result.errors != [] do
          warning("#{length(result.errors)} file(s) had errors:")

          for {file, error} <- Enum.take(result.errors, 5) do
            warning("  #{file}: #{format_error(error)}")
          end

          if length(result.errors) > 5 do
            warning("  ... and #{length(result.errors) - 5} more")
          end
        end

        # Write output
        case write_output(result.graph, result, output_file, quiet) do
          :ok ->
            progress(quiet, "")
            progress(quiet, "Full analysis complete!")
            :ok

          {:error, reason} ->
            error("Failed to write output: #{format_error(reason)}")
            exit({:shutdown, 1})
        end

      {:error, reason} ->
        error("Failed to perform analysis: #{format_error(reason)}")
        exit({:shutdown, 1})
    end
  end

  # ===========================================================================
  # Private - Option Parsing
  # ===========================================================================

  defp parse_options(args) do
    OptionParser.parse(args,
      strict: [
        input: :string,
        output: :string,
        force_full: :boolean,
        base_iri: :string,
        include_source: :boolean,
        include_git: :boolean,
        exclude_tests: :boolean,
        quiet: :boolean
      ],
      aliases: [
        i: :input,
        o: :output,
        b: :base_iri,
        q: :quiet
      ]
    )
  end

  # ===========================================================================
  # Private - Graph Loading
  # ===========================================================================

  @spec load_existing_graph(Path.t()) :: {:ok, ElixirOntologies.Graph.t()} | {:error, term()}
  defp load_existing_graph(input_file) do
    ElixirOntologies.Graph.load(input_file)
  end

  # ===========================================================================
  # Private - State File Management
  # ===========================================================================

  @spec state_file_path(Path.t()) :: Path.t()
  defp state_file_path(graph_path) do
    graph_path <> ".state"
  end

  @spec load_state(Path.t()) :: {:ok, map()} | {:error, term()}
  defp load_state(graph_path) do
    state_path = state_file_path(graph_path)

    case File.read(state_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, state} -> {:ok, state}
          {:error, reason} -> {:error, {:invalid_json, reason}}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  @spec save_state(Path.t(), ProjectAnalyzer.Result.t() | ProjectAnalyzer.UpdateResult.t()) ::
          :ok | {:error, term()}
  defp save_state(graph_path, result) do
    state_path = state_file_path(graph_path)

    # Extract analysis_state from metadata
    analysis_state = Map.get(result.metadata, :analysis_state)

    state = %{
      "version" => "1.0",
      "project" => %{
        "path" => result.project.path,
        "name" => Atom.to_string(result.project.name),
        "version" => result.project.version
      },
      "files" =>
        Enum.map(result.files, fn file_result ->
          %{
            "file_path" => file_result.file_path,
            "relative_path" => file_result.relative_path,
            "status" => if(file_result.error, do: "error", else: "ok")
          }
        end),
      "metadata" => %{
        "file_count" => Map.get(result.metadata, :file_count, length(result.files)),
        "module_count" => Map.get(result.metadata, :module_count, 0),
        "last_analysis" => DateTime.utc_now() |> DateTime.to_iso8601()
      },
      "analysis_state" => encode_analysis_state(analysis_state)
    }

    case Jason.encode(state, pretty: true) do
      {:ok, json} ->
        File.write(state_path, json)

      {:error, reason} ->
        {:error, {:encode_error, reason}}
    end
  end

  defp encode_analysis_state(nil), do: nil

  defp encode_analysis_state(%ElixirOntologies.Analyzer.ChangeTracker.State{} = state) do
    %{
      "files" =>
        Enum.map(state.files, fn {path, file_info} ->
          %{
            "path" => path,
            "mtime" => file_info.mtime,
            "size" => file_info.size
          }
        end),
      "timestamp" => state.timestamp
    }
  end

  # ===========================================================================
  # Private - State-to-Result Conversion
  # ===========================================================================

  @spec state_to_result(map(), ElixirOntologies.Graph.t(), String.t()) ::
          {:ok, ProjectAnalyzer.Result.t()} | {:error, term()}
  defp state_to_result(state, graph, project_path) do
    with {:ok, project} <- extract_project_from_state(state, project_path),
         {:ok, files} <- extract_files_from_state(state, project_path),
         {:ok, metadata} <- extract_metadata_from_state(state) do
      result = %ProjectAnalyzer.Result{
        project: project,
        files: files,
        graph: graph,
        errors: [],
        metadata: metadata
      }

      {:ok, result}
    end
  end

  defp extract_project_from_state(state, project_path) do
    project_data = state["project"]

    if is_nil(project_data) do
      {:error, :missing_project_data}
    else
      project = %ElixirOntologies.Analyzer.Project.Project{
        path: project_data["path"] || project_path,
        name: String.to_atom(project_data["name"] || "unknown"),
        version: project_data["version"],
        mix_file: Path.join(project_data["path"] || project_path, "mix.exs"),
        umbrella?: false,
        apps: [],
        deps: [],
        source_dirs: ["lib"],
        elixir_version: nil,
        metadata: %{}
      }

      {:ok, project}
    end
  end

  defp extract_files_from_state(state, _project_path) do
    files_data = state["files"]

    if is_nil(files_data) do
      {:error, :missing_files_data}
    else
      files =
        Enum.map(files_data, fn file_data ->
          %ProjectAnalyzer.FileResult{
            file_path: file_data["file_path"],
            relative_path: file_data["relative_path"],
            analysis: nil,
            status: :ok,
            error: nil
          }
        end)

      {:ok, files}
    end
  end

  defp extract_metadata_from_state(state) do
    metadata_data = state["metadata"]
    analysis_state_data = state["analysis_state"]

    if is_nil(metadata_data) do
      {:error, :missing_metadata}
    else
      metadata = %{
        file_count: metadata_data["file_count"],
        module_count: metadata_data["module_count"],
        last_analysis: metadata_data["last_analysis"],
        analysis_state: decode_analysis_state(analysis_state_data)
      }

      {:ok, metadata}
    end
  end

  defp decode_analysis_state(nil), do: nil

  defp decode_analysis_state(state_data) do
    files_data = state_data["files"] || []

    files =
      files_data
      |> Enum.map(fn fs ->
        {fs["path"],
         %ElixirOntologies.Analyzer.ChangeTracker.FileInfo{
           path: fs["path"],
           mtime: fs["mtime"],
           size: fs["size"]
         }}
      end)
      |> Map.new()

    %ElixirOntologies.Analyzer.ChangeTracker.State{
      files: files,
      timestamp: state_data["timestamp"] || :os.system_time(:second)
    }
  end

  # ===========================================================================
  # Private - Incremental Update
  # ===========================================================================

  @spec perform_incremental_update(ProjectAnalyzer.Result.t(), String.t(), keyword(), boolean()) ::
          {:ok, ProjectAnalyzer.UpdateResult.t()} | {:error, term()}
  defp perform_incremental_update(result, project_path, opts, quiet) do
    config = build_config(opts)
    analyzer_opts = build_analyzer_opts(opts)

    progress(quiet, "Performing incremental analysis...")

    case ProjectAnalyzer.update(
           result,
           project_path,
           Keyword.merge(analyzer_opts, config: config)
         ) do
      {:ok, update_result} ->
        {:ok, update_result}

      {:error, reason} ->
        {:error, {:update_failed, reason}}
    end
  end

  # ===========================================================================
  # Private - Full Analysis Fallback
  # ===========================================================================

  @spec perform_full_analysis(String.t(), keyword(), boolean()) ::
          {:ok, ProjectAnalyzer.Result.t()} | {:error, term()}
  defp perform_full_analysis(project_path, opts, quiet) do
    config = build_config(opts)
    analyzer_opts = build_analyzer_opts(opts)

    progress(quiet, "Performing full analysis...")

    case ProjectAnalyzer.analyze(project_path, Keyword.merge(analyzer_opts, config: config)) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, {:analysis_failed, reason}}
    end
  end

  # ===========================================================================
  # Private - Configuration
  # ===========================================================================

  defp build_config(opts) do
    base_config = Config.default()

    config =
      if base_iri = Keyword.get(opts, :base_iri) do
        %{base_config | base_iri: base_iri}
      else
        base_config
      end

    config =
      case Keyword.fetch(opts, :include_source) do
        {:ok, value} -> %{config | include_source_text: value}
        :error -> config
      end

    config =
      case Keyword.fetch(opts, :include_git) do
        {:ok, value} -> %{config | include_git_info: value}
        :error -> config
      end

    config
  end

  defp build_analyzer_opts(opts) do
    analyzer_opts = []

    analyzer_opts =
      case Keyword.fetch(opts, :exclude_tests) do
        {:ok, value} -> Keyword.put(analyzer_opts, :exclude_tests, value)
        :error -> analyzer_opts
      end

    analyzer_opts
  end

  # ===========================================================================
  # Private - Change Reporting
  # ===========================================================================

  @spec report_changes(ElixirOntologies.Analyzer.ChangeTracker.Changes.t(), boolean()) :: :ok
  defp report_changes(changes, quiet) do
    progress(quiet, "")
    progress(quiet, "Changes detected:")
    progress(quiet, "  - Changed: #{length(changes.changed)} file(s)")
    progress(quiet, "  - New: #{length(changes.new)} file(s)")
    progress(quiet, "  - Deleted: #{length(changes.deleted)} file(s)")
    progress(quiet, "  - Unchanged: #{length(changes.unchanged)} file(s)")

    unless Enum.empty?(changes.changed) do
      progress(quiet, "")
      progress(quiet, "Changed files:")

      changes.changed
      |> Enum.take(10)
      |> Enum.each(fn file -> progress(quiet, "  - #{file}") end)

      if length(changes.changed) > 10 do
        progress(quiet, "  ... and #{length(changes.changed) - 10} more")
      end
    end

    unless Enum.empty?(changes.new) do
      progress(quiet, "")
      progress(quiet, "New files:")

      changes.new
      |> Enum.take(10)
      |> Enum.each(fn file -> progress(quiet, "  - #{file}") end)

      if length(changes.new) > 10 do
        progress(quiet, "  ... and #{length(changes.new) - 10} more")
      end
    end

    unless Enum.empty?(changes.deleted) do
      progress(quiet, "")
      progress(quiet, "Deleted files:")

      changes.deleted
      |> Enum.take(10)
      |> Enum.each(fn file -> progress(quiet, "  - #{file}") end)

      if length(changes.deleted) > 10 do
        progress(quiet, "  ... and #{length(changes.deleted) - 10} more")
      end
    end

    :ok
  end

  # ===========================================================================
  # Private - Output Writing
  # ===========================================================================

  @spec write_output(
          ElixirOntologies.Graph.t(),
          ProjectAnalyzer.Result.t() | ProjectAnalyzer.UpdateResult.t(),
          Path.t(),
          boolean()
        ) :: :ok | {:error, term()}
  defp write_output(graph, result, output_file, quiet) do
    progress(quiet, "")
    progress(quiet, "Serializing to Turtle format...")

    # Get the Result struct (works for both Result and UpdateResult)
    result_struct =
      case result do
        %ProjectAnalyzer.UpdateResult{} -> result
        %ProjectAnalyzer.Result{} -> result
      end

    with :ok <- ElixirOntologies.Graph.save(graph, output_file),
         :ok <- save_state(output_file, result_struct) do
      progress(quiet, "Output written to #{output_file}")
      progress(quiet, "State saved to #{state_file_path(output_file)}")
      :ok
    else
      {:error, reason} ->
        {:error, {:write_failed, reason}}
    end
  end

  # ===========================================================================
  # Private - Progress and Error Reporting
  # ===========================================================================

  defp progress(true, _message), do: :ok
  defp progress(false, message), do: Mix.shell().info(message)

  defp warning(message) do
    Mix.shell().error([:yellow, "warning: ", :reset, message])
  end

  defp error(message) do
    Mix.shell().error([:red, "error: ", :reset, message])
  end

  defp format_error(%{message: message}), do: message
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
