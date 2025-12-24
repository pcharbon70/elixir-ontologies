defmodule ElixirOntologies.Metaprogramming.Phase15IntegrationTest do
  @moduledoc """
  Integration tests for Phase 15 metaprogramming support.

  These tests verify end-to-end functionality of macro invocation extraction,
  attribute value extraction, quote/unquote handling, and RDF generation.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.{MacroInvocation, Attribute, Quote}

  alias ElixirOntologies.Extractors.Quote.{
    QuotedExpression,
    QuoteOptions,
    UnquoteExpression,
    HygieneViolation
  }

  alias ElixirOntologies.Builders.{MacroBuilder, AttributeBuilder, QuoteBuilder, Context}
  alias ElixirOntologies.NS.Structure

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp build_context(opts \\ []) do
    Context.new(
      base_iri: Keyword.get(opts, :base_iri, "https://example.org/code#"),
      file_path: Keyword.get(opts, :file_path, nil)
    )
  end

  defp has_triple?(triples, subject, predicate, object) do
    Enum.any?(triples, fn {s, p, o} ->
      s == subject and p == predicate and o == object
    end)
  end

  defp has_triple_with_value?(triples, predicate, value) do
    Enum.any?(triples, fn
      {_, p, o} ->
        p == predicate and RDF.Literal.value(o) == value

      _ ->
        false
    end)
  end

  defp count_triples_with_type(triples, type_class) do
    rdf_type = RDF.type()

    Enum.count(triples, fn
      {_, p, o} -> p == rdf_type and o == type_class
      _ -> false
    end)
  end

  defp count_triples_with_predicate(triples, predicate) do
    Enum.count(triples, fn
      {_, p, _} -> p == predicate
      _ -> false
    end)
  end

  # ===========================================================================
  # Macro-Heavy Module Tests
  # ===========================================================================

  describe "complete metaprogramming extraction for macro-heavy module" do
    @macro_heavy_module """
    defmodule MacroHeavy do
      @moduledoc "A module with lots of macros"

      require Logger
      import Enum, only: [map: 2]

      @doc "A documented function"
      @deprecated "Use new_func/1 instead"
      def old_func(x) do
        if x > 0 do
          Logger.debug("positive")
          x
        else
          unless x < -10 do
            0
          else
            -1
          end
        end
      end

      defmacro my_macro(expr) do
        quote do
          unquote(expr) + 1
        end
      end

      for i <- 1..3 do
        def unquote(:"func_\#{i}")(), do: unquote(i)
      end
    end
    """

    test "extracts all macro invocations from macro-heavy module" do
      {:ok, ast} = Code.string_to_quoted(@macro_heavy_module)

      # Use extract_all_recursive for full AST traversal
      invocations = MacroInvocation.extract_all_recursive(ast)

      # Should find: defmodule, require, import, @, def, if, unless, defmacro, quote, for
      assert length(invocations) >= 8

      macro_names = Enum.map(invocations, & &1.macro_name)
      assert :defmodule in macro_names
      assert :def in macro_names
      assert :defmacro in macro_names
    end

    test "extracts module attributes from macro-heavy module" do
      {:ok, {:defmodule, _, [_, [do: {:__block__, _, body}]]}} =
        Code.string_to_quoted(@macro_heavy_module)

      # Build a __block__ from the body list for extract_all
      block_ast = {:__block__, [], body}
      attributes = Attribute.extract_all(block_ast)

      # Should find: @moduledoc, @doc, @deprecated
      assert length(attributes) >= 3

      attr_names = Enum.map(attributes, & &1.name)
      assert :moduledoc in attr_names
      assert :doc in attr_names
      assert :deprecated in attr_names
    end

    test "builds RDF for macro invocations" do
      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :def,
        arity: 2,
        category: :definition,
        resolution_status: :kernel,
        metadata: %{invocation_index: 0, module: [:MacroHeavy]}
      }

      context = build_context()
      {invocation_iri, triples} = MacroBuilder.build(invocation, context)

      assert to_string(invocation_iri) =~ "MacroHeavy"
      assert to_string(invocation_iri) =~ "invocation"
      assert has_triple?(triples, invocation_iri, RDF.type(), Structure.MacroInvocation)
      assert has_triple_with_value?(triples, Structure.macroName(), "def")
    end
  end

  # ===========================================================================
  # Macro Invocation Tests
  # ===========================================================================

  describe "macro invocation tracking across multiple modules" do
    test "tracks Kernel macros with correct module" do
      ast = {:if, [line: 1], [true, [do: :ok]]}
      {:ok, invocation} = MacroInvocation.extract(ast)

      assert invocation.macro_module == Kernel
      assert invocation.macro_name == :if
      assert invocation.category == :control_flow
      assert invocation.resolution_status == :kernel
    end

    test "tracks definition macros" do
      ast = {:def, [line: 1], [{:foo, [], []}, [do: :ok]]}
      {:ok, invocation} = MacroInvocation.extract(ast)

      assert invocation.macro_module == Kernel
      assert invocation.macro_name == :def
      assert invocation.category == :definition
    end

    test "tracks import macros" do
      ast = {:import, [line: 1], [{:__aliases__, [], [:Enum]}]}
      {:ok, invocation} = MacroInvocation.extract(ast)

      assert invocation.macro_name == :import
      assert invocation.category == :import
    end

    test "builds RDF with correct resolution status" do
      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :unless,
        arity: 2,
        category: :control_flow,
        resolution_status: :kernel,
        metadata: %{invocation_index: 0, module: [:TestModule]}
      }

      context = build_context()
      {_iri, triples} = MacroBuilder.build(invocation, context)

      assert has_triple_with_value?(triples, Structure.resolutionStatus(), "kernel")
    end
  end

  # ===========================================================================
  # Attribute Value Tests
  # ===========================================================================

  describe "attribute value extraction for all attribute types" do
    test "extracts @moduledoc with content" do
      ast = {:@, [line: 1], [{:moduledoc, [], ["Module documentation here"]}]}
      {:ok, attr} = Attribute.extract(ast)

      assert attr.type == :moduledoc_attribute
      assert attr.name == :moduledoc
      assert attr.value == "Module documentation here"
    end

    test "extracts @doc with content" do
      ast = {:@, [line: 1], [{:doc, [], ["Function documentation"]}]}
      {:ok, attr} = Attribute.extract(ast)

      assert attr.type == :doc_attribute
      assert attr.name == :doc
      assert attr.value == "Function documentation"
    end

    test "extracts @doc false" do
      ast = {:@, [line: 1], [{:doc, [], [false]}]}
      {:ok, attr} = Attribute.extract(ast)

      assert attr.type == :doc_attribute
      assert attr.value == false
      assert attr.metadata.hidden == true
    end

    test "extracts @deprecated with message" do
      ast = {:@, [line: 1], [{:deprecated, [], ["Use new_func/1"]}]}
      {:ok, attr} = Attribute.extract(ast)

      assert attr.type == :deprecated_attribute
      assert attr.value == "Use new_func/1"
    end

    test "extracts @since version" do
      ast = {:@, [line: 1], [{:since, [], ["1.5.0"]}]}
      {:ok, attr} = Attribute.extract(ast)

      assert attr.type == :since_attribute
      assert attr.value == "1.5.0"
    end

    test "extracts custom attribute with literal value" do
      ast = {:@, [line: 1], [{:my_attr, [], [42]}]}
      {:ok, attr} = Attribute.extract(ast)

      assert attr.type == :attribute
      assert attr.name == :my_attr
      assert attr.value == 42
    end

    test "builds RDF for documentation attributes" do
      attr = %Attribute{
        type: :doc_attribute,
        name: :doc,
        value: "Function docs",
        metadata: %{hidden: false}
      }

      context = build_context()
      {attr_iri, triples} = AttributeBuilder.build(attr, context, module: [:TestModule])

      assert has_triple?(triples, attr_iri, RDF.type(), Structure.FunctionDocAttribute)
      assert has_triple_with_value?(triples, Structure.docstring(), "Function docs")
    end

    test "builds RDF for @doc false" do
      attr = %Attribute{
        type: :doc_attribute,
        name: :doc,
        value: false,
        metadata: %{hidden: true}
      }

      context = build_context()
      {_attr_iri, triples} = AttributeBuilder.build(attr, context, module: [:TestModule])

      assert has_triple_with_value?(triples, Structure.isDocFalse(), true)
    end
  end

  describe "accumulated attribute representation" do
    test "builds RDF for accumulated attributes" do
      attr = %Attribute{
        type: :attribute,
        name: :callbacks,
        value: {:on_init, 1},
        metadata: %{}
      }

      context = build_context()

      {attr_iri, triples} =
        AttributeBuilder.build(attr, context, module: [:TestModule], accumulated: true, index: 0)

      assert to_string(attr_iri) =~ "callbacks/0"
      assert has_triple_with_value?(triples, Structure.isAccumulating(), true)
    end

    test "indexes accumulated attributes correctly" do
      context = build_context()

      {iri0, _} =
        AttributeBuilder.build(
          %Attribute{type: :attribute, name: :items, value: "a", metadata: %{}},
          context,
          module: [:M],
          accumulated: true,
          index: 0
        )

      {iri1, _} =
        AttributeBuilder.build(
          %Attribute{type: :attribute, name: :items, value: "b", metadata: %{}},
          context,
          module: [:M],
          accumulated: true,
          index: 1
        )

      assert to_string(iri0) =~ "items/0"
      assert to_string(iri1) =~ "items/1"
      assert iri0 != iri1
    end
  end

  describe "documentation content preservation" do
    test "preserves full documentation content" do
      long_doc = """
      This is a long documentation string.

      It has multiple paragraphs and
      various formatting.

      ## Examples

          iex> example()
          :ok
      """

      attr = %Attribute{
        type: :moduledoc_attribute,
        name: :moduledoc,
        value: long_doc,
        metadata: %{hidden: false}
      }

      context = build_context()
      {_attr_iri, triples} = AttributeBuilder.build(attr, context, module: [:TestModule])

      # Find the docstring triple
      doc_triple =
        Enum.find(triples, fn
          {_, pred, _} -> pred == Structure.docstring()
          _ -> false
        end)

      assert doc_triple != nil
      {_, _, obj} = doc_triple
      assert RDF.Literal.value(obj) == long_doc
    end
  end

  describe "compile attribute extraction" do
    test "extracts @compile attribute" do
      ast = {:@, [line: 1], [{:compile, [], [[:inline]]}]}
      {:ok, attr} = Attribute.extract(ast)

      assert attr.type == :compile_attribute
      assert attr.name == :compile
    end

    test "extracts @external_resource attribute" do
      ast = {:@, [line: 1], [{:external_resource, [], ["priv/data.json"]}]}
      {:ok, attr} = Attribute.extract(ast)

      assert attr.type == :external_resource_attribute
    end

    test "extracts @before_compile attribute" do
      ast = {:@, [line: 1], [{:before_compile, [], [{:__aliases__, [], [:MyHooks]}]}]}
      {:ok, attr} = Attribute.extract(ast)

      assert attr.type == :before_compile_attribute
    end
  end

  # ===========================================================================
  # Quote/Unquote Tests
  # ===========================================================================

  describe "quote/unquote extraction in macro definitions" do
    test "extracts basic quote block" do
      ast = {:quote, [], [[do: {:+, [], [1, 2]}]]}
      {:ok, quote_expr} = Quote.extract(ast)

      assert quote_expr.body == {:+, [], [1, 2]}
      assert quote_expr.options.unquote == true
    end

    test "extracts quote with context option" do
      ast = {:quote, [], [[context: :match], [do: {:x, [], nil}]]}
      {:ok, quote_expr} = Quote.extract(ast)

      assert quote_expr.options.context == :match
    end

    test "extracts quote with bind_quoted option" do
      ast = {:quote, [], [[bind_quoted: [x: 1, y: 2]], [do: :ok]]}
      {:ok, quote_expr} = Quote.extract(ast)

      assert quote_expr.options.bind_quoted == [x: 1, y: 2]
    end

    test "extracts unquote expressions within quote" do
      body = {:+, [], [{:unquote, [], [{:x, [], nil}]}, 1]}
      ast = {:quote, [], [[do: body]]}
      {:ok, quote_expr} = Quote.extract(ast)

      assert length(quote_expr.unquotes) == 1
      assert hd(quote_expr.unquotes).kind == :unquote
    end

    test "builds RDF for quote block with options" do
      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{context: :match, bind_quoted: [x: 1]},
        unquotes: [],
        metadata: %{}
      }

      context = build_context()

      {quote_iri, triples} =
        QuoteBuilder.build(quote_expr, context, module: [:MyMacros], index: 0)

      assert to_string(quote_iri) =~ "quote/0"
      assert has_triple?(triples, quote_iri, RDF.type(), Structure.QuotedExpression)
      assert has_triple_with_value?(triples, Structure.quoteContext(), "match")
      assert has_triple_with_value?(triples, Structure.hasBindQuoted(), true)
    end
  end

  describe "nested quote handling" do
    test "extracts nested quote with correct depth from body" do
      # quote do: quote do: unquote(x)
      inner_body = {:unquote, [], [{:x, [], nil}]}
      inner_quote = {:quote, [], [[do: inner_body]]}
      outer_ast = {:quote, [], [[do: inner_quote]]}

      {:ok, outer_quote} = Quote.extract(outer_ast)

      # outer_quote.body is the inner_quote node (a single quote)
      # When starting from a quote node, find_unquotes starts at depth 0
      # Then the quote is encountered and depth becomes 1
      # The unquote inside that single quote is at depth 1
      unquotes = Quote.find_unquotes(outer_quote.body)
      assert length(unquotes) == 1
      assert hd(unquotes).depth == 1
    end

    test "extracts nested quote - direct call to find_unquotes on full ast" do
      # Build: quote do: quote do: unquote(x)
      inner_body = {:unquote, [], [{:x, [], nil}]}
      inner_quote = {:quote, [], [[do: inner_body]]}
      outer_ast = {:quote, [], [[do: inner_quote]]}

      # Find unquotes starting from the outer quote
      unquotes = Quote.find_unquotes(outer_ast)
      assert length(unquotes) == 1
      # Starting from outer quote (quote node), depth increments correctly
      assert hd(unquotes).depth == 2
    end

    test "builds RDF for unquote with depth" do
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

      context = build_context()
      {_quote_iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:M], index: 0)

      assert has_triple_with_value?(triples, Structure.unquoteDepth(), 2)
    end
  end

  describe "hygiene analysis accuracy" do
    test "detects var!/1 usage" do
      ast = {:var!, [], [{:x, [], nil}]}
      violations = Quote.find_var_bang(ast)

      assert length(violations) == 1
      assert hd(violations).type == :var_bang
      assert hd(violations).variable == :x
    end

    test "detects var!/2 usage with context" do
      ast = {:var!, [], [{:y, [], nil}, :match]}
      violations = Quote.find_var_bang(ast)

      assert length(violations) == 1
      assert hd(violations).context == :match
    end

    test "detects Macro.escape usage" do
      ast = {{:., [], [{:__aliases__, [], [:Macro]}, :escape]}, [], [{:value, [], nil}]}
      violations = Quote.find_macro_escapes(ast)

      assert length(violations) == 1
      assert hd(violations).type == :macro_escape
    end

    test "builds RDF for hygiene violations" do
      violation = %HygieneViolation{
        type: :var_bang,
        variable: :my_var,
        context: :match,
        metadata: %{}
      }

      quote_expr = %QuotedExpression{
        body: {:var!, [], [{:my_var, [], nil}, :match]},
        options: %QuoteOptions{},
        unquotes: [],
        metadata: %{}
      }

      context = build_context()

      {_quote_iri, triples} =
        QuoteBuilder.build(quote_expr, context,
          module: [:M],
          index: 0,
          hygiene_violations: [violation]
        )

      # Should have hasHygieneViolation link
      assert count_triples_with_predicate(triples, Structure.hasHygieneViolation()) == 1

      # Should have Hygiene type
      assert count_triples_with_type(triples, Structure.Hygiene) == 1

      # Should have violation details
      assert has_triple_with_value?(triples, Structure.violationType(), "var_bang")
      assert has_triple_with_value?(triples, Structure.unhygienicVariable(), "my_var")
      assert has_triple_with_value?(triples, Structure.hygieneContext(), "match")
    end
  end

  # ===========================================================================
  # Backward Compatibility Tests
  # ===========================================================================

  describe "backward compatibility with existing macro extraction" do
    test "MacroInvocation struct has expected fields" do
      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :def,
        arity: 2,
        category: :definition,
        resolution_status: :kernel,
        arguments: [],
        location: nil,
        metadata: %{}
      }

      assert invocation.macro_module == Kernel
      assert invocation.macro_name == :def
      assert invocation.arity == 2
    end

    test "Attribute struct has expected fields" do
      attr = %Attribute{
        type: :attribute,
        name: :my_attr,
        value: 42,
        location: nil,
        metadata: %{}
      }

      assert attr.type == :attribute
      assert attr.name == :my_attr
      assert attr.value == 42
    end

    test "QuotedExpression struct has expected fields" do
      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{},
        unquotes: [],
        location: nil,
        metadata: %{}
      }

      assert quote_expr.body == :ok
      assert quote_expr.options.unquote == true
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "error handling for complex AST patterns" do
    test "handles nil AST gracefully" do
      result = MacroInvocation.extract(nil)
      assert {:error, _} = result
    end

    test "handles non-macro AST gracefully" do
      # A simple literal is not a macro invocation
      result = MacroInvocation.extract(42)
      assert {:error, _} = result
    end

    test "handles empty quote body" do
      ast = {:quote, [], [[do: nil]]}
      {:ok, quote_expr} = Quote.extract(ast)
      assert quote_expr.body == nil
    end

    test "Quote.extract returns error for non-quote" do
      result = Quote.extract({:if, [], [true, [do: :ok]]})
      assert {:error, _} = result
    end

    test "handles quote with unquote: false" do
      body = {:+, [], [{:unquote, [], [{:x, [], nil}]}, 1]}
      ast = {:quote, [], [[unquote: false], [do: body]]}
      {:ok, quote_expr} = Quote.extract(ast)

      # unquotes should be empty because unquoting is disabled
      assert quote_expr.options.unquote == false
      assert quote_expr.unquotes == []
    end
  end

  # ===========================================================================
  # RDF Validation Tests
  # ===========================================================================

  describe "metaprogramming RDF structure" do
    test "macro invocation RDF has required triples" do
      invocation = %MacroInvocation{
        macro_module: Kernel,
        macro_name: :if,
        arity: 2,
        category: :control_flow,
        resolution_status: :kernel,
        metadata: %{invocation_index: 5, module: [:TestMod]}
      }

      context = build_context()
      {iri, triples} = MacroBuilder.build(invocation, context)

      # Required triples
      assert has_triple?(triples, iri, RDF.type(), Structure.MacroInvocation)
      assert has_triple_with_value?(triples, Structure.macroName(), "if")
      assert has_triple_with_value?(triples, Structure.macroArity(), 2)
      assert has_triple_with_value?(triples, Structure.macroCategory(), "control_flow")
    end

    test "attribute RDF has required triples" do
      attr = %Attribute{
        type: :deprecated_attribute,
        name: :deprecated,
        value: "Use new_func/1",
        metadata: %{message: "Use new_func/1"}
      }

      context = build_context()
      {iri, triples} = AttributeBuilder.build(attr, context, module: [:TestMod])

      assert has_triple?(triples, iri, RDF.type(), Structure.DeprecatedAttribute)
      assert has_triple_with_value?(triples, Structure.attributeName(), "deprecated")
      assert has_triple_with_value?(triples, Structure.deprecationMessage(), "Use new_func/1")
    end

    test "quote RDF has required triples" do
      unquote_expr = %UnquoteExpression{
        kind: :unquote,
        value: {:x, [], nil},
        depth: 1,
        metadata: %{}
      }

      quote_expr = %QuotedExpression{
        body: :ok,
        options: %QuoteOptions{location: :keep},
        unquotes: [unquote_expr],
        metadata: %{}
      }

      context = build_context()
      {iri, triples} = QuoteBuilder.build(quote_expr, context, module: [:TestMod], index: 0)

      assert has_triple?(triples, iri, RDF.type(), Structure.QuotedExpression)
      assert has_triple_with_value?(triples, Structure.locationKeep(), true)
      assert count_triples_with_predicate(triples, Structure.containsUnquote()) == 1
      assert count_triples_with_type(triples, Structure.UnquoteExpression) == 1
    end
  end
end
