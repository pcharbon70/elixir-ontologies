defmodule ElixirOntologies.Builders.PatternContextIntegrationTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.ExpressionBuilder
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.NS.Core

  doctest ElixirOntologies.Builders.ExpressionBuilder

  @moduletag :pattern_context_integration

  # ===========================================================================
  # Fixtures
  # ===========================================================================

  defp full_mode_context do
    Context.new(
      base_iri: "https://example.org/code#",
      config: %{include_expressions: true},
      file_path: "lib/my_app/users.ex"
    )
    |> Context.with_expression_counter()
  end

  defp has_type?(triples, expected_type) do
    Enum.any?(triples, fn {_s, p, o} -> p == RDF.type() and o == expected_type end)
  end

  # ===========================================================================
  # Context Pattern Integration Tests
  # ===========================================================================

  describe "context pattern integration" do
    test "builds GenServer handle_call pattern" do
      context = full_mode_context()
      # def handle_call({:get_state, %{key: key}}, _from, state) do
      # The pattern portion is: {:get_state, %{key: key}}
      inner_map = {:%{}, [], [key: {:key, [], Elixir}]}
      pattern_ast = {{:get_state, [], Elixir}, inner_map}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(pattern_ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(pattern_ast, expr_iri, context)

      # Should have TuplePattern
      assert has_type?(pattern_triples, Core.TuplePattern)
      # Should have MapPattern
      assert has_type?(pattern_triples, Core.MapPattern)
    end

    test "builds case expression with tuple patterns" do
      context = full_mode_context()
      # case result do
      #   {:ok, value} -> :success
      #   {:error, reason} -> :failure
      # end
      pattern_ast = {{:ok, [], nil}, {:value, [], Elixir}}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(pattern_ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(pattern_ast, expr_iri, context)

      # Should have TuplePattern and LiteralPattern
      assert has_type?(pattern_triples, Core.TuplePattern)
      assert has_type?(pattern_triples, Core.LiteralPattern)
      # Should have VariablePattern for value
      assert has_type?(pattern_triples, Core.VariablePattern)
    end

    test "builds case expression with struct patterns" do
      context = full_mode_context()
      # case user do
      #   %User{name: name} -> {:ok, name}
      #   nil -> {:error, :not_found}
      # end
      pattern_ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [name: {:name, [], Elixir}]}]}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(pattern_ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(pattern_ast, expr_iri, context)

      # Should have StructPattern
      assert has_type?(pattern_triples, Core.StructPattern)
    end

    test "builds with expression pattern matching" do
      context = full_mode_context()
      # with {:ok, user} <- fetch_user(id),
      #      {:ok, posts} <- fetch_posts(user.id) do
      #   {:ok, user, posts}
      # end
      pattern_ast = {{:ok, [], Elixir}, {:user, [], Elixir}}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(pattern_ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(pattern_ast, expr_iri, context)

      # Should have TuplePattern
      assert has_type?(pattern_triples, Core.TuplePattern)
      # Should have VariablePattern
      assert has_type?(pattern_triples, Core.VariablePattern)
    end

    test "builds for comprehension pattern" do
      context = full_mode_context()
      # for {%User{id: id} = user} <- users, do: user.id
      # Pattern portion: {%User{id: id} = user}
      struct_map = {:%{}, [], [id: {:id, [], Elixir}]}
      struct_ast = {:%, [], [{:__aliases__, [], [:User]}, struct_map]}
      var_ast = {:user, [], Elixir}
      pattern_ast = {:=, [], [struct_ast, var_ast]}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(pattern_ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(pattern_ast, expr_iri, context)

      # Should have AsPattern and StructPattern
      assert has_type?(pattern_triples, Core.AsPattern)
      assert has_type?(pattern_triples, Core.StructPattern)
    end

    test "builds receive pattern" do
      context = full_mode_context()
      # receive do
      #   {:EXIT, pid, reason} -> :handle_exit
      #   msg -> :handle_message
      # end
      # 3-tuple AST: {:{}, [], [:EXIT, {:pid, [], Elixir}, {:reason, [], Elixir}]}
      pattern_ast = {:{}, [], [:EXIT, {:pid, [], Elixir}, {:reason, [], Elixir}]}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(pattern_ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(pattern_ast, expr_iri, context)

      # Should have TuplePattern
      assert has_type?(pattern_triples, Core.TuplePattern)
      # Should have VariablePattern for pid and reason
      variable_pattern_count =
        Enum.count(pattern_triples, fn {_s, p, o} ->
          p == RDF.type() and o == Core.VariablePattern
        end)

      assert variable_pattern_count >= 2
    end
  end

  # ===========================================================================
  # Real-World Pattern Tests
  # ===========================================================================

  describe "real-world pattern scenarios" do
    test "builds Ecto query result destructuring pattern" do
      context = full_mode_context()
      # [%User{id: id, name: name} | _] = users
      inner_map = {:%{}, [], [id: {:id, [], Elixir}, name: {:name, [], Elixir}]}
      struct_ast = {:%, [], [{:__aliases__, [], [:User]}, inner_map]}
      cons_ast = [{:|, [], [[struct_ast], {:_}]}]
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(cons_ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(cons_ast, expr_iri, context)

      # Should have ListPattern, StructPattern, and WildcardPattern
      assert has_type?(pattern_triples, Core.ListPattern)
      assert has_type?(pattern_triples, Core.StructPattern)
      assert has_type?(pattern_triples, Core.WildcardPattern)
    end

    test "builds Phoenix conn pattern" do
      context = full_mode_context()
      # %Plug.Conn{params: %{"user_id" => user_id}}
      inner_map = {:%{}, [], [[{"user_id"}, {:user_id, [], Elixir}]]}
      outer_map = {:%{}, [], [params: inner_map]}
      struct_ast = {:%, [], [{:__aliases__, [], [:Plug, :Conn]}, outer_map]}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(struct_ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(struct_ast, expr_iri, context)

      # Should have StructPattern
      assert has_type?(pattern_triples, Core.StructPattern)
      # Should have MapPattern for the params field
      assert has_type?(pattern_triples, Core.MapPattern)
    end

    test "builds Task result pattern" do
      context = full_mode_context()
      # case Task.await(task) do
      #   {:ok, result} -> :success
      #   {:error, _} -> :error
      # end
      pattern_ast = {{:ok, [], Elixir}, {:result, [], Elixir}}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(pattern_ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(pattern_ast, expr_iri, context)

      # Should have TuplePattern and VariablePattern
      assert has_type?(pattern_triples, Core.TuplePattern)
      assert has_type?(pattern_triples, Core.VariablePattern)
    end

    test "builds Agent state pattern" do
      context = full_mode_context()
      # def handle_call(:get_state, _from, %{count: count} = state) do
      # Pattern: %{count: count} = state
      map_pattern = {:%{}, [], [count: {:count, [], Elixir}]}
      var_ast = {:state, [], Elixir}
      pattern_ast = {:=, [], [map_pattern, var_ast]}
      {:ok, {expr_iri, _triples, _}} = ExpressionBuilder.build(pattern_ast, context, [])

      pattern_triples = ExpressionBuilder.build_pattern(pattern_ast, expr_iri, context)

      # Should have AsPattern and MapPattern
      assert has_type?(pattern_triples, Core.AsPattern)
      assert has_type?(pattern_triples, Core.MapPattern)
    end
  end
end
