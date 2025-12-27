defmodule ElixirOntologies.Extractors.MacroInvocationTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.MacroInvocation

  doctest MacroInvocation

  # ===========================================================================
  # Classification Tests
  # ===========================================================================

  describe "macro classification lists" do
    test "definition_macros includes def/defp/defmacro" do
      macros = MacroInvocation.definition_macros()
      assert :def in macros
      assert :defp in macros
      assert :defmacro in macros
      assert :defmacrop in macros
      assert :defmodule in macros
      assert :defstruct in macros
    end

    test "control_flow_macros includes if/case/with/for" do
      macros = MacroInvocation.control_flow_macros()
      assert :if in macros
      assert :unless in macros
      assert :case in macros
      assert :cond in macros
      assert :with in macros
      assert :for in macros
      assert :try in macros
      assert :receive in macros
    end

    test "import_macros includes import/require/use/alias" do
      macros = MacroInvocation.import_macros()
      assert :import in macros
      assert :require in macros
      assert :use in macros
      assert :alias in macros
    end

    test "quote_macros includes quote/unquote/unquote_splicing" do
      macros = MacroInvocation.quote_macros()
      assert :quote in macros
      assert :unquote in macros
      assert :unquote_splicing in macros
    end
  end

  # ===========================================================================
  # Macro Detection Tests
  # ===========================================================================

  describe "macro_invocation?/1" do
    test "returns true for def" do
      ast = {:def, [], [{:foo, [], []}, [do: :ok]]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns true for defp" do
      ast = {:defp, [], [{:bar, [], []}, [do: :ok]]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns true for defmodule" do
      ast = {:defmodule, [], [{:__aliases__, [], [:Foo]}, [do: nil]]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns true for if" do
      ast = {:if, [], [true, [do: :ok]]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns true for case" do
      ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:_], :ok]}]]]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns true for with" do
      ast = {:with, [], [{:<-, [], [{:x, [], nil}, {:ok, 1}]}, [do: {:x, [], nil}]]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns true for for" do
      ast = {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2, 3]]}, [do: {:x, [], nil}]]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns true for @ attribute" do
      ast = {:@, [], [{:doc, [], ["test"]}]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns true for quote" do
      ast = {:quote, [], [[do: :ok]]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns true for import" do
      ast = {:import, [], [{:__aliases__, [], [:Enum]}]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns true for require" do
      ast = {:require, [], [{:__aliases__, [], [:Logger]}]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns true for use" do
      ast = {:use, [], [{:__aliases__, [], [:GenServer]}]}
      assert MacroInvocation.macro_invocation?(ast)
    end

    test "returns false for regular function calls" do
      ast = {:my_function, [], [1, 2]}
      refute MacroInvocation.macro_invocation?(ast)
    end

    test "returns false for nil" do
      refute MacroInvocation.macro_invocation?(nil)
    end

    test "returns false for atoms" do
      refute MacroInvocation.macro_invocation?(:ok)
    end
  end

  describe "kernel_macro?/1" do
    test "returns true for kernel macros" do
      assert MacroInvocation.kernel_macro?(:def)
      assert MacroInvocation.kernel_macro?(:if)
      assert MacroInvocation.kernel_macro?(:case)
      assert MacroInvocation.kernel_macro?(:quote)
    end

    test "returns false for non-kernel macros" do
      refute MacroInvocation.kernel_macro?(:my_macro)
      refute MacroInvocation.kernel_macro?(:custom)
    end
  end

  # ===========================================================================
  # Definition Macro Extraction Tests
  # ===========================================================================

  describe "extract/2 definition macros" do
    test "extracts def invocation" do
      ast = {:def, [], [{:foo, [], [{:x, [], nil}]}, [do: {:x, [], nil}]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :def
      assert result.macro_module == Kernel
      assert result.category == :definition
      assert result.arity == 2
      assert length(result.arguments) == 2
    end

    test "extracts defp invocation" do
      ast = {:defp, [], [{:private_fn, [], []}, [do: :ok]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :defp
      assert result.category == :definition
    end

    test "extracts defmacro invocation" do
      ast = {:defmacro, [], [{:my_macro, [], [{:x, [], nil}]}, [do: {:x, [], nil}]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :defmacro
      assert result.category == :definition
    end

    test "extracts defmodule invocation" do
      ast = {:defmodule, [], [{:__aliases__, [], [:MyModule]}, [do: nil]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :defmodule
      assert result.category == :definition
    end

    test "extracts defstruct invocation" do
      ast = {:defstruct, [], [[:name, :age]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :defstruct
      assert result.category == :definition
    end

    test "extracts defprotocol invocation" do
      ast = {:defprotocol, [], [{:__aliases__, [], [:MyProtocol]}, [do: nil]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :defprotocol
      assert result.category == :definition
    end

    test "extracts defimpl invocation" do
      ast = {:defimpl, [], [{:__aliases__, [], [:MyProtocol]}, [for: String], [do: nil]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :defimpl
      assert result.category == :definition
    end
  end

  # ===========================================================================
  # Control Flow Macro Extraction Tests
  # ===========================================================================

  describe "extract/2 control flow macros" do
    test "extracts if invocation" do
      ast = {:if, [], [true, [do: :ok]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :if
      assert result.macro_module == Kernel
      assert result.category == :control_flow
      assert result.arity == 2
    end

    test "extracts if/else invocation" do
      ast = {:if, [], [true, [do: :ok, else: :error]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :if
      assert result.category == :control_flow
    end

    test "extracts unless invocation" do
      ast = {:unless, [], [false, [do: :ok]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :unless
      assert result.category == :control_flow
    end

    test "extracts case invocation" do
      ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:_], :ok]}]]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :case
      assert result.category == :control_flow
    end

    test "extracts cond invocation" do
      ast = {:cond, [], [[do: [{:->, [], [[true], :ok]}]]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :cond
      assert result.category == :control_flow
    end

    test "extracts with invocation" do
      ast = {:with, [], [{:<-, [], [{:x, [], nil}, {:ok, 1}]}, [do: {:x, [], nil}]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :with
      assert result.category == :control_flow
    end

    test "extracts for invocation" do
      ast = {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2, 3]]}, [do: {:x, [], nil}]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :for
      assert result.category == :control_flow
    end

    test "extracts try invocation" do
      ast = {:try, [], [[do: :ok, rescue: [{:->, [], [[{:e, [], nil}], :error]}]]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :try
      assert result.category == :control_flow
    end

    test "extracts receive invocation" do
      ast = {:receive, [], [[do: [{:->, [], [[{:msg, [], nil}], :ok]}]]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :receive
      assert result.category == :control_flow
    end

    test "extracts raise invocation" do
      ast = {:raise, [], ["error message"]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :raise
      assert result.category == :control_flow
    end
  end

  # ===========================================================================
  # Import Macro Extraction Tests
  # ===========================================================================

  describe "extract/2 import macros" do
    test "extracts import invocation" do
      ast = {:import, [], [{:__aliases__, [], [:Enum]}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :import
      assert result.category == :import
    end

    test "extracts import with only option" do
      ast = {:import, [], [{:__aliases__, [], [:Enum]}, [only: [map: 2]]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :import
      assert result.arity == 2
    end

    test "extracts require invocation" do
      ast = {:require, [], [{:__aliases__, [], [:Logger]}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :require
      assert result.category == :import
    end

    test "extracts use invocation" do
      ast = {:use, [], [{:__aliases__, [], [:GenServer]}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :use
      assert result.category == :import
    end

    test "extracts use with options" do
      ast = {:use, [], [{:__aliases__, [], [:GenServer]}, [restart: :temporary]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :use
      assert result.arity == 2
    end

    test "extracts alias invocation" do
      ast = {:alias, [], [{:__aliases__, [], [:MyModule, :SubModule]}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :alias
      assert result.category == :import
    end
  end

  # ===========================================================================
  # Attribute Macro Extraction Tests
  # ===========================================================================

  describe "extract/2 @ attribute macro" do
    test "extracts @doc attribute" do
      ast = {:@, [], [{:doc, [], ["Some documentation"]}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :@
      assert result.macro_module == Kernel
      assert result.category == :attribute
      assert result.metadata.attribute_name == :doc
    end

    test "extracts @moduledoc attribute" do
      ast = {:@, [], [{:moduledoc, [], ["Module documentation"]}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :@
      assert result.category == :attribute
      assert result.metadata.attribute_name == :moduledoc
    end

    test "extracts @spec attribute" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :@
      assert result.category == :attribute
      assert result.metadata.attribute_name == :spec
    end

    test "extracts @behaviour attribute" do
      ast = {:@, [], [{:behaviour, [], [{:__aliases__, [], [:GenServer]}]}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :@
      assert result.category == :attribute
      assert result.metadata.attribute_name == :behaviour
    end

    test "extracts custom attribute" do
      ast = {:@, [], [{:my_attr, [], [42]}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :@
      assert result.category == :attribute
      assert result.metadata.attribute_name == :my_attr
    end
  end

  # ===========================================================================
  # Quote Macro Extraction Tests
  # ===========================================================================

  describe "extract/2 quote macros" do
    test "extracts quote invocation" do
      ast = {:quote, [], [[do: :ok]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :quote
      assert result.category == :quote
    end

    test "extracts unquote invocation" do
      ast = {:unquote, [], [{:x, [], nil}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :unquote
      assert result.category == :quote
    end

    test "extracts unquote_splicing invocation" do
      ast = {:unquote_splicing, [], [{:list, [], nil}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :unquote_splicing
      assert result.category == :quote
    end
  end

  # ===========================================================================
  # Location Extraction Tests
  # ===========================================================================

  describe "extract/2 with location" do
    test "extracts location when present in metadata" do
      ast = {:if, [line: 10, column: 5], [true, [do: :ok]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.location != nil
      assert result.location.start_line == 10
      assert result.location.start_column == 5
    end

    test "location is nil when metadata has no line info" do
      ast = {:if, [], [true, [do: :ok]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.location == nil
    end

    test "respects include_location: false option" do
      ast = {:if, [line: 10], [true, [do: :ok]]}

      assert {:ok, result} = MacroInvocation.extract(ast, include_location: false)
      assert result.location == nil
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/2 error handling" do
    test "returns error for non-macro call" do
      ast = {:my_function, [], [1, 2]}

      assert {:error, message} = MacroInvocation.extract(ast)
      assert message =~ "Not a recognized macro invocation"
    end

    test "returns error for nil" do
      assert {:error, _} = MacroInvocation.extract(nil)
    end

    test "returns error for atom" do
      assert {:error, _} = MacroInvocation.extract(:ok)
    end
  end

  describe "extract!/2" do
    test "returns result for valid macro invocation" do
      ast = {:def, [], [{:foo, [], []}, [do: :ok]]}

      result = MacroInvocation.extract!(ast)
      assert result.macro_name == :def
    end

    test "raises for invalid input" do
      ast = {:not_a_macro, [], [1, 2]}

      assert_raise ArgumentError, fn ->
        MacroInvocation.extract!(ast)
      end
    end
  end

  # ===========================================================================
  # Bulk Extraction Tests
  # ===========================================================================

  describe "extract_all/2" do
    test "extracts all macro invocations from block" do
      body =
        {:__block__, [],
         [
           {:def, [], [{:foo, [], []}, [do: :ok]]},
           {:if, [], [true, [do: :ok]]},
           {:some_call, [], [1, 2]},
           {:@, [], [{:doc, [], ["test"]}]}
         ]}

      results = MacroInvocation.extract_all(body)
      assert length(results) == 3

      names = Enum.map(results, & &1.macro_name)
      assert :def in names
      assert :if in names
      assert :@ in names
    end

    test "returns empty list for nil" do
      assert MacroInvocation.extract_all(nil) == []
    end

    test "extracts from single statement" do
      ast = {:def, [], [{:foo, [], []}, [do: :ok]]}

      results = MacroInvocation.extract_all(ast)
      assert length(results) == 1
      assert hd(results).macro_name == :def
    end

    test "returns empty for non-macro statement" do
      ast = {:some_call, [], [1, 2]}
      assert MacroInvocation.extract_all(ast) == []
    end
  end

  describe "extract_all_recursive/2" do
    test "extracts nested macro invocations" do
      body = {:def, [], [{:foo, [], []}, [do: {:if, [], [true, [do: :ok]]}]]}

      results = MacroInvocation.extract_all_recursive(body)
      assert length(results) == 2

      names = Enum.map(results, & &1.macro_name)
      assert :def in names
      assert :if in names
    end

    test "extracts deeply nested macros" do
      body =
        {:defmodule, [],
         [
           {:__aliases__, [], [:Test]},
           [
             do:
               {:def, [],
                [
                  {:foo, [], []},
                  [
                    do:
                      {:case, [],
                       [{:x, [], nil}, [do: [{:->, [], [[:_], {:raise, [], ["error"]}]}]]]}
                  ]
                ]}
           ]
         ]}

      results = MacroInvocation.extract_all_recursive(body)

      names = Enum.map(results, & &1.macro_name)
      assert :defmodule in names
      assert :def in names
      assert :case in names
      assert :raise in names
    end
  end

  # ===========================================================================
  # Helper Function Tests
  # ===========================================================================

  describe "helper predicates" do
    test "definition?/1" do
      {:ok, def_inv} = MacroInvocation.extract({:def, [], [{:foo, [], []}, [do: :ok]]})
      {:ok, if_inv} = MacroInvocation.extract({:if, [], [true, [do: :ok]]})

      assert MacroInvocation.definition?(def_inv)
      refute MacroInvocation.definition?(if_inv)
    end

    test "control_flow?/1" do
      {:ok, if_inv} = MacroInvocation.extract({:if, [], [true, [do: :ok]]})
      {:ok, def_inv} = MacroInvocation.extract({:def, [], [{:foo, [], []}, [do: :ok]]})

      assert MacroInvocation.control_flow?(if_inv)
      refute MacroInvocation.control_flow?(def_inv)
    end

    test "import?/1" do
      {:ok, import_inv} = MacroInvocation.extract({:import, [], [{:__aliases__, [], [:Enum]}]})
      {:ok, def_inv} = MacroInvocation.extract({:def, [], [{:foo, [], []}, [do: :ok]]})

      assert MacroInvocation.import?(import_inv)
      refute MacroInvocation.import?(def_inv)
    end

    test "attribute?/1" do
      {:ok, attr_inv} = MacroInvocation.extract({:@, [], [{:doc, [], ["test"]}]})
      {:ok, def_inv} = MacroInvocation.extract({:def, [], [{:foo, [], []}, [do: :ok]]})

      assert MacroInvocation.attribute?(attr_inv)
      refute MacroInvocation.attribute?(def_inv)
    end
  end

  describe "invocation_id/1" do
    test "returns formatted identifier" do
      {:ok, inv} = MacroInvocation.extract({:def, [], [{:foo, [], [{:x, [], nil}]}, [do: :ok]]})
      assert MacroInvocation.invocation_id(inv) == "Kernel.def/2"
    end

    test "handles attribute macro" do
      {:ok, inv} = MacroInvocation.extract({:@, [], [{:doc, [], ["test"]}]})
      assert MacroInvocation.invocation_id(inv) == "Kernel.@/1"
    end
  end

  # ===========================================================================
  # Other Kernel Macro Tests
  # ===========================================================================

  describe "extract/2 other kernel macros" do
    test "extracts and macro" do
      ast = {:and, [], [true, false]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :and
      assert result.category == :other
    end

    test "extracts or macro" do
      ast = {:or, [], [true, false]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :or
      assert result.category == :other
    end

    test "extracts in macro" do
      ast = {:in, [], [{:x, [], nil}, [1, 2, 3]]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :in
      assert result.category == :other
    end

    test "extracts binding macro" do
      ast = {:binding, [], []}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :binding
      assert result.category == :other
    end
  end

  # ===========================================================================
  # Qualified Macro Call Tests (15.1.2)
  # ===========================================================================

  describe "qualified_call?/1" do
    test "returns true for Module.function form" do
      ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [], ["msg"]}
      assert MacroInvocation.qualified_call?(ast)
    end

    test "returns false for unqualified call" do
      ast = {:if, [], [true, [do: :ok]]}
      refute MacroInvocation.qualified_call?(ast)
    end
  end

  describe "extract/2 qualified macro calls" do
    test "extracts Logger.debug call" do
      ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [], ["message"]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :debug
      assert result.macro_module == Logger
      assert result.category == :library
      assert result.resolution_status == :resolved
      assert result.metadata.qualified == true
      assert result.arity == 1
    end

    test "extracts Logger.info call" do
      ast = {{:., [], [{:__aliases__, [], [:Logger]}, :info]}, [], ["info msg"]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :info
      assert result.macro_module == Logger
      assert result.category == :library
    end

    test "extracts Ecto.Query.from call" do
      ast =
        {{:., [], [{:__aliases__, [], [:Ecto, :Query]}, :from]}, [],
         [{:u, [], nil}, {:in, [], [{:__aliases__, [], [:User]}]}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :from
      assert result.macro_module == Ecto.Query
      assert result.category == :library
    end

    test "extracts custom module macro call" do
      ast = {{:., [], [{:__aliases__, [], [:MyMacros]}, :custom_macro]}, [], [1, 2]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :custom_macro
      assert result.macro_module == MyMacros
      assert result.category == :custom
      assert result.resolution_status == :resolved
    end

    test "extracts qualified call with atom module" do
      ast = {{:., [], [:erlang, :is_atom]}, [], [{:x, [], nil}]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.macro_name == :is_atom
      assert result.macro_module == :erlang
      assert result.category == :custom
    end

    test "extracts location for qualified call" do
      # The outer tuple has the line info
      ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [line: 15, column: 3], ["msg"]}

      assert {:ok, result} = MacroInvocation.extract(ast)
      assert result.location != nil
      assert result.location.start_line == 15
    end
  end

  # ===========================================================================
  # Library Macro Classification Tests (15.1.2)
  # ===========================================================================

  describe "library macro classification" do
    test "known_library_macros returns map" do
      macros = MacroInvocation.known_library_macros()
      assert is_map(macros)
      assert :debug in macros[Logger]
      assert :from in macros[Ecto.Query]
    end

    test "known_library_macro? returns true for Logger macros" do
      assert MacroInvocation.known_library_macro?(:debug)
      assert MacroInvocation.known_library_macro?(:info)
      assert MacroInvocation.known_library_macro?(:warning)
      assert MacroInvocation.known_library_macro?(:error)
    end

    test "known_library_macro? returns true for Ecto.Query macros" do
      assert MacroInvocation.known_library_macro?(:from)
      assert MacroInvocation.known_library_macro?(:where)
      assert MacroInvocation.known_library_macro?(:select)
    end

    test "known_library_macro? returns false for unknown macros" do
      refute MacroInvocation.known_library_macro?(:unknown_macro)
      refute MacroInvocation.known_library_macro?(:my_custom)
    end

    test "logger_macros returns Logger macro list" do
      macros = MacroInvocation.logger_macros()
      assert :debug in macros
      assert :info in macros
      assert :error in macros
    end

    test "ecto_query_macros returns Ecto.Query macro list" do
      macros = MacroInvocation.ecto_query_macros()
      assert :from in macros
      assert :where in macros
      assert :select in macros
      assert :join in macros
    end
  end

  # ===========================================================================
  # Import/Require Extraction Tests (15.1.2)
  # ===========================================================================

  describe "extract_imports/1" do
    test "extracts simple import" do
      {:ok, ast} = Code.string_to_quoted("import Enum")
      body = {:__block__, [], [ast]}

      [import_info] = MacroInvocation.extract_imports(body)
      assert import_info.module == Enum
      assert import_info.only == nil
      assert import_info.except == nil
    end

    test "extracts import with only option" do
      {:ok, ast} = Code.string_to_quoted("import Enum, only: [map: 2, filter: 2]")
      body = {:__block__, [], [ast]}

      [import_info] = MacroInvocation.extract_imports(body)
      assert import_info.module == Enum
      assert import_info.only == [map: 2, filter: 2]
    end

    test "extracts import with except option" do
      {:ok, ast} = Code.string_to_quoted("import Enum, except: [map: 2]")
      body = {:__block__, [], [ast]}

      [import_info] = MacroInvocation.extract_imports(body)
      assert import_info.module == Enum
      assert import_info.except == [map: 2]
    end

    test "extracts multiple imports" do
      {:ok, import1} = Code.string_to_quoted("import Enum")
      {:ok, import2} = Code.string_to_quoted("import String")
      body = {:__block__, [], [import1, import2]}

      imports = MacroInvocation.extract_imports(body)
      assert length(imports) == 2
      modules = Enum.map(imports, & &1.module)
      assert Enum in modules
      assert String in modules
    end

    test "returns empty list for no imports" do
      {:ok, ast} = Code.string_to_quoted("def foo, do: :ok")
      body = {:__block__, [], [ast]}

      assert MacroInvocation.extract_imports(body) == []
    end
  end

  describe "extract_requires/1" do
    test "extracts simple require" do
      {:ok, ast} = Code.string_to_quoted("require Logger")
      body = {:__block__, [], [ast]}

      [require_info] = MacroInvocation.extract_requires(body)
      assert require_info.module == Logger
      assert require_info.as == nil
    end

    test "extracts require with as option" do
      {:ok, ast} = Code.string_to_quoted("require Logger, as: L")
      body = {:__block__, [], [ast]}

      [require_info] = MacroInvocation.extract_requires(body)
      assert require_info.module == Logger
      assert require_info.as == L
    end

    test "extracts multiple requires" do
      {:ok, req1} = Code.string_to_quoted("require Logger")
      {:ok, req2} = Code.string_to_quoted("require Ecto.Query")
      body = {:__block__, [], [req1, req2]}

      requires = MacroInvocation.extract_requires(body)
      assert length(requires) == 2
      modules = Enum.map(requires, & &1.module)
      assert Logger in modules
      assert Ecto.Query in modules
    end

    test "returns empty list for no requires" do
      {:ok, ast} = Code.string_to_quoted("def foo, do: :ok")
      body = {:__block__, [], [ast]}

      assert MacroInvocation.extract_requires(body) == []
    end
  end

  # ===========================================================================
  # Resolution Status Tests (15.1.2)
  # ===========================================================================

  describe "resolution status" do
    test "kernel macros have :kernel resolution status" do
      {:ok, inv} = MacroInvocation.extract({:if, [], [true, [do: :ok]]})
      assert inv.resolution_status == :kernel
    end

    test "attribute macros have :kernel resolution status" do
      {:ok, inv} = MacroInvocation.extract({:@, [], [{:doc, [], ["test"]}]})
      assert inv.resolution_status == :kernel
    end

    test "qualified calls have :resolved status" do
      ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [], ["msg"]}
      {:ok, inv} = MacroInvocation.extract(ast)
      assert inv.resolution_status == :resolved
    end

    test "resolved?/1 returns true for kernel macros" do
      {:ok, inv} = MacroInvocation.extract({:if, [], [true, [do: :ok]]})
      assert MacroInvocation.resolved?(inv)
    end

    test "resolved?/1 returns true for qualified calls" do
      ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [], ["msg"]}
      {:ok, inv} = MacroInvocation.extract(ast)
      assert MacroInvocation.resolved?(inv)
    end

    test "unresolved?/1 returns true for unresolved status" do
      inv = %MacroInvocation{
        macro_name: :custom,
        macro_module: nil,
        arity: 0,
        category: :custom,
        resolution_status: :unresolved
      }

      assert MacroInvocation.unresolved?(inv)
    end

    test "filter_unresolved/1 filters to only unresolved" do
      resolved = %MacroInvocation{
        macro_name: :if,
        resolution_status: :kernel,
        arity: 2,
        category: :control_flow
      }

      unresolved = %MacroInvocation{
        macro_name: :custom,
        resolution_status: :unresolved,
        arity: 0,
        category: :custom
      }

      result = MacroInvocation.filter_unresolved([resolved, unresolved])
      assert length(result) == 1
      assert hd(result).macro_name == :custom
    end
  end

  # ===========================================================================
  # Qualified Predicate Tests (15.1.2)
  # ===========================================================================

  describe "qualified?/1" do
    test "returns true for qualified macro calls" do
      ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [], ["msg"]}
      {:ok, inv} = MacroInvocation.extract(ast)
      assert MacroInvocation.qualified?(inv)
    end

    test "returns false for unqualified macro calls" do
      {:ok, inv} = MacroInvocation.extract({:if, [], [true, [do: :ok]]})
      refute MacroInvocation.qualified?(inv)
    end
  end

  describe "library?/1" do
    test "returns true for known library macro calls" do
      ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [], ["msg"]}
      {:ok, inv} = MacroInvocation.extract(ast)
      assert MacroInvocation.library?(inv)
    end

    test "returns false for custom macro calls" do
      ast = {{:., [], [{:__aliases__, [], [:MyModule]}, :my_macro]}, [], []}
      {:ok, inv} = MacroInvocation.extract(ast)
      refute MacroInvocation.library?(inv)
    end

    test "returns false for kernel macros" do
      {:ok, inv} = MacroInvocation.extract({:if, [], [true, [do: :ok]]})
      refute MacroInvocation.library?(inv)
    end
  end

  # ===========================================================================
  # Recursive Extraction with Qualified Calls (15.1.2)
  # ===========================================================================

  describe "extract_all_recursive with qualified calls" do
    test "extracts qualified calls recursively" do
      # Logger.debug inside a function
      body =
        {:def, [],
         [
           {:foo, [], []},
           [do: {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [], ["msg"]}]
         ]}

      results = MacroInvocation.extract_all_recursive(body)
      names = Enum.map(results, & &1.macro_name)

      assert :def in names
      assert :debug in names
    end
  end

  # ===========================================================================
  # Macro Context Tests (15.1.3)
  # ===========================================================================

  describe "MacroContext struct" do
    alias MacroInvocation.MacroContext

    test "new/1 creates context with all fields" do
      ctx =
        MacroContext.new(
          module: MyModule,
          file: "lib/my_module.ex",
          line: 42,
          function: {:foo, 2},
          aliases: [{A, Some.Module}]
        )

      assert ctx.module == MyModule
      assert ctx.file == "lib/my_module.ex"
      assert ctx.line == 42
      assert ctx.function == {:foo, 2}
      assert ctx.aliases == [{A, Some.Module}]
    end

    test "new/0 creates empty context" do
      ctx = MacroContext.new()

      assert ctx.module == nil
      assert ctx.file == nil
      assert ctx.line == nil
      assert ctx.function == nil
      assert ctx.aliases == []
    end

    test "from_meta/1 extracts context from AST metadata" do
      meta = [line: 10, column: 5, file: "lib/test.ex"]
      ctx = MacroContext.from_meta(meta)

      assert ctx.line == 10
      assert ctx.file == "lib/test.ex"
      assert ctx.module == nil
      assert ctx.function == nil
    end

    test "from_meta/1 handles missing metadata" do
      ctx = MacroContext.from_meta([])

      assert ctx.line == nil
      assert ctx.file == nil
    end

    test "merge/2 combines context with options" do
      ctx = MacroContext.new(line: 10, file: "lib/foo.ex")
      merged = MacroContext.merge(ctx, module: MyModule, function: {:bar, 1})

      assert merged.line == 10
      assert merged.file == "lib/foo.ex"
      assert merged.module == MyModule
      assert merged.function == {:bar, 1}
    end

    test "merge/2 overrides with new values" do
      ctx = MacroContext.new(line: 10, module: OldModule)
      merged = MacroContext.merge(ctx, line: 20, module: NewModule)

      assert merged.line == 20
      assert merged.module == NewModule
    end

    test "populated?/1 returns true when any field is set" do
      assert MacroContext.populated?(MacroContext.new(line: 10))
      assert MacroContext.populated?(MacroContext.new(module: MyModule))
      assert MacroContext.populated?(MacroContext.new(file: "lib/foo.ex"))
      assert MacroContext.populated?(MacroContext.new(function: {:foo, 0}))
      assert MacroContext.populated?(MacroContext.new(aliases: [{A, B}]))
    end

    test "populated?/1 returns false for empty context" do
      refute MacroContext.populated?(MacroContext.new())
    end
  end

  # ===========================================================================
  # Context-Aware Extraction Tests (15.1.3)
  # ===========================================================================

  describe "extract_with_context/2" do
    test "extracts macro with context from AST metadata" do
      ast = {:if, [line: 10, column: 5], [true, [do: :ok]]}

      assert {:ok, inv} = MacroInvocation.extract_with_context(ast, module: MyModule)
      assert inv.macro_name == :if
      assert MacroInvocation.has_context?(inv)

      ctx = MacroInvocation.get_context(inv)
      assert ctx.module == MyModule
      assert ctx.line == 10
    end

    test "extracts macro with file from AST metadata" do
      ast = {:def, [line: 5, file: "lib/foo.ex"], [{:bar, [], []}, [do: :ok]]}

      assert {:ok, inv} = MacroInvocation.extract_with_context(ast, [])
      ctx = MacroInvocation.get_context(inv)

      assert ctx.line == 5
      assert ctx.file == "lib/foo.ex"
    end

    test "merges context options with AST metadata" do
      ast = {:case, [line: 15], [{:x, [], nil}, [do: [{:->, [], [[:_], :ok]}]]]}

      assert {:ok, inv} =
               MacroInvocation.extract_with_context(ast, module: TestMod, function: {:baz, 2})

      ctx = MacroInvocation.get_context(inv)

      assert ctx.line == 15
      assert ctx.module == TestMod
      assert ctx.function == {:baz, 2}
    end

    test "works without AST metadata" do
      ast = {:if, [], [true, [do: :ok]]}

      assert {:ok, inv} = MacroInvocation.extract_with_context(ast, module: MyModule)
      ctx = MacroInvocation.get_context(inv)

      assert ctx.module == MyModule
      assert ctx.line == nil
    end

    test "returns error for non-macro" do
      ast = {:not_a_macro, [], [1, 2]}

      assert {:error, _} = MacroInvocation.extract_with_context(ast, module: MyModule)
    end
  end

  describe "extract_with_context!/2" do
    test "returns result for valid macro" do
      ast = {:def, [line: 10], [{:foo, [], []}, [do: :ok]]}

      inv = MacroInvocation.extract_with_context!(ast, module: TestMod)
      assert inv.macro_name == :def
      assert MacroInvocation.context_module(inv) == TestMod
    end

    test "raises for invalid input" do
      ast = {:not_a_macro, [], []}

      assert_raise ArgumentError, fn ->
        MacroInvocation.extract_with_context!(ast, module: MyModule)
      end
    end
  end

  describe "extract_all_recursive_with_context/2" do
    test "extracts all macros with context" do
      body = {:def, [line: 1], [{:foo, [], []}, [do: {:if, [line: 2], [true, [do: :ok]]}]]}

      results = MacroInvocation.extract_all_recursive_with_context(body, module: MyMod)

      assert length(results) == 2
      assert Enum.all?(results, &MacroInvocation.has_context?/1)

      modules = Enum.map(results, &MacroInvocation.context_module/1)
      assert Enum.all?(modules, &(&1 == MyMod))
    end

    test "preserves individual line numbers" do
      body =
        {:__block__, [],
         [
           {:def, [line: 5], [{:foo, [], []}, [do: :ok]]},
           {:if, [line: 10], [true, [do: :ok]]}
         ]}

      results = MacroInvocation.extract_all_recursive_with_context(body, module: TestMod)

      lines = Enum.map(results, &MacroInvocation.context_line/1) |> Enum.sort()
      assert 5 in lines
      assert 10 in lines
    end

    test "applies function context to all invocations" do
      body = {:with, [line: 20], [{:<-, [], [{:x, [], nil}, {:ok, 1}]}, [do: {:x, [], nil}]]}

      results = MacroInvocation.extract_all_recursive_with_context(body, function: {:my_fn, 3})

      assert length(results) > 0
      assert Enum.all?(results, &(MacroInvocation.context_function(&1) == {:my_fn, 3}))
    end
  end

  # ===========================================================================
  # Context Helper Function Tests (15.1.3)
  # ===========================================================================

  describe "has_context?/1" do
    test "returns true when context has data" do
      ast = {:if, [line: 10], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract_with_context(ast, module: MyModule)

      assert MacroInvocation.has_context?(inv)
    end

    test "returns false when no context" do
      ast = {:if, [], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract(ast)

      refute MacroInvocation.has_context?(inv)
    end

    test "returns false for empty context" do
      ast = {:if, [], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract_with_context(ast, [])

      refute MacroInvocation.has_context?(inv)
    end
  end

  describe "get_context/1" do
    test "returns context when present" do
      ast = {:if, [line: 10], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract_with_context(ast, module: MyModule)

      ctx = MacroInvocation.get_context(inv)
      assert ctx != nil
      assert ctx.module == MyModule
    end

    test "returns nil when no context" do
      ast = {:if, [], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract(ast)

      assert MacroInvocation.get_context(inv) == nil
    end
  end

  describe "context_module/1" do
    test "returns module from context" do
      ast = {:if, [line: 10], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract_with_context(ast, module: MyModule)

      assert MacroInvocation.context_module(inv) == MyModule
    end

    test "returns nil when no context" do
      ast = {:if, [], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract(ast)

      assert MacroInvocation.context_module(inv) == nil
    end

    test "returns nil when module not set" do
      ast = {:if, [line: 10], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract_with_context(ast, [])

      assert MacroInvocation.context_module(inv) == nil
    end
  end

  describe "context_file/1" do
    test "returns file from context" do
      ast = {:if, [line: 10, file: "lib/test.ex"], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract_with_context(ast, [])

      assert MacroInvocation.context_file(inv) == "lib/test.ex"
    end

    test "returns nil when no file" do
      ast = {:if, [line: 10], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract_with_context(ast, [])

      assert MacroInvocation.context_file(inv) == nil
    end
  end

  describe "context_line/1" do
    test "returns line from context" do
      ast = {:if, [line: 42], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract_with_context(ast, [])

      assert MacroInvocation.context_line(inv) == 42
    end

    test "returns nil when no line" do
      ast = {:if, [], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract_with_context(ast, [])

      assert MacroInvocation.context_line(inv) == nil
    end
  end

  describe "context_function/1" do
    test "returns function from context" do
      ast = {:if, [line: 10], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract_with_context(ast, function: {:my_func, 2})

      assert MacroInvocation.context_function(inv) == {:my_func, 2}
    end

    test "returns nil when no function context" do
      ast = {:if, [line: 10], [true, [do: :ok]]}
      {:ok, inv} = MacroInvocation.extract_with_context(ast, module: MyModule)

      assert MacroInvocation.context_function(inv) == nil
    end
  end

  describe "context with qualified calls" do
    test "qualified calls can have context" do
      ast = {{:., [], [{:__aliases__, [], [:Logger]}, :debug]}, [line: 25], ["msg"]}

      {:ok, inv} =
        MacroInvocation.extract_with_context(ast, module: MyMod, function: {:log_it, 1})

      assert MacroInvocation.has_context?(inv)
      assert MacroInvocation.context_module(inv) == MyMod
      assert MacroInvocation.context_function(inv) == {:log_it, 1}
      assert MacroInvocation.context_line(inv) == 25
    end
  end
end
