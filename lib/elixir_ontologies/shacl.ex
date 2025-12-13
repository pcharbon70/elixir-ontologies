defmodule ElixirOntologies.SHACL do
  @moduledoc """
  Public API for SHACL validation of RDF graphs.

  This module provides a clean, well-documented interface for validating
  RDF graphs against SHACL shapes using the native Elixir SHACL implementation.

  ## Quick Start

      # Validate RDF graphs
      {:ok, data} = RDF.Turtle.read_file("data.ttl")
      {:ok, shapes} = RDF.Turtle.read_file("shapes.ttl")
      {:ok, report} = SHACL.validate(data, shapes)

      if report.conforms? do
        IO.puts("Valid!")
      else
        IO.puts("Found violations:")
        Enum.each(report.results, fn r ->
          IO.puts("  - \#{r.message}")
        end)
      end

      # Validate files directly
      {:ok, report} = SHACL.validate_file("data.ttl", "shapes.ttl")

  ## Features

  - Native Elixir implementation (no external dependencies)
  - Supports core SHACL constraints (cardinality, type, string, value, qualified)
  - Supports SPARQL-based constraints for complex validation rules
  - Parallel validation for performance
  - Structured validation reports compliant with SHACL specification

  ## Validation Options

  - `:parallel` - Enable parallel validation across shapes (default: `true`)
  - `:max_concurrency` - Maximum concurrent validation tasks (default: `System.schedulers_online()`)
  - `:timeout` - Validation timeout per shape in milliseconds (default: `5000`)

  ## Validation Reports

  Validation returns a `SHACL.Model.ValidationReport` struct containing:

  - `conforms?` - Boolean indicating overall conformance
  - `results` - List of `SHACL.Model.ValidationResult` structs (violations, warnings, info)

  Each `ValidationResult` includes:

  - `focus_node` - The RDF node that violated the constraint
  - `path` - The property path that was constrained (nil for node-level constraints)
  - `severity` - `:violation`, `:warning`, or `:info`
  - `source_constraint_component` - The SHACL constraint that was violated
  - `message` - Human-readable error message
  - `details` - Map with constraint-specific details

  ## Examples

      # Basic validation
      {:ok, data} = RDF.Turtle.read_file("my_data.ttl")
      {:ok, shapes} = RDF.Turtle.read_file("my_shapes.ttl")
      {:ok, report} = SHACL.validate(data, shapes)

      if report.conforms? do
        IO.puts("Data conforms to shapes!")
      else
        violations = Enum.filter(report.results, fn r -> r.severity == :violation end)
        IO.puts("Found \#{length(violations)} violations")

        Enum.each(violations, fn v ->
          IO.puts("  Focus: \#{inspect(v.focus_node)}")
          IO.puts("  Message: \#{v.message}")
        end)
      end

      # Validate with options
      {:ok, report} = SHACL.validate(data, shapes,
        parallel: false,
        timeout: 10_000
      )

      # Validate files directly (convenience)
      {:ok, report} = SHACL.validate_file("data.ttl", "shapes.ttl")

      # Handle validation errors
      case SHACL.validate_file("data.ttl", "shapes.ttl") do
        {:ok, report} ->
          IO.puts("Validation complete: \#{report.conforms?}")

        {:error, {:file_read_error, :data, path, reason}} ->
          IO.puts("Failed to read data file \#{path}: \#{inspect(reason)}")

        {:error, {:file_read_error, :shapes, path, reason}} ->
          IO.puts("Failed to read shapes file \#{path}: \#{inspect(reason)}")

        {:error, reason} ->
          IO.puts("Validation error: \#{inspect(reason)}")
      end

  ## See Also

  - `ElixirOntologies.SHACL.Validator` - Internal validation orchestration engine
  - `ElixirOntologies.SHACL.Model.ValidationReport` - Report structure documentation
  - `ElixirOntologies.SHACL.Model.ValidationResult` - Individual result structure
  - `ElixirOntologies.SHACL.Reader` - SHACL shapes parser
  - `ElixirOntologies.SHACL.Writer` - Validation report serializer
  """

  alias ElixirOntologies.SHACL.{Validator, Model}

  @typedoc """
  SHACL validation options.

  - `:parallel` - Enable parallel validation (default: `true`)
  - `:max_concurrency` - Max concurrent tasks (default: `System.schedulers_online()`)
  - `:timeout` - Validation timeout per shape in ms (default: `5000`)
  """
  @type option ::
          {:parallel, boolean()}
          | {:max_concurrency, pos_integer()}
          | {:timeout, timeout()}

  @typedoc """
  SHACL validation result.

  - `{:ok, report}` - Validation completed, check `report.conforms?` for conformance
  - `{:error, reason}` - Validation failed due to error
  """
  @type validation_result ::
          {:ok, Model.ValidationReport.t()} | {:error, term()}

  @doc """
  Validates an RDF data graph against SHACL shapes.

  This is the main validation function. It takes an RDF data graph and a SHACL
  shapes graph, validates the data against the shapes, and returns a structured
  validation report.

  ## Parameters

  - `data_graph` - `RDF.Graph.t()` containing the data to validate
  - `shapes_graph` - `RDF.Graph.t()` containing SHACL shape definitions
  - `opts` - Keyword list of validation options (see module documentation)

  ## Returns

  - `{:ok, report}` - Validation completed successfully. Check `report.conforms?`
    to determine if data conforms to shapes. `report.results` contains any
    violations, warnings, or informational messages.
  - `{:error, reason}` - Validation failed due to an error (e.g., malformed
    shapes, internal error)

  ## Examples

      # Basic validation
      {:ok, data} = RDF.Turtle.read_file("data.ttl")
      {:ok, shapes} = RDF.Turtle.read_file("shapes.ttl")
      {:ok, report} = SHACL.validate(data, shapes)

      if report.conforms? do
        IO.puts("Valid!")
      else
        IO.puts("Found \#{length(report.results)} issues")

        Enum.each(report.results, fn result ->
          IO.puts("[\#{result.severity}] \#{result.message}")
          if result.focus_node do
            IO.puts("  Focus node: \#{inspect(result.focus_node)}")
          end
          if result.path do
            IO.puts("  Path: \#{inspect(result.path)}")
          end
        end)
      end

      # Validation with custom options
      {:ok, report} = SHACL.validate(data, shapes,
        parallel: false,        # Disable parallel validation
        timeout: 10_000         # 10 second timeout per shape
      )

      # Sequential validation for debugging
      {:ok, report} = SHACL.validate(data, shapes, parallel: false)

      # High concurrency for large datasets
      {:ok, report} = SHACL.validate(data, shapes, max_concurrency: 16)
  """
  @spec validate(RDF.Graph.t(), RDF.Graph.t(), [option()]) :: validation_result()
  def validate(data_graph, shapes_graph, opts \\ []) do
    Validator.run(data_graph, shapes_graph, opts)
  end

  @doc """
  Validates RDF Turtle files directly.

  Convenience function that reads Turtle files from disk and validates them.
  This is useful for command-line tools, scripts, and simple validation workflows.

  ## Parameters

  - `data_file` - Path to Turtle file containing data to validate
  - `shapes_file` - Path to Turtle file containing SHACL shape definitions
  - `opts` - Keyword list of validation options (see module documentation)

  ## Returns

  - `{:ok, report}` - Files read successfully and validation completed
  - `{:error, {:file_read_error, type, path, reason}}` - Failed to read file
    - `type` is `:data` or `:shapes` indicating which file failed
    - `path` is the file path that failed
    - `reason` is the underlying error
  - `{:error, reason}` - Validation failed due to other error

  ## Examples

      # Validate files
      {:ok, report} = SHACL.validate_file("data.ttl", "shapes.ttl")

      if report.conforms? do
        IO.puts("Files are valid!")
      else
        IO.puts("Validation failed")
      end

      # With validation options
      {:ok, report} = SHACL.validate_file(
        "large_data.ttl",
        "complex_shapes.ttl",
        parallel: true,
        max_concurrency: 8
      )

      # Handle file read errors
      case SHACL.validate_file("data.ttl", "shapes.ttl") do
        {:ok, report} ->
          IO.puts("Validation complete")

        {:error, {:file_read_error, :data, path, :enoent}} ->
          IO.puts("Data file not found: \#{path}")

        {:error, {:file_read_error, :shapes, path, :enoent}} ->
          IO.puts("Shapes file not found: \#{path}")

        {:error, {:file_read_error, type, path, reason}} ->
          IO.puts("Failed to read \#{type} file \#{path}: \#{inspect(reason)}")

        {:error, reason} ->
          IO.puts("Validation error: \#{inspect(reason)}")
      end

      # Validate against default Elixir ontology shapes
      shapes_path = Path.join(
        :code.priv_dir(:elixir_ontologies),
        "ontologies/elixir-shapes.ttl"
      )
      {:ok, report} = SHACL.validate_file("my_elixir_graph.ttl", shapes_path)
  """
  @spec validate_file(Path.t(), Path.t(), [option()]) :: validation_result()
  def validate_file(data_file, shapes_file, opts \\ []) do
    with {:ok, data_graph} <- read_turtle_file(data_file, :data),
         {:ok, shapes_graph} <- read_turtle_file(shapes_file, :shapes) do
      validate(data_graph, shapes_graph, opts)
    end
  end

  # Private helper to read Turtle files with error context
  @spec read_turtle_file(Path.t(), :data | :shapes) ::
          {:ok, RDF.Graph.t()} | {:error, term()}
  defp read_turtle_file(path, type) do
    case RDF.Turtle.read_file(path) do
      {:ok, graph} ->
        {:ok, graph}

      {:error, reason} ->
        {:error, {:file_read_error, type, path, reason}}
    end
  end
end
