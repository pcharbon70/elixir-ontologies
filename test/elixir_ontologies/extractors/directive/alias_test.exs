defmodule ElixirOntologies.Extractors.Directive.AliasTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Directive.Alias
  alias ElixirOntologies.Extractors.Directive.Alias.{AliasDirective, MultiAliasGroup}

  doctest Alias

  # ===========================================================================
  # alias?/1 Tests
  # ===========================================================================

  describe "alias?/1" do
    test "returns true for simple alias" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}]}
      assert Alias.alias?(ast)
    end

    test "returns true for alias with as option" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}, [as: {:__aliases__, [], [:U]}]]}
      assert Alias.alias?(ast)
    end

    test "returns true for erlang module alias" do
      ast = {:alias, [], [:crypto]}
      assert Alias.alias?(ast)
    end

    test "returns false for import" do
      ast = {:import, [], [{:__aliases__, [], [:MyApp]}]}
      refute Alias.alias?(ast)
    end

    test "returns false for require" do
      ast = {:require, [], [{:__aliases__, [], [:Logger]}]}
      refute Alias.alias?(ast)
    end

    test "returns false for use" do
      ast = {:use, [], [{:__aliases__, [], [:GenServer]}]}
      refute Alias.alias?(ast)
    end

    test "returns false for non-directive" do
      refute Alias.alias?(:atom)
      refute Alias.alias?({:def, [], []})
      refute Alias.alias?(nil)
    end

    test "returns true for multi-alias" do
      ast =
        {:alias, [],
         [
           {{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [],
            [{:__aliases__, [], [:Users]}, {:__aliases__, [], [:Accounts]}]}
         ]}

      assert Alias.alias?(ast)
    end
  end

  # ===========================================================================
  # multi_alias?/1 Tests
  # ===========================================================================

  describe "multi_alias?/1" do
    test "returns true for basic multi-alias" do
      ast =
        {:alias, [],
         [
           {{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [],
            [{:__aliases__, [], [:Users]}, {:__aliases__, [], [:Accounts]}]}
         ]}

      assert Alias.multi_alias?(ast)
    end

    test "returns true for nested multi-alias" do
      ast =
        {:alias, [],
         [
           {{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [],
            [
              {{:., [], [{:__aliases__, [], [:Sub]}, :{}]}, [],
               [{:__aliases__, [], [:A]}, {:__aliases__, [], [:B]}]},
              {:__aliases__, [], [:Other]}
            ]}
         ]}

      assert Alias.multi_alias?(ast)
    end

    test "returns false for simple alias" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}]}
      refute Alias.multi_alias?(ast)
    end

    test "returns false for non-alias" do
      refute Alias.multi_alias?({:import, [], [{:__aliases__, [], [:MyApp]}]})
      refute Alias.multi_alias?(:atom)
    end
  end

  # ===========================================================================
  # simple_alias?/1 Tests
  # ===========================================================================

  describe "simple_alias?/1" do
    test "returns true for simple alias" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}]}
      assert Alias.simple_alias?(ast)
    end

    test "returns false for multi-alias" do
      ast =
        {:alias, [],
         [
           {{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [], [{:__aliases__, [], [:Users]}]}
         ]}

      refute Alias.simple_alias?(ast)
    end
  end

  # ===========================================================================
  # extract/2 Simple Alias Tests
  # ===========================================================================

  describe "extract/2 simple alias" do
    test "extracts simple single-segment alias" do
      ast = {:alias, [line: 1], [{:__aliases__, [line: 1], [:Users]}]}

      assert {:ok, %AliasDirective{} = directive} = Alias.extract(ast)
      assert directive.source == [:Users]
      assert directive.as == :Users
      assert directive.explicit_as == false
    end

    test "extracts simple multi-segment alias" do
      ast = {:alias, [line: 5], [{:__aliases__, [line: 5], [:MyApp, :Users]}]}

      assert {:ok, %AliasDirective{} = directive} = Alias.extract(ast)
      assert directive.source == [:MyApp, :Users]
      assert directive.as == :Users
      assert directive.explicit_as == false
    end

    test "extracts deeply nested module alias" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Accounts, :Users, :Admin]}]}

      assert {:ok, %AliasDirective{} = directive} = Alias.extract(ast)
      assert directive.source == [:MyApp, :Accounts, :Users, :Admin]
      assert directive.as == :Admin
      assert directive.explicit_as == false
    end

    test "computes alias name from last segment" do
      ast = {:alias, [], [{:__aliases__, [], [:Very, :Deep, :Module, :Path]}]}

      assert {:ok, directive} = Alias.extract(ast)
      assert directive.as == :Path
    end
  end

  # ===========================================================================
  # extract/2 Alias with :as Option Tests
  # ===========================================================================

  describe "extract/2 alias with :as option" do
    test "extracts alias with explicit :as option" do
      ast =
        {:alias, [line: 10],
         [{:__aliases__, [line: 10], [:MyApp, :Users]}, [as: {:__aliases__, [], [:U]}]]}

      assert {:ok, %AliasDirective{} = directive} = Alias.extract(ast)
      assert directive.source == [:MyApp, :Users]
      assert directive.as == :U
      assert directive.explicit_as == true
    end

    test "extracts alias with multi-segment :as option" do
      # Unusual but valid: alias MyApp.Users, as: Custom.Name
      ast =
        {:alias, [],
         [
           {:__aliases__, [], [:MyApp, :Users]},
           [as: {:__aliases__, [], [:Custom, :Name]}]
         ]}

      assert {:ok, directive} = Alias.extract(ast)
      assert directive.as == :Name
      assert directive.explicit_as == true
    end

    test "extracts alias with atom :as option" do
      # When :as is a bare atom (rare but possible)
      ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}, [as: :U]]}

      assert {:ok, directive} = Alias.extract(ast)
      assert directive.as == :U
      assert directive.explicit_as == true
    end
  end

  # ===========================================================================
  # extract/2 Erlang Module Tests
  # ===========================================================================

  describe "extract/2 erlang module" do
    test "extracts erlang module alias" do
      ast = {:alias, [line: 1], [:crypto]}

      assert {:ok, %AliasDirective{} = directive} = Alias.extract(ast)
      assert directive.source == [:crypto]
      assert directive.as == :crypto
      assert directive.explicit_as == false
    end

    test "extracts erlang module with :as option" do
      ast = {:alias, [line: 1], [:crypto, [as: {:__aliases__, [], [:Crypto]}]]}

      assert {:ok, directive} = Alias.extract(ast)
      assert directive.source == [:crypto]
      assert directive.as == :Crypto
      assert directive.explicit_as == true
    end

    test "extracts erlang module with atom :as option" do
      ast = {:alias, [], [:ets, [as: :ETS]]}

      assert {:ok, directive} = Alias.extract(ast)
      assert directive.source == [:ets]
      assert directive.as == :ETS
      assert directive.explicit_as == true
    end
  end

  # ===========================================================================
  # extract/2 Location Tests
  # ===========================================================================

  describe "extract/2 location extraction" do
    test "extracts source location when present" do
      ast = {:alias, [line: 15, column: 3], [{:__aliases__, [line: 15, column: 9], [:MyApp]}]}

      assert {:ok, directive} = Alias.extract(ast)
      assert directive.location != nil
      assert directive.location.start_line == 15
      assert directive.location.start_column == 3
    end

    test "location is nil when include_location is false" do
      ast = {:alias, [line: 15, column: 3], [{:__aliases__, [], [:MyApp]}]}

      assert {:ok, directive} = Alias.extract(ast, include_location: false)
      assert directive.location == nil
    end

    test "location is nil when meta is empty" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp]}]}

      assert {:ok, directive} = Alias.extract(ast)
      assert directive.location == nil
    end
  end

  # ===========================================================================
  # extract/2 Error Cases
  # ===========================================================================

  describe "extract/2 error cases" do
    test "returns error for non-alias node" do
      ast = {:import, [], [{:__aliases__, [], [:MyApp]}]}

      assert {:error, {:not_an_alias, _msg}} = Alias.extract(ast)
    end

    test "returns error for invalid ast" do
      assert {:error, {:not_an_alias, _msg}} = Alias.extract(:not_an_ast)
      assert {:error, {:not_an_alias, _msg}} = Alias.extract(nil)
      assert {:error, {:not_an_alias, _msg}} = Alias.extract({:alias, [], []})
    end
  end

  # ===========================================================================
  # extract!/2 Tests
  # ===========================================================================

  describe "extract!/2" do
    test "returns directive on success" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}]}

      directive = Alias.extract!(ast)
      assert %AliasDirective{} = directive
      assert directive.source == [:MyApp, :Users]
    end

    test "raises on error" do
      ast = {:import, [], [{:__aliases__, [], [:MyApp]}]}

      assert_raise ArgumentError, ~r/Failed to extract alias/, fn ->
        Alias.extract!(ast)
      end
    end
  end

  # ===========================================================================
  # extract_all/2 Tests
  # ===========================================================================

  describe "extract_all/2" do
    test "extracts all aliases from list of statements" do
      statements = [
        {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}]},
        {:alias, [], [{:__aliases__, [], [:MyApp, :Accounts]}]},
        {:def, [], [{:foo, [], nil}, [do: :ok]]}
      ]

      directives = Alias.extract_all(statements)
      assert length(directives) == 2
      assert Enum.map(directives, & &1.as) == [:Users, :Accounts]
    end

    test "extracts aliases from __block__" do
      ast =
        {:__block__, [],
         [
           {:alias, [], [{:__aliases__, [], [:A]}]},
           {:alias, [], [{:__aliases__, [], [:B]}]},
           {:alias, [], [{:__aliases__, [], [:C]}]}
         ]}

      directives = Alias.extract_all(ast)
      assert length(directives) == 3
      assert Enum.map(directives, & &1.as) == [:A, :B, :C]
    end

    test "returns empty list for no aliases" do
      statements = [
        {:import, [], [{:__aliases__, [], [:Enum]}]},
        {:def, [], [{:foo, [], nil}, [do: :ok]]}
      ]

      assert Alias.extract_all(statements) == []
    end

    test "extracts single alias" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp]}]}

      directives = Alias.extract_all(ast)
      assert length(directives) == 1
      assert hd(directives).as == :MyApp
    end

    test "returns empty list for non-alias single node" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      assert Alias.extract_all(ast) == []
    end
  end

  # ===========================================================================
  # Convenience Function Tests
  # ===========================================================================

  describe "source_module_name/1" do
    test "returns dot-separated module name" do
      directive = %AliasDirective{
        source: [:MyApp, :Users, :Admin],
        as: :Admin
      }

      assert Alias.source_module_name(directive) == "MyApp.Users.Admin"
    end

    test "returns single segment name" do
      directive = %AliasDirective{
        source: [:Users],
        as: :Users
      }

      assert Alias.source_module_name(directive) == "Users"
    end

    test "returns erlang module name lowercase" do
      directive = %AliasDirective{
        source: [:crypto],
        as: :Crypto
      }

      assert Alias.source_module_name(directive) == "crypto"
    end
  end

  describe "alias_name/1" do
    test "returns alias name as string" do
      directive = %AliasDirective{
        source: [:MyApp, :Users],
        as: :U
      }

      assert Alias.alias_name(directive) == "U"
    end
  end

  # ===========================================================================
  # Integration with quote Tests
  # ===========================================================================

  describe "integration with quoted code" do
    test "extracts from quoted simple alias" do
      ast =
        quote do
          alias MyApp.Users
        end

      assert {:ok, directive} = Alias.extract(ast)
      assert directive.source == [:MyApp, :Users]
      assert directive.as == :Users
    end

    test "extracts from quoted alias with :as" do
      ast =
        quote do
          alias MyApp.Users, as: U
        end

      assert {:ok, directive} = Alias.extract(ast)
      assert directive.source == [:MyApp, :Users]
      assert directive.as == :U
      assert directive.explicit_as == true
    end

    test "extracts from quoted deeply nested alias" do
      ast =
        quote do
          alias MyApp.Accounts.Users.Admin
        end

      assert {:ok, directive} = Alias.extract(ast)
      assert directive.source == [:MyApp, :Accounts, :Users, :Admin]
      assert directive.as == :Admin
    end

    test "extract_all from quoted module body" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule TestModule do
            alias MyApp.Users
            alias MyApp.Accounts, as: Acc
            alias MyApp.Products

            def foo, do: :ok
          end
        end

      directives = Alias.extract_all(body)
      assert length(directives) == 3
      assert Enum.map(directives, & &1.as) == [:Users, :Acc, :Products]
    end
  end

  # ===========================================================================
  # extract_multi_alias/2 Tests
  # ===========================================================================

  describe "extract_multi_alias/2" do
    test "extracts basic multi-alias" do
      ast =
        quote do
          alias MyApp.{Users, Accounts}
        end

      assert {:ok, directives} = Alias.extract_multi_alias(ast)
      assert length(directives) == 2

      [users, accounts] = directives
      assert users.source == [:MyApp, :Users]
      assert users.as == :Users
      assert accounts.source == [:MyApp, :Accounts]
      assert accounts.as == :Accounts
    end

    test "extracts multi-alias with three modules" do
      ast =
        quote do
          alias MyApp.{Users, Accounts, Products}
        end

      assert {:ok, directives} = Alias.extract_multi_alias(ast)
      assert length(directives) == 3
      assert Enum.map(directives, & &1.as) == [:Users, :Accounts, :Products]
    end

    test "extracts multi-alias with nested prefix" do
      ast =
        quote do
          alias MyApp.Sub.{A, B}
        end

      assert {:ok, directives} = Alias.extract_multi_alias(ast)
      assert length(directives) == 2

      [a, b] = directives
      assert a.source == [:MyApp, :Sub, :A]
      assert a.as == :A
      assert b.source == [:MyApp, :Sub, :B]
      assert b.as == :B
    end

    test "extracts multi-alias with nested suffixes" do
      ast =
        quote do
          alias MyApp.{Sub.A, Sub.B}
        end

      assert {:ok, directives} = Alias.extract_multi_alias(ast)
      assert length(directives) == 2

      [a, b] = directives
      assert a.source == [:MyApp, :Sub, :A]
      assert a.as == :A
      assert b.source == [:MyApp, :Sub, :B]
      assert b.as == :B
    end

    test "extracts deeply nested multi-alias" do
      ast =
        quote do
          alias MyApp.{Sub.{A, B}, Other}
        end

      assert {:ok, directives} = Alias.extract_multi_alias(ast)
      assert length(directives) == 3

      [a, b, other] = directives
      assert a.source == [:MyApp, :Sub, :A]
      assert a.as == :A
      assert b.source == [:MyApp, :Sub, :B]
      assert b.as == :B
      assert other.source == [:MyApp, :Other]
      assert other.as == :Other
    end

    test "sets from_multi_alias metadata" do
      ast =
        quote do
          alias MyApp.{Users, Accounts}
        end

      assert {:ok, directives} = Alias.extract_multi_alias(ast)

      for directive <- directives do
        assert directive.metadata.from_multi_alias == true
        assert directive.metadata.multi_alias_prefix == [:MyApp]
      end

      [users, accounts] = directives
      assert users.metadata.multi_alias_index == 0
      assert accounts.metadata.multi_alias_index == 1
    end

    test "returns error for simple alias" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}]}

      assert {:error, {:not_a_multi_alias, _msg}} = Alias.extract_multi_alias(ast)
    end

    test "respects max_nesting_depth option" do
      # Two levels of nesting: MyApp.{Sub.{A}}
      ast =
        quote do
          alias MyApp.{Sub.{A}}
        end

      # Should succeed with default depth (10)
      assert {:ok, directives} = Alias.extract_multi_alias(ast)
      assert length(directives) == 1

      # Should succeed with depth 2
      assert {:ok, _} = Alias.extract_multi_alias(ast, max_nesting_depth: 2)

      # Should fail with depth 0 (no nesting allowed at all)
      assert {:error, {:max_nesting_depth_exceeded, _msg}} =
               Alias.extract_multi_alias(ast, max_nesting_depth: 0)
    end

    test "returns error when max nesting depth exceeded" do
      # Build deeply nested multi-alias: A.{B.{C.{D}}}
      # This is 3 levels of nesting
      nested_ast =
        {:alias, [],
         [
           {{:., [],
             [
               {:__aliases__, [], [:A]},
               :{}
             ]}, [],
            [
              {{:., [],
                [
                  {:__aliases__, [], [:B]},
                  :{}
                ]}, [],
               [
                 {{:., [],
                   [
                     {:__aliases__, [], [:C]},
                     :{}
                   ]}, [], [{:__aliases__, [], [:D]}]}
               ]}
            ]}
         ]}

      # Should fail with max depth of 1 (since we have 3 levels of nesting)
      # Level 0: A.{...}, Level 1: B.{...}, Level 2: C.{...}
      assert {:error, {:max_nesting_depth_exceeded, message}} =
               Alias.extract_multi_alias(nested_ast, max_nesting_depth: 1)

      assert message =~ "exceeded"

      # Should succeed with max depth of 3
      assert {:ok, _} = Alias.extract_multi_alias(nested_ast, max_nesting_depth: 3)
    end
  end

  # ===========================================================================
  # extract_multi_alias_group/2 Tests
  # ===========================================================================

  describe "extract_multi_alias_group/2" do
    test "extracts group with prefix and aliases" do
      ast =
        quote do
          alias MyApp.{Users, Accounts}
        end

      assert {:ok, %MultiAliasGroup{} = group} = Alias.extract_multi_alias_group(ast)
      assert group.prefix == [:MyApp]
      assert length(group.aliases) == 2
      assert Enum.map(group.aliases, & &1.as) == [:Users, :Accounts]
    end

    test "extracts group with nested prefix" do
      ast =
        quote do
          alias MyApp.Sub.{A, B, C}
        end

      assert {:ok, group} = Alias.extract_multi_alias_group(ast)
      assert group.prefix == [:MyApp, :Sub]
      assert length(group.aliases) == 3
    end

    test "returns error for simple alias" do
      ast = {:alias, [], [{:__aliases__, [], [:MyApp, :Users]}]}

      assert {:error, {:not_a_multi_alias, _msg}} = Alias.extract_multi_alias_group(ast)
    end
  end

  # ===========================================================================
  # extract_all/2 with Multi-Alias Tests
  # ===========================================================================

  describe "extract_all/2 with multi-alias" do
    test "expands multi-alias in extract_all" do
      ast =
        quote do
          alias MyApp.{Users, Accounts}
        end

      directives = Alias.extract_all(ast)
      assert length(directives) == 2
      assert Enum.map(directives, & &1.as) == [:Users, :Accounts]
    end

    test "handles mixed simple and multi-alias" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule TestModule do
            alias MyApp.Users
            alias MyApp.{Accounts, Products}
            alias MyApp.Other

            def foo, do: :ok
          end
        end

      directives = Alias.extract_all(body)
      assert length(directives) == 4
      assert Enum.map(directives, & &1.as) == [:Users, :Accounts, :Products, :Other]
    end

    test "handles deeply nested multi-alias in extract_all" do
      ast =
        quote do
          alias MyApp.{Sub.{A, B}, Other}
        end

      directives = Alias.extract_all(ast)
      assert length(directives) == 3

      assert Enum.map(directives, & &1.source) == [
               [:MyApp, :Sub, :A],
               [:MyApp, :Sub, :B],
               [:MyApp, :Other]
             ]
    end
  end

  # ===========================================================================
  # extract_all_with_scope/2 Tests
  # ===========================================================================

  describe "extract_all_with_scope/2" do
    test "tags module-level aliases with :module scope" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            alias MyApp.Users
            alias MyApp.Accounts

            def foo, do: :ok
          end
        end

      directives = Alias.extract_all_with_scope(body)
      assert length(directives) == 2

      for directive <- directives do
        assert directive.scope == :module
      end
    end

    test "tags function-level aliases with :function scope" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            def foo do
              alias MyApp.Users
              :ok
            end

            defp bar do
              alias MyApp.Accounts
              :ok
            end
          end
        end

      directives = Alias.extract_all_with_scope(body)
      assert length(directives) == 2

      for directive <- directives do
        assert directive.scope == :function
      end
    end

    test "distinguishes module-level from function-level aliases" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            alias MyApp.ModuleLevel

            def foo do
              alias MyApp.FunctionLevel
              :ok
            end
          end
        end

      directives = Alias.extract_all_with_scope(body)
      assert length(directives) == 2

      [module_alias, function_alias] = directives
      assert module_alias.as == :ModuleLevel
      assert module_alias.scope == :module
      assert function_alias.as == :FunctionLevel
      assert function_alias.scope == :function
    end

    test "handles aliases in defmacro" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            defmacro my_macro do
              alias MyApp.MacroAlias
              quote do: :ok
            end
          end
        end

      # Wrap single statement in list for extract_all_with_scope
      body_list = if is_tuple(body), do: [body], else: body
      directives = Alias.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
    end

    test "handles aliases in if block inside function" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo(x) do
              if x do
                alias MyApp.InBlock
                :ok
              end
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Alias.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :block
    end

    test "handles aliases in case block inside function" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo(x) do
              case x do
                :a ->
                  alias MyApp.CaseA
                  :ok

                :b ->
                  alias MyApp.CaseB
                  :ok
              end
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Alias.extract_all_with_scope(body_list)
      assert length(directives) == 2

      for directive <- directives do
        assert directive.scope == :block
      end
    end

    test "handles multi-alias with scope tracking" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            alias MyApp.{Users, Accounts}

            def foo do
              alias MyApp.{Products, Orders}
              :ok
            end
          end
        end

      directives = Alias.extract_all_with_scope(body)
      assert length(directives) == 4

      module_aliases = Enum.filter(directives, &(&1.scope == :module))
      function_aliases = Enum.filter(directives, &(&1.scope == :function))

      assert length(module_aliases) == 2
      assert length(function_aliases) == 2
      assert Enum.map(module_aliases, & &1.as) == [:Users, :Accounts]
      assert Enum.map(function_aliases, & &1.as) == [:Products, :Orders]
    end

    test "handles function with guard clause" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo(x) when is_integer(x) do
              alias MyApp.WithGuard
              :ok
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Alias.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
      assert hd(directives).as == :WithGuard
    end

    test "handles nested functions (anonymous functions)" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo do
              alias MyApp.InFunction

              fn ->
                alias MyApp.InAnon
                :ok
              end
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Alias.extract_all_with_scope(body_list)
      # The alias in the anonymous function should still be found
      # Both are at function scope since we're inside a def
      assert length(directives) >= 1
      assert hd(directives).scope == :function
    end

    test "handles empty module body" do
      body = []
      directives = Alias.extract_all_with_scope(body)
      assert directives == []
    end

    test "handles module with no aliases" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            def foo, do: :ok
            def bar, do: :ok
          end
        end

      directives = Alias.extract_all_with_scope(body)
      assert directives == []
    end
  end

  # ===========================================================================
  # LexicalScope Struct Tests
  # ===========================================================================

  describe "LexicalScope struct" do
    alias ElixirOntologies.Extractors.Directive.Alias.LexicalScope

    test "can create module scope" do
      scope = %LexicalScope{type: :module, start_line: 1}
      assert scope.type == :module
      assert scope.start_line == 1
      assert scope.name == nil
    end

    test "can create function scope with name" do
      scope = %LexicalScope{type: :function, name: :my_func, start_line: 5}
      assert scope.type == :function
      assert scope.name == :my_func
    end

    test "can create nested scope with parent" do
      parent = %LexicalScope{type: :function, name: :foo, start_line: 5}
      child = %LexicalScope{type: :block, start_line: 7, parent: parent}
      assert child.type == :block
      assert child.parent.type == :function
      assert child.parent.name == :foo
    end
  end
end
