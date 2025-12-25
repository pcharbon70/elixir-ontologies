defmodule ElixirOntologies.Builders.OTP.SupervisorBuilder do
  @moduledoc """
  Builds RDF triples for OTP Supervisor implementations.

  This module transforms `ElixirOntologies.Extractors.OTP.Supervisor` results into RDF
  triples following the elixir-otp.ttl ontology. It handles:

  - Supervisor implementations (use Supervisor vs @behaviour Supervisor)
  - DynamicSupervisor implementations
  - Supervision strategies (one_for_one, one_for_all, rest_for_one)
  - Child specifications
  - Restart and shutdown strategies

  ## Supervision Patterns

  **Supervisor**: Static process supervision with predefined children
  **DynamicSupervisor**: Dynamic supervision for runtime child management

  **Supervision Strategies**:
  - :one_for_one - Restart only the failed child
  - :one_for_all - Restart all children if one fails
  - :rest_for_one - Restart failed child and all started after it

  ## Usage

      alias ElixirOntologies.Builders.OTP.{SupervisorBuilder, Context}
      alias ElixirOntologies.Extractors.OTP.Supervisor

      # Build Supervisor implementation
      supervisor_info = %Supervisor{
        supervisor_type: :supervisor,
        detection_method: :use,
        location: nil,
        metadata: %{}
      }
      module_iri = ~I<https://example.org/code#MySupervisor>
      context = Context.new(base_iri: "https://example.org/code#")
      {supervisor_iri, triples} = SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor
      iex> supervisor_info = %Supervisor{
      ...>   supervisor_type: :supervisor,
      ...>   detection_method: :use,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {supervisor_iri, _triples} = SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)
      iex> to_string(supervisor_iri)
      "https://example.org/code#MySup"
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.{IRI, NS}
  alias ElixirOntologies.Extractors.OTP.Supervisor
  alias NS.{OTP, Core}

  # ===========================================================================
  # Public API - Supervisor Implementation Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a Supervisor implementation.

  ## Parameters

  - `supervisor_info` - Supervisor extraction result
  - `module_iri` - The IRI of the module implementing Supervisor
  - `context` - Builder context

  ## Returns

  A tuple `{supervisor_iri, triples}` where:
  - `supervisor_iri` - The IRI of the Supervisor (same as module_iri)
  - `triples` - List of RDF triples

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor
      iex> supervisor_info = %Supervisor{
      ...>   supervisor_type: :supervisor,
      ...>   detection_method: :use,
      ...>   location: nil,
      ...>   metadata: %{}
      ...> }
      iex> module_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {supervisor_iri, triples} = SupervisorBuilder.build_supervisor(supervisor_info, module_iri, context)
      iex> type_pred = RDF.type()
      iex> Enum.any?(triples, fn {^supervisor_iri, ^type_pred, _} -> true; _ -> false end)
      true
  """
  @spec build_supervisor(Supervisor.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_supervisor(supervisor_info, module_iri, context) do
    # Supervisor IRI is the same as module IRI
    supervisor_iri = module_iri

    # Build all triples
    triples =
      [
        # Core Supervisor triples
        build_type_triple(supervisor_iri, supervisor_info.supervisor_type),
        build_implements_otp_behaviour_triple(supervisor_iri, supervisor_info.supervisor_type)
      ] ++
        build_location_triple(supervisor_iri, supervisor_info.location, context)

    # Flatten and deduplicate
    triples = List.flatten(triples) |> Enum.uniq()

    {supervisor_iri, triples}
  end

  # ===========================================================================
  # Public API - Supervision Strategy Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a supervision strategy.

  ## Parameters

  - `strategy_info` - Strategy extraction result
  - `supervisor_iri` - The IRI of the supervisor
  - `_context` - Builder context (unused currently)

  ## Returns

  A tuple `{strategy_iri, triples}` where:
  - `strategy_iri` - The IRI of the strategy (predefined individual)
  - `triples` - List of RDF triples
  """
  @spec build_strategy(Supervisor.Strategy.t(), RDF.IRI.t(), Context.t()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_strategy(strategy_info, supervisor_iri, _context) do
    # Strategy IRI is a predefined individual
    strategy_iri = determine_strategy_iri(strategy_info.type)

    # Build triples
    triples = [
      # Link supervisor to strategy
      Helpers.object_property(supervisor_iri, OTP.hasStrategy(), strategy_iri)
    ]

    {strategy_iri, triples}
  end

  # ===========================================================================
  # Supervisor Implementation Triple Generation
  # ===========================================================================

  # Build rdf:type triple for Supervisor or DynamicSupervisor
  defp build_type_triple(supervisor_iri, :supervisor) do
    Helpers.type_triple(supervisor_iri, OTP.Supervisor)
  end

  defp build_type_triple(supervisor_iri, :dynamic_supervisor) do
    Helpers.type_triple(supervisor_iri, OTP.DynamicSupervisor)
  end

  # Build otp:implementsOTPBehaviour triple
  defp build_implements_otp_behaviour_triple(supervisor_iri, :supervisor) do
    Helpers.object_property(supervisor_iri, OTP.implementsOTPBehaviour(), OTP.SupervisorBehaviour)
  end

  defp build_implements_otp_behaviour_triple(supervisor_iri, :dynamic_supervisor) do
    Helpers.object_property(supervisor_iri, OTP.implementsOTPBehaviour(), OTP.SupervisorBehaviour)
  end

  # Build location triple if present
  defp build_location_triple(_supervisor_iri, nil, _context), do: []
  defp build_location_triple(_supervisor_iri, _location, %Context{file_path: nil}), do: []

  defp build_location_triple(supervisor_iri, location, context) do
    file_iri = IRI.for_source_file(context.base_iri, context.file_path)
    end_line = location.end_line || location.start_line
    location_iri = IRI.for_source_location(file_iri, location.start_line, end_line)

    [Helpers.object_property(supervisor_iri, Core.hasSourceLocation(), location_iri)]
  end

  # ===========================================================================
  # Strategy Triple Generation
  # ===========================================================================

  # Determine strategy IRI (predefined individuals from ontology)
  defp determine_strategy_iri(:one_for_one), do: OTP.OneForOne
  defp determine_strategy_iri(:one_for_all), do: OTP.OneForAll
  defp determine_strategy_iri(:rest_for_one), do: OTP.RestForOne

  # ===========================================================================
  # Public API - Child Spec Building
  # ===========================================================================

  @doc """
  Builds RDF triples for a child specification.

  ## Parameters

  - `child_spec` - ChildSpec extraction result
  - `supervisor_iri` - The IRI of the supervisor
  - `context` - Builder context
  - `index` - Position in children list (default: 0)

  ## Returns

  A tuple `{child_spec_iri, triples}` where:
  - `child_spec_iri` - The IRI of the child spec
  - `triples` - List of RDF triples

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
      iex> child_spec = %ChildSpec{
      ...>   id: :worker1,
      ...>   module: MyWorker,
      ...>   restart: :permanent,
      ...>   type: :worker
      ...> }
      iex> supervisor_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {child_spec_iri, triples} = SupervisorBuilder.build_child_spec(child_spec, supervisor_iri, context, 0)
      iex> to_string(child_spec_iri) =~ "MySup/child/worker1/0"
      true
      iex> Enum.any?(triples, fn {_, pred, _} -> pred == RDF.type() end)
      true
  """
  @spec build_child_spec(Supervisor.ChildSpec.t(), RDF.IRI.t(), Context.t(), non_neg_integer()) ::
          {RDF.IRI.t(), [RDF.Triple.t()]}
  def build_child_spec(child_spec, supervisor_iri, _context, index \\ 0) do
    # Generate child spec IRI
    child_id = child_spec.id || child_spec.module || :unknown
    child_spec_iri = IRI.for_child_spec(supervisor_iri, child_id, index)

    # Build all triples
    triples =
      [
        # Type triple
        Helpers.type_triple(child_spec_iri, OTP.ChildSpec),

        # Link supervisor to child spec
        Helpers.object_property(supervisor_iri, OTP.hasChildSpec(), child_spec_iri),

        # Child ID
        build_child_id_triple(child_spec_iri, child_id),

        # Start function
        build_start_module_triple(child_spec_iri, child_spec),
        build_start_function_triple(child_spec_iri, child_spec),

        # Restart strategy
        build_restart_strategy_triple(child_spec_iri, child_spec.restart),

        # Child type
        build_child_type_triple(child_spec_iri, child_spec.type)
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    {child_spec_iri, triples}
  end

  @doc """
  Builds RDF triples for multiple child specifications.

  Iterates through a list of ChildSpec structs and builds triples for each,
  using the list position as the index.

  ## Parameters

  - `child_specs` - List of ChildSpec extraction results
  - `supervisor_iri` - The IRI of the supervisor
  - `context` - Builder context

  ## Returns

  A tuple `{child_spec_iris, all_triples}` where:
  - `child_spec_iris` - List of IRIs for all child specs
  - `all_triples` - Combined list of RDF triples

  ## Examples

      iex> alias ElixirOntologies.Builders.OTP.SupervisorBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.OTP.Supervisor.ChildSpec
      iex> specs = [
      ...>   %ChildSpec{id: :worker1, module: Worker1, restart: :permanent, type: :worker},
      ...>   %ChildSpec{id: :worker2, module: Worker2, restart: :temporary, type: :worker}
      ...> ]
      iex> supervisor_iri = RDF.iri("https://example.org/code#MySup")
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {iris, triples} = SupervisorBuilder.build_child_specs(specs, supervisor_iri, context)
      iex> length(iris)
      2
      iex> length(triples) > 0
      true
  """
  @spec build_child_specs([Supervisor.ChildSpec.t()], RDF.IRI.t(), Context.t()) ::
          {[RDF.IRI.t()], [RDF.Triple.t()]}
  def build_child_specs(child_specs, supervisor_iri, context) when is_list(child_specs) do
    {iris, triples_list} =
      child_specs
      |> Enum.with_index()
      |> Enum.map(fn {spec, index} ->
        build_child_spec(spec, supervisor_iri, context, index)
      end)
      |> Enum.unzip()

    {iris, List.flatten(triples_list)}
  end

  # ===========================================================================
  # Child Spec Triple Generation
  # ===========================================================================

  # Build child ID triple
  defp build_child_id_triple(child_spec_iri, child_id) do
    id_string = format_id_for_literal(child_id)
    Helpers.datatype_property(child_spec_iri, OTP.childId(), id_string)
  end

  # Build start module triple
  defp build_start_module_triple(_child_spec_iri, %{start: nil}), do: nil
  defp build_start_module_triple(_child_spec_iri, %{module: nil, start: %{module: nil}}), do: nil

  defp build_start_module_triple(child_spec_iri, %{start: %{module: module}}) when not is_nil(module) do
    module_string = format_id_for_literal(module)
    Helpers.datatype_property(child_spec_iri, OTP.startModule(), module_string)
  end

  defp build_start_module_triple(child_spec_iri, %{module: module}) when not is_nil(module) do
    module_string = format_id_for_literal(module)
    Helpers.datatype_property(child_spec_iri, OTP.startModule(), module_string)
  end

  defp build_start_module_triple(_, _), do: nil

  # Build start function triple
  defp build_start_function_triple(_child_spec_iri, %{start: nil}), do: nil
  defp build_start_function_triple(_child_spec_iri, %{start: %{function: nil}}), do: nil

  defp build_start_function_triple(child_spec_iri, %{start: %{function: function}}) when not is_nil(function) do
    function_string = Atom.to_string(function)
    Helpers.datatype_property(child_spec_iri, OTP.startFunction(), function_string)
  end

  defp build_start_function_triple(_, _), do: nil

  # Build restart strategy triple
  defp build_restart_strategy_triple(child_spec_iri, restart_type) do
    restart_iri = determine_restart_strategy_iri(restart_type)
    Helpers.object_property(child_spec_iri, OTP.hasRestartStrategy(), restart_iri)
  end

  # Build child type triple
  defp build_child_type_triple(child_spec_iri, child_type) do
    type_iri = determine_child_type_iri(child_type)
    Helpers.object_property(child_spec_iri, OTP.hasChildType(), type_iri)
  end

  # Determine restart strategy IRI (predefined individuals from ontology)
  defp determine_restart_strategy_iri(:permanent), do: OTP.Permanent
  defp determine_restart_strategy_iri(:temporary), do: OTP.Temporary
  defp determine_restart_strategy_iri(:transient), do: OTP.Transient
  defp determine_restart_strategy_iri(_), do: OTP.Permanent

  # Determine child type IRI (predefined individuals from ontology)
  defp determine_child_type_iri(:worker), do: OTP.WorkerType
  defp determine_child_type_iri(:supervisor), do: OTP.SupervisorType
  defp determine_child_type_iri(_), do: OTP.WorkerType

  # Format ID for RDF literal (atom, module, or other term)
  defp format_id_for_literal(id) when is_atom(id) do
    id |> Atom.to_string() |> String.replace("Elixir.", "")
  end

  defp format_id_for_literal(id), do: inspect(id)
end
