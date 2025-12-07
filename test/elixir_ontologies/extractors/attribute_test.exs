defmodule ElixirOntologies.Extractors.AttributeTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Attribute

  doctest Attribute

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "attribute?/1" do
    test "returns true for simple attribute" do
      ast = {:@, [], [{:custom, [], [42]}]}
      assert Attribute.attribute?(ast)
    end

    test "returns true for doc attribute" do
      ast = {:@, [], [{:doc, [], ["documentation"]}]}
      assert Attribute.attribute?(ast)
    end

    test "returns true for behaviour attribute" do
      ast = {:@, [], [{:behaviour, [], [{:__aliases__, [], [:GenServer]}]}]}
      assert Attribute.attribute?(ast)
    end

    test "returns false for function definition" do
      ast = {:def, [], [{:foo, [], nil}]}
      refute Attribute.attribute?(ast)
    end

    test "returns false for non-AST values" do
      refute Attribute.attribute?(:not_an_attribute)
      refute Attribute.attribute?(123)
      refute Attribute.attribute?("string")
    end
  end

  # ===========================================================================
  # Basic Extraction Tests
  # ===========================================================================

  describe "extract/2 generic attributes" do
    test "extracts simple attribute with integer value" do
      ast = {:@, [], [{:count, [], [42]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :attribute
      assert result.name == :count
      assert result.value == 42
    end

    test "extracts attribute with string value" do
      ast = {:@, [], [{:version, [], ["1.0.0"]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.name == :version
      assert result.value == "1.0.0"
    end

    test "extracts attribute with list value" do
      ast = {:@, [], [{:items, [], [[1, 2, 3]]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.name == :items
      assert result.value == [1, 2, 3]
    end

    test "extracts attribute with atom value" do
      ast = {:@, [], [{:mode, [], [:production]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.name == :mode
      assert result.value == :production
    end

    test "returns error for non-attribute" do
      ast = {:def, [], [{:foo, [], nil}]}
      assert {:error, message} = Attribute.extract(ast)
      assert message =~ "Not an attribute"
    end
  end

  # ===========================================================================
  # Documentation Attribute Tests
  # ===========================================================================

  describe "extract/2 doc attributes" do
    test "extracts @doc with string" do
      ast = {:@, [], [{:doc, [], ["Function documentation"]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :doc_attribute
      assert result.name == :doc
      assert result.value == "Function documentation"
      refute result.metadata.hidden
    end

    test "extracts @doc false as hidden" do
      ast = {:@, [], [{:doc, [], [false]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :doc_attribute
      assert result.value == false
      assert result.metadata.hidden == true
    end

    test "extracts @moduledoc with string" do
      ast = {:@, [], [{:moduledoc, [], ["Module documentation"]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :moduledoc_attribute
      assert result.name == :moduledoc
      assert result.value == "Module documentation"
    end

    test "extracts @moduledoc false as hidden" do
      ast = {:@, [], [{:moduledoc, [], [false]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :moduledoc_attribute
      assert result.metadata.hidden == true
    end

    test "extracts @typedoc with string" do
      ast = {:@, [], [{:typedoc, [], ["Type documentation"]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :typedoc_attribute
      assert result.name == :typedoc
    end

    test "doc_attribute? returns true for doc attributes" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}
      {:ok, result} = Attribute.extract(ast)
      assert Attribute.doc_attribute?(result)
    end

    test "doc_attribute? returns false for other attributes" do
      ast = {:@, [], [{:custom, [], [1]}]}
      {:ok, result} = Attribute.extract(ast)
      refute Attribute.doc_attribute?(result)
    end

    test "hidden? returns true for @doc false" do
      ast = {:@, [], [{:doc, [], [false]}]}
      {:ok, result} = Attribute.extract(ast)
      assert Attribute.hidden?(result)
    end

    test "hidden? returns false for @doc with content" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}
      {:ok, result} = Attribute.extract(ast)
      refute Attribute.hidden?(result)
    end
  end

  # ===========================================================================
  # Deprecated Attribute Tests
  # ===========================================================================

  describe "extract/2 @deprecated" do
    test "extracts @deprecated with message" do
      ast = {:@, [], [{:deprecated, [], ["Use new_func/1 instead"]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :deprecated_attribute
      assert result.name == :deprecated
      assert result.value == "Use new_func/1 instead"
      assert result.metadata.message == "Use new_func/1 instead"
    end

    test "extracts @deprecated without string message" do
      ast = {:@, [], [{:deprecated, [], [true]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :deprecated_attribute
      assert result.metadata.message == nil
    end
  end

  # ===========================================================================
  # Since Attribute Tests
  # ===========================================================================

  describe "extract/2 @since" do
    test "extracts @since with version" do
      ast = {:@, [], [{:since, [], ["1.2.0"]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :since_attribute
      assert result.name == :since
      assert result.value == "1.2.0"
      assert result.metadata.version == "1.2.0"
    end
  end

  # ===========================================================================
  # External Resource Attribute Tests
  # ===========================================================================

  describe "extract/2 @external_resource" do
    test "extracts @external_resource with path" do
      ast = {:@, [], [{:external_resource, [], ["priv/data.json"]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :external_resource_attribute
      assert result.name == :external_resource
      assert result.value == "priv/data.json"
      assert result.metadata.path == "priv/data.json"
    end
  end

  # ===========================================================================
  # Compile Attribute Tests
  # ===========================================================================

  describe "extract/2 @compile" do
    test "extracts @compile with option" do
      ast = {:@, [], [{:compile, [], [:inline]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :compile_attribute
      assert result.name == :compile
      assert result.value == :inline
    end

    test "extracts @compile with keyword options" do
      ast = {:@, [], [{:compile, [], [[inline: [{:my_func, 1}]]]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :compile_attribute
      assert result.metadata.options == [inline: [{:my_func, 1}]]
    end
  end

  # ===========================================================================
  # Behaviour Attribute Tests
  # ===========================================================================

  describe "extract/2 @behaviour" do
    test "extracts @behaviour with module" do
      ast = {:@, [], [{:behaviour, [], [{:__aliases__, [], [:GenServer]}]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :behaviour_declaration
      assert result.name == :behaviour
      assert result.metadata.module == [:GenServer]
    end

    test "extracts @behavior (US spelling)" do
      ast = {:@, [], [{:behavior, [], [{:__aliases__, [], [:Supervisor]}]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :behaviour_declaration
      assert result.name == :behavior
      assert result.metadata.module == [:Supervisor]
    end

    test "extracts @behaviour with nested module" do
      ast = {:@, [], [{:behaviour, [], [{:__aliases__, [], [:MyApp, :CustomBehaviour]}]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.metadata.module == [:MyApp, :CustomBehaviour]
    end

    test "extracts @behaviour with erlang module" do
      ast = {:@, [], [{:behaviour, [], [:gen_server]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :behaviour_declaration
      assert result.metadata.module == :gen_server
    end

    test "behaviour? returns true for behaviour declarations" do
      ast = {:@, [], [{:behaviour, [], [{:__aliases__, [], [:GenServer]}]}]}
      {:ok, result} = Attribute.extract(ast)
      assert Attribute.behaviour?(result)
    end

    test "behaviour? returns false for other attributes" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}
      {:ok, result} = Attribute.extract(ast)
      refute Attribute.behaviour?(result)
    end

    test "behaviour_module returns module for behaviour" do
      ast = {:@, [], [{:behaviour, [], [{:__aliases__, [], [:GenServer]}]}]}
      {:ok, result} = Attribute.extract(ast)
      assert Attribute.behaviour_module(result) == [:GenServer]
    end

    test "behaviour_module returns nil for non-behaviour" do
      ast = {:@, [], [{:doc, [], ["docs"]}]}
      {:ok, result} = Attribute.extract(ast)
      assert Attribute.behaviour_module(result) == nil
    end
  end

  # ===========================================================================
  # Other Attribute Type Tests
  # ===========================================================================

  describe "extract/2 other attribute types" do
    test "extracts @callback" do
      ast =
        {:@, [],
         [{:callback, [], [{:"::", [], [{:my_callback, [], [{:t, [], nil}]}, {:atom, [], nil}]}]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :callback_attribute
      assert result.name == :callback
    end

    test "extracts @impl" do
      ast = {:@, [], [{:impl, [], [true]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :impl_attribute
      assert result.name == :impl
      assert result.value == true
    end

    test "extracts @derive" do
      ast = {:@, [], [{:derive, [], [[{:__aliases__, [], [:Inspect]}]]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :derive_attribute
      assert result.name == :derive
    end

    test "extracts @enforce_keys" do
      ast = {:@, [], [{:enforce_keys, [], [[:name, :age]]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :enforce_keys_attribute
      assert result.metadata.keys == [:name, :age]
    end

    test "extracts @dialyzer" do
      ast = {:@, [], [{:dialyzer, [], [:no_return]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :dialyzer_attribute
      assert result.name == :dialyzer
    end

    test "extracts @on_load" do
      ast = {:@, [], [{:on_load, [], [:init]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :on_load_attribute
    end

    test "extracts @before_compile" do
      ast = {:@, [], [{:before_compile, [], [{:__aliases__, [], [:MyMacros]}]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :before_compile_attribute
    end

    test "extracts @after_compile" do
      ast = {:@, [], [{:after_compile, [], [{:__aliases__, [], [:MyModule]}]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :after_compile_attribute
    end

    test "extracts @vsn" do
      ast = {:@, [], [{:vsn, [], ["1.0.0"]}]}

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :vsn_attribute
    end
  end

  # ===========================================================================
  # Bulk Extraction Tests
  # ===========================================================================

  describe "extract_all/1" do
    test "extracts all attributes from block" do
      body =
        {:__block__, [],
         [
           {:@, [], [{:moduledoc, [], ["Module docs"]}]},
           {:@, [], [{:doc, [], ["Function docs"]}]},
           {:def, [], [{:foo, [], nil}]},
           {:@, [], [{:deprecated, [], ["Use bar/0"]}]}
         ]}

      results = Attribute.extract_all(body)
      assert length(results) == 3
      assert Enum.map(results, & &1.name) == [:moduledoc, :doc, :deprecated]
    end

    test "extracts single attribute" do
      body = {:@, [], [{:doc, [], ["docs"]}]}

      results = Attribute.extract_all(body)
      assert length(results) == 1
      assert hd(results).name == :doc
    end

    test "returns empty list for nil" do
      assert Attribute.extract_all(nil) == []
    end

    test "returns empty list for non-attribute" do
      body = {:def, [], [{:foo, [], nil}]}
      assert Attribute.extract_all(body) == []
    end

    test "maintains order of attributes" do
      body =
        {:__block__, [],
         [
           {:@, [], [{:first, [], [1]}]},
           {:@, [], [{:second, [], [2]}]},
           {:@, [], [{:third, [], [3]}]}
         ]}

      results = Attribute.extract_all(body)
      assert Enum.map(results, & &1.name) == [:first, :second, :third]
    end
  end

  # ===========================================================================
  # Extract! Tests
  # ===========================================================================

  describe "extract!/2" do
    test "returns result on success" do
      ast = {:@, [], [{:custom, [], [42]}]}
      result = Attribute.extract!(ast)

      assert result.name == :custom
      assert result.value == 42
    end

    test "raises on error" do
      ast = {:def, [], [{:foo, [], nil}]}

      assert_raise ArgumentError, ~r/Not an attribute/, fn ->
        Attribute.extract!(ast)
      end
    end
  end

  # ===========================================================================
  # Integration Tests with quote
  # ===========================================================================

  describe "integration with quote" do
    test "extracts @doc from quoted code" do
      ast =
        quote do
          @doc "Hello world"
        end

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :doc_attribute
      assert result.value == "Hello world"
    end

    test "extracts @behaviour from quoted code" do
      ast =
        quote do
          @behaviour GenServer
        end

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :behaviour_declaration
      assert result.metadata.module == [:GenServer]
    end

    test "extracts @deprecated from quoted code" do
      ast =
        quote do
          @deprecated "Use new_function/1 instead"
        end

      assert {:ok, result} = Attribute.extract(ast)
      assert result.type == :deprecated_attribute
      assert result.metadata.message == "Use new_function/1 instead"
    end
  end
end
