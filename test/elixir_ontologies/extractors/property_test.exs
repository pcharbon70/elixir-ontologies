defmodule ElixirOntologies.Extractors.PropertyTest do
  @moduledoc """
  Property-based tests for Phase 3 extractors using StreamData.

  These tests verify that extractors handle a wide range of inputs correctly,
  including edge cases that may not be covered by unit tests.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ElixirOntologies.Extractors.{
    Literal,
    Operator,
    Pattern,
    ControlFlow,
    Comprehension,
    Block,
    Reference
  }

  alias ElixirOntologies.Extractors.OTP.Supervisor, as: SupervisorExtractor

  # ============================================================================
  # AST Generators
  # ============================================================================

  defp atom_gen do
    gen all(
          name <-
            StreamData.member_of([
              :ok,
              :error,
              true,
              false,
              nil,
              :foo,
              :bar,
              :baz,
              :hello,
              :world
            ])
        ) do
      name
    end
  end

  defp integer_gen do
    StreamData.integer(-1_000_000..1_000_000)
  end

  defp float_gen do
    gen all(value <- StreamData.float(min: -1_000.0, max: 1_000.0)) do
      # Ensure finite floats
      if Float.parse(Float.to_string(value)) == :error, do: 0.0, else: value
    end
  end

  defp string_gen do
    StreamData.string(:printable, min_length: 0, max_length: 100)
  end

  defp variable_name_gen do
    gen all(
          first <- StreamData.member_of(~c"abcdefghijklmnopqrstuvwxyz"),
          rest <- StreamData.string(:alphanumeric, max_length: 10)
        ) do
      String.to_atom(<<first>> <> rest)
    end
  end

  defp variable_ast_gen do
    gen all(name <- variable_name_gen()) do
      {name, [], Elixir}
    end
  end

  defp simple_literal_gen do
    StreamData.one_of([
      atom_gen(),
      integer_gen(),
      float_gen(),
      string_gen()
    ])
  end

  defp list_literal_gen do
    StreamData.list_of(simple_literal_gen(), max_length: 5)
  end

  defp map_ast_gen do
    gen all(
          pairs <-
            StreamData.list_of(
              StreamData.tuple({atom_gen(), simple_literal_gen()}),
              max_length: 5
            )
        ) do
      {:%{}, [], pairs}
    end
  end

  defp binary_operator_gen do
    gen all(
          op <- StreamData.member_of([:+, :-, :*, :/, :==, :!=, :<, :>, :<=, :>=, :and, :or]),
          left <- integer_gen(),
          right <- integer_gen()
        ) do
      {op, [], [left, right]}
    end
  end

  defp unary_operator_gen do
    gen all(
          op <- StreamData.member_of([:not, :!, :-]),
          operand <- integer_gen()
        ) do
      {op, [], [operand]}
    end
  end

  defp if_ast_gen do
    gen all(
          condition <- variable_ast_gen(),
          then_branch <- simple_literal_gen(),
          else_branch <- simple_literal_gen()
        ) do
      {:if, [], [condition, [do: then_branch, else: else_branch]]}
    end
  end

  defp case_ast_gen do
    gen all(
          subject <- variable_ast_gen(),
          result1 <- simple_literal_gen(),
          result2 <- simple_literal_gen()
        ) do
      {:case, [],
       [
         subject,
         [
           do: [
             {:->, [], [[:ok], result1]},
             {:->, [], [[{:_, [], Elixir}], result2]}
           ]
         ]
       ]}
    end
  end

  defp for_ast_gen do
    gen all(
          var <- variable_ast_gen(),
          enumerable <- list_literal_gen(),
          body <- simple_literal_gen()
        ) do
      {:for, [], [{:<-, [], [var, enumerable]}, [do: body]]}
    end
  end

  defp block_ast_gen do
    gen all(exprs <- StreamData.list_of(simple_literal_gen(), min_length: 1, max_length: 5)) do
      {:__block__, [], exprs}
    end
  end

  defp fn_ast_gen do
    gen all(
          params <- StreamData.list_of(variable_ast_gen(), max_length: 3),
          body <- simple_literal_gen()
        ) do
      {:fn, [], [{:->, [], [params, body]}]}
    end
  end

  # ============================================================================
  # Literal Extractor Properties
  # ============================================================================

  describe "Literal extractor properties" do
    property "extracts all atoms correctly" do
      check all(atom <- atom_gen()) do
        assert {:ok, result} = Literal.extract(atom)
        assert result.type == :atom
        assert result.value == atom
      end
    end

    property "extracts all integers correctly" do
      check all(int <- integer_gen()) do
        assert {:ok, result} = Literal.extract(int)
        assert result.type == :integer
        assert result.value == int
      end
    end

    property "extracts all floats correctly" do
      check all(float <- float_gen()) do
        assert {:ok, result} = Literal.extract(float)
        assert result.type == :float
        assert result.value == float
      end
    end

    property "extracts all strings correctly" do
      check all(str <- string_gen()) do
        assert {:ok, result} = Literal.extract(str)
        assert result.type == :string
        assert result.value == str
      end
    end

    property "extracts lists correctly" do
      check all(list <- list_literal_gen()) do
        assert {:ok, result} = Literal.extract(list)
        assert result.type in [:list, :keyword_list]
      end
    end

    property "extracts maps correctly" do
      check all(map_ast <- map_ast_gen()) do
        assert {:ok, result} = Literal.extract(map_ast)
        assert result.type == :map
      end
    end
  end

  # ============================================================================
  # Operator Extractor Properties
  # ============================================================================

  describe "Operator extractor properties" do
    property "extracts binary operators with correct operands" do
      check all(op_ast <- binary_operator_gen()) do
        assert {:ok, result} = Operator.extract(op_ast)
        assert result.arity == 2
        assert result.operator_class == :BinaryOperator
        assert Map.has_key?(result.operands, :left)
        assert Map.has_key?(result.operands, :right)
      end
    end

    property "extracts unary operators with correct operand" do
      check all(op_ast <- unary_operator_gen()) do
        assert {:ok, result} = Operator.extract(op_ast)
        assert result.arity == 1
        assert result.operator_class == :UnaryOperator
        assert Map.has_key?(result.operands, :operand)
      end
    end
  end

  # ============================================================================
  # Pattern Extractor Properties
  # ============================================================================

  describe "Pattern extractor properties" do
    property "extracts variable patterns with correct bindings" do
      check all(var <- variable_ast_gen()) do
        assert {:ok, result} = Pattern.extract(var)
        assert result.type == :variable
        assert length(result.bindings) == 1
      end
    end

    property "wildcard patterns have no bindings" do
      check all(_ <- StreamData.constant({:_, [], Elixir})) do
        assert {:ok, result} = Pattern.extract({:_, [], Elixir})
        assert result.type == :wildcard
        assert result.bindings == []
      end
    end

    property "literal patterns have correct type" do
      check all(lit <- simple_literal_gen()) do
        assert {:ok, result} = Pattern.extract(lit)
        assert result.type == :literal
        assert result.bindings == []
      end
    end
  end

  # ============================================================================
  # Control Flow Extractor Properties
  # ============================================================================

  describe "ControlFlow extractor properties" do
    property "extracts if expressions correctly" do
      check all(if_ast <- if_ast_gen()) do
        assert {:ok, result} = ControlFlow.extract(if_ast)
        assert result.type == :if
        assert result.condition != nil
      end
    end

    property "extracts case expressions correctly" do
      check all(case_ast <- case_ast_gen()) do
        assert {:ok, result} = ControlFlow.extract(case_ast)
        assert result.type == :case
        assert length(result.clauses) >= 1
      end
    end
  end

  # ============================================================================
  # Comprehension Extractor Properties
  # ============================================================================

  describe "Comprehension extractor properties" do
    property "extracts for comprehensions with generators" do
      check all(for_ast <- for_ast_gen()) do
        assert {:ok, result} = Comprehension.extract(for_ast)
        assert result.type == :for
        assert length(result.generators) >= 1
      end
    end
  end

  # ============================================================================
  # Block Extractor Properties
  # ============================================================================

  describe "Block extractor properties" do
    property "extracts blocks with correct expression count" do
      check all(block_ast <- block_ast_gen()) do
        {:__block__, [], exprs} = block_ast
        assert {:ok, result} = Block.extract(block_ast)
        assert result.type == :block
        assert length(result.expressions) == length(exprs)
      end
    end

    property "extracts fn with clauses" do
      check all(fn_ast <- fn_ast_gen()) do
        assert {:ok, result} = Block.extract(fn_ast)
        assert result.type == :fn
        assert length(result.clauses) >= 1
      end
    end
  end

  # ============================================================================
  # Reference Extractor Properties
  # ============================================================================

  describe "Reference extractor properties" do
    property "extracts variables correctly" do
      check all(var <- variable_ast_gen()) do
        assert {:ok, result} = Reference.extract(var)
        assert result.type == :variable
        assert is_atom(result.name)
      end
    end

    property "extracts module references correctly" do
      check all(
              parts <-
                StreamData.list_of(
                  StreamData.member_of([:Foo, :Bar, :Baz, :Module, :Test]),
                  min_length: 1,
                  max_length: 3
                )
            ) do
        module_ast = {:__aliases__, [], parts}
        assert {:ok, result} = Reference.extract(module_ast)
        assert result.type == :module
        assert result.name == parts
      end
    end
  end

  # ============================================================================
  # Error Handling Properties
  # ============================================================================

  describe "Error handling properties" do
    property "Literal.extract returns error for special forms" do
      check all(
              form <-
                StreamData.member_of([
                  {:def, [], [{:foo, [], nil}]},
                  {:defmodule, [], [{:__aliases__, [], [:Foo]}, [do: nil]]},
                  {:import, [], [{:__aliases__, [], [:Enum]}]},
                  {:fn, [], [{:->, [], [[], :ok]}]}
                ])
            ) do
        result = Literal.extract(form)
        # These special forms are not literals
        assert match?({:error, _}, result)
      end
    end

    property "Operator.extract returns error for non-operators" do
      check all(lit <- simple_literal_gen()) do
        result = Operator.extract(lit)
        assert match?({:error, _}, result)
      end
    end

    property "ControlFlow.extract returns error for non-control-flow" do
      check all(lit <- simple_literal_gen()) do
        result = ControlFlow.extract(lit)
        assert match?({:error, _}, result)
      end
    end

    property "Comprehension.extract returns error for non-comprehensions" do
      check all(lit <- simple_literal_gen()) do
        result = Comprehension.extract(lit)
        assert match?({:error, _}, result)
      end
    end

    property "Block.extract returns error for non-blocks" do
      check all(lit <- simple_literal_gen()) do
        result = Block.extract(lit)
        assert match?({:error, _}, result)
      end
    end
  end

  # ============================================================================
  # Supervisor Extractor Properties
  # ============================================================================

  describe "Supervisor extractor properties" do
    # Generator for supervisor module body AST
    defp supervisor_module_gen do
      gen all(
            sup_type <- StreamData.member_of([:Supervisor, :DynamicSupervisor]),
            detection <- StreamData.member_of([:use, :behaviour])
          ) do
        case detection do
          :use -> {:use, [], [{:__aliases__, [], [sup_type]}]}
          :behaviour -> {:@, [], [{:behaviour, [], [{:__aliases__, [], [sup_type]}]}]}
        end
      end
    end

    defp strategy_gen do
      StreamData.member_of([:one_for_one, :one_for_all, :rest_for_one])
    end

    defp supervisor_with_init_gen do
      gen all(
            sup_type <- StreamData.member_of([:Supervisor, :DynamicSupervisor]),
            strategy <- strategy_gen()
          ) do
        use_stmt = {:use, [], [{:__aliases__, [], [sup_type]}]}

        init_body =
          if sup_type == :Supervisor do
            {{:., [], [{:__aliases__, [], [:Supervisor]}, :init]}, [],
             [[], [strategy: strategy]]}
          else
            {{:., [], [{:__aliases__, [], [:DynamicSupervisor]}, :init]}, [],
             [[strategy: strategy]]}
          end

        init_def = {:def, [], [{:init, [], [{:_, [], Elixir}]}, [do: init_body]]}

        {:__block__, [], [use_stmt, init_def]}
      end
    end

    property "detects all supervisor AST variants correctly" do
      check all(sup_ast <- supervisor_module_gen()) do
        body = {:__block__, [], [sup_ast]}
        assert SupervisorExtractor.supervisor?(body)
      end
    end

    property "supervisor_type matches extract result" do
      check all(sup_ast <- supervisor_module_gen()) do
        body = {:__block__, [], [sup_ast]}
        type = SupervisorExtractor.supervisor_type(body)

        case SupervisorExtractor.extract(body) do
          {:ok, result} -> assert result.supervisor_type == type
          {:error, _} -> assert type == nil
        end
      end
    end

    property "detection_method is consistent with extract" do
      check all(sup_ast <- supervisor_module_gen()) do
        body = {:__block__, [], [sup_ast]}
        method = SupervisorExtractor.detection_method(body)

        case SupervisorExtractor.extract(body) do
          {:ok, result} -> assert result.detection_method == method
          {:error, _} -> assert method == nil
        end
      end
    end

    property "strategy extraction returns valid strategy types" do
      check all(body <- supervisor_with_init_gen()) do
        case SupervisorExtractor.extract_strategy(body) do
          {:ok, strategy} ->
            assert strategy.type in [:one_for_one, :one_for_all, :rest_for_one]

          {:error, _} ->
            # Valid case when no strategy found
            :ok
        end
      end
    end

    property "child_count equals length of extract_children" do
      check all(body <- supervisor_with_init_gen()) do
        count = SupervisorExtractor.child_count(body)
        {:ok, children} = SupervisorExtractor.extract_children(body)
        assert count == length(children)
      end
    end

    property "non-supervisor modules return error" do
      check all(
              other_behaviour <-
                StreamData.member_of([:GenServer, :Agent, :Task, :GenEvent, :Application])
            ) do
        body =
          {:__block__, [],
           [
             {:use, [], [{:__aliases__, [], [other_behaviour]}]}
           ]}

        refute SupervisorExtractor.supervisor?(body)
        assert {:error, _} = SupervisorExtractor.extract(body)
      end
    end
  end
end
