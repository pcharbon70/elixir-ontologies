defmodule ElixirOntologies.SHACL.Model.PropertyShape do
  @moduledoc """
  Represents a SHACL property shape (sh:property).

  Property shapes define constraints on the values of a specific property path
  for focus nodes. This struct supports all constraint types used in elixir-shapes.ttl.

  ## Constraint Categories

  ### Cardinality Constraints
  - `min_count` - Minimum number of values (sh:minCount)
  - `max_count` - Maximum number of values (sh:maxCount)

  ### Type Constraints
  - `datatype` - Required RDF datatype for literals (sh:datatype)
  - `class` - Required RDF class for resources (sh:class)

  ### String Constraints
  - `pattern` - Compiled regex pattern for string matching (sh:pattern)
  - `min_length` - Minimum string length (sh:minLength)

  ### Numeric Constraints
  - `min_inclusive` - Minimum inclusive value for numbers (sh:minInclusive)
  - `max_inclusive` - Maximum inclusive value for numbers (sh:maxInclusive)

  ### Value Constraints
  - `in` - List of allowed RDF terms (sh:in)
  - `has_value` - Specific required value (sh:hasValue)

  ### Qualified Constraints
  - `qualified_class` - Class constraint for qualified value shapes (sh:qualifiedValueShape)
  - `qualified_min_count` - Minimum count for qualified values (sh:qualifiedMinCount)

  ## Fields

  - `id` - Identifier for this property shape (typically a blank node, required)
  - `path` - The property path being constrained (IRI, required)
  - `message` - Human-readable error message for violations (optional)

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.PropertyShape
      iex> # Cardinality constraint
      iex> %PropertyShape{
      ...>   id: RDF.bnode("b1"),
      ...>   path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
      ...>   min_count: 1,
      ...>   max_count: 1,
      ...>   message: "Module must have exactly one name"
      ...> }
      %ElixirOntologies.SHACL.Model.PropertyShape{
        id: ~B<b1>,
        path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
        message: "Module must have exactly one name",
        min_count: 1,
        max_count: 1,
        ...
      }

      iex> # Pattern constraint
      iex> %PropertyShape{
      ...>   id: RDF.bnode("b2"),
      ...>   path: ~I<https://w3id.org/elixir-code/structure#functionName>,
      ...>   pattern: ~r/^[a-z_][a-z0-9_]*[!?]?$/,
      ...>   message: "Function name must be valid Elixir identifier"
      ...> }
      %ElixirOntologies.SHACL.Model.PropertyShape{
        id: ~B<b2>,
        path: ~I<https://w3id.org/elixir-code/structure#functionName>,
        pattern: ~r/^[a-z_][a-z0-9_]*[!?]?$/,
        message: "Function name must be valid Elixir identifier",
        ...
      }

      iex> # Value enumeration constraint
      iex> %PropertyShape{
      ...>   id: RDF.bnode("b3"),
      ...>   path: ~I<https://w3id.org/elixir-code/otp#supervisorStrategy>,
      ...>   in: [
      ...>     ~I<https://w3id.org/elixir-code/otp#OneForOne>,
      ...>     ~I<https://w3id.org/elixir-code/otp#OneForAll>
      ...>   ],
      ...>   message: "Supervisor strategy must be one of the allowed values"
      ...> }
      %ElixirOntologies.SHACL.Model.PropertyShape{
        id: ~B<b3>,
        path: ~I<https://w3id.org/elixir-code/otp#supervisorStrategy>,
        in: [
          ~I<https://w3id.org/elixir-code/otp#OneForOne>,
          ~I<https://w3id.org/elixir-code/otp#OneForAll>
        ],
        message: "Supervisor strategy must be one of the allowed values",
        ...
      }

  ## Real-World Usage

  From elixir-shapes.ttl, property shapes constrain various Elixir code elements:

      # Module name must be present and match pattern
      %PropertyShape{
        id: RDF.bnode(),
        path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
        min_count: 1,
        max_count: 1,
        pattern: ~r/^[A-Z][a-zA-Z0-9_]*$/,
        message: "Module name required and must be valid Elixir module identifier"
      }

      # Function arity must be non-negative integer
      %PropertyShape{
        id: RDF.bnode(),
        path: ~I<https://w3id.org/elixir-code/structure#arity>,
        min_count: 1,
        max_count: 1,
        datatype: ~I<http://www.w3.org/2001/XMLSchema#nonNegativeInteger>,
        message: "Function must have exactly one non-negative arity value"
      }
  """

  @enforce_keys [:id, :path]
  defstruct [
    # RDF.IRI.t() | RDF.BlankNode.t()
    :id,
    # RDF.IRI.t()
    :path,
    # String.t() | nil
    :message,

    # Cardinality
    # non_neg_integer() | nil
    min_count: nil,
    # non_neg_integer() | nil
    max_count: nil,

    # Datatype / class
    # RDF.IRI.t() | nil
    datatype: nil,
    # RDF.IRI.t() | nil
    class: nil,

    # String constraints
    # Regex.t() | nil
    pattern: nil,
    # non_neg_integer() | nil
    min_length: nil,

    # Numeric constraints
    # integer() | float() | nil
    min_inclusive: nil,
    # integer() | float() | nil
    max_inclusive: nil,

    # Value constraints
    # [RDF.Term.t()]
    in: [],
    # RDF.Term.t() | nil
    has_value: nil,

    # Qualified
    # RDF.IRI.t() | nil
    qualified_class: nil,
    # non_neg_integer() | nil
    qualified_min_count: nil
  ]

  @type t :: %__MODULE__{
          id: RDF.IRI.t() | RDF.BlankNode.t(),
          path: RDF.IRI.t(),
          message: String.t() | nil,
          min_count: non_neg_integer() | nil,
          max_count: non_neg_integer() | nil,
          datatype: RDF.IRI.t() | nil,
          class: RDF.IRI.t() | nil,
          pattern: Regex.t() | nil,
          min_length: non_neg_integer() | nil,
          min_inclusive: integer() | float() | nil,
          max_inclusive: integer() | float() | nil,
          in: [RDF.Term.t()],
          has_value: RDF.Term.t() | nil,
          qualified_class: RDF.IRI.t() | nil,
          qualified_min_count: non_neg_integer() | nil
        }
end
