defmodule ElixirOntologies.Builders.QuoteBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{QuoteBuilder, Context}

  alias ElixirOntologies.Extractors.Quote.{
    QuotedExpression,
    QuoteOptions,
    UnquoteExpression,
    HygieneViolation
  }

  alias ElixirOntologies.NS.{Structure, Core}
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  doctest QuoteBuilder

  describe "build/3 basic quote" do
    test "builds basic quote block" do
      quote_expr = %QuotedExpression{
        body: {:+, [], [1, 2]},
        options: %QuoteOptions{},
        unquotes: [],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

      # Verify IRI format
      assert to_string(quote_iri) =~ "MyApp/quote/0"

      # Verify type triple
      assert {quote_iri, RDF.type(), Structure.QuotedExpression} in triples
    end

    test "builds quote with nested module" do
      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{},
        unquotes: [],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {quote_iri, _triples} =
        QuoteBuilder.build(quote_expr, context, module: [:MyApp, :Macros, :Helpers], index: 3)

      assert to_string(quote_iri) =~ "MyApp.Macros.Helpers/quote/3"
    end
  end

  describe "build/3 quote options" do
    test "builds quote with context option" do
      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{context: :match},
        unquotes: [],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

      # Verify quoteContext triple
      assert Enum.any?(triples, fn
               {^quote_iri, pred, obj} ->
                 pred == Structure.quoteContext() and
                   RDF.Literal.value(obj) == "match"

               _ ->
                 false
             end)
    end

    test "builds quote with bind_quoted option" do
      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{bind_quoted: [x: 1, y: 2]},
        unquotes: [],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

      # Verify hasBindQuoted triple
      assert Enum.any?(triples, fn
               {^quote_iri, pred, obj} ->
                 pred == Structure.hasBindQuoted() and
                   RDF.Literal.value(obj) == true

               _ ->
                 false
             end)
    end

    test "builds quote with location :keep option" do
      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{location: :keep},
        unquotes: [],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

      # Verify locationKeep triple
      assert Enum.any?(triples, fn
               {^quote_iri, pred, obj} ->
                 pred == Structure.locationKeep() and
                   RDF.Literal.value(obj) == true

               _ ->
                 false
             end)
    end

    test "builds quote with unquote disabled" do
      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{unquote: false},
        unquotes: [],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

      # Verify unquoteEnabled false triple
      assert Enum.any?(triples, fn
               {^quote_iri, pred, obj} ->
                 pred == Structure.unquoteEnabled() and
                   RDF.Literal.value(obj) == false

               _ ->
                 false
             end)
    end

    test "builds quote with generated option" do
      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{generated: true},
        unquotes: [],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

      # Verify isGenerated triple
      assert Enum.any?(triples, fn
               {^quote_iri, pred, obj} ->
                 pred == Structure.isGenerated() and
                   RDF.Literal.value(obj) == true

               _ ->
                 false
             end)
    end
  end

  describe "build/3 with unquotes" do
    test "builds quote with single unquote" do
      unquote_expr = %UnquoteExpression{
        kind: :unquote,
        value: {:x, [], nil},
        depth: 1,
        metadata: %{}
      }

      quote_expr = %QuotedExpression{
        body: {:+, [], [{:unquote, [], [{:x, [], nil}]}, 1]},
        options: %QuoteOptions{},
        unquotes: [unquote_expr],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

      # Verify containsUnquote triple exists
      assert Enum.any?(triples, fn
               {^quote_iri, pred, _obj} ->
                 pred == Structure.containsUnquote()

               _ ->
                 false
             end)

      # Verify unquote IRI and type
      rdf_type = RDF.type()
      unquote_type = Structure.UnquoteExpression

      unquote_triples =
        Enum.filter(triples, fn
          {s, ^rdf_type, ^unquote_type} -> to_string(s) =~ "unquote"
          _ -> false
        end)

      assert length(unquote_triples) == 1
    end

    test "builds quote with unquote_splicing" do
      unquote_expr = %UnquoteExpression{
        kind: :unquote_splicing,
        value: {:list, [], nil},
        depth: 1,
        metadata: %{}
      }

      quote_expr = %QuotedExpression{
        body: [{:unquote_splicing, [], [{:list, [], nil}]}, :end],
        options: %QuoteOptions{},
        unquotes: [unquote_expr],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {_quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

      # Verify UnquoteSplicingExpression type
      rdf_type = RDF.type()
      splicing_type = Structure.UnquoteSplicingExpression

      assert Enum.any?(triples, fn
               {_s, ^rdf_type, ^splicing_type} -> true
               _ -> false
             end)
    end

    test "builds quote with multiple unquotes" do
      unquote1 = %UnquoteExpression{kind: :unquote, value: {:x, [], nil}, depth: 1, metadata: %{}}
      unquote2 = %UnquoteExpression{kind: :unquote, value: {:y, [], nil}, depth: 1, metadata: %{}}

      quote_expr = %QuotedExpression{
        body: {:+, [], [{:unquote, [], [{:x, [], nil}]}, {:unquote, [], [{:y, [], nil}]}]},
        options: %QuoteOptions{},
        unquotes: [unquote1, unquote2],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

      # Count containsUnquote triples
      unquote_links =
        Enum.filter(triples, fn
          {^quote_iri, pred, _obj} -> pred == Structure.containsUnquote()
          _ -> false
        end)

      assert length(unquote_links) == 2
    end

    test "unquote has depth property" do
      unquote_expr = %UnquoteExpression{
        kind: :unquote,
        value: {:x, [], nil},
        depth: 2,
        metadata: %{}
      }

      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{},
        unquotes: [unquote_expr],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {_quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

      # Verify unquoteDepth triple
      assert Enum.any?(triples, fn
               {_s, pred, obj} ->
                 pred == Structure.unquoteDepth() and
                   RDF.Literal.value(obj) == 2

               _ ->
                 false
             end)
    end
  end

  describe "build/3 with hygiene violations" do
    test "builds quote with var! hygiene violation" do
      violation = %HygieneViolation{
        type: :var_bang,
        variable: :x,
        context: nil,
        metadata: %{}
      }

      quote_expr = %QuotedExpression{
        body: {:var!, [], [{:x, [], nil}]},
        options: %QuoteOptions{},
        unquotes: [],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {quote_iri, triples} =
        QuoteBuilder.build(quote_expr, context,
          module: [:MyApp],
          index: 0,
          hygiene_violations: [violation]
        )

      # Verify hasHygieneViolation triple
      assert Enum.any?(triples, fn
               {^quote_iri, pred, _obj} ->
                 pred == Structure.hasHygieneViolation()

               _ ->
                 false
             end)

      # Verify Hygiene type
      rdf_type = RDF.type()
      hygiene_type = Structure.Hygiene

      assert Enum.any?(triples, fn
               {_s, ^rdf_type, ^hygiene_type} -> true
               _ -> false
             end)

      # Verify violationType
      assert Enum.any?(triples, fn
               {_s, pred, obj} ->
                 pred == Structure.violationType() and
                   RDF.Literal.value(obj) == "var_bang"

               _ ->
                 false
             end)

      # Verify unhygienicVariable
      assert Enum.any?(triples, fn
               {_s, pred, obj} ->
                 pred == Structure.unhygienicVariable() and
                   RDF.Literal.value(obj) == "x"

               _ ->
                 false
             end)
    end

    test "builds quote with var!/2 hygiene violation (with context)" do
      violation = %HygieneViolation{
        type: :var_bang,
        variable: :y,
        context: :match,
        metadata: %{}
      }

      quote_expr = %QuotedExpression{
        body: {:var!, [], [{:y, [], nil}, :match]},
        options: %QuoteOptions{},
        unquotes: [],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {_quote_iri, triples} =
        QuoteBuilder.build(quote_expr, context,
          module: [:MyApp],
          index: 0,
          hygiene_violations: [violation]
        )

      # Verify hygieneContext
      assert Enum.any?(triples, fn
               {_s, pred, obj} ->
                 pred == Structure.hygieneContext() and
                   RDF.Literal.value(obj) == "match"

               _ ->
                 false
             end)
    end

    test "builds quote with Macro.escape hygiene violation" do
      violation = %HygieneViolation{
        type: :macro_escape,
        variable: nil,
        context: nil,
        metadata: %{}
      }

      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{},
        unquotes: [],
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {_quote_iri, triples} =
        QuoteBuilder.build(quote_expr, context,
          module: [:MyApp],
          index: 0,
          hygiene_violations: [violation]
        )

      # Verify violationType is macro_escape
      assert Enum.any?(triples, fn
               {_s, pred, obj} ->
                 pred == Structure.violationType() and
                   RDF.Literal.value(obj) == "macro_escape"

               _ ->
                 false
             end)
    end
  end

  describe "build/3 with location" do
    test "builds quote with source location" do
      location = %SourceLocation{
        start_line: 15,
        start_column: 5,
        end_line: 20,
        end_column: 8
      }

      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{},
        unquotes: [],
        location: location,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")

      {quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:MyApp], index: 0)

      # Verify hasSourceLocation triple
      assert Enum.any?(triples, fn
               {^quote_iri, pred, _obj} ->
                 pred == Core.hasSourceLocation()

               _ ->
                 false
             end)

      # Verify location IRI includes line numbers
      location_triples =
        Enum.filter(triples, fn
          {_s, pred, _o} -> pred == Core.hasSourceLocation()
          _ -> false
        end)

      assert length(location_triples) >= 1
      {_, _, location_iri} = hd(location_triples)

      assert to_string(location_iri) =~ "L15-20"

      # Verify location has SourceLocation type
      assert {location_iri, RDF.type(), Core.SourceLocation} in triples
    end
  end

  describe "build_unquote/3" do
    test "builds unquote expression directly" do
      unquote_expr = %UnquoteExpression{
        kind: :unquote,
        value: {:x, [], nil},
        depth: 1,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      quote_iri = RDF.iri("https://example.org/code#MyApp/quote/0")

      {unquote_iri, triples} =
        QuoteBuilder.build_unquote(unquote_expr, context, quote_iri: quote_iri, index: 0)

      # Verify IRI format
      assert to_string(unquote_iri) =~ "unquote/0"

      # Verify type
      assert {unquote_iri, RDF.type(), Structure.UnquoteExpression} in triples
    end

    test "builds unquote_splicing expression" do
      unquote_expr = %UnquoteExpression{
        kind: :unquote_splicing,
        value: {:list, [], nil},
        depth: 1,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      quote_iri = RDF.iri("https://example.org/code#MyApp/quote/0")

      {unquote_iri, triples} =
        QuoteBuilder.build_unquote(unquote_expr, context, quote_iri: quote_iri, index: 0)

      # Verify splicing type
      assert {unquote_iri, RDF.type(), Structure.UnquoteSplicingExpression} in triples
    end
  end

  describe "build_hygiene_violation/3" do
    test "builds hygiene violation directly" do
      violation = %HygieneViolation{
        type: :var_bang,
        variable: :my_var,
        context: nil,
        metadata: %{}
      }

      context = Context.new(base_iri: "https://example.org/code#")
      quote_iri = RDF.iri("https://example.org/code#MyApp/quote/0")

      {violation_iri, triples} =
        QuoteBuilder.build_hygiene_violation(violation, context, quote_iri: quote_iri, index: 0)

      # Verify IRI format
      assert to_string(violation_iri) =~ "hygiene/0"

      # Verify type
      assert {violation_iri, RDF.type(), Structure.Hygiene} in triples

      # Verify variable name
      assert Enum.any?(triples, fn
               {^violation_iri, pred, obj} ->
                 pred == Structure.unhygienicVariable() and
                   RDF.Literal.value(obj) == "my_var"

               _ ->
                 false
             end)
    end
  end
end
