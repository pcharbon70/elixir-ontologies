defmodule ElixirOntologies.Extractors.BehaviourTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Behaviour

  doctest Behaviour

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "callback?/1" do
    test "returns true for @callback attribute" do
      code = "@callback foo(term()) :: :ok"
      {:ok, ast} = Code.string_to_quoted(code)
      assert Behaviour.callback?(ast)
    end

    test "returns false for @macrocallback" do
      code = "@macrocallback foo(term()) :: Macro.t()"
      {:ok, ast} = Code.string_to_quoted(code)
      refute Behaviour.callback?(ast)
    end

    test "returns false for other attributes" do
      code = "@doc \"text\""
      {:ok, ast} = Code.string_to_quoted(code)
      refute Behaviour.callback?(ast)
    end

    test "returns false for non-attributes" do
      refute Behaviour.callback?(:atom)
    end
  end

  describe "macrocallback?/1" do
    test "returns true for @macrocallback attribute" do
      code = "@macrocallback foo(term()) :: Macro.t()"
      {:ok, ast} = Code.string_to_quoted(code)
      assert Behaviour.macrocallback?(ast)
    end

    test "returns false for @callback" do
      code = "@callback foo(term()) :: :ok"
      {:ok, ast} = Code.string_to_quoted(code)
      refute Behaviour.macrocallback?(ast)
    end
  end

  describe "optional_callbacks?/1" do
    test "returns true for @optional_callbacks" do
      code = "@optional_callbacks [foo: 1]"
      {:ok, ast} = Code.string_to_quoted(code)
      assert Behaviour.optional_callbacks?(ast)
    end

    test "returns false for @callback" do
      code = "@callback foo(term()) :: :ok"
      {:ok, ast} = Code.string_to_quoted(code)
      refute Behaviour.optional_callbacks?(ast)
    end
  end

  # ===========================================================================
  # Single Callback Extraction Tests
  # ===========================================================================

  describe "extract_callback/1" do
    test "extracts simple callback" do
      code = "@callback foo(term()) :: :ok"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, callback} = Behaviour.extract_callback(ast)
      assert callback.name == :foo
      assert callback.arity == 1
      assert callback.type == :callback
    end

    test "extracts callback with multiple parameters" do
      code = "@callback handle_call(request, from, state) :: {:reply, term(), term()}"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, callback} = Behaviour.extract_callback(ast)
      assert callback.name == :handle_call
      assert callback.arity == 3
    end

    test "extracts macrocallback" do
      code = "@macrocallback my_macro(term()) :: Macro.t()"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, callback} = Behaviour.extract_callback(ast)
      assert callback.name == :my_macro
      assert callback.type == :macrocallback
    end

    test "preserves spec AST" do
      code = "@callback init(args :: term()) :: {:ok, state :: term()}"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, callback} = Behaviour.extract_callback(ast)
      assert callback.spec != nil
      assert callback.return_type != nil
    end

    test "returns error for non-callback" do
      code = "@doc \"text\""
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:error, message} = Behaviour.extract_callback(ast)
      assert message =~ "Not a callback"
    end
  end

  describe "extract_callback!/1" do
    test "returns callback on success" do
      code = "@callback foo(term()) :: :ok"
      {:ok, ast} = Code.string_to_quoted(code)

      callback = Behaviour.extract_callback!(ast)
      assert callback.name == :foo
    end

    test "raises on error" do
      assert_raise ArgumentError, ~r/Not a callback/, fn ->
        Behaviour.extract_callback!(:not_callback)
      end
    end
  end

  # ===========================================================================
  # Module Body Extraction Tests
  # ===========================================================================

  describe "extract_from_body/1" do
    test "extracts single callback" do
      code = "defmodule B do @callback foo(t) :: t end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_from_body(body)
      assert length(result.callbacks) == 1
      assert hd(result.callbacks).name == :foo
    end

    test "extracts multiple callbacks" do
      code = """
      defmodule B do
        @callback foo(t) :: t
        @callback bar(t, t) :: t
        @callback baz(t, t, t) :: t
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_from_body(body)
      assert length(result.callbacks) == 3

      names = Enum.map(result.callbacks, & &1.name)
      assert :foo in names
      assert :bar in names
      assert :baz in names
    end

    test "extracts macrocallbacks separately" do
      code = """
      defmodule B do
        @callback foo(t) :: t
        @macrocallback bar(t) :: Macro.t()
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_from_body(body)
      assert length(result.callbacks) == 1
      assert length(result.macrocallbacks) == 1
      assert hd(result.callbacks).name == :foo
      assert hd(result.macrocallbacks).name == :bar
    end

    test "marks optional callbacks" do
      code = """
      defmodule B do
        @callback required_cb(t) :: t
        @callback optional_cb(t) :: t
        @optional_callbacks [optional_cb: 1]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_from_body(body)

      required = Enum.find(result.callbacks, &(&1.name == :required_cb))
      optional = Enum.find(result.callbacks, &(&1.name == :optional_cb))

      assert required.is_optional == false
      assert optional.is_optional == true
    end

    test "extracts callback @doc" do
      code = """
      defmodule B do
        @doc "Documentation for foo"
        @callback foo(t) :: t
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_from_body(body)
      assert hd(result.callbacks).doc == "Documentation for foo"
    end

    test "doc applies only to next callback" do
      code = """
      defmodule B do
        @doc "Doc for foo"
        @callback foo(t) :: t
        @callback bar(t) :: t
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_from_body(body)

      foo = Enum.find(result.callbacks, &(&1.name == :foo))
      bar = Enum.find(result.callbacks, &(&1.name == :bar))

      assert foo.doc == "Doc for foo"
      assert bar.doc == nil
    end

    test "extracts @moduledoc" do
      code = """
      defmodule B do
        @moduledoc "Behaviour documentation"
        @callback foo(t) :: t
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_from_body(body)
      assert result.doc == "Behaviour documentation"
    end

    test "handles empty body" do
      result = Behaviour.extract_from_body(nil)
      assert result.callbacks == []
      assert result.macrocallbacks == []
    end
  end

  describe "defines_behaviour?/1" do
    test "returns true for body with @callback" do
      code = "defmodule B do @callback foo(t) :: t end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert Behaviour.defines_behaviour?(body)
    end

    test "returns true for body with @macrocallback" do
      code = "defmodule B do @macrocallback foo(t) :: Macro.t() end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert Behaviour.defines_behaviour?(body)
    end

    test "returns false for regular module" do
      code = "defmodule M do def foo, do: :ok end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      refute Behaviour.defines_behaviour?(body)
    end

    test "returns false for nil body" do
      refute Behaviour.defines_behaviour?(nil)
    end
  end

  # ===========================================================================
  # Utility Function Tests
  # ===========================================================================

  describe "callback_names/1" do
    test "returns all callback and macrocallback names" do
      code = """
      defmodule B do
        @callback foo(t) :: t
        @callback bar(t) :: t
        @macrocallback baz(t) :: Macro.t()
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      result = Behaviour.extract_from_body(body)

      names = Behaviour.callback_names(result)
      assert :foo in names
      assert :bar in names
      assert :baz in names
      assert length(names) == 3
    end
  end

  describe "required_callback_names/1" do
    test "returns only required callbacks" do
      code = """
      defmodule B do
        @callback required(t) :: t
        @callback optional(t) :: t
        @optional_callbacks [optional: 1]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      result = Behaviour.extract_from_body(body)

      required = Behaviour.required_callback_names(result)
      assert required == [:required]
    end
  end

  describe "optional_callback_names/1" do
    test "returns only optional callbacks" do
      code = """
      defmodule B do
        @callback required(t) :: t
        @callback optional(t) :: t
        @optional_callbacks [optional: 1]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      result = Behaviour.extract_from_body(body)

      optional = Behaviour.optional_callback_names(result)
      assert optional == [:optional]
    end
  end

  describe "get_callback/2" do
    test "finds callback by name" do
      code = """
      defmodule B do
        @callback foo(t) :: t
        @callback bar(t, t) :: t
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      result = Behaviour.extract_from_body(body)

      cb = Behaviour.get_callback(result, :bar)
      assert cb.name == :bar
      assert cb.arity == 2
    end

    test "returns nil for unknown callback" do
      code = "defmodule B do @callback foo(t) :: t end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      result = Behaviour.extract_from_body(body)

      assert Behaviour.get_callback(result, :unknown) == nil
    end
  end

  describe "optional?/3" do
    test "returns true for optional callback" do
      code = """
      defmodule B do
        @callback opt(t) :: t
        @optional_callbacks [opt: 1]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      result = Behaviour.extract_from_body(body)

      assert Behaviour.optional?(result, :opt, 1)
    end

    test "returns false for required callback" do
      code = """
      defmodule B do
        @callback req(t) :: t
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      result = Behaviour.extract_from_body(body)

      refute Behaviour.optional?(result, :req, 1)
    end

    test "returns false for non-existent callback" do
      code = "defmodule B do @callback foo(t) :: t end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      result = Behaviour.extract_from_body(body)

      refute Behaviour.optional?(result, :unknown, 1)
    end
  end

  # ===========================================================================
  # Real World Behaviour Tests
  # ===========================================================================

  describe "real world behaviours" do
    test "GenServer-like behaviour" do
      code = """
      defmodule GenServer do
        @moduledoc "A behaviour for implementing the server side of client-server patterns."

        @doc "Invoked when the server is started."
        @callback init(args :: term()) :: {:ok, state :: term()} | {:ok, state :: term(), timeout() | :hibernate} | :ignore | {:stop, reason :: term()}

        @doc "Invoked to handle synchronous calls."
        @callback handle_call(request :: term(), from :: {pid(), tag :: term()}, state :: term()) ::
                    {:reply, reply :: term(), new_state :: term()} |
                    {:noreply, new_state :: term()} |
                    {:stop, reason :: term(), reply :: term(), new_state :: term()}

        @doc "Invoked to handle asynchronous casts."
        @callback handle_cast(request :: term(), state :: term()) ::
                    {:noreply, new_state :: term()} |
                    {:stop, reason :: term(), new_state :: term()}

        @callback handle_info(msg :: term(), state :: term()) ::
                    {:noreply, new_state :: term()} |
                    {:stop, reason :: term(), new_state :: term()}

        @callback terminate(reason :: term(), state :: term()) :: term()

        @callback code_change(old_vsn :: term(), state :: term(), extra :: term()) ::
                    {:ok, new_state :: term()} |
                    {:error, reason :: term()}

        @optional_callbacks [handle_info: 2, terminate: 2, code_change: 3]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      result = Behaviour.extract_from_body(body)

      assert result.doc =~ "client-server patterns"
      assert length(result.callbacks) == 6

      # Check required callbacks
      required = Behaviour.required_callback_names(result)
      assert :init in required
      assert :handle_call in required
      assert :handle_cast in required

      # Check optional callbacks
      optional = Behaviour.optional_callback_names(result)
      assert :handle_info in optional
      assert :terminate in optional
      assert :code_change in optional

      # Check specific callback
      init = Behaviour.get_callback(result, :init)
      assert init.arity == 1
      assert init.doc =~ "server is started"
    end

    test "Plug-like behaviour" do
      code = """
      defmodule Plug do
        @callback init(opts :: term()) :: opts :: term()
        @callback call(conn :: term(), opts :: term()) :: conn :: term()
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      result = Behaviour.extract_from_body(body)

      assert length(result.callbacks) == 2
      assert Behaviour.callback_names(result) == [:init, :call]

      init = Behaviour.get_callback(result, :init)
      assert init.arity == 1

      call = Behaviour.get_callback(result, :call)
      assert call.arity == 2
    end

    test "behaviour with macrocallbacks" do
      code = """
      defmodule MyDSL do
        @callback run(opts :: keyword()) :: :ok | {:error, term()}
        @macrocallback define_action(name :: atom(), opts :: keyword()) :: Macro.t()
        @optional_callbacks [define_action: 2]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      result = Behaviour.extract_from_body(body)

      assert length(result.callbacks) == 1
      assert length(result.macrocallbacks) == 1

      run = Behaviour.get_callback(result, :run)
      assert run.type == :callback
      assert run.is_optional == false

      define = Behaviour.get_callback(result, :define_action)
      assert define.type == :macrocallback
      assert define.is_optional == true
    end
  end

  # ===========================================================================
  # Behaviour Implementation Tests (Task 5.2.2)
  # ===========================================================================

  describe "behaviour_declaration?/1" do
    test "returns true for @behaviour attribute" do
      code = "@behaviour GenServer"
      {:ok, ast} = Code.string_to_quoted(code)
      assert Behaviour.behaviour_declaration?(ast)
    end

    test "returns false for @callback" do
      code = "@callback foo(t) :: t"
      {:ok, ast} = Code.string_to_quoted(code)
      refute Behaviour.behaviour_declaration?(ast)
    end

    test "returns false for other attributes" do
      refute Behaviour.behaviour_declaration?({:@, [], [{:doc, [], ["text"]}]})
    end
  end

  describe "defoverridable?/1" do
    test "returns true for defoverridable with list" do
      code = "defoverridable [init: 1, call: 2]"
      {:ok, ast} = Code.string_to_quoted(code)
      assert Behaviour.defoverridable?(ast)
    end

    test "returns true for defoverridable with module" do
      code = "defoverridable MyBehaviour"
      {:ok, ast} = Code.string_to_quoted(code)
      assert Behaviour.defoverridable?(ast)
    end

    test "returns false for def" do
      code = "def foo, do: :ok"
      {:ok, ast} = Code.string_to_quoted(code)
      refute Behaviour.defoverridable?(ast)
    end
  end

  describe "implements_behaviour?/1" do
    test "returns true for module with @behaviour" do
      code = "defmodule M do @behaviour GenServer; def init(a), do: {:ok, a} end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert Behaviour.implements_behaviour?(body)
    end

    test "returns false for regular module" do
      code = "defmodule M do def foo, do: :ok end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      refute Behaviour.implements_behaviour?(body)
    end

    test "returns true for multiple behaviours" do
      code = "defmodule M do @behaviour Plug; @behaviour GenServer end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert Behaviour.implements_behaviour?(body)
    end
  end

  describe "extract_behaviour_declaration/1" do
    test "extracts simple behaviour" do
      code = "@behaviour GenServer"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, impl} = Behaviour.extract_behaviour_declaration(ast)
      assert impl.behaviour == GenServer
    end

    test "extracts nested module behaviour" do
      code = "@behaviour MyApp.CustomBehaviour"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, impl} = Behaviour.extract_behaviour_declaration(ast)
      assert impl.behaviour == MyApp.CustomBehaviour
    end

    test "returns error for non-behaviour" do
      code = "@doc \"text\""
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:error, msg} = Behaviour.extract_behaviour_declaration(ast)
      assert msg =~ "Not a @behaviour"
    end
  end

  describe "extract_defoverridable/1" do
    test "extracts keyword list overridables" do
      code = "defoverridable [init: 1, call: 2]"
      {:ok, ast} = Code.string_to_quoted(code)

      overridables = Behaviour.extract_defoverridable(ast)
      assert length(overridables) == 2

      init = hd(overridables)
      assert init.name == :init
      assert init.arity == 1
      assert init.source == :list
    end

    test "extracts module reference overridable" do
      code = "defoverridable MyBehaviour"
      {:ok, ast} = Code.string_to_quoted(code)

      overridables = Behaviour.extract_defoverridable(ast)
      assert length(overridables) == 1

      ref = hd(overridables)
      assert ref.name == MyBehaviour
      assert ref.source == :module
    end

    test "returns empty for non-overridable" do
      code = "def foo, do: :ok"
      {:ok, ast} = Code.string_to_quoted(code)

      assert Behaviour.extract_defoverridable(ast) == []
    end
  end

  describe "extract_implementations/1" do
    test "extracts single behaviour" do
      code = "defmodule M do @behaviour GenServer; def init(a), do: {:ok, a} end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      assert length(result.behaviours) == 1
      assert hd(result.behaviours).behaviour == GenServer
    end

    test "extracts multiple behaviours" do
      code = """
      defmodule M do
        @behaviour Plug
        @behaviour GenServer

        def init(a), do: {:ok, a}
        def call(c, _o), do: c
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      assert length(result.behaviours) == 2

      behaviours = Behaviour.implemented_behaviours(result)
      assert Plug in behaviours
      assert GenServer in behaviours
    end

    test "extracts functions" do
      code = """
      defmodule M do
        @behaviour GenServer

        def init(args), do: {:ok, args}
        def handle_call(req, from, state), do: {:reply, :ok, state}
        defp helper, do: :ok
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      assert {:init, 1} in result.functions
      assert {:handle_call, 3} in result.functions
      assert {:helper, 0} in result.functions
    end

    test "extracts defoverridable" do
      code = """
      defmodule M do
        @behaviour GenServer

        def init(args), do: {:ok, args}
        defoverridable [init: 1]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      assert length(result.overridables) == 1
      assert hd(result.overridables).name == :init
    end

    test "handles empty module" do
      code = "defmodule M do end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      assert result.behaviours == []
      assert result.overridables == []
      assert result.functions == []
    end
  end

  describe "implemented_behaviours/1" do
    test "returns list of behaviour modules" do
      code = "defmodule M do @behaviour GenServer; @behaviour Plug end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      behaviours = Behaviour.implemented_behaviours(result)

      assert behaviours == [GenServer, Plug]
    end
  end

  describe "overridable_functions/1" do
    test "returns list of overridable name/arity tuples" do
      code = "defmodule M do defoverridable [init: 1, call: 2] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      overridables = Behaviour.overridable_functions(result)

      assert {:init, 1} in overridables
      assert {:call, 2} in overridables
    end

    test "excludes module references" do
      code = "defmodule M do defoverridable MyBehaviour end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      overridables = Behaviour.overridable_functions(result)

      assert overridables == []
    end
  end

  describe "overridable?/3" do
    test "returns true for overridable function" do
      code = "defmodule M do defoverridable [init: 1] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      assert Behaviour.overridable?(result, :init, 1)
    end

    test "returns false for non-overridable function" do
      code = "defmodule M do defoverridable [init: 1] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      refute Behaviour.overridable?(result, :call, 2)
    end
  end

  describe "implements?/2" do
    test "returns true when behaviour is implemented" do
      code = "defmodule M do @behaviour GenServer end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      assert Behaviour.implements?(result, GenServer)
    end

    test "returns false when behaviour is not implemented" do
      code = "defmodule M do @behaviour GenServer end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      refute Behaviour.implements?(result, Plug)
    end
  end

  describe "matching_callbacks/2" do
    test "finds functions matching callback signatures" do
      code = """
      defmodule M do
        @behaviour GenServer

        def init(a), do: {:ok, a}
        def handle_call(r, f, s), do: {:reply, :ok, s}
        def custom_function, do: :ok
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      callbacks = [{:init, 1}, {:handle_call, 3}, {:handle_cast, 2}]

      matching = Behaviour.matching_callbacks(result, callbacks)
      assert {:init, 1} in matching
      assert {:handle_call, 3} in matching
      refute {:handle_cast, 2} in matching
    end
  end

  describe "missing_callbacks/2" do
    test "finds callbacks not implemented" do
      code = """
      defmodule M do
        def init(a), do: {:ok, a}
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)
      callbacks = [{:init, 1}, {:handle_call, 3}]

      missing = Behaviour.missing_callbacks(result, callbacks)
      assert missing == [{:handle_call, 3}]
    end
  end

  # ===========================================================================
  # Real World Implementation Tests
  # ===========================================================================

  describe "real world implementations" do
    test "GenServer implementation" do
      code = """
      defmodule MyServer do
        @behaviour GenServer

        def init(args), do: {:ok, args}
        def handle_call(:get, _from, state), do: {:reply, state, state}
        def handle_cast({:set, val}, _state), do: {:noreply, val}
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)

      assert Behaviour.implements?(result, GenServer)
      assert {:init, 1} in result.functions
      assert {:handle_call, 3} in result.functions
      assert {:handle_cast, 2} in result.functions
    end

    test "Plug implementation" do
      code = """
      defmodule MyPlug do
        @behaviour Plug

        def init(opts), do: opts
        def call(conn, opts), do: conn
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)

      assert Behaviour.implements?(result, Plug)
      assert {:init, 1} in result.functions
      assert {:call, 2} in result.functions
    end

    test "module with use and defoverridable" do
      code = """
      defmodule MyModule do
        @behaviour MyBehaviour

        def callback_impl(arg), do: arg
        def default_impl, do: :default
        defoverridable [default_impl: 0]

        def default_impl, do: :overridden
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)

      assert Behaviour.implements?(result, MyBehaviour)
      assert Behaviour.overridable?(result, :default_impl, 0)
      assert {:callback_impl, 1} in result.functions
      assert {:default_impl, 0} in result.functions
    end

    test "module implementing multiple behaviours" do
      code = """
      defmodule ComplexModule do
        @behaviour GenServer
        @behaviour Supervisor
        @behaviour Application

        def init(args), do: {:ok, args}
        def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
        def start(_type, _args), do: {:ok, self()}
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Behaviour.extract_implementations(body)

      behaviours = Behaviour.implemented_behaviours(result)
      assert GenServer in behaviours
      assert Supervisor in behaviours
      assert Application in behaviours
      assert length(behaviours) == 3
    end
  end
end
