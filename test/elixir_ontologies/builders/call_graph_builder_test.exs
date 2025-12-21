defmodule ElixirOntologies.Builders.CallGraphBuilderTest do
  @moduledoc """
  Tests for the CallGraphBuilder module.

  These tests verify RDF triple generation for function calls including
  local calls, remote calls, and dynamic calls.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{CallGraphBuilder, Context}
  alias ElixirOntologies.Extractors.Call.FunctionCall
  alias ElixirOntologies.NS.{Core, Structure}

  @base_iri "https://example.org/code#"

  # ===========================================================================
  # IRI Generation Tests
  # ===========================================================================

  describe "call_iri/3" do
    test "generates IRI with caller function and index" do
      iri = CallGraphBuilder.call_iri(@base_iri, "MyApp/foo/1", 0)
      assert to_string(iri) == "https://example.org/code#call/MyApp/foo/1/0"
    end

    test "increments index for multiple calls" do
      iri0 = CallGraphBuilder.call_iri(@base_iri, "MyApp/bar/2", 0)
      iri1 = CallGraphBuilder.call_iri(@base_iri, "MyApp/bar/2", 1)
      iri2 = CallGraphBuilder.call_iri(@base_iri, "MyApp/bar/2", 2)

      assert to_string(iri0) == "https://example.org/code#call/MyApp/bar/2/0"
      assert to_string(iri1) == "https://example.org/code#call/MyApp/bar/2/1"
      assert to_string(iri2) == "https://example.org/code#call/MyApp/bar/2/2"
    end

    test "handles RDF.IRI as base" do
      base = RDF.iri(@base_iri)
      iri = CallGraphBuilder.call_iri(base, "Test/func/0", 5)
      assert to_string(iri) == "https://example.org/code#call/Test/func/0/5"
    end
  end

  # ===========================================================================
  # Local Call Building Tests
  # ===========================================================================

  describe "build/3 with local calls" do
    test "generates type triple for local call" do
      call = %FunctionCall{type: :local, name: :helper, arity: 0, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/test/0", index: 0)

      type_triple = find_triple(triples, call_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.LocalCall
    end

    test "generates function name triple" do
      call = %FunctionCall{type: :local, name: :process_data, arity: 2, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/run/0", index: 0)

      name_triple = find_triple(triples, call_iri, Structure.functionName())
      assert name_triple != nil
      assert RDF.Literal.value(elem(name_triple, 2)) == "process_data"
    end

    test "generates arity triple" do
      call = %FunctionCall{type: :local, name: :foo, arity: 3, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/bar/0", index: 0)

      arity_triple = find_triple(triples, call_iri, Structure.arity())
      assert arity_triple != nil
      assert RDF.Literal.value(elem(arity_triple, 2)) == 3
    end

    test "generates belongsTo triple linking to caller function" do
      call = %FunctionCall{type: :local, name: :helper, arity: 0, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/main/0", index: 0)

      belongs_triple = find_triple(triples, call_iri, Structure.belongsTo())
      assert belongs_triple != nil
      assert to_string(elem(belongs_triple, 2)) == "https://example.org/code#MyApp/main/0"
    end

    test "does not generate belongsTo when caller_function is unknown" do
      call = %FunctionCall{type: :local, name: :helper, arity: 0, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context)

      belongs_triple = find_triple(triples, call_iri, Structure.belongsTo())
      assert belongs_triple == nil
    end
  end

  # ===========================================================================
  # Remote Call Building Tests
  # ===========================================================================

  describe "build/3 with remote calls" do
    test "generates type triple for remote call" do
      call = %FunctionCall{type: :remote, name: :upcase, arity: 1, module: [:String], metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/test/0", index: 0)

      type_triple = find_triple(triples, call_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.RemoteCall
    end

    test "generates module name triple for remote call" do
      call = %FunctionCall{type: :remote, name: :get, arity: 2, module: [:Map], metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/run/0", index: 0)

      module_triple = find_triple(triples, call_iri, Structure.moduleName())
      assert module_triple != nil
      assert RDF.Literal.value(elem(module_triple, 2)) == "Map"
    end

    test "generates module name for nested modules" do
      call = %FunctionCall{type: :remote, name: :fetch, arity: 2, module: [:MyApp, :Data, :Store], metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "Test/run/0", index: 0)

      module_triple = find_triple(triples, call_iri, Structure.moduleName())
      assert module_triple != nil
      assert RDF.Literal.value(elem(module_triple, 2)) == "MyApp.Data.Store"
    end

    test "generates callsFunction triple for remote call" do
      call = %FunctionCall{type: :remote, name: :upcase, arity: 1, module: [:String], metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/test/0", index: 0)

      calls_triple = find_triple(triples, call_iri, Structure.callsFunction())
      assert calls_triple != nil
      # Target should be String/upcase/1
      assert to_string(elem(calls_triple, 2)) == "https://example.org/code#String/upcase/1"
    end

    test "handles atom module for erlang calls" do
      call = %FunctionCall{type: :remote, name: :new, arity: 2, module: :ets, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/init/0", index: 0)

      module_triple = find_triple(triples, call_iri, Structure.moduleName())
      assert module_triple != nil
      assert RDF.Literal.value(elem(module_triple, 2)) == "ets"
    end
  end

  # ===========================================================================
  # Dynamic Call Building Tests
  # ===========================================================================

  describe "build/3 with dynamic calls" do
    test "generates type triple for dynamic call" do
      call = %FunctionCall{type: :dynamic, name: :apply, arity: 3, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/dispatch/1", index: 0)

      type_triple = find_triple(triples, call_iri, RDF.type())
      assert type_triple != nil
      # Dynamic calls currently use LocalCall as fallback
      assert elem(type_triple, 2) == Core.LocalCall
    end

    test "generates name and arity for dynamic call" do
      call = %FunctionCall{type: :dynamic, name: :callback, arity: 1, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/run/0", index: 0)

      name_triple = find_triple(triples, call_iri, Structure.functionName())
      arity_triple = find_triple(triples, call_iri, Structure.arity())

      assert RDF.Literal.value(elem(name_triple, 2)) == "callback"
      assert RDF.Literal.value(elem(arity_triple, 2)) == 1
    end
  end

  # ===========================================================================
  # Location Handling Tests
  # ===========================================================================

  describe "build/3 with location" do
    test "generates startLine triple when location has line" do
      location = %{line: 42}
      call = %FunctionCall{type: :local, name: :foo, arity: 0, location: location, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/test/0", index: 0)

      line_triple = find_triple(triples, call_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 42
    end

    test "does not generate location triple when location is nil" do
      call = %FunctionCall{type: :local, name: :foo, arity: 0, location: nil, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/test/0", index: 0)

      line_triple = find_triple(triples, call_iri, Core.startLine())
      assert line_triple == nil
    end
  end

  # ===========================================================================
  # Bulk Building Tests
  # ===========================================================================

  describe "build_all/3" do
    test "builds multiple calls with sequential indices" do
      calls = [
        %FunctionCall{type: :local, name: :foo, arity: 0, metadata: %{}},
        %FunctionCall{type: :local, name: :bar, arity: 1, metadata: %{}},
        %FunctionCall{type: :remote, name: :baz, arity: 2, module: [:Other], metadata: %{}}
      ]
      context = Context.new(base_iri: @base_iri)

      {iris, triples} = CallGraphBuilder.build_all(calls, context, caller_function: "MyApp/main/0")

      assert length(iris) == 3
      assert to_string(Enum.at(iris, 0)) == "https://example.org/code#call/MyApp/main/0/0"
      assert to_string(Enum.at(iris, 1)) == "https://example.org/code#call/MyApp/main/0/1"
      assert to_string(Enum.at(iris, 2)) == "https://example.org/code#call/MyApp/main/0/2"

      # Each call should generate at least type, name, arity triples
      assert length(triples) >= 9
    end

    test "returns empty lists for empty input" do
      context = Context.new(base_iri: @base_iri)

      {iris, triples} = CallGraphBuilder.build_all([], context, caller_function: "MyApp/test/0")

      assert iris == []
      assert triples == []
    end

    test "combines triples from all calls" do
      calls = [
        %FunctionCall{type: :local, name: :a, arity: 0, metadata: %{}},
        %FunctionCall{type: :local, name: :b, arity: 0, metadata: %{}}
      ]
      context = Context.new(base_iri: @base_iri)

      {_iris, triples} = CallGraphBuilder.build_all(calls, context, caller_function: "MyApp/test/0")

      # Find function names - should have both "a" and "b"
      name_values =
        triples
        |> Enum.filter(fn {_, p, _} -> p == Structure.functionName() end)
        |> Enum.map(fn {_, _, o} -> RDF.Literal.value(o) end)

      assert "a" in name_values
      assert "b" in name_values
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles call with no module for local call" do
      call = %FunctionCall{type: :local, name: :test, arity: 0, module: nil, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/run/0", index: 0)

      # Should not have module triple
      module_triple = find_triple(triples, call_iri, Structure.moduleName())
      assert module_triple == nil

      # Should still have type and name
      type_triple = find_triple(triples, call_iri, RDF.type())
      assert type_triple != nil
    end

    test "handles empty module list" do
      call = %FunctionCall{type: :remote, name: :test, arity: 0, module: [], metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/run/0", index: 0)

      # Should not have module triple for empty list
      module_triple = find_triple(triples, call_iri, Structure.moduleName())
      assert module_triple == nil
    end

    test "uses default index 0 when not specified" do
      call = %FunctionCall{type: :local, name: :foo, arity: 0, metadata: %{}}
      context = Context.new(base_iri: @base_iri)

      {call_iri, _triples} = CallGraphBuilder.build(call, context, caller_function: "MyApp/test/0")

      assert to_string(call_iri) == "https://example.org/code#call/MyApp/test/0/0"
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp find_triple(triples, subject, predicate) do
    Enum.find(triples, fn {s, p, _o} -> s == subject and p == predicate end)
  end
end
