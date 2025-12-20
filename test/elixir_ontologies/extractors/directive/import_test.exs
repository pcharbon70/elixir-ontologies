defmodule ElixirOntologies.Extractors.Directive.ImportTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Directive.Import
  alias ElixirOntologies.Extractors.Directive.Import.ImportDirective

  doctest ElixirOntologies.Extractors.Directive.Import

  describe "import?/1" do
    test "returns true for basic import" do
      ast = quote do: import(Enum)
      assert Import.import?(ast)
    end

    test "returns true for import with only" do
      ast = quote do: import(Enum, only: [map: 2])
      assert Import.import?(ast)
    end

    test "returns true for import with except" do
      ast = quote do: import(Enum, except: [reduce: 3])
      assert Import.import?(ast)
    end

    test "returns false for alias" do
      ast = quote do: alias(MyApp.Users)
      refute Import.import?(ast)
    end

    test "returns false for require" do
      ast = quote do: require(Logger)
      refute Import.import?(ast)
    end

    test "returns false for other expressions" do
      refute Import.import?(:atom)
      refute Import.import?("string")
      refute Import.import?(123)
    end
  end

  describe "extract/2 - basic imports" do
    test "extracts simple import" do
      ast = quote do: import(Enum)
      assert {:ok, directive} = Import.extract(ast)
      assert directive.module == [:Enum]
      assert directive.only == nil
      assert directive.except == nil
    end

    test "extracts multi-part module import" do
      ast = quote do: import(MyApp.Utils.Helpers)
      assert {:ok, directive} = Import.extract(ast)
      assert directive.module == [:MyApp, :Utils, :Helpers]
    end

    test "extracts Erlang module import" do
      ast = {:import, [], [:lists]}
      assert {:ok, directive} = Import.extract(ast)
      assert directive.module == [:lists]
    end

    test "extracts location when available" do
      ast = {:import, [line: 10, column: 3], [{:__aliases__, [line: 10], [:Enum]}]}
      assert {:ok, directive} = Import.extract(ast)
      assert directive.location != nil
      assert directive.location.start_line == 10
    end

    test "returns error for non-import" do
      ast = quote do: alias(MyApp.Users)
      assert {:error, {:not_an_import, _}} = Import.extract(ast)
    end
  end

  describe "extract/2 - only option" do
    test "extracts import with function/arity list" do
      ast = quote do: import(Enum, only: [map: 2, filter: 2, reduce: 3])
      assert {:ok, directive} = Import.extract(ast)
      assert directive.module == [:Enum]
      assert directive.only == [map: 2, filter: 2, reduce: 3]
      assert directive.except == nil
    end

    test "extracts import with single function" do
      ast = quote do: import(Enum, only: [map: 2])
      assert {:ok, directive} = Import.extract(ast)
      assert directive.only == [map: 2]
    end

    test "extracts import with only: :functions" do
      ast = quote do: import(Enum, only: :functions)
      assert {:ok, directive} = Import.extract(ast)
      assert directive.only == :functions
    end

    test "extracts import with only: :macros" do
      ast = quote do: import(Kernel, only: :macros)
      assert {:ok, directive} = Import.extract(ast)
      assert directive.only == :macros
    end

    test "extracts import with only: :sigils" do
      ast = quote do: import(Kernel, only: :sigils)
      assert {:ok, directive} = Import.extract(ast)
      assert directive.only == :sigils
    end
  end

  describe "extract/2 - except option" do
    test "extracts import with except list" do
      ast = quote do: import(Enum, except: [reduce: 3, map: 2])
      assert {:ok, directive} = Import.extract(ast)
      assert directive.module == [:Enum]
      assert directive.except == [reduce: 3, map: 2]
      assert directive.only == nil
    end

    test "extracts import with single except" do
      ast = quote do: import(Enum, except: [reduce: 3])
      assert {:ok, directive} = Import.extract(ast)
      assert directive.except == [reduce: 3]
    end
  end

  describe "extract!/2" do
    test "returns directive for valid import" do
      ast = quote do: import(Enum)
      directive = Import.extract!(ast)
      assert %ImportDirective{} = directive
      assert directive.module == [:Enum]
    end

    test "raises for invalid import" do
      ast = quote do: alias(MyApp.Users)

      assert_raise ArgumentError, ~r/Failed to extract import/, fn ->
        Import.extract!(ast)
      end
    end
  end

  describe "extract_all/2" do
    test "extracts all imports from statement list" do
      body = [
        quote(do: import(Enum)),
        quote(do: import(String)),
        quote(do: alias(MyApp.Users)),
        quote(do: import(Map))
      ]

      directives = Import.extract_all(body)
      assert length(directives) == 3
      modules = Enum.map(directives, & &1.module)
      assert [:Enum] in modules
      assert [:String] in modules
      assert [:Map] in modules
    end

    test "extracts imports from __block__" do
      ast =
        {:__block__, [],
         [
           quote(do: import(Enum)),
           quote(do: import(String))
         ]}

      directives = Import.extract_all(ast)
      assert length(directives) == 2
    end

    test "returns empty list when no imports" do
      body = [
        quote(do: alias(MyApp.Users)),
        quote(do: require(Logger))
      ]

      assert Import.extract_all(body) == []
    end

    test "returns empty list for non-import single expression" do
      ast = quote do: def(foo, do: :ok)
      assert Import.extract_all(ast) == []
    end

    test "extracts single import from non-list AST" do
      ast = quote do: import(Enum)
      directives = Import.extract_all(ast)
      assert length(directives) == 1
      assert hd(directives).module == [:Enum]
    end
  end

  describe "module_name/1" do
    test "returns single module name" do
      directive = %ImportDirective{module: [:Enum]}
      assert Import.module_name(directive) == "Enum"
    end

    test "returns dotted module name" do
      directive = %ImportDirective{module: [:MyApp, :Utils, :Helpers]}
      assert Import.module_name(directive) == "MyApp.Utils.Helpers"
    end

    test "returns Erlang module name" do
      directive = %ImportDirective{module: [:lists]}
      assert Import.module_name(directive) == "lists"
    end
  end

  describe "full_import?/1" do
    test "returns true when no only or except" do
      directive = %ImportDirective{module: [:Enum]}
      assert Import.full_import?(directive)
    end

    test "returns false when only is set" do
      directive = %ImportDirective{module: [:Enum], only: [map: 2]}
      refute Import.full_import?(directive)
    end

    test "returns false when except is set" do
      directive = %ImportDirective{module: [:Enum], except: [reduce: 3]}
      refute Import.full_import?(directive)
    end

    test "returns false when only is type-based" do
      directive = %ImportDirective{module: [:Kernel], only: :macros}
      refute Import.full_import?(directive)
    end
  end

  describe "type_import?/1" do
    test "returns true for :functions" do
      directive = %ImportDirective{module: [:Enum], only: :functions}
      assert Import.type_import?(directive)
    end

    test "returns true for :macros" do
      directive = %ImportDirective{module: [:Kernel], only: :macros}
      assert Import.type_import?(directive)
    end

    test "returns true for :sigils" do
      directive = %ImportDirective{module: [:Kernel], only: :sigils}
      assert Import.type_import?(directive)
    end

    test "returns false for function list" do
      directive = %ImportDirective{module: [:Enum], only: [map: 2]}
      refute Import.type_import?(directive)
    end

    test "returns false for nil only" do
      directive = %ImportDirective{module: [:Enum]}
      refute Import.type_import?(directive)
    end
  end

  describe "ImportDirective struct" do
    test "has correct default values" do
      directive = %ImportDirective{module: [:Enum]}
      assert directive.only == nil
      assert directive.except == nil
      assert directive.location == nil
      assert directive.scope == nil
      assert directive.metadata == %{}
    end

    test "module is enforced" do
      assert_raise ArgumentError, ~r/must also be given/, fn ->
        struct!(ImportDirective, %{})
      end
    end
  end

  describe "extract_all_with_scope/2" do
    test "extracts module-level import with :module scope" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            import Enum
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Import.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :module
      assert hd(directives).module == [:Enum]
    end

    test "extracts function-level import with :function scope" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo do
              import String
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Import.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
      assert hd(directives).module == [:String]
    end

    test "extracts block-level import with :block scope inside function" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo do
              if true do
                import Map
              end
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Import.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :block
      assert hd(directives).module == [:Map]
    end

    test "extracts mixed scopes correctly" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            import Enum

            def foo do
              import String
            end

            import Map
          end
        end

      directives = Import.extract_all_with_scope(body)
      assert length(directives) == 3

      scopes = Enum.map(directives, & &1.scope)
      assert scopes == [:module, :function, :module]

      modules = Enum.map(directives, & &1.module)
      assert modules == [[:Enum], [:String], [:Map]]
    end

    test "handles defp with import" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            defp helper do
              import List
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Import.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
    end

    test "handles defmacro with import" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            defmacro my_macro do
              import Macro
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Import.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
    end

    test "handles case block inside function" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo(x) do
              case x do
                :a -> import Enum
                :b -> import String
              end
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Import.extract_all_with_scope(body_list)
      assert length(directives) == 2
      assert Enum.all?(directives, &(&1.scope == :block))
    end

    test "handles with block inside function" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo do
              with {:ok, _} <- {:ok, 1} do
                import Keyword
              end
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Import.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :block
    end

    test "handles function with guard clause" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo(x) when is_integer(x) do
              import Integer
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Import.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
    end

    test "handles nested functions" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            import Enum

            def foo do
              import String

              fn ->
                import Map
              end
            end

            def bar do
              import List
            end
          end
        end

      directives = Import.extract_all_with_scope(body)
      assert length(directives) == 4

      modules = Enum.map(directives, & &1.module)
      assert [:Enum] in modules
      assert [:String] in modules
      assert [:Map] in modules
      assert [:List] in modules
    end

    test "preserves only/except options with scope" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            import Enum, only: [map: 2]

            def foo do
              import String, except: [upcase: 1]
            end
          end
        end

      directives = Import.extract_all_with_scope(body)
      assert length(directives) == 2

      [enum_import, string_import] = directives
      assert enum_import.scope == :module
      assert enum_import.only == [map: 2]
      assert string_import.scope == :function
      assert string_import.except == [upcase: 1]
    end
  end
end
