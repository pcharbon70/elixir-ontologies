defmodule ElixirOntologies.Extractors.Directive.AliasTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Directive.Alias
  alias ElixirOntologies.Extractors.Directive.Alias.AliasDirective

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
end
