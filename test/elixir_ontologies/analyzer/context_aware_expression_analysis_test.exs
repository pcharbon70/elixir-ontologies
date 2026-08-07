defmodule ElixirOntologies.Analyzer.ContextAwareExpressionAnalysisTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Analyzer.FileAnalyzer
  alias ElixirOntologies.Builders.Context
  alias ElixirOntologies.Config
  alias ElixirOntologies.NS.{Core, Structure}
  alias ElixirOntologies.Pipeline

  @source """
  defmodule ContextAwareExpressions do
    def classify(value) when is_integer(value), do: value + 1
    def classify(value), do: {:other, value}

    def enabled?(left, right), do: left and right
  end
  """

  @context [
    file_path: "lib/context_aware_expressions.ex",
    source_kind: :project,
    expression_identity_base: "example/revision/lib/context_aware_expressions.ex"
  ]

  test "legacy string analysis remains lightweight" do
    config = Config.new(include_expressions: true)

    assert {:ok, result} = FileAnalyzer.analyze_string(@source, config)
    assert result.file_path == "<string>"
    refute Enum.any?(RDF.Graph.subjects(result.graph.graph), &expression_subject?/1)
  end

  test "legacy analysis preserves the historical one-function-result-per-definition shape" do
    config = Config.new(include_expressions: true)

    assert {:ok, result} = FileAnalyzer.analyze_string(@source, config)
    [module] = result.modules
    assert length(Enum.filter(module.functions, &(&1.name == :classify))) == 2
  end

  test "trusted project context emits distinct reachable expression roots" do
    config = Config.new(include_expressions: true)

    assert {:ok, result} = FileAnalyzer.analyze_string(@source, config, @context)
    assert result.file_path == "lib/context_aware_expressions.ex"
    assert result.metadata.expression_complete

    [module] = result.modules
    assert length(module.functions) == 2

    classify = Enum.find(module.functions, &(&1.name == :classify))
    assert Enum.map(classify.clauses, & &1.order) == [1, 2]

    body_roots =
      result.graph.graph
      |> RDF.Graph.triples()
      |> Enum.filter(fn {_subject, predicate, _object} ->
        predicate == RDF.type()
      end)
      |> Enum.filter(fn {_subject, _predicate, object} ->
        object == Structure.FunctionBody or
          to_string(object) == "https://w3id.org/elixir-code/structure#FunctionBody"
      end)
      |> Enum.map(fn {subject, _predicate, _object} -> subject end)
      |> Enum.filter(&expression_subject?/1)

    assert length(body_roots) == 3
    assert length(Enum.uniq(body_roots)) == 3

    has_body_objects =
      result.graph.graph
      |> RDF.Graph.triples()
      |> Enum.filter(fn {_subject, predicate, _object} -> predicate == Structure.hasBody() end)
      |> Enum.map(fn {_subject, _predicate, object} -> object end)

    assert Enum.all?(body_roots, &(&1 in has_body_objects))
  end

  test "dependency context stays lightweight even when expressions are configured" do
    config = Config.new(include_expressions: true)

    dependency_context =
      @context
      |> Keyword.put(:file_path, "deps/example/lib/example.ex")
      |> Keyword.put(:source_kind, :dependency)
      |> Keyword.delete(:expression_identity_base)

    assert {:ok, result} =
             FileAnalyzer.analyze_string(@source, config, dependency_context)

    refute result.metadata.expression_complete
    refute Enum.any?(RDF.Graph.subjects(result.graph.graph), &expression_subject?/1)
  end

  test "expression resources are deterministic for one identity and disjoint for another" do
    config = Config.new(include_expressions: true)

    assert {:ok, first} = FileAnalyzer.analyze_string(@source, config, @context)
    assert {:ok, second} = FileAnalyzer.analyze_string(@source, config, @context)

    other_context =
      Keyword.put(
        @context,
        :expression_identity_base,
        "example/next-revision/lib/context_aware_expressions.ex"
      )

    assert {:ok, other} = FileAnalyzer.analyze_string(@source, config, other_context)

    assert graph_statements(first) == graph_statements(second)

    first_subjects = expression_subjects(first)
    assert first_subjects == expression_subjects(second)
    assert MapSet.disjoint?(first_subjects, expression_subjects(other))
  end

  test "invalid or incomplete trusted context is rejected before graph publication" do
    config = Config.new(include_expressions: true)

    assert {:error, :invalid_source_file_path} =
             FileAnalyzer.analyze_string(@source, config,
               file_path: "../secret.ex",
               source_kind: :project,
               expression_identity_base: "example/revision/secret.ex"
             )

    assert {:error, :invalid_expression_identity_base} =
             FileAnalyzer.analyze_string(@source, config,
               file_path: "lib/example.ex",
               source_kind: :project
             )

    assert {:error, :invalid_source_context} =
             FileAnalyzer.analyze_string(@source, config, @context ++ [unknown: true])

    assert {:error, :invalid_source_context} =
             FileAnalyzer.analyze_string(@source, config, [:not_a_keyword])
  end

  test "rooted control flow preserves semantic roles, locations, and parameter patterns" do
    source = """
    defmodule ControlFlowExpressions do
      def choose({left, right}) do
        if left do
          case right do
            :ok -> [answer: right]
            other ->
              map = %{answer: other}
              %{map | answer: right}
          end
        else
          for item <- [left, right], item != nil, do: item
        end
      end

      def evaluate(value) do
        cond do
          value == :ok -> :accepted
          true -> :rejected
        end
      end

      def chain(value) do
        with {:ok, result} <- value do
          result
        else
          _other -> :error
        end
      end

      def await_message do
        receive do
          {:ok, value} -> value
        after
          0 -> :timeout
        end
      end
    end
    """

    context =
      Keyword.merge(@context,
        file_path: "lib/control_flow_expressions.ex",
        expression_identity_base: "example/revision/lib/control_flow_expressions.ex"
      )

    assert {:ok, result} =
             FileAnalyzer.analyze_string(source, Config.new(include_expressions: true), context)

    assert {:ok, repeated} =
             FileAnalyzer.analyze_string(source, Config.new(include_expressions: true), context)

    assert graph_statements(result) == graph_statements(repeated)

    triples = RDF.Graph.triples(result.graph.graph)

    refute Enum.any?(triples, fn {subject, _predicate, object} ->
             is_struct(subject, RDF.BlankNode) or is_struct(object, RDF.BlankNode)
           end)

    for type <- [
          Core.IfExpression,
          Core.CondExpression,
          Core.CaseExpression,
          Core.WithExpression,
          Core.ReceiveExpression,
          Core.ForComprehension
        ] do
      typed_subjects = subjects_with_type(triples, type)
      assert typed_subjects != [], "missing rooted #{type}"
      assert Enum.all?(typed_subjects, &expression_subject?/1)
    end

    [if_iri] = subjects_with_type(triples, Core.IfExpression)
    assert object_for(triples, if_iri, Core.hasCondition())
    assert object_for(triples, if_iri, Core.hasThenBranch())
    assert object_for(triples, if_iri, Core.hasElseBranch())

    [with_iri] = subjects_with_type(triples, Core.WithExpression)
    assert object_for(triples, with_iri, Core.hasThenBranch())
    assert object_for(triples, with_iri, Core.hasElseBranch())

    location_iri = object_for(triples, if_iri, Core.hasSourceLocation())
    assert location_iri
    assert object_for(triples, location_iri, Core.startLine())
    assert object_for(triples, location_iri, Core.endLine())

    assert Enum.any?(triples, fn {subject, predicate, object} ->
             predicate == RDF.type() and rdf_type?(object, Core.TuplePattern) and
               String.contains?(to_string(subject), "/param/0")
           end)

    assert Enum.any?(triples, fn {subject, predicate, object} ->
             predicate == RDF.type() and rdf_type?(object, Core.AtomLiteral) and
               String.ends_with?(to_string(subject), "/entry/0/key")
           end)
  end

  @tag timeout: 30_000
  test "expression depth and resource bounds fail before returning a result" do
    config = Config.new(include_expressions: true)

    nested = Enum.reduce(1..110, "true", fn _index, acc -> "not (#{acc})" end)
    depth_source = "defmodule TooDeep do\n  def run, do: #{nested}\nend"

    assert {:error, {:expression_depth_limit_exceeded, %{limit: 100}}} =
             FileAnalyzer.analyze_string(depth_source, config,
               file_path: "lib/too_deep.ex",
               source_kind: :project,
               expression_identity_base: "example/revision/lib/too_deep.ex"
             )

    elements = String.duplicate("0,", 100_000) <> "0"
    resource_source = "defmodule TooLarge do\n  def run, do: [#{elements}]\nend"

    assert {:error, {:expression_resource_limit_exceeded, %{limit: 100_000}}} =
             FileAnalyzer.analyze_string(resource_source, config,
               file_path: "lib/too_large.ex",
               source_kind: :project,
               expression_identity_base: "example/revision/lib/too_large.ex"
             )
  end

  test "strict module construction returns an error instead of a partial graph" do
    assert {:ok, result} = FileAnalyzer.analyze_string(@source)
    [module] = result.modules

    context =
      Context.new(
        base_iri: "https://example.org/code#",
        file_path: "lib/context_aware_expressions.ex"
      )

    assert {:error, {:module_graph_failed, _reason}} =
             Pipeline.build_graph_for_modules_result([%{module | module_info: nil}], context)
  end

  test "strict contextual diagnostics never contain source literals" do
    sentinel = "SUPER_SECRET_VALUE"
    source = "defmodule InvalidConditional do\n  def run, do: if(\"#{sentinel}\")\nend"

    assert {:error, {:expression_analysis_failed, _reason}} =
             error =
             FileAnalyzer.analyze_string(source, Config.new(include_expressions: true),
               file_path: "lib/invalid_conditional.ex",
               source_kind: :project,
               expression_identity_base: "example/revision/lib/invalid_conditional.ex"
             )

    refute inspect(error) =~ sentinel
  end

  defp expression_subjects(result) do
    result.graph.graph
    |> RDF.Graph.subjects()
    |> Enum.filter(&expression_subject?/1)
    |> MapSet.new()
  end

  defp graph_statements(result) do
    result.graph.graph
    |> RDF.Graph.triples()
    |> MapSet.new()
  end

  defp expression_subject?(subject) do
    String.contains?(to_string(subject), "expr/source/")
  end

  defp subjects_with_type(triples, type) do
    for {subject, predicate, object} <- triples,
        predicate == RDF.type(),
        rdf_type?(object, type),
        do: subject
  end

  defp rdf_type?(object, type) do
    String.ends_with?(to_string(object), "##{type |> Module.split() |> List.last()}")
  end

  defp object_for(triples, subject, predicate) do
    Enum.find_value(triples, fn
      {^subject, ^predicate, object} -> object
      _triple -> nil
    end)
  end
end
