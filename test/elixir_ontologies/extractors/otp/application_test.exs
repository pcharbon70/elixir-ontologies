defmodule ElixirOntologies.Extractors.OTP.ApplicationTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.OTP.Application, as: AppExtractor

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp parse_module_body(code) do
    {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
    body
  end

  defp parse_module_body_with_columns(code) do
    {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code, columns: true)
    body
  end

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "application?/1" do
    test "returns true for use Application" do
      body = parse_module_body("defmodule MyApp do use Application end")
      assert AppExtractor.application?(body)
    end

    test "returns true for @behaviour Application" do
      body = parse_module_body("defmodule MyApp do @behaviour Application end")
      assert AppExtractor.application?(body)
    end

    test "returns false for use GenServer" do
      body = parse_module_body("defmodule MyApp do use GenServer end")
      refute AppExtractor.application?(body)
    end

    test "returns false for use Supervisor" do
      body = parse_module_body("defmodule MyApp do use Supervisor end")
      refute AppExtractor.application?(body)
    end

    test "returns false for empty module" do
      body = parse_module_body("defmodule MyApp do end")
      refute AppExtractor.application?(body)
    end
  end

  describe "uses_application?/1" do
    test "returns true for use Application" do
      body = parse_module_body("defmodule MyApp do use Application end")
      assert AppExtractor.uses_application?(body)
    end

    test "returns false for @behaviour Application" do
      body = parse_module_body("defmodule MyApp do @behaviour Application end")
      refute AppExtractor.uses_application?(body)
    end
  end

  describe "has_application_behaviour?/1" do
    test "returns true for @behaviour Application" do
      body = parse_module_body("defmodule MyApp do @behaviour Application end")
      assert AppExtractor.has_application_behaviour?(body)
    end

    test "returns false for use Application" do
      body = parse_module_body("defmodule MyApp do use Application end")
      refute AppExtractor.has_application_behaviour?(body)
    end
  end

  describe "use_application?/1 (single node)" do
    test "returns true for use Application node" do
      {:ok, ast} = Code.string_to_quoted("use Application")
      assert AppExtractor.use_application?(ast)
    end

    test "returns false for other use statements" do
      {:ok, ast} = Code.string_to_quoted("use GenServer")
      refute AppExtractor.use_application?(ast)
    end
  end

  describe "behaviour_application?/1 (single node)" do
    test "returns true for @behaviour Application node" do
      {:ok, ast} = Code.string_to_quoted("@behaviour Application")
      assert AppExtractor.behaviour_application?(ast)
    end

    test "returns false for other behaviour declarations" do
      {:ok, ast} = Code.string_to_quoted("@behaviour GenServer")
      refute AppExtractor.behaviour_application?(ast)
    end
  end

  # ===========================================================================
  # Extraction Tests
  # ===========================================================================

  describe "extract/1" do
    test "returns {:ok, result} for Application module" do
      body = parse_module_body("defmodule MyApp do use Application end")
      assert {:ok, %AppExtractor{}} = AppExtractor.extract(body)
    end

    test "returns {:error, message} for non-Application module" do
      body = parse_module_body("defmodule MyApp do use GenServer end")
      assert {:error, "Module does not implement Application"} = AppExtractor.extract(body)
    end

    test "sets detection_method to :use for use Application" do
      body = parse_module_body("defmodule MyApp do use Application end")
      {:ok, result} = AppExtractor.extract(body)
      assert result.detection_method == :use
    end

    test "sets detection_method to :behaviour for @behaviour Application" do
      body = parse_module_body("defmodule MyApp do @behaviour Application end")
      {:ok, result} = AppExtractor.extract(body)
      assert result.detection_method == :behaviour
    end

    test "tracks has_start_callback in metadata" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application
          def start(_type, _args), do: {:ok, self()}
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      assert result.metadata.has_start_callback == true
    end

    test "handles module without start callback" do
      body = parse_module_body("defmodule MyApp do use Application end")
      {:ok, result} = AppExtractor.extract(body)
      assert result.metadata.has_start_callback == false
    end
  end

  describe "extract!/1" do
    test "returns result for valid Application module" do
      body = parse_module_body("defmodule MyApp do use Application end")
      assert %AppExtractor{} = AppExtractor.extract!(body)
    end

    test "raises for non-Application module" do
      body = parse_module_body("defmodule MyApp do use GenServer end")

      assert_raise ArgumentError, ~r/Failed to extract Application/, fn ->
        AppExtractor.extract!(body)
      end
    end
  end

  # ===========================================================================
  # Start Callback Extraction Tests
  # ===========================================================================

  describe "extract_start_callback/1" do
    test "returns start/2 function AST" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application
          def start(_type, _args), do: {:ok, self()}
        end
        """)

      start_fn = AppExtractor.extract_start_callback(body)
      assert match?({:def, _, [{:start, _, [_, _]} | _]}, start_fn)
    end

    test "returns nil when no start/2 defined" do
      body = parse_module_body("defmodule MyApp do use Application end")
      assert AppExtractor.extract_start_callback(body) == nil
    end

    test "ignores start/1 function" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application
          def start(_type), do: {:ok, self()}
        end
        """)

      assert AppExtractor.extract_start_callback(body) == nil
    end

    test "finds start/2 among other functions" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application

          def init(_), do: :ok
          def start(_type, _args), do: {:ok, self()}
          def stop(_state), do: :ok
        end
        """)

      start_fn = AppExtractor.extract_start_callback(body)
      assert match?({:def, _, [{:start, _, [_, _]} | _]}, start_fn)
    end
  end

  describe "extract_start_clauses/1" do
    test "returns all start/2 clauses" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application
          def start(:normal, args), do: do_start(args)
          def start(:takeover, args), do: do_takeover(args)
        end
        """)

      clauses = AppExtractor.extract_start_clauses(body)
      assert length(clauses) == 2
    end

    test "returns empty list when no start/2 defined" do
      body = parse_module_body("defmodule MyApp do use Application end")
      assert AppExtractor.extract_start_clauses(body) == []
    end
  end

  # ===========================================================================
  # Inline Supervisor Pattern Tests
  # ===========================================================================

  describe "extract/1 with inline Supervisor.start_link" do
    test "detects inline supervisor pattern" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application

          def start(_type, _args) do
            children = []
            opts = [strategy: :one_for_one, name: MyApp.Supervisor]
            Supervisor.start_link(children, opts)
          end
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      assert result.uses_inline_supervisor == true
      assert result.supervisor_module == nil
    end

    test "extracts supervisor name" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application

          def start(_type, _args) do
            Supervisor.start_link([], strategy: :one_for_one, name: MyApp.Supervisor)
          end
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      assert match?({:__aliases__, _, [:MyApp, :Supervisor]}, result.supervisor_name)
    end

    test "extracts supervisor strategy" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application

          def start(_type, _args) do
            Supervisor.start_link([], strategy: :one_for_all, name: MyApp.Supervisor)
          end
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      assert result.supervisor_strategy == :one_for_all
    end
  end

  # ===========================================================================
  # Dedicated Supervisor Module Pattern Tests
  # ===========================================================================

  describe "extract/1 with dedicated supervisor module" do
    test "detects dedicated supervisor module pattern" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application

          def start(_type, _args) do
            MyApp.Supervisor.start_link(name: MyApp.Supervisor)
          end
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      assert result.uses_inline_supervisor == false
      assert match?({:__aliases__, _, [:MyApp, :Supervisor]}, result.supervisor_module)
    end

    test "extracts supervisor name from dedicated module call" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application

          def start(_type, _args) do
            MyApp.Supervisor.start_link(name: MyApp.RootSupervisor)
          end
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      assert match?({:__aliases__, _, [:MyApp, :RootSupervisor]}, result.supervisor_name)
    end

    test "handles supervisor module without name option" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application

          def start(_type, _args) do
            MyApp.Supervisor.start_link([])
          end
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      assert result.uses_inline_supervisor == false
      assert match?({:__aliases__, _, [:MyApp, :Supervisor]}, result.supervisor_module)
      assert result.supervisor_name == nil
    end
  end

  # ===========================================================================
  # Edge Case Tests
  # ===========================================================================

  describe "edge cases" do
    test "handles complex start body with assignments" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application

          def start(_type, _args) do
            children = [
              MyWorker,
              {MyOtherWorker, []}
            ]

            opts = [
              strategy: :one_for_one,
              name: MyApp.Supervisor,
              max_restarts: 5
            ]

            Supervisor.start_link(children, opts)
          end
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      assert result.uses_inline_supervisor == true
    end

    test "handles start returning tuple directly" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application

          def start(_type, _args) do
            {:ok, self()}
          end
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      # No supervisor call detected
      assert result.uses_inline_supervisor == false
      assert result.supervisor_module == nil
    end

    test "handles Application with stop callback" do
      body =
        parse_module_body("""
        defmodule MyApp do
          use Application

          def start(_type, _args) do
            Supervisor.start_link([], strategy: :one_for_one)
          end

          def stop(_state) do
            :ok
          end
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      assert result.detection_method == :use
      assert result.metadata.has_start_callback == true
    end

    test "extracts location from start callback" do
      body =
        parse_module_body_with_columns("""
        defmodule MyApp do
          use Application

          def start(_type, _args), do: {:ok, self()}
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      # Location is now a SourceLocation struct from Helpers.extract_location_if
      assert result.location != nil
      assert is_integer(result.location.start_line)
    end
  end

  # ===========================================================================
  # Real-world Pattern Tests
  # ===========================================================================

  describe "real-world patterns" do
    test "handles Credo-style inline supervisor" do
      body =
        parse_module_body("""
        defmodule Credo.Application do
          use Application

          def start(_type, _args) do
            opts = [strategy: :one_for_one, name: Credo.Supervisor]
            Supervisor.start_link(children(), opts)
          end

          def children do
            [Worker1, Worker2]
          end
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      assert result.uses_inline_supervisor == true
      assert result.detection_method == :use
    end

    test "handles Phoenix-style supervisor delegation" do
      body =
        parse_module_body("""
        defmodule MyApp.Application do
          use Application

          def start(_type, _args) do
            MyApp.Supervisor.start_link(name: MyApp.Supervisor)
          end
        end
        """)

      {:ok, result} = AppExtractor.extract(body)
      assert result.uses_inline_supervisor == false
      assert match?({:__aliases__, _, [:MyApp, :Supervisor]}, result.supervisor_module)
    end
  end
end
