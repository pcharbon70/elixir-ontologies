defmodule ElixirOntologies.Builders.ProtocolBuilderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.{ProtocolBuilder, Context}
  alias ElixirOntologies.Extractors.Protocol
  alias ElixirOntologies.Extractors.Protocol.Implementation
  alias ElixirOntologies.NS.{Structure, Core}

  doctest ProtocolBuilder

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp build_test_protocol(opts \\ []) do
    %Protocol{
      name: Keyword.get(opts, :name, [:Stringable]),
      functions: Keyword.get(opts, :functions, []),
      fallback_to_any: Keyword.get(opts, :fallback_to_any, false),
      doc: Keyword.get(opts, :doc, nil),
      typedoc: Keyword.get(opts, :typedoc, nil),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp build_test_implementation(opts \\ []) do
    %Implementation{
      protocol: Keyword.get(opts, :protocol, [:Stringable]),
      for_type: Keyword.get(opts, :for_type, [:String]),
      functions: Keyword.get(opts, :functions, []),
      is_any: Keyword.get(opts, :is_any, false),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp build_test_context do
    Context.new(base_iri: "https://example.org/code#")
  end

  # ===========================================================================
  # 1. Basic Protocol Building
  # ===========================================================================

  describe "build_protocol/2 - basic protocol" do
    test "builds minimal protocol with no functions" do
      protocol_info = build_test_protocol()
      context = build_test_context()

      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify protocol IRI
      assert to_string(protocol_iri) == "https://example.org/code#Stringable"

      # Verify type triple
      assert {protocol_iri, RDF.type(), Structure.Protocol} in triples

      # Verify protocolName
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == protocol_iri ->
                 pred == Structure.protocolName() and RDF.Literal.value(obj) == "Stringable"

               _ ->
                 false
             end)

      # Verify fallbackToAny (default false)
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == protocol_iri ->
                 pred == Structure.fallbackToAny() and RDF.Literal.value(obj) == false

               _ ->
                 false
             end)
    end

    test "builds protocol with fallback_to_any true" do
      protocol_info = build_test_protocol(fallback_to_any: true)
      context = build_test_context()

      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify fallbackToAny is true
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == protocol_iri ->
                 pred == Structure.fallbackToAny() and RDF.Literal.value(obj) == true

               _ ->
                 false
             end)
    end

    test "builds protocol with documentation" do
      protocol_info = build_test_protocol(doc: "A protocol for stringable types")
      context = build_test_context()

      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify docstring
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == protocol_iri ->
                 pred == Structure.docstring() and
                   RDF.Literal.value(obj) == "A protocol for stringable types"

               _ ->
                 false
             end)
    end

    test "handles protocol with @doc false" do
      protocol_info = build_test_protocol(doc: false)
      context = build_test_context()

      {_protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify no docstring triple
      refute Enum.any?(triples, fn
               {_s, pred, _o} -> pred == Structure.docstring()
             end)
    end

    test "builds namespaced protocol (String.Chars)" do
      protocol_info = build_test_protocol(name: [:String, :Chars])
      context = build_test_context()

      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify IRI
      assert to_string(protocol_iri) == "https://example.org/code#String.Chars"

      # Verify protocolName
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == protocol_iri ->
                 pred == Structure.protocolName() and RDF.Literal.value(obj) == "String.Chars"

               _ ->
                 false
             end)
    end
  end

  # ===========================================================================
  # 2. Protocol Functions
  # ===========================================================================

  describe "build_protocol/2 - protocol functions" do
    test "builds protocol with single function" do
      functions = [
        %{
          name: :to_string,
          arity: 1,
          parameters: [:data],
          doc: nil,
          spec: nil,
          location: nil
        }
      ]

      protocol_info = build_test_protocol(functions: functions)
      context = build_test_context()

      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify protocol function IRI
      func_iri = ~I<https://example.org/code#Stringable/to_string/1>

      # Verify function type
      assert {func_iri, RDF.type(), Structure.ProtocolFunction} in triples

      # Verify function name
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == func_iri ->
                 pred == Structure.functionName() and RDF.Literal.value(obj) == "to_string"

               _ ->
                 false
             end)

      # Verify function arity
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == func_iri ->
                 pred == Structure.arity() and RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)

      # Verify definesProtocolFunction relationship
      assert {protocol_iri, Structure.definesProtocolFunction(), func_iri} in triples
    end

    test "builds protocol with multiple functions" do
      functions = [
        %{name: :count, arity: 1, parameters: [:enumerable], doc: nil, spec: nil, location: nil},
        %{name: :member?, arity: 2, parameters: [:enumerable, :element], doc: nil, spec: nil, location: nil},
        %{name: :reduce, arity: 3, parameters: [:enumerable, :acc, :fun], doc: nil, spec: nil, location: nil}
      ]

      protocol_info = build_test_protocol(name: [:Enumerable], functions: functions)
      context = build_test_context()

      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify all three functions exist
      func_iri_1 = ~I<https://example.org/code#Enumerable/count/1>
      func_iri_2 = ~I<https://example.org/code#Enumerable/member?/2>
      func_iri_3 = ~I<https://example.org/code#Enumerable/reduce/3>

      assert Enum.any?(triples, fn {s, p, _} -> s == func_iri_1 and p == RDF.type() end)
      assert Enum.any?(triples, fn {s, p, _} -> s == func_iri_2 and p == RDF.type() end)
      assert Enum.any?(triples, fn {s, p, _} -> s == func_iri_3 and p == RDF.type() end)

      # Verify all definesProtocolFunction relationships
      assert {protocol_iri, Structure.definesProtocolFunction(), func_iri_1} in triples
      assert {protocol_iri, Structure.definesProtocolFunction(), func_iri_2} in triples
      assert {protocol_iri, Structure.definesProtocolFunction(), func_iri_3} in triples
    end

    test "builds protocol function with documentation" do
      functions = [
        %{
          name: :to_string,
          arity: 1,
          parameters: [:data],
          doc: "Converts data to a string",
          spec: nil,
          location: nil
        }
      ]

      protocol_info = build_test_protocol(functions: functions)
      context = build_test_context()

      {_protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      func_iri = ~I<https://example.org/code#Stringable/to_string/1>

      # Verify function docstring
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == func_iri ->
                 pred == Structure.docstring() and
                   RDF.Literal.value(obj) == "Converts data to a string"

               _ ->
                 false
             end)
    end
  end

  # ===========================================================================
  # 3. Basic Implementation Building
  # ===========================================================================

  describe "build_implementation/2 - basic implementation" do
    test "builds minimal implementation" do
      impl_info = build_test_implementation()
      context = build_test_context()

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify implementation IRI pattern (Protocol.for.Type)
      assert to_string(impl_iri) == "https://example.org/code#Stringable.for.String"

      # Verify type triple
      assert {impl_iri, RDF.type(), Structure.ProtocolImplementation} in triples
    end

    test "builds implementsProtocol relationship" do
      impl_info = build_test_implementation()
      context = build_test_context()

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      protocol_iri = ~I<https://example.org/code#Stringable>

      # Verify implementsProtocol triple
      assert {impl_iri, Structure.implementsProtocol(), protocol_iri} in triples
    end

    test "builds forDataType relationship" do
      impl_info = build_test_implementation(for_type: [:Integer])
      context = build_test_context()

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      type_iri = ~I<https://example.org/code#Integer>

      # Verify forDataType triple
      assert {impl_iri, Structure.forDataType(), type_iri} in triples
    end

    test "handles Any implementation" do
      impl_info = build_test_implementation(for_type: :Any, is_any: true)
      context = build_test_context()

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify IRI pattern
      assert to_string(impl_iri) == "https://example.org/code#Stringable.for.Any"

      # Verify forDataType points to Any
      any_iri = ~I<https://example.org/code#Any>
      assert {impl_iri, Structure.forDataType(), any_iri} in triples
    end

    test "handles namespaced protocol implementation" do
      impl_info = build_test_implementation(
        protocol: [:String, :Chars],
        for_type: [:Integer]
      )

      context = build_test_context()

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify IRI pattern
      assert to_string(impl_iri) == "https://example.org/code#String.Chars.for.Integer"

      # Verify implementsProtocol
      protocol_iri = ~I<https://example.org/code#String.Chars>
      assert {impl_iri, Structure.implementsProtocol(), protocol_iri} in triples
    end
  end

  # ===========================================================================
  # 4. Implementation Functions
  # ===========================================================================

  describe "build_implementation/2 - implementation functions" do
    test "builds implementation with single function" do
      functions = [
        %{name: :to_string, arity: 1, has_body: true, location: nil}
      ]

      impl_info = build_test_implementation(functions: functions)
      context = build_test_context()

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify implementation function IRI
      impl_func_iri = RDF.iri("#{impl_iri}/to_string/1")

      # Verify function type
      assert {impl_func_iri, RDF.type(), Structure.Function} in triples

      # Verify containsFunction relationship
      assert {impl_iri, Structure.containsFunction(), impl_func_iri} in triples
    end

    test "builds implementation with multiple functions" do
      functions = [
        %{name: :count, arity: 1, has_body: true, location: nil},
        %{name: :member?, arity: 2, has_body: true, location: nil},
        %{name: :reduce, arity: 3, has_body: true, location: nil}
      ]

      impl_info = build_test_implementation(
        protocol: [:Enumerable],
        for_type: [:List],
        functions: functions
      )

      context = build_test_context()

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify all three functions
      func_iri_1 = RDF.iri("#{impl_iri}/count/1")
      func_iri_2 = RDF.iri("#{impl_iri}/member?/2")
      func_iri_3 = RDF.iri("#{impl_iri}/reduce/3")

      assert Enum.any?(triples, fn {s, p, _} -> s == func_iri_1 and p == RDF.type() end)
      assert Enum.any?(triples, fn {s, p, _} -> s == func_iri_2 and p == RDF.type() end)
      assert Enum.any?(triples, fn {s, p, _} -> s == func_iri_3 and p == RDF.type() end)

      # Verify containsFunction relationships
      assert {impl_iri, Structure.containsFunction(), func_iri_1} in triples
      assert {impl_iri, Structure.containsFunction(), func_iri_2} in triples
      assert {impl_iri, Structure.containsFunction(), func_iri_3} in triples
    end
  end

  # ===========================================================================
  # 5. Source Location
  # ===========================================================================

  describe "build_protocol/2 - source location" do
    test "adds location triple when location and file path available" do
      location = %{start_line: 10, end_line: 15, start_column: 1, end_column: 5}
      protocol_info = build_test_protocol(location: location)
      context = Context.new(base_iri: "https://example.org/code#", file_path: "lib/my_protocol.ex")

      {_protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify hasSourceLocation triple exists
      assert Enum.any?(triples, fn
               {_s, pred, _o} -> pred == Core.hasSourceLocation()
             end)
    end

    test "omits location triple when location is nil" do
      protocol_info = build_test_protocol(location: nil)
      context = Context.new(base_iri: "https://example.org/code#", file_path: "lib/my_protocol.ex")

      {_protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify no hasSourceLocation triple
      refute Enum.any?(triples, fn
               {_s, pred, _o} -> pred == Core.hasSourceLocation()
             end)
    end

    test "omits location triple when file path is nil" do
      location = %{start_line: 10, end_line: 15, start_column: 1, end_column: 5}
      protocol_info = build_test_protocol(location: location)
      context = Context.new(base_iri: "https://example.org/code#", file_path: nil)

      {_protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify no hasSourceLocation triple
      refute Enum.any?(triples, fn
               {_s, pred, _o} -> pred == Core.hasSourceLocation()
             end)
    end
  end

  describe "build_implementation/2 - source location" do
    test "adds location triple when location and file path available" do
      location = %{start_line: 20, end_line: 30, start_column: 1, end_column: 5}
      impl_info = build_test_implementation(location: location)
      context = Context.new(base_iri: "https://example.org/code#", file_path: "lib/my_impl.ex")

      {_impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify hasSourceLocation triple exists
      assert Enum.any?(triples, fn
               {_s, pred, _o} -> pred == Core.hasSourceLocation()
             end)
    end
  end

  # ===========================================================================
  # 6. IRI Generation
  # ===========================================================================

  describe "IRI generation" do
    test "protocol IRI uses module pattern" do
      protocol_info = build_test_protocol(name: [:MyApp, :MyProtocol])
      context = build_test_context()

      {protocol_iri, _triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      assert to_string(protocol_iri) == "https://example.org/code#MyApp.MyProtocol"
    end

    test "implementation IRI uses Protocol.for.Type pattern" do
      impl_info = build_test_implementation(
        protocol: [:MyApp, :MyProtocol],
        for_type: [:MyApp, :MyType]
      )

      context = build_test_context()

      {impl_iri, _triples} = ProtocolBuilder.build_implementation(impl_info, context)

      assert to_string(impl_iri) == "https://example.org/code#MyApp.MyProtocol.for.MyApp.MyType"
    end

    test "protocol function IRI uses Protocol/function/arity pattern" do
      functions = [
        %{name: :my_func, arity: 2, parameters: [:a, :b], doc: nil, spec: nil, location: nil}
      ]

      protocol_info = build_test_protocol(name: [:MyProtocol], functions: functions)
      context = build_test_context()

      {_protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      func_iri = ~I<https://example.org/code#MyProtocol/my_func/2>
      assert Enum.any?(triples, fn {s, p, _} -> s == func_iri and p == RDF.type() end)
    end

    test "implementation function IRI uses Implementation/function/arity pattern" do
      functions = [
        %{name: :my_func, arity: 2, has_body: true, location: nil}
      ]

      impl_info = build_test_implementation(
        protocol: [:MyProtocol],
        for_type: [:MyType],
        functions: functions
      )

      context = build_test_context()

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      impl_func_iri = RDF.iri("#{impl_iri}/my_func/2")
      assert Enum.any?(triples, fn {s, p, _} -> s == impl_func_iri and p == RDF.type() end)
    end
  end

  # ===========================================================================
  # 7. Triple Validation
  # ===========================================================================

  describe "triple validation" do
    test "protocol with functions generates expected triples" do
      functions = [
        %{name: :count, arity: 1, parameters: [:enum], doc: nil, spec: nil, location: nil}
      ]

      protocol_info = build_test_protocol(
        name: [:Enumerable],
        functions: functions,
        fallback_to_any: true,
        doc: "Enumeration protocol"
      )

      context = build_test_context()

      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify protocol type
      assert {protocol_iri, RDF.type(), Structure.Protocol} in triples

      # Verify protocolName
      assert Enum.any?(triples, fn {s, p, _} -> s == protocol_iri and p == Structure.protocolName() end)

      # Verify fallbackToAny
      assert Enum.any?(triples, fn {s, p, _} -> s == protocol_iri and p == Structure.fallbackToAny() end)

      # Verify docstring
      assert Enum.any?(triples, fn {s, p, _} -> s == protocol_iri and p == Structure.docstring() end)

      # Verify definesProtocolFunction
      assert Enum.any?(triples, fn {s, p, _} -> s == protocol_iri and p == Structure.definesProtocolFunction() end)

      # Verify ProtocolFunction type
      assert Enum.any?(triples, fn {_s, _p, o} -> o == Structure.ProtocolFunction end)
    end

    test "implementation generates expected triples" do
      functions = [
        %{name: :count, arity: 1, has_body: true, location: nil}
      ]

      impl_info = build_test_implementation(
        protocol: [:Enumerable],
        for_type: [:List],
        functions: functions
      )

      context = build_test_context()

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify implementation type
      assert {impl_iri, RDF.type(), Structure.ProtocolImplementation} in triples

      # Verify implementsProtocol
      assert Enum.any?(triples, fn {s, p, _} -> s == impl_iri and p == Structure.implementsProtocol() end)

      # Verify forDataType
      assert Enum.any?(triples, fn {s, p, _} -> s == impl_iri and p == Structure.forDataType() end)

      # Verify containsFunction
      assert Enum.any?(triples, fn {s, p, _} -> s == impl_iri and p == Structure.containsFunction() end)
    end

    test "no duplicate triples in protocol" do
      functions = [
        %{name: :func1, arity: 1, parameters: [:a], doc: nil, spec: nil, location: nil},
        %{name: :func2, arity: 1, parameters: [:b], doc: nil, spec: nil, location: nil}
      ]

      protocol_info = build_test_protocol(functions: functions)
      context = build_test_context()

      {_protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Verify uniqueness
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "no duplicate triples in implementation" do
      functions = [
        %{name: :func1, arity: 1, has_body: true, location: nil},
        %{name: :func2, arity: 1, has_body: true, location: nil}
      ]

      impl_info = build_test_implementation(functions: functions)
      context = build_test_context()

      {_impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify uniqueness
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end
  end

  # ===========================================================================
  # 8. Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "handles protocol with zero functions" do
      protocol_info = build_test_protocol(functions: [])
      context = build_test_context()

      {protocol_iri, triples} = ProtocolBuilder.build_protocol(protocol_info, context)

      # Should still generate protocol triples
      assert {protocol_iri, RDF.type(), Structure.Protocol} in triples

      # Should have no definesProtocolFunction triples
      refute Enum.any?(triples, fn
               {_s, pred, _o} -> pred == Structure.definesProtocolFunction()
             end)
    end

    test "handles implementation with zero functions" do
      impl_info = build_test_implementation(functions: [])
      context = build_test_context()

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Should still generate implementation triples
      assert {impl_iri, RDF.type(), Structure.ProtocolImplementation} in triples

      # Should have no containsFunction triples
      refute Enum.any?(triples, fn
               {s, pred, _o} when s == impl_iri -> pred == Structure.containsFunction()
               _ -> false
             end)
    end

    test "handles implementation for built-in atom type" do
      impl_info = build_test_implementation(for_type: :atom)
      context = build_test_context()

      {impl_iri, triples} = ProtocolBuilder.build_implementation(impl_info, context)

      # Verify IRI pattern
      assert to_string(impl_iri) == "https://example.org/code#Stringable.for.atom"

      # Verify forDataType
      type_iri = ~I<https://example.org/code#atom>
      assert {impl_iri, Structure.forDataType(), type_iri} in triples
    end
  end
end
