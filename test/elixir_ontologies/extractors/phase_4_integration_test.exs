defmodule ElixirOntologies.Extractors.Phase4IntegrationTest do
  @moduledoc """
  Integration tests for Phase 4 Structure Extractors.

  These tests verify that all Phase 4 extractors work together correctly
  when extracting real-world Elixir module patterns including:
  - Complete modules with functions, specs, and attributes
  - GenServer modules with callbacks
  - Multi-clause functions with pattern matching
  - Parameter-to-type linking via specs
  - Macro extraction with quote/unquote
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.{
    Module,
    Attribute,
    Clause,
    Parameter,
    ReturnExpression,
    TypeDefinition,
    FunctionSpec,
    TypeExpression,
    Macro,
    Quote
  }

  # ===========================================================================
  # Test 1: Full Module Extraction with Functions, Specs, and Attributes
  # ===========================================================================

  describe "full module extraction" do
    test "extracts complete module with all components" do
      ast =
        quote do
          defmodule MyApp.Users do
            @moduledoc "User management module"

            @type user :: %{name: String.t(), age: integer()}
            @type id :: pos_integer()

            @doc "Lists all users"
            @spec list_users() :: [user()]
            def list_users do
              []
            end

            @doc "Gets a user by ID"
            @spec get_user(id()) :: user() | nil
            def get_user(id) do
              nil
            end

            @doc false
            defp validate_user(user) do
              {:ok, user}
            end
          end
        end

      # Extract module
      assert {:ok, module_result} = Module.extract(ast)
      assert module_result.name == [:MyApp, :Users]
      assert module_result.docstring == "User management module"
      assert module_result.type == :module

      # Extract types from module body
      {:defmodule, _, [_, [do: body]]} = ast
      types = TypeDefinition.extract_all(body)
      assert length(types) == 2
      assert Enum.any?(types, &(&1.name == :user))
      assert Enum.any?(types, &(&1.name == :id))

      # Extract specs
      specs = FunctionSpec.extract_all(body)
      assert length(specs) == 2
      list_spec = Enum.find(specs, &(&1.name == :list_users))
      assert list_spec.arity == 0

      get_spec = Enum.find(specs, &(&1.name == :get_user))
      assert get_spec.arity == 1

      # Extract function clauses (Clause.extract_all gets all function defs)
      clauses = Clause.extract_all(body)
      assert length(clauses) == 3
      assert Enum.any?(clauses, &(&1.name == :list_users && &1.visibility == :public))
      assert Enum.any?(clauses, &(&1.name == :get_user && &1.visibility == :public))
      assert Enum.any?(clauses, &(&1.name == :validate_user && &1.visibility == :private))

      # Extract attributes
      attrs = Attribute.extract_all(body)
      # @moduledoc, @type x2, @doc x3, @spec x2 = 8 attributes
      assert length(attrs) >= 7
      moduledoc = Enum.find(attrs, &(&1.name == :moduledoc))
      assert moduledoc.value == "User management module"
    end

    test "extracts module with alias, import, require, use" do
      ast =
        quote do
          defmodule MyApp.Services.UserService do
            alias MyApp.Users
            alias MyApp.Repo, as: R
            import Enum, only: [map: 2, filter: 2]
            require Logger
            use GenServer

            def start_link(opts) do
              GenServer.start_link(__MODULE__, opts)
            end
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert result.name == [:MyApp, :Services, :UserService]

      # Check aliases
      assert length(result.aliases) == 2
      users_alias = Enum.find(result.aliases, &(&1.module == [:MyApp, :Users]))
      assert users_alias != nil
      repo_alias = Enum.find(result.aliases, &(&1.as == :R))
      assert repo_alias.module == [:MyApp, :Repo]

      # Check imports
      assert length(result.imports) == 1
      import_info = hd(result.imports)
      assert import_info.module == [:Enum]
      assert import_info.only == [map: 2, filter: 2]

      # Check requires
      assert length(result.requires) == 1
      assert hd(result.requires).module == [:Logger]

      # Check uses
      assert length(result.uses) == 1
      assert hd(result.uses).module == [:GenServer]
    end
  end

  # ===========================================================================
  # Test 2: GenServer Module with Callbacks
  # ===========================================================================

  describe "GenServer module extraction" do
    test "extracts GenServer module with behaviour and callbacks" do
      ast =
        quote do
          defmodule MyApp.Counter do
            @moduledoc "A simple counter GenServer"
            use GenServer
            @behaviour GenServer

            @type state :: integer()

            # Client API

            @doc "Starts the counter"
            @spec start_link(keyword()) :: GenServer.on_start()
            def start_link(opts \\ []) do
              GenServer.start_link(__MODULE__, 0, opts)
            end

            @spec increment(pid()) :: :ok
            def increment(pid) do
              GenServer.cast(pid, :increment)
            end

            @spec get_count(pid()) :: state()
            def get_count(pid) do
              GenServer.call(pid, :get_count)
            end

            # Server callbacks

            @impl true
            def init(initial_count) do
              {:ok, initial_count}
            end

            @impl GenServer
            def handle_call(:get_count, _from, state) do
              {:reply, state, state}
            end

            @impl GenServer
            def handle_cast(:increment, state) do
              {:noreply, state + 1}
            end
          end
        end

      # Extract module
      assert {:ok, module_result} = Module.extract(ast)
      assert module_result.name == [:MyApp, :Counter]
      assert module_result.docstring == "A simple counter GenServer"

      # Check use GenServer
      assert length(module_result.uses) == 1
      assert hd(module_result.uses).module == [:GenServer]

      # Extract body for further analysis
      {:defmodule, _, [_, [do: body]]} = ast

      # Extract attributes to find @behaviour
      attrs = Attribute.extract_all(body)
      behaviour_attr = Enum.find(attrs, &(&1.name == :behaviour))
      assert behaviour_attr != nil
      # The value is stored as AST: {:__aliases__, _, [:GenServer]}
      assert match?({:__aliases__, _, [:GenServer]}, behaviour_attr.value)

      # Extract @impl attributes
      impl_attrs = Enum.filter(attrs, &(&1.name == :impl))
      assert length(impl_attrs) == 3

      # Extract function clauses
      clauses = Clause.extract_all(body)
      assert length(clauses) >= 6

      # Check callback functions exist
      assert Enum.any?(clauses, &(&1.name == :init && &1.arity == 1))
      assert Enum.any?(clauses, &(&1.name == :handle_call && &1.arity == 3))
      assert Enum.any?(clauses, &(&1.name == :handle_cast && &1.arity == 2))

      # Check client API functions
      assert Enum.any?(clauses, &(&1.name == :start_link))
      assert Enum.any?(clauses, &(&1.name == :increment && &1.arity == 1))
      assert Enum.any?(clauses, &(&1.name == :get_count && &1.arity == 1))

      # Extract specs
      specs = FunctionSpec.extract_all(body)
      assert length(specs) >= 3
      assert Enum.any?(specs, &(&1.name == :start_link))
      assert Enum.any?(specs, &(&1.name == :increment))
      assert Enum.any?(specs, &(&1.name == :get_count))
    end
  end

  # ===========================================================================
  # Test 3: Multi-Clause Function Extraction Preserves Order
  # ===========================================================================

  describe "multi-clause function extraction" do
    test "preserves clause order for pattern-matched function" do
      # quote do with multiple defs creates a __block__
      {:__block__, _, defs} =
        quote do
          def factorial(0), do: 1
          def factorial(n) when n > 0, do: n * factorial(n - 1)
        end

      # Create a block from the individual def ASTs
      block_ast = {:__block__, [], defs}
      clauses = Clause.extract_all(block_ast)

      assert length(clauses) == 2

      # First clause: factorial(0)
      [first, second] = clauses
      assert first.order == 1
      assert first.name == :factorial
      assert first.arity == 1
      refute Clause.has_guard?(first)

      # Second clause: factorial(n) when n > 0
      assert second.order == 2
      assert second.name == :factorial
      assert second.arity == 1
      assert Clause.has_guard?(second)
    end

    test "preserves clause order for complex pattern matching" do
      {:__block__, _, defs} =
        quote do
          def process([]), do: []
          def process([head | tail]), do: [transform(head) | process(tail)]
          def process(other), do: [other]
        end

      block_ast = {:__block__, [], defs}
      clauses = Clause.extract_all(block_ast)

      assert length(clauses) == 3

      # Verify order is preserved
      orders = Enum.map(clauses, & &1.order)
      assert orders == [1, 2, 3]

      # All clauses have same name and arity
      assert Enum.all?(clauses, &(&1.name == :process))
      assert Enum.all?(clauses, &(&1.arity == 1))
    end

    test "extracts guards from multi-clause function" do
      {:__block__, _, defs} =
        quote do
          def classify(x) when is_integer(x) and x > 0, do: :positive_integer
          def classify(x) when is_integer(x) and x < 0, do: :negative_integer
          def classify(0), do: :zero
          def classify(x) when is_float(x), do: :float
          def classify(_), do: :other
        end

      block_ast = {:__block__, [], defs}
      clauses = Clause.extract_all(block_ast)

      assert length(clauses) == 5

      # Count clauses with guards
      clauses_with_guards = Enum.filter(clauses, &Clause.has_guard?/1)
      assert length(clauses_with_guards) == 3

      # Extract guards from first clause
      first_clause = hd(clauses)
      assert Clause.has_guard?(first_clause)
    end

    test "extracts parameters from each clause" do
      {:__block__, _, defs} =
        quote do
          def format(:date, value), do: format_date(value)
          def format(:time, value), do: format_time(value)
          def format(:datetime, value), do: format_datetime(value)
        end

      block_ast = {:__block__, [], defs}
      clauses = Clause.extract_all(block_ast)

      assert length(clauses) == 3

      # Each clause should have 2 parameters
      for clause <- clauses do
        params = Parameter.extract_all(clause.head.parameters)
        assert length(params) == 2
      end
    end
  end

  # ===========================================================================
  # Test 4: Parameter-to-Type Linking via Specs
  # ===========================================================================

  describe "parameter-to-type linking" do
    test "parameter count matches spec type count" do
      ast =
        quote do
          @spec calculate(integer(), float(), String.t()) :: float()
          def calculate(base, multiplier, label) do
            IO.puts(label)
            base * multiplier
          end
        end

      {:__block__, _, [spec_ast, func_ast]} = ast

      # Extract spec
      assert {:ok, spec} = FunctionSpec.extract(spec_ast)
      assert spec.name == :calculate
      assert spec.arity == 3
      assert length(spec.parameter_types) == 3

      # Extract function clause
      assert {:ok, clause} = Clause.extract(func_ast)
      assert clause.name == :calculate
      assert clause.arity == 3

      # Extract parameters from clause head
      params = Parameter.extract_all(clause.head.parameters)
      assert length(params) == 3

      # Verify spec parameter types
      [type1, type2, type3] = spec.parameter_types
      assert {:ok, t1} = TypeExpression.parse(type1)
      assert t1.kind == :basic
      assert t1.name == :integer

      assert {:ok, t2} = TypeExpression.parse(type2)
      assert t2.kind == :basic
      assert t2.name == :float

      assert {:ok, t3} = TypeExpression.parse(type3)
      assert t3.kind == :remote
    end

    test "spec return type is correctly parsed" do
      ast =
        quote do
          @spec find_user(integer()) :: {:ok, map()} | {:error, atom()}
        end

      assert {:ok, spec} = FunctionSpec.extract(ast)
      assert spec.name == :find_user
      assert spec.arity == 1

      # Return type should be a union type
      assert {:ok, return_type} = TypeExpression.parse(spec.return_type)
      assert return_type.kind == :union
      assert length(return_type.elements) == 2
    end

    test "spec with type constraints (when clause)" do
      ast =
        quote do
          @spec identity(a) :: a when a: any()
        end

      assert {:ok, spec} = FunctionSpec.extract(ast)
      assert spec.name == :identity
      assert spec.arity == 1
      assert spec.type_constraints != nil
      assert Map.has_key?(spec.type_constraints, :a)
    end

    test "spec with complex nested types" do
      ast =
        quote do
          @spec transform([{atom(), integer()}]) :: %{required(atom()) => integer()}
        end

      assert {:ok, spec} = FunctionSpec.extract(ast)

      # Parameter type should be a list of tuples
      [param_type] = spec.parameter_types
      assert {:ok, list_type} = TypeExpression.parse(param_type)
      assert list_type.kind == :list

      # Return type should be a map
      assert {:ok, return_type} = TypeExpression.parse(spec.return_type)
      assert return_type.kind == :map
    end
  end

  # ===========================================================================
  # Test 5: Macro Extraction in Metaprogramming-Heavy Module
  # ===========================================================================

  describe "macro extraction with metaprogramming" do
    test "extracts macro definitions" do
      ast =
        quote do
          defmodule MyDSL do
            defmacro define_getter(name) do
              quote do
                def unquote(name)() do
                  @unquote name
                end
              end
            end

            defmacrop internal_helper(expr) do
              quote do
                inspect(unquote(expr))
              end
            end
          end
        end

      # Extract module
      assert {:ok, module_result} = Module.extract(ast)
      assert module_result.name == [:MyDSL]

      # Extract macros from body
      {:defmodule, _, [_, [do: body]]} = ast
      macros = Macro.extract_all(body)

      assert length(macros) == 2

      # Check public macro
      define_getter = Enum.find(macros, &(&1.name == :define_getter))
      assert define_getter != nil
      assert define_getter.visibility == :public
      assert define_getter.arity == 1

      # Check private macro
      internal_helper = Enum.find(macros, &(&1.name == :internal_helper))
      assert internal_helper != nil
      assert internal_helper.visibility == :private
      assert internal_helper.arity == 1
    end

    test "extracts quote blocks within macros" do
      ast =
        quote do
          defmacro create_function(name, body) do
            quote do
              def unquote(name)() do
                unquote(body)
              end
            end
          end
        end

      assert {:ok, macro_result} = Macro.extract(ast)
      assert macro_result.name == :create_function
      assert macro_result.arity == 2

      # The macro body should contain a quote
      # Find quote in macro body
      quotes = Quote.extract_all(macro_result.body)
      assert length(quotes) >= 1

      quote_expr = hd(quotes)
      assert quote_expr.body != nil

      # Find unquotes within the quote
      unquotes = quote_expr.unquotes
      assert length(unquotes) >= 1
    end

    test "detects non-hygienic macros using var!" do
      # Create AST manually for var! usage
      ast =
        {:defmacro, [],
         [
           {:set_value, [], [{:val, [], nil}]},
           [
             do:
               {:quote, [],
                [
                  [
                    do:
                      {:=, [],
                       [
                         {:var!, [], [:value]},
                         {:unquote, [], [{:val, [], nil}]}
                       ]}
                  ]
                ]}
           ]
         ]}

      assert {:ok, macro_result} = Macro.extract(ast)
      refute Macro.hygienic?(macro_result)
      assert macro_result.metadata.uses_var_bang == true
    end

    test "extracts quote with bind_quoted option" do
      ast =
        quote do
          defmacro log_value(value) do
            quote bind_quoted: [value: value] do
              Logger.debug("Value: #{inspect(value)}")
            end
          end
        end

      assert {:ok, macro_result} = Macro.extract(ast)

      # Find quote in macro body
      quotes = Quote.extract_all(macro_result.body)
      assert length(quotes) == 1

      quote_expr = hd(quotes)
      assert Quote.has_bind_quoted?(quote_expr)
      assert quote_expr.options.bind_quoted != nil
    end

    test "finds unquote_splicing in macro" do
      ast =
        quote do
          defmacro define_functions(names) do
            quote do
              (unquote_splicing(
                 for name <- names do
                   quote do
                     def unquote(name)(), do: unquote(name)
                   end
                 end
               ))
            end
          end
        end

      assert {:ok, macro_result} = Macro.extract(ast)

      # Find quotes and check for unquote_splicing
      quotes = Quote.extract_all(macro_result.body)
      assert length(quotes) >= 1

      # The outer quote should have unquote_splicing
      outer_quote = hd(quotes)
      has_splicing = outer_quote.metadata.has_unquote_splicing
      assert has_splicing == true
    end
  end

  # ===========================================================================
  # Test 6: Return Expression Extraction
  # ===========================================================================

  describe "return expression extraction" do
    test "extracts return expression from simple function" do
      ast =
        quote do
          def greet(name) do
            "Hello, " <> name
          end
        end

      {:def, _, [_head, [do: body]]} = ast
      assert {:ok, return_expr} = ReturnExpression.extract(body)
      assert return_expr.type == :call
    end

    test "extracts return expression from multi-line function" do
      ast =
        quote do
          def process(data) do
            validated = validate(data)
            transformed = transform(validated)
            {:ok, transformed}
          end
        end

      {:def, _, [_head, [do: body]]} = ast
      assert {:ok, return_expr} = ReturnExpression.extract(body)
      assert return_expr.type == :literal
    end

    test "extracts return expression from case" do
      ast =
        quote do
          def check(value) do
            case value do
              :ok -> :success
              :error -> :failure
            end
          end
        end

      {:def, _, [_head, [do: body]]} = ast
      assert {:ok, return_expr} = ReturnExpression.extract(body)
      assert return_expr.type == :control_flow
    end
  end

  # ===========================================================================
  # Test 7: Type Definition Extraction
  # ===========================================================================

  describe "type definition extraction" do
    test "extracts all type variants" do
      ast =
        quote do
          @type public_type :: atom()
          @typep private_type :: integer()
          @opaque opaque_type :: map()
        end

      types = TypeDefinition.extract_all(ast)
      assert length(types) == 3

      public = Enum.find(types, &(&1.name == :public_type))
      assert public.visibility == :public

      private = Enum.find(types, &(&1.name == :private_type))
      assert private.visibility == :private

      opaque = Enum.find(types, &(&1.name == :opaque_type))
      assert opaque.visibility == :opaque
    end

    test "extracts parameterized types" do
      ast =
        quote do
          @type result(ok, error) :: {:ok, ok} | {:error, error}
        end

      assert {:ok, type_def} = TypeDefinition.extract(ast)
      assert type_def.name == :result
      assert type_def.arity == 2
      assert length(type_def.parameters) == 2
    end
  end

  # ===========================================================================
  # Test 8: Complete Workflow Integration
  # ===========================================================================

  describe "complete extraction workflow" do
    test "extracts all components from a realistic module" do
      ast =
        quote do
          defmodule MyApp.Calculator do
            @moduledoc """
            A calculator module demonstrating various Elixir features.
            """

            @type number_type :: integer() | float()
            @type result :: {:ok, number_type()} | {:error, String.t()}

            @default_precision 2

            @doc "Adds two numbers"
            @spec add(number_type(), number_type()) :: number_type()
            def add(a, b), do: a + b

            @doc "Divides two numbers safely"
            @spec divide(number_type(), number_type()) :: result()
            def divide(_a, 0), do: {:error, "Division by zero"}
            def divide(a, b), do: {:ok, a / b}

            @doc false
            defp round_result(value) do
              Float.round(value, @default_precision)
            end

            defmacro define_operation(name) do
              quote do
                def unquote(name)(a, b), do: a + b
              end
            end
          end
        end

      # 1. Extract module
      assert {:ok, module} = Module.extract(ast)
      assert module.name == [:MyApp, :Calculator]
      assert module.docstring != nil

      # Get body for component extraction
      {:defmodule, _, [_, [do: body]]} = ast

      # 2. Extract types
      types = TypeDefinition.extract_all(body)
      assert length(types) == 2
      assert Enum.any?(types, &(&1.name == :number_type))
      assert Enum.any?(types, &(&1.name == :result))

      # 3. Extract specs
      specs = FunctionSpec.extract_all(body)
      assert length(specs) == 2
      assert Enum.any?(specs, &(&1.name == :add))
      assert Enum.any?(specs, &(&1.name == :divide))

      # 4. Extract function clauses
      clauses = Clause.extract_all(body)
      assert length(clauses) >= 4

      # Public functions
      add_clause = Enum.find(clauses, &(&1.name == :add))
      assert add_clause.visibility == :public
      assert add_clause.arity == 2

      divide_clauses = Enum.filter(clauses, &(&1.name == :divide))
      assert length(divide_clauses) == 2

      # Private function
      round_clause = Enum.find(clauses, &(&1.name == :round_result))
      assert round_clause.visibility == :private

      # 5. Extract macros
      macros = Macro.extract_all(body)
      assert length(macros) == 1
      assert hd(macros).name == :define_operation

      # 6. Extract attributes
      attrs = Attribute.extract_all(body)
      assert Enum.any?(attrs, &(&1.name == :moduledoc))
      assert Enum.any?(attrs, &(&1.name == :default_precision))

      # 7. Verify function clauses for divide (has 2 clauses)
      divide_clause_orders = Enum.map(divide_clauses, & &1.order)
      # The orders depend on position in the module body
      assert length(divide_clause_orders) == 2
    end
  end
end
