defmodule ElixirOntologies.Builders.ExceptionBuilderTest do
  @moduledoc """
  Tests for the ExceptionBuilder module.

  These tests verify RDF triple generation for exception handling structures
  including try expressions, raise expressions, throw expressions, and exit expressions.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Builders.{ExceptionBuilder, Context}
  alias ElixirOntologies.Extractors.Exception

  alias ElixirOntologies.Extractors.Exception.{
    RescueClause,
    CatchClause,
    RaiseExpression,
    ThrowExpression,
    ExitExpression
  }

  alias ElixirOntologies.NS.Core

  @base_iri "https://example.org/code#"

  # ===========================================================================
  # Try IRI Generation Tests
  # ===========================================================================

  describe "try_iri/3" do
    test "generates IRI with containing function and index" do
      iri = ExceptionBuilder.try_iri(@base_iri, "MyApp/foo/1", 0)
      assert to_string(iri) == "https://example.org/code#try/MyApp/foo/1/0"
    end

    test "increments index for multiple try expressions" do
      iri0 = ExceptionBuilder.try_iri(@base_iri, "MyApp/bar/2", 0)
      iri1 = ExceptionBuilder.try_iri(@base_iri, "MyApp/bar/2", 1)

      assert to_string(iri0) == "https://example.org/code#try/MyApp/bar/2/0"
      assert to_string(iri1) == "https://example.org/code#try/MyApp/bar/2/1"
    end

    test "handles RDF.IRI as base" do
      base = RDF.iri(@base_iri)
      iri = ExceptionBuilder.try_iri(base, "Test/func/0", 5)
      assert to_string(iri) == "https://example.org/code#try/Test/func/0/5"
    end
  end

  # ===========================================================================
  # Raise IRI Generation Tests
  # ===========================================================================

  describe "raise_iri/3" do
    test "generates IRI with containing function and index" do
      iri = ExceptionBuilder.raise_iri(@base_iri, "MyApp/run/1", 0)
      assert to_string(iri) == "https://example.org/code#raise/MyApp/run/1/0"
    end

    test "handles RDF.IRI as base" do
      base = RDF.iri(@base_iri)
      iri = ExceptionBuilder.raise_iri(base, "Test/error/0", 3)
      assert to_string(iri) == "https://example.org/code#raise/Test/error/0/3"
    end
  end

  # ===========================================================================
  # Throw IRI Generation Tests
  # ===========================================================================

  describe "throw_iri/3" do
    test "generates IRI with containing function and index" do
      iri = ExceptionBuilder.throw_iri(@base_iri, "MyApp/process/2", 0)
      assert to_string(iri) == "https://example.org/code#throw/MyApp/process/2/0"
    end

    test "handles RDF.IRI as base" do
      base = RDF.iri(@base_iri)
      iri = ExceptionBuilder.throw_iri(base, "Test/abort/1", 2)
      assert to_string(iri) == "https://example.org/code#throw/Test/abort/1/2"
    end
  end

  # ===========================================================================
  # Exit IRI Generation Tests
  # ===========================================================================

  describe "exit_iri/3" do
    test "generates IRI with containing function and index" do
      iri = ExceptionBuilder.exit_iri(@base_iri, "MyApp/terminate/1", 0)
      assert to_string(iri) == "https://example.org/code#exit/MyApp/terminate/1/0"
    end

    test "increments index for multiple exit expressions" do
      iri0 = ExceptionBuilder.exit_iri(@base_iri, "MyApp/stop/0", 0)
      iri1 = ExceptionBuilder.exit_iri(@base_iri, "MyApp/stop/0", 1)

      assert to_string(iri0) == "https://example.org/code#exit/MyApp/stop/0/0"
      assert to_string(iri1) == "https://example.org/code#exit/MyApp/stop/0/1"
    end

    test "handles RDF.IRI as base" do
      base = RDF.iri(@base_iri)
      iri = ExceptionBuilder.exit_iri(base, "Test/shutdown/0", 3)
      assert to_string(iri) == "https://example.org/code#exit/Test/shutdown/0/3"
    end
  end

  # ===========================================================================
  # Try Expression Building Tests
  # ===========================================================================

  describe "build_try/3" do
    test "generates type triple for try expression" do
      try_expr = %Exception{
        body: {:risky_call, [], []},
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.TryExpression
    end

    test "generates hasRescueClause triple when rescue clauses present" do
      try_expr = %Exception{
        body: :ok,
        has_rescue: true,
        rescue_clauses: [%RescueClause{body: :error, is_catch_all: true}],
        catch_clauses: [],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/handle/0",
          index: 0
        )

      rescue_triple = find_triple(triples, expr_iri, Core.hasRescueClause())
      assert rescue_triple != nil
      assert RDF.Literal.value(elem(rescue_triple, 2)) == true
    end

    test "does not generate hasRescueClause when no rescue clauses" do
      try_expr = %Exception{
        body: :ok,
        has_rescue: false,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      rescue_triple = find_triple(triples, expr_iri, Core.hasRescueClause())
      assert rescue_triple == nil
    end

    test "generates hasCatchClause triple when catch clauses present" do
      try_expr = %Exception{
        body: :ok,
        has_catch: true,
        rescue_clauses: [],
        catch_clauses: [%CatchClause{kind: :throw, pattern: :done, body: :ok}],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/handle/0",
          index: 0
        )

      catch_triple = find_triple(triples, expr_iri, Core.hasCatchClause())
      assert catch_triple != nil
      assert RDF.Literal.value(elem(catch_triple, 2)) == true
    end

    test "does not generate hasCatchClause when no catch clauses" do
      try_expr = %Exception{
        body: :ok,
        has_catch: false,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      catch_triple = find_triple(triples, expr_iri, Core.hasCatchClause())
      assert catch_triple == nil
    end

    test "generates hasAfterClause triple when after block present" do
      try_expr = %Exception{
        body: :ok,
        has_after: true,
        after_body: {:cleanup, [], []},
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/handle/0",
          index: 0
        )

      after_triple = find_triple(triples, expr_iri, Core.hasAfterClause())
      assert after_triple != nil
      assert RDF.Literal.value(elem(after_triple, 2)) == true
    end

    test "does not generate hasAfterClause when no after block" do
      try_expr = %Exception{
        body: :ok,
        has_after: false,
        after_body: nil,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      after_triple = find_triple(triples, expr_iri, Core.hasAfterClause())
      assert after_triple == nil
    end

    test "generates hasElseClause triple when else clauses present" do
      try_expr = %Exception{
        body: :ok,
        has_else: true,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: [%Exception.ElseClause{pattern: {:ok, :result}, body: :result}]
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/handle/0",
          index: 0
        )

      else_triple = find_triple(triples, expr_iri, Core.hasElseClause())
      assert else_triple != nil
      assert RDF.Literal.value(elem(else_triple, 2)) == true
    end

    test "does not generate hasElseClause when no else clauses" do
      try_expr = %Exception{
        body: :ok,
        has_else: false,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      else_triple = find_triple(triples, expr_iri, Core.hasElseClause())
      assert else_triple == nil
    end

    test "generates all clause triples for complete try" do
      try_expr = %Exception{
        body: :risky,
        has_rescue: true,
        has_catch: true,
        has_after: true,
        has_else: true,
        rescue_clauses: [%RescueClause{body: :err}],
        catch_clauses: [%CatchClause{pattern: :x, body: :x}],
        else_clauses: [%Exception.ElseClause{pattern: :ok, body: :ok}],
        after_body: :cleanup
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/complete/0",
          index: 0
        )

      assert find_triple(triples, expr_iri, Core.hasRescueClause()) != nil
      assert find_triple(triples, expr_iri, Core.hasCatchClause()) != nil
      assert find_triple(triples, expr_iri, Core.hasAfterClause()) != nil
      assert find_triple(triples, expr_iri, Core.hasElseClause()) != nil
    end
  end

  # ===========================================================================
  # Raise Expression Building Tests
  # ===========================================================================

  describe "build_raise/3" do
    test "generates type triple for raise expression" do
      raise_expr = %RaiseExpression{message: "error"}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_raise(raise_expr, context,
          containing_function: "MyApp/fail/0",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.RaiseExpression
    end

    test "generates type triple for raise with exception module" do
      raise_expr = %RaiseExpression{exception: ArgumentError, message: "bad argument"}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_raise(raise_expr, context,
          containing_function: "MyApp/validate/1",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.RaiseExpression
    end

    test "generates type triple for reraise expression" do
      raise_expr = %RaiseExpression{
        exception: {:e, [], nil},
        is_reraise: true,
        stacktrace: {:__STACKTRACE__, [], nil}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_raise(raise_expr, context,
          containing_function: "MyApp/rethrow/0",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.RaiseExpression
    end
  end

  # ===========================================================================
  # Throw Expression Building Tests
  # ===========================================================================

  describe "build_throw/3" do
    test "generates type triple for throw expression" do
      throw_expr = %ThrowExpression{value: :done}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_throw(throw_expr, context,
          containing_function: "MyApp/abort/0",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.ThrowExpression
    end

    test "generates type triple for throw with complex value" do
      throw_expr = %ThrowExpression{value: {:error, :not_found}}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_throw(throw_expr, context,
          containing_function: "MyApp/search/1",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.ThrowExpression
    end
  end

  # ===========================================================================
  # Exit Expression Building Tests
  # ===========================================================================

  describe "build_exit/3" do
    test "generates type triple for exit expression" do
      exit_expr = %ExitExpression{reason: :normal}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_exit(exit_expr, context,
          containing_function: "MyApp/stop/0",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.ExitExpression
    end

    test "generates type triple for exit with shutdown reason" do
      exit_expr = %ExitExpression{reason: :shutdown}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_exit(exit_expr, context,
          containing_function: "MyApp/terminate/1",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.ExitExpression
    end

    test "generates type triple for exit with complex reason" do
      exit_expr = %ExitExpression{reason: {:shutdown, :timeout}}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_exit(exit_expr, context,
          containing_function: "MyApp/handle_timeout/0",
          index: 0
        )

      type_triple = find_triple(triples, expr_iri, RDF.type())
      assert type_triple != nil
      assert elem(type_triple, 2) == Core.ExitExpression
    end

    test "generates startLine triple for exit with location" do
      exit_expr = %ExitExpression{reason: :normal, location: %{line: 88}}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_exit(exit_expr, context,
          containing_function: "MyApp/stop/0",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 88
    end

    test "uses default index 0 when not specified" do
      exit_expr = %ExitExpression{reason: :normal}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, _triples} =
        ExceptionBuilder.build_exit(exit_expr, context, containing_function: "MyApp/stop/0")

      assert to_string(expr_iri) == "https://example.org/code#exit/MyApp/stop/0/0"
    end

    test "uses unknown/0 when containing_function not specified" do
      exit_expr = %ExitExpression{reason: :normal}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, _triples} = ExceptionBuilder.build_exit(exit_expr, context)

      assert to_string(expr_iri) == "https://example.org/code#exit/unknown/0/0"
    end
  end

  # ===========================================================================
  # Location Handling Tests
  # ===========================================================================

  describe "location handling" do
    test "generates startLine triple for try with location" do
      try_expr = %Exception{
        body: :ok,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: [],
        location: %{line: 42}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 42
    end

    test "generates startLine triple for raise with location" do
      raise_expr = %RaiseExpression{message: "error", location: %{line: 100}}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_raise(raise_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 100
    end

    test "generates startLine triple for throw with location" do
      throw_expr = %ThrowExpression{value: :done, location: %{line: 55}}
      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_throw(throw_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple != nil
      assert RDF.Literal.value(elem(line_triple, 2)) == 55
    end

    test "does not generate location triple when location is nil" do
      try_expr = %Exception{
        body: :ok,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: [],
        location: nil
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      assert line_triple == nil
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "uses default index 0 when not specified" do
      try_expr = %Exception{
        body: :ok,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, _triples} =
        ExceptionBuilder.build_try(try_expr, context, containing_function: "MyApp/test/0")

      assert to_string(expr_iri) == "https://example.org/code#try/MyApp/test/0/0"
    end

    test "uses unknown/0 when containing_function not specified" do
      try_expr = %Exception{
        body: :ok,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, _triples} = ExceptionBuilder.build_try(try_expr, context)

      assert to_string(expr_iri) == "https://example.org/code#try/unknown/0/0"
    end

    test "handles try with only rescue" do
      try_expr = %Exception{
        body: :risky,
        has_rescue: true,
        rescue_clauses: [%RescueClause{body: :error}],
        catch_clauses: [],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      assert find_triple(triples, expr_iri, Core.hasRescueClause()) != nil
      assert find_triple(triples, expr_iri, Core.hasCatchClause()) == nil
      assert find_triple(triples, expr_iri, Core.hasAfterClause()) == nil
      assert find_triple(triples, expr_iri, Core.hasElseClause()) == nil
    end

    test "handles try with only after" do
      try_expr = %Exception{
        body: :work,
        has_after: true,
        after_body: :cleanup,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: []
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      assert find_triple(triples, expr_iri, Core.hasRescueClause()) == nil
      assert find_triple(triples, expr_iri, Core.hasCatchClause()) == nil
      assert find_triple(triples, expr_iri, Core.hasAfterClause()) != nil
      assert find_triple(triples, expr_iri, Core.hasElseClause()) == nil
    end
  end

  # ===========================================================================
  # Triple Validation Tests
  # ===========================================================================

  describe "triple validation" do
    test "all triples have valid subjects (IRIs)" do
      try_expr = %Exception{
        body: :ok,
        has_rescue: true,
        has_catch: true,
        has_after: true,
        rescue_clauses: [%RescueClause{body: :err}],
        catch_clauses: [%CatchClause{pattern: :x, body: :x}],
        after_body: :cleanup,
        location: %{line: 10}
      }

      context = Context.new(base_iri: @base_iri)

      {_expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      for {subject, _predicate, _object} <- triples do
        assert %RDF.IRI{} = subject
        assert String.starts_with?(to_string(subject), "https://")
      end
    end

    test "all triples have valid predicates (IRIs)" do
      try_expr = %Exception{
        body: :ok,
        has_rescue: true,
        rescue_clauses: [%RescueClause{body: :err}],
        catch_clauses: [],
        else_clauses: [],
        location: %{line: 10}
      }

      context = Context.new(base_iri: @base_iri)

      {_expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      for {_subject, predicate, _object} <- triples do
        assert %RDF.IRI{} = predicate
      end
    end

    test "type triples have correct class IRIs" do
      try_expr = %Exception{body: :ok, rescue_clauses: [], catch_clauses: [], else_clauses: []}
      raise_expr = %RaiseExpression{message: "error"}
      throw_expr = %ThrowExpression{value: :done}
      exit_expr = %ExitExpression{reason: :normal}
      context = Context.new(base_iri: @base_iri)

      {try_iri, try_triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      {raise_iri, raise_triples} =
        ExceptionBuilder.build_raise(raise_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      {throw_iri, throw_triples} =
        ExceptionBuilder.build_throw(throw_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      {exit_iri, exit_triples} =
        ExceptionBuilder.build_exit(exit_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      try_type = find_triple(try_triples, try_iri, RDF.type())
      raise_type = find_triple(raise_triples, raise_iri, RDF.type())
      throw_type = find_triple(throw_triples, throw_iri, RDF.type())
      exit_type = find_triple(exit_triples, exit_iri, RDF.type())

      assert elem(try_type, 2) == Core.TryExpression
      assert elem(raise_type, 2) == Core.RaiseExpression
      assert elem(throw_type, 2) == Core.ThrowExpression
      assert elem(exit_type, 2) == Core.ExitExpression
    end

    test "boolean properties have correct literal type" do
      try_expr = %Exception{
        body: :ok,
        has_rescue: true,
        has_catch: true,
        has_after: true,
        has_else: true,
        rescue_clauses: [%RescueClause{body: :err}],
        catch_clauses: [%CatchClause{pattern: :x, body: :x}],
        else_clauses: [%Exception.ElseClause{pattern: :ok, body: :ok}],
        after_body: :cleanup
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      rescue_triple = find_triple(triples, expr_iri, Core.hasRescueClause())
      catch_triple = find_triple(triples, expr_iri, Core.hasCatchClause())
      after_triple = find_triple(triples, expr_iri, Core.hasAfterClause())
      else_triple = find_triple(triples, expr_iri, Core.hasElseClause())

      for triple <- [rescue_triple, catch_triple, after_triple, else_triple] do
        literal = elem(triple, 2)
        assert RDF.Literal.datatype_id(literal) == RDF.XSD.Boolean.id()
        assert RDF.Literal.value(literal) == true
      end
    end

    test "startLine is a positive integer literal" do
      try_expr = %Exception{
        body: :ok,
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: [],
        location: %{line: 42}
      }

      context = Context.new(base_iri: @base_iri)

      {expr_iri, triples} =
        ExceptionBuilder.build_try(try_expr, context,
          containing_function: "MyApp/test/0",
          index: 0
        )

      line_triple = find_triple(triples, expr_iri, Core.startLine())
      literal = elem(line_triple, 2)

      assert RDF.Literal.datatype_id(literal) == RDF.XSD.PositiveInteger.id()
      assert RDF.Literal.value(literal) == 42
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp find_triple(triples, subject, predicate) do
    Enum.find(triples, fn {s, p, _o} -> s == subject and p == predicate end)
  end
end
