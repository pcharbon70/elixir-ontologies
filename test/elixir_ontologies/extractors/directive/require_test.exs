defmodule ElixirOntologies.Extractors.Directive.RequireTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Directive.Require
  alias ElixirOntologies.Extractors.Directive.Require.RequireDirective

  doctest ElixirOntologies.Extractors.Directive.Require

  describe "require?/1" do
    test "returns true for basic require" do
      ast = quote do: require(Logger)
      assert Require.require?(ast)
    end

    test "returns true for require with as" do
      ast = quote do: require(Logger, as: L)
      assert Require.require?(ast)
    end

    test "returns false for import" do
      ast = quote do: import(Enum)
      refute Require.require?(ast)
    end

    test "returns false for alias" do
      ast = quote do: alias(MyApp.Users)
      refute Require.require?(ast)
    end

    test "returns false for other expressions" do
      refute Require.require?(:atom)
      refute Require.require?("string")
      refute Require.require?(123)
    end
  end

  describe "extract/2 - basic requires" do
    test "extracts simple require" do
      ast = quote do: require(Logger)
      assert {:ok, directive} = Require.extract(ast)
      assert directive.module == [:Logger]
      assert directive.as == nil
    end

    test "extracts multi-part module require" do
      ast = quote do: require(MyApp.Macros.Helpers)
      assert {:ok, directive} = Require.extract(ast)
      assert directive.module == [:MyApp, :Macros, :Helpers]
    end

    test "extracts Erlang module require" do
      ast = {:require, [], [:ets]}
      assert {:ok, directive} = Require.extract(ast)
      assert directive.module == [:ets]
    end

    test "extracts location when available" do
      ast = {:require, [line: 10, column: 3], [{:__aliases__, [line: 10], [:Logger]}]}
      assert {:ok, directive} = Require.extract(ast)
      assert directive.location != nil
      assert directive.location.start_line == 10
    end

    test "returns error for non-require" do
      ast = quote do: import(Enum)
      assert {:error, {:not_a_require, _}} = Require.extract(ast)
    end
  end

  describe "extract/2 - as option" do
    test "extracts require with as option" do
      ast = quote do: require(Logger, as: L)
      assert {:ok, directive} = Require.extract(ast)
      assert directive.module == [:Logger]
      assert directive.as == :L
    end

    test "extracts require with multi-part as" do
      ast =
        {:require, [], [{:__aliases__, [], [:MyApp, :Macros]}, [as: {:__aliases__, [], [:M]}]]}

      assert {:ok, directive} = Require.extract(ast)
      assert directive.module == [:MyApp, :Macros]
      assert directive.as == :M
    end

    test "extracts Erlang module with as option" do
      ast = {:require, [], [:ets, [as: {:__aliases__, [], [:ETS]}]]}
      assert {:ok, directive} = Require.extract(ast)
      assert directive.module == [:ets]
      assert directive.as == :ETS
    end
  end

  describe "extract!/2" do
    test "returns directive for valid require" do
      ast = quote do: require(Logger)
      directive = Require.extract!(ast)
      assert %RequireDirective{} = directive
      assert directive.module == [:Logger]
    end

    test "raises for invalid require" do
      ast = quote do: import(Enum)

      assert_raise ArgumentError, ~r/Failed to extract require/, fn ->
        Require.extract!(ast)
      end
    end
  end

  describe "extract_all/2" do
    test "extracts all requires from statement list" do
      body = [
        quote(do: require(Logger)),
        quote(do: require(Macro)),
        quote(do: import(Enum)),
        quote(do: require(Code))
      ]

      directives = Require.extract_all(body)
      assert length(directives) == 3
      modules = Enum.map(directives, & &1.module)
      assert [:Logger] in modules
      assert [:Macro] in modules
      assert [:Code] in modules
    end

    test "extracts requires from __block__" do
      ast =
        {:__block__, [],
         [
           quote(do: require(Logger)),
           quote(do: require(Macro))
         ]}

      directives = Require.extract_all(ast)
      assert length(directives) == 2
    end

    test "returns empty list when no requires" do
      body = [
        quote(do: import(Enum)),
        quote(do: alias(MyApp.Users))
      ]

      assert Require.extract_all(body) == []
    end

    test "returns empty list for non-require single expression" do
      ast = quote do: def(foo, do: :ok)
      assert Require.extract_all(ast) == []
    end

    test "extracts single require from non-list AST" do
      ast = quote do: require(Logger)
      directives = Require.extract_all(ast)
      assert length(directives) == 1
      assert hd(directives).module == [:Logger]
    end
  end

  describe "module_name/1" do
    test "returns single module name" do
      directive = %RequireDirective{module: [:Logger]}
      assert Require.module_name(directive) == "Logger"
    end

    test "returns dotted module name" do
      directive = %RequireDirective{module: [:MyApp, :Macros, :Helpers]}
      assert Require.module_name(directive) == "MyApp.Macros.Helpers"
    end

    test "returns Erlang module name" do
      directive = %RequireDirective{module: [:ets]}
      assert Require.module_name(directive) == "ets"
    end
  end

  describe "extract_all_with_scope/2" do
    test "extracts module-level require with :module scope" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            require Logger
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Require.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :module
      assert hd(directives).module == [:Logger]
    end

    test "extracts function-level require with :function scope" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo do
              require Macro
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Require.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
      assert hd(directives).module == [:Macro]
    end

    test "extracts block-level require with :block scope inside function" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo do
              if true do
                require Code
              end
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Require.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :block
      assert hd(directives).module == [:Code]
    end

    test "extracts mixed scopes correctly" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            require Logger

            def foo do
              require Macro
            end

            require Code
          end
        end

      directives = Require.extract_all_with_scope(body)
      assert length(directives) == 3

      scopes = Enum.map(directives, & &1.scope)
      assert scopes == [:module, :function, :module]

      modules = Enum.map(directives, & &1.module)
      assert modules == [[:Logger], [:Macro], [:Code]]
    end

    test "handles defmacro with require" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            defmacro my_macro do
              require Macro
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Require.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
    end

    test "handles case block inside function" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo(x) do
              case x do
                :a -> require Logger
                :b -> require Macro
              end
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Require.extract_all_with_scope(body_list)
      assert length(directives) == 2
      assert Enum.all?(directives, &(&1.scope == :block))
    end

    test "handles function with guard clause" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo(x) when is_integer(x) do
              require Integer
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Require.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
    end

    test "preserves as option with scope" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            require Logger, as: L

            def foo do
              require Macro, as: M
            end
          end
        end

      directives = Require.extract_all_with_scope(body)
      assert length(directives) == 2

      [logger, macro] = directives
      assert logger.scope == :module
      assert logger.as == :L
      assert macro.scope == :function
      assert macro.as == :M
    end
  end

  describe "RequireDirective struct" do
    test "has correct default values" do
      directive = %RequireDirective{module: [:Logger]}
      assert directive.as == nil
      assert directive.location == nil
      assert directive.scope == nil
      assert directive.metadata == %{}
    end

    test "module is enforced" do
      assert_raise ArgumentError, ~r/must also be given/, fn ->
        struct!(RequireDirective, %{})
      end
    end
  end
end
