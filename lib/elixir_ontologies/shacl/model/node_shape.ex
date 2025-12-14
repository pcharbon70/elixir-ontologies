defmodule ElixirOntologies.SHACL.Model.NodeShape do
  @moduledoc """
  Represents a SHACL node shape (sh:NodeShape).

  A node shape defines constraints that apply to focus nodes in the data graph,
  typically selected via sh:targetClass. Each node shape contains:
  - Property shapes that constrain specific properties of the focus node
  - SPARQL constraints for complex validation logic

  ## Fields

  - `id` - The IRI or blank node identifying this shape (required)
  - `target_classes` - List of RDF classes (IRIs) to which this shape applies via sh:targetClass
  - `implicit_class_target` - The IRI of the class this shape represents (for implicit targeting per SHACL 2.1.3.1)
  - `property_shapes` - List of PropertyShape structs constraining properties
  - `sparql_constraints` - List of SPARQLConstraint structs for advanced validation

  ## Node-Level Constraints (SHACL Section 2.1)

  Constraints applied directly to the focus node itself (not to its properties):

  - `node_datatype` - Required datatype for the node value (sh:datatype on NodeShape)
  - `node_class` - Required RDF class for the node (sh:class on NodeShape)
  - `node_node_kind` - Required node kind (sh:nodeKind on NodeShape)
  - `node_min_inclusive` - Minimum value inclusive (sh:minInclusive on NodeShape)
  - `node_max_inclusive` - Maximum value inclusive (sh:maxInclusive on NodeShape)
  - `node_min_exclusive` - Minimum value exclusive (sh:minExclusive on NodeShape)
  - `node_max_exclusive` - Maximum value exclusive (sh:maxExclusive on NodeShape)
  - `node_min_length` - Minimum string length (sh:minLength on NodeShape)
  - `node_max_length` - Maximum string length (sh:maxLength on NodeShape)
  - `node_pattern` - Regex pattern (sh:pattern on NodeShape)
  - `node_in` - List of allowed values (sh:in on NodeShape)
  - `node_has_value` - Required specific value (sh:hasValue on NodeShape)
  - `node_language_in` - Allowed language tags (sh:languageIn on NodeShape)

  ## Logical Operators (SHACL Sections 4.1-4.4)

  Logical constraint operators combine multiple shapes:

  - `node_and` - All shapes must conform (sh:and on NodeShape)
  - `node_or` - At least one shape must conform (sh:or on NodeShape)
  - `node_xone` - Exactly one shape must conform (sh:xone on NodeShape)
  - `node_not` - Shape must NOT conform (sh:not on NodeShape)

  ## Implicit Class Targeting (SHACL 2.1.3.1)

  Per the SHACL specification, when a node shape is also defined as an rdfs:Class,
  it implicitly targets all instances of that class. This is tracked via the
  `implicit_class_target` field.

  Example:

      ex:PersonShape
        a rdfs:Class ;       # This shape is also a class
        a sh:NodeShape ;
        sh:property [...] .

      ex:John
        a ex:PersonShape .   # Implicitly targeted by ex:PersonShape

  In this case, `implicit_class_target` would be set to `~I<ex:PersonShape>`.

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.NodeShape
      iex> %NodeShape{
      ...>   id: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
      ...>   target_classes: [~I<https://w3id.org/elixir-code/structure#Module>],
      ...>   property_shapes: [],
      ...>   sparql_constraints: []
      ...> }
      %ElixirOntologies.SHACL.Model.NodeShape{
        id: ~I<https://w3id.org/elixir-code/shapes#ModuleShape>,
        target_classes: [~I<https://w3id.org/elixir-code/structure#Module>],
        property_shapes: [],
        sparql_constraints: []
      }

  ## Real-World Usage

  From elixir-shapes.ttl, a typical node shape targets Elixir structural elements:

      %NodeShape{
        id: ~I<https://w3id.org/elixir-code/shapes#FunctionShape>,
        target_classes: [~I<https://w3id.org/elixir-code/structure#Function>],
        property_shapes: [
          # Property shapes constraining function name, arity, parameters, etc.
        ],
        sparql_constraints: [
          # SPARQL constraints for arity matching parameter count
        ]
      }
  """

  alias ElixirOntologies.SHACL.Model.{PropertyShape, SPARQLConstraint}

  @enforce_keys [:id]
  defstruct [
    # RDF.IRI.t() | RDF.BlankNode.t()
    :id,
    # [RDF.IRI.t()]
    target_classes: [],
    # [RDF.Term.t()] - Explicit nodes to target via sh:targetNode
    target_nodes: [],
    # RDF.IRI.t() | nil - Set when shape is also rdfs:Class (implicit targeting)
    implicit_class_target: nil,
    # [PropertyShape.t()]
    property_shapes: [],
    # [SPARQLConstraint.t()]
    sparql_constraints: [],
    # String.t() | nil - Custom violation message for this shape
    message: nil,
    # Node-level constraints (applied to focus node itself)
    node_datatype: nil,
    node_class: nil,
    node_node_kind: nil,
    node_min_inclusive: nil,
    node_max_inclusive: nil,
    node_min_exclusive: nil,
    node_max_exclusive: nil,
    node_min_length: nil,
    node_max_length: nil,
    node_pattern: nil,
    node_in: nil,
    node_has_value: nil,
    node_language_in: nil,
    # Logical operators (sh:and, sh:or, sh:xone, sh:not)
    node_and: nil,
    node_or: nil,
    node_xone: nil,
    node_not: nil
  ]

  @type t :: %__MODULE__{
          id: RDF.IRI.t() | RDF.BlankNode.t(),
          target_classes: [RDF.IRI.t()],
          target_nodes: [RDF.Term.t()],
          implicit_class_target: RDF.IRI.t() | nil,
          property_shapes: [PropertyShape.t()],
          sparql_constraints: [SPARQLConstraint.t()],
          message: String.t() | nil,
          # Node-level constraints
          node_datatype: RDF.IRI.t() | nil,
          node_class: RDF.IRI.t() | nil,
          node_node_kind: atom() | nil,
          node_min_inclusive: RDF.Literal.t() | nil,
          node_max_inclusive: RDF.Literal.t() | nil,
          node_min_exclusive: RDF.Literal.t() | nil,
          node_max_exclusive: RDF.Literal.t() | nil,
          node_min_length: non_neg_integer() | nil,
          node_max_length: non_neg_integer() | nil,
          node_pattern: Regex.t() | nil,
          node_in: [RDF.Term.t()] | nil,
          node_has_value: RDF.Term.t() | nil,
          node_language_in: [String.t()] | nil,
          # Logical operators
          node_and: [RDF.IRI.t() | RDF.BlankNode.t()] | nil,
          node_or: [RDF.IRI.t() | RDF.BlankNode.t()] | nil,
          node_xone: [RDF.IRI.t() | RDF.BlankNode.t()] | nil,
          node_not: RDF.IRI.t() | RDF.BlankNode.t() | nil
        }
end
