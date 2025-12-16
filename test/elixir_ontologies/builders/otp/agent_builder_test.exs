defmodule ElixirOntologies.Builders.OTP.AgentBuilderTest do
  use ExUnit.Case, async: true
  doctest ElixirOntologies.Builders.OTP.AgentBuilder

  alias ElixirOntologies.Builders.OTP.AgentBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors.OTP.Agent
  alias ElixirOntologies.NS.OTP

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp build_test_context(opts \\ []) do
    Context.new(
      base_iri: Keyword.get(opts, :base_iri, "https://example.org/code#"),
      file_path: Keyword.get(opts, :file_path, nil)
    )
  end

  defp build_test_module_iri(opts \\ []) do
    base_iri = Keyword.get(opts, :base_iri, "https://example.org/code#")
    module_name = Keyword.get(opts, :module_name, "TestAgent")
    RDF.iri("#{base_iri}#{module_name}")
  end

  defp build_test_agent(opts \\ []) do
    %Agent{
      detection_method: Keyword.get(opts, :detection_method, :use),
      use_options: Keyword.get(opts, :use_options, []),
      function_calls: Keyword.get(opts, :function_calls, []),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # ===========================================================================
  # Agent Implementation Building Tests
  # ===========================================================================

  describe "build_agent/3 - basic building" do
    test "builds minimal Agent with use detection" do
      agent_info = build_test_agent(detection_method: :use)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Verify IRI (same as module IRI)
      assert agent_iri == module_iri
      assert to_string(agent_iri) == "https://example.org/code#TestAgent"

      # Verify type triple
      assert {agent_iri, RDF.type(), OTP.Agent} in triples

      # Verify implementsOTPBehaviour triple
      assert {agent_iri, OTP.implementsOTPBehaviour(), OTP.Agent} in triples
    end

    test "builds Agent with behaviour detection" do
      agent_info = build_test_agent(detection_method: :behaviour, use_options: nil)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Verify type triple
      assert {agent_iri, RDF.type(), OTP.Agent} in triples

      # Verify implementsOTPBehaviour triple
      assert {agent_iri, OTP.implementsOTPBehaviour(), OTP.Agent} in triples
    end

    test "builds Agent with function_call detection" do
      agent_info = build_test_agent(detection_method: :function_call, use_options: nil)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Verify type triple
      assert {agent_iri, RDF.type(), OTP.Agent} in triples

      # Verify implementsOTPBehaviour triple
      assert {agent_iri, OTP.implementsOTPBehaviour(), OTP.Agent} in triples
    end

    test "builds Agent with use options" do
      agent_info = build_test_agent(use_options: [restart: :transient, shutdown: 5000])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Verify Agent implementation exists
      assert {agent_iri, RDF.type(), OTP.Agent} in triples
    end

    test "builds Agent without use options" do
      agent_info = build_test_agent(use_options: [])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Verify Agent implementation exists
      assert {agent_iri, RDF.type(), OTP.Agent} in triples
    end
  end

  describe "build_agent/3 - IRI patterns" do
    test "Agent IRI is same as module IRI" do
      agent_info = build_test_agent()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "Counter")

      {agent_iri, _triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      assert agent_iri == module_iri
      assert to_string(agent_iri) == "https://example.org/code#Counter"
    end

    test "handles nested module names" do
      agent_info = build_test_agent()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.Agents.Counter")

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      assert agent_iri == module_iri
      assert {agent_iri, RDF.type(), OTP.Agent} in triples
    end
  end

  # ===========================================================================
  # Triple Validation Tests
  # ===========================================================================

  describe "triple validation" do
    test "no duplicate triples in Agent implementation" do
      agent_info = build_test_agent()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {_agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Check for duplicates
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "Agent has both type and implementsOTPBehaviour" do
      agent_info = build_test_agent()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Count relevant triples
      has_type = Enum.any?(triples, fn
        {^agent_iri, pred, OTP.Agent} -> pred == RDF.type()
        _ -> false
      end)

      has_behaviour = Enum.any?(triples, fn
        {^agent_iri, pred, OTP.Agent} -> pred == OTP.implementsOTPBehaviour()
        _ -> false
      end)

      assert has_type
      assert has_behaviour
    end

    test "all expected triples for basic Agent" do
      agent_info = build_test_agent()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Should have at least 2 triples (type + implementsOTPBehaviour)
      assert length(triples) >= 2

      # Verify all triples have the agent IRI as subject
      assert Enum.all?(triples, fn {subj, _, _} -> subj == agent_iri end)
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "Agent in nested module" do
      agent_info = build_test_agent()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.Services.CounterAgent")

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Verify implementation
      assert {agent_iri, RDF.type(), OTP.Agent} in triples
      assert to_string(agent_iri) == "https://example.org/code#MyApp.Services.CounterAgent"
    end

    test "multiple detection methods produce same structure" do
      context = build_test_context()
      module_iri = build_test_module_iri()

      agent_use = build_test_agent(detection_method: :use)
      agent_behaviour = build_test_agent(detection_method: :behaviour, use_options: nil)
      agent_function = build_test_agent(detection_method: :function_call, use_options: nil)

      {_, triples_use} = AgentBuilder.build_agent(agent_use, module_iri, context)
      {_, triples_behaviour} = AgentBuilder.build_agent(agent_behaviour, module_iri, context)
      {_, triples_function} = AgentBuilder.build_agent(agent_function, module_iri, context)

      # All should have same core triples (type + implementsOTPBehaviour)
      assert length(triples_use) == length(triples_behaviour)
      assert length(triples_behaviour) == length(triples_function)
    end

    test "Agent with different base IRIs" do
      agent_info = build_test_agent()
      context1 = build_test_context(base_iri: "https://example.org/code#")
      context2 = build_test_context(base_iri: "https://different.org/app#")

      module_iri1 = build_test_module_iri(base_iri: "https://example.org/code#")
      module_iri2 = build_test_module_iri(base_iri: "https://different.org/app#")

      {agent_iri1, triples1} = AgentBuilder.build_agent(agent_info, module_iri1, context1)
      {agent_iri2, triples2} = AgentBuilder.build_agent(agent_info, module_iri2, context2)

      # Different IRIs but same structure
      assert agent_iri1 != agent_iri2
      assert length(triples1) == length(triples2)
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "Agent with empty use options" do
      agent_info = build_test_agent(use_options: [])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Verify implementation
      assert {agent_iri, RDF.type(), OTP.Agent} in triples
    end

    test "Agent with nil use options" do
      agent_info = build_test_agent(use_options: nil)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Verify implementation
      assert {agent_iri, RDF.type(), OTP.Agent} in triples
    end

    test "Agent with nil location" do
      agent_info = build_test_agent(location: nil)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Should still work, just no location triple
      assert {agent_iri, RDF.type(), OTP.Agent} in triples
      assert {agent_iri, OTP.implementsOTPBehaviour(), OTP.Agent} in triples
    end

    test "Agent with context that has no file_path" do
      agent_info = build_test_agent(
        location: %ElixirOntologies.Analyzer.Location.SourceLocation{
          start_line: 5,
          start_column: 1
        }
      )
      context = build_test_context(file_path: nil)
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Should still work, just no location triple
      assert {agent_iri, RDF.type(), OTP.Agent} in triples
    end

    test "Agent with metadata" do
      agent_info = build_test_agent(
        metadata: %{
          otp_behaviour: :agent,
          has_options: true,
          custom_key: "custom_value"
        }
      )
      context = build_test_context()
      module_iri = build_test_module_iri()

      {agent_iri, triples} =
        AgentBuilder.build_agent(agent_info, module_iri, context)

      # Metadata doesn't affect triples, but implementation should still work
      assert {agent_iri, RDF.type(), OTP.Agent} in triples
    end
  end
end
