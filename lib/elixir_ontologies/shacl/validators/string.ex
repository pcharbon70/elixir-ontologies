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

  alias ElixirOntologies.SHACL.Model.{NodeShape, PropertyShape, ValidationResult}
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
            check_pattern_value(value, pattern, focus_node, property_shape, acc)
          end)

        results ++ Enum.reverse(violations)
    end
  end

  defp check_pattern_value(value, pattern, focus_node, property_shape, acc) do
    case Helpers.extract_string(value) do
      nil ->
        # Not a literal with string content - skip (datatype validator handles this)
        acc

      str when is_binary(str) ->
        if Regex.match?(pattern, str) do
          acc
        else
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
            check_min_length_value(value, min_length, focus_node, property_shape, acc)
          end)

        results ++ Enum.reverse(violations)
    end
  end

  defp check_min_length_value(value, min_length, focus_node, property_shape, acc) do
    case Helpers.extract_string(value) do
      nil ->
        # Not a literal with string content - skip (datatype validator handles this)
        acc

      str ->
        actual_length = String.length(str)

        if actual_length >= min_length do
          acc
        else
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
  end

  @doc """
  Validate node-level string constraints (sh:pattern, sh:minLength, sh:maxLength).

  Validates constraints applied directly to the focus node itself, not to its properties.

  Returns a list of ValidationResult structs for any violations found.
  Returns empty list if the focus node conforms to all node-level string constraints.

  ## Parameters

  - `_data_graph` - RDF.Graph.t() (unused for string validation)
  - `focus_node` - RDF.Term.t() the node being validated (checked directly)
  - `node_shape` - NodeShape.t() containing node_pattern, node_min_length, and/or node_max_length

  ## Returns

  List of ValidationResult.t() structs (empty = no violations)
  """
  @spec validate_node(RDF.Graph.t(), RDF.Term.t(), NodeShape.t()) :: [ValidationResult.t()]
  def validate_node(_data_graph, focus_node, node_shape) do
    # Accumulate violations for node-level constraints
    []
    |> check_node_pattern(focus_node, node_shape)
    |> check_node_min_length(focus_node, node_shape)
    |> check_node_max_length(focus_node, node_shape)
    |> check_node_language_in(focus_node, node_shape)
  end

  # Check sh:pattern constraint on the focus node itself
  @spec check_node_pattern([ValidationResult.t()], RDF.Term.t(), NodeShape.t()) ::
          [ValidationResult.t()]
  defp check_node_pattern(results, focus_node, node_shape) do
    case node_shape.node_pattern do
      nil ->
        # No pattern constraint
        results

      pattern ->
        # Extract string content from focus node
        case Helpers.extract_string(focus_node) do
          nil ->
            # Not a literal with string content - no violation (nodeKind validator handles this)
            results

          str ->
            # Test against pattern
            if Regex.match?(pattern, str) do
              # Pattern matches
              results
            else
              # Violation: pattern doesn't match
              violation =
                Helpers.build_node_violation(
                  focus_node,
                  node_shape,
                  "Focus node does not match required pattern #{inspect(pattern.source)}",
                  %{
                    constraint_component: ~I<http://www.w3.org/ns/shacl#PatternConstraintComponent>,
                    pattern: pattern.source,
                    actual_value: str
                  }
                )

              [violation | results]
            end
        end
    end
  end

  # Check sh:minLength constraint on the focus node itself
  @spec check_node_min_length([ValidationResult.t()], RDF.Term.t(), NodeShape.t()) ::
          [ValidationResult.t()]
  defp check_node_min_length(results, focus_node, node_shape) do
    case node_shape.node_min_length do
      nil ->
        # No minLength constraint
        results

      min_length ->
        # Extract string content from focus node
        case Helpers.extract_string(focus_node) do
          nil ->
            # Not a literal with string content - no violation (nodeKind validator handles this)
            results

          str ->
            # Check length
            actual_length = String.length(str)

            if actual_length >= min_length do
              # Length is sufficient
              results
            else
              # Violation: string too short
              violation =
                Helpers.build_node_violation(
                  focus_node,
                  node_shape,
                  "Focus node is too short (expected at least #{min_length} characters, found #{actual_length})",
                  %{
                    constraint_component: ~I<http://www.w3.org/ns/shacl#MinLengthConstraintComponent>,
                    min_length: min_length,
                    actual_length: actual_length,
                    actual_value: str
                  }
                )

              [violation | results]
            end
        end
    end
  end

  # Check sh:maxLength constraint on the focus node itself
  @spec check_node_max_length([ValidationResult.t()], RDF.Term.t(), NodeShape.t()) ::
          [ValidationResult.t()]
  defp check_node_max_length(results, focus_node, node_shape) do
    case node_shape.node_max_length do
      nil ->
        # No maxLength constraint
        results

      max_length ->
        # Extract string content from focus node
        case Helpers.extract_string(focus_node) do
          nil ->
            # Not a literal with string content - no violation (nodeKind validator handles this)
            results

          str ->
            # Check length
            actual_length = String.length(str)

            if actual_length <= max_length do
              # Length is acceptable
              results
            else
              # Violation: string too long
              violation =
                Helpers.build_node_violation(
                  focus_node,
                  node_shape,
                  "Focus node is too long (expected at most #{max_length} characters, found #{actual_length})",
                  %{
                    constraint_component: ~I<http://www.w3.org/ns/shacl#MaxLengthConstraintComponent>,
                    max_length: max_length,
                    actual_length: actual_length,
                    actual_value: str
                  }
                )

              [violation | results]
            end
        end
    end
  end

  # Check sh:languageIn constraint on the focus node itself
  @spec check_node_language_in([ValidationResult.t()], RDF.Term.t(), NodeShape.t()) ::
          [ValidationResult.t()]
  defp check_node_language_in(results, focus_node, node_shape) do
    case node_shape.node_language_in do
      nil ->
        results

      [] ->
        results

      allowed_languages ->
        check_language_in_constraint(results, focus_node, node_shape, allowed_languages)
    end
  end

  defp check_language_in_constraint(results, %RDF.Literal{} = focus_node, node_shape, allowed_languages) do
    case RDF.Literal.language(focus_node) do
      nil ->
        violation =
          Helpers.build_node_violation(
            focus_node,
            node_shape,
            "Focus node must have a language tag",
            %{
              constraint_component: ~I<http://www.w3.org/ns/shacl#LanguageInConstraintComponent>,
              allowed_languages: allowed_languages,
              actual_value: focus_node
            }
          )

        [violation | results]

      lang ->
        if lang in allowed_languages do
          results
        else
          violation =
            Helpers.build_node_violation(
              focus_node,
              node_shape,
              "Language tag '#{lang}' is not in the allowed list",
              %{
                constraint_component: ~I<http://www.w3.org/ns/shacl#LanguageInConstraintComponent>,
                allowed_languages: allowed_languages,
                actual_language: lang,
                actual_value: focus_node
              }
            )

          [violation | results]
        end
    end
  end

  defp check_language_in_constraint(results, focus_node, node_shape, allowed_languages) do
    # Not a literal - violation
    violation =
      Helpers.build_node_violation(
        focus_node,
        node_shape,
        "Focus node must be a literal with a language tag",
        %{
          constraint_component: ~I<http://www.w3.org/ns/shacl#LanguageInConstraintComponent>,
          allowed_languages: allowed_languages,
          actual_value: focus_node
        }
      )

    [violation | results]
  end
end
