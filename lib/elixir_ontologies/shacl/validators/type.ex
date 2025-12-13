defmodule ElixirOntologies.SHACL.Validators.Type do
  @moduledoc """
  SHACL type constraint validator.

  Validates sh:datatype and sh:class constraints on property values.

  ## Constraints

  - **sh:datatype** - Requires values to be literals with a specific XSD datatype
  - **sh:class** - Requires values to be instances of a specific RDF class

  ## Algorithm

  ### sh:datatype

  1. Extract all values for the property path
  2. For each value, check if it's a literal with the required datatype
  3. Build ValidationResult for each value that doesn't match
  4. Return list of violations

  ### sh:class

  1. Extract all values for the property path
  2. For each value, check if it has rdf:type equal to the required class
  3. Build ValidationResult for each value that doesn't match
  4. Return list of violations

  ## Examples

      # Datatype constraint: arity must be xsd:nonNegativeInteger
      property_shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<https://w3id.org/elixir-code/structure#arity>,
        datatype: ~I<http://www.w3.org/2001/XMLSchema#nonNegativeInteger>,
        message: "Arity must be a non-negative integer"
      }

      # Conformant data (correct datatype)
      graph = RDF.Graph.new([
        {~I<http://example.org/Function1>, ~I<https://w3id.org/elixir-code/structure#arity>,
         RDF.XSD.non_negative_integer(2)}
      ])
      validate(graph, ~I<http://example.org/Function1>, property_shape)
      # => [] (no violations)

      # Non-conformant data (wrong datatype)
      graph = RDF.Graph.new([
        {~I<http://example.org/Function1>, ~I<https://w3id.org/elixir-code/structure#arity>, "two"}
      ])
      validate(graph, ~I<http://example.org/Function1>, property_shape)
      # => [%ValidationResult{message: "Arity must be a non-negative integer", ...}]

      # Class constraint: module must be instance of elixir:Module
      property_shape = %PropertyShape{
        id: RDF.bnode("b2"),
        path: ~I<https://w3id.org/elixir-code/structure#hasModule>,
        class: ~I<https://w3id.org/elixir-code/structure#Module>,
        message: "Value must be a Module"
      }

  ## Real-World Usage

  From elixir-shapes.ttl, type constraints ensure:

  - Function arity is xsd:nonNegativeInteger
  - Module name is xsd:string
  - Function clauses are instances of FunctionClause class
  - GenServer callbacks are instances of Function class
  """

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.{PropertyShape, ValidationResult}
  alias ElixirOntologies.SHACL.Validators.Helpers

  @doc """
  Validate type constraints (sh:datatype, sh:class).

  Returns a list of ValidationResult structs for any violations found.
  Returns empty list if all property values conform to type constraints.

  ## Parameters

  - `data_graph` - RDF.Graph.t() containing the data to validate
  - `focus_node` - RDF.Term.t() the node being validated
  - `property_shape` - PropertyShape.t() containing datatype and/or class

  ## Returns

  List of ValidationResult.t() structs (empty = no violations)

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.PropertyShape
      iex> alias ElixirOntologies.SHACL.Validators.Type
      iex>
      iex> # Shape requiring xsd:string datatype
      iex> shape = %PropertyShape{
      ...>   id: RDF.bnode("b1"),
      ...>   path: ~I<http://example.org/name>,
      ...>   datatype: ~I<http://www.w3.org/2001/XMLSchema#string>
      ...> }
      iex>
      iex> # Graph with string value (conforms)
      iex> graph = RDF.Graph.new([{~I<http://example.org/n1>, ~I<http://example.org/name>, RDF.Literal.new("Alice", datatype: ~I<http://www.w3.org/2001/XMLSchema#string>)}])
      iex> Type.validate(graph, ~I<http://example.org/n1>, shape)
      []
  """
  @spec validate(RDF.Graph.t(), RDF.Term.t(), PropertyShape.t()) :: [ValidationResult.t()]
  def validate(data_graph, focus_node, property_shape) do
    # Extract property values
    values = Helpers.get_property_values(data_graph, focus_node, property_shape.path)

    # Accumulate violations
    []
    |> check_datatype(data_graph, focus_node, property_shape, values)
    |> check_class(data_graph, focus_node, property_shape, values)
  end

  # Check sh:datatype constraint for all values
  @spec check_datatype(
          [ValidationResult.t()],
          RDF.Graph.t(),
          RDF.Term.t(),
          PropertyShape.t(),
          [RDF.Term.t()]
        ) ::
          [ValidationResult.t()]
  defp check_datatype(results, _data_graph, focus_node, property_shape, values) do
    case property_shape.datatype do
      nil ->
        # No datatype constraint
        results

      datatype_iri ->
        # Check each value
        violations =
          Enum.reduce(values, [], fn value, acc ->
            if Helpers.is_datatype?(value, datatype_iri) do
              # Value has correct datatype
              acc
            else
              # Violation: wrong datatype or not a literal
              violation =
                Helpers.build_violation(
                  focus_node,
                  property_shape,
                  "Value does not have required datatype #{inspect(datatype_iri)}",
                  %{
                    constraint_component: ~I<http://www.w3.org/ns/shacl#DatatypeConstraintComponent>,
                    expected_datatype: datatype_iri,
                    actual_value: value
                  }
                )

              [violation | acc]
            end
          end)

        results ++ Enum.reverse(violations)
    end
  end

  # Check sh:class constraint for all values
  @spec check_class(
          [ValidationResult.t()],
          RDF.Graph.t(),
          RDF.Term.t(),
          PropertyShape.t(),
          [RDF.Term.t()]
        ) ::
          [ValidationResult.t()]
  defp check_class(results, data_graph, focus_node, property_shape, values) do
    case property_shape.class do
      nil ->
        # No class constraint
        results

      class_iri ->
        # Check each value
        violations =
          Enum.reduce(values, [], fn value, acc ->
            if Helpers.is_instance_of?(data_graph, value, class_iri) do
              # Value is instance of required class
              acc
            else
              # Violation: not an instance of the class
              violation =
                Helpers.build_violation(
                  focus_node,
                  property_shape,
                  "Value is not an instance of class #{inspect(class_iri)}",
                  %{
                    constraint_component: ~I<http://www.w3.org/ns/shacl#ClassConstraintComponent>,
                    expected_class: class_iri,
                    actual_value: value
                  }
                )

              [violation | acc]
            end
          end)

        results ++ Enum.reverse(violations)
    end
  end
end
