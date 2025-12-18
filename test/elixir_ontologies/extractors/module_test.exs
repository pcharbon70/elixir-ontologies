defmodule ElixirOntologies.Extractors.ModuleTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Module

  doctest Module

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "module?/1" do
    test "returns true for simple module" do
      ast = {:defmodule, [], [{:__aliases__, [], [:MyModule]}, [do: nil]]}
      assert Module.module?(ast)
    end

    test "returns true for nested module name" do
      ast = {:defmodule, [], [{:__aliases__, [], [:MyApp, :Users]}, [do: nil]]}
      assert Module.module?(ast)
    end

    test "returns false for function definition" do
      ast = {:def, [], [{:foo, [], nil}]}
      refute Module.module?(ast)
    end

    test "returns false for non-AST values" do
      refute Module.module?(:not_a_module)
      refute Module.module?(123)
      refute Module.module?("string")
    end
  end

  # ===========================================================================
  # Basic Extraction Tests
  # ===========================================================================

  describe "extract/2 basic module" do
    test "extracts simple module" do
      ast = {:defmodule, [], [{:__aliases__, [], [:SimpleModule]}, [do: nil]]}

      assert {:ok, result} = Module.extract(ast)
      assert result.type == :module
      assert result.name == [:SimpleModule]
      assert result.docstring == nil
    end

    test "extracts multi-segment module name" do
      ast = {:defmodule, [], [{:__aliases__, [], [:MyApp, :Users, :Admin]}, [do: nil]]}

      assert {:ok, result} = Module.extract(ast)
      assert result.name == [:MyApp, :Users, :Admin]
    end

    test "extracts module with atom name" do
      ast = {:defmodule, [], [:SimpleAtom, [do: nil]]}

      assert {:ok, result} = Module.extract(ast)
      assert result.name == [:SimpleAtom]
    end

    test "returns error for non-module" do
      ast = {:def, [], [{:foo, [], nil}]}
      assert {:error, message} = Module.extract(ast)
      assert message =~ "Not a module definition"
    end
  end

  # ===========================================================================
  # Nested Module Tests
  # ===========================================================================

  describe "extract/2 nested modules" do
    test "detects nested module with parent" do
      ast = {:defmodule, [], [{:__aliases__, [], [:Child]}, [do: nil]]}

      assert {:ok, result} = Module.extract(ast, parent_module: [:Parent])
      assert result.type == :nested_module
      assert result.metadata.parent_module == [:Parent]
    end

    test "normal module has no parent" do
      ast = {:defmodule, [], [{:__aliases__, [], [:TopLevel]}, [do: nil]]}

      assert {:ok, result} = Module.extract(ast)
      assert result.type == :module
      assert result.metadata.parent_module == nil
    end

    test "detects nested module definitions in body" do
      ast =
        quote do
          defmodule Outer do
            defmodule Inner do
            end
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert [:Inner] in result.metadata.nested_modules
    end
  end

  # ===========================================================================
  # Moduledoc Tests
  # ===========================================================================

  describe "extract/2 @moduledoc" do
    test "extracts string moduledoc" do
      ast =
        quote do
          defmodule Documented do
            @moduledoc "This is the documentation"
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert result.docstring == "This is the documentation"
    end

    test "extracts heredoc moduledoc" do
      ast =
        quote do
          defmodule Documented do
            @moduledoc """
            Multi-line
            documentation
            """
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert result.docstring =~ "Multi-line"
      assert result.docstring =~ "documentation"
    end

    test "extracts @moduledoc false" do
      ast =
        quote do
          defmodule Hidden do
            @moduledoc false
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert result.docstring == false
    end

    test "module without moduledoc has nil docstring" do
      ast = {:defmodule, [], [{:__aliases__, [], [:NoDoc]}, [do: nil]]}

      assert {:ok, result} = Module.extract(ast)
      assert result.docstring == nil
    end
  end

  # ===========================================================================
  # Alias Extraction Tests
  # ===========================================================================

  describe "extract/2 aliases" do
    test "extracts simple alias" do
      ast =
        quote do
          defmodule WithAlias do
            alias MyApp.Users
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.aliases) == 1
      assert hd(result.aliases).module == [:MyApp, :Users]
      assert hd(result.aliases).as == nil
    end

    test "extracts alias with :as option" do
      ast =
        quote do
          defmodule WithAlias do
            alias MyApp.Users, as: U
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.aliases) == 1
      assert hd(result.aliases).module == [:MyApp, :Users]
      assert hd(result.aliases).as == :U
    end

    test "extracts multiple aliases" do
      ast =
        quote do
          defmodule WithAliases do
            alias MyApp.Users
            alias MyApp.Products
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.aliases) == 2
    end
  end

  # ===========================================================================
  # Import Extraction Tests
  # ===========================================================================

  describe "extract/2 imports" do
    test "extracts simple import" do
      ast =
        quote do
          defmodule WithImport do
            import Enum
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.imports) == 1
      assert hd(result.imports).module == [:Enum]
    end

    test "extracts import with :only" do
      ast =
        quote do
          defmodule WithImport do
            import Enum, only: [map: 2, filter: 2]
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.imports) == 1
      assert hd(result.imports).only == [map: 2, filter: 2]
    end

    test "extracts import with :except" do
      ast =
        quote do
          defmodule WithImport do
            import Enum, except: [map: 2]
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert hd(result.imports).except == [map: 2]
    end

    test "extracts erlang module import" do
      ast = {:defmodule, [], [{:__aliases__, [], [:WithErlang]}, [do: {:import, [], [:lists]}]]}

      assert {:ok, result} = Module.extract(ast)
      assert length(result.imports) == 1
      assert hd(result.imports).module == :lists
    end
  end

  # ===========================================================================
  # Require Extraction Tests
  # ===========================================================================

  describe "extract/2 requires" do
    test "extracts simple require" do
      ast =
        quote do
          defmodule WithRequire do
            require Logger
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.requires) == 1
      assert hd(result.requires).module == [:Logger]
    end

    test "extracts require with :as option" do
      ast =
        quote do
          defmodule WithRequire do
            require Logger, as: L
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert hd(result.requires).as == :L
    end
  end

  # ===========================================================================
  # Use Extraction Tests
  # ===========================================================================

  describe "extract/2 uses" do
    test "extracts simple use" do
      ast =
        quote do
          defmodule WithUse do
            use GenServer
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.uses) == 1
      assert hd(result.uses).module == [:GenServer]
    end

    test "extracts use with options" do
      ast =
        quote do
          defmodule WithUse do
            use GenServer, restart: :temporary
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert hd(result.uses).opts == [restart: :temporary]
    end
  end

  # ===========================================================================
  # Function Extraction Tests
  # ===========================================================================

  describe "extract/2 functions" do
    test "extracts public function" do
      ast =
        quote do
          defmodule WithFunc do
            def hello(name), do: name
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.functions) == 1
      assert hd(result.functions).name == :hello
      assert hd(result.functions).arity == 1
      assert hd(result.functions).visibility == :public
    end

    test "extracts private function" do
      ast =
        quote do
          defmodule WithFunc do
            defp internal(x), do: x
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.functions) == 1
      assert hd(result.functions).visibility == :private
    end

    test "extracts function with guard" do
      ast =
        quote do
          defmodule WithFunc do
            def process(x) when is_integer(x), do: x
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.functions) == 1
      assert hd(result.functions).name == :process
    end

    test "deduplicates multi-clause functions" do
      ast =
        quote do
          defmodule WithFunc do
            def process(:ok), do: :ok
            def process(:error), do: :error
          end
        end

      assert {:ok, result} = Module.extract(ast)
      # Should be deduplicated to one entry
      assert length(result.functions) == 1
    end

    test "extracts multiple functions with different arities" do
      ast =
        quote do
          defmodule WithFunc do
            def greet, do: "Hello"
            def greet(name), do: "Hello, #{name}"
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.functions) == 2

      arities = result.functions |> Enum.map(& &1.arity) |> Enum.sort()
      assert arities == [0, 1]
    end
  end

  # ===========================================================================
  # Macro Extraction Tests
  # ===========================================================================

  describe "extract/2 macros" do
    test "extracts public macro" do
      ast =
        quote do
          defmodule WithMacro do
            defmacro my_macro(expr), do: expr
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.macros) == 1
      assert hd(result.macros).name == :my_macro
      assert hd(result.macros).visibility == :public
    end

    test "extracts private macro" do
      ast =
        quote do
          defmodule WithMacro do
            defmacrop private_macro(x), do: x
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.macros) == 1
      assert hd(result.macros).visibility == :private
    end
  end

  # ===========================================================================
  # Type Extraction Tests
  # ===========================================================================

  describe "extract/2 types" do
    test "extracts public type" do
      ast =
        quote do
          defmodule WithType do
            @type my_type :: atom()
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.types) == 1
      assert hd(result.types).name == :my_type
      assert hd(result.types).visibility == :public
    end

    test "extracts private type" do
      ast =
        quote do
          defmodule WithType do
            @typep internal :: integer()
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.types) == 1
      assert hd(result.types).visibility == :private
    end

    test "extracts opaque type" do
      ast =
        quote do
          defmodule WithType do
            @opaque hidden :: %__MODULE__{}
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert length(result.types) == 1
      assert hd(result.types).visibility == :opaque
    end

    test "extracts parameterized type" do
      ast =
        quote do
          defmodule WithType do
            @type pair(a, b) :: {a, b}
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert hd(result.types).name == :pair
      assert hd(result.types).arity == 2
    end
  end

  # ===========================================================================
  # Convenience Function Tests
  # ===========================================================================

  describe "module_name_string/1" do
    test "returns dot-separated string" do
      ast = {:defmodule, [], [{:__aliases__, [], [:MyApp, :Users]}, [do: nil]]}
      {:ok, result} = Module.extract(ast)

      assert Module.module_name_string(result) == "MyApp.Users"
    end
  end

  describe "module_name_atom/1" do
    test "returns module atom" do
      ast = {:defmodule, [], [{:__aliases__, [], [:MyApp, :Users]}, [do: nil]]}
      {:ok, result} = Module.extract(ast)

      assert Module.module_name_atom(result) == MyApp.Users
    end
  end

  describe "has_docs?/1" do
    test "returns true for documented module" do
      ast =
        quote do
          defmodule Doc do
            @moduledoc "Has docs"
          end
        end

      {:ok, result} = Module.extract(ast)
      assert Module.has_docs?(result)
    end

    test "returns false for undocumented module" do
      ast = {:defmodule, [], [{:__aliases__, [], [:NoDoc]}, [do: nil]]}
      {:ok, result} = Module.extract(ast)

      refute Module.has_docs?(result)
    end

    test "returns false for @moduledoc false" do
      ast =
        quote do
          defmodule Hidden do
            @moduledoc false
          end
        end

      {:ok, result} = Module.extract(ast)
      refute Module.has_docs?(result)
    end
  end

  describe "docs_hidden?/1" do
    test "returns true for @moduledoc false" do
      ast =
        quote do
          defmodule Hidden do
            @moduledoc false
          end
        end

      {:ok, result} = Module.extract(ast)
      assert Module.docs_hidden?(result)
    end

    test "returns false for normal module" do
      ast =
        quote do
          defmodule Normal do
            @moduledoc "Visible docs"
          end
        end

      {:ok, result} = Module.extract(ast)
      refute Module.docs_hidden?(result)
    end
  end

  # ===========================================================================
  # Extract! Tests
  # ===========================================================================

  describe "extract!/2" do
    test "returns result on success" do
      ast = {:defmodule, [], [{:__aliases__, [], [:MyModule]}, [do: nil]]}
      result = Module.extract!(ast)

      assert result.name == [:MyModule]
    end

    test "raises on error" do
      ast = {:def, [], [{:foo, [], nil}]}

      assert_raise ArgumentError, ~r/Not a module definition/, fn ->
        Module.extract!(ast)
      end
    end
  end

  # ===========================================================================
  # Complex Module Tests
  # ===========================================================================

  describe "extract/2 complex modules" do
    test "extracts module with all components" do
      ast =
        quote do
          defmodule MyApp.Users do
            @moduledoc "User management"

            alias MyApp.Repo
            import Ecto.Query
            require Logger
            use GenServer

            @type t :: %__MODULE__{}

            def list, do: []
            defp internal, do: :ok
            defmacro my_macro(x), do: x
          end
        end

      assert {:ok, result} = Module.extract(ast)
      assert result.name == [:MyApp, :Users]
      assert result.docstring == "User management"
      assert length(result.aliases) == 1
      assert length(result.imports) == 1
      assert length(result.requires) == 1
      assert length(result.uses) == 1
      assert length(result.functions) == 2
      assert length(result.macros) == 1
      assert length(result.types) == 1
    end
  end
end
