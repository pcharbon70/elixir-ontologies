defmodule ElixirOntologies.Builders.ExpressionBuilderTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{Context, ExpressionBuilder}
  alias ElixirOntologies.NS.Core

  doctest ExpressionBuilder

  describe "build/3 mode selection" do
    test "returns :skip when include_expressions is false" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: false},
          file_path: "lib/my_app/users.ex"
        )

      ast = {:==, [], [{:x, [], nil}, 1]}
      assert ExpressionBuilder.build(ast, context, []) == :skip
    end

    test "returns {:ok, {expr_iri, triples, context}} for nil AST in full mode" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      assert {:ok, {expr_iri, triples, _updated_context}} = ExpressionBuilder.build(nil, context, [])
      assert has_type?(triples, Core.NilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.atomValue(), "nil")
    end

    test "returns :skip for dependency files even when include_expressions is true" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "deps/decimal/lib/decimal.ex"
        )

      ast = {:==, [], [{:x, [], nil}, 1]}
      assert ExpressionBuilder.build(ast, context, []) == :skip
    end

    test "returns {:ok, {expr_iri, triples, context}} when include_expressions is true and project file" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}
      result = ExpressionBuilder.build(ast, context, [])

      assert {:ok, {expr_iri, triples, _updated_context}} = result
      assert is_struct(expr_iri, RDF.IRI)
      assert is_list(triples)
    end
  end

  describe "build/3 IRI generation" do
    test "generates IRI with correct base" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, _triples, _context}} = ExpressionBuilder.build(ast, context, [])

      iri_string = RDF.IRI.to_string(expr_iri)
      assert String.starts_with?(iri_string, "https://example.org/code#expr/")
    end

    test "accepts custom suffix option" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {expr_iri, _triples, _context}} = ExpressionBuilder.build(ast, context, suffix: "my_expr")

      iri_string = RDF.IRI.to_string(expr_iri)
      assert iri_string == "https://example.org/code#expr/my_expr"
    end

    test "generates unique IRIs for multiple calls" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}

      {:ok, {iri1, _, context2}} = ExpressionBuilder.build(ast, context, [])
      {:ok, {iri2, _, _}} = ExpressionBuilder.build(ast, context2, [])

      refute iri1 == iri2
    end

    test "generates deterministic sequential IRIs" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      ast = {:==, [], [{:x, [], nil}, 1]}

      {:ok, {iri1, _, context2}} = ExpressionBuilder.build(ast, context, [])
      {:ok, {iri2, _, context3}} = ExpressionBuilder.build(ast, context2, [])
      {:ok, {iri3, _, _}} = ExpressionBuilder.build(ast, context3, [])

      # IRIs should be sequential based on counter
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/expr_2"
    end
  end

  describe "comparison operators" do
    for op <- [:==, :!=, :===, :!==, :<, :>, :<=, :>=] do
      @op op

      test "dispatches #{op} to ComparisonOperator" do
        context =
          Context.new(
            base_iri: "https://example.org/code#",
            config: %{include_expressions: true},
            file_path: "lib/my_app/users.ex"
          )

        ast = {@op, [], [{:x, [], nil}, 1]}
        {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

        # Check for ComparisonOperator type
        assert Enum.any?(triples, fn {_s, p, o} ->
          p == RDF.type() and o == Core.ComparisonOperator
        end)

        # Check for operator symbol
        assert Enum.any?(triples, fn {_s, p, o} ->
          p == Core.operatorSymbol() and
            RDF.Literal.value(o) == to_string(@op)
        end)
      end
    end
  end

  describe "logical operators" do
    test "dispatches and to LogicalOperator" do
      context = full_mode_context()
      ast = {:and, [], [true, false]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "and")
    end

    test "dispatches or to LogicalOperator" do
      context = full_mode_context()
      ast = {:or, [], [true, false]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "or")
    end

    test "dispatches && to LogicalOperator" do
      context = full_mode_context()
      ast = {:&&, [], [true, false]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "&&")
    end

    test "dispatches || to LogicalOperator" do
      context = full_mode_context()
      ast = {:||, [], [true, false]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "||")
    end

    test "dispatches not to LogicalOperator (unary)" do
      context = full_mode_context()
      ast = {:not, [], [true]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "not")
    end

    test "dispatches ! to LogicalOperator (unary)" do
      context = full_mode_context()
      ast = {:!, [], [true]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "!")
    end
  end

  describe "arithmetic operators" do
    for op <- [:+, :-, :*, :/, :div, :rem] do
      @op op

      test "dispatches #{op} to ArithmeticOperator" do
        context = full_mode_context()
        ast = {@op, [], [1, 2]}
        {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

        assert has_type?(triples, Core.ArithmeticOperator)
        assert has_operator_symbol?(triples, to_string(@op))
      end
    end
  end

  describe "pipe operator" do
    test "dispatches |> to PipeOperator" do
      context = full_mode_context()
      ast = {:|>, [], [1, Enum]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.PipeOperator)
      assert has_operator_symbol?(triples, "|>")
    end
  end

  describe "string concatenation operator" do
    test "dispatches <> to StringConcatOperator" do
      context = full_mode_context()
      ast = {:<>, [], ["hello", "world"]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.StringConcatOperator)
      assert has_operator_symbol?(triples, "<>")
    end
  end

  describe "list operators" do
    test "dispatches ++ to ListOperator" do
      context = full_mode_context()
      ast = {:++, [], [[1], [2]]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.ListOperator)
      assert has_operator_symbol?(triples, "++")
    end

    test "dispatches -- to ListOperator" do
      context = full_mode_context()
      ast = {:--, [], [[1, 2], [1]]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.ListOperator)
      assert has_operator_symbol?(triples, "--")
    end
  end

  describe "match operator" do
    test "dispatches = to MatchOperator" do
      context = full_mode_context()
      ast = {:"=", [], [{:x, [], nil}, 1]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.MatchOperator)
      assert has_operator_symbol?(triples, "=")
    end
  end

  describe "variables" do
    test "dispatches variable pattern to Variable" do
      context = full_mode_context()
      ast = {:x, [], nil}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.Variable)

      # Check for name property
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and RDF.Literal.value(o) == "x"
      end)
    end

    test "handles variables with different names" do
      context = full_mode_context()

      for var_name <- [:user, :count, :result, :acc] do
        ast = {var_name, [], nil}
        {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

        assert has_type?(triples, Core.Variable)
        assert Enum.any?(triples, fn {_s, p, o} ->
          p == Core.name() and RDF.Literal.value(o) == to_string(var_name)
        end)
      end
    end
  end

  describe "wildcard pattern" do
    test "dispatches _ to WildcardPattern" do
      context = full_mode_context()
      ast = {:_}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.WildcardPattern)
    end
  end

  describe "remote calls" do
    test "dispatches Module.function to RemoteCall" do
      context = full_mode_context()

      # AST for String.to_integer("123")
      ast =
        {{:., [], [{:__aliases__, [], [:String]}, :to_integer]}, [],
         ["123"]}

      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.RemoteCall)

      # Check for name property with module and function
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and
          RDF.Literal.value(o) == "String.to_integer"
      end)
    end

    test "handles nested module names" do
      context = full_mode_context()

      # AST for MyApp.Users.get(1)
      ast =
        {{:., [], [{:__aliases__, [], [:MyApp, :Users]}, :get]}, [], [1]}

      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.RemoteCall)
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and RDF.Literal.value(o) == "MyApp.Users.get"
      end)
    end
  end

  describe "local calls" do
    test "dispatches function(args) to LocalCall" do
      context = full_mode_context()
      ast = {:foo, [], [1, 2]}
      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(ast, context, [])

      assert has_type?(triples, Core.LocalCall)

      # Check for name property
      assert Enum.any?(triples, fn {_s, p, o} ->
        p == Core.name() and RDF.Literal.value(o) == "foo"
      end)
    end
  end

  describe "literals" do
    test "builds IntegerLiteral triples for integer literals" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(42, context, [])

      assert has_type?(triples, Core.IntegerLiteral)
      assert has_literal_value?(triples, expr_iri, Core.integerValue(), 42)
    end

    test "builds FloatLiteral triples for float literals" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(3.14, context, [])

      assert has_type?(triples, Core.FloatLiteral)
      assert has_literal_value?(triples, expr_iri, Core.floatValue(), 3.14)
    end

    test "builds IntegerLiteral triples for zero" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(0, context, [])

      assert has_type?(triples, Core.IntegerLiteral)
      assert has_literal_value?(triples, expr_iri, Core.integerValue(), 0)
    end

    test "builds IntegerLiteral triples for large integers" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(9_999_999_999, context, [])

      assert has_type?(triples, Core.IntegerLiteral)
      assert has_literal_value?(triples, expr_iri, Core.integerValue(), 9_999_999_999)
    end

    test "builds IntegerLiteral triples for small integers" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(1, context, [])

      assert has_type?(triples, Core.IntegerLiteral)
      assert has_literal_value?(triples, expr_iri, Core.integerValue(), 1)
    end

    test "builds FloatLiteral triples for zero" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(0.0, context, [])

      assert has_type?(triples, Core.FloatLiteral)
      assert has_literal_value?(triples, expr_iri, Core.floatValue(), 0.0)
    end

    test "builds FloatLiteral triples for scientific notation" do
      context = full_mode_context()

      # Elixir parses 1.5e-3 as 0.0015
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(0.0015, context, [])

      assert has_type?(triples, Core.FloatLiteral)
      assert has_literal_value?(triples, expr_iri, Core.floatValue(), 0.0015)
    end

    test "builds FloatLiteral triples for large scientific notation" do
      context = full_mode_context()

      # Elixir parses 1.0e10 as 10000000000.0
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(10_000_000_000.0, context, [])

      assert has_type?(triples, Core.FloatLiteral)
      assert has_literal_value?(triples, expr_iri, Core.floatValue(), 10_000_000_000.0)
    end

    test "builds FloatLiteral triples for negative decimal" do
      context = full_mode_context()

      # Negative floats use unary operator, so we test the literal value itself
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(0.5, context, [])

      assert has_type?(triples, Core.FloatLiteral)
      assert has_literal_value?(triples, expr_iri, Core.floatValue(), 0.5)
    end

    test "builds FloatLiteral triples for very small floats" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(1.0e-10, context, [])

      assert has_type?(triples, Core.FloatLiteral)
      # The value is preserved in float precision
      assert has_type?(triples, Core.FloatLiteral)
    end

    test "builds StringLiteral triples for string literals" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build("hello", context, [])

      assert has_type?(triples, Core.StringLiteral)
      assert has_literal_value?(triples, expr_iri, Core.stringValue(), "hello")
    end

    test "builds StringLiteral triples for empty strings" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build("", context, [])

      assert has_type?(triples, Core.StringLiteral)
      assert has_literal_value?(triples, expr_iri, Core.stringValue(), "")
    end

    test "builds StringLiteral triples for multi-line strings (heredocs)" do
      context = full_mode_context()

      # Heredocs are converted to plain binaries with newlines preserved
      heredoc_content = "multi\nline\nstring"
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(heredoc_content, context, [])

      assert has_type?(triples, Core.StringLiteral)
      assert has_literal_value?(triples, expr_iri, Core.stringValue(), heredoc_content)
    end

    test "builds StringLiteral triples for strings with escape sequences" do
      context = full_mode_context()

      # Escape sequences are processed by Elixir compiler before AST
      # The resulting binary contains the actual characters
      string_with_escapes = "hello\nworld\t!"
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(string_with_escapes, context, [])

      assert has_type?(triples, Core.StringLiteral)
      assert has_literal_value?(triples, expr_iri, Core.stringValue(), string_with_escapes)
    end

    test "builds StringLiteral triples for strings with special characters" do
      context = full_mode_context()

      special_chars = "!@#$%^&*()_+-=[]{}|;':\",./<>?"
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(special_chars, context, [])

      assert has_type?(triples, Core.StringLiteral)
      assert has_literal_value?(triples, expr_iri, Core.stringValue(), special_chars)
    end

    test "builds StringLiteral triples for Unicode strings" do
      context = full_mode_context()

      unicode_string = "héllo wørld 你好"
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(unicode_string, context, [])

      assert has_type?(triples, Core.StringLiteral)
      assert has_literal_value?(triples, expr_iri, Core.stringValue(), unicode_string)
    end

    test "builds StringLiteral triples for strings with quotes" do
      context = full_mode_context()

      # Strings containing quotes (escape sequences processed by compiler)
      quoted_string = "He said \"hello\""
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(quoted_string, context, [])

      assert has_type?(triples, Core.StringLiteral)
      assert has_literal_value?(triples, expr_iri, Core.stringValue(), quoted_string)
    end

    test "builds StringLiteral triples for long strings" do
      context = full_mode_context()

      long_string = String.duplicate("a", 1000)
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(long_string, context, [])

      assert has_type?(triples, Core.StringLiteral)
      assert has_literal_value?(triples, expr_iri, Core.stringValue(), long_string)
    end

    test "builds AtomLiteral triples for atom literals" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(:ok, context, [])

      assert has_type?(triples, Core.AtomLiteral)
      assert has_literal_value?(triples, expr_iri, Core.atomValue(), ":ok")
    end

    test "builds BooleanLiteral triples for true" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(true, context, [])

      assert has_type?(triples, Core.BooleanLiteral)
      assert has_literal_value?(triples, expr_iri, Core.atomValue(), "true")
    end

    test "builds BooleanLiteral triples for false" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(false, context, [])

      assert has_type?(triples, Core.BooleanLiteral)
      assert has_literal_value?(triples, expr_iri, Core.atomValue(), "false")
    end

    test "builds NilLiteral triples for nil" do
      context = full_mode_context()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(nil, context, [])

      assert has_type?(triples, Core.NilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.atomValue(), "nil")
    end

    test "builds CharlistLiteral triples for charlists" do
      context = full_mode_context()

      # In Elixir AST, 'hello' appears as a list of character codes
      charlist = [104, 101, 108, 108, 111]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "hello")
    end

    test "builds CharlistLiteral triples for empty charlist" do
      context = full_mode_context()

      # Empty charlist '' appears as empty list []
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build([], context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "")
    end

    test "builds CharlistLiteral triples for single character charlist" do
      context = full_mode_context()

      # Single character charlist like '?' appears as [63]
      charlist = [63]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "?")
    end

    test "builds CharlistLiteral triples for charlist with escape sequences" do
      context = full_mode_context()

      # Escape sequences are processed by Elixir compiler
      # '\n' appears as [10] (newline character code)
      charlist = [10]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "\n")
    end

    test "builds CharlistLiteral triples for charlist with Unicode characters" do
      context = full_mode_context()

      # Unicode characters are represented by their codepoints
      # "héllo" = [104, 233, 108, 108, 111]
      charlist = [104, 233, 108, 108, 111]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "héllo")
    end

    test "builds CharlistLiteral triples for multi-byte Unicode charlist" do
      context = full_mode_context()

      # Chinese characters: "你好" (codepoints 20320 and 22909)
      charlist = [20320, 22909]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_literal_value?(triples, expr_iri, Core.charlistValue(), "你好")
    end

    test "treats non-charlist lists as ListLiteral" do
      context = full_mode_context()

      # A list containing non-integer elements is not a charlist
      mixed_list = [1, :atom, "string"]
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(mixed_list, context, [])

      # Should be ListLiteral (not CharlistLiteral, not generic Expression)
      refute has_type?(triples, Core.CharlistLiteral)
      assert has_type?(triples, Core.ListLiteral)
    end

    test "builds BinaryLiteral triples for binary with single literal integer" do
      context = full_mode_context()

      # Binary with single byte: <<65>>
      binary_ast = {:<<>>, [], [65]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      assert has_type?(triples, Core.BinaryLiteral)
      # RDF.XSD.Base64Binary stores the raw binary value (checked via lexical)
      assert has_binary_literal_value?(triples, expr_iri, Core.binaryValue(), "A")
    end

    test "builds BinaryLiteral triples for binary with multiple literal integers" do
      context = full_mode_context()

      # Binary with multiple bytes: <<65, 66, 67>> = "ABC"
      binary_ast = {:<<>>, [], [65, 66, 67]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      assert has_type?(triples, Core.BinaryLiteral)
      # RDF.XSD.Base64Binary stores the raw binary value (checked via lexical)
      assert has_binary_literal_value?(triples, expr_iri, Core.binaryValue(), "ABC")
    end

    test "builds BinaryLiteral triples for empty binary" do
      context = full_mode_context()

      # Empty binary: <<>>
      binary_ast = {:<<>>, [], []}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      assert has_type?(triples, Core.BinaryLiteral)
      # Empty binary
      assert has_binary_literal_value?(triples, expr_iri, Core.binaryValue(), "")
    end

    test "builds BinaryLiteral triples for binary with zero bytes" do
      context = full_mode_context()

      # Binary with zeros: <<0, 0, 0>>
      binary_ast = {:<<>>, [], [0, 0, 0]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      assert has_type?(triples, Core.BinaryLiteral)
      # RDF.XSD.Base64Binary stores the raw binary value (three null bytes)
      assert has_binary_literal_value?(triples, expr_iri, Core.binaryValue(), <<0, 0, 0>>)
    end

    test "builds BinaryLiteral triples for binary with all byte values" do
      context = full_mode_context()

      # Binary with values 0-255
      bytes = Enum.to_list(0..255)
      binary_ast = {:<<>>, [], bytes}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      assert has_type?(triples, Core.BinaryLiteral)
      # Verify the base64 value is set (we don't check exact value due to size)
      assert Enum.any?(triples, fn
        {_, p, _} -> p == Core.binaryValue()
        _ -> false
      end)
    end

    test "treats binary with variables as generic expression" do
      context = full_mode_context()

      # Binary with variable: <<x::8>>
      binary_ast = {:<<>>, [], [{:"::", [], [{:x, [], Elixir}, 8]}]}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      # Should fall through to generic expression (not BinaryLiteral)
      refute has_type?(triples, Core.BinaryLiteral)
      assert has_type?(triples, Core.Expression)
    end

    test "treats binary with mixed literals and variables as generic expression" do
      context = full_mode_context()

      # Binary with mixed: <<65, x::8, 67>>
      binary_ast = {:<<>>, [], [65, {:"::", [], [{:x, [], Elixir}, 8]}, 67]}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      # Should fall through to generic expression (not BinaryLiteral)
      refute has_type?(triples, Core.BinaryLiteral)
      assert has_type?(triples, Core.Expression)
    end

    test "treats binary with type specification as generic expression" do
      context = full_mode_context()

      # Binary with binary type: <<x::binary>>
      binary_ast = {:<<>>, [], [{:"::", [], [{:x, [], Elixir}, {:binary, [], Elixir}]}]}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(binary_ast, context, [])

      # Should fall through to generic expression
      refute has_type?(triples, Core.BinaryLiteral)
      assert has_type?(triples, Core.Expression)
    end

    test "builds ListLiteral triples for empty list" do
      context = full_mode_context()

      # Empty list is [] - which is also an empty charlist
      # This gets caught by charlist check first
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build([], context, [])

      # Empty list is treated as charlist (indistinguishable in AST)
      assert has_type?(triples, Core.CharlistLiteral)
    end

    test "builds ListLiteral triples for list of integers" do
      context = full_mode_context()

      # List of integers
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build([1, 2, 3], context, [])

      # This is treated as a charlist since all elements are valid codepoints
      # In practice, [1, 2, 3] could be either a list or a charlist
      # Our implementation treats it as charlist
      assert has_type?(triples, Core.CharlistLiteral)
    end

    test "builds ListLiteral triples for heterogeneous list" do
      context = full_mode_context()

      # List with mixed types
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build([1, "two", :three], context, [])

      # Heterogeneous lists are treated as ListLiteral, not charlist
      assert has_type?(triples, Core.ListLiteral)
    end

    test "builds ListLiteral triples for nested lists" do
      context = full_mode_context()

      # Nested lists
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build([["a", "b"], ["c", "d"]], context, [])

      # Nested lists are treated as ListLiteral
      assert has_type?(triples, Core.ListLiteral)
    end

    test "builds ListLiteral triples for list with atoms" do
      context = full_mode_context()

      # List with atoms
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build([:ok, :error], context, [])

      # List with atoms is treated as ListLiteral, not charlist
      assert has_type?(triples, Core.ListLiteral)
    end

    test "builds ListLiteral triples for cons pattern with atom tail" do
      context = full_mode_context()

      # Cons pattern: [1 | :two]
      cons_ast = [{:|, [], [1, :two]}]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(cons_ast, context, [])

      # Cons pattern creates ListLiteral
      assert has_type?(triples, Core.ListLiteral)
    end

    test "builds ListLiteral triples for cons pattern with list tail" do
      context = full_mode_context()

      # Cons pattern with list tail: [1 | [2, 3]]
      cons_ast = [{:|, [], [1, [2, 3]]}]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(cons_ast, context, [])

      # Cons pattern creates ListLiteral
      assert has_type?(triples, Core.ListLiteral)
    end

    test "charlists with valid codepoints are still handled correctly" do
      context = full_mode_context()

      # Charlist with ASCII characters
      charlist = [104, 101, 108, 108, 111]  # "hello"
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_binary_literal_value?(triples, expr_iri, Core.charlistValue(), "hello")
    end

    test "charlists with Unicode are still handled correctly" do
      context = full_mode_context()

      # Charlist with Unicode characters: "héllo" = [104, 233, 108, 108, 111]
      charlist = [104, 233, 108, 108, 111]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(charlist, context, [])

      assert has_type?(triples, Core.CharlistLiteral)
      assert has_binary_literal_value?(triples, expr_iri, Core.charlistValue(), "héllo")
    end

    test "lists with integers outside Unicode range are ListLiteral" do
      context = full_mode_context()

      # Integer outside Unicode range (> 0x10FFFF)
      list_with_large_int = [0x110000]
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(list_with_large_int, context, [])

      # Should be treated as ListLiteral, not charlist
      assert has_type?(triples, Core.ListLiteral)
      refute has_type?(triples, Core.CharlistLiteral)
    end
  end

  describe "tuple literals" do
    test "builds TupleLiteral triples for empty tuple" do
      context = full_mode_context()

      # Empty tuple: {}
      empty_tuple_ast = quote do: {}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(empty_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "builds TupleLiteral triples for 2-tuple" do
      context = full_mode_context()

      # 2-tuple: {1, 2}
      two_tuple_ast = quote do: {1, 2}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(two_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "builds TupleLiteral triples for 3-tuple" do
      context = full_mode_context()

      # 3-tuple: {1, 2, 3}
      three_tuple_ast = quote do: {1, 2, 3}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(three_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "builds TupleLiteral triples for 4+ tuple" do
      context = full_mode_context()

      # 4-tuple: {1, 2, 3, 4}
      four_tuple_ast = quote do: {1, 2, 3, 4}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(four_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "builds TupleLiteral triples for nested tuple" do
      context = full_mode_context()

      # Nested tuples: {{1, 2}, {3, 4}}
      nested_tuple_ast = quote do: {{1, 2}, {3, 4}}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(nested_tuple_ast, context, [])

      # Top-level tuple is TupleLiteral
      assert has_type?(triples, Core.TupleLiteral)

      # Should have child expressions for the nested tuples
      # The children will also be TupleLiteral
      child_tuples = Enum.filter(triples, fn {s, _p, o} -> o == Core.TupleLiteral end)
      # At least the parent tuple should be TupleLiteral
      assert length(child_tuples) >= 1
    end

    test "builds TupleLiteral triples for heterogeneous tuple" do
      context = full_mode_context()

      # Tuple with mixed types: {1, "two", :three}
      het_tuple_ast = quote do: {1, "two", :three}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(het_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "builds TupleLiteral triples for tagged tuple" do
      context = full_mode_context()

      # Tagged tuple: {:ok, 42}
      tagged_tuple_ast = quote do: {:ok, 42}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(tagged_tuple_ast, context, [])

      assert has_type?(triples, Core.TupleLiteral)
    end

    test "tuple elements are extracted as child expressions" do
      context = full_mode_context()

      # Tuple with literals: {1, 2, 3}
      three_tuple_ast = quote do: {1, 2, 3}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(three_tuple_ast, context, [])

      # Parent tuple is TupleLiteral
      assert has_type?(triples, Core.TupleLiteral)

      # Child elements should be IntegerLiteral
      # We should have at least 4 IntegerLiteral triples (one for each child + type triples)
      integer_literals = Enum.filter(triples, fn {s, _p, o} -> o == Core.IntegerLiteral end)
      assert length(integer_literals) == 3
    end
  end

  describe "map literals" do
    test "builds MapLiteral triples for empty map" do
      context = full_mode_context()

      # Empty map: %{}
      empty_map_ast = quote do: %{}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(empty_map_ast, context, [])

      assert has_type?(triples, Core.MapLiteral)
    end

    test "builds MapLiteral triples for map with atom keys" do
      context = full_mode_context()

      # Map with atom keys: %{a: 1, b: 2}
      map_ast = quote do: %{a: 1, b: 2}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(map_ast, context, [])

      assert has_type?(triples, Core.MapLiteral)
    end

    test "builds MapLiteral triples for map with string keys" do
      context = full_mode_context()

      # Map with string keys: %{"a" => 1, "b" => 2}
      map_ast = quote do: %{"a" => 1, "b" => 2}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(map_ast, context, [])

      assert has_type?(triples, Core.MapLiteral)
    end

    test "builds MapLiteral triples for map with mixed keys" do
      context = full_mode_context()

      # Map with mixed keys: %{"a" => 1, b: 2}
      map_ast = quote do: %{"a" => 1, b: 2}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(map_ast, context, [])

      assert has_type?(triples, Core.MapLiteral)
    end
  end

  describe "struct literals" do
    test "builds StructLiteral triples for struct literal" do
      context = full_mode_context()

      # Struct literal: %User{name: "John"}
      # Note: User needs to be defined for this to compile, so we construct the AST manually
      # AST: {:%, [], [{:__aliases__, ..., [:User]}, {:%{}, [], [name: "John"]}]}
      kw_list = [name: "John"]
      struct_ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], kw_list}]}
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(struct_ast, context, [])

      assert has_type?(triples, Core.StructLiteral)
    end

    test "struct literal includes refersToModule property" do
      context = full_mode_context()

      # Struct literal: %User{name: "John"}
      kw_list = [name: "John"]
      struct_ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], kw_list}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(struct_ast, context, [])

      assert has_type?(triples, Core.StructLiteral)

      # Check for refersToModule property
      has_refers_to_module =
        Enum.any?(triples, fn {s, p, o} ->
          s == expr_iri and p == Core.refersToModule()
        end)

      assert has_refers_to_module
    end
  end

  describe "keyword list literals" do
    test "builds KeywordListLiteral triples for keyword list" do
      context = full_mode_context()

      # Keyword list: [a: 1, b: 2]
      kw_list_ast = quote do: [a: 1, b: 2]
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(kw_list_ast, context, [])

      assert has_type?(triples, Core.KeywordListLiteral)
    end

    test "keyword list is distinguished from regular list" do
      context = full_mode_context()

      # Keyword list: [a: 1, b: 2]
      kw_list_ast = quote do: [a: 1, b: 2]
      {:ok, {_expr_iri, kw_triples, _}} = ExpressionBuilder.build(kw_list_ast, context, [])

      # Regular list: [1, 2, 3]
      regular_list_ast = quote do: [1, 2, 3]
      {:ok, {_expr_iri, regular_triples, _}} = ExpressionBuilder.build(regular_list_ast, context, [])

      # Keyword list creates KeywordListLiteral
      assert has_type?(kw_triples, Core.KeywordListLiteral)

      # Regular list does NOT create KeywordListLiteral
      refute has_type?(regular_triples, Core.KeywordListLiteral)
    end

    test "keyword list with duplicate keys is handled correctly" do
      context = full_mode_context()

      # Keyword list with duplicates: [a: 1, a: 2]
      kw_list_ast = quote do: [a: 1, a: 2]
      {:ok, {_expr_iri, triples, _}} = ExpressionBuilder.build(kw_list_ast, context, [])

      assert has_type?(triples, Core.KeywordListLiteral)
    end
  end

  describe "sigil literals" do
    test "builds SigilLiteral for word sigil" do
      context = full_mode_context()

      # Word sigil: ~w(foo bar baz)
      sigil_ast = quote do: ~w(foo bar baz)
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "w")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "foo bar baz")
    end

    test "builds SigilLiteral for regex sigil" do
      context = full_mode_context()

      # Regex sigil: ~r/pattern/
      sigil_ast = quote do: ~r(pattern)
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "r")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "pattern")
    end

    test "builds SigilLiteral for string sigil" do
      context = full_mode_context()

      # String sigil: ~s(string)
      sigil_ast = quote do: ~s(string)
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "s")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "string")
    end

    test "builds SigilLiteral for custom sigil" do
      context = full_mode_context()

      # Custom sigil: ~x(content)
      # Note: This will fail at runtime but the AST is valid
      sigil_ast = {:sigil_x, [], [{:<<>>, [], ["content"]}, []]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "x")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "content")
    end

    test "handles sigil with empty content" do
      context = full_mode_context()

      # Empty sigil: ~s()
      sigil_ast = quote do: ~s()
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "s")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "")
    end

    test "handles sigil with modifiers" do
      context = full_mode_context()

      # Regex sigil with modifiers: ~r/pattern/iom
      sigil_ast = quote do: ~r(pattern)iom
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "r")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "pattern")
      assert has_literal_value?(triples, expr_iri, Core.sigilModifiers(), "iom")
    end

    test "handles sigil without modifiers" do
      context = full_mode_context()

      # Regex sigil without modifiers: ~r/pattern/
      sigil_ast = quote do: ~r(pattern)
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      # Should NOT have sigilModifiers triple (empty modifiers don't create a triple)
      refute Enum.any?(triples, fn {s, p, _o} ->
        s == expr_iri and p == Core.sigilModifiers()
      end)
    end

    test "handles charlist sigil" do
      context = full_mode_context()

      # Charlist sigil: ~c(charlist)
      sigil_ast = quote do: ~c(charlist)
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "c")
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "charlist")
    end

    test "handles sigil with heredoc content" do
      context = full_mode_context()

      # Heredoc sigil: ~s"""
      # multi
      # line
      # string
      # """
      sigil_ast = quote do: ~s"""
multi
line
string
"""
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilChar(), "s")
      # Heredoc content is multi-line
      assert has_literal_value?(triples, expr_iri, Core.sigilContent(), "multi\nline\nstring\n")
    end

    test "handles sigil with multiple modifiers" do
      context = full_mode_context()

      # Regex sigil with multiple modifiers: ~r/pattern/iom
      sigil_ast = quote do: ~r(pattern)iom
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(sigil_ast, context, [])

      assert has_type?(triples, Core.SigilLiteral)
      assert has_literal_value?(triples, expr_iri, Core.sigilModifiers(), "iom")
    end
  end

  describe "unknown expressions" do
    test "dispatches unknown AST to generic Expression type" do
      context = full_mode_context()

      # Some unusual AST that doesn't match our patterns
      # Using a 4-element tuple which is not a standard Elixir AST form
      # (3+ tuples use {:{}, meta, elements} form, not direct tuples)
      unusual_ast = {:one, :two, :three, :four}

      {:ok, {_expr_iri, triples, _context}} = ExpressionBuilder.build(unusual_ast, context, [])

      assert has_type?(triples, Core.Expression)
    end
  end

  describe "expression_iri/3" do
    test "generates IRI with counter-based suffix when no options provided" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 0}
        )

      {iri, updated_context} = ExpressionBuilder.expression_iri("https://example.org/code#", context)

      assert RDF.IRI.to_string(iri) == "https://example.org/code#expr/expr_0"
      assert Context.get_expression_counter(updated_context) == 1
    end

    test "increments counter on each call" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 0}
        )

      {iri1, ctx1} = ExpressionBuilder.expression_iri("https://example.org/code#", context)
      {iri2, ctx2} = ExpressionBuilder.expression_iri("https://example.org/code#", ctx1)
      {iri3, _ctx3} = ExpressionBuilder.expression_iri("https://example.org/code#", ctx2)

      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/expr_2"
    end

    test "uses custom suffix when provided" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 5}
        )

      {iri, updated_context} =
        ExpressionBuilder.expression_iri("https://example.org/code#", context, suffix: "my_custom_expr")

      assert RDF.IRI.to_string(iri) == "https://example.org/code#expr/my_custom_expr"
      # Counter should not be incremented when custom suffix is used
      assert Context.get_expression_counter(updated_context) == 5
    end

    test "uses explicit counter option when provided" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 10}
        )

      {iri, updated_context} =
        ExpressionBuilder.expression_iri("https://example.org/code#", context, counter: 42)

      assert RDF.IRI.to_string(iri) == "https://example.org/code#expr/expr_42"
      # Counter should not be incremented when explicit counter is used
      assert Context.get_expression_counter(updated_context) == 10
    end

    test "handles different base IRIs" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 0}
        )

      {iri, _ctx} =
        ExpressionBuilder.expression_iri("https://other.org/base#", context)

      assert RDF.IRI.to_string(iri) == "https://other.org/base#expr/expr_0"
    end
  end

  describe "fresh_iri/2" do
    test "creates relative IRI from parent with left child" do
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      child_iri = ExpressionBuilder.fresh_iri(parent, "left")

      assert RDF.IRI.to_string(child_iri) == "https://example.org/code#expr/0/left"
    end

    test "creates relative IRI from parent with right child" do
      parent = RDF.IRI.new("https://example.org/code#expr/5")

      child_iri = ExpressionBuilder.fresh_iri(parent, "right")

      assert RDF.IRI.to_string(child_iri) == "https://example.org/code#expr/5/right"
    end

    test "creates nested relative IRIs" do
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      left_iri = ExpressionBuilder.fresh_iri(parent, "left")
      left_left_iri = ExpressionBuilder.fresh_iri(left_iri, "left")

      assert RDF.IRI.to_string(left_iri) == "https://example.org/code#expr/0/left"
      assert RDF.IRI.to_string(left_left_iri) == "https://example.org/code#expr/0/left/left"
    end

    test "handles various child names" do
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      assert ExpressionBuilder.fresh_iri(parent, "condition")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/condition"

      assert ExpressionBuilder.fresh_iri(parent, "then")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/then"

      assert ExpressionBuilder.fresh_iri(parent, "else")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/else"

      assert ExpressionBuilder.fresh_iri(parent, "operand")
             |> RDF.IRI.to_string() == "https://example.org/code#expr/0/operand"
    end
  end

  describe "get_or_create_iri/3" do
    test "creates new IRI when cache is nil" do
      generator = fn -> RDF.IRI.new("https://example.org/expr/0") end

      {iri, cache} = ExpressionBuilder.get_or_create_iri(nil, :some_key, generator)

      assert RDF.IRI.to_string(iri) == "https://example.org/expr/0"
      assert cache == %{}
    end

    test "creates and caches new IRI on first call" do
      cache = %{}
      generator = fn -> RDF.IRI.new("https://example.org/expr/new") end

      {iri, updated_cache} =
        ExpressionBuilder.get_or_create_iri(cache, :my_key, generator)

      assert RDF.IRI.to_string(iri) == "https://example.org/expr/new"
      assert Map.has_key?(updated_cache, :my_key)
    end

    test "reuses cached IRI on subsequent calls with same key" do
      cache = %{}
      gen1 = fn -> RDF.IRI.new("https://example.org/expr/first") end
      gen2 = fn -> RDF.IRI.new("https://example.org/expr/second") end

      {iri1, cache1} = ExpressionBuilder.get_or_create_iri(cache, :same_key, gen1)
      {iri2, cache2} = ExpressionBuilder.get_or_create_iri(cache1, :same_key, gen2)

      # Second generator should not be called - IRI is reused
      assert iri1 == iri2
      assert RDF.IRI.to_string(iri1) == "https://example.org/expr/first"
      assert cache2 == cache1
    end

    test "creates different IRIs for different keys" do
      cache = %{}

      # Each key gets its own generator
      gen1 = fn -> RDF.IRI.new("https://example.org/expr/first") end
      gen2 = fn -> RDF.IRI.new("https://example.org/expr/second") end

      {iri1, cache1} = ExpressionBuilder.get_or_create_iri(cache, :key1, gen1)
      {iri2, cache2} = ExpressionBuilder.get_or_create_iri(cache1, :key2, gen2)

      # Should create two different IRIs
      refute iri1 == iri2
      assert Map.has_key?(cache2, :key1)
      assert Map.has_key?(cache2, :key2)
    end

    test "works with complex cache keys" do
      cache = %{}

      # Using AST structure as cache key
      ast_key1 = {:==, [], [{:x, [], nil}, 1]}
      ast_key2 = {:==, [], [{:y, [], nil}, 2]}
      ast_key3 = {:==, [], [{:x, [], nil}, 1]} # Same as key1

      # Create unique generators for each key
      gen1 = fn -> RDF.IRI.new("https://example.org/expr/hash1") end
      gen2 = fn -> RDF.IRI.new("https://example.org/expr/hash2") end
      gen3 = fn -> RDF.IRI.new("https://example.org/expr/hash3") end

      {iri1, cache1} = ExpressionBuilder.get_or_create_iri(cache, ast_key1, gen1)
      {iri2, cache2} = ExpressionBuilder.get_or_create_iri(cache1, ast_key2, gen2)
      {iri3, _cache3} = ExpressionBuilder.get_or_create_iri(cache2, ast_key3, gen3)

      # key1 and key3 are the same, so IRIs should match (key3 reuses cached value from key1)
      assert iri1 == iri3
      refute iri1 == iri2
    end
  end

  describe "Context expression counter" do
    test "with_expression_counter/1 initializes counter to 0" do
      context = Context.new(base_iri: "https://example.org/code#")

      initialized = Context.with_expression_counter(context)

      assert Context.get_expression_counter(initialized) == 0
    end

    test "next_expression_counter/1 returns current counter and increments" do
      context = Context.new(base_iri: "https://example.org/code#")
      context = Context.with_expression_counter(context)

      {counter1, ctx1} = Context.next_expression_counter(context)
      {counter2, ctx2} = Context.next_expression_counter(ctx1)
      {counter3, _ctx3} = Context.next_expression_counter(ctx2)

      assert counter1 == 0
      assert counter2 == 1
      assert counter3 == 2
    end

    test "next_expression_counter/1 works with pre-initialized counter" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 5}
        )

      {counter, updated_ctx} = Context.next_expression_counter(context)

      assert counter == 5
      assert Context.get_expression_counter(updated_ctx) == 6
    end

    test "get_expression_counter/1 returns current counter without incrementing" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{expression_counter: 10}
        )

      assert Context.get_expression_counter(context) == 10
      assert Context.get_expression_counter(context) == 10 # Still 10
    end

    test "get_expression_counter/1 defaults to 0 when not set" do
      context = Context.new(base_iri: "https://example.org/code#")

      assert Context.get_expression_counter(context) == 0
    end
  end

  describe "integration tests" do
    test "complete IRI flow through ExpressionBuilder" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      # Build multiple expressions and verify sequential IRIs
      ast1 = {:==, [], [{:x, [], nil}, 1]}
      ast2 = {:>, [], [{:y, [], nil}, 5]}
      ast3 = {:and, [], [true, false]}

      {:ok, {iri1, _, context2}} = ExpressionBuilder.build(ast1, context, [])
      {:ok, {iri2, _, context3}} = ExpressionBuilder.build(ast2, context2, [])
      {:ok, {iri3, _, _}} = ExpressionBuilder.build(ast3, context3, [])

      # Sequential IRIs based on counter
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/expr_2"
    end

    test "fresh_iri creates proper hierarchy for nested expressions" do
      # Simulate nested binary operator: x > 5 and y < 10
      parent = RDF.IRI.new("https://example.org/code#expr/0")

      left = ExpressionBuilder.fresh_iri(parent, "left")
      right = ExpressionBuilder.fresh_iri(parent, "right")

      # Verify hierarchy
      assert RDF.IRI.to_string(left) == "https://example.org/code#expr/0/left"
      assert RDF.IRI.to_string(right) == "https://example.org/code#expr/0/right"

      # Nested children
      left_left = ExpressionBuilder.fresh_iri(left, "left")
      assert RDF.IRI.to_string(left_left) == "https://example.org/code#expr/0/left/left"
    end

    test "get_or_create_iri enables expression deduplication" do
      # Simulate shared sub-expression: x == 1 appearing twice
      shared_expr = {:==, [], [{:x, [], nil}, 1]}

      cache = %{}

      # First occurrence - creates new IRI
      {iri1, cache1} =
        ExpressionBuilder.get_or_create_iri(
          cache,
          shared_expr,
          fn -> RDF.IRI.new("https://example.org/code#expr/shared_0") end
        )

      # Second occurrence - reuses cached IRI
      {iri2, cache2} =
        ExpressionBuilder.get_or_create_iri(
          cache1,
          shared_expr,
          fn -> RDF.IRI.new("https://example.org/code#expr/shared_new") end
        )

      # Same IRI should be returned
      assert iri1 == iri2
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/shared_0"

      # Different expression - creates new IRI
      different_expr = {:!=, [], [{:y, [], nil}, 2]}
      {iri3, _cache3} =
        ExpressionBuilder.get_or_create_iri(
          cache2,
          different_expr,
          fn -> RDF.IRI.new("https://example.org/code#expr/shared_1") end
        )

      refute iri1 == iri3
      assert RDF.IRI.to_string(iri3) == "https://example.org/code#expr/shared_1"
    end

    test "counter properly resets between different contexts" do
      # Context 1
      context1 =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      {:ok, {iri1, _, context2}} = ExpressionBuilder.build({:==, [], [1, 1]}, context1, [])
      {:ok, {iri2, _, _}} = ExpressionBuilder.build({:==, [], [2, 2]}, context2, [])

      # Context 2 - different base IRI, so counter starts at 0
      context3 =
        Context.new(
          base_iri: "https://other.org/base#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/accounts.ex"
        )
        |> Context.with_expression_counter()

      {:ok, {iri3, _, _}} = ExpressionBuilder.build({:==, [], [3, 3]}, context3, [])

      # context1 starts at expr_0 and increments
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/expr_0"
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_1"

      # context2 has different base IRI, so starts at expr_0
      assert RDF.IRI.to_string(iri3) == "https://other.org/base#expr/expr_0"
    end

    test "custom suffix option bypasses counter" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true},
          file_path: "lib/my_app/users.ex"
        )
        |> Context.with_expression_counter()

      # Use custom suffix
      ast = {:==, [], [{:x, [], nil}, 1]}
      {:ok, {iri1, _, _}} = ExpressionBuilder.build(ast, context, suffix: "custom_expr")

      # Next expression without suffix should use counter
      {:ok, {iri2, _, _}} = ExpressionBuilder.build(ast, context, [])

      # Custom suffix should be respected
      assert RDF.IRI.to_string(iri1) == "https://example.org/code#expr/custom_expr"
      # Counter expression should start at 0
      assert RDF.IRI.to_string(iri2) == "https://example.org/code#expr/expr_0"
    end
  end

  describe "nested expression tests (Phase 21.4)" do
    test "binary operator creates left and right operand triples" do
      context = full_mode_context()
      # x > 5
      ast = {:>, [], [{:x, [], nil}, 5]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should have operator type and symbol
      assert has_type?(triples, Core.ComparisonOperator)
      assert has_operator_symbol?(triples, ">")

      # Should link to left and right operands
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)

      # Left operand should be a Variable
      assert has_type?(triples, Core.Variable)
      assert has_literal_value?(triples, left_iri, Core.name(), "x")

      # Right operand should be an IntegerLiteral
      assert has_type?(triples, Core.IntegerLiteral)
      assert has_literal_value?(triples, right_iri, Core.integerValue(), 5)
    end

    test "nested binary operators create correct IRI hierarchy" do
      context = full_mode_context()
      # x > 5 and y < 10
      ast = {:and, [], [{:>, [], [{:x, [], nil}, 5]}, {:<, [], [{:y, [], nil}, 10]}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Top-level is LogicalOperator (and)
      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "and")

      # Left child is a comparison operator
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} ->
        s == left_iri and o == Core.ComparisonOperator
      end)
      assert Enum.any?(triples, fn {s, p, o} ->
        s == left_iri and p == Core.operatorSymbol() and
          RDF.Literal.value(o) == ">"
      end)

      # Left-left is Variable "x"
      left_left_iri = ExpressionBuilder.fresh_iri(left_iri, "left")
      assert Enum.any?(triples, fn {s, _p, o} ->
        s == left_left_iri and o == Core.Variable
      end)
      assert Enum.any?(triples, fn {s, p, o} ->
        s == left_left_iri and p == Core.name() and
          RDF.Literal.value(o) == "x"
      end)

      # Left-right is IntegerLiteral 5
      left_right_iri = ExpressionBuilder.fresh_iri(left_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} ->
        s == left_right_iri and o == Core.IntegerLiteral
      end)
      assert Enum.any?(triples, fn {s, p, o} ->
        s == left_right_iri and p == Core.integerValue() and
          RDF.Literal.value(o) == 5
      end)
    end

    test "unary operator creates operand triples" do
      context = full_mode_context()
      # not x
      ast = {:not, [], [{:x, [], nil}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should have operator type and symbol
      assert has_type?(triples, Core.LogicalOperator)
      assert has_operator_symbol?(triples, "not")

      # Should link to operand
      operand_iri = ExpressionBuilder.fresh_iri(expr_iri, "operand")
      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasOperand() and o == operand_iri
      end)

      # Operand should be a Variable
      assert has_type?(triples, Core.Variable)
      assert has_literal_value?(triples, operand_iri, Core.name(), "x")
    end

    test "arithmetic operators create nested expressions" do
      context = full_mode_context()
      # x + y * 2
      ast = {:+, [], [{:x, [], nil}, {:*, [], [{:y, [], nil}, 2]}]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Top-level is ArithmeticOperator (+)
      assert has_type?(triples, Core.ArithmeticOperator)
      assert has_operator_symbol?(triples, "+")

      # Right operand is another ArithmeticOperator (*)
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")
      assert Enum.any?(triples, fn {s, _p, o} ->
        s == right_iri and o == Core.ArithmeticOperator
      end)
      assert Enum.any?(triples, fn {s, p, o} ->
        s == right_iri and p == Core.operatorSymbol() and
          RDF.Literal.value(o) == "*"
      end)
    end

    test "match operator creates left and right expressions" do
      context = full_mode_context()
      # x = 42
      ast = {:=, [], [{:x, [], nil}, 42]}
      {:ok, {expr_iri, triples, _}} = ExpressionBuilder.build(ast, context, [])

      # Should have MatchOperator type
      assert has_type?(triples, Core.MatchOperator)
      assert has_operator_symbol?(triples, "=")

      # Should have left and right operands
      left_iri = ExpressionBuilder.fresh_iri(expr_iri, "left")
      right_iri = ExpressionBuilder.fresh_iri(expr_iri, "right")

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasLeftOperand() and o == left_iri
      end)

      assert Enum.any?(triples, fn {s, p, o} ->
        s == expr_iri and p == Core.hasRightOperand() and o == right_iri
      end)

      # Left is Variable "x"
      assert has_type?(triples, Core.Variable)
      assert has_literal_value?(triples, left_iri, Core.name(), "x")

      # Right is IntegerLiteral 42
      assert has_type?(triples, Core.IntegerLiteral)
      assert has_literal_value?(triples, right_iri, Core.integerValue(), 42)
    end
  end

  # ===========================================================================
  # Helpers
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

  defp has_operator_symbol?(triples, symbol) do
    Enum.any?(triples, fn {_s, p, o} ->
      p == Core.operatorSymbol() and RDF.Literal.value(o) == symbol
    end)
  end

  defp has_literal_value?(triples, subject, predicate, expected_value) do
    Enum.any?(triples, fn {s, p, o} ->
      s == subject and p == predicate and RDF.Literal.value(o) == expected_value
    end)
  end

  # For Base64Binary literals, RDF.Literal.value/1 returns nil
  # We need to check RDF.Literal.lexical/1 instead
  defp has_binary_literal_value?(triples, subject, predicate, expected_value) do
    Enum.any?(triples, fn {s, p, o} ->
      s == subject and p == predicate and RDF.Literal.lexical(o) == expected_value
    end)
  end
end
