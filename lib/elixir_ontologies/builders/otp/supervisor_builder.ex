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
end
