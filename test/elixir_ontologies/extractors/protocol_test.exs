defmodule ElixirOntologies.Extractors.ProtocolTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Protocol

  doctest Protocol

  # ===========================================================================
  # Protocol Type Detection Tests
  # ===========================================================================

  describe "protocol?/1" do
    test "returns true for defprotocol node" do
      ast = {:defprotocol, [], [{:__aliases__, [], [:MyProtocol]}, [do: nil]]}
      assert Protocol.protocol?(ast)
    end

    test "returns false for defmodule node" do
      ast = {:defmodule, [], [{:__aliases__, [], [:MyModule]}, [do: nil]]}
      refute Protocol.protocol?(ast)
    end

    test "returns false for defimpl node" do
      ast = {:defimpl, [], [{:__aliases__, [], [:Proto]}, [for: :atom], [do: nil]]}
      refute Protocol.protocol?(ast)
    end

    test "returns false for atoms" do
      refute Protocol.protocol?(:not_a_protocol)
    end
  end

  describe "implementation?/1" do
    test "returns true for defimpl node" do
      ast = {:defimpl, [], [{:__aliases__, [], [:Proto]}, [for: :atom], [do: nil]]}
      assert Protocol.implementation?(ast)
    end

    test "returns false for defprotocol node" do
      ast = {:defprotocol, [], [{:__aliases__, [], [:Proto]}, [do: nil]]}
      refute Protocol.implementation?(ast)
    end

    test "returns false for defmodule node" do
      ast = {:defmodule, [], [{:__aliases__, [], [:Mod]}, [do: nil]]}
      refute Protocol.implementation?(ast)
    end

    test "returns false for atoms" do
      refute Protocol.implementation?(:not_impl)
    end
  end

  # ===========================================================================
  # Protocol Definition Extraction Tests
  # ===========================================================================

  describe "extract/2 protocol definition" do
    test "extracts simple protocol" do
      ast = {:defprotocol, [], [{:__aliases__, [], [:Simple]}, [do: nil]]}

      assert {:ok, result} = Protocol.extract(ast)
      assert result.name == [:Simple]
      assert result.functions == []
      assert result.fallback_to_any == false
    end

    test "extracts protocol with nested name" do
      ast = {:defprotocol, [], [{:__aliases__, [], [:MyApp, :Protocols, :Stringable]}, [do: nil]]}

      assert {:ok, result} = Protocol.extract(ast)
      assert result.name == [:MyApp, :Protocols, :Stringable]
    end

    test "extracts protocol with functions" do
      ast =
        quote do
          defprotocol Stringable do
            def to_string(data)
            def to_iodata(data, opts)
          end
        end

      assert {:ok, result} = Protocol.extract(ast)
      assert length(result.functions) == 2

      [to_string, to_iodata] = result.functions
      assert to_string.name == :to_string
      assert to_string.arity == 1
      assert to_iodata.name == :to_iodata
      assert to_iodata.arity == 2
    end

    test "extracts @fallback_to_any" do
      code = """
      defprotocol Fallbackable do
        @fallback_to_any true
        def foo(data)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      assert {:ok, result} = Protocol.extract(ast)
      assert result.fallback_to_any == true
    end

    test "extracts @moduledoc" do
      code = """
      defprotocol Documented do
        @moduledoc "Protocol docs"
        def foo(data)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      assert {:ok, result} = Protocol.extract(ast)
      assert result.doc == "Protocol docs"
    end

    test "extracts @moduledoc false" do
      code = """
      defprotocol Hidden do
        @moduledoc false
        def foo(data)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      assert {:ok, result} = Protocol.extract(ast)
      assert result.doc == false
    end

    test "extracts function @doc" do
      code = """
      defprotocol WithDocs do
        @doc "Converts to string"
        def to_string(data)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      assert {:ok, result} = Protocol.extract(ast)
      [func] = result.functions
      assert func.doc == "Converts to string"
    end

    test "returns error for non-protocol" do
      assert {:error, message} = Protocol.extract({:defmodule, [], []})
      assert message =~ "Not a protocol definition"
    end
  end

  # ===========================================================================
  # Protocol Implementation Extraction Tests
  # ===========================================================================

  describe "extract_implementation/2" do
    test "extracts basic implementation" do
      code = "defimpl String.Chars, for: Integer do def to_string(i), do: Integer.to_string(i) end"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, impl} = Protocol.extract_implementation(ast)
      assert impl.protocol == [:String, :Chars]
      assert impl.for_type == [:Integer]
      assert impl.is_any == false
    end

    test "extracts for: Any implementation" do
      code = "defimpl Enumerable, for: Any do def count(_), do: {:error, __MODULE__} end"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, impl} = Protocol.extract_implementation(ast)
      assert impl.protocol == [:Enumerable]
      assert impl.for_type == [:Any]
      assert impl.is_any == true
    end

    test "extracts for: atom type" do
      code = "defimpl Proto, for: :atom do end"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, impl} = Protocol.extract_implementation(ast)
      assert impl.for_type == :atom
    end

    test "extracts implemented functions" do
      code = """
      defimpl MyProtocol, for: List do
        def foo(list), do: list
        def bar(list, acc), do: {list, acc}
        defp helper(x), do: x
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      assert {:ok, impl} = Protocol.extract_implementation(ast)

      # Should extract all functions including private
      assert length(impl.functions) == 3

      func_names = Enum.map(impl.functions, & &1.name)
      assert :foo in func_names
      assert :bar in func_names
      assert :helper in func_names
    end

    test "extracts function arities" do
      code = """
      defimpl P, for: Integer do
        def one(x), do: x
        def two(x, y), do: {x, y}
        def three(x, y, z), do: {x, y, z}
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      assert {:ok, impl} = Protocol.extract_implementation(ast)

      arities = impl.functions |> Enum.map(& &1.arity) |> Enum.sort()
      assert arities == [1, 2, 3]
    end

    test "returns error for non-implementation" do
      assert {:error, message} = Protocol.extract_implementation({:defmodule, [], []})
      assert message =~ "Not a protocol implementation"
    end

    test "handles empty implementation body" do
      code = "defimpl Proto, for: List do end"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, impl} = Protocol.extract_implementation(ast)
      assert impl.functions == []
    end
  end

  describe "extract_implementation!/2" do
    test "returns result on success" do
      code = "defimpl P, for: List do end"
      {:ok, ast} = Code.string_to_quoted(code)

      impl = Protocol.extract_implementation!(ast)
      assert impl.protocol == [:P]
    end

    test "raises on error" do
      assert_raise ArgumentError, ~r/Not a protocol implementation/, fn ->
        Protocol.extract_implementation!(:not_impl)
      end
    end
  end

  describe "extract_all_implementations/2" do
    test "extracts all implementations from list" do
      code1 = "defimpl P1, for: Integer do end"
      code2 = "defimpl P2, for: String do end"
      {:ok, ast1} = Code.string_to_quoted(code1)
      {:ok, ast2} = Code.string_to_quoted(code2)

      impls = Protocol.extract_all_implementations([ast1, ast2])
      assert length(impls) == 2
    end

    test "skips non-implementation nodes" do
      code = "defimpl P, for: List do end"
      {:ok, ast} = Code.string_to_quoted(code)

      impls = Protocol.extract_all_implementations([ast, :not_impl, {:defmodule, [], []}])
      assert length(impls) == 1
    end
  end

  # ===========================================================================
  # @derive Extraction Tests
  # ===========================================================================

  describe "extract_derives/1" do
    test "extracts single @derive with list" do
      code = "defmodule M do @derive [Inspect, Enumerable]; defstruct [:a] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      derives = Protocol.extract_derives(body)
      assert length(derives) == 1

      [derive] = derives
      protocol_names = Enum.map(derive.protocols, & &1.protocol)
      assert [:Inspect] in protocol_names
      assert [:Enumerable] in protocol_names
    end

    test "extracts @derive with single protocol" do
      code = "defmodule M do @derive Inspect; defstruct [:a] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      derives = Protocol.extract_derives(body)
      assert length(derives) == 1

      [derive] = derives
      assert length(derive.protocols) == 1
      assert hd(derive.protocols).protocol == [:Inspect]
    end

    test "extracts @derive with options" do
      code = "defmodule M do @derive {Phoenix.Param, key: :id}; defstruct [:id] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      derives = Protocol.extract_derives(body)
      [derive] = derives

      [protocol_info] = derive.protocols
      assert protocol_info.protocol == [:Phoenix, :Param]
      assert protocol_info.options == [key: :id]
    end

    test "extracts multiple @derive directives" do
      code = """
      defmodule M do
        @derive Inspect
        @derive Enumerable
        defstruct [:a]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      derives = Protocol.extract_derives(body)
      assert length(derives) == 2
    end

    test "returns empty list when no @derive" do
      code = "defmodule M do defstruct [:a] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      derives = Protocol.extract_derives(body)
      assert derives == []
    end
  end

  # ===========================================================================
  # Utility Function Tests
  # ===========================================================================

  describe "function_names/1" do
    test "returns list of function names" do
      ast =
        quote do
          defprotocol MyProtocol do
            def foo(data)
            def bar(data)
          end
        end

      {:ok, proto} = Protocol.extract(ast)
      assert Protocol.function_names(proto) == [:foo, :bar]
    end
  end

  describe "get_function/2" do
    test "returns function by name" do
      ast =
        quote do
          defprotocol MyProtocol do
            def foo(data)
            def bar(data, opts)
          end
        end

      {:ok, proto} = Protocol.extract(ast)
      func = Protocol.get_function(proto, :bar)
      assert func.name == :bar
      assert func.arity == 2
    end

    test "returns nil for unknown function" do
      ast = {:defprotocol, [], [{:__aliases__, [], [:P]}, [do: nil]]}
      {:ok, proto} = Protocol.extract(ast)
      assert Protocol.get_function(proto, :unknown) == nil
    end
  end

  describe "fallback_to_any?/1" do
    test "returns true when enabled" do
      code = "defprotocol P do @fallback_to_any true; def foo(x); end"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, proto} = Protocol.extract(ast)
      assert Protocol.fallback_to_any?(proto) == true
    end

    test "returns false when not enabled" do
      code = "defprotocol P do def foo(x); end"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, proto} = Protocol.extract(ast)
      assert Protocol.fallback_to_any?(proto) == false
    end
  end

  describe "implementation_function_names/1" do
    test "returns list of implemented function names" do
      code = "defimpl P, for: Integer do def foo(x), do: x; def bar(x), do: x end"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, impl} = Protocol.extract_implementation(ast)

      assert Protocol.implementation_function_names(impl) == [:foo, :bar]
    end
  end

  # ===========================================================================
  # Real World Protocol Tests
  # ===========================================================================

  describe "real world scenarios" do
    test "Enumerable-like protocol" do
      code = """
      defprotocol Enumerable do
        @fallback_to_any true
        @moduledoc "Protocol for enumerable types"

        @doc "Reduces the enumerable"
        def reduce(enumerable, acc, fun)

        @doc "Returns the count"
        def count(enumerable)

        def member?(enumerable, element)
        def slice(enumerable)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      assert {:ok, proto} = Protocol.extract(ast)

      assert proto.name == [:Enumerable]
      assert proto.fallback_to_any == true
      assert proto.doc == "Protocol for enumerable types"
      assert length(proto.functions) == 4
    end

    test "String.Chars-like implementation" do
      code = """
      defimpl String.Chars, for: Integer do
        def to_string(integer) do
          Integer.to_string(integer)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      assert {:ok, impl} = Protocol.extract_implementation(ast)

      assert impl.protocol == [:String, :Chars]
      assert impl.for_type == [:Integer]
      assert length(impl.functions) == 1
      assert hd(impl.functions).name == :to_string
    end

    test "implementation for multiple types pattern" do
      # Test extracting implementations for different types
      impls_code = [
        "defimpl Size, for: List do def size(list), do: length(list) end",
        "defimpl Size, for: Map do def size(map), do: map_size(map) end",
        "defimpl Size, for: BitString do def size(bits), do: bit_size(bits) end"
      ]

      impls =
        impls_code
        |> Enum.map(fn code ->
          {:ok, ast} = Code.string_to_quoted(code)
          {:ok, impl} = Protocol.extract_implementation(ast)
          impl
        end)

      protocols = Enum.map(impls, & &1.protocol)
      assert Enum.all?(protocols, &(&1 == [:Size]))

      types = Enum.map(impls, & &1.for_type)
      assert [:List] in types
      assert [:Map] in types
      assert [:BitString] in types
    end

    test "struct with @derive" do
      code = """
      defmodule User do
        @derive [Inspect, {Jason.Encoder, only: [:id, :name]}]
        defstruct [:id, :name, :email, :password_hash]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      derives = Protocol.extract_derives(body)

      [derive] = derives
      assert length(derive.protocols) == 2

      inspect_proto = Enum.find(derive.protocols, &(&1.protocol == [:Inspect]))
      assert inspect_proto.options == nil

      jason_proto = Enum.find(derive.protocols, &(&1.protocol == [:Jason, :Encoder]))
      assert jason_proto.options == [only: [:id, :name]]
    end

    test "protocol function with guard clause" do
      code = """
      defprotocol Guarded do
        @doc "Validates and converts data"
        def validate(data) when is_map(data)
      end
      """

      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, proto} = Protocol.extract(ast)

      assert proto.name == [:Guarded]
      assert length(proto.functions) == 1

      [func] = proto.functions
      assert func.name == :validate
      assert func.arity == 1
      assert func.parameters == [:data]
      assert func.doc == "Validates and converts data"
    end
  end
end
