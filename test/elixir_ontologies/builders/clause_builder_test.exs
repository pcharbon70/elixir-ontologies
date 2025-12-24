defmodule ElixirOntologies.Builders.ClauseBuilderTest do
  use ExUnit.Case, async: true
  import RDF.Sigils

  alias ElixirOntologies.Builders.{ClauseBuilder, Context}
  alias ElixirOntologies.Extractors.Clause
  alias ElixirOntologies.NS.{Structure, Core}

  doctest ClauseBuilder

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp build_test_clause(opts \\ []) do
    %Clause{
      name: Keyword.get(opts, :name, :test_function),
      arity: Keyword.get(opts, :arity, 1),
      visibility: Keyword.get(opts, :visibility, :public),
      order: Keyword.get(opts, :order, 1),
      head: Keyword.get(opts, :head, %{parameters: [{:x, [], nil}], guard: nil}),
      body: Keyword.get(opts, :body, quote(do: :ok)),
      location: Keyword.get(opts, :location, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp build_test_context do
    Context.new(base_iri: "https://example.org/code#")
  end

  # ===========================================================================
  # 1. Basic Clause Building
  # ===========================================================================

  describe "build_clause/3 - basic clause" do
    test "builds simple clause with no parameters" do
      clause_info = build_test_clause(arity: 0, head: %{parameters: [], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/0>
      context = build_test_context()

      {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify clause IRI (0-indexed)
      assert to_string(clause_iri) == "https://example.org/code#MyApp/test_function/0/clause/0"

      # Verify type triple
      assert {clause_iri, RDF.type(), Structure.FunctionClause} in triples

      # Verify clauseOrder (1-indexed)
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == clause_iri ->
                 pred == Structure.clauseOrder() and RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)

      # Verify hasClause from function
      assert {function_iri, Structure.hasClause(), clause_iri} in triples
    end

    test "builds clause with single parameter" do
      clause_info = build_test_clause(arity: 1, head: %{parameters: [{:x, [], nil}], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify parameter IRI exists
      param_iri = ~I<https://example.org/code#MyApp/test_function/1/clause/0/param/0>

      assert Enum.any?(triples, fn
               {s, pred, _} when s == param_iri -> pred == RDF.type()
               _ -> false
             end)

      # Verify parameter name
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == param_iri ->
                 pred == Structure.parameterName() and RDF.Literal.value(obj) == "x"

               _ ->
                 false
             end)
    end

    test "builds clause with multiple parameters" do
      clause_info =
        build_test_clause(
          arity: 3,
          head: %{parameters: [{:x, [], nil}, {:y, [], nil}, {:z, [], nil}], guard: nil}
        )

      function_iri = ~I<https://example.org/code#MyApp/test_function/3>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify all three parameters exist
      param_iri_0 = ~I<https://example.org/code#MyApp/test_function/3/clause/0/param/0>
      param_iri_1 = ~I<https://example.org/code#MyApp/test_function/3/clause/0/param/1>
      param_iri_2 = ~I<https://example.org/code#MyApp/test_function/3/clause/0/param/2>

      assert Enum.any?(triples, fn {s, p, _} -> s == param_iri_0 and p == RDF.type() end)
      assert Enum.any?(triples, fn {s, p, _} -> s == param_iri_1 and p == RDF.type() end)
      assert Enum.any?(triples, fn {s, p, _} -> s == param_iri_2 and p == RDF.type() end)
    end

    test "preserves clause ordering with clauseOrder property" do
      # Test three different clause orders
      for order <- [1, 2, 3] do
        clause_info = build_test_clause(order: order)
        function_iri = ~I<https://example.org/code#MyApp/test_function/1>
        context = build_test_context()

        {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

        # Verify IRI uses 0-indexed
        expected_iri = "https://example.org/code#MyApp/test_function/1/clause/#{order - 1}"
        assert to_string(clause_iri) == expected_iri

        # Verify clauseOrder uses 1-indexed
        assert Enum.any?(triples, fn
                 {s, pred, obj} when s == clause_iri ->
                   pred == Structure.clauseOrder() and RDF.Literal.value(obj) == order

                 _ ->
                   false
               end)
      end
    end
  end

  # ===========================================================================
  # 2. Parameter Types
  # ===========================================================================

  describe "build_clause/3 - parameter types" do
    test "simple parameters generate core:Parameter class" do
      clause_info = build_test_clause(head: %{parameters: [{:id, [], nil}], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      param_iri = ~I<https://example.org/code#MyApp/test_function/1/clause/0/param/0>
      assert {param_iri, RDF.type(), Structure.Parameter} in triples
    end

    test "default parameters generate struct:DefaultParameter class" do
      # Default parameter AST: {:\\, [], [{:timeout, [], nil}, 5000]}
      default_param = {:\\, [], [{:timeout, [], nil}, 5000]}

      clause_info =
        build_test_clause(arity: 1, head: %{parameters: [default_param], guard: nil})

      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      param_iri = ~I<https://example.org/code#MyApp/test_function/1/clause/0/param/0>
      assert {param_iri, RDF.type(), Structure.DefaultParameter} in triples
    end

    test "pattern parameters generate struct:PatternParameter class" do
      # Pattern parameter (map): %{key: value}
      pattern_param = {:%{}, [], [key: {:value, [], nil}]}

      clause_info =
        build_test_clause(arity: 1, head: %{parameters: [pattern_param], guard: nil})

      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      param_iri = ~I<https://example.org/code#MyApp/test_function/1/clause/0/param/0>
      assert {param_iri, RDF.type(), Structure.PatternParameter} in triples
    end

    test "pin parameters generate struct:PatternParameter class" do
      # Pin parameter: ^existing_var
      pin_param = {:^, [], [{:existing_var, [], nil}]}

      clause_info =
        build_test_clause(arity: 1, head: %{parameters: [pin_param], guard: nil})

      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      param_iri = ~I<https://example.org/code#MyApp/test_function/1/clause/0/param/0>
      assert {param_iri, RDF.type(), Structure.PatternParameter} in triples
    end

    test "mixed parameter types in one clause" do
      # Mix of simple, default, and pattern parameters
      params = [
        {:id, [], nil},
        {:\\, [], [{:timeout, [], nil}, 5000]},
        {:%{}, [], [key: {:value, [], nil}]}
      ]

      clause_info = build_test_clause(arity: 3, head: %{parameters: params, guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/3>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify each parameter has correct type
      param_iri_0 = ~I<https://example.org/code#MyApp/test_function/3/clause/0/param/0>
      param_iri_1 = ~I<https://example.org/code#MyApp/test_function/3/clause/0/param/1>
      param_iri_2 = ~I<https://example.org/code#MyApp/test_function/3/clause/0/param/2>

      assert {param_iri_0, RDF.type(), Structure.Parameter} in triples
      assert {param_iri_1, RDF.type(), Structure.DefaultParameter} in triples
      assert {param_iri_2, RDF.type(), Structure.PatternParameter} in triples
    end
  end

  # ===========================================================================
  # 3. RDF List Structure
  # ===========================================================================

  describe "build_clause/3 - RDF list structure" do
    test "empty parameter list generates rdf:nil" do
      clause_info = build_test_clause(arity: 0, head: %{parameters: [], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/0>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Find the hasParameters triple
      has_params_triple =
        Enum.find(triples, fn
          {_s, pred, _o} -> pred == Structure.hasParameters()
          _ -> false
        end)

      assert has_params_triple != nil
      {_head, _pred, list_head} = has_params_triple

      # Verify it points to rdf:nil
      assert list_head == RDF.nil()
    end

    test "single parameter list generates proper RDF list structure" do
      clause_info = build_test_clause(arity: 1, head: %{parameters: [{:x, [], nil}], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Find the hasParameters triple
      has_params_triple =
        Enum.find(triples, fn
          {_s, pred, _o} -> pred == Structure.hasParameters()
          _ -> false
        end)

      assert has_params_triple != nil
      {_head, _pred, list_head} = has_params_triple

      # Verify list_head is a blank node
      assert match?(%RDF.BlankNode{}, list_head)

      # Verify rdf:first triple exists
      param_iri = ~I<https://example.org/code#MyApp/test_function/1/clause/0/param/0>

      assert Enum.any?(triples, fn
               {s, pred, obj} when s == list_head ->
                 pred == RDF.first() and obj == param_iri

               _ ->
                 false
             end)

      # Verify rdf:rest points to rdf:nil
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == list_head ->
                 pred == RDF.rest() and obj == RDF.nil()

               _ ->
                 false
             end)
    end

    test "multiple parameter list generates chained RDF list" do
      params = [{:x, [], nil}, {:y, [], nil}]
      clause_info = build_test_clause(arity: 2, head: %{parameters: params, guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/2>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Find the hasParameters triple
      has_params_triple =
        Enum.find(triples, fn
          {_s, pred, _o} -> pred == Structure.hasParameters()
          _ -> false
        end)

      assert has_params_triple != nil
      {_head, _pred, list_head} = has_params_triple

      # Verify first node
      param_iri_0 = ~I<https://example.org/code#MyApp/test_function/2/clause/0/param/0>

      assert Enum.any?(triples, fn
               {s, pred, obj} when s == list_head ->
                 pred == RDF.first() and obj == param_iri_0

               _ ->
                 false
             end)

      # Find the rest node
      rest_triple =
        Enum.find(triples, fn
          {s, pred, _obj} when s == list_head -> pred == RDF.rest()
          _ -> false
        end)

      assert rest_triple != nil
      {_s, _pred, rest_node} = rest_triple

      # Verify second node
      param_iri_1 = ~I<https://example.org/code#MyApp/test_function/2/clause/0/param/1>

      assert Enum.any?(triples, fn
               {s, pred, obj} when s == rest_node ->
                 pred == RDF.first() and obj == param_iri_1

               _ ->
                 false
             end)

      # Verify final rest points to rdf:nil
      assert Enum.any?(triples, fn
               {s, pred, obj} when s == rest_node ->
                 pred == RDF.rest() and obj == RDF.nil()

               _ ->
                 false
             end)
    end

    test "verifies rdf:first/rdf:rest/rdf:nil structure correctness" do
      params = [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}]
      clause_info = build_test_clause(arity: 3, head: %{parameters: params, guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/3>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Count rdf:first triples (should be 3, one per parameter)
      first_count =
        Enum.count(triples, fn
          {_s, pred, _o} -> pred == RDF.first()
          _ -> false
        end)

      assert first_count == 3

      # Count rdf:rest triples (should be 3, one per node)
      rest_count =
        Enum.count(triples, fn
          {_s, pred, _o} -> pred == RDF.rest()
          _ -> false
        end)

      assert rest_count == 3

      # Verify exactly one rest points to rdf:nil (final node)
      nil_count =
        Enum.count(triples, fn
          {_s, pred, obj} -> pred == RDF.rest() and obj == RDF.nil()
          _ -> false
        end)

      assert nil_count == 1
    end
  end

  # ===========================================================================
  # 4. Parameter Properties
  # ===========================================================================

  describe "build_clause/3 - parameter properties" do
    test "generates parameterName for named parameters" do
      clause_info =
        build_test_clause(head: %{parameters: [{:user_id, [], nil}], guard: nil})

      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      param_iri = ~I<https://example.org/code#MyApp/test_function/1/clause/0/param/0>

      assert Enum.any?(triples, fn
               {s, pred, obj} when s == param_iri ->
                 pred == Structure.parameterName() and RDF.Literal.value(obj) == "user_id"

               _ ->
                 false
             end)
    end

    test "generates parameterPosition with 1-indexed values" do
      params = [{:first, [], nil}, {:second, [], nil}, {:third, [], nil}]
      clause_info = build_test_clause(arity: 3, head: %{parameters: params, guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/3>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify positions are 1, 2, 3 (not 0, 1, 2)
      param_iri_0 = ~I<https://example.org/code#MyApp/test_function/3/clause/0/param/0>
      param_iri_1 = ~I<https://example.org/code#MyApp/test_function/3/clause/0/param/1>
      param_iri_2 = ~I<https://example.org/code#MyApp/test_function/3/clause/0/param/2>

      assert Enum.any?(triples, fn
               {s, pred, obj} when s == param_iri_0 ->
                 pred == Structure.parameterPosition() and RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)

      assert Enum.any?(triples, fn
               {s, pred, obj} when s == param_iri_1 ->
                 pred == Structure.parameterPosition() and RDF.Literal.value(obj) == 2

               _ ->
                 false
             end)

      assert Enum.any?(triples, fn
               {s, pred, obj} when s == param_iri_2 ->
                 pred == Structure.parameterPosition() and RDF.Literal.value(obj) == 3

               _ ->
                 false
             end)
    end

    test "generates correct parameter IRI format" do
      clause_info = build_test_clause(head: %{parameters: [{:x, [], nil}], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Expected pattern: {clause_iri}/param/0
      expected_param_iri = "#{clause_iri}/param/0"
      param_iri = RDF.iri(expected_param_iri)

      assert Enum.any?(triples, fn
               {s, p, _} -> s == param_iri and p == RDF.type()
             end)
    end

    test "maintains position consistency across parameters" do
      params = [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}, {:d, [], nil}]
      clause_info = build_test_clause(arity: 4, head: %{parameters: params, guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/4>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Extract all parameter positions
      positions =
        triples
        |> Enum.filter(fn
          {_s, pred, _o} -> pred == Structure.parameterPosition()
          _ -> false
        end)
        |> Enum.map(fn {_s, _pred, obj} -> RDF.Literal.value(obj) end)
        |> Enum.sort()

      # Verify positions are consecutive: [1, 2, 3, 4]
      assert positions == [1, 2, 3, 4]
    end
  end

  # ===========================================================================
  # 5. FunctionHead Structure
  # ===========================================================================

  describe "build_clause/3 - FunctionHead structure" do
    test "creates blank node for FunctionHead" do
      clause_info = build_test_clause(head: %{parameters: [{:x, [], nil}], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Find the hasHead triple
      has_head_triple =
        Enum.find(triples, fn
          {_s, pred, _o} -> pred == Structure.hasHead()
          _ -> false
        end)

      assert has_head_triple != nil
      {_clause, _pred, head_bnode} = has_head_triple

      # Verify head is a blank node
      assert match?(%RDF.BlankNode{}, head_bnode)

      # Verify blank node has type FunctionHead
      assert {head_bnode, RDF.type(), Structure.FunctionHead} in triples
    end

    test "links clause to head via hasHead property" do
      clause_info = build_test_clause(head: %{parameters: [], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/0>
      context = build_test_context()

      {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Find hasHead triple
      assert Enum.any?(triples, fn
               {s, pred, _o} when s == clause_iri -> pred == Structure.hasHead()
               _ -> false
             end)
    end

    test "head has hasParameters property with list" do
      clause_info = build_test_clause(head: %{parameters: [{:x, [], nil}], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Find the hasHead triple to get head blank node
      {_clause, _pred, head_bnode} =
        Enum.find(triples, fn
          {_s, pred, _o} -> pred == Structure.hasHead()
          _ -> false
        end)

      # Verify head has hasParameters property
      assert Enum.any?(triples, fn
               {s, pred, _o} when s == head_bnode -> pred == Structure.hasParameters()
               _ -> false
             end)
    end

    test "head without guard has no hasGuard property" do
      clause_info = build_test_clause(head: %{parameters: [{:x, [], nil}], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify no hasGuard property exists
      refute Enum.any?(triples, fn
               {_s, pred, _o} -> pred == Core.hasGuard()
             end)
    end
  end

  # ===========================================================================
  # 6. Guard Handling
  # ===========================================================================

  describe "build_clause/3 - guard handling" do
    test "clause with guard generates hasGuard property" do
      # Guard: when is_atom(x)
      guard_ast = {:is_atom, [], [{:x, [], nil}]}
      clause_info = build_test_clause(head: %{parameters: [{:x, [], nil}], guard: guard_ast})
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Find the hasHead triple to get head blank node
      {_clause, _pred, head_bnode} =
        Enum.find(triples, fn
          {_s, pred, _o} -> pred == Structure.hasHead()
          _ -> false
        end)

      # Verify head has hasGuard property
      assert Enum.any?(triples, fn
               {s, pred, _o} when s == head_bnode -> pred == Core.hasGuard()
               _ -> false
             end)
    end

    test "clause without guard has no guard blank node" do
      clause_info = build_test_clause(head: %{parameters: [{:x, [], nil}], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify no GuardExpression type exists
      refute Enum.any?(triples, fn
               {_s, _pred, obj} -> obj == Core.GuardClause
             end)
    end

    test "guard blank node has correct type" do
      guard_ast = {:is_integer, [], [{:n, [], nil}]}
      clause_info = build_test_clause(head: %{parameters: [{:n, [], nil}], guard: guard_ast})
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Find hasGuard triple to get guard blank node
      guard_triple =
        Enum.find(triples, fn
          {_s, pred, _o} -> pred == Core.hasGuard()
          _ -> false
        end)

      assert guard_triple != nil
      {_head, _pred, guard_bnode} = guard_triple

      # Verify guard has type GuardExpression
      assert {guard_bnode, RDF.type(), Core.GuardClause} in triples
    end
  end

  # ===========================================================================
  # 7. FunctionBody Structure
  # ===========================================================================

  describe "build_clause/3 - FunctionBody structure" do
    test "creates blank node for FunctionBody" do
      clause_info = build_test_clause(body: quote(do: :ok))
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Find the hasBody triple
      has_body_triple =
        Enum.find(triples, fn
          {_s, pred, _o} -> pred == Structure.hasBody()
          _ -> false
        end)

      assert has_body_triple != nil
      {_clause, _pred, body_bnode} = has_body_triple

      # Verify body is a blank node
      assert match?(%RDF.BlankNode{}, body_bnode)

      # Verify blank node has type FunctionBody
      assert {body_bnode, RDF.type(), Structure.FunctionBody} in triples
    end

    test "links clause to body via hasBody property" do
      clause_info = build_test_clause(body: quote(do: :result))
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Find hasBody triple
      assert Enum.any?(triples, fn
               {s, pred, _o} when s == clause_iri -> pred == Structure.hasBody()
               _ -> false
             end)
    end

    test "handles bodyless clause (protocol definition)" do
      clause_info = build_test_clause(body: nil, metadata: %{bodyless: true})
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Bodyless clauses still generate body blank node
      # (the ontology doesn't distinguish bodyless clauses at RDF level)
      assert Enum.any?(triples, fn
               {_s, pred, _o} -> pred == Structure.hasBody()
             end)
    end
  end

  # ===========================================================================
  # 8. Clause-Function Relationship
  # ===========================================================================

  describe "build_clause/3 - clause-function relationship" do
    test "generates hasClause triple from function to clause" do
      clause_info = build_test_clause()
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify hasClause relationship
      assert {function_iri, Structure.hasClause(), clause_iri} in triples
    end

    test "clause IRI correctly includes function IRI as prefix" do
      clause_info = build_test_clause(order: 1)
      function_iri = ~I<https://example.org/code#SomeModule.SubModule/complex_function/5>
      context = build_test_context()

      {clause_iri, _triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify clause IRI structure
      clause_iri_string = to_string(clause_iri)
      function_iri_string = to_string(function_iri)

      assert String.starts_with?(clause_iri_string, function_iri_string)
      assert String.ends_with?(clause_iri_string, "/clause/0")
    end
  end

  # ===========================================================================
  # 9. IRI Generation
  # ===========================================================================

  describe "build_clause/3 - IRI generation" do
    test "clause IRI uses 0-indexed path" do
      # Test orders 1, 2, 3 map to clause/0, clause/1, clause/2
      test_cases = [
        {1, "/clause/0"},
        {2, "/clause/1"},
        {3, "/clause/2"}
      ]

      for {order, expected_suffix} <- test_cases do
        clause_info = build_test_clause(order: order)
        function_iri = ~I<https://example.org/code#MyApp/test_function/1>
        context = build_test_context()

        {clause_iri, _triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

        assert String.ends_with?(to_string(clause_iri), expected_suffix)
      end
    end

    test "parameter IRI uses 0-indexed path" do
      params = [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}]
      clause_info = build_test_clause(arity: 3, head: %{parameters: params, guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/3>
      context = build_test_context()

      {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify parameter paths: param/0, param/1, param/2
      expected_param_iris = [
        "#{clause_iri}/param/0",
        "#{clause_iri}/param/1",
        "#{clause_iri}/param/2"
      ]

      for expected_iri <- expected_param_iris do
        param_iri = RDF.iri(expected_iri)

        assert Enum.any?(triples, fn
                 {s, p, _} -> s == param_iri and p == RDF.type()
               end)
      end
    end

    test "multiple clauses of same function have different IRIs" do
      function_iri = ~I<https://example.org/code#MyApp/test_function/2>
      context = build_test_context()

      clause_info_1 = build_test_clause(order: 1)
      clause_info_2 = build_test_clause(order: 2)
      clause_info_3 = build_test_clause(order: 3)

      {clause_iri_1, _triples1} = ClauseBuilder.build_clause(clause_info_1, function_iri, context)
      {clause_iri_2, _triples2} = ClauseBuilder.build_clause(clause_info_2, function_iri, context)
      {clause_iri_3, _triples3} = ClauseBuilder.build_clause(clause_info_3, function_iri, context)

      # All IRIs should be different
      iris = [clause_iri_1, clause_iri_2, clause_iri_3]
      assert length(Enum.uniq(iris)) == 3

      # Verify paths
      assert String.ends_with?(to_string(clause_iri_1), "/clause/0")
      assert String.ends_with?(to_string(clause_iri_2), "/clause/1")
      assert String.ends_with?(to_string(clause_iri_3), "/clause/2")
    end
  end

  # ===========================================================================
  # 10. Triple Validation
  # ===========================================================================

  describe "build_clause/3 - triple validation" do
    test "verifies all expected triples present for complete clause" do
      params = [{:x, [], nil}, {:y, [], nil}]
      guard_ast = {:is_atom, [], [{:x, [], nil}]}

      clause_info =
        build_test_clause(
          arity: 2,
          order: 1,
          head: %{parameters: params, guard: guard_ast}
        )

      function_iri = ~I<https://example.org/code#MyApp/test_function/2>
      context = build_test_context()

      {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify clause type
      assert {clause_iri, RDF.type(), Structure.FunctionClause} in triples

      # Verify clauseOrder
      assert Enum.any?(triples, fn {s, p, _} ->
               s == clause_iri and p == Structure.clauseOrder()
             end)

      # Verify hasClause
      assert {function_iri, Structure.hasClause(), clause_iri} in triples

      # Verify hasHead
      assert Enum.any?(triples, fn {s, p, _} -> s == clause_iri and p == Structure.hasHead() end)

      # Verify hasBody
      assert Enum.any?(triples, fn {s, p, _} -> s == clause_iri and p == Structure.hasBody() end)

      # Verify FunctionHead type
      assert Enum.any?(triples, fn {_s, _p, o} -> o == Structure.FunctionHead end)

      # Verify FunctionBody type
      assert Enum.any?(triples, fn {_s, _p, o} -> o == Structure.FunctionBody end)

      # Verify parameters
      assert Enum.any?(triples, fn {_s, p, _} -> p == Structure.parameterName() end)
      assert Enum.any?(triples, fn {_s, p, _} -> p == Structure.parameterPosition() end)

      # Verify hasParameters
      assert Enum.any?(triples, fn {_s, p, _} -> p == Structure.hasParameters() end)

      # Verify guard
      assert Enum.any?(triples, fn {_s, p, _} -> p == Core.hasGuard() end)
      assert Enum.any?(triples, fn {_s, _p, o} -> o == Core.GuardClause end)
    end

    test "no duplicate triples generated" do
      params = [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}]
      clause_info = build_test_clause(arity: 3, head: %{parameters: params, guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/3>
      context = build_test_context()

      {_clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Verify uniqueness
      unique_triples = Enum.uniq(triples)
      assert length(triples) == length(unique_triples)
    end

    test "triple count scales with clause complexity" do
      function_iri = ~I<https://example.org/code#MyApp/test_function/3>
      context = build_test_context()

      # Simple clause: 0 parameters
      clause_simple = build_test_clause(arity: 0, head: %{parameters: [], guard: nil})
      {_iri1, triples1} = ClauseBuilder.build_clause(clause_simple, function_iri, context)

      # Medium clause: 3 parameters, no guard
      params = [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}]
      clause_medium = build_test_clause(arity: 3, head: %{parameters: params, guard: nil})

      {_iri2, triples2} =
        ClauseBuilder.build_clause(
          clause_medium,
          ~I<https://example.org/code#MyApp/test_function_2/3>,
          context
        )

      # Complex clause: 3 parameters, with guard
      guard_ast = {:is_atom, [], [{:a, [], nil}]}

      clause_complex =
        build_test_clause(arity: 3, head: %{parameters: params, guard: guard_ast})

      {_iri3, triples3} =
        ClauseBuilder.build_clause(
          clause_complex,
          ~I<https://example.org/code#MyApp/test_function_3/3>,
          context
        )

      # More complex clauses should have more triples
      assert length(triples2) > length(triples1)
      assert length(triples3) > length(triples2)
    end
  end

  # ===========================================================================
  # 11. Edge Cases
  # ===========================================================================

  describe "build_clause/3 - edge cases" do
    test "handles zero-arity function clause" do
      clause_info = build_test_clause(arity: 0, head: %{parameters: [], guard: nil})
      function_iri = ~I<https://example.org/code#MyApp/test_function/0>
      context = build_test_context()

      {clause_iri, triples} = ClauseBuilder.build_clause(clause_info, function_iri, context)

      # Should still generate clause structure
      assert {clause_iri, RDF.type(), Structure.FunctionClause} in triples
      assert {function_iri, Structure.hasClause(), clause_iri} in triples

      # Should have empty parameter list (rdf:nil)
      has_params_triple =
        Enum.find(triples, fn
          {_s, pred, _o} -> pred == Structure.hasParameters()
          _ -> false
        end)

      assert has_params_triple != nil
      {_head, _pred, list_head} = has_params_triple
      assert list_head == RDF.nil()
    end

    test "handles multi-clause function with different orders" do
      function_iri = ~I<https://example.org/code#MyApp/test_function/1>
      context = build_test_context()

      # Build three clauses
      clause_info_1 =
        build_test_clause(order: 1, head: %{parameters: [{:x, [], nil}], guard: nil})

      clause_info_2 =
        build_test_clause(order: 2, head: %{parameters: [{:y, [], nil}], guard: nil})

      clause_info_3 =
        build_test_clause(order: 3, head: %{parameters: [{:z, [], nil}], guard: nil})

      {clause_iri_1, triples1} = ClauseBuilder.build_clause(clause_info_1, function_iri, context)
      {clause_iri_2, triples2} = ClauseBuilder.build_clause(clause_info_2, function_iri, context)
      {clause_iri_3, triples3} = ClauseBuilder.build_clause(clause_info_3, function_iri, context)

      # Verify each clause has correct order property
      assert Enum.any?(triples1, fn
               {s, pred, obj} when s == clause_iri_1 ->
                 pred == Structure.clauseOrder() and RDF.Literal.value(obj) == 1

               _ ->
                 false
             end)

      assert Enum.any?(triples2, fn
               {s, pred, obj} when s == clause_iri_2 ->
                 pred == Structure.clauseOrder() and RDF.Literal.value(obj) == 2

               _ ->
                 false
             end)

      assert Enum.any?(triples3, fn
               {s, pred, obj} when s == clause_iri_3 ->
                 pred == Structure.clauseOrder() and RDF.Literal.value(obj) == 3

               _ ->
                 false
             end)

      # Verify IRIs are different
      assert clause_iri_1 != clause_iri_2
      assert clause_iri_2 != clause_iri_3
      assert clause_iri_1 != clause_iri_3
    end
  end
end
