defmodule ElixirOntologies.SHACL.Validators.Value do
  @moduledoc """
  SHACL value constraint validator.

  Validates sh:in, sh:hasValue, and sh:maxInclusive constraints on property values.

  ## Constraints

  - **sh:in** - Requires values to be one of a specified list (enumeration)
  - **sh:hasValue** - Requires a specific value to be present
  - **sh:maxInclusive** - Requires numeric values to be <= maximum (inclusive)

  ## Algorithm

  ### sh:in

  1. Extract all values for the property path
  2. For each value, check if it's in the allowed list
  3. Build ValidationResult for values not in the list
  4. Return list of violations

  ### sh:hasValue

  1. Extract all values for the property path
  2. Check if the required value is present in the list
  3. Build ValidationResult if required value is missing
  4. Return list of violations (0 or 1)

  ### sh:maxInclusive

  1. Extract all values for the property path
  2. For each value:
     - Extract numeric value (only applies to numeric literals)
     - Check if value <= maxInclusive
     - Build ValidationResult if too large
  3. Return list of violations

  ## Examples

      # Enumeration constraint: supervisor strategy must be one of allowed values
      property_shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<https://w3id.org/elixir-code/otp#supervisorStrategy>,
        in: [
          ~I<https://w3id.org/elixir-code/otp#OneForOne>,
          ~I<https://w3id.org/elixir-code/otp#OneForAll>,
          ~I<https://w3id.org/elixir-code/otp#RestForOne>
        ],
        message: "Supervisor strategy must be one of the allowed values"
      }

      # Conformant data (value in list)
      graph = RDF.Graph.new([
        {~I<http://example.org/Supervisor1>, ~I<https://w3id.org/elixir-code/otp#supervisorStrategy>,
         ~I<https://w3id.org/elixir-code/otp#OneForOne>}
      ])
      validate(graph, ~I<http://example.org/Supervisor1>, property_shape)
      # => [] (no violations)

  ## Real-World Usage

  From elixir-shapes.ttl, value constraints ensure:

  - Supervisor strategies are one of: OneForOne, OneForAll, RestForOne
  - Supervisor restart strategies are one of: Permanent, Transient, Temporary
  - Function arity is <= 255 (Erlang VM limit)
  - Boolean flags have specific true/false values
  """

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.{PropertyShape, ValidationResult}
  alias ElixirOntologies.SHACL.Validators.Helpers

  @doc """
  Validate value constraints (sh:in, sh:hasValue, sh:maxInclusive).

  Returns a list of ValidationResult structs for any violations found.
  Returns empty list if all property values conform to value constraints.

  ## Parameters

  - `data_graph` - RDF.Graph.t() containing the data to validate
  - `focus_node` - RDF.Term.t() the node being validated
  - `property_shape` - PropertyShape.t() containing in, has_value, and/or max_inclusive

  ## Returns

  List of ValidationResult.t() structs (empty = no violations)

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.PropertyShape
      iex> alias ElixirOntologies.SHACL.Validators.Value
      iex>
      iex> # Shape requiring value from enumeration
      iex> shape = %PropertyShape{
      ...>   id: RDF.bnode("b1"),
      ...>   path: ~I<http://example.org/color>,
      ...>   in: [~I<http://example.org/Red>, ~I<http://example.org/Green>, ~I<http://example.org/Blue>]
      ...> }
      iex>
      iex> # Graph with allowed value
      iex> graph = RDF.Graph.new([{~I<http://example.org/item>, ~I<http://example.org/color>, ~I<http://example.org/Red>}])
      iex> Value.validate(graph, ~I<http://example.org/item>, shape)
      []
  """
  @spec validate(RDF.Graph.t(), RDF.Term.t(), PropertyShape.t()) :: [ValidationResult.t()]
  def validate(data_graph, focus_node, property_shape) do
    # Extract property values
    values = Helpers.get_property_values(data_graph, focus_node, property_shape.path)

    # Accumulate violations
    []
    |> check_in(focus_node, property_shape, values)
    |> check_has_value(focus_node, property_shape, values)
    |> check_max_inclusive(focus_node, property_shape, values)
  end

  # Check sh:in constraint for all values
  @spec check_in(
          [ValidationResult.t()],
          RDF.Term.t(),
          PropertyShape.t(),
          [RDF.Term.t()]
        ) ::
          [ValidationResult.t()]
  defp check_in(results, focus_node, property_shape, values) do
    case property_shape.in do
      [] ->
        # No in constraint (empty list means no constraint)
        results

      allowed_values ->
        # Check each value
        violations =
          Enum.reduce(values, [], fn value, acc ->
            if value in allowed_values do
              # Value is in allowed list
              acc
            else
              # Violation: value not in allowed list
              violation =
                Helpers.build_violation(
                  focus_node,
                  property_shape,
                  "Value is not one of the allowed values",
                  %{
                    constraint_component: ~I<http://www.w3.org/ns/shacl#InConstraintComponent>,
                    allowed_values: allowed_values,
                    actual_value: value
                  }
                )

              [violation | acc]
            end
          end)

        results ++ Enum.reverse(violations)
    end
  end

  # Check sh:hasValue constraint
  @spec check_has_value(
          [ValidationResult.t()],
          RDF.Term.t(),
          PropertyShape.t(),
          [RDF.Term.t()]
        ) ::
          [ValidationResult.t()]
  defp check_has_value(results, focus_node, property_shape, values) do
    case property_shape.has_value do
      nil ->
        # No hasValue constraint
        results

      required_value ->
        # Check if required value is present
        if required_value in values do
          # Required value is present
          results
        else
          # Violation: required value is missing
          violation =
            Helpers.build_violation(
              focus_node,
              property_shape,
              "Required value is missing",
              %{
                constraint_component: ~I<http://www.w3.org/ns/shacl#HasValueConstraintComponent>,
                required_value: required_value
              }
            )

          [violation | results]
        end
    end
  end

  # Check sh:maxInclusive constraint for all values
  @spec check_max_inclusive(
          [ValidationResult.t()],
          RDF.Term.t(),
          PropertyShape.t(),
          [RDF.Term.t()]
        ) ::
          [ValidationResult.t()]
  defp check_max_inclusive(results, focus_node, property_shape, values) do
    case property_shape.max_inclusive do
      nil ->
        # No maxInclusive constraint
        results

      max_value ->
        # Check each value
        violations =
          Enum.reduce(values, [], fn value, acc ->
            # Extract numeric value
            case Helpers.extract_number(value) do
              nil ->
                # Not a numeric literal - skip (datatype validator handles this)
                acc

              num ->
                # Check if value <= maxInclusive
                if num <= max_value do
                  # Value within range
                  acc
                else
                  # Violation: value too large
                  violation =
                    Helpers.build_violation(
                      focus_node,
                      property_shape,
                      "Value exceeds maximum (expected <= #{max_value}, found #{num})",
                      %{
                        constraint_component: ~I<http://www.w3.org/ns/shacl#MaxInclusiveConstraintComponent>,
                        max_inclusive: max_value,
                        actual_value: num
                      }
                    )

                  [violation | acc]
                end
            end
          end)

        results ++ Enum.reverse(violations)
    end
  end
end
