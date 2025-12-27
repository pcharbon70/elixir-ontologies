defmodule ElixirOntologies.Builders.BehaviourBuilderTest do
  use ExUnit.Case, async: true
  doctest ElixirOntologies.Builders.BehaviourBuilder

  alias ElixirOntologies.Builders.{BehaviourBuilder, Context}
  alias ElixirOntologies.Extractors.Behaviour
  alias ElixirOntologies.NS.Structure
  alias ElixirOntologies.NS.Core

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
    module_name = Keyword.get(opts, :module_name, "TestBehaviour")
    RDF.iri("#{base_iri}#{module_name}")
  end

  defp build_test_behaviour(opts \\ []) do
    %Behaviour{
      callbacks: Keyword.get(opts, :callbacks, []),
      macrocallbacks: Keyword.get(opts, :macrocallbacks, []),
      optional_callbacks: Keyword.get(opts, :optional_callbacks, []),
      doc: Keyword.get(opts, :doc, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp build_test_callback(opts \\ []) do
    %{
      name: Keyword.get(opts, :name, :test_callback),
      arity: Keyword.get(opts, :arity, 1),
      spec: Keyword.get(opts, :spec, nil),
      return_type: Keyword.get(opts, :return_type, nil),
      parameters: Keyword.get(opts, :parameters, []),
      is_optional: Keyword.get(opts, :is_optional, false),
      type: Keyword.get(opts, :type, :callback),
      doc: Keyword.get(opts, :doc, nil),
      location: Keyword.get(opts, :location, nil)
    }
  end

  defp build_test_implementation(opts \\ []) do
    %{
      behaviours: Keyword.get(opts, :behaviours, []),
      overridables: Keyword.get(opts, :overridables, []),
      functions: Keyword.get(opts, :functions, [])
    }
  end

  defp build_test_behaviour_impl(opts \\ []) do
    %{
      behaviour: Keyword.get(opts, :behaviour, :GenServer),
      behaviour_alias: Keyword.get(opts, :behaviour_alias, nil),
      location: Keyword.get(opts, :location, nil)
    }
  end

  # ===========================================================================
  # Basic Behaviour Building Tests
  # ===========================================================================

  describe "build_behaviour/2 - basic building" do
    test "builds minimal behaviour with no callbacks" do
      behaviour_info = build_test_behaviour()
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      # Verify IRI
      assert to_string(behaviour_iri) == "https://example.org/code#TestBehaviour"

      # Verify type triple
      assert {behaviour_iri, RDF.type(), Structure.Behaviour} in triples

      # Verify definesBehaviour triple (behaviour_iri is same as module_iri)
      assert {behaviour_iri, Structure.definesBehaviour(), behaviour_iri} in triples
    end

    test "builds behaviour with single required callback" do
      callback = build_test_callback(name: :init, arity: 1, is_optional: false)
      behaviour_info = build_test_behaviour(callbacks: [callback])
      context = build_test_context()

      module_iri = build_test_module_iri(module_name: "MyBehaviour")

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      # Verify callback IRI
      callback_iri = RDF.iri("#{behaviour_iri}/init/1")

      # Verify callback type
      assert {callback_iri, RDF.type(), Structure.Callback} in triples

      # Verify callback properties
      assert {callback_iri, Structure.functionName(), RDF.XSD.String.new("init")} in triples
      assert {callback_iri, Structure.arity(), RDF.XSD.NonNegativeInteger.new(1)} in triples

      # Verify definesCallback relationship
      assert {behaviour_iri, Structure.definesCallback(), callback_iri} in triples
    end

    test "builds behaviour with multiple callbacks" do
      callbacks = [
        build_test_callback(name: :init, arity: 1),
        build_test_callback(name: :handle_call, arity: 3),
        build_test_callback(name: :terminate, arity: 2)
      ]

      behaviour_info = build_test_behaviour(callbacks: callbacks)
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      # Verify all callbacks present
      init_iri = RDF.iri("#{behaviour_iri}/init/1")
      handle_call_iri = RDF.iri("#{behaviour_iri}/handle_call/3")
      terminate_iri = RDF.iri("#{behaviour_iri}/terminate/2")

      assert {init_iri, RDF.type(), Structure.Callback} in triples
      assert {handle_call_iri, RDF.type(), Structure.Callback} in triples
      assert {terminate_iri, RDF.type(), Structure.Callback} in triples
    end

    test "builds behaviour with documentation" do
      behaviour_info = build_test_behaviour(doc: "Test behaviour documentation")
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      # Verify docstring triple
      assert {behaviour_iri, Structure.docstring(),
              RDF.XSD.String.new("Test behaviour documentation")} in triples
    end

    test "builds behaviour without documentation" do
      behaviour_info = build_test_behaviour(doc: nil)
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      # Verify no docstring triple
      docstring_pred = Structure.docstring()

      refute Enum.any?(triples, fn
               {^behaviour_iri, ^docstring_pred, _} -> true
               _ -> false
             end)
    end
  end

  # ===========================================================================
  # Callback Type Tests
  # ===========================================================================

  describe "build_behaviour/2 - callback types" do
    test "builds required callback with Callback class" do
      callback = build_test_callback(name: :required_fn, arity: 0, is_optional: false)
      behaviour_info = build_test_behaviour(callbacks: [callback])
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      callback_iri = RDF.iri("#{behaviour_iri}/required_fn/0")
      assert {callback_iri, RDF.type(), Structure.Callback} in triples
    end

    test "builds optional callback with OptionalCallback class" do
      callback = build_test_callback(name: :optional_fn, arity: 1, is_optional: true)
      behaviour_info = build_test_behaviour(callbacks: [callback])
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      callback_iri = RDF.iri("#{behaviour_iri}/optional_fn/1")
      assert {callback_iri, RDF.type(), Structure.OptionalCallback} in triples
    end

    test "builds macrocallback with MacroCallback class" do
      macrocallback = build_test_callback(name: :macro_fn, arity: 2, type: :macrocallback)
      behaviour_info = build_test_behaviour(macrocallbacks: [macrocallback])
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      callback_iri = RDF.iri("#{behaviour_iri}/macro_fn/2")
      assert {callback_iri, RDF.type(), Structure.MacroCallback} in triples
    end

    test "builds behaviour with mixed callback types" do
      callbacks = [
        build_test_callback(name: :required, arity: 0, is_optional: false),
        build_test_callback(name: :optional, arity: 1, is_optional: true)
      ]

      macrocallbacks = [
        build_test_callback(name: :macro, arity: 2, type: :macrocallback)
      ]

      behaviour_info = build_test_behaviour(callbacks: callbacks, macrocallbacks: macrocallbacks)
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      required_iri = RDF.iri("#{behaviour_iri}/required/0")
      optional_iri = RDF.iri("#{behaviour_iri}/optional/1")
      macro_iri = RDF.iri("#{behaviour_iri}/macro/2")

      assert {required_iri, RDF.type(), Structure.Callback} in triples
      assert {optional_iri, RDF.type(), Structure.OptionalCallback} in triples
      assert {macro_iri, RDF.type(), Structure.MacroCallback} in triples
    end
  end

  # ===========================================================================
  # Callback Documentation and Location Tests
  # ===========================================================================

  describe "build_behaviour/2 - callback metadata" do
    test "builds callback with documentation" do
      callback =
        build_test_callback(
          name: :init,
          arity: 1,
          doc: "Initializes the process"
        )

      behaviour_info = build_test_behaviour(callbacks: [callback])
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      callback_iri = RDF.iri("#{behaviour_iri}/init/1")

      assert {callback_iri, Structure.docstring(), RDF.XSD.String.new("Initializes the process")} in triples
    end

    test "builds callback without documentation" do
      callback = build_test_callback(name: :init, arity: 1, doc: nil)
      behaviour_info = build_test_behaviour(callbacks: [callback])
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      callback_iri = RDF.iri("#{behaviour_iri}/init/1")
      docstring_pred = Structure.docstring()

      refute Enum.any?(triples, fn
               {^callback_iri, ^docstring_pred, _} -> true
               _ -> false
             end)
    end

    test "builds callback with source location" do
      location = %{start_line: 10, end_line: 12, start_column: 1, end_column: 50}
      callback = build_test_callback(name: :init, arity: 1, location: location)
      behaviour_info = build_test_behaviour(callbacks: [callback])
      context = build_test_context(file_path: "lib/my_behaviour.ex")

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      callback_iri = RDF.iri("#{behaviour_iri}/init/1")

      # Verify hasSourceLocation triple exists
      location_pred = Core.hasSourceLocation()

      assert Enum.any?(triples, fn
               {^callback_iri, ^location_pred, _} -> true
               _ -> false
             end)
    end

    test "builds callback without source location" do
      callback = build_test_callback(name: :init, arity: 1, location: nil)
      behaviour_info = build_test_behaviour(callbacks: [callback])
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      callback_iri = RDF.iri("#{behaviour_iri}/init/1")
      location_pred = Core.hasSourceLocation()

      refute Enum.any?(triples, fn
               {^callback_iri, ^location_pred, _} -> true
               _ -> false
             end)
    end
  end

  # ===========================================================================
  # Implementation Building Tests
  # ===========================================================================

  describe "build_implementation/2 - basic implementation" do
    test "builds minimal implementation with no behaviours" do
      impl_info = build_test_implementation()
      module_iri = RDF.iri("https://example.org/code#MyModule")
      context = build_test_context()

      {returned_iri, triples} =
        BehaviourBuilder.build_implementation(impl_info, module_iri, context)

      # Verify returned IRI is unchanged
      assert returned_iri == module_iri

      # Verify no triples generated for empty implementation
      assert triples == []
    end

    test "builds implementation with single behaviour" do
      behaviour_impl = build_test_behaviour_impl(behaviour: :GenServer)
      impl_info = build_test_implementation(behaviours: [behaviour_impl])
      module_iri = RDF.iri("https://example.org/code#MyServer")
      context = build_test_context()

      {_iri, triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)

      behaviour_iri = RDF.iri("https://example.org/code#GenServer")
      assert {module_iri, Structure.implementsBehaviour(), behaviour_iri} in triples
    end

    test "builds implementation with multiple behaviours" do
      behaviour_impls = [
        build_test_behaviour_impl(behaviour: :GenServer),
        build_test_behaviour_impl(behaviour: :Supervisor)
      ]

      impl_info = build_test_implementation(behaviours: behaviour_impls)
      module_iri = RDF.iri("https://example.org/code#MyModule")
      context = build_test_context()

      {_iri, triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)

      genserver_iri = RDF.iri("https://example.org/code#GenServer")
      supervisor_iri = RDF.iri("https://example.org/code#Supervisor")

      assert {module_iri, Structure.implementsBehaviour(), genserver_iri} in triples
      assert {module_iri, Structure.implementsBehaviour(), supervisor_iri} in triples
    end

    test "normalizes behaviour module atoms to strings" do
      # Test with Elixir. prefix
      behaviour_impl = build_test_behaviour_impl(behaviour: :"Elixir.GenServer")
      impl_info = build_test_implementation(behaviours: [behaviour_impl])
      module_iri = RDF.iri("https://example.org/code#MyServer")
      context = build_test_context()

      {_iri, triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)

      # Should strip Elixir. prefix
      behaviour_iri = RDF.iri("https://example.org/code#GenServer")
      assert {module_iri, Structure.implementsBehaviour(), behaviour_iri} in triples
    end
  end

  # ===========================================================================
  # Callback Implementation Linkage Tests
  # ===========================================================================

  describe "build_implementation/2 - callback linkage" do
    test "links GenServer init/1 implementation to callback" do
      behaviour_impl = build_test_behaviour_impl(behaviour: :GenServer)

      impl_info =
        build_test_implementation(
          behaviours: [behaviour_impl],
          functions: [{:init, 1}]
        )

      module_iri = RDF.iri("https://example.org/code#MyServer")
      context = build_test_context()

      {_iri, triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)

      function_iri = RDF.iri("https://example.org/code#MyServer/init/1")
      callback_iri = RDF.iri("https://example.org/code#GenServer/init/1")

      assert {function_iri, Structure.implementsCallback(), callback_iri} in triples
    end

    test "links multiple GenServer callback implementations" do
      behaviour_impl = build_test_behaviour_impl(behaviour: :GenServer)

      impl_info =
        build_test_implementation(
          behaviours: [behaviour_impl],
          functions: [{:init, 1}, {:handle_call, 3}, {:terminate, 2}]
        )

      module_iri = RDF.iri("https://example.org/code#MyServer")
      context = build_test_context()

      {_iri, triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)

      # Verify all three callbacks linked
      init_fn = RDF.iri("https://example.org/code#MyServer/init/1")
      init_cb = RDF.iri("https://example.org/code#GenServer/init/1")
      assert {init_fn, Structure.implementsCallback(), init_cb} in triples

      handle_call_fn = RDF.iri("https://example.org/code#MyServer/handle_call/3")
      handle_call_cb = RDF.iri("https://example.org/code#GenServer/handle_call/3")
      assert {handle_call_fn, Structure.implementsCallback(), handle_call_cb} in triples

      terminate_fn = RDF.iri("https://example.org/code#MyServer/terminate/2")
      terminate_cb = RDF.iri("https://example.org/code#GenServer/terminate/2")
      assert {terminate_fn, Structure.implementsCallback(), terminate_cb} in triples
    end

    test "does not link functions that are not callbacks" do
      behaviour_impl = build_test_behaviour_impl(behaviour: :GenServer)

      impl_info =
        build_test_implementation(
          behaviours: [behaviour_impl],
          functions: [{:init, 1}, {:custom_function, 2}]
        )

      module_iri = RDF.iri("https://example.org/code#MyServer")
      context = build_test_context()

      {_iri, triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)

      # init/1 should be linked
      init_fn = RDF.iri("https://example.org/code#MyServer/init/1")
      init_cb = RDF.iri("https://example.org/code#GenServer/init/1")
      assert {init_fn, Structure.implementsCallback(), init_cb} in triples

      # custom_function/2 should NOT be linked
      custom_fn = RDF.iri("https://example.org/code#MyServer/custom_function/2")
      callback_pred = Structure.implementsCallback()

      refute Enum.any?(triples, fn
               {^custom_fn, ^callback_pred, _} -> true
               _ -> false
             end)
    end

    test "links Supervisor init/1 implementation" do
      behaviour_impl = build_test_behaviour_impl(behaviour: :Supervisor)

      impl_info =
        build_test_implementation(
          behaviours: [behaviour_impl],
          functions: [{:init, 1}]
        )

      module_iri = RDF.iri("https://example.org/code#MySupervisor")
      context = build_test_context()

      {_iri, triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)

      function_iri = RDF.iri("https://example.org/code#MySupervisor/init/1")
      callback_iri = RDF.iri("https://example.org/code#Supervisor/init/1")

      assert {function_iri, Structure.implementsCallback(), callback_iri} in triples
    end

    test "does not link unknown behaviour callbacks" do
      behaviour_impl = build_test_behaviour_impl(behaviour: :CustomBehaviour)

      impl_info =
        build_test_implementation(
          behaviours: [behaviour_impl],
          functions: [{:custom_callback, 1}]
        )

      module_iri = RDF.iri("https://example.org/code#MyModule")
      context = build_test_context()

      {_iri, triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)

      # Should have implementsBehaviour triple
      custom_behaviour_iri = RDF.iri("https://example.org/code#CustomBehaviour")
      assert {module_iri, Structure.implementsBehaviour(), custom_behaviour_iri} in triples

      # But should NOT have implementsCallback triple (unknown behaviour)
      callback_pred = Structure.implementsCallback()

      refute Enum.any?(triples, fn
               {_, ^callback_pred, _} -> true
               _ -> false
             end)
    end
  end

  # ===========================================================================
  # IRI Generation Tests
  # ===========================================================================

  describe "IRI generation" do
    test "generates behaviour IRI using module pattern" do
      behaviour_info = build_test_behaviour()
      context = build_test_context()

      module_iri = build_test_module_iri(module_name: "MyApp.CustomBehaviour")

      {behaviour_iri, _triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      assert to_string(behaviour_iri) == "https://example.org/code#MyApp.CustomBehaviour"
    end

    test "generates callback IRI with behaviour/name/arity pattern" do
      callback = build_test_callback(name: :handle_event, arity: 3)
      behaviour_info = build_test_behaviour(callbacks: [callback])
      context = build_test_context()

      module_iri = build_test_module_iri(module_name: "EventHandler")

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      callback_iri = RDF.iri("#{behaviour_iri}/handle_event/3")
      assert {callback_iri, RDF.type(), Structure.Callback} in triples
    end

    test "generates different IRIs for callbacks with same name but different arity" do
      callbacks = [
        build_test_callback(name: :format_status, arity: 1),
        build_test_callback(name: :format_status, arity: 2)
      ]

      behaviour_info = build_test_behaviour(callbacks: callbacks)
      context = build_test_context()

      module_iri = build_test_module_iri(module_name: "GenServer")

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      callback_iri_1 = RDF.iri("#{behaviour_iri}/format_status/1")
      callback_iri_2 = RDF.iri("#{behaviour_iri}/format_status/2")

      assert {callback_iri_1, RDF.type(), Structure.Callback} in triples
      assert {callback_iri_2, RDF.type(), Structure.Callback} in triples
    end
  end

  # ===========================================================================
  # Triple Validation Tests
  # ===========================================================================

  describe "triple validation" do
    test "generates all expected triples for behaviour with callbacks" do
      callback = build_test_callback(name: :init, arity: 1, doc: "Initialize")

      behaviour_info =
        build_test_behaviour(
          callbacks: [callback],
          doc: "Behaviour documentation"
        )

      context = build_test_context()

      module_iri = build_test_module_iri(module_name: "MyBehaviour")

      {_behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      # Count expected triples:
      # 1. Behaviour type
      # 2. definesBehaviour
      # 3. Behaviour docstring
      # 4. Callback type
      # 5. Callback name
      # 6. Callback arity
      # 7. definesCallback
      # 8. Callback docstring
      # = 8 triples minimum

      assert length(triples) >= 8
    end

    test "does not generate duplicate triples" do
      callbacks = [
        build_test_callback(name: :init, arity: 1),
        # Duplicate (shouldn't happen but test deduplication)
        build_test_callback(name: :init, arity: 1)
      ]

      behaviour_info = build_test_behaviour(callbacks: callbacks)
      context = build_test_context()

      module_iri = build_test_module_iri()
      {_iri, triples} = BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      # Verify deduplication worked
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "generates all expected triples for implementation" do
      behaviour_impl = build_test_behaviour_impl(behaviour: :GenServer)

      impl_info =
        build_test_implementation(
          behaviours: [behaviour_impl],
          functions: [{:init, 1}, {:handle_call, 3}]
        )

      module_iri = RDF.iri("https://example.org/code#MyServer")
      context = build_test_context()

      {_iri, triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)

      # Count expected triples:
      # 1. implementsBehaviour
      # 2. init/1 implementsCallback
      # 3. handle_call/3 implementsCallback
      # = 3 triples minimum

      assert length(triples) >= 3
    end
  end

  # ===========================================================================
  # Edge Cases Tests
  # ===========================================================================

  describe "edge cases" do
    test "handles behaviour with only macrocallbacks (no regular callbacks)" do
      macrocallback = build_test_callback(name: :macro_fn, arity: 1, type: :macrocallback)

      behaviour_info =
        build_test_behaviour(
          callbacks: [],
          macrocallbacks: [macrocallback]
        )

      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      callback_iri = RDF.iri("#{behaviour_iri}/macro_fn/1")
      assert {callback_iri, RDF.type(), Structure.MacroCallback} in triples
    end

    test "handles behaviour with @doc false" do
      behaviour_info = build_test_behaviour(doc: false)
      context = build_test_context()

      module_iri = build_test_module_iri()

      {behaviour_iri, triples} =
        BehaviourBuilder.build_behaviour(behaviour_info, module_iri, context)

      # Should not have docstring triple
      docstring_pred = Structure.docstring()

      refute Enum.any?(triples, fn
               {^behaviour_iri, ^docstring_pred, _} -> true
               _ -> false
             end)
    end

    test "handles implementation with no matching callbacks" do
      behaviour_impl = build_test_behaviour_impl(behaviour: :GenServer)

      impl_info =
        build_test_implementation(
          behaviours: [behaviour_impl],
          functions: [{:custom_function, 1}, {:another_function, 2}]
        )

      module_iri = RDF.iri("https://example.org/code#MyModule")
      context = build_test_context()

      {_iri, triples} = BehaviourBuilder.build_implementation(impl_info, module_iri, context)

      # Should have implementsBehaviour but no implementsCallback
      genserver_iri = RDF.iri("https://example.org/code#GenServer")
      assert {module_iri, Structure.implementsBehaviour(), genserver_iri} in triples

      callback_pred = Structure.implementsCallback()

      refute Enum.any?(triples, fn
               {_, ^callback_pred, _} -> true
               _ -> false
             end)
    end
  end
end
