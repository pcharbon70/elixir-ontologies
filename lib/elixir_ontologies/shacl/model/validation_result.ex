defmodule ElixirOntologies.SHACL.Model.ValidationResult do
  @moduledoc """
  Represents a single SHACL validation result (sh:ValidationResult).

  A validation result describes one specific constraint violation found during
  validation. It identifies:
  - Which focus node violated the constraint
  - Which property path was constrained (if applicable)
  - Which shape was violated
  - The severity of the violation
  - A human-readable error message

  ## Severity Levels

  SHACL defines three severity levels:

  - `:violation` - Error that causes non-conformance (sh:Violation)
  - `:warning` - Non-critical issue that does not prevent conformance (sh:Warning)
  - `:info` - Informational message (sh:Info)

  Only `:violation` severity affects the conformance status of a ValidationReport.

  ## Fields

  - `focus_node` - The RDF node (IRI, blank node, or literal) that violated the constraint
  - `path` - The property path that was constrained (nil for node-level constraints)
  - `source_shape` - The IRI of the shape that was violated
  - `severity` - Level of the violation (`:violation`, `:warning`, or `:info`)
  - `message` - Human-readable error description
  - `details` - Additional information map (e.g., actual value, expected value, constraint type)

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.ValidationResult
      iex> # Property constraint violation
      iex> %ValidationResult{
      ...>   focus_node: ~I<http://example.org/Module1>,
      ...>   path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
      ...>   source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
      ...>   severity: :violation,
      ...>   message: "Module name must match pattern ^[A-Z]...",
      ...>   details: %{
      ...>     actual_value: "invalid_name",
      ...>     constraint_component: ~I<http://www.w3.org/ns/shacl#PatternConstraintComponent>
      ...>   }
      ...> }
      %ElixirOntologies.SHACL.Model.ValidationResult{
        focus_node: ~I<http://example.org/Module1>,
        path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
        severity: :violation,
        message: "Module name must match pattern ^[A-Z]...",
        details: %{...}
      }

      iex> # SPARQL constraint violation (no path)
      iex> %ValidationResult{
      ...>   focus_node: ~I<http://example.org/Function1>,
      ...>   path: nil,
      ...>   source_shape: ~I<https://w3id.org/elixir-code/shapes#FunctionArityMatchShape>,
      ...>   severity: :violation,
      ...>   message: "Function arity must match parameter count",
      ...>   details: %{
      ...>     arity: 2,
      ...>     parameter_count: 3
      ...>   }
      ...> }
      %ElixirOntologies.SHACL.Model.ValidationResult{
        focus_node: ~I<http://example.org/Function1>,
        path: nil,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#FunctionArityMatchShape>,
        severity: :violation,
        message: "Function arity must match parameter count",
        details: %{arity: 2, parameter_count: 3}
      }

  ## Real-World Usage

  From validating Elixir code against elixir-shapes.ttl:

      # Cardinality violation
      %ValidationResult{
        focus_node: ~I<http://example.org/MyModule>,
        path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
        severity: :violation,
        message: "Module must have exactly one name",
        details: %{
          min_count: 1,
          max_count: 1,
          actual_count: 0
        }
      }

      # Datatype violation
      %ValidationResult{
        focus_node: ~I<http://example.org/MyModule#foo/2>,
        path: ~I<https://w3id.org/elixir-code/structure#arity>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#FunctionShape>,
        severity: :violation,
        message: "Arity must be a non-negative integer",
        details: %{
          expected_datatype: ~I<http://www.w3.org/2001/XMLSchema#nonNegativeInteger>,
          actual_value: "not a number"
        }
      }

      # Value enumeration violation
      %ValidationResult{
        focus_node: ~I<http://example.org/MySupervisor>,
        path: ~I<https://w3id.org/elixir-code/otp#supervisorStrategy>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#SupervisorShape>,
        severity: :violation,
        message: "Supervisor strategy must be one of the allowed values",
        details: %{
          allowed_values: [
            ~I<https://w3id.org/elixir-code/otp#OneForOne>,
            ~I<https://w3id.org/elixir-code/otp#OneForAll>
          ],
          actual_value: ~I<https://w3id.org/elixir-code/otp#InvalidStrategy>
        }
      }

  ## Warning vs Violation

  Warnings do not prevent conformance:

      # Warning about missing documentation (graph still conforms)
      %ValidationResult{
        focus_node: ~I<http://example.org/MyModule#foo/2>,
        path: ~I<https://w3id.org/elixir-code/structure#documentation>,
        source_shape: ~I<https://w3id.org/elixir-code/shapes#DocumentationShape>,
        severity: :warning,
        message: "Consider adding documentation to public functions",
        details: %{}
      }
  """

  defstruct [
    # RDF.Term.t()
    :focus_node,
    # RDF.IRI.t() | nil
    :path,
    # RDF.IRI.t()
    :source_shape,
    # :violation | :warning | :info
    :severity,
    # String.t()
    :message,
    # map()
    :details
  ]

  @type severity :: :violation | :warning | :info

  @type t :: %__MODULE__{
          focus_node: RDF.Term.t(),
          path: RDF.IRI.t() | nil,
          source_shape: RDF.IRI.t(),
          severity: severity(),
          message: String.t(),
          details: map()
        }
end
