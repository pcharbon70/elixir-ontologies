defmodule ElixirOntologies.Builders.Evolution.ActivityBuilder do
  @moduledoc """
  Builds RDF triples for development activities using PROV-O Activity class.

  This module transforms `ElixirOntologies.Extractors.Evolution.ActivityModel.ActivityModel`
  results into RDF triples following the elixir-evolution.ttl ontology. It handles:

  - Activity type classification (FeatureAddition, BugFix, Refactoring, etc.)
  - PROV-O temporal relationships (startedAtTime, endedAtTime)
  - Entity usage and generation (prov:used, prov:generated)
  - Activity communication chains (prov:wasInformedBy)
  - Agent associations (prov:wasAssociatedWith)

  ## Usage

      alias ElixirOntologies.Builders.Evolution.ActivityBuilder
      alias ElixirOntologies.Builders.Context
      alias ElixirOntologies.Extractors.Evolution.ActivityModel
      alias ElixirOntologies.Extractors.Evolution.Commit

      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, activity} = ActivityModel.extract_activity(".", commit)
      context = Context.new(base_iri: "https://example.org/code#")

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

  ## RDF Output

  For an activity:

      activity:abc123d a evo:FeatureAddition, prov:Activity ;
          prov:startedAtTime "2025-01-15T10:30:00Z"^^xsd:dateTime ;
          prov:endedAtTime "2025-01-15T10:35:00Z"^^xsd:dateTime ;
          prov:used entity:MyApp.User@def456e ;
          prov:generated entity:MyApp.User@abc123d ;
          prov:wasInformedBy activity:def456e ;
          prov:wasAssociatedWith agent:xyz123 .

  ## Activity Type Mapping

  | Activity Type | Ontology Class |
  |--------------|----------------|
  | `:feature` | `evolution:FeatureAddition` |
  | `:bugfix` | `evolution:BugFix` |
  | `:refactor` | `evolution:Refactoring` |
  | `:docs` | `evolution:DevelopmentActivity` |
  | `:test` | `evolution:DevelopmentActivity` |
  | `:chore` | `evolution:DevelopmentActivity` |
  | `:deprecation` | `evolution:Deprecation` |
  | `:deletion` | `evolution:Deletion` |
  | `:unknown` | `evolution:DevelopmentActivity` |

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.ActivityBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.Evolution.ActivityModel.ActivityModel
      iex> activity = %ActivityModel{
      ...>   activity_id: "activity:abc123d",
      ...>   activity_type: :feature,
      ...>   commit_sha: "abc123def456789012345678901234567890abcd",
      ...>   short_sha: "abc123d",
      ...>   started_at: nil,
      ...>   ended_at: nil,
      ...>   used_entities: [],
      ...>   generated_entities: [],
      ...>   informed_by: [],
      ...>   associated_agents: []
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {activity_iri, triples} = ActivityBuilder.build(activity, context)
      iex> to_string(activity_iri) |> String.contains?("abc123d")
      true
      iex> length(triples) >= 2
      true
  """

  alias ElixirOntologies.Builders.{Context, Helpers}
  alias ElixirOntologies.Extractors.Evolution.ActivityModel.ActivityModel
  alias ElixirOntologies.NS.{Evolution, PROV}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds RDF triples for an activity.

  Takes an ActivityModel struct and builder context, returns the activity IRI
  and a list of RDF triples representing the activity in the ontology.

  ## Parameters

  - `activity` - ActivityModel struct from `Extractors.Evolution.ActivityModel`
  - `context` - Builder context with base IRI and configuration

  ## Returns

  A tuple `{activity_iri, triples}` where:
  - `activity_iri` - The IRI of the activity
  - `triples` - List of RDF triples describing the activity

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.ActivityBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> alias ElixirOntologies.Extractors.Evolution.ActivityModel.ActivityModel
      iex> activity = %ActivityModel{
      ...>   activity_id: "activity:abc123d",
      ...>   activity_type: :bugfix,
      ...>   commit_sha: "abc123def456789012345678901234567890abcd",
      ...>   short_sha: "abc123d"
      ...> }
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> {activity_iri, triples} = ActivityBuilder.build(activity, context)
      iex> is_list(triples) and length(triples) > 0
      true
  """
  @spec build(ActivityModel.t(), Context.t()) :: {RDF.IRI.t(), [RDF.Triple.t()]}
  def build(%ActivityModel{} = activity, %Context{} = context) do
    # Generate activity IRI
    activity_iri = generate_activity_iri(activity, context)

    # Build all triples using list of lists pattern
    triples =
      [
        build_type_triples(activity_iri, activity),
        build_timestamp_triples(activity_iri, activity),
        build_usage_triples(activity_iri, activity, context),
        build_generation_triples(activity_iri, activity, context),
        build_communication_triples(activity_iri, activity, context),
        build_agent_triples(activity_iri, activity, context)
      ]
      |> Helpers.finalize_triples()

    {activity_iri, triples}
  end

  @doc """
  Builds RDF triples for multiple activities.

  ## Parameters

  - `activities` - List of ActivityModel structs
  - `context` - Builder context

  ## Returns

  A list of `{activity_iri, triples}` tuples.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.ActivityBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> results = ActivityBuilder.build_all([], context)
      iex> results
      []
  """
  @spec build_all([ActivityModel.t()], Context.t()) :: [{RDF.IRI.t(), [RDF.Triple.t()]}]
  def build_all(activities, context) when is_list(activities) do
    Enum.map(activities, &build(&1, context))
  end

  @doc """
  Builds RDF triples for multiple activities and collects all triples.

  Returns a flat list of all triples from all activities.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.ActivityBuilder
      iex> alias ElixirOntologies.Builders.Context
      iex> context = Context.new(base_iri: "https://example.org/code#")
      iex> triples = ActivityBuilder.build_all_triples([], context)
      iex> triples
      []
  """
  @spec build_all_triples([ActivityModel.t()], Context.t()) :: [RDF.Triple.t()]
  def build_all_triples(activities, context) when is_list(activities) do
    activities
    |> build_all(context)
    |> Enum.flat_map(fn {_iri, triples} -> triples end)
  end

  # ===========================================================================
  # IRI Generation
  # ===========================================================================

  defp generate_activity_iri(activity, context) do
    base = to_string(context.base_iri)

    # Activity IDs are in format "activity:abc123d"
    # We extract the ID part and create a proper IRI
    case activity.activity_id do
      "activity:" <> id ->
        RDF.iri("#{base}activity/#{id}")

      id ->
        # Fallback if not prefixed
        RDF.iri("#{base}activity/#{id}")
    end
  end

  # ===========================================================================
  # Type Triple Generation
  # ===========================================================================

  defp build_type_triples(activity_iri, activity) do
    # Dual-typing: prov:Activity + specific evolution class
    evolution_class = activity_type_to_class(activity.activity_type)
    Helpers.dual_type_triples(activity_iri, PROV.Activity, evolution_class)
  end

  @doc """
  Maps an activity type atom to its corresponding ontology class.

  ## Examples

      iex> alias ElixirOntologies.Builders.Evolution.ActivityBuilder
      iex> alias ElixirOntologies.NS.Evolution
      iex> ActivityBuilder.activity_type_to_class(:feature) == Evolution.FeatureAddition
      true

      iex> alias ElixirOntologies.Builders.Evolution.ActivityBuilder
      iex> alias ElixirOntologies.NS.Evolution
      iex> ActivityBuilder.activity_type_to_class(:bugfix) == Evolution.BugFix
      true
  """
  @spec activity_type_to_class(atom()) :: RDF.IRI.t()
  def activity_type_to_class(:feature), do: Evolution.FeatureAddition |> RDF.iri()
  def activity_type_to_class(:bugfix), do: Evolution.BugFix |> RDF.iri()
  def activity_type_to_class(:refactor), do: Evolution.Refactoring |> RDF.iri()
  def activity_type_to_class(:deprecation), do: Evolution.Deprecation |> RDF.iri()
  def activity_type_to_class(:deletion), do: Evolution.Deletion |> RDF.iri()
  def activity_type_to_class(:docs), do: Evolution.DevelopmentActivity |> RDF.iri()
  def activity_type_to_class(:test), do: Evolution.DevelopmentActivity |> RDF.iri()
  def activity_type_to_class(:chore), do: Evolution.DevelopmentActivity |> RDF.iri()
  def activity_type_to_class(:perf), do: Evolution.DevelopmentActivity |> RDF.iri()
  def activity_type_to_class(:style), do: Evolution.DevelopmentActivity |> RDF.iri()
  def activity_type_to_class(:build), do: Evolution.DevelopmentActivity |> RDF.iri()
  def activity_type_to_class(:ci), do: Evolution.DevelopmentActivity |> RDF.iri()
  def activity_type_to_class(:revert), do: Evolution.DevelopmentActivity |> RDF.iri()
  def activity_type_to_class(:unknown), do: Evolution.DevelopmentActivity |> RDF.iri()
  # Catch-all with guard for unknown atom types
  def activity_type_to_class(type) when is_atom(type),
    do: Evolution.DevelopmentActivity |> RDF.iri()

  # ===========================================================================
  # Timestamp Triple Generation
  # ===========================================================================

  defp build_timestamp_triples(activity_iri, activity) do
    # Data-driven approach: PROV-O timestamp properties
    [
      Helpers.optional_datetime_property(activity_iri, PROV.startedAtTime(), activity.started_at),
      Helpers.optional_datetime_property(activity_iri, PROV.endedAtTime(), activity.ended_at)
    ]
  end

  # ===========================================================================
  # Usage Triple Generation (prov:used)
  # ===========================================================================

  defp build_usage_triples(activity_iri, activity, context) do
    Enum.map(activity.used_entities, fn entity_id ->
      entity_iri = generate_entity_iri(entity_id, context)
      Helpers.object_property(activity_iri, PROV.used(), entity_iri)
    end)
  end

  # ===========================================================================
  # Generation Triple Generation (prov:wasGeneratedBy)
  # ===========================================================================

  defp build_generation_triples(activity_iri, activity, context) do
    # In PROV-O, generation is expressed from entity perspective:
    # entity prov:wasGeneratedBy activity
    Enum.map(activity.generated_entities, fn entity_id ->
      entity_iri = generate_entity_iri(entity_id, context)
      Helpers.object_property(entity_iri, PROV.wasGeneratedBy(), activity_iri)
    end)
  end

  # ===========================================================================
  # Communication Triple Generation (prov:wasInformedBy)
  # ===========================================================================

  defp build_communication_triples(activity_iri, activity, context) do
    Enum.map(activity.informed_by, fn informing_activity_id ->
      informing_iri = generate_informing_activity_iri(informing_activity_id, context)
      Helpers.object_property(activity_iri, PROV.wasInformedBy(), informing_iri)
    end)
  end

  # ===========================================================================
  # Agent Association Triple Generation (prov:wasAssociatedWith)
  # ===========================================================================

  defp build_agent_triples(activity_iri, activity, context) do
    Enum.map(activity.associated_agents, fn agent_id ->
      agent_iri = generate_agent_iri(agent_id, context)
      Helpers.object_property(activity_iri, PROV.wasAssociatedWith(), agent_iri)
    end)
  end

  # ===========================================================================
  # IRI Generation Helpers
  # ===========================================================================

  defp generate_entity_iri(entity_id, context) do
    base = to_string(context.base_iri)

    # Entity IDs may be in format "ModuleName@sha" or prefixed
    case entity_id do
      "entity:" <> id ->
        RDF.iri("#{base}entity/#{URI.encode(id)}")

      id ->
        # Assume it's a raw entity ID
        RDF.iri("#{base}entity/#{URI.encode(id)}")
    end
  end

  defp generate_informing_activity_iri(activity_id, context) do
    base = to_string(context.base_iri)

    case activity_id do
      "activity:" <> id ->
        RDF.iri("#{base}activity/#{id}")

      id ->
        RDF.iri("#{base}activity/#{id}")
    end
  end

  defp generate_agent_iri(agent_id, context) do
    base = to_string(context.base_iri)

    case agent_id do
      "agent:" <> id ->
        RDF.iri("#{base}agent/#{id}")

      id ->
        RDF.iri("#{base}agent/#{id}")
    end
  end
end
