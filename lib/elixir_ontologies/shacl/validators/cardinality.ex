defmodule ElixirOntologies.SHACL.Validators.Cardinality do
  @moduledoc """
  SHACL cardinality constraint validator.

  Validates sh:minCount and sh:maxCount constraints on property values.

  ## Constraints

  - **sh:minCount** - Minimum number of values required for a property
  - **sh:maxCount** - Maximum number of values allowed for a property

  ## Algorithm

  1. Extract all values for the property path from the focus node
  2. Count the number of values
  3. Check if count < minCount → violation
  4. Check if count > maxCount → violation
  5. Return list of violations (empty list = success)

  ## Examples

      # Property shape requiring exactly one value
      property_shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
        min_count: 1,
        max_count: 1,
        message: "Module must have exactly one name"
      }

      # Conformant data (1 value)
      graph = RDF.Graph.new([
        {~I<http://example.org/Module1>, ~I<https://w3id.org/elixir-code/structure#moduleName>, "MyModule"}
      ])
      validate(graph, ~I<http://example.org/Module1>, property_shape)
      # => [] (no violations)

      # Non-conformant data (0 values)
      graph = RDF.Graph.new([])
      validate(graph, ~I<http://example.org/Module1>, property_shape)
      # => [%ValidationResult{message: "Module must have exactly one name", ...}]

  ## Real-World Usage

  From elixir-shapes.ttl, cardinality constraints ensure:

  - Module has exactly 1 name (min=1, max=1)
  - Function has exactly 1 arity (min=1, max=1)
  - Function has at least 1 clause (min=1, max=nil)
  - Protocol has at least 1 function (min=1, max=nil)
  - Supervisor may have 0+ children (min=nil, max=nil)
  """

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.{PropertyShape, ValidationResult}
  alias ElixirOntologies.SHACL.Validators.Helpers

  @doc """
  Validate cardinality constraints (sh:minCount, sh:maxCount).

  Returns a list of ValidationResult structs for any violations found.
  Returns empty list if the property values conform to all cardinality constraints.

  ## Parameters

  - `data_graph` - RDF.Graph.t() containing the data to validate
  - `focus_node` - RDF.Term.t() the node being validated
  - `property_shape` - PropertyShape.t() containing min_count and/or max_count

  ## Returns

  List of ValidationResult.t() structs (empty = no violations)

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.PropertyShape
      iex> alias ElixirOntologies.SHACL.Validators.Cardinality
      iex>
      iex> # Shape requiring exactly 1 value
      iex> shape = %PropertyShape{
      ...>   id: RDF.bnode("b1"),
      ...>   path: ~I<http://example.org/name>,
      ...>   min_count: 1,
      ...>   max_count: 1
      ...> }
      iex>
      iex> # Graph with 1 value (conforms)
      iex> graph = RDF.Graph.new([{~I<http://example.org/n1>, ~I<http://example.org/name>, "Alice"}])
      iex> Cardinality.validate(graph, ~I<http://example.org/n1>, shape)
      []
  """
  @spec validate(RDF.Graph.t(), RDF.Term.t(), PropertyShape.t()) :: [ValidationResult.t()]
  def validate(data_graph, focus_node, property_shape) do
    # Extract property values
    values = Helpers.get_property_values(data_graph, focus_node, property_shape.path)
    count = length(values)

    # Accumulate violations
    []
    |> check_min_count(focus_node, property_shape, count)
    |> check_max_count(focus_node, property_shape, count)
  end

  # Check sh:minCount constraint
  @spec check_min_count([ValidationResult.t()], RDF.Term.t(), PropertyShape.t(), non_neg_integer()) ::
          [ValidationResult.t()]
  defp check_min_count(results, focus_node, property_shape, count) do
    case property_shape.min_count do
      nil ->
        # No minCount constraint
        results

      min_count when count < min_count ->
        # Violation: too few values
        violation =
          Helpers.build_violation(
            focus_node,
            property_shape,
            "Property has too few values (expected at least #{min_count}, found #{count})",
            %{
              constraint_component: ~I<http://www.w3.org/ns/shacl#MinCountConstraintComponent>,
              min_count: min_count,
              actual_count: count
            }
          )

        [violation | results]

      _ ->
        # minCount satisfied
        results
    end
  end

  # Check sh:maxCount constraint
  @spec check_max_count([ValidationResult.t()], RDF.Term.t(), PropertyShape.t(), non_neg_integer()) ::
          [ValidationResult.t()]
  defp check_max_count(results, focus_node, property_shape, count) do
    case property_shape.max_count do
      nil ->
        # No maxCount constraint
        results

      max_count when count > max_count ->
        # Violation: too many values
        violation =
          Helpers.build_violation(
            focus_node,
            property_shape,
            "Property has too many values (expected at most #{max_count}, found #{count})",
            %{
              constraint_component: ~I<http://www.w3.org/ns/shacl#MaxCountConstraintComponent>,
              max_count: max_count,
              actual_count: count
            }
          )

        [violation | results]

      _ ->
        # maxCount satisfied
        results
    end
  end
end
