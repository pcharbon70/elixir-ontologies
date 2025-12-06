defmodule ElixirOntologies.Extractors.Phase5IntegrationTest do
  @moduledoc """
  Integration tests for Phase 5 extractors (Protocol, Behaviour, Struct, Exception).

  These tests validate that extractors work correctly together in realistic
  multi-module scenarios that represent real-world Elixir code patterns.
  """

  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Protocol
  alias ElixirOntologies.Extractors.Behaviour
  alias ElixirOntologies.Extractors.Struct

  # ===========================================================================
  # Protocol with Multiple Implementations
  # ===========================================================================

  describe "protocol with multiple implementations" do
    @protocol_code """
    defprotocol Stringable do
      @moduledoc "Protocol for converting to string representation"
      @fallback_to_any true

      @doc "Convert the data to a string"
      def to_string(data)

      @doc "Convert to string with options"
      def to_string(data, opts)
    end
    """

    @impl_integer """
    defimpl Stringable, for: Integer do
      def to_string(i), do: Integer.to_string(i)
      def to_string(i, _opts), do: Integer.to_string(i)
    end
    """

    @impl_list """
    defimpl Stringable, for: List do
      def to_string(list), do: Enum.join(list, ", ")
      def to_string(list, opts) do
        sep = Keyword.get(opts, :separator, ", ")
        Enum.join(list, sep)
      end
    end
    """

    @impl_any """
    defimpl Stringable, for: Any do
      def to_string(data), do: inspect(data)
      def to_string(data, _opts), do: inspect(data)
    end
    """

    test "extracts protocol definition with functions and attributes" do
      {:ok, ast} = Code.string_to_quoted(@protocol_code)
      {:ok, proto} = Protocol.extract(ast)

      assert proto.name == [:Stringable]
      assert proto.fallback_to_any == true
      assert proto.doc == "Protocol for converting to string representation"
      assert length(proto.functions) == 2

      func_names = Protocol.function_names(proto)
      assert :to_string in func_names
    end

    test "extracts protocol function with documentation" do
      {:ok, ast} = Code.string_to_quoted(@protocol_code)
      {:ok, proto} = Protocol.extract(ast)

      to_string_1 = Enum.find(proto.functions, fn f -> f.name == :to_string and f.arity == 1 end)
      assert to_string_1.doc == "Convert the data to a string"
    end

    test "extracts multiple implementations for same protocol" do
      {:ok, int_ast} = Code.string_to_quoted(@impl_integer)
      {:ok, list_ast} = Code.string_to_quoted(@impl_list)
      {:ok, any_ast} = Code.string_to_quoted(@impl_any)

      impls = Protocol.extract_all_implementations([int_ast, list_ast, any_ast])

      assert length(impls) == 3

      # All implement Stringable
      protocols = Enum.map(impls, & &1.protocol)
      assert Enum.all?(protocols, &(&1 == [:Stringable]))

      # Different target types
      types = Enum.map(impls, & &1.for_type)
      assert [:Integer] in types
      assert [:List] in types
      assert [:Any] in types
    end

    test "detects for: Any implementation" do
      {:ok, any_ast} = Code.string_to_quoted(@impl_any)
      {:ok, impl} = Protocol.extract_implementation(any_ast)

      assert impl.is_any == true
      assert impl.for_type == [:Any]
    end

    test "extracts implemented functions from each implementation" do
      {:ok, list_ast} = Code.string_to_quoted(@impl_list)
      {:ok, impl} = Protocol.extract_implementation(list_ast)

      assert length(impl.functions) == 2

      func_names = Protocol.implementation_function_names(impl)
      assert :to_string in func_names
    end

    test "verifies protocol and implementation function arities match" do
      {:ok, proto_ast} = Code.string_to_quoted(@protocol_code)
      {:ok, proto} = Protocol.extract(proto_ast)

      {:ok, int_ast} = Code.string_to_quoted(@impl_integer)
      {:ok, impl} = Protocol.extract_implementation(int_ast)

      proto_arities = proto.functions |> Enum.map(& &1.arity) |> Enum.sort()
      impl_arities = impl.functions |> Enum.map(& &1.arity) |> Enum.sort()

      assert proto_arities == impl_arities
    end
  end

  # ===========================================================================
  # Behaviour with Implementing Module
  # ===========================================================================

  describe "behaviour with implementing module" do
    @behaviour_code """
    defmodule Worker do
      @moduledoc "Worker behaviour for background jobs"

      @doc "Initialize the worker state"
      @callback init(args :: term()) :: {:ok, state :: term()} | {:error, reason :: term()}

      @doc "Handle a job"
      @callback handle_job(job :: term(), state :: term()) :: {:ok, state :: term()}

      @doc "Optional cleanup callback"
      @callback cleanup(state :: term()) :: :ok

      @optional_callbacks [cleanup: 1]
    end
    """

    @implementation_code """
    defmodule MyWorker do
      @behaviour Worker

      @impl true
      def init(args) do
        {:ok, %{args: args, count: 0}}
      end

      @impl true
      def handle_job(job, state) do
        {:ok, %{state | count: state.count + 1}}
      end

      def helper(x), do: x * 2
    end
    """

    @implementation_with_optional """
    defmodule FullWorker do
      @behaviour Worker

      def init(args), do: {:ok, args}
      def handle_job(_job, state), do: {:ok, state}
      def cleanup(_state), do: :ok
    end
    """

    test "extracts behaviour definition with callbacks" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@behaviour_code)
      result = Behaviour.extract_from_body(body)

      assert result.doc == "Worker behaviour for background jobs"
      assert length(result.callbacks) == 3
      assert result.optional_callbacks == [cleanup: 1]
    end

    test "extracts callback with documentation" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@behaviour_code)
      result = Behaviour.extract_from_body(body)

      init_cb = Behaviour.get_callback(result, :init)
      assert init_cb.doc == "Initialize the worker state"
      assert init_cb.arity == 1
    end

    test "identifies required vs optional callbacks" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@behaviour_code)
      result = Behaviour.extract_from_body(body)

      required = Behaviour.required_callback_names(result)
      optional = Behaviour.optional_callback_names(result)

      assert :init in required
      assert :handle_job in required
      assert :cleanup in optional
      refute :cleanup in required
    end

    test "extracts behaviour implementation" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@implementation_code)
      result = Behaviour.extract_implementations(body)

      assert length(result.behaviours) == 1
      assert hd(result.behaviours).behaviour == Worker
    end

    test "matches implemented functions to callbacks" do
      {:ok, {:defmodule, _, [_, [do: beh_body]]}} = Code.string_to_quoted(@behaviour_code)
      behaviour = Behaviour.extract_from_body(beh_body)

      {:ok, {:defmodule, _, [_, [do: impl_body]]}} = Code.string_to_quoted(@implementation_code)
      impl_result = Behaviour.extract_implementations(impl_body)

      # Get required callbacks as {name, arity}
      required_callbacks =
        behaviour.callbacks
        |> Enum.reject(& &1.is_optional)
        |> Enum.map(&{&1.name, &1.arity})

      # Check which are implemented
      matching = Behaviour.matching_callbacks(impl_result, required_callbacks)
      missing = Behaviour.missing_callbacks(impl_result, required_callbacks)

      assert {:init, 1} in matching
      assert {:handle_job, 2} in matching
      assert missing == []
    end

    test "detects missing optional callbacks" do
      {:ok, {:defmodule, _, [_, [do: beh_body]]}} = Code.string_to_quoted(@behaviour_code)
      behaviour = Behaviour.extract_from_body(beh_body)

      {:ok, {:defmodule, _, [_, [do: impl_body]]}} = Code.string_to_quoted(@implementation_code)
      impl_result = Behaviour.extract_implementations(impl_body)

      optional_callbacks =
        behaviour.callbacks
        |> Enum.filter(& &1.is_optional)
        |> Enum.map(&{&1.name, &1.arity})

      missing = Behaviour.missing_callbacks(impl_result, optional_callbacks)

      # cleanup/1 is optional and not implemented in MyWorker
      assert {:cleanup, 1} in missing
    end

    test "verifies all callbacks implemented when optional is provided" do
      {:ok, {:defmodule, _, [_, [do: beh_body]]}} = Code.string_to_quoted(@behaviour_code)
      behaviour = Behaviour.extract_from_body(beh_body)

      {:ok, {:defmodule, _, [_, [do: impl_body]]}} = Code.string_to_quoted(@implementation_with_optional)
      impl_result = Behaviour.extract_implementations(impl_body)

      all_callbacks = Enum.map(behaviour.callbacks, &{&1.name, &1.arity})
      missing = Behaviour.missing_callbacks(impl_result, all_callbacks)

      assert missing == []
    end
  end

  # ===========================================================================
  # Struct with Enforced Keys and Derived Protocols
  # ===========================================================================

  describe "struct with enforced keys and derived protocols" do
    @struct_code """
    defmodule User do
      @moduledoc "User account struct"

      @derive [Inspect, {Jason.Encoder, only: [:id, :email, :name]}]
      @enforce_keys [:email]

      defstruct [
        :id,
        :email,
        name: "",
        role: :user,
        active: true,
        metadata: %{}
      ]
    end
    """

    test "extracts struct with all features" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@struct_code)
      {:ok, result} = Struct.extract_from_body(body)

      # Fields
      assert length(result.fields) == 6
      field_names = Struct.field_names(result)
      assert :id in field_names
      assert :email in field_names
      assert :name in field_names
      assert :role in field_names
      assert :active in field_names
      assert :metadata in field_names
    end

    test "extracts enforced keys" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@struct_code)
      {:ok, result} = Struct.extract_from_body(body)

      assert result.enforce_keys == [:email]
      assert Struct.enforced?(result, :email)
      refute Struct.enforced?(result, :name)
    end

    test "extracts derived protocols" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@struct_code)
      {:ok, result} = Struct.extract_from_body(body)

      assert Struct.has_derives?(result)
      protocols = Struct.derived_protocols(result)

      assert [:Inspect] in protocols
      assert [:Jason, :Encoder] in protocols
    end

    test "extracts fields with and without defaults" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@struct_code)
      {:ok, result} = Struct.extract_from_body(body)

      # Fields without defaults
      refute Struct.has_default?(result, :id)
      refute Struct.has_default?(result, :email)

      # Fields with defaults
      assert Struct.has_default?(result, :name)
      assert Struct.has_default?(result, :role)
      assert Struct.has_default?(result, :active)
      assert Struct.has_default?(result, :metadata)

      # Check specific default values
      assert Struct.default_value(result, :name) == ""
      assert Struct.default_value(result, :role) == :user
      assert Struct.default_value(result, :active) == true
      # Maps are stored as AST, not evaluated values
      assert match?({:%{}, _, []}, Struct.default_value(result, :metadata))
    end

    test "identifies required fields (enforced without defaults)" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@struct_code)
      {:ok, result} = Struct.extract_from_body(body)

      required = Struct.required_fields(result)
      required_names = Enum.map(required, & &1.name)

      # :email is enforced and has no default
      assert :email in required_names

      # :id has no default but is not enforced
      refute :id in required_names

      # :name has a default so not required
      refute :name in required_names
    end

    test "extracts derive options" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@struct_code)
      {:ok, result} = Struct.extract_from_body(body)

      [derive_info] = result.derives

      jason_derive = Enum.find(derive_info.protocols, fn p ->
        p.protocol == [:Jason, :Encoder]
      end)

      assert jason_derive.options == [only: [:id, :email, :name]]
    end
  end

  # ===========================================================================
  # Exception with Custom Message
  # ===========================================================================

  describe "exception with custom message" do
    @exception_code """
    defmodule ValidationError do
      @moduledoc "Validation error with detailed information"

      @enforce_keys [:errors]

      defexception [
        :errors,
        :context,
        message: "validation failed"
      ]

      @impl true
      def message(%{errors: errors, context: context}) do
        error_list = errors |> Enum.map(&format_error/1) |> Enum.join("; ")
        "Validation failed for \#{context}: \#{error_list}"
      end

      def message(%{errors: errors}) do
        error_list = errors |> Enum.map(&format_error/1) |> Enum.join("; ")
        "Validation failed: \#{error_list}"
      end

      defp format_error({field, message}), do: "\#{field}: \#{message}"
    end
    """

    @simple_exception """
    defmodule NotFoundError do
      defexception message: "resource not found"
    end
    """

    test "extracts exception with all features" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@exception_code)
      {:ok, result} = Struct.extract_exception_from_body(body)

      # Fields
      assert length(result.fields) == 3
      field_names = Enum.map(result.fields, & &1.name)
      assert :errors in field_names
      assert :context in field_names
      assert :message in field_names
    end

    test "extracts enforce_keys for exception" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@exception_code)
      {:ok, result} = Struct.extract_exception_from_body(body)

      assert result.enforce_keys == [:errors]
    end

    test "extracts default message" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@exception_code)
      {:ok, result} = Struct.extract_exception_from_body(body)

      assert result.default_message == "validation failed"
    end

    test "detects custom message/1 implementation" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@exception_code)
      {:ok, result} = Struct.extract_exception_from_body(body)

      assert result.has_custom_message == true
    end

    test "simple exception without custom message" do
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(@simple_exception)
      {:ok, result} = Struct.extract_exception_from_body(body)

      assert result.default_message == "resource not found"
      assert result.has_custom_message == false
      assert length(result.fields) == 1
    end

    test "exception is identified correctly vs struct" do
      {:ok, {:defmodule, _, [_, [do: exc_body]]}} = Code.string_to_quoted(@exception_code)
      {:ok, {:defmodule, _, [_, [do: struct_body]]}} = Code.string_to_quoted("""
        defmodule MyStruct do
          defstruct [:field]
        end
      """)

      assert Struct.defines_exception?(exc_body)
      refute Struct.defines_struct?(exc_body)

      assert Struct.defines_struct?(struct_body)
      refute Struct.defines_exception?(struct_body)
    end
  end

  # ===========================================================================
  # Cross-Extractor Scenarios
  # ===========================================================================

  describe "cross-extractor scenarios" do
    @struct_with_protocol_impl """
    defmodule Person do
      @derive [Inspect]
      defstruct [:name, :age]
    end
    """

    @protocol_impl_for_struct """
    defimpl String.Chars, for: Person do
      def to_string(%Person{name: name, age: age}) do
        "\#{name} (\#{age})"
      end
    end
    """

    test "struct with @derive and separate protocol implementation" do
      # Extract struct with derive
      {:ok, {:defmodule, _, [_, [do: struct_body]]}} = Code.string_to_quoted(@struct_with_protocol_impl)
      {:ok, struct_result} = Struct.extract_from_body(struct_body)

      assert Struct.has_derives?(struct_result)
      assert [:Inspect] in Struct.derived_protocols(struct_result)

      # Extract separate implementation
      {:ok, impl_ast} = Code.string_to_quoted(@protocol_impl_for_struct)
      {:ok, impl} = Protocol.extract_implementation(impl_ast)

      assert impl.protocol == [:String, :Chars]
      assert impl.for_type == [:Person]
    end

    @behaviour_and_struct """
    defmodule Serializable do
      @callback serialize(struct :: struct()) :: binary()
      @callback deserialize(data :: binary()) :: {:ok, struct()} | {:error, term()}
    end
    """

    @implementing_struct """
    defmodule Document do
      @behaviour Serializable
      @derive Jason.Encoder

      defstruct [:id, :title, :content]

      @impl true
      def serialize(%__MODULE__{} = doc) do
        Jason.encode!(doc)
      end

      @impl true
      def deserialize(data) do
        case Jason.decode(data) do
          {:ok, map} -> {:ok, struct(__MODULE__, map)}
          error -> error
        end
      end
    end
    """

    test "struct implementing behaviour with @derive" do
      # Extract behaviour
      {:ok, {:defmodule, _, [_, [do: beh_body]]}} = Code.string_to_quoted(@behaviour_and_struct)
      behaviour = Behaviour.extract_from_body(beh_body)

      assert length(behaviour.callbacks) == 2

      # Extract implementing struct
      {:ok, {:defmodule, _, [_, [do: impl_body]]}} = Code.string_to_quoted(@implementing_struct)

      # Check behaviour implementation
      impl_result = Behaviour.extract_implementations(impl_body)
      assert Behaviour.implements?(impl_result, Serializable)

      # Check callback matching
      callbacks = Enum.map(behaviour.callbacks, &{&1.name, &1.arity})
      matching = Behaviour.matching_callbacks(impl_result, callbacks)
      assert {:serialize, 1} in matching
      assert {:deserialize, 1} in matching

      # Check struct features
      {:ok, struct_result} = Struct.extract_from_body(impl_body)
      assert Struct.has_derives?(struct_result)
      assert length(struct_result.fields) == 3
    end

    test "exception implementing behaviour" do
      exception_code = """
      defmodule Formattable do
        @callback format() :: String.t()
      end

      defmodule MyError do
        @behaviour Formattable
        defexception [:type, :reason, message: "An error occurred"]

        @impl Formattable
        def format do
          "Error"
        end

        @impl true
        def message(%{type: type, reason: reason}) do
          "[\#{type}] \#{reason}"
        end
      end
      """

      {:ok, {:__block__, _, [behaviour_module, exception_module]}} = Code.string_to_quoted(exception_code)

      # Extract behaviour
      {:ok, {:defmodule, _, [_, [do: behaviour_body]]}} = {:ok, behaviour_module}
      behaviour = Behaviour.extract_from_body(behaviour_body)
      assert length(behaviour.callbacks) == 1
      assert hd(behaviour.callbacks).name == :format

      # Extract exception module body
      {:ok, {:defmodule, _, [_, [do: exception_body]]}} = {:ok, exception_module}

      # Verify exception extraction
      {:ok, exception} = Struct.extract_exception_from_body(exception_body)
      assert exception.has_custom_message == true
      assert exception.default_message == "An error occurred"
      assert length(exception.fields) == 3

      # Verify behaviour implementation
      impl_result = Behaviour.extract_implementations(exception_body)
      assert Behaviour.implements?(impl_result, Formattable)
      assert {:format, 0} in impl_result.functions
      assert {:message, 1} in impl_result.functions
    end
  end
end
