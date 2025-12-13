defmodule ElixirOntologies.SHACL.Validators.String do
  @moduledoc """
  SHACL string constraint validator.

  Validates sh:pattern and sh:minLength constraints on string literal values.

  ## Constraints

  - **sh:pattern** - Requires string values to match a regular expression pattern
  - **sh:minLength** - Requires string values to have at least N characters

  ## Algorithm

  ### sh:pattern

  1. Extract all values for the property path
  2. For each value:
     - Extract string content (only applies to literals)
     - Test against the regex pattern
     - Build ValidationResult if pattern doesn't match
  3. Return list of violations

  ### sh:minLength

  1. Extract all values for the property path
  2. For each value:
     - Extract string content (only applies to literals)
     - Check if string length >= minLength
     - Build ValidationResult if too short
  3. Return list of violations

  ## Examples

      # Pattern constraint: module name must match Elixir identifier pattern
      property_shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<https://w3id.org/elixir-code/structure#moduleName>,
        pattern: ~r/^[A-Z][a-zA-Z0-9_]*$/,
        message: "Module name must be valid Elixir identifier"
      }

      # Conformant data (matches pattern)
      graph = RDF.Graph.new([
        {~I<http://example.org/Module1>, ~I<https://w3id.org/elixir-code/structure#moduleName>,
         "MyModule"}
      ])
      validate(graph, ~I<http://example.org/Module1>, property_shape)
      # => [] (no violations)

      # Non-conformant data (doesn't match pattern)
      graph = RDF.Graph.new([
        {~I<http://example.org/Module1>, ~I<https://w3id.org/elixir-code/structure#moduleName>,
         "invalid_name"}
      ])
      validate(graph, ~I<http://example.org/Module1>, property_shape)
      # => [%ValidationResult{message: "Module name must be valid Elixir identifier", ...}]

  ## Real-World Usage

  From elixir-shapes.ttl, string constraints ensure:

  - Module names match ^[A-Z][a-zA-Z0-9_]*$
  - Function names match ^[a-z_][a-z0-9_]*[!?]?$
  - Variable names have minimum length of 1 character
  - Atom literals match valid Elixir atom syntax
  """

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.{PropertyShape, ValidationResult}
  alias ElixirOntologies.SHACL.Validators.Helpers

  @doc """
  Validate string constraints (sh:pattern, sh:minLength).

  Returns a list of ValidationResult structs for any violations found.
  Returns empty list if all property values conform to string constraints.

  ## Parameters

  - `data_graph` - RDF.Graph.t() containing the data to validate
  - `focus_node` - RDF.Term.t() the node being validated
  - `property_shape` - PropertyShape.t() containing pattern and/or min_length

  ## Returns

  List of ValidationResult.t() structs (empty = no violations)

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.PropertyShape
      iex> alias ElixirOntologies.SHACL.Validators.String
      iex>
      iex> # Shape requiring pattern match
      iex> shape = %PropertyShape{
      ...>   id: RDF.bnode("b1"),
      ...>   path: ~I<http://example.org/name>,
      ...>   pattern: ~r/^[A-Z]/
      ...> }
      iex>
      iex> # Graph with matching value
      iex> graph = RDF.Graph.new([{~I<http://example.org/n1>, ~I<http://example.org/name>, "Alice"}])
      iex> String.validate(graph, ~I<http://example.org/n1>, shape)
      []
  """
  @spec validate(RDF.Graph.t(), RDF.Term.t(), PropertyShape.t()) :: [ValidationResult.t()]
  def validate(data_graph, focus_node, property_shape) do
    # Extract property values
    values = Helpers.get_property_values(data_graph, focus_node, property_shape.path)

    # Accumulate violations
    []
    |> check_pattern(focus_node, property_shape, values)
    |> check_min_length(focus_node, property_shape, values)
  end

  # Check sh:pattern constraint for all values
  @spec check_pattern(
          [ValidationResult.t()],
          RDF.Term.t(),
          PropertyShape.t(),
          [RDF.Term.t()]
        ) ::
          [ValidationResult.t()]
  defp check_pattern(results, focus_node, property_shape, values) do
    case property_shape.pattern do
      nil ->
        # No pattern constraint
        results

      pattern ->
        # Check each value
        violations =
          Enum.reduce(values, [], fn value, acc ->
            # Extract string content
            case Helpers.extract_string(value) do
              nil ->
                # Not a literal with string content - skip (datatype validator handles this)
                acc

              str ->
                # Test against pattern
                if Regex.match?(pattern, str) do
                  # Pattern matches
                  acc
                else
                  # Violation: pattern doesn't match
                  violation =
                    Helpers.build_violation(
                      focus_node,
                      property_shape,
                      "Value does not match required pattern #{inspect(pattern.source)}",
                      %{
                        constraint_component: ~I<http://www.w3.org/ns/shacl#PatternConstraintComponent>,
                        pattern: pattern.source,
                        actual_value: str
                      }
                    )

                  [violation | acc]
                end
            end
          end)

        results ++ Enum.reverse(violations)
    end
  end

  # Check sh:minLength constraint for all values
  @spec check_min_length(
          [ValidationResult.t()],
          RDF.Term.t(),
          PropertyShape.t(),
          [RDF.Term.t()]
        ) ::
          [ValidationResult.t()]
  defp check_min_length(results, focus_node, property_shape, values) do
    case property_shape.min_length do
      nil ->
        # No minLength constraint
        results

      min_length ->
        # Check each value
        violations =
          Enum.reduce(values, [], fn value, acc ->
            # Extract string content
            case Helpers.extract_string(value) do
              nil ->
                # Not a literal with string content - skip (datatype validator handles this)
                acc

              str ->
                # Check length
                actual_length = String.length(str)

                if actual_length >= min_length do
                  # Length is sufficient
                  acc
                else
                  # Violation: string too short
                  violation =
                    Helpers.build_violation(
                      focus_node,
                      property_shape,
                      "Value is too short (expected at least #{min_length} characters, found #{actual_length})",
                      %{
                        constraint_component: ~I<http://www.w3.org/ns/shacl#MinLengthConstraintComponent>,
                        min_length: min_length,
                        actual_length: actual_length,
                        actual_value: str
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
