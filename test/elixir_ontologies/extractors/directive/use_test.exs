defmodule ElixirOntologies.Extractors.Directive.UseTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Directive.Use
  alias ElixirOntologies.Extractors.Directive.Use.UseDirective

  doctest ElixirOntologies.Extractors.Directive.Use

  describe "use?/1" do
    test "returns true for basic use" do
      ast = quote do: use(GenServer)
      assert Use.use?(ast)
    end

    test "returns true for use with options" do
      ast = quote do: use(GenServer, restart: :temporary)
      assert Use.use?(ast)
    end

    test "returns false for import" do
      ast = quote do: import(Enum)
      refute Use.use?(ast)
    end

    test "returns false for require" do
      ast = quote do: require(Logger)
      refute Use.use?(ast)
    end

    test "returns false for alias" do
      ast = quote do: alias(MyApp.Users)
      refute Use.use?(ast)
    end

    test "returns false for other expressions" do
      refute Use.use?(:atom)
      refute Use.use?("string")
      refute Use.use?(123)
    end
  end

  describe "extract/2 - basic use" do
    test "extracts simple use" do
      ast = quote do: use(GenServer)
      assert {:ok, directive} = Use.extract(ast)
      assert directive.module == [:GenServer]
      assert directive.options == nil
    end

    test "extracts multi-part module use" do
      ast = quote do: use(Plug.Builder)
      assert {:ok, directive} = Use.extract(ast)
      assert directive.module == [:Plug, :Builder]
    end

    test "extracts Erlang module use" do
      ast = {:use, [], [:gen_server]}
      assert {:ok, directive} = Use.extract(ast)
      assert directive.module == [:gen_server]
    end

    test "extracts location when available" do
      ast = {:use, [line: 10, column: 3], [{:__aliases__, [line: 10], [:GenServer]}]}
      assert {:ok, directive} = Use.extract(ast)
      assert directive.location != nil
      assert directive.location.start_line == 10
    end

    test "returns error for non-use" do
      ast = quote do: import(Enum)
      assert {:error, {:not_a_use, _}} = Use.extract(ast)
    end
  end

  describe "extract/2 - keyword options" do
    test "extracts use with single keyword option" do
      ast = quote do: use(GenServer, restart: :temporary)
      assert {:ok, directive} = Use.extract(ast)
      assert directive.module == [:GenServer]
      assert directive.options == [restart: :temporary]
    end

    test "extracts use with multiple keyword options" do
      ast = quote do: use(Plug.Builder, init_mode: :runtime, log_on_halt: :debug)
      assert {:ok, directive} = Use.extract(ast)
      assert directive.module == [:Plug, :Builder]
      assert directive.options == [init_mode: :runtime, log_on_halt: :debug]
    end

    test "extracts use with complex option values" do
      ast = quote do: use(Phoenix.Controller, namespace: MyApp.Web)
      assert {:ok, directive} = Use.extract(ast)
      assert directive.module == [:Phoenix, :Controller]
      assert is_list(directive.options)
    end
  end

  describe "extract/2 - non-keyword options" do
    test "extracts use with atom option" do
      ast = quote do: use(MyApp.Web, :controller)
      assert {:ok, directive} = Use.extract(ast)
      assert directive.module == [:MyApp, :Web]
      assert directive.options == :controller
    end

    test "extracts use with string option" do
      ast = {:use, [], [{:__aliases__, [], [:MyApp, :Web]}, "live_view"]}
      assert {:ok, directive} = Use.extract(ast)
      assert directive.module == [:MyApp, :Web]
      assert directive.options == "live_view"
    end

    test "extracts Erlang module with options" do
      ast = {:use, [], [:gen_server, [restart: :temporary]]}
      assert {:ok, directive} = Use.extract(ast)
      assert directive.module == [:gen_server]
      assert directive.options == [restart: :temporary]
    end
  end

  describe "extract!/2" do
    test "returns directive for valid use" do
      ast = quote do: use(GenServer)
      directive = Use.extract!(ast)
      assert %UseDirective{} = directive
      assert directive.module == [:GenServer]
    end

    test "raises for invalid use" do
      ast = quote do: import(Enum)

      assert_raise ArgumentError, ~r/Failed to extract use/, fn ->
        Use.extract!(ast)
      end
    end
  end

  describe "extract_all/2" do
    test "extracts all uses from statement list" do
      body = [
        quote(do: use(GenServer)),
        quote(do: use(Supervisor)),
        quote(do: import(Enum)),
        quote(do: use(Agent))
      ]

      directives = Use.extract_all(body)
      assert length(directives) == 3
      modules = Enum.map(directives, & &1.module)
      assert [:GenServer] in modules
      assert [:Supervisor] in modules
      assert [:Agent] in modules
    end

    test "extracts uses from __block__" do
      ast =
        {:__block__, [],
         [
           quote(do: use(GenServer)),
           quote(do: use(Supervisor))
         ]}

      directives = Use.extract_all(ast)
      assert length(directives) == 2
    end

    test "returns empty list when no uses" do
      body = [
        quote(do: import(Enum)),
        quote(do: alias(MyApp.Users))
      ]

      assert Use.extract_all(body) == []
    end

    test "returns empty list for non-use single expression" do
      ast = quote do: def(foo, do: :ok)
      assert Use.extract_all(ast) == []
    end

    test "extracts single use from non-list AST" do
      ast = quote do: use(GenServer)
      directives = Use.extract_all(ast)
      assert length(directives) == 1
      assert hd(directives).module == [:GenServer]
    end
  end

  describe "module_name/1" do
    test "returns single module name" do
      directive = %UseDirective{module: [:GenServer]}
      assert Use.module_name(directive) == "GenServer"
    end

    test "returns dotted module name" do
      directive = %UseDirective{module: [:Plug, :Builder]}
      assert Use.module_name(directive) == "Plug.Builder"
    end

    test "returns Erlang module name" do
      directive = %UseDirective{module: [:gen_server]}
      assert Use.module_name(directive) == "gen_server"
    end
  end

  describe "has_options?/1" do
    test "returns false for nil options" do
      directive = %UseDirective{module: [:GenServer], options: nil}
      refute Use.has_options?(directive)
    end

    test "returns false for empty options list" do
      directive = %UseDirective{module: [:GenServer], options: []}
      refute Use.has_options?(directive)
    end

    test "returns true for keyword options" do
      directive = %UseDirective{module: [:GenServer], options: [restart: :temporary]}
      assert Use.has_options?(directive)
    end

    test "returns true for atom option" do
      directive = %UseDirective{module: [:MyApp, :Web], options: :controller}
      assert Use.has_options?(directive)
    end
  end

  describe "keyword_options?/1" do
    test "returns false for nil options" do
      directive = %UseDirective{module: [:GenServer], options: nil}
      refute Use.keyword_options?(directive)
    end

    test "returns false for empty options list" do
      directive = %UseDirective{module: [:GenServer], options: []}
      refute Use.keyword_options?(directive)
    end

    test "returns true for keyword options" do
      directive = %UseDirective{module: [:GenServer], options: [restart: :temporary]}
      assert Use.keyword_options?(directive)
    end

    test "returns false for atom option" do
      directive = %UseDirective{module: [:MyApp, :Web], options: :controller}
      refute Use.keyword_options?(directive)
    end

    test "returns false for string option" do
      directive = %UseDirective{module: [:MyApp, :Web], options: "controller"}
      refute Use.keyword_options?(directive)
    end
  end

  describe "extract_all_with_scope/2" do
    test "extracts module-level use with :module scope" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            use GenServer
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Use.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :module
      assert hd(directives).module == [:GenServer]
    end

    test "extracts function-level use with :function scope" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo do
              use GenServer
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Use.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
      assert hd(directives).module == [:GenServer]
    end

    test "extracts block-level use with :block scope inside function" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo do
              if true do
                use Agent
              end
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Use.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :block
      assert hd(directives).module == [:Agent]
    end

    test "extracts mixed scopes correctly" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            use GenServer

            def foo do
              use Supervisor
            end

            use Agent
          end
        end

      directives = Use.extract_all_with_scope(body)
      assert length(directives) == 3

      scopes = Enum.map(directives, & &1.scope)
      assert scopes == [:module, :function, :module]

      modules = Enum.map(directives, & &1.module)
      assert modules == [[:GenServer], [:Supervisor], [:Agent]]
    end

    test "handles defmacro with use" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            defmacro my_macro do
              use GenServer
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Use.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
    end

    test "handles case block inside function" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo(x) do
              case x do
                :a -> use GenServer
                :b -> use Supervisor
              end
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Use.extract_all_with_scope(body_list)
      assert length(directives) == 2
      assert Enum.all?(directives, &(&1.scope == :block))
    end

    test "handles function with guard clause" do
      {:defmodule, _, [_, [do: body]]} =
        quote do
          defmodule Test do
            def foo(x) when is_integer(x) do
              use GenServer
            end
          end
        end

      body_list = if is_tuple(body), do: [body], else: body
      directives = Use.extract_all_with_scope(body_list)
      assert length(directives) == 1
      assert hd(directives).scope == :function
    end

    test "preserves options with scope" do
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} =
        quote do
          defmodule Test do
            use GenServer, restart: :temporary

            def foo do
              use MyApp.Web, :controller
            end
          end
        end

      directives = Use.extract_all_with_scope(body)
      assert length(directives) == 2

      [gen_server, web] = directives
      assert gen_server.scope == :module
      assert gen_server.options == [restart: :temporary]
      assert web.scope == :function
      assert web.options == :controller
    end
  end

  describe "UseDirective struct" do
    test "has correct default values" do
      directive = %UseDirective{module: [:GenServer]}
      assert directive.options == nil
      assert directive.location == nil
      assert directive.scope == nil
      assert directive.metadata == %{}
    end

    test "module is enforced" do
      assert_raise ArgumentError, ~r/must also be given/, fn ->
        struct!(UseDirective, %{})
      end
    end
  end

  # ===========================================================================
  # Option Analysis Tests
  # ===========================================================================

  alias ElixirOntologies.Extractors.Directive.Use.UseOption

  describe "analyze_options/1" do
    test "returns empty list for nil options" do
      directive = %UseDirective{module: [:GenServer], options: nil}
      assert Use.analyze_options(directive) == []
    end

    test "returns empty list for empty options" do
      directive = %UseDirective{module: [:GenServer], options: []}
      assert Use.analyze_options(directive) == []
    end

    test "analyzes keyword options" do
      directive = %UseDirective{
        module: [:GenServer],
        options: [restart: :temporary, max_restarts: 3]
      }

      options = Use.analyze_options(directive)
      assert length(options) == 2

      [restart, max] = options
      assert restart.key == :restart
      assert restart.value == :temporary
      assert restart.value_type == :atom
      refute restart.dynamic

      assert max.key == :max_restarts
      assert max.value == 3
      assert max.value_type == :integer
      refute max.dynamic
    end

    test "analyzes non-keyword atom option" do
      directive = %UseDirective{module: [:MyApp, :Web], options: :controller}
      [option] = Use.analyze_options(directive)

      assert option.key == nil
      assert option.value == :controller
      assert option.value_type == :atom
      refute option.dynamic
    end

    test "analyzes non-keyword string option" do
      directive = %UseDirective{module: [:MyApp, :Web], options: "live_view"}
      [option] = Use.analyze_options(directive)

      assert option.key == nil
      assert option.value == "live_view"
      assert option.value_type == :string
      refute option.dynamic
    end

    test "analyzes module reference value" do
      # Simulates: use Phoenix.Controller, namespace: MyApp.Web
      directive = %UseDirective{
        module: [:Phoenix, :Controller],
        options: [namespace: {:__aliases__, [], [:MyApp, :Web]}]
      }

      [option] = Use.analyze_options(directive)
      assert option.key == :namespace
      assert option.value == [:MyApp, :Web]
      assert option.value_type == :module
      refute option.dynamic
    end

    test "analyzes list value" do
      directive = %UseDirective{
        module: [:MyBehaviour],
        options: [callbacks: [:init, :handle_call, :terminate]]
      }

      [option] = Use.analyze_options(directive)
      assert option.key == :callbacks
      assert option.value == [:init, :handle_call, :terminate]
      assert option.value_type == :list
      refute option.dynamic
    end

    test "marks variable value as dynamic" do
      # Simulates: use GenServer, restart: some_var
      directive = %UseDirective{
        module: [:GenServer],
        options: [restart: {:some_var, [], Elixir}]
      }

      [option] = Use.analyze_options(directive)
      assert option.key == :restart
      assert option.value_type == :dynamic
      assert option.dynamic
      assert option.raw_ast == {:some_var, [], Elixir}
    end

    test "marks function call value as dynamic" do
      # Simulates: use GenServer, restart: String.to_atom("temp")
      func_call = {{:., [], [{:__aliases__, [], [:String]}, :to_atom]}, [], ["temp"]}

      directive = %UseDirective{
        module: [:GenServer],
        options: [restart: func_call]
      }

      [option] = Use.analyze_options(directive)
      assert option.key == :restart
      assert option.value_type == :dynamic
      assert option.dynamic
      assert option.raw_ast == func_call
    end
  end

  describe "parse_option/1" do
    test "parses atom value" do
      option = Use.parse_option({:restart, :temporary})
      assert option.key == :restart
      assert option.value == :temporary
      assert option.value_type == :atom
      refute option.dynamic
    end

    test "parses integer value" do
      option = Use.parse_option({:max_restarts, 5})
      assert option.key == :max_restarts
      assert option.value == 5
      assert option.value_type == :integer
      refute option.dynamic
    end

    test "parses string value" do
      option = Use.parse_option({:name, "my_server"})
      assert option.key == :name
      assert option.value == "my_server"
      assert option.value_type == :string
      refute option.dynamic
    end

    test "parses boolean value" do
      option = Use.parse_option({:debug, true})
      assert option.key == :debug
      assert option.value == true
      assert option.value_type == :boolean
      refute option.dynamic
    end

    test "parses float value" do
      option = Use.parse_option({:timeout, 1.5})
      assert option.key == :timeout
      assert option.value == 1.5
      assert option.value_type == :float
      refute option.dynamic
    end

    test "parses nil value" do
      option = Use.parse_option({:default, nil})
      assert option.key == :default
      assert option.value == nil
      assert option.value_type == :nil
      refute option.dynamic
    end
  end

  describe "dynamic_value?/1" do
    test "returns false for atoms" do
      refute Use.dynamic_value?(:atom)
      refute Use.dynamic_value?(:temporary)
    end

    test "returns false for strings" do
      refute Use.dynamic_value?("string")
    end

    test "returns false for integers" do
      refute Use.dynamic_value?(42)
      refute Use.dynamic_value?(0)
      refute Use.dynamic_value?(-1)
    end

    test "returns false for floats" do
      refute Use.dynamic_value?(3.14)
    end

    test "returns false for booleans" do
      refute Use.dynamic_value?(true)
      refute Use.dynamic_value?(false)
    end

    test "returns false for module references" do
      refute Use.dynamic_value?({:__aliases__, [], [:MyApp, :Web]})
    end

    test "returns false for literal lists" do
      refute Use.dynamic_value?([:a, :b, :c])
      refute Use.dynamic_value?([1, 2, 3])
    end

    test "returns false for literal tuples" do
      refute Use.dynamic_value?({:a, :b})
      refute Use.dynamic_value?({1, 2})
    end

    test "returns true for variable references" do
      assert Use.dynamic_value?({:some_var, [], Elixir})
      assert Use.dynamic_value?({:opts, [line: 1], nil})
    end

    test "returns true for function calls" do
      func_call = {{:., [], [{:__aliases__, [], [:String]}, :to_atom]}, [], ["temp"]}
      assert Use.dynamic_value?(func_call)
    end

    test "returns true for list with dynamic element" do
      assert Use.dynamic_value?([:a, {:var, [], Elixir}, :c])
    end
  end

  describe "value_type/1" do
    test "classifies atoms" do
      assert Use.value_type(:atom) == :atom
      assert Use.value_type(:temporary) == :atom
    end

    test "classifies strings" do
      assert Use.value_type("string") == :string
    end

    test "classifies integers" do
      assert Use.value_type(42) == :integer
    end

    test "classifies floats" do
      assert Use.value_type(3.14) == :float
    end

    test "classifies booleans" do
      assert Use.value_type(true) == :boolean
      assert Use.value_type(false) == :boolean
    end

    test "classifies nil" do
      assert Use.value_type(nil) == :nil
    end

    test "classifies lists" do
      assert Use.value_type([:a, :b]) == :list
      assert Use.value_type([1, 2, 3]) == :list
    end

    test "classifies tuples" do
      assert Use.value_type({:a, :b}) == :tuple
    end

    test "classifies module references" do
      assert Use.value_type({:__aliases__, [], [:MyApp, :Web]}) == :module
    end

    test "classifies dynamic values" do
      assert Use.value_type({:some_var, [], Elixir}) == :dynamic
    end
  end

  describe "extract_literal_value/1" do
    test "extracts atoms" do
      assert Use.extract_literal_value(:temporary) == {:ok, :temporary}
    end

    test "extracts strings" do
      assert Use.extract_literal_value("string") == {:ok, "string"}
    end

    test "extracts integers" do
      assert Use.extract_literal_value(42) == {:ok, 42}
    end

    test "extracts floats" do
      assert Use.extract_literal_value(3.14) == {:ok, 3.14}
    end

    test "extracts booleans" do
      assert Use.extract_literal_value(true) == {:ok, true}
      assert Use.extract_literal_value(false) == {:ok, false}
    end

    test "extracts nil" do
      assert Use.extract_literal_value(nil) == {:ok, nil}
    end

    test "extracts module reference as list of atoms" do
      assert Use.extract_literal_value({:__aliases__, [], [:MyApp, :Web]}) == {:ok, [:MyApp, :Web]}
    end

    test "extracts literal lists" do
      assert Use.extract_literal_value([:a, :b, :c]) == {:ok, [:a, :b, :c]}
    end

    test "extracts literal tuples" do
      assert Use.extract_literal_value({:a, :b}) == {:ok, {:a, :b}}
    end

    test "returns dynamic for variable references" do
      var = {:some_var, [], Elixir}
      assert Use.extract_literal_value(var) == {:dynamic, var}
    end

    test "returns dynamic for function calls" do
      func_call = {{:., [], [{:__aliases__, [], [:String]}, :to_atom]}, [], ["temp"]}
      assert Use.extract_literal_value(func_call) == {:dynamic, func_call}
    end
  end

  describe "UseOption struct" do
    test "has correct default values" do
      option = %UseOption{key: :restart, value: :temporary, value_type: :atom}
      assert option.dynamic == false
      assert option.raw_ast == nil
      assert option.source_kind == :literal
    end
  end

  describe "source_kind/1" do
    test "classifies literal atoms" do
      assert Use.source_kind(:atom) == :literal
      assert Use.source_kind(:temporary) == :literal
    end

    test "classifies literal strings" do
      assert Use.source_kind("string") == :literal
    end

    test "classifies literal integers" do
      assert Use.source_kind(42) == :literal
    end

    test "classifies literal floats" do
      assert Use.source_kind(3.14) == :literal
    end

    test "classifies literal booleans" do
      assert Use.source_kind(true) == :literal
      assert Use.source_kind(false) == :literal
    end

    test "classifies module references as literal" do
      assert Use.source_kind({:__aliases__, [], [:MyApp, :Web]}) == :literal
    end

    test "classifies literal lists" do
      assert Use.source_kind([:a, :b, :c]) == :literal
      assert Use.source_kind([1, 2, 3]) == :literal
    end

    test "classifies literal tuples" do
      assert Use.source_kind({:a, :b}) == :literal
    end

    test "classifies variable references" do
      assert Use.source_kind({:some_var, [], Elixir}) == :variable
      assert Use.source_kind({:opts, [], nil}) == :variable
    end

    test "classifies function calls" do
      func_call = {{:., [], [{:__aliases__, [], [:String]}, :to_atom]}, [], ["temp"]}
      assert Use.source_kind(func_call) == :function_call
    end

    test "classifies module attribute references" do
      # @config
      attr = {:@, [], [{:config, [], nil}]}
      assert Use.source_kind(attr) == :module_attribute
    end

    test "classifies mixed lists as other" do
      assert Use.source_kind([:a, {:var, [], Elixir}]) == :other
    end
  end

  describe "analyze_options/1 with source_kind" do
    test "literal options have :literal source_kind" do
      directive = %UseDirective{
        module: [:GenServer],
        options: [restart: :temporary, max_restarts: 3]
      }

      [restart, max] = Use.analyze_options(directive)

      assert restart.source_kind == :literal
      assert max.source_kind == :literal
    end

    test "variable option has :variable source_kind" do
      directive = %UseDirective{
        module: [:GenServer],
        options: [restart: {:some_var, [], Elixir}]
      }

      [option] = Use.analyze_options(directive)
      assert option.source_kind == :variable
    end

    test "function call option has :function_call source_kind" do
      func_call = {{:., [], [{:__aliases__, [], [:String]}, :to_atom]}, [], ["temp"]}

      directive = %UseDirective{
        module: [:GenServer],
        options: [restart: func_call]
      }

      [option] = Use.analyze_options(directive)
      assert option.source_kind == :function_call
    end

    test "module attribute option has :module_attribute source_kind" do
      directive = %UseDirective{
        module: [:GenServer],
        options: [restart: {:@, [], [{:config, [], nil}]}]
      }

      [option] = Use.analyze_options(directive)
      assert option.source_kind == :module_attribute
    end
  end
end
