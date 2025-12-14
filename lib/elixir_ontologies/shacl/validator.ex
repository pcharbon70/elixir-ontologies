defmodule ElixirOntologies.SHACL.Validator do
  @moduledoc """
  Main SHACL validation orchestration engine.

  This module coordinates validation across all SHACL shapes, selecting target
  nodes, dispatching to constraint validators, and aggregating results into
  a validation report.

  ## Workflow

  1. Parse shapes from shapes graph using `SHACL.Reader`
  2. For each `NodeShape`:
     - Select target nodes from data graph (via `sh:targetClass`)
     - For each target node (focus node):
       - For each `PropertyShape` in the `NodeShape`:
         - Dispatch to appropriate constraint validators
         - Collect `ValidationResult`s
  3. Aggregate all results into `ValidationReport`
  4. Return report with `conforms?` flag

  ## Usage

      # Load graphs
      {:ok, data_graph} = RDF.Turtle.read_file("my_data.ttl")
      {:ok, shapes_graph} = RDF.Turtle.read_file("priv/ontologies/elixir-shapes.ttl")

      # Validate
      {:ok, report} = Validator.run(data_graph, shapes_graph)

      if report.conforms? do
        IO.puts("Valid!")
      else
        IO.puts("Found \#{length(report.results)} violations")
      end

  ## Options

  - `:parallel` - Enable parallel validation (default: `true`)
  - `:max_concurrency` - Max concurrent tasks (default: `System.schedulers_online()`)
  - `:timeout` - Validation timeout per shape in ms (default: `5000`)

  ## Examples

      iex> alias ElixirOntologies.SHACL.Validator
      iex>
      iex> # Simple conformant data
      iex> shapes_graph = RDF.Graph.new([
      ...>   {~I<http://example.org/shapes#S1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
      ...>   {~I<http://example.org/shapes#S1>, ~I<http://www.w3.org/ns/shacl#targetClass>, ~I<http://example.org/Module>}
      ...> ])
      iex>
      iex> data_graph = RDF.Graph.new([
      ...>   {~I<http://example.org/M1>, RDF.type(), ~I<http://example.org/Module>}
      ...> ])
      iex>
      iex> {:ok, report} = Validator.run(data_graph, shapes_graph)
      iex> report.conforms?
      true
  """

  require Logger

  alias ElixirOntologies.SHACL.{Reader, Validators}
  alias ElixirOntologies.SHACL.Model.{NodeShape, PropertyShape, ValidationReport, ValidationResult}

  @type validation_option ::
          {:parallel, boolean()}
          | {:max_concurrency, pos_integer()}
          | {:timeout, timeout()}

  @doc """
  Run SHACL validation on a data graph.

  ## Parameters

  - `data_graph` - `RDF.Graph.t()` to validate
  - `shapes_graph` - `RDF.Graph.t()` containing SHACL shapes
  - `opts` - Keyword list of options

  ## Returns

  - `{:ok, ValidationReport.t()}` - Validation completed
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> data = RDF.Graph.new([{~I<http://example.org/n1>, RDF.type(), ~I<http://example.org/Class1>}])
      iex> shapes = RDF.Graph.new([
      ...>   {~I<http://example.org/S1>, RDF.type(), ~I<http://www.w3.org/ns/shacl#NodeShape>},
      ...>   {~I<http://example.org/S1>, ~I<http://www.w3.org/ns/shacl#targetClass>, ~I<http://example.org/Class1>}
      ...> ])
      iex> {:ok, report} = Validator.run(data, shapes)
      iex> is_struct(report, ElixirOntologies.SHACL.Model.ValidationReport)
      true
  """
  @spec run(RDF.Graph.t(), RDF.Graph.t(), [validation_option()]) ::
          {:ok, ValidationReport.t()} | {:error, term()}
  def run(data_graph, shapes_graph, opts \\ []) do
    with {:ok, node_shapes} <- Reader.parse_shapes(shapes_graph),
         {:ok, all_results} <- validate_all_shapes(data_graph, node_shapes, opts) do
      # Compute conformance: no violations = conforms
      conforms? = Enum.all?(all_results, fn r -> r.severity != :violation end)

      report = %ValidationReport{
        conforms?: conforms?,
        results: all_results
      }

      {:ok, report}
    end
  end

  # Validate all shapes (potentially in parallel)
  @spec validate_all_shapes(RDF.Graph.t(), [NodeShape.t()], keyword()) ::
          {:ok, [ValidationResult.t()]} | {:error, term()}
  defp validate_all_shapes(data_graph, node_shapes, opts) do
    if Keyword.get(opts, :parallel, true) do
      validate_shapes_parallel(data_graph, node_shapes, opts)
    else
      validate_shapes_sequential(data_graph, node_shapes)
    end
  end

  # Sequential validation (simple, predictable)
  @spec validate_shapes_sequential(RDF.Graph.t(), [NodeShape.t()]) ::
          {:ok, [ValidationResult.t()]}
  defp validate_shapes_sequential(data_graph, node_shapes) do
    results =
      node_shapes
      |> Enum.flat_map(&validate_node_shape(data_graph, &1))

    {:ok, results}
  end

  # Parallel validation (performance)
  @spec validate_shapes_parallel(RDF.Graph.t(), [NodeShape.t()], keyword()) ::
          {:ok, [ValidationResult.t()]}
  defp validate_shapes_parallel(data_graph, node_shapes, opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    timeout = Keyword.get(opts, :timeout, 5_000)

    results =
      node_shapes
      |> Task.async_stream(
        fn shape -> validate_node_shape(data_graph, shape) end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        ordered: false
      )
      |> Enum.flat_map(fn
        {:ok, shape_results} ->
          shape_results

        {:exit, reason} ->
          Logger.warning("Shape validation timed out: #{inspect(reason)}")
          []
      end)

    {:ok, results}
  end

  # Validate a single NodeShape against all its target nodes
  @spec validate_node_shape(RDF.Graph.t(), NodeShape.t()) :: [ValidationResult.t()]
  defp validate_node_shape(data_graph, %NodeShape{} = node_shape) do
    # Find all target nodes for this shape via explicit targeting (sh:targetClass)
    explicit_targets = select_target_nodes(data_graph, node_shape.target_classes)

    # Find all target nodes via implicit class targeting (SHACL 2.1.3.1)
    implicit_targets = select_implicit_target_nodes(data_graph, node_shape.implicit_class_target)

    # Combine and deduplicate target nodes
    target_nodes = (explicit_targets ++ implicit_targets) |> Enum.uniq()

    # Validate each target node
    Enum.flat_map(target_nodes, fn focus_node ->
      validate_focus_node(data_graph, focus_node, node_shape)
    end)
  end

  # Select target nodes from data graph based on sh:targetClass
  @spec select_target_nodes(RDF.Graph.t(), [RDF.IRI.t()]) :: [RDF.Term.t()]
  defp select_target_nodes(_data_graph, target_classes) when target_classes == [] do
    # No target classes specified - shape doesn't target any nodes
    []
  end

  defp select_target_nodes(data_graph, target_classes) do
    # Find all subjects that have rdf:type matching any target class
    target_classes
    |> Enum.flat_map(fn target_class ->
      data_graph
      |> RDF.Graph.triples()
      |> Enum.filter(fn {_s, p, o} ->
        p == RDF.type() && o == target_class
      end)
      |> Enum.map(fn {s, _p, _o} -> s end)
    end)
    |> Enum.uniq()
  end

  # Select target nodes via implicit class targeting (SHACL 2.1.3.1)
  # When a shape is also an rdfs:Class, it implicitly targets all instances of that class
  @spec select_implicit_target_nodes(RDF.Graph.t(), RDF.IRI.t() | nil) :: [RDF.Term.t()]
  defp select_implicit_target_nodes(_data_graph, nil) do
    # No implicit targeting
    []
  end

  defp select_implicit_target_nodes(data_graph, implicit_class_iri) do
    # Find all subjects that have rdf:type matching the implicit class
    data_graph
    |> RDF.Graph.triples()
    |> Enum.filter(fn {_s, p, o} ->
      p == RDF.type() && o == implicit_class_iri
    end)
    |> Enum.map(fn {s, _p, _o} -> s end)
    |> Enum.uniq()
  end

  # Validate a focus node against all property shapes and SPARQL constraints in a NodeShape
  @spec validate_focus_node(RDF.Graph.t(), RDF.Term.t(), NodeShape.t()) ::
          [ValidationResult.t()]
  defp validate_focus_node(data_graph, focus_node, node_shape) do
    # Validate property shapes
    property_results =
      node_shape.property_shapes
      |> Enum.flat_map(fn property_shape ->
        validate_property_shape(data_graph, focus_node, property_shape)
      end)

    # Validate SPARQL constraints (node-level)
    sparql_results = Validators.SPARQL.validate(data_graph, focus_node, node_shape.sparql_constraints)

    property_results ++ sparql_results
  end

  # Dispatch to appropriate constraint validators for a PropertyShape
  @spec validate_property_shape(RDF.Graph.t(), RDF.Term.t(), PropertyShape.t()) ::
          [ValidationResult.t()]
  defp validate_property_shape(data_graph, focus_node, property_shape) do
    []
    |> concat(Validators.Cardinality.validate(data_graph, focus_node, property_shape))
    |> concat(Validators.Type.validate(data_graph, focus_node, property_shape))
    |> concat(Validators.String.validate(data_graph, focus_node, property_shape))
    |> concat(Validators.Value.validate(data_graph, focus_node, property_shape))
    |> concat(Validators.Qualified.validate(data_graph, focus_node, property_shape))
  end

  # Helper: Concatenate results efficiently
  @spec concat([ValidationResult.t()], [ValidationResult.t()]) :: [ValidationResult.t()]
  defp concat(results, []), do: results
  defp concat(results, new_results), do: results ++ new_results
end
