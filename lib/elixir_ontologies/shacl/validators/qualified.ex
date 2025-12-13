defmodule ElixirOntologies.SHACL.Validators.Qualified do
  @moduledoc """
  SHACL qualified value shape constraint validator.

  Validates sh:qualifiedValueShape with sh:qualifiedMinCount constraints.

  ## Constraints

  - **sh:qualifiedValueShape** - Specifies a class that qualified values must belong to
  - **sh:qualifiedMinCount** - Minimum number of values that must match the qualified shape

  ## Algorithm

  1. Extract all values for the property path
  2. For each value, check if it's an instance of the qualified class
  3. Count how many values match the qualified shape
  4. Check if qualified count >= qualifiedMinCount
  5. Build ValidationResult if count is too low
  6. Return list of violations (0 or 1)

  ## Examples

      # Qualified constraint: GenServer must have at least 2 callback functions
      property_shape = %PropertyShape{
        id: RDF.bnode("b1"),
        path: ~I<https://w3id.org/elixir-code/structure#hasFunction>,
        qualified_class: ~I<https://w3id.org/elixir-code/structure#Function>,
        qualified_min_count: 2,
        message: "GenServer must implement at least 2 callback functions"
      }

      # Conformant data (2 callback functions)
      graph = RDF.Graph.new([
        {~I<http://example.org/GenServer1>, ~I<https://w3id.org/elixir-code/structure#hasFunction>,
         ~I<http://example.org/init/1>},
        {~I<http://example.org/GenServer1>, ~I<https://w3id.org/elixir-code/structure#hasFunction>,
         ~I<http://example.org/handle_call/3>},
        {~I<http://example.org/init/1>, RDF.type(), ~I<https://w3id.org/elixir-code/structure#Function>},
        {~I<http://example.org/handle_call/3>, RDF.type(), ~I<https://w3id.org/elixir-code/structure#Function>}
      ])
      validate(graph, ~I<http://example.org/GenServer1>, property_shape)
      # => [] (no violations)

  ## Real-World Usage

  From elixir-shapes.ttl, qualified constraints ensure:

  - GenServers have at least 2 callback functions (init/1 and handle_call/3 minimum)
  - Supervisors have qualified child specs
  - Protocols have qualified implementations
  """

  import RDF.Sigils

  alias ElixirOntologies.SHACL.Model.{PropertyShape, ValidationResult}
  alias ElixirOntologies.SHACL.Validators.Helpers

  @doc """
  Validate qualified value shape constraint (sh:qualifiedValueShape + sh:qualifiedMinCount).

  Returns a list of ValidationResult structs for any violations found.
  Returns empty list if qualified constraints are satisfied.

  ## Parameters

  - `data_graph` - RDF.Graph.t() containing the data to validate
  - `focus_node` - RDF.Term.t() the node being validated
  - `property_shape` - PropertyShape.t() containing qualified_class and qualified_min_count

  ## Returns

  List of ValidationResult.t() structs (empty = no violations)

  ## Examples

      iex> alias ElixirOntologies.SHACL.Model.PropertyShape
      iex> alias ElixirOntologies.SHACL.Validators.Qualified
      iex>
      iex> # Shape requiring at least 2 Functions
      iex> shape = %PropertyShape{
      ...>   id: RDF.bnode("b1"),
      ...>   path: ~I<http://example.org/hasFunction>,
      ...>   qualified_class: ~I<http://example.org/Function>,
      ...>   qualified_min_count: 2
      ...> }
      iex>
      iex> # Graph with 2 Functions
      iex> graph = RDF.Graph.new([
      ...>   {~I<http://example.org/module>, ~I<http://example.org/hasFunction>, ~I<http://example.org/f1>},
      ...>   {~I<http://example.org/module>, ~I<http://example.org/hasFunction>, ~I<http://example.org/f2>},
      ...>   {~I<http://example.org/f1>, RDF.type(), ~I<http://example.org/Function>},
      ...>   {~I<http://example.org/f2>, RDF.type(), ~I<http://example.org/Function>}
      ...> ])
      iex> Qualified.validate(graph, ~I<http://example.org/module>, shape)
      []
  """
  @spec validate(RDF.Graph.t(), RDF.Term.t(), PropertyShape.t()) :: [ValidationResult.t()]
  def validate(data_graph, focus_node, property_shape) do
    # Extract property values
    values = Helpers.get_property_values(data_graph, focus_node, property_shape.path)

    # Check qualified constraints
    check_qualified(data_graph, focus_node, property_shape, values)
  end

  # Check sh:qualifiedValueShape + sh:qualifiedMinCount constraint
  @spec check_qualified(
          RDF.Graph.t(),
          RDF.Term.t(),
          PropertyShape.t(),
          [RDF.Term.t()]
        ) ::
          [ValidationResult.t()]
  defp check_qualified(data_graph, focus_node, property_shape, values) do
    case {property_shape.qualified_class, property_shape.qualified_min_count} do
      {nil, _} ->
        # No qualified constraint
        []

      {_, nil} ->
        # No qualified min count
        []

      {qualified_class, qualified_min_count} ->
        # Count how many values are instances of the qualified class
        qualified_count =
          Enum.count(values, fn value ->
            Helpers.is_instance_of?(data_graph, value, qualified_class)
          end)

        if qualified_count >= qualified_min_count do
          # Qualified constraint satisfied
          []
        else
          # Violation: not enough qualified values
          violation =
            Helpers.build_violation(
              focus_node,
              property_shape,
              "Property has too few values of required type (expected at least #{qualified_min_count} instances of #{inspect(qualified_class)}, found #{qualified_count})",
              %{
                constraint_component: ~I<http://www.w3.org/ns/shacl#QualifiedMinCountConstraintComponent>,
                qualified_class: qualified_class,
                qualified_min_count: qualified_min_count,
                actual_qualified_count: qualified_count,
                total_values: length(values)
              }
            )

          [violation]
        end
    end
  end
end
