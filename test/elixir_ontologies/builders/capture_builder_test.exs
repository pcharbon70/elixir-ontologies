defmodule ElixirOntologies.Builders.CaptureBuilderTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.{CaptureBuilder, Context}
  alias ElixirOntologies.Extractors.Capture
  alias ElixirOntologies.NS.{Structure, Core}

  doctest CaptureBuilder

  describe "build/3 for named local captures" do
    test "generates CapturedFunction type triple" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      assert {capture_iri, RDF.type(), Structure.CapturedFunction} in triples
    end

    test "generates arity triple" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 2]}]}
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      arity_triple =
        Enum.find(triples, fn
          {^capture_iri, pred, _} -> pred == Structure.arity()
          _ -> false
        end)

      assert arity_triple != nil
      {_, _, arity_literal} = arity_triple
      assert RDF.Literal.value(arity_literal) == 2
    end

    test "generates refersToFunction triple with module context" do
      ast = {:&, [], [{:/, [], [{:my_function, [], Elixir}, 1]}]}
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      function_iri = ~I<https://example.org/code#MyApp/my_function/1>

      assert {capture_iri, Core.refersToFunction(), function_iri} in triples
    end

    test "generates correct IRI pattern" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, _triples} = CaptureBuilder.build(capture, context, 0)

      assert to_string(capture_iri) == "https://example.org/code#MyApp/&/0"
    end

    test "uses index for unique IRIs" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri_0, _} = CaptureBuilder.build(capture, context, 0)
      {capture_iri_1, _} = CaptureBuilder.build(capture, context, 1)
      {capture_iri_5, _} = CaptureBuilder.build(capture, context, 5)

      assert to_string(capture_iri_0) == "https://example.org/code#MyApp/&/0"
      assert to_string(capture_iri_1) == "https://example.org/code#MyApp/&/1"
      assert to_string(capture_iri_5) == "https://example.org/code#MyApp/&/5"
    end
  end

  describe "build/3 for named remote captures" do
    test "generates CapturedFunction type triple" do
      ast = quote do: &String.upcase/1
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      assert {capture_iri, RDF.type(), Structure.CapturedFunction} in triples
    end

    test "generates refersToModule triple" do
      ast = quote do: &String.upcase/1
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      module_iri = ~I<https://example.org/code#String>

      assert {capture_iri, Core.refersToModule(), module_iri} in triples
    end

    test "generates refersToFunction triple" do
      ast = quote do: &String.upcase/1
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      function_iri = ~I<https://example.org/code#String/upcase/1>

      assert {capture_iri, Core.refersToFunction(), function_iri} in triples
    end

    test "handles Erlang module captures" do
      # &:erlang.element/2
      ast =
        {:&, [],
         [
           {:/, [],
            [
              {{:., [], [:erlang, :element]}, [], []},
              2
            ]}
         ]}

      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      # Should have module reference to erlang
      module_triple =
        Enum.find(triples, fn
          {^capture_iri, pred, _} -> pred == Core.refersToModule()
          _ -> false
        end)

      assert module_triple != nil
    end

    test "generates arity triple for remote captures" do
      ast = quote do: &Enum.map/2
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      arity_triple =
        Enum.find(triples, fn
          {^capture_iri, pred, _} -> pred == Structure.arity()
          _ -> false
        end)

      assert arity_triple != nil
      {_, _, arity_literal} = arity_triple
      assert RDF.Literal.value(arity_literal) == 2
    end
  end

  describe "build/3 for shorthand captures" do
    test "generates PartialApplication type triple" do
      ast = quote do: &(&1 + 1)
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      assert {capture_iri, RDF.type(), Structure.PartialApplication} in triples
    end

    test "derives arity from placeholders for single arg" do
      ast = quote do: &(&1 + 1)
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      arity_triple =
        Enum.find(triples, fn
          {^capture_iri, pred, _} -> pred == Structure.arity()
          _ -> false
        end)

      assert arity_triple != nil
      {_, _, arity_literal} = arity_triple
      assert RDF.Literal.value(arity_literal) == 1
    end

    test "derives arity from placeholders for multiple args" do
      ast = quote do: &(&1 + &2)
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      arity_triple =
        Enum.find(triples, fn
          {^capture_iri, pred, _} -> pred == Structure.arity()
          _ -> false
        end)

      assert arity_triple != nil
      {_, _, arity_literal} = arity_triple
      assert RDF.Literal.value(arity_literal) == 2
    end

    test "handles shorthand with remote call" do
      # &String.split(&1, ",")
      ast = quote do: &String.split(&1, ",")
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      # Should be PartialApplication (shorthand), not CapturedFunction
      assert {capture_iri, RDF.type(), Structure.PartialApplication} in triples
    end

    test "does not generate function reference for shorthand" do
      ast = quote do: &(&1 + 1)
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      function_ref_triple =
        Enum.find(triples, fn
          {^capture_iri, pred, _} -> pred == Core.refersToFunction()
          _ -> false
        end)

      assert function_ref_triple == nil
    end
  end

  describe "context handling" do
    test "uses module from metadata" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      {:ok, capture} = Capture.extract(ast)

      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{module: [:MyApp, :Server]}
        )

      {capture_iri, _triples} = CaptureBuilder.build(capture, context, 0)

      assert to_string(capture_iri) == "https://example.org/code#MyApp.Server/&/0"
    end

    test "uses file path when no module context" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      {:ok, capture} = Capture.extract(ast)

      context =
        Context.new(
          base_iri: "https://example.org/code#",
          file_path: "lib/my_app.ex"
        )

      {capture_iri, _triples} = CaptureBuilder.build(capture, context, 0)

      assert to_string(capture_iri) =~ "file/lib/my_app.ex/&/0"
    end
  end

  describe "triple counts" do
    test "named local capture generates 3 triples with module context" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {_capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      # type, arity, refersToFunction
      assert length(triples) == 3
    end

    test "named remote capture generates 4 triples" do
      ast = quote do: &String.upcase/1
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {_capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      # type, arity, refersToModule, refersToFunction
      assert length(triples) == 4
    end

    test "shorthand capture generates 2 triples" do
      ast = quote do: &(&1 + 1)
      {:ok, capture} = Capture.extract(ast)

      context = Context.new(base_iri: "https://example.org/code#", metadata: %{module: [:MyApp]})
      {_capture_iri, triples} = CaptureBuilder.build(capture, context, 0)

      # type, arity
      assert length(triples) == 2
    end
  end
end
