defmodule ElixirOntologies.Builders.Evolution.ActivityBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.Evolution.ActivityBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors.Evolution.ActivityModel.ActivityModel
  alias ElixirOntologies.NS.{Evolution, PROV}

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp create_activity(opts \\ []) do
    defaults = %{
      activity_id: "activity:abc123d",
      activity_type: :feature,
      commit_sha: "abc123def456789012345678901234567890abcd",
      short_sha: "abc123d",
      started_at: ~U[2025-01-15 10:30:00Z],
      ended_at: ~U[2025-01-15 10:35:00Z],
      used_entities: [],
      generated_entities: [],
      invalidated_entities: [],
      informed_by: [],
      informs: [],
      associated_agents: [],
      metadata: %{}
    }

    struct(ActivityModel, Map.merge(defaults, Map.new(opts)))
  end

  defp create_context(opts \\ []) do
    defaults = [base_iri: "https://example.org/code#"]
    Context.new(Keyword.merge(defaults, opts))
  end

  defp find_triple(triples, predicate) do
    Enum.find(triples, fn {_s, p, _o} -> p == predicate end)
  end

  defp find_triples(triples, predicate) do
    Enum.filter(triples, fn {_s, p, _o} -> p == predicate end)
  end

  defp get_object(triples, predicate) do
    case find_triple(triples, predicate) do
      {_s, _p, o} -> o
      nil -> nil
    end
  end

  # ===========================================================================
  # Basic Build Tests
  # ===========================================================================

  describe "build/2" do
    test "returns activity IRI and triples" do
      activity = create_activity()
      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      assert %RDF.IRI{} = activity_iri
      assert is_list(triples)
      assert length(triples) > 0
    end

    test "generates stable IRI from activity_id" do
      activity = create_activity(activity_id: "activity:deadbeef")
      context = create_context()

      {activity_iri, _triples} = ActivityBuilder.build(activity, context)

      assert to_string(activity_iri) == "https://example.org/code#activity/deadbeef"
    end

    test "same activity produces same IRI" do
      activity = create_activity()
      context = create_context()

      {iri1, _} = ActivityBuilder.build(activity, context)
      {iri2, _} = ActivityBuilder.build(activity, context)

      assert iri1 == iri2
    end

    test "handles activity_id without prefix" do
      activity = create_activity(activity_id: "xyz789")
      context = create_context()

      {activity_iri, _triples} = ActivityBuilder.build(activity, context)

      assert to_string(activity_iri) == "https://example.org/code#activity/xyz789"
    end
  end

  # ===========================================================================
  # Type Triple Tests
  # ===========================================================================

  describe "type triples" do
    test "generates prov:Activity type triple" do
      activity = create_activity()
      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      type_triples = find_triples(triples, RDF.type())

      prov_activity_triple =
        Enum.find(type_triples, fn {^activity_iri, _, o} -> o == PROV.Activity end)

      assert prov_activity_triple != nil
    end

    test "generates FeatureAddition type for :feature" do
      activity = create_activity(activity_type: :feature)
      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      type_triples = find_triples(triples, RDF.type())

      feature_triple =
        Enum.find(type_triples, fn {^activity_iri, _, o} -> o == Evolution.FeatureAddition end)

      assert feature_triple != nil
    end

    test "generates BugFix type for :bugfix" do
      activity = create_activity(activity_type: :bugfix)
      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      type_triples = find_triples(triples, RDF.type())

      bugfix_triple =
        Enum.find(type_triples, fn {^activity_iri, _, o} -> o == Evolution.BugFix end)

      assert bugfix_triple != nil
    end

    test "generates Refactoring type for :refactor" do
      activity = create_activity(activity_type: :refactor)
      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      type_triples = find_triples(triples, RDF.type())

      refactor_triple =
        Enum.find(type_triples, fn {^activity_iri, _, o} -> o == Evolution.Refactoring end)

      assert refactor_triple != nil
    end

    test "generates DevelopmentActivity type for :unknown" do
      activity = create_activity(activity_type: :unknown)
      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      type_triples = find_triples(triples, RDF.type())

      dev_activity_triple =
        Enum.find(type_triples, fn {^activity_iri, _, o} -> o == Evolution.DevelopmentActivity end)

      assert dev_activity_triple != nil
    end

    test "generates DevelopmentActivity type for :docs" do
      activity = create_activity(activity_type: :docs)
      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      type_triples = find_triples(triples, RDF.type())

      dev_activity_triple =
        Enum.find(type_triples, fn {^activity_iri, _, o} -> o == Evolution.DevelopmentActivity end)

      assert dev_activity_triple != nil
    end

    test "generates Deprecation type for :deprecation" do
      activity = create_activity(activity_type: :deprecation)
      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      type_triples = find_triples(triples, RDF.type())

      deprecation_triple =
        Enum.find(type_triples, fn {^activity_iri, _, o} -> o == Evolution.Deprecation end)

      assert deprecation_triple != nil
    end
  end

  # ===========================================================================
  # activity_type_to_class/1 Tests
  # ===========================================================================

  describe "activity_type_to_class/1" do
    test "maps :feature to FeatureAddition" do
      assert ActivityBuilder.activity_type_to_class(:feature) == Evolution.FeatureAddition
    end

    test "maps :bugfix to BugFix" do
      assert ActivityBuilder.activity_type_to_class(:bugfix) == Evolution.BugFix
    end

    test "maps :refactor to Refactoring" do
      assert ActivityBuilder.activity_type_to_class(:refactor) == Evolution.Refactoring
    end

    test "maps :deprecation to Deprecation" do
      assert ActivityBuilder.activity_type_to_class(:deprecation) == Evolution.Deprecation
    end

    test "maps :deletion to Deletion" do
      assert ActivityBuilder.activity_type_to_class(:deletion) == Evolution.Deletion
    end

    test "maps :docs to DevelopmentActivity" do
      assert ActivityBuilder.activity_type_to_class(:docs) == Evolution.DevelopmentActivity
    end

    test "maps :test to DevelopmentActivity" do
      assert ActivityBuilder.activity_type_to_class(:test) == Evolution.DevelopmentActivity
    end

    test "maps :chore to DevelopmentActivity" do
      assert ActivityBuilder.activity_type_to_class(:chore) == Evolution.DevelopmentActivity
    end

    test "maps :unknown to DevelopmentActivity" do
      assert ActivityBuilder.activity_type_to_class(:unknown) == Evolution.DevelopmentActivity
    end

    test "maps unknown atoms to DevelopmentActivity" do
      assert ActivityBuilder.activity_type_to_class(:random_type) == Evolution.DevelopmentActivity
    end
  end

  # ===========================================================================
  # Timestamp Triple Tests
  # ===========================================================================

  describe "timestamp triples" do
    test "generates prov:startedAtTime triple" do
      started_at = ~U[2025-01-15 10:30:00Z]
      activity = create_activity(started_at: started_at)
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      started_value = get_object(triples, PROV.startedAtTime())
      assert started_value != nil
      assert RDF.Literal.value(started_value) == started_at
    end

    test "generates prov:endedAtTime triple" do
      ended_at = ~U[2025-01-15 10:35:00Z]
      activity = create_activity(ended_at: ended_at)
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      ended_value = get_object(triples, PROV.endedAtTime())
      assert ended_value != nil
      assert RDF.Literal.value(ended_value) == ended_at
    end

    test "omits timestamp triples when nil" do
      activity = create_activity(started_at: nil, ended_at: nil)
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      assert find_triple(triples, PROV.startedAtTime()) == nil
      assert find_triple(triples, PROV.endedAtTime()) == nil
    end
  end

  # ===========================================================================
  # Usage Triple Tests (prov:used)
  # ===========================================================================

  describe "usage triples" do
    test "generates prov:used triples for used entities" do
      activity =
        create_activity(used_entities: ["MyApp.User@def456e", "MyApp.Repo@ghi789"])

      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      used_triples = find_triples(triples, PROV.used())
      assert length(used_triples) == 2

      # Verify subjects are the activity IRI
      Enum.each(used_triples, fn {s, _, _} ->
        assert s == activity_iri
      end)
    end

    test "generates correct entity IRIs for used entities" do
      activity = create_activity(used_entities: ["entity:MyApp.User@def456e"])
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      used_triples = find_triples(triples, PROV.used())
      {_, _, entity_iri} = hd(used_triples)

      assert to_string(entity_iri) =~ "entity/"
      assert to_string(entity_iri) =~ "MyApp.User"
    end

    test "no prov:used triples when used_entities is empty" do
      activity = create_activity(used_entities: [])
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      used_triples = find_triples(triples, PROV.used())
      assert used_triples == []
    end
  end

  # ===========================================================================
  # Generation Triple Tests (prov:wasGeneratedBy)
  # ===========================================================================

  describe "generation triples" do
    test "generates prov:wasGeneratedBy triples for generated entities" do
      activity =
        create_activity(generated_entities: ["MyApp.User@abc123d", "MyApp.Repo@abc123d"])

      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      generated_triples = find_triples(triples, PROV.wasGeneratedBy())
      assert length(generated_triples) == 2

      # Verify objects are the activity IRI (entity wasGeneratedBy activity)
      Enum.each(generated_triples, fn {_, _, o} ->
        assert o == activity_iri
      end)
    end

    test "generates correct entity IRIs for generated entities" do
      activity = create_activity(generated_entities: ["entity:MyApp.User@abc123d"])
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      generated_triples = find_triples(triples, PROV.wasGeneratedBy())
      {entity_iri, _, _} = hd(generated_triples)

      assert to_string(entity_iri) =~ "entity/"
      assert to_string(entity_iri) =~ "MyApp.User"
    end

    test "no prov:wasGeneratedBy triples when generated_entities is empty" do
      activity = create_activity(generated_entities: [])
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      generated_triples = find_triples(triples, PROV.wasGeneratedBy())
      assert generated_triples == []
    end
  end

  # ===========================================================================
  # Communication Triple Tests (prov:wasInformedBy)
  # ===========================================================================

  describe "communication triples" do
    test "generates prov:wasInformedBy triples" do
      activity =
        create_activity(informed_by: ["activity:def456e", "activity:ghi789"])

      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      informed_triples = find_triples(triples, PROV.wasInformedBy())
      assert length(informed_triples) == 2

      # Verify subjects are the activity IRI
      Enum.each(informed_triples, fn {s, _, _} ->
        assert s == activity_iri
      end)
    end

    test "generates correct activity IRIs for informed_by" do
      activity = create_activity(informed_by: ["activity:def456e"])
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      informed_triples = find_triples(triples, PROV.wasInformedBy())
      {_, _, informing_iri} = hd(informed_triples)

      assert to_string(informing_iri) == "https://example.org/code#activity/def456e"
    end

    test "no prov:wasInformedBy triples when informed_by is empty" do
      activity = create_activity(informed_by: [])
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      informed_triples = find_triples(triples, PROV.wasInformedBy())
      assert informed_triples == []
    end
  end

  # ===========================================================================
  # Agent Association Triple Tests (prov:wasAssociatedWith)
  # ===========================================================================

  describe "agent association triples" do
    test "generates prov:wasAssociatedWith triples" do
      activity =
        create_activity(associated_agents: ["agent:abc123", "agent:def456"])

      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      agent_triples = find_triples(triples, PROV.wasAssociatedWith())
      assert length(agent_triples) == 2

      # Verify subjects are the activity IRI
      Enum.each(agent_triples, fn {s, _, _} ->
        assert s == activity_iri
      end)
    end

    test "generates correct agent IRIs" do
      activity = create_activity(associated_agents: ["agent:abc123"])
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      agent_triples = find_triples(triples, PROV.wasAssociatedWith())
      {_, _, agent_iri} = hd(agent_triples)

      assert to_string(agent_iri) == "https://example.org/code#agent/abc123"
    end

    test "no prov:wasAssociatedWith triples when associated_agents is empty" do
      activity = create_activity(associated_agents: [])
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      agent_triples = find_triples(triples, PROV.wasAssociatedWith())
      assert agent_triples == []
    end
  end

  # ===========================================================================
  # Build All Tests
  # ===========================================================================

  describe "build_all/2" do
    test "builds multiple activities" do
      activities = [
        create_activity(activity_id: "activity:abc1"),
        create_activity(activity_id: "activity:def2")
      ]

      context = create_context()

      results = ActivityBuilder.build_all(activities, context)

      assert length(results) == 2

      Enum.each(results, fn {iri, triples} ->
        assert %RDF.IRI{} = iri
        assert is_list(triples)
      end)
    end

    test "returns empty list for empty input" do
      context = create_context()
      results = ActivityBuilder.build_all([], context)
      assert results == []
    end
  end

  describe "build_all_triples/2" do
    test "returns flat list of all triples" do
      activities = [
        create_activity(activity_id: "activity:abc1"),
        create_activity(activity_id: "activity:def2")
      ]

      context = create_context()

      triples = ActivityBuilder.build_all_triples(activities, context)

      assert is_list(triples)
      # Each activity has at least 2 type triples + 2 timestamp triples
      assert length(triples) >= 8
    end

    test "returns empty list for empty input" do
      context = create_context()
      triples = ActivityBuilder.build_all_triples([], context)
      assert triples == []
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles minimal activity with only required fields" do
      activity = %ActivityModel{
        activity_id: "activity:minimal",
        activity_type: :unknown,
        commit_sha: "abc123def456789012345678901234567890abcd",
        short_sha: "abc123d"
      }

      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      assert %RDF.IRI{} = activity_iri
      # Should have at least 2 type triples
      assert length(triples) >= 2
    end

    test "handles activity with all relationships populated" do
      activity =
        create_activity(
          used_entities: ["entity:a", "entity:b"],
          generated_entities: ["entity:c"],
          informed_by: ["activity:x"],
          associated_agents: ["agent:y", "agent:z"]
        )

      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      assert %RDF.IRI{} = activity_iri
      # 2 types + 2 timestamps + 2 used + 1 generated + 1 informed + 2 agents = 10
      assert length(triples) >= 10
    end

    test "handles special characters in entity IDs" do
      activity = create_activity(used_entities: ["MyApp.User<T>@abc123"])
      context = create_context()

      {_activity_iri, triples} = ActivityBuilder.build(activity, context)

      used_triples = find_triples(triples, PROV.used())
      assert length(used_triples) == 1
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    @tag :integration
    test "builds from real activity extraction" do
      alias ElixirOntologies.Extractors.Evolution.Commit
      alias ElixirOntologies.Extractors.Evolution.ActivityModel, as: AM

      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, activity} = AM.extract_activity(".", commit)
      context = create_context()

      {activity_iri, triples} = ActivityBuilder.build(activity, context)

      assert %RDF.IRI{} = activity_iri
      assert to_string(activity_iri) =~ activity.short_sha
      assert length(triples) > 0

      # Verify type triples
      type_triples = find_triples(triples, RDF.type())
      assert length(type_triples) >= 2
    end
  end
end
