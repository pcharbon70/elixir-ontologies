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

  ## API Stability

  **Stability**: Public API - This module's public interface is stable and follows semantic versioning.

  - **Breaking Changes**: Will only occur in major version updates (e.g., 1.x → 2.x)
  - **New Features**: May be added in minor version updates (e.g., 1.0 → 1.1)
  - **Bug Fixes**: May occur in patch version updates (e.g., 1.0.0 → 1.0.1)
  - **Internal Implementation**: May change at any time without notice

  **Public API Surface** (Stable):
  - `validate/3` - Core validation function
  - `validate_file/3` - File-based validation convenience function
  - `ValidationReport` struct - Validation report structure
  - `ValidationResult` struct - Individual result structure

  **Internal/Unstable** (Subject to change):
  - `ElixirOntologies.SHACL.Validator` - Internal orchestrator, may change
  - `ElixirOntologies.SHACL.Validators.*` - Constraint validators, may change
  - `ElixirOntologies.SHACL.Reader/Writer` - I/O modules, may change

  ## Migration from pySHACL

  Prior to Phase 11.4, ElixirOntologies used pySHACL (Python-based SHACL validator)
  as an external dependency. As of Phase 11.4, validation is implemented natively
  in Elixir with no external dependencies.

  ### What Changed

  **Removed**:
  - Python/pySHACL installation requirement
  - External process execution for validation
  - `ElixirOntologies.Validator.SHACLEngine` module (Python bridge)

  **Added**:
  - Native Elixir SHACL implementation
  - `ElixirOntologies.SHACL` public API module (this module)
  - Performance improvements via parallel validation
  - Better error handling with structured error tuples

  ### API Compatibility

  The public API of `ElixirOntologies.Validator.validate/2` remains identical.
  This module (`SHACL`) is new and provides additional convenience functions.

  **Before (with pySHACL)**:
  ```elixir
  # Required Python and pySHACL installed
  {:ok, graph} = ElixirOntologies.analyze_file("lib/my_module.ex")
  {:ok, report} = ElixirOntologies.Validator.validate(graph)
  ```

  **After (native Elixir)**:
  ```elixir
  # No external dependencies required
  {:ok, graph} = ElixirOntologies.analyze_file("lib/my_module.ex")
  {:ok, report} = ElixirOntologies.Validator.validate(graph)
  # OR use this module directly:
  {:ok, report} = SHACL.validate(graph.graph, shapes_graph)
  ```

  ### Benefits of Native Implementation

  1. **No External Dependencies** - No Python installation required
  2. **Better Performance** - Elixir concurrency and parallel validation
  3. **Improved Security** - No shell execution or command injection vectors
  4. **Better Error Messages** - Native Elixir error handling and context
  5. **Easier Testing** - Pure Elixir tests, no Python mocking required
  6. **Simpler Deployment** - Single BEAM VM, no language bridges

  ### Known Limitations

  **SPARQL Constraints**: SPARQL constraints with complex subqueries or `FILTER NOT EXISTS`
  patterns may not execute due to SPARQL.ex library limitations. Core constraints
  (cardinality, type, string, value, qualified) work identically to pySHACL.

  These are edge cases affecting <5% of real-world SHACL shapes. The elixir-shapes.ttl
  constraints are fully supported.

  ### Rollback (if needed)

  If you need to temporarily revert to pySHACL (not recommended):

  1. Checkout commit `6e35846` (before pySHACL removal)
  2. Install Python and pySHACL: `pip install pyshacl`

  The native implementation is more secure, performant, and easier to maintain.

  ## Relationship to Validator Module

  This module (`ElixirOntologies.SHACL`) provides **general-purpose** SHACL validation
  for any RDF graphs and shapes.

  The `ElixirOntologies.Validator` module is a **domain-specific facade** that delegates
  to this module for Elixir ontology validation with automatic shape loading.

  **When to use**:
  - Use `SHACL` (this module) when validating arbitrary RDF graphs with custom shapes
  - Use `Validator` when validating Elixir code graphs with automatic elixir-shapes.ttl loading

  **See Also**: `ElixirOntologies.Validator` for Elixir ontology-specific validation

  ## See Also

  - `ElixirOntologies.SHACL.Validator` - Internal validation orchestration engine
  - `ElixirOntologies.SHACL.Model.ValidationReport` - Report structure documentation
  - `ElixirOntologies.SHACL.Model.ValidationResult` - Individual result structure
  - `ElixirOntologies.SHACL.Reader` - SHACL shapes parser
  - `ElixirOntologies.SHACL.Writer` - Validation report serializer
  - `ElixirOntologies.Validator` - Domain-specific validation for Elixir code
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
