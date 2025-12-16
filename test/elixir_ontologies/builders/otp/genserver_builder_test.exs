defmodule ElixirOntologies.Builders.OTP.GenServerBuilderTest do
  use ExUnit.Case, async: true
  doctest ElixirOntologies.Builders.OTP.GenServerBuilder

  alias ElixirOntologies.Builders.OTP.GenServerBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Extractors.OTP.GenServer
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
    module_name = Keyword.get(opts, :module_name, "TestServer")
    RDF.iri("#{base_iri}#{module_name}")
  end

  defp build_test_genserver(opts \\ []) do
    %GenServer{
      detection_method: Keyword.get(opts, :detection_method, :use),
      use_options: Keyword.get(opts, :use_options, []),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp build_test_callback(opts \\ []) do
    %GenServer.Callback{
      type: Keyword.get(opts, :type, :init),
      name: Keyword.get(opts, :name, :init),
      arity: Keyword.get(opts, :arity, 1),
      clauses: Keyword.get(opts, :clauses, 1),
      has_impl: Keyword.get(opts, :has_impl, false),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # ===========================================================================
  # GenServer Implementation Building Tests
  # ===========================================================================

  describe "build_genserver/3 - basic building" do
    test "builds minimal GenServer with use detection" do
      genserver_info = build_test_genserver(detection_method: :use)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Verify IRI (same as module IRI)
      assert genserver_iri == module_iri
      assert to_string(genserver_iri) == "https://example.org/code#TestServer"

      # Verify type triple
      assert {genserver_iri, RDF.type(), OTP.GenServerImplementation} in triples

      # Verify implementsOTPBehaviour triple
      assert {genserver_iri, OTP.implementsOTPBehaviour(), OTP.GenServer} in triples
    end

    test "builds GenServer with behaviour detection" do
      genserver_info = build_test_genserver(detection_method: :behaviour, use_options: nil)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Verify type triple
      assert {genserver_iri, RDF.type(), OTP.GenServerImplementation} in triples
    end

    test "builds GenServer with use options" do
      genserver_info = build_test_genserver(use_options: [restart: :transient, shutdown: 5000])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Verify GenServer implementation exists
      assert {genserver_iri, RDF.type(), OTP.GenServerImplementation} in triples
    end
  end

  describe "build_genserver/3 - IRI patterns" do
    test "GenServer IRI is same as module IRI" do
      genserver_info = build_test_genserver()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "Counter")

      {genserver_iri, _triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      assert genserver_iri == module_iri
      assert to_string(genserver_iri) == "https://example.org/code#Counter"
    end

    test "handles nested module names" do
      genserver_info = build_test_genserver()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.Workers.Counter")

      {genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      assert genserver_iri == module_iri
      assert {genserver_iri, RDF.type(), OTP.GenServerImplementation} in triples
    end
  end

  # ===========================================================================
  # GenServer Callback Building Tests
  # ===========================================================================

  describe "build_callback/3 - init callback" do
    test "builds init/1 callback" do
      callback_info = build_test_callback(type: :init, name: :init, arity: 1)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Verify callback IRI uses function pattern
      assert to_string(callback_iri) == "https://example.org/code#TestServer/init/1"

      # Verify specific callback type
      assert {callback_iri, RDF.type(), OTP.InitCallback} in triples

      # Verify generic GenServerCallback type
      assert {callback_iri, RDF.type(), OTP.GenServerCallback} in triples

      # Verify hasGenServerCallback link
      assert {module_iri, OTP.hasGenServerCallback(), callback_iri} in triples
    end
  end

  describe "build_callback/3 - handle_call callback" do
    test "builds handle_call/3 callback" do
      callback_info = build_test_callback(type: :handle_call, name: :handle_call, arity: 3)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Verify callback IRI
      assert to_string(callback_iri) == "https://example.org/code#TestServer/handle_call/3"

      # Verify specific callback type
      assert {callback_iri, RDF.type(), OTP.HandleCallCallback} in triples

      # Verify generic type
      assert {callback_iri, RDF.type(), OTP.GenServerCallback} in triples
    end
  end

  describe "build_callback/3 - handle_cast callback" do
    test "builds handle_cast/2 callback" do
      callback_info = build_test_callback(type: :handle_cast, name: :handle_cast, arity: 2)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Verify specific callback type
      assert {callback_iri, RDF.type(), OTP.HandleCastCallback} in triples
    end
  end

  describe "build_callback/3 - handle_info callback" do
    test "builds handle_info/2 callback" do
      callback_info = build_test_callback(type: :handle_info, name: :handle_info, arity: 2)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Verify specific callback type
      assert {callback_iri, RDF.type(), OTP.HandleInfoCallback} in triples
    end
  end

  describe "build_callback/3 - handle_continue callback" do
    test "builds handle_continue/2 callback" do
      callback_info = build_test_callback(type: :handle_continue, name: :handle_continue, arity: 2)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Verify specific callback type
      assert {callback_iri, RDF.type(), OTP.HandleContinueCallback} in triples
    end
  end

  describe "build_callback/3 - terminate callback" do
    test "builds terminate/2 callback" do
      callback_info = build_test_callback(type: :terminate, name: :terminate, arity: 2)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Verify specific callback type
      assert {callback_iri, RDF.type(), OTP.TerminateCallback} in triples
    end
  end

  describe "build_callback/3 - code_change callback" do
    test "builds code_change/3 callback" do
      callback_info = build_test_callback(type: :code_change, name: :code_change, arity: 3)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Verify specific callback type
      assert {callback_iri, RDF.type(), OTP.CodeChangeCallback} in triples
    end
  end

  describe "build_callback/3 - format_status callback" do
    test "builds format_status/1 callback" do
      callback_info = build_test_callback(type: :format_status, name: :format_status, arity: 1)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Verify specific callback type
      assert {callback_iri, RDF.type(), OTP.FormatStatusCallback} in triples
    end
  end

  # ===========================================================================
  # Triple Validation Tests
  # ===========================================================================

  describe "triple validation" do
    test "no duplicate triples in GenServer implementation" do
      genserver_info = build_test_genserver()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {_genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Check for duplicates
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "no duplicate triples in callback" do
      callback_info = build_test_callback()
      context = build_test_context()
      module_iri = build_test_module_iri()

      {_callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Check for duplicates
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "callback has both specific and generic types" do
      callback_info = build_test_callback(type: :init)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Count type triples
      type_count =
        Enum.count(triples, fn
          {^callback_iri, pred, _} -> pred == RDF.type()
          _ -> false
        end)

      # Should have 2 types: InitCallback + GenServerCallback
      assert type_count == 2
    end
  end

  # ===========================================================================
  # Integration Tests
  # ===========================================================================

  describe "integration" do
    test "can build GenServer with multiple callbacks" do
      genserver_info = build_test_genserver()
      context = build_test_context()
      module_iri = build_test_module_iri()

      # Build GenServer
      {genserver_iri, genserver_triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Build callbacks
      init_callback = build_test_callback(type: :init, name: :init, arity: 1)
      handle_call_callback = build_test_callback(type: :handle_call, name: :handle_call, arity: 3)

      {init_iri, init_triples} = GenServerBuilder.build_callback(init_callback, module_iri, context)

      {call_iri, call_triples} =
        GenServerBuilder.build_callback(handle_call_callback, module_iri, context)

      # Verify GenServer implementation exists
      assert {genserver_iri, RDF.type(), OTP.GenServerImplementation} in genserver_triples

      # Verify both callbacks link to GenServer
      assert {genserver_iri, OTP.hasGenServerCallback(), init_iri} in init_triples
      assert {genserver_iri, OTP.hasGenServerCallback(), call_iri} in call_triples

      # Verify different callback IRIs
      assert init_iri != call_iri
    end

    test "GenServer in nested module" do
      genserver_info = build_test_genserver()
      context = build_test_context()
      module_iri = build_test_module_iri(module_name: "MyApp.Services.CounterServer")

      {genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Verify implementation
      assert {genserver_iri, RDF.type(), OTP.GenServerImplementation} in triples
      assert to_string(genserver_iri) == "https://example.org/code#MyApp.Services.CounterServer"
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "callback with multiple clauses" do
      callback_info = build_test_callback(clauses: 3)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Verify callback exists
      assert {callback_iri, RDF.type(), OTP.InitCallback} in triples
    end

    test "callback with @impl annotation" do
      callback_info = build_test_callback(has_impl: true)
      context = build_test_context()
      module_iri = build_test_module_iri()

      {callback_iri, triples} = GenServerBuilder.build_callback(callback_info, module_iri, context)

      # Verify callback exists
      assert {callback_iri, RDF.type(), OTP.InitCallback} in triples
    end

    test "GenServer with empty use options" do
      genserver_info = build_test_genserver(use_options: [])
      context = build_test_context()
      module_iri = build_test_module_iri()

      {genserver_iri, triples} =
        GenServerBuilder.build_genserver(genserver_info, module_iri, context)

      # Verify implementation
      assert {genserver_iri, RDF.type(), OTP.GenServerImplementation} in triples
    end
  end
end
