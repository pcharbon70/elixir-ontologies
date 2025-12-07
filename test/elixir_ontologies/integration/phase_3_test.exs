defmodule ElixirOntologies.Integration.Phase3Test do
  @moduledoc """
  Integration tests for Phase 3 core extractors.

  These tests verify that all extractors work together correctly on real Elixir
  code, handling complex nested AST structures and preserving source locations.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.{
    Literal,
    Operator,
    Pattern,
    ControlFlow,
    Comprehension,
    Block,
    Reference
  }

  # ===========================================================================
  # Test 1: Module with All Literal Types
  # ===========================================================================

  describe "integration: all literal types" do
    test "extracts atom literals" do
      atoms = [:ok, :error, true, false, nil]

      for atom <- atoms do
        assert {:ok, result} = Literal.extract(atom)
        assert result.type == :atom
        assert result.value == atom
      end
    end

    test "extracts integer literals in various bases" do
      # Decimal
      assert {:ok, result} = Literal.extract(42)
      assert result.type == :integer
      assert result.value == 42

      # Hex (quoted form preserves value)
      assert {:ok, result} = Literal.extract(0xFF)
      assert result.value == 255

      # Binary
      assert {:ok, result} = Literal.extract(0b1010)
      assert result.value == 10

      # Octal
      assert {:ok, result} = Literal.extract(0o777)
      assert result.value == 511
    end

    test "extracts float literals" do
      assert {:ok, result} = Literal.extract(3.14)
      assert result.type == :float
      assert result.value == 3.14

      assert {:ok, result} = Literal.extract(1.0e10)
      assert result.value == 1.0e10
    end

    test "extracts string literals" do
      assert {:ok, result} = Literal.extract("hello")
      assert result.type == :string
      assert result.value == "hello"
    end

    test "extracts list literals" do
      ast = [1, 2, 3]
      assert {:ok, result} = Literal.extract(ast)
      assert result.type == :list
      assert result.value == [1, 2, 3]
    end

    test "extracts tuple literals" do
      ast = {:{}, [], [:ok, "value"]}
      assert {:ok, result} = Literal.extract(ast)
      assert result.type == :tuple
      assert result.value == {:ok, "value"}
    end

    test "extracts map literals" do
      ast = {:%{}, [], [name: "John", age: 30]}
      assert {:ok, result} = Literal.extract(ast)
      assert result.type == :map
      assert result.metadata.pair_count == 2
    end

    test "extracts keyword list literals" do
      ast = [name: "John", age: 30]
      assert {:ok, result} = Literal.extract(ast)
      assert result.type == :keyword_list
      assert result.metadata.length == 2
    end

    test "extracts binary literals" do
      ast = {:<<>>, [], [1, 2, 3]}
      assert {:ok, result} = Literal.extract(ast)
      assert result.type == :binary
    end

    test "extracts range literals" do
      ast = {:.., [], [1, 10]}
      assert {:ok, result} = Literal.extract(ast)
      assert result.type == :range
      assert result.metadata.range_start == 1
      assert result.metadata.range_end == 10
    end

    test "extracts range with step" do
      ast = {:..//, [], [1, 10, 2]}
      assert {:ok, result} = Literal.extract(ast)
      assert result.type == :range
      assert result.metadata.range_step == 2
    end

    test "extracts sigil literals" do
      ast = {:sigil_r, [], [{:<<>>, [], ["pattern"]}, ~c"i"]}
      assert {:ok, result} = Literal.extract(ast)
      assert result.type == :sigil
      assert result.metadata.sigil_char == "r"
      assert result.metadata.modifiers == ~c"i"
    end
  end

  # ===========================================================================
  # Test 2: Function with Complex Patterns
  # ===========================================================================

  describe "integration: complex patterns" do
    test "extracts variable pattern" do
      ast = {:x, [], nil}
      assert {:ok, result} = Pattern.extract(ast)
      assert result.type == :variable
      assert result.metadata.variable_name == :x
    end

    test "extracts wildcard pattern" do
      ast = {:_, [], nil}
      assert {:ok, result} = Pattern.extract(ast)
      assert result.type == :wildcard
    end

    test "extracts pin pattern" do
      ast = {:^, [], [{:x, [], nil}]}
      assert {:ok, result} = Pattern.extract(ast)
      assert result.type == :pin
      assert result.metadata.pinned_variable == :x
    end

    test "extracts tuple pattern with nested elements" do
      # {:ok, {x, y}}
      inner_tuple = {:{}, [], [{:x, [], nil}, {:y, [], nil}]}
      ast = {:{}, [], [:ok, inner_tuple]}
      assert {:ok, result} = Pattern.extract(ast)
      assert result.type == :tuple
      assert length(result.metadata.elements) == 2
    end

    test "extracts list pattern with head|tail" do
      # [head | tail]
      ast = [{:|, [], [{:head, [], nil}, {:tail, [], nil}]}]
      assert {:ok, result} = Pattern.extract(ast)
      assert result.type == :list
      assert result.metadata.has_cons_cell == true
    end

    test "extracts map pattern" do
      # %{key: value}
      ast = {:%{}, [], [key: {:value, [], nil}]}
      assert {:ok, result} = Pattern.extract(ast)
      assert result.type == :map
    end

    test "extracts struct pattern" do
      # %User{name: name}
      ast = {:%, [], [{:__aliases__, [], [:User]}, {:%{}, [], [name: {:name, [], nil}]}]}
      assert {:ok, result} = Pattern.extract(ast)
      assert result.type == :struct
      assert result.metadata.struct_name == [:User]
    end

    test "extracts binary pattern" do
      # <<x::8, rest::binary>>
      ast =
        {:<<>>, [],
         [
           {:"::", [], [{:x, [], nil}, 8]},
           {:"::", [], [{:rest, [], nil}, {:binary, [], nil}]}
         ]}

      assert {:ok, result} = Pattern.extract(ast)
      assert result.type == :binary
    end

    test "extracts as pattern" do
      # value = {:ok, result}
      ast = {:=, [], [{:value, [], nil}, {:{}, [], [:ok, {:result, [], nil}]}]}
      assert {:ok, result} = Pattern.extract(ast)
      assert result.type == :as
    end

    test "extracts guard clause" do
      # when is_integer(x) and x > 0
      guard_ast =
        {:when, [],
         [
           {:x, [], nil},
           {:and, [],
            [
              {:is_integer, [], [{:x, [], nil}]},
              {:>, [], [{:x, [], nil}, 0]}
            ]}
         ]}

      result = Pattern.extract_guard(guard_ast)
      assert result.type == :guard
      assert result.metadata.guard_expression != nil
    end

    test "patterns in function head work together" do
      # def process({:ok, %User{name: name} = user}) when is_binary(name)
      # This tests nested patterns: tuple containing struct with as pattern
      struct_pattern =
        {:%, [],
         [
           {:__aliases__, [], [:User]},
           {:%{}, [], [name: {:name, [], nil}]}
         ]}

      as_pattern = {:=, [], [struct_pattern, {:user, [], nil}]}
      tuple_pattern = {:{}, [], [:ok, as_pattern]}

      assert {:ok, result} = Pattern.extract(tuple_pattern)
      assert result.type == :tuple
    end
  end

  # ===========================================================================
  # Test 3: Control Flow Heavy Function
  # ===========================================================================

  describe "integration: control flow expressions" do
    test "extracts if expression" do
      ast =
        {:if, [],
         [
           {:x, [], nil},
           [do: 1, else: 2]
         ]}

      assert {:ok, result} = ControlFlow.extract(ast)
      assert result.type == :if
      assert result.branches.then == 1
      assert result.branches.else == 2
    end

    test "extracts unless expression" do
      ast =
        {:unless, [],
         [
           {:error, [], nil},
           [do: :ok]
         ]}

      assert {:ok, result} = ControlFlow.extract(ast)
      assert result.type == :unless
    end

    test "extracts case expression with multiple clauses" do
      ast =
        {:case, [],
         [
           {:x, [], nil},
           [
             do: [
               {:->, [], [[:ok], 1]},
               {:->, [], [[:error], 2]},
               {:->, [], [[{:_, [], nil}], 3]}
             ]
           ]
         ]}

      assert {:ok, result} = ControlFlow.extract(ast)
      assert result.type == :case
      assert length(result.clauses) == 3
    end

    test "extracts cond expression" do
      ast =
        {:cond, [],
         [
           [
             do: [
               {:->, [], [[true], 1]},
               {:->, [], [[false], 2]}
             ]
           ]
         ]}

      assert {:ok, result} = ControlFlow.extract(ast)
      assert result.type == :cond
      assert length(result.clauses) == 2
    end

    test "extracts with expression" do
      ast =
        {:with, [],
         [
           {:<-, [], [{:ok, {:x, [], nil}}, {:get_x, [], []}]},
           {:<-, [], [{:ok, {:y, [], nil}}, {:get_y, [], []}]},
           [do: {:+, [], [{:x, [], nil}, {:y, [], nil}]}]
         ]}

      assert {:ok, result} = ControlFlow.extract(ast)
      assert result.type == :with
      assert result.metadata.match_clause_count == 2
    end

    test "extracts try/rescue/after expression" do
      ast =
        {:try, [],
         [
           [
             do: {:dangerous_operation, [], []},
             rescue: [{:->, [], [[{:e, [], nil}], {:handle_error, [], [{:e, [], nil}]}]}],
             after: {:cleanup, [], []}
           ]
         ]}

      assert {:ok, result} = ControlFlow.extract(ast)
      assert result.type == :try
      assert result.branches.rescue != nil
      assert result.branches.after != nil
    end

    test "extracts raise expression" do
      ast = {:raise, [], ["error message"]}
      assert {:ok, result} = ControlFlow.extract(ast)
      assert result.type == :raise
    end

    test "extracts throw expression" do
      ast = {:throw, [], [:value]}
      assert {:ok, result} = ControlFlow.extract(ast)
      assert result.type == :throw
    end

    test "extracts receive expression with timeout" do
      ast =
        {:receive, [],
         [
           [
             do: [{:->, [], [[{:msg, [], nil}], {:process, [], [{:msg, [], nil}]}]}],
             after: [{:->, [], [[5000], :timeout]}]
           ]
         ]}

      assert {:ok, result} = ControlFlow.extract(ast)
      assert result.type == :receive
      assert result.metadata.has_timeout == true
    end

    test "nested control flow: case inside if" do
      inner_case =
        {:case, [],
         [
           {:y, [], nil},
           [do: [{:->, [], [[:a], 1]}, {:->, [], [[:b], 2]}]]
         ]}

      outer_if = {:if, [], [{:x, [], nil}, [do: inner_case, else: 0]]}

      assert {:ok, if_result} = ControlFlow.extract(outer_if)
      assert if_result.type == :if

      # The then_branch contains the case
      assert {:ok, case_result} = ControlFlow.extract(if_result.branches.then)
      assert case_result.type == :case
    end
  end

  # ===========================================================================
  # Test 4: Comprehension and Block Integration
  # ===========================================================================

  describe "integration: comprehensions and blocks" do
    test "extracts for comprehension with generator" do
      ast =
        {:for, [],
         [
           {:<-, [], [{:x, [], nil}, [1, 2, 3]]},
           [do: {:*, [], [{:x, [], nil}, 2]}]
         ]}

      assert {:ok, result} = Comprehension.extract(ast)
      assert result.type == :for
      assert length(result.generators) == 1
    end

    test "extracts for comprehension with filter" do
      ast =
        {:for, [],
         [
           {:<-, [], [{:x, [], nil}, [1, 2, 3, 4, 5]]},
           {:>, [], [{:x, [], nil}, 2]},
           [do: {:x, [], nil}]
         ]}

      assert {:ok, result} = Comprehension.extract(ast)
      assert length(result.filters) == 1
    end

    test "extracts for comprehension with into" do
      ast =
        {:for, [],
         [
           {:<-, [], [{:x, [], nil}, [1, 2, 3]]},
           [into: {:%{}, [], []}, do: {{:x, [], nil}, {:x, [], nil}}]
         ]}

      assert {:ok, result} = Comprehension.extract(ast)
      assert result.options.into != nil
    end

    test "extracts block with multiple expressions" do
      ast =
        {:__block__, [],
         [
           {:x, [], nil},
           {:y, [], nil},
           {:+, [], [{:x, [], nil}, {:y, [], nil}]}
         ]}

      assert {:ok, result} = Block.extract(ast)
      assert result.type == :block
      assert length(result.expressions) == 3
      assert Enum.at(result.expressions, 2).is_last == true
    end

    test "extracts anonymous function with single clause" do
      ast =
        {:fn, [],
         [
           {:->, [], [[{:x, [], nil}], {:*, [], [{:x, [], nil}, 2]}]}
         ]}

      assert {:ok, result} = Block.extract(ast)
      assert result.type == :fn
      assert length(result.clauses) == 1
    end

    test "extracts anonymous function with multiple clauses" do
      ast =
        {:fn, [],
         [
           {:->, [], [[:ok], 1]},
           {:->, [], [[:error], 0]}
         ]}

      assert {:ok, result} = Block.extract(ast)
      assert result.type == :fn
      assert length(result.clauses) == 2
    end
  end

  # ===========================================================================
  # Test 5: Reference and Operator Integration
  # ===========================================================================

  describe "integration: references and operators" do
    test "extracts variable reference" do
      ast = {:my_var, [], Elixir}
      assert {:ok, result} = Reference.extract(ast)
      assert result.type == :variable
      assert result.name == :my_var
    end

    test "extracts module reference" do
      ast = {:__aliases__, [], [:MyApp, :Users]}
      assert {:ok, result} = Reference.extract(ast)
      assert result.type == :module
      assert result.name == [:MyApp, :Users]
    end

    test "extracts local function capture" do
      ast = {:&, [], [{:/, [], [{:my_func, [], nil}, 2]}]}
      assert {:ok, result} = Reference.extract(ast)
      assert result.type == :function_capture
      assert result.function == :my_func
      assert result.arity == 2
    end

    test "extracts remote function capture" do
      ast = quote do: &String.upcase/1
      assert {:ok, result} = Reference.extract(ast)
      assert result.type == :function_capture
      assert result.module == [:String]
      assert result.function == :upcase
    end

    test "extracts remote call" do
      ast = quote do: String.upcase("hello")
      assert {:ok, result} = Reference.extract(ast)
      assert result.type == :remote_call
      assert result.module == [:String]
      assert result.function == :upcase
    end

    test "extracts local call" do
      ast = {:my_func, [], [1, 2]}
      assert {:ok, result} = Reference.extract(ast)
      assert result.type == :local_call
      assert result.function == :my_func
      assert result.arity == 2
    end

    test "extracts binding" do
      ast = {:=, [], [{:x, [], nil}, 42]}
      assert {:ok, result} = Reference.extract(ast)
      assert result.type == :binding
      assert result.name == :x
      assert result.value == 42
    end

    test "extracts arithmetic operators" do
      for {op, _} <- [
            {:+, "addition"},
            {:-, "subtraction"},
            {:*, "multiplication"},
            {:/, "division"}
          ] do
        ast = {op, [], [1, 2]}
        assert {:ok, result} = Operator.extract(ast)
        assert result.symbol == op
        assert result.type == :arithmetic
      end
    end

    test "extracts comparison operators" do
      for op <- [:==, :!=, :===, :!==, :<, :>, :<=, :>=] do
        ast = {op, [], [1, 2]}
        assert {:ok, result} = Operator.extract(ast)
        assert result.symbol == op
        assert result.type == :comparison
      end
    end

    test "extracts logical operators" do
      for op <- [:and, :or, :&&, :||] do
        ast = {op, [], [true, false]}
        assert {:ok, result} = Operator.extract(ast)
        assert result.symbol == op
        assert result.type == :logical
      end
    end

    test "extracts pipe operator" do
      ast = {:|>, [], [{:x, [], nil}, {:func, [], []}]}
      assert {:ok, result} = Operator.extract(ast)
      assert result.symbol == :|>
      assert result.type == :pipe
    end

    test "extracts string concat operator" do
      ast = {:<>, [], ["hello", "world"]}
      assert {:ok, result} = Operator.extract(ast)
      assert result.symbol == :<>
      assert result.type == :string_concat
    end

    test "extracts list operators" do
      for op <- [:++, :--] do
        ast = {op, [], [[1, 2], [3, 4]]}
        assert {:ok, result} = Operator.extract(ast)
        assert result.symbol == op
        assert result.type == :list
      end
    end
  end

  # ===========================================================================
  # Test 6: Source Location Preservation
  # ===========================================================================

  describe "integration: source location preservation" do
    test "control flow preserves source location" do
      code = """
      if x do
        1
      else
        2
      end
      """

      {:ok, ast} = Code.string_to_quoted(code, columns: true)
      assert {:ok, result} = ControlFlow.extract(ast)
      assert result.location != nil
      assert result.location.start_line == 1
    end

    test "comprehension preserves source location" do
      code = "for x <- list, do: x"
      {:ok, ast} = Code.string_to_quoted(code, columns: true)
      assert {:ok, result} = Comprehension.extract(ast)
      assert result.location != nil
      assert result.location.start_line == 1
    end

    test "block preserves source location" do
      code = """
      (
        x = 1
        y = 2
        x + y
      )
      """

      {:ok, ast} = Code.string_to_quoted(code, columns: true)
      assert {:ok, result} = Block.extract(ast)
      assert result.location != nil
    end

    test "reference preserves source location for module" do
      {:ok, ast} = Code.string_to_quoted("MyApp.Users", columns: true)
      assert {:ok, result} = Reference.extract(ast)
      assert result.location != nil
      assert result.location.start_line == 1
    end

    test "operator preserves source location" do
      {:ok, ast} = Code.string_to_quoted("1 + 2", columns: true)
      assert {:ok, result} = Operator.extract(ast)
      assert result.location != nil
      assert result.location.start_line == 1
    end
  end

  # ===========================================================================
  # Test 7: Core Ontology Coverage
  # ===========================================================================

  describe "integration: ontology class coverage" do
    @tag :ontology
    test "Literal extractor covers all literal ontology classes" do
      # Test that extractor returns expected types
      assert {:ok, %{type: :atom}} = Literal.extract(:ok)
      assert {:ok, %{type: :integer}} = Literal.extract(42)
      assert {:ok, %{type: :float}} = Literal.extract(3.14)
      assert {:ok, %{type: :string}} = Literal.extract("hello")
      assert {:ok, %{type: :list}} = Literal.extract([1, 2, 3])
    end

    @tag :ontology
    test "Operator extractor covers all operator ontology classes" do
      # Sample one operator from each category
      samples = [
        {:+, :arithmetic},
        {:==, :comparison},
        {:and, :logical},
        {:|>, :pipe},
        {:=, :match},
        {:&, :capture},
        {:<>, :string_concat},
        {:++, :list},
        {:in, :in}
      ]

      for {op, expected_category} <- samples do
        ast =
          case op do
            # Unary
            :& -> {:&, [], [1]}
            # Binary
            _ -> {op, [], [1, 2]}
          end

        assert {:ok, result} = Operator.extract(ast)

        assert result.type == expected_category,
               "Operator #{op} should be category #{expected_category}, got #{result.type}"
      end
    end

    @tag :ontology
    test "Pattern extractor covers all pattern ontology classes" do
      # Test representative samples
      assert {:ok, %{type: :literal}} = Pattern.extract(42)
      assert {:ok, %{type: :variable}} = Pattern.extract({:x, [], nil})
      assert {:ok, %{type: :wildcard}} = Pattern.extract({:_, [], nil})
      assert {:ok, %{type: :pin}} = Pattern.extract({:^, [], [{:x, [], nil}]})
      assert {:ok, %{type: :tuple}} = Pattern.extract({:{}, [], [1, 2]})
      assert {:ok, %{type: :list}} = Pattern.extract([1, 2])
      assert {:ok, %{type: :map}} = Pattern.extract({:%{}, [], [a: 1]})
    end

    @tag :ontology
    test "ControlFlow extractor covers all control flow ontology classes" do
      # Test representative samples
      assert {:ok, %{type: :if}} = ControlFlow.extract({:if, [], [true, [do: 1]]})
      assert {:ok, %{type: :unless}} = ControlFlow.extract({:unless, [], [false, [do: 1]]})
      assert {:ok, %{type: :case}} = ControlFlow.extract({:case, [], [:x, [do: []]]})
      assert {:ok, %{type: :cond}} = ControlFlow.extract({:cond, [], [[do: []]]})
      assert {:ok, %{type: :try}} = ControlFlow.extract({:try, [], [[do: 1]]})
      assert {:ok, %{type: :raise}} = ControlFlow.extract({:raise, [], ["error"]})
      assert {:ok, %{type: :throw}} = ControlFlow.extract({:throw, [], [:value]})
      assert {:ok, %{type: :receive}} = ControlFlow.extract({:receive, [], [[do: []]]})
    end

    @tag :ontology
    test "Reference extractor covers all reference ontology classes" do
      assert {:ok, %{type: :variable}} = Reference.extract({:x, [], Elixir})
      assert {:ok, %{type: :module}} = Reference.extract({:__aliases__, [], [:Mod]})
      assert {:ok, %{type: :local_call}} = Reference.extract({:func, [], [1]})
      assert {:ok, %{type: :binding}} = Reference.extract({:=, [], [{:x, [], nil}, 1]})
      assert {:ok, %{type: :pin}} = Reference.extract({:^, [], [{:x, [], nil}]})
    end

    @tag :ontology
    test "Comprehension extractor covers comprehension ontology class" do
      assert {:ok, %{type: :for}} =
               Comprehension.extract(
                 {:for, [], [{:<-, [], [{:x, [], nil}, []]}, [do: {:x, [], nil}]]}
               )
    end

    @tag :ontology
    test "Block extractor covers block ontology classes" do
      assert {:ok, %{type: :block}} = Block.extract({:__block__, [], [1, 2]})
      assert {:ok, %{type: :fn}} = Block.extract({:fn, [], [{:->, [], [[], 1]}]})
    end
  end

  # ===========================================================================
  # Test 8: Cross-Extractor Integration
  # ===========================================================================

  describe "integration: cross-extractor scenarios" do
    test "literal range extraction" do
      # Range is a literal type
      range_ast = {:.., [], [1, 10]}
      assert {:ok, literal_result} = Literal.extract(range_ast)
      assert literal_result.type == :range
      assert literal_result.metadata.range_start == 1
      assert literal_result.metadata.range_end == 10
    end

    test "reference inside comprehension" do
      # for x <- list, do: x * 2
      ast =
        {:for, [],
         [
           {:<-, [], [{:x, [], nil}, {:list, [], nil}]},
           [do: {:*, [], [{:x, [], nil}, 2]}]
         ]}

      assert {:ok, comp} = Comprehension.extract(ast)
      # The body contains an operator
      body = comp.body
      assert {:ok, _} = Operator.extract(body)
    end

    test "pattern inside control flow" do
      # case value do {:ok, x} -> x end
      ast =
        {:case, [],
         [
           {:value, [], nil},
           [do: [{:->, [], [[{:{}, [], [:ok, {:x, [], nil}]}], {:x, [], nil}]}]]
         ]}

      assert {:ok, cf} = ControlFlow.extract(ast)
      [clause] = cf.clauses
      [pattern] = clause.patterns
      assert {:ok, _} = Pattern.extract(pattern)
    end

    test "block inside control flow" do
      # if cond do x = 1; y = 2; x + y end
      block =
        {:__block__, [],
         [
           {:=, [], [{:x, [], nil}, 1]},
           {:=, [], [{:y, [], nil}, 2]},
           {:+, [], [{:x, [], nil}, {:y, [], nil}]}
         ]}

      ast = {:if, [], [{:cond, [], nil}, [do: block]]}

      assert {:ok, cf} = ControlFlow.extract(ast)
      assert {:ok, _} = Block.extract(cf.branches.then)
    end

    test "complex pipeline expression" do
      # list |> Enum.map(&(&1 * 2)) |> Enum.sum()
      capture = {:&, [], [{:*, [], [{:&, [], [1]}, 2]}]}
      map_call = {{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], [capture]}
      sum_call = {{:., [], [{:__aliases__, [], [:Enum]}, :sum]}, [], []}

      pipe1 = {:|>, [], [{:list, [], nil}, map_call]}
      pipe2 = {:|>, [], [pipe1, sum_call]}

      assert {:ok, op} = Operator.extract(pipe2)
      assert op.type == :pipe

      # Left operand is another pipe
      assert {:ok, inner_op} = Operator.extract(op.operands.left)
      assert inner_op.type == :pipe
    end
  end
end
