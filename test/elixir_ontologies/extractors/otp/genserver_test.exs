defmodule ElixirOntologies.Extractors.OTP.GenServerTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.OTP.GenServer, as: GenServerExtractor

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp parse_module_body(code) do
    {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
    body
  end

  defp parse_statement(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    ast
  end

  # ===========================================================================
  # genserver?/1 Tests
  # ===========================================================================

  describe "genserver?/1" do
    test "returns true for use GenServer" do
      body = parse_module_body("defmodule C do use GenServer end")
      assert GenServerExtractor.genserver?(body)
    end

    test "returns true for use GenServer with options" do
      body = parse_module_body("defmodule C do use GenServer, restart: :transient end")
      assert GenServerExtractor.genserver?(body)
    end

    test "returns true for @behaviour GenServer" do
      body = parse_module_body("defmodule C do @behaviour GenServer end")
      assert GenServerExtractor.genserver?(body)
    end

    test "returns false for plain module" do
      body = parse_module_body("defmodule C do def foo, do: :ok end")
      refute GenServerExtractor.genserver?(body)
    end

    test "returns false for use Supervisor" do
      body = parse_module_body("defmodule C do use Supervisor end")
      refute GenServerExtractor.genserver?(body)
    end

    test "returns false for @behaviour Supervisor" do
      body = parse_module_body("defmodule C do @behaviour Supervisor end")
      refute GenServerExtractor.genserver?(body)
    end

    test "returns true when GenServer is mixed with other behaviours" do
      body = parse_module_body("defmodule C do @behaviour Plug; use GenServer end")
      assert GenServerExtractor.genserver?(body)
    end
  end

  # ===========================================================================
  # use_genserver?/1 Tests
  # ===========================================================================

  describe "use_genserver?/1" do
    test "returns true for use GenServer" do
      ast = parse_statement("use GenServer")
      assert GenServerExtractor.use_genserver?(ast)
    end

    test "returns true for use GenServer with options" do
      ast = parse_statement("use GenServer, restart: :transient")
      assert GenServerExtractor.use_genserver?(ast)
    end

    test "returns false for use Supervisor" do
      ast = parse_statement("use Supervisor")
      refute GenServerExtractor.use_genserver?(ast)
    end

    test "returns false for @behaviour GenServer" do
      ast = parse_statement("@behaviour GenServer")
      refute GenServerExtractor.use_genserver?(ast)
    end

    test "returns false for arbitrary code" do
      ast = parse_statement("def init(state), do: {:ok, state}")
      refute GenServerExtractor.use_genserver?(ast)
    end
  end

  # ===========================================================================
  # behaviour_genserver?/1 Tests
  # ===========================================================================

  describe "behaviour_genserver?/1" do
    test "returns true for @behaviour GenServer" do
      ast = parse_statement("@behaviour GenServer")
      assert GenServerExtractor.behaviour_genserver?(ast)
    end

    test "returns false for @behaviour Supervisor" do
      ast = parse_statement("@behaviour Supervisor")
      refute GenServerExtractor.behaviour_genserver?(ast)
    end

    test "returns false for use GenServer" do
      ast = parse_statement("use GenServer")
      refute GenServerExtractor.behaviour_genserver?(ast)
    end

    test "returns false for other attributes" do
      ast = parse_statement("@moduledoc false")
      refute GenServerExtractor.behaviour_genserver?(ast)
    end
  end

  # ===========================================================================
  # extract/2 Tests
  # ===========================================================================

  describe "extract/2" do
    test "extracts use GenServer" do
      body = parse_module_body("defmodule C do use GenServer end")
      {:ok, result} = GenServerExtractor.extract(body)

      assert result.detection_method == :use
      assert result.use_options == []
      assert result.metadata.otp_behaviour == :genserver
    end

    test "extracts use GenServer with options" do
      body = parse_module_body("defmodule C do use GenServer, restart: :transient end")
      {:ok, result} = GenServerExtractor.extract(body)

      assert result.detection_method == :use
      assert result.use_options == [restart: :transient]
      assert result.metadata.has_options == true
    end

    test "extracts use GenServer with multiple options" do
      body = parse_module_body("defmodule C do use GenServer, restart: :transient, shutdown: 5000 end")
      {:ok, result} = GenServerExtractor.extract(body)

      assert result.use_options == [restart: :transient, shutdown: 5000]
    end

    test "extracts @behaviour GenServer" do
      body = parse_module_body("defmodule C do @behaviour GenServer end")
      {:ok, result} = GenServerExtractor.extract(body)

      assert result.detection_method == :behaviour
      assert result.use_options == nil
      assert result.metadata.otp_behaviour == :genserver
    end

    test "returns error for non-GenServer module" do
      body = parse_module_body("defmodule C do def foo, do: :ok end")
      assert {:error, "Module does not implement GenServer"} = GenServerExtractor.extract(body)
    end

    test "extracts location when AST has column info" do
      # Build AST with both line and column metadata
      use_node = {:use, [line: 2, column: 5], [{:__aliases__, [line: 2, column: 9], [:GenServer]}]}
      body = {:__block__, [], [use_node]}

      {:ok, result} = GenServerExtractor.extract(body)

      assert result.location != nil
      assert result.location.start_line == 2
      assert result.location.start_column == 5
    end

    test "handles AST without column info gracefully" do
      # Standard Code.string_to_quoted only provides line info
      body = parse_module_body("defmodule C do use GenServer end")
      {:ok, result} = GenServerExtractor.extract(body)

      # Location may be nil when column info is missing
      assert result.detection_method == :use
    end

    test "does not extract location when include_location is false" do
      body = parse_module_body("defmodule C do use GenServer end")
      {:ok, result} = GenServerExtractor.extract(body, include_location: false)

      assert result.location == nil
    end

    test "prefers use over @behaviour when both present" do
      body = parse_module_body("defmodule C do @behaviour GenServer; use GenServer end")
      {:ok, result} = GenServerExtractor.extract(body)

      # use comes after @behaviour in the code, but we check use first
      assert result.detection_method == :use
    end
  end

  # ===========================================================================
  # extract!/2 Tests
  # ===========================================================================

  describe "extract!/2" do
    test "returns result for valid GenServer" do
      body = parse_module_body("defmodule C do use GenServer end")
      result = GenServerExtractor.extract!(body)

      assert result.detection_method == :use
    end

    test "raises for non-GenServer module" do
      body = parse_module_body("defmodule C do def foo, do: :ok end")

      assert_raise ArgumentError, "Module does not implement GenServer", fn ->
        GenServerExtractor.extract!(body)
      end
    end
  end

  # ===========================================================================
  # detection_method/1 Tests
  # ===========================================================================

  describe "detection_method/1" do
    test "returns :use for use GenServer" do
      body = parse_module_body("defmodule C do use GenServer end")
      assert GenServerExtractor.detection_method(body) == :use
    end

    test "returns :behaviour for @behaviour GenServer" do
      body = parse_module_body("defmodule C do @behaviour GenServer end")
      assert GenServerExtractor.detection_method(body) == :behaviour
    end

    test "returns nil for non-GenServer module" do
      body = parse_module_body("defmodule C do def foo, do: :ok end")
      assert GenServerExtractor.detection_method(body) == nil
    end
  end

  # ===========================================================================
  # use_options/1 Tests
  # ===========================================================================

  describe "use_options/1" do
    test "returns options for use GenServer with options" do
      body = parse_module_body("defmodule C do use GenServer, restart: :transient end")
      assert GenServerExtractor.use_options(body) == [restart: :transient]
    end

    test "returns empty list for use GenServer without options" do
      body = parse_module_body("defmodule C do use GenServer end")
      assert GenServerExtractor.use_options(body) == []
    end

    test "returns nil for @behaviour GenServer" do
      body = parse_module_body("defmodule C do @behaviour GenServer end")
      assert GenServerExtractor.use_options(body) == nil
    end

    test "returns nil for non-GenServer module" do
      body = parse_module_body("defmodule C do def foo, do: :ok end")
      assert GenServerExtractor.use_options(body) == nil
    end
  end

  # ===========================================================================
  # otp_behaviour/0 Tests
  # ===========================================================================

  describe "otp_behaviour/0" do
    test "returns :genserver" do
      assert GenServerExtractor.otp_behaviour() == :genserver
    end
  end

  # ===========================================================================
  # Real-World Patterns
  # ===========================================================================

  describe "real-world GenServer patterns" do
    test "extracts typical GenServer with init callback" do
      code = """
      defmodule Counter do
        use GenServer

        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end

        @impl true
        def init(state), do: {:ok, state}
      end
      """

      body = parse_module_body(code)
      {:ok, result} = GenServerExtractor.extract(body)

      assert result.detection_method == :use
      assert result.use_options == []
    end

    test "extracts GenServer with child_spec options" do
      code = """
      defmodule Worker do
        use GenServer, restart: :temporary, shutdown: 10_000

        def init(state), do: {:ok, state}
      end
      """

      body = parse_module_body(code)
      {:ok, result} = GenServerExtractor.extract(body)

      assert result.use_options == [restart: :temporary, shutdown: 10_000]
    end

    test "handles empty module body" do
      body = nil
      result = GenServerExtractor.extract(body)

      assert {:error, "Module does not implement GenServer"} = result
    end

    test "handles single statement body" do
      body = {:use, [line: 1], [{:__aliases__, [line: 1], [:GenServer]}]}
      {:ok, result} = GenServerExtractor.extract(body)

      assert result.detection_method == :use
    end
  end

  # ===========================================================================
  # Callback Extraction Tests
  # ===========================================================================

  describe "extract_callbacks/2" do
    test "extracts init/1 callback" do
      body = parse_module_body("defmodule C do use GenServer; def init(s), do: {:ok, s} end")
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).type == :init
      assert hd(callbacks).name == :init
      assert hd(callbacks).arity == 1
    end

    test "extracts handle_call/3 callback" do
      body = parse_module_body("defmodule C do use GenServer; def handle_call(r,f,s), do: {:reply,:ok,s} end")
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).type == :handle_call
      assert hd(callbacks).arity == 3
    end

    test "extracts handle_cast/2 callback" do
      body = parse_module_body("defmodule C do use GenServer; def handle_cast(m,s), do: {:noreply,s} end")
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).type == :handle_cast
      assert hd(callbacks).arity == 2
    end

    test "extracts handle_info/2 callback" do
      body = parse_module_body("defmodule C do use GenServer; def handle_info(m,s), do: {:noreply,s} end")
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).type == :handle_info
      assert hd(callbacks).arity == 2
    end

    test "extracts handle_continue/2 callback" do
      body = parse_module_body("defmodule C do use GenServer; def handle_continue(c,s), do: {:noreply,s} end")
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).type == :handle_continue
      assert hd(callbacks).arity == 2
    end

    test "extracts terminate/2 callback" do
      body = parse_module_body("defmodule C do use GenServer; def terminate(r,s), do: :ok end")
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).type == :terminate
      assert hd(callbacks).arity == 2
    end

    test "extracts multiple callbacks" do
      code = """
      defmodule Counter do
        use GenServer

        def init(state), do: {:ok, state}
        def handle_call(:get, _from, state), do: {:reply, state, state}
        def handle_cast({:put, val}, _state), do: {:noreply, val}
      end
      """

      body = parse_module_body(code)
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 3
      types = Enum.map(callbacks, & &1.type)
      assert :init in types
      assert :handle_call in types
      assert :handle_cast in types
    end

    test "counts multiple clauses for same callback" do
      code = """
      defmodule Counter do
        use GenServer

        def handle_call(:get, _from, state), do: {:reply, state, state}
        def handle_call(:inc, _from, state), do: {:reply, :ok, state + 1}
        def handle_call(:dec, _from, state), do: {:reply, :ok, state - 1}
      end
      """

      body = parse_module_body(code)
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).clauses == 3
    end

    test "returns empty list for module without callbacks" do
      body = parse_module_body("defmodule C do use GenServer end")
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert callbacks == []
    end

    test "ignores non-callback functions" do
      code = """
      defmodule Counter do
        use GenServer

        def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
        def init(state), do: {:ok, state}
        def get(pid), do: GenServer.call(pid, :get)
      end
      """

      body = parse_module_body(code)
      callbacks = GenServerExtractor.extract_callbacks(body)

      # Only init/1 is a GenServer callback
      assert length(callbacks) == 1
      assert hd(callbacks).type == :init
    end
  end

  # ===========================================================================
  # @impl Detection Tests
  # ===========================================================================

  describe "@impl annotation detection" do
    test "detects @impl true before callback" do
      code = """
      defmodule Counter do
        use GenServer

        @impl true
        def init(state), do: {:ok, state}
      end
      """

      body = parse_module_body(code)
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).has_impl == true
    end

    test "detects @impl GenServer before callback" do
      code = """
      defmodule Counter do
        use GenServer

        @impl GenServer
        def init(state), do: {:ok, state}
      end
      """

      body = parse_module_body(code)
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).has_impl == true
    end

    test "has_impl is false when no @impl annotation" do
      code = """
      defmodule Counter do
        use GenServer

        def init(state), do: {:ok, state}
      end
      """

      body = parse_module_body(code)
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).has_impl == false
    end

    test "@impl only applies to immediately following function" do
      code = """
      defmodule Counter do
        use GenServer

        @impl true
        def init(state), do: {:ok, state}

        def handle_call(:get, _from, state), do: {:reply, state, state}
      end
      """

      body = parse_module_body(code)
      callbacks = GenServerExtractor.extract_callbacks(body)

      init_cb = Enum.find(callbacks, & &1.type == :init)
      call_cb = Enum.find(callbacks, & &1.type == :handle_call)

      assert init_cb.has_impl == true
      assert call_cb.has_impl == false
    end
  end

  # ===========================================================================
  # genserver_callback?/1 Tests
  # ===========================================================================

  describe "genserver_callback?/1" do
    test "returns true for init/1" do
      ast = parse_statement("def init(state), do: {:ok, state}")
      assert GenServerExtractor.genserver_callback?(ast)
    end

    test "returns true for handle_call/3" do
      ast = parse_statement("def handle_call(req, from, state), do: {:reply, :ok, state}")
      assert GenServerExtractor.genserver_callback?(ast)
    end

    test "returns true for handle_cast/2" do
      ast = parse_statement("def handle_cast(msg, state), do: {:noreply, state}")
      assert GenServerExtractor.genserver_callback?(ast)
    end

    test "returns true for handle_info/2" do
      ast = parse_statement("def handle_info(msg, state), do: {:noreply, state}")
      assert GenServerExtractor.genserver_callback?(ast)
    end

    test "returns true for terminate/2" do
      ast = parse_statement("def terminate(reason, state), do: :ok")
      assert GenServerExtractor.genserver_callback?(ast)
    end

    test "returns false for non-callback functions" do
      ast = parse_statement("def my_function(arg), do: arg")
      refute GenServerExtractor.genserver_callback?(ast)
    end

    test "returns false for wrong arity" do
      ast = parse_statement("def init(a, b), do: {:ok, a}")
      refute GenServerExtractor.genserver_callback?(ast)
    end
  end

  # ===========================================================================
  # callback_type/1 Tests
  # ===========================================================================

  describe "callback_type/1" do
    test "returns :init for init/1" do
      ast = parse_statement("def init(state), do: {:ok, state}")
      assert GenServerExtractor.callback_type(ast) == :init
    end

    test "returns :handle_call for handle_call/3" do
      ast = parse_statement("def handle_call(req, from, state), do: {:reply, :ok, state}")
      assert GenServerExtractor.callback_type(ast) == :handle_call
    end

    test "returns :handle_cast for handle_cast/2" do
      ast = parse_statement("def handle_cast(msg, state), do: {:noreply, state}")
      assert GenServerExtractor.callback_type(ast) == :handle_cast
    end

    test "returns nil for non-callback" do
      ast = parse_statement("def my_function(arg), do: arg")
      assert GenServerExtractor.callback_type(ast) == nil
    end
  end

  # ===========================================================================
  # extract_callback/3 Tests
  # ===========================================================================

  describe "extract_callback/3" do
    test "extracts specific callback type" do
      code = """
      defmodule Counter do
        use GenServer

        def init(state), do: {:ok, state}
        def handle_call(:get, _from, state), do: {:reply, state, state}
      end
      """

      body = parse_module_body(code)

      init_cbs = GenServerExtractor.extract_callback(body, :init)
      assert length(init_cbs) == 1
      assert hd(init_cbs).type == :init

      call_cbs = GenServerExtractor.extract_callback(body, :handle_call)
      assert length(call_cbs) == 1
      assert hd(call_cbs).type == :handle_call
    end

    test "returns empty for missing callback type" do
      body = parse_module_body("defmodule C do use GenServer; def init(s), do: {:ok, s} end")

      result = GenServerExtractor.extract_callback(body, :handle_cast)
      assert result == []
    end
  end

  # ===========================================================================
  # callback_specs/0 Tests
  # ===========================================================================

  describe "callback_specs/0" do
    test "includes all standard GenServer callbacks" do
      specs = GenServerExtractor.callback_specs()

      assert {:init, 1, :init} in specs
      assert {:handle_call, 3, :handle_call} in specs
      assert {:handle_cast, 2, :handle_cast} in specs
      assert {:handle_info, 2, :handle_info} in specs
      assert {:handle_continue, 2, :handle_continue} in specs
      assert {:terminate, 2, :terminate} in specs
      assert {:code_change, 3, :code_change} in specs
      assert {:format_status, 1, :format_status} in specs
    end
  end

  # ===========================================================================
  # Callback with Guards Tests
  # ===========================================================================

  describe "callbacks with guards" do
    test "extracts callback with when guard" do
      code = """
      defmodule Counter do
        use GenServer

        def handle_info(msg, state) when is_atom(msg), do: {:noreply, state}
      end
      """

      body = parse_module_body(code)
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).type == :handle_info
    end

    test "counts guarded clauses correctly" do
      code = """
      defmodule Counter do
        use GenServer

        def handle_info(msg, state) when is_atom(msg), do: {:noreply, state}
        def handle_info(msg, state) when is_binary(msg), do: {:noreply, state}
      end
      """

      body = parse_module_body(code)
      callbacks = GenServerExtractor.extract_callbacks(body)

      assert length(callbacks) == 1
      assert hd(callbacks).clauses == 2
    end
  end
end
