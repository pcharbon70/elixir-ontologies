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
    # RDF.IRI.t() | nil - Set when shape is also rdfs:Class (implicit targeting)
    implicit_class_target: nil,
    # [PropertyShape.t()]
    property_shapes: [],
    # [SPARQLConstraint.t()]
    sparql_constraints: []
  ]

  @type t :: %__MODULE__{
          id: RDF.IRI.t() | RDF.BlankNode.t(),
          target_classes: [RDF.IRI.t()],
          implicit_class_target: RDF.IRI.t() | nil,
          property_shapes: [PropertyShape.t()],
          sparql_constraints: [SPARQLConstraint.t()]
        }
end
