defmodule ElixirOntologies.Validator.Report do
  @moduledoc """
  SHACL validation report structure.

  Represents the results of validating an RDF graph against SHACL shapes.
  A report contains:
  - Overall conformance status
  - Violations (constraint failures)
  - Warnings (non-critical issues)
  - Info messages (informational notices)

  ## Example

      iex> report = %ElixirOntologies.Validator.Report{
      ...>   conforms: false,
      ...>   violations: [%ElixirOntologies.Validator.Violation{message: "Missing required property"}],
      ...>   warnings: [],
      ...>   info: []
      ...> }
      iex> report.conforms
      false

  """

  alias ElixirOntologies.Validator.{Violation, Warning, Info}

  @type t :: %__MODULE__{
          conforms: boolean(),
          violations: [Violation.t()],
          warnings: [Warning.t()],
          info: [Info.t()],
          shapes_graph_uri: String.t() | nil,
          data_graph_uri: String.t() | nil
        }

  defstruct conforms: true,
            violations: [],
            warnings: [],
            info: [],
            shapes_graph_uri: nil,
            data_graph_uri: nil

  @doc """
  Creates a new conformant report (no issues).

  ## Examples

      iex> report = ElixirOntologies.Validator.Report.new()
      iex> report.conforms
      true
      iex> report.violations
      []

  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Creates a new report with the given attributes.

  ## Examples

      iex> violations = [%ElixirOntologies.Validator.Violation{message: "Error"}]
      iex> report = ElixirOntologies.Validator.Report.new(conforms: false, violations: violations)
      iex> report.conforms
      false
      iex> length(report.violations)
      1

  """
  @spec new(keyword()) :: t()
  def new(attrs) when is_list(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Returns true if the report has any violations.

  ## Examples

      iex> report = ElixirOntologies.Validator.Report.new()
      iex> ElixirOntologies.Validator.Report.has_violations?(report)
      false

      iex> violations = [%ElixirOntologies.Validator.Violation{message: "Error"}]
      iex> report = ElixirOntologies.Validator.Report.new(violations: violations)
      iex> ElixirOntologies.Validator.Report.has_violations?(report)
      true

  """
  @spec has_violations?(t()) :: boolean()
  def has_violations?(%__MODULE__{violations: []}), do: false
  def has_violations?(%__MODULE__{violations: [_ | _]}), do: true

  @doc """
  Returns the total number of issues (violations + warnings + info).

  ## Examples

      iex> report = ElixirOntologies.Validator.Report.new()
      iex> ElixirOntologies.Validator.Report.issue_count(report)
      0

  """
  @spec issue_count(t()) :: non_neg_integer()
  def issue_count(%__MODULE__{violations: v, warnings: w, info: i}) do
    length(v) + length(w) + length(i)
  end
end

defmodule ElixirOntologies.Validator.Violation do
  @moduledoc """
  Represents a SHACL constraint violation.

  A violation indicates that the RDF graph does not conform to the SHACL shapes.
  Each violation contains:
  - Focus node: The RDF node that violated the constraint
  - Result path: The property path that was constrained
  - Value: The actual value that violated the constraint
  - Message: Human-readable error message
  - Severity: Always `:violation` for this type
  - Source shape: The SHACL shape that was violated
  - Constraint component: Which SHACL constraint failed

  ## Example

      %ElixirOntologies.Validator.Violation{
        focus_node: ~I<http://example.org/MyModule>,
        result_path: ~I<http://example.org/hasFunction>,
        value: nil,
        message: "Required property hasFunction is missing",
        severity: :violation,
        source_shape: ~I<http://example.org/shapes#ModuleShape>,
        constraint_component: ~I<http://www.w3.org/ns/shacl#MinCountConstraintComponent>
      }

  """

  @type t :: %__MODULE__{
          focus_node: term() | nil,
          result_path: term() | nil,
          value: term() | nil,
          message: String.t(),
          severity: :violation | :warning | :info,
          source_shape: term() | nil,
          constraint_component: term() | nil
        }

  defstruct focus_node: nil,
            result_path: nil,
            value: nil,
            message: "",
            severity: :violation,
            source_shape: nil,
            constraint_component: nil

  @doc """
  Creates a new violation with the given attributes.

  ## Examples

      iex> violation = ElixirOntologies.Validator.Violation.new(message: "Missing required property")
      iex> violation.message
      "Missing required property"
      iex> violation.severity
      :violation

  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) do
    struct(__MODULE__, attrs)
  end
end

defmodule ElixirOntologies.Validator.Warning do
  @moduledoc """
  Represents a SHACL warning (non-critical issue).

  Warnings indicate potential issues that don't prevent conformance but may
  indicate problems or suboptimal patterns in the RDF graph.

  Structure is identical to Violation but with severity `:warning`.

  ## Example

      %ElixirOntologies.Validator.Warning{
        focus_node: ~I<http://example.org/MyFunction>,
        message: "Function name does not follow naming conventions",
        severity: :warning
      }

  """

  @type t :: %__MODULE__{
          focus_node: term() | nil,
          result_path: term() | nil,
          value: term() | nil,
          message: String.t(),
          severity: :violation | :warning | :info,
          source_shape: term() | nil,
          constraint_component: term() | nil
        }

  defstruct focus_node: nil,
            result_path: nil,
            value: nil,
            message: "",
            severity: :warning,
            source_shape: nil,
            constraint_component: nil

  @doc """
  Creates a new warning with the given attributes.

  ## Examples

      iex> warning = ElixirOntologies.Validator.Warning.new(message: "Potential issue detected")
      iex> warning.message
      "Potential issue detected"
      iex> warning.severity
      :warning

  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) do
    struct(__MODULE__, attrs)
  end
end

defmodule ElixirOntologies.Validator.Info do
  @moduledoc """
  Represents informational SHACL messages.

  Info messages provide additional information about the validation process
  or the RDF graph without indicating any issues.

  Structure is identical to Violation but with severity `:info`.

  ## Example

      %ElixirOntologies.Validator.Info{
        message: "Validation completed successfully",
        severity: :info
      }

  """

  @type t :: %__MODULE__{
          focus_node: term() | nil,
          result_path: term() | nil,
          value: term() | nil,
          message: String.t(),
          severity: :violation | :warning | :info,
          source_shape: term() | nil,
          constraint_component: term() | nil
        }

  defstruct focus_node: nil,
            result_path: nil,
            value: nil,
            message: "",
            severity: :info,
            source_shape: nil,
            constraint_component: nil

  @doc """
  Creates a new info message with the given attributes.

  ## Examples

      iex> info = ElixirOntologies.Validator.Info.new(message: "Validation completed")
      iex> info.message
      "Validation completed"
      iex> info.severity
      :info

  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) do
    struct(__MODULE__, attrs)
  end
end
