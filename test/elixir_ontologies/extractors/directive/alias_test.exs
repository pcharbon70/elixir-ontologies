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
           {{:., [], [{:__aliases__, [], [:MyApp]}, :{}]}, [],
            [{:__aliases__, [], [:Users]}]}
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
end
