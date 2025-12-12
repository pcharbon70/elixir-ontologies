defmodule ElixirOntologies.SHACL.Model.ValidationReport do
  @moduledoc """
  Represents a SHACL validation report (sh:ValidationReport).

  A validation report aggregates all validation results from validating a
  data graph against a shapes graph. The report's `conforms?` field indicates
  whether the data graph fully conforms to the SHACL shapes (no violations).

  ## Conformance Semantics

  A data graph **conforms** if and only if there are **zero** validation results with
  severity `:violation`. Results with severity `:warning` or `:info` do not affect
  conformance status.

  The `conforms?` field is computed as:

      conforms? = Enum.all?(results, fn r -> r.severity != :violation end)

  Or equivalently:

      conforms? = Enum.count(results, & &1.severity == :violation) == 0

  ## Fields

  - `conforms?` - True if no violations found, false if any violations exist
  - `results` - List of all validation results (violations, warnings, info messages)

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.{ValidationReport, ValidationResult}
      iex> # Conformant graph (no violations)
      iex> %ValidationReport{
      ...>   conforms?: true,
      ...>   results: []
      ...> }
      %ElixirOntologies.SHACL.Model.ValidationReport{
        conforms?: true,
        results: []
      }

      iex> # Non-conformant graph (has violations)
      iex> %ValidationReport{
      ...>   conforms?: false,
      ...>   results: [
      ...>     %ValidationResult{
      ...>       severity: :violation,
      ...>       message: "Module name is invalid",
      ...>       focus_node: ~I<http://example.org/BadModule>,
      ...>       path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
      ...>       source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
      ...>       details: %{}
      ...>     }
      ...>   ]
      ...> }
      %ElixirOntologies.SHACL.Model.ValidationReport{
        conforms?: false,
        results: [%ElixirOntologies.SHACL.Model.ValidationResult{severity: :violation, ...}]
      }

      iex> # Graph with warnings but still conformant
      iex> %ValidationReport{
      ...>   conforms?: true,
      ...>   results: [
      ...>     %ValidationResult{
      ...>       severity: :warning,
      ...>       message: "Consider adding documentation",
      ...>       focus_node: ~I<http://example.org/MyModule#foo/2>,
      ...>       path: ~I<https://w3id.org/elixir-code/structure#documentation>,
      ...>       source_shape: ~I<https://w3id.org/elixir-code/shapes#DocumentationShape>,
      ...>       details: %{}
      ...>     }
      ...>   ]
      ...> }
      %ElixirOntologies.SHACL.Model.ValidationReport{
        conforms?: true,
        results: [%ElixirOntologies.SHACL.Model.ValidationResult{severity: :warning, ...}]
      }

  ## Real-World Usage

  Validating Elixir code against elixir-shapes.ttl:

      # Valid Elixir module - conforms
      %ValidationReport{
        conforms?: true,
        results: []
      }

      # Module with multiple violations
      %ValidationReport{
        conforms?: false,
        results: [
          %ValidationResult{
            severity: :violation,
            focus_node: ~I<http://example.org/BadModule>,
            path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
            source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
            message: "Module name must match pattern ^[A-Z][a-zA-Z0-9_]*$",
            details: %{actual_value: "bad_name"}
          },
          %ValidationResult{
            severity: :violation,
            focus_node: ~I<http://example.org/BadModule#foo/2>,
            path: nil,
            source_shape: ~I<https://w3id.org/elixir-code/shapes#FunctionArityMatchShape>,
            message: "Function arity must match parameter count",
            details: %{arity: 2, parameter_count: 3}
          }
        ]
      }

      # Module with violations and warnings
      %ValidationReport{
        conforms?: false,  # false because of violation, not because of warning
        results: [
          %ValidationResult{
            severity: :violation,
            message: "Required property missing",
            ...
          },
          %ValidationResult{
            severity: :warning,
            message: "Consider adding type specs",
            ...
          },
          %ValidationResult{
            severity: :info,
            message: "Documentation coverage: 80%",
            ...
          }
        ]
      }

  ## Constructing Reports

  Reports are typically constructed by the SHACL validator engine after running
  all constraint checks:

      # Collect all results from validation
      results = validate_all_shapes(data_graph, shapes)

      # Compute conformance
      conforms? = Enum.all?(results, fn r -> r.severity != :violation end)

      # Build report
      %ValidationReport{
        conforms?: conforms?,
        results: results
      }

  ## Serialization

  The SHACL.Writer module (task 11.1.3) will serialize this struct to RDF/Turtle format
  following the SHACL validation report vocabulary:

      @prefix sh: <http://www.w3.org/ns/shacl#> .

      [] a sh:ValidationReport ;
        sh:conforms false ;
        sh:result [
          a sh:ValidationResult ;
          sh:focusNode <http://example.org/BadModule> ;
          sh:resultPath <.../moduleName> ;
          sh:sourceShape <.../ModuleShape> ;
          sh:resultSeverity sh:Violation ;
          sh:resultMessage "Module name is invalid"
        ] .
  """

  alias ElixirOntologies.SHACL.Model.ValidationResult

  defstruct [
    # boolean()
    conforms?: true,
    # [ValidationResult.t()]
    results: []
  ]

  @type t :: %__MODULE__{
          conforms?: boolean(),
          results: [ValidationResult.t()]
        }

  @doc """
  Creates a ValidationReport from a legacy Validator.Report struct.

  This adapter function provides backward compatibility by converting
  the older Report structure (with separate violations/warnings/info lists)
  into the SHACL-compliant ValidationReport structure (with unified results list).

  ## Field Mapping

  - `Report.conforms` → `ValidationReport.conforms?`
  - `Report.violations` → results with severity `:violation`
  - `Report.warnings` → results with severity `:warning`
  - `Report.info` → results with severity `:info`

  ## Examples

      iex> alias ElixirOntologies.Validator.{Report, Violation}
      iex> alias ElixirOntologies.SHACL.Model.ValidationReport
      iex>
      iex> legacy_report = %Report{
      ...>   conforms: false,
      ...>   violations: [%Violation{message: "Error"}],
      ...>   warnings: []
      ...> }
      iex>
      iex> validation_report = ValidationReport.from_legacy_report(legacy_report)
      iex> validation_report.conforms?
      false
      iex> length(validation_report.results)
      1

  """
  @spec from_legacy_report(ElixirOntologies.Validator.Report.t()) :: t()
  def from_legacy_report(%ElixirOntologies.Validator.Report{} = report) do
    # Convert violations
    violation_results =
      Enum.map(report.violations, fn v ->
        %ValidationResult{
          focus_node: v.focus_node,
          path: v.result_path,
          source_shape: v.source_shape,
          severity: :violation,
          message: v.message,
          details: %{
            value: v.value,
            constraint_component: v.constraint_component
          }
        }
      end)

    # Convert warnings
    warning_results =
      Enum.map(report.warnings, fn w ->
        %ValidationResult{
          focus_node: w.focus_node,
          path: w.result_path,
          source_shape: w.source_shape,
          severity: :warning,
          message: w.message,
          details: %{
            value: w.value,
            constraint_component: w.constraint_component
          }
        }
      end)

    # Convert info messages
    info_results =
      Enum.map(report.info, fn i ->
        %ValidationResult{
          focus_node: i.focus_node,
          path: i.result_path,
          source_shape: i.source_shape,
          severity: :info,
          message: i.message,
          details: %{
            value: i.value,
            constraint_component: i.constraint_component
          }
        }
      end)

    # Combine all results
    all_results = violation_results ++ warning_results ++ info_results

    %__MODULE__{
      conforms?: report.conforms,
      results: all_results
    }
  end
end
