defmodule Mix.Tasks.ElixirOntologies.Analyze do
  @moduledoc """
  Analyzes Elixir source code and generates an RDF knowledge graph.

  ## Usage

      # Analyze current project
      mix elixir_ontologies.analyze

      # Analyze specific project
      mix elixir_ontologies.analyze /path/to/project

      # Analyze single file
      mix elixir_ontologies.analyze lib/my_module.ex

      # Save to file
      mix elixir_ontologies.analyze --output output.ttl

      # Customize base IRI
      mix elixir_ontologies.analyze --base-iri https://myapp.org/code#

  ## Options

    * `--output`, `-o` - Output file path (default: stdout)
    * `--base-iri`, `-b` - Base IRI for generated resources
    * `--include-source` - Include source code text in graph (default: false)
    * `--include-git` - Include git provenance information (default: true)
    * `--exclude-tests` - Exclude test files from project analysis (default: true)
    * `--validate`, `-v` - Validate output against SHACL shapes (requires pySHACL)
    * `--quiet`, `-q` - Suppress progress output (default: false)

  ## Examples

      # Analyze project and save to file
      mix elixir_ontologies.analyze --output my_project.ttl

      # Analyze with custom base IRI and source text
      mix elixir_ontologies.analyze --base-iri https://myapp.org/ --include-source

      # Analyze single file to stdout
      mix elixir_ontologies.analyze lib/my_module.ex

      # Analyze without git info (faster)
      mix elixir_ontologies.analyze --no-include-git

      # Pipe to file
      mix elixir_ontologies.analyze > output.ttl
  """

  use Mix.Task

  alias ElixirOntologies.Analyzer.{ProjectAnalyzer, FileAnalyzer}
  alias ElixirOntologies.{Config, Validator}

  @shortdoc "Analyze Elixir code and generate RDF knowledge graph"
  @requirements ["compile"]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    # Parse command-line options
    {opts, remaining_args, invalid} = parse_options(args)

    # Handle invalid options
    if invalid != [] do
      error("Invalid options: #{inspect(invalid)}")
      Mix.Task.run("help", ["elixir_ontologies.analyze"])
      exit({:shutdown, 1})
    end

    quiet = Keyword.get(opts, :quiet, false)

    # Determine analysis mode
    case determine_analysis_mode(remaining_args) do
      {:project, path} ->
        analyze_project(path, opts, quiet)

      {:file, path} ->
        analyze_file(path, opts, quiet)

      {:error, message} ->
        error(message)
        exit({:shutdown, 1})
    end
  end

  # ===========================================================================
  # Private - Option Parsing
  # ===========================================================================

  defp parse_options(args) do
    OptionParser.parse(args,
      strict: [
        output: :string,
        base_iri: :string,
        include_source: :boolean,
        include_git: :boolean,
        exclude_tests: :boolean,
        validate: :boolean,
        quiet: :boolean
      ],
      aliases: [
        o: :output,
        b: :base_iri,
        v: :validate,
        q: :quiet
      ]
    )
  end

  # ===========================================================================
  # Private - Analysis Mode Detection
  # ===========================================================================

  defp determine_analysis_mode([]) do
    {:project, "."}
  end

  defp determine_analysis_mode([path]) do
    cond do
      File.regular?(path) -> {:file, path}
      File.dir?(path) -> {:project, path}
      true -> {:error, "Path not found: #{path}"}
    end
  end

  defp determine_analysis_mode(args) do
    {:error, "Expected 0 or 1 argument, got #{length(args)}"}
  end

  # ===========================================================================
  # Private - Project Analysis
  # ===========================================================================

  defp analyze_project(path, opts, quiet) do
    config = build_config(opts)
    analyzer_opts = build_analyzer_opts(opts)

    progress(quiet, "Analyzing project at #{Path.expand(path)}")

    case ProjectAnalyzer.analyze(path, Keyword.merge(analyzer_opts, config: config)) do
      {:ok, result} ->
        progress(quiet, "Analyzed #{result.metadata.file_count} files")
        progress(quiet, "Found #{result.metadata.module_count} modules")

        # Check for errors
        if result.errors != [] do
          warning("#{length(result.errors)} file(s) had errors:")

          for {file, error} <- Enum.take(result.errors, 5) do
            warning("  #{file}: #{format_error(error)}")
          end

          if length(result.errors) > 5 do
            warning("  ... and #{length(result.errors) - 5} more")
          end
        end

        # Serialize and output
        serialize_and_output(result.graph, opts, quiet)

        # Validate if requested
        if Keyword.get(opts, :validate, false) do
          validate_graph(result.graph, quiet)
        end

        :ok

      {:error, reason} ->
        error("Failed to analyze project: #{format_error(reason)}")
        exit({:shutdown, 1})
    end
  end

  # ===========================================================================
  # Private - File Analysis
  # ===========================================================================

  defp analyze_file(path, opts, quiet) do
    config = build_config(opts)

    progress(quiet, "Analyzing file #{Path.expand(path)}")

    case FileAnalyzer.analyze(path, config) do
      {:ok, result} ->
        progress(quiet, "Found #{length(result.modules)} module(s)")

        # Serialize and output
        serialize_and_output(result.graph, opts, quiet)

        # Validate if requested
        if Keyword.get(opts, :validate, false) do
          validate_graph(result.graph, quiet)
        end

        :ok

      {:error, reason} ->
        error("Failed to analyze file: #{format_error(reason)}")
        exit({:shutdown, 1})
    end
  end

  # ===========================================================================
  # Private - Configuration
  # ===========================================================================

  defp build_config(opts) do
    base_config = Config.default()

    # Apply command-line options to config
    config = base_config

    # Update base IRI if provided
    config =
      if base_iri = Keyword.get(opts, :base_iri) do
        %{config | base_iri: base_iri}
      else
        config
      end

    # Update include_source_text if provided
    config =
      case Keyword.fetch(opts, :include_source) do
        {:ok, value} -> %{config | include_source_text: value}
        :error -> config
      end

    # Update include_git_info if provided
    config =
      case Keyword.fetch(opts, :include_git) do
        {:ok, value} -> %{config | include_git_info: value}
        :error -> config
      end

    config
  end

  defp build_analyzer_opts(opts) do
    # Build options for ProjectAnalyzer
    analyzer_opts = []

    # Add exclude_tests option if provided
    analyzer_opts =
      case Keyword.fetch(opts, :exclude_tests) do
        {:ok, value} -> Keyword.put(analyzer_opts, :exclude_tests, value)
        :error -> analyzer_opts
      end

    analyzer_opts
  end

  # ===========================================================================
  # Private - Serialization and Output
  # ===========================================================================

  defp serialize_and_output(graph, opts, quiet) do
    progress(quiet, "Serializing to Turtle format...")

    # Serialize graph to Turtle
    case RDF.Turtle.write_string(graph.graph) do
      {:ok, turtle_string} ->
        write_output(turtle_string, opts, quiet)

      {:error, reason} ->
        error("Failed to serialize graph: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp write_output(content, opts, quiet) do
    case Keyword.get(opts, :output) do
      nil ->
        # Write to stdout
        IO.puts(content)
        progress(quiet, "Output written to stdout")

      output_file ->
        # Write to file
        case File.write(output_file, content) do
          :ok ->
            progress(quiet, "Output written to #{output_file}")

          {:error, reason} ->
            error("Failed to write output file: #{:file.format_error(reason)}")
            exit({:shutdown, 1})
        end
    end
  end

  # ===========================================================================
  # Private - Validation
  # ===========================================================================

  defp validate_graph(graph, quiet) do
    progress(quiet, "Validating graph against SHACL shapes...")

    case Validator.validate(graph) do
      {:ok, report} ->
        if report.conforms? do
          progress(quiet, "Validation: PASSED")
          Mix.shell().info([:green, "✓ ", :reset, "Graph conforms to SHACL shapes"])
        else
          # Filter for violations only (ignore warnings and info)
          violations = Enum.filter(report.results, fn r -> r.severity == :violation end)

          error("Validation: FAILED")
          Mix.shell().info("")
          Mix.shell().info("Found #{length(violations)} violation(s):")

          for violation <- Enum.take(violations, 10) do
            Mix.shell().info("")
            Mix.shell().info([:red, "  ✗ ", :reset, violation.message])

            if violation.focus_node do
              Mix.shell().info("    Focus node: #{inspect(violation.focus_node)}")
            end

            if violation.path do
              Mix.shell().info("    Path: #{inspect(violation.path)}")
            end
          end

          if length(violations) > 10 do
            Mix.shell().info("")
            Mix.shell().info("  ... and #{length(violations) - 10} more violations")
          end

          exit({:shutdown, 1})
        end

      {:error, reason} ->
        error("Validation error: #{format_error(reason)}")
        exit({:shutdown, 1})
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
