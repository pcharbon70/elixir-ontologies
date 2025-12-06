defmodule ElixirOntologies.Extractors.MacroTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Macro, as: MacroExtractor

  doctest MacroExtractor

  # ===========================================================================
  # Macro Detection Tests
  # ===========================================================================

  describe "macro?/1" do
    test "returns true for defmacro" do
      ast = {:defmacro, [], [{:foo, [], []}, [do: :ok]]}
      assert MacroExtractor.macro?(ast)
    end

    test "returns true for defmacrop" do
      ast = {:defmacrop, [], [{:bar, [], []}, [do: :ok]]}
      assert MacroExtractor.macro?(ast)
    end

    test "returns false for def" do
      ast = {:def, [], [{:foo, [], []}, [do: :ok]]}
      refute MacroExtractor.macro?(ast)
    end

    test "returns false for defp" do
      ast = {:defp, [], [{:foo, [], []}, [do: :ok]]}
      refute MacroExtractor.macro?(ast)
    end

    test "returns false for nil" do
      refute MacroExtractor.macro?(nil)
    end

    test "returns false for @spec" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      refute MacroExtractor.macro?(ast)
    end
  end

  # ===========================================================================
  # defmacro Extraction Tests
  # ===========================================================================

  describe "extract/2 defmacro" do
    test "extracts simple public macro" do
      ast = {:defmacro, [], [{:my_macro, [], []}, [do: :ok]]}

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.name == :my_macro
      assert result.arity == 0
      assert result.visibility == :public
      assert result.parameters == []
      assert result.body == :ok
    end

    test "extracts macro with one parameter" do
      ast = {:defmacro, [], [{:my_macro, [], [{:x, [], nil}]}, [do: {:x, [], nil}]]}

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.name == :my_macro
      assert result.arity == 1
      assert length(result.parameters) == 1
    end

    test "extracts macro with multiple parameters" do
      ast = {:defmacro, [], [{:my_macro, [], [{:a, [], nil}, {:b, [], nil}, {:c, [], nil}]}, [do: :ok]]}

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.name == :my_macro
      assert result.arity == 3
      assert length(result.parameters) == 3
    end

    test "extracts macro with guard" do
      ast =
        {:defmacro, [],
         [
           {:when, [], [{:guarded, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]},
           [do: :ok]
         ]}

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.name == :guarded
      assert result.arity == 1
      assert result.guard != nil
      assert result.metadata.has_guard == true
    end

    test "extracts macro body" do
      body = {:quote, [], [[do: {:+, [], [{:x, [], nil}, 1]}]]}
      ast = {:defmacro, [], [{:add_one, [], [{:x, [], nil}]}, [do: body]]}

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.body == body
    end
  end

  # ===========================================================================
  # defmacrop Extraction Tests
  # ===========================================================================

  describe "extract/2 defmacrop" do
    test "extracts private macro" do
      ast = {:defmacrop, [], [{:private_macro, [], []}, [do: :ok]]}

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.name == :private_macro
      assert result.visibility == :private
    end

    test "extracts private macro with parameters" do
      ast = {:defmacrop, [], [{:private_macro, [], [{:a, [], nil}, {:b, [], nil}]}, [do: :ok]]}

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.name == :private_macro
      assert result.arity == 2
      assert result.visibility == :private
    end

    test "extracts private macro with guard" do
      ast =
        {:defmacrop, [],
         [
           {:when, [], [{:guarded_private, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]},
           [do: :ok]
         ]}

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.name == :guarded_private
      assert result.visibility == :private
      assert result.guard != nil
    end
  end

  # ===========================================================================
  # Hygiene Detection Tests
  # ===========================================================================

  describe "hygiene detection" do
    test "detects hygienic macro" do
      body = {:quote, [], [[do: :ok]]}
      ast = {:defmacro, [], [{:hygienic, [], []}, [do: body]]}

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.is_hygienic == true
      assert result.metadata.uses_var_bang == false
    end

    test "detects unhygienic macro with var!" do
      body = {:quote, [], [[do: {:=, [], [{:var!, [], [{:x, [], nil}]}, 1]}]]}
      ast = {:defmacro, [], [{:unhygienic, [], []}, [do: body]]}

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.is_hygienic == false
      assert result.metadata.uses_var_bang == true
    end

    test "detects Macro.escape usage" do
      body =
        {:__block__, [],
         [
           {:=, [], [{:escaped, [], nil}, {{:., [], [{:__aliases__, [], [:Macro]}, :escape]}, [], [{:value, [], nil}]}]},
           {:quote, [], [[do: {:unquote, [], [{:escaped, [], nil}]}]]}
         ]}

      ast = {:defmacro, [], [{:with_escape, [], [{:value, [], nil}]}, [do: body]]}

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.metadata.uses_macro_escape == true
    end
  end

  # ===========================================================================
  # Bulk Extraction Tests
  # ===========================================================================

  describe "extract_all/1" do
    test "extracts all macros from block" do
      body =
        {:__block__, [],
         [
           {:defmacro, [], [{:foo, [], []}, [do: :ok]]},
           {:defmacrop, [], [{:bar, [], []}, [do: :ok]]},
           {:def, [], [{:baz, [], []}, [do: :ok]]},
           {:defmacro, [], [{:qux, [], []}, [do: :ok]]}
         ]}

      results = MacroExtractor.extract_all(body)
      assert length(results) == 3
      assert Enum.map(results, & &1.name) == [:foo, :bar, :qux]
    end

    test "extracts single macro" do
      ast = {:defmacro, [], [{:single, [], []}, [do: :ok]]}

      results = MacroExtractor.extract_all(ast)
      assert length(results) == 1
      assert hd(results).name == :single
    end

    test "returns empty list for nil" do
      assert MacroExtractor.extract_all(nil) == []
    end

    test "returns empty list for non-macro" do
      ast = {:def, [], [{:not_a_macro, [], []}, [do: :ok]]}
      assert MacroExtractor.extract_all(ast) == []
    end
  end

  # ===========================================================================
  # Helper Function Tests
  # ===========================================================================

  describe "public?/1" do
    test "returns true for defmacro" do
      ast = {:defmacro, [], [{:foo, [], []}, [do: :ok]]}
      {:ok, result} = MacroExtractor.extract(ast)
      assert MacroExtractor.public?(result)
    end

    test "returns false for defmacrop" do
      ast = {:defmacrop, [], [{:bar, [], []}, [do: :ok]]}
      {:ok, result} = MacroExtractor.extract(ast)
      refute MacroExtractor.public?(result)
    end
  end

  describe "private?/1" do
    test "returns true for defmacrop" do
      ast = {:defmacrop, [], [{:bar, [], []}, [do: :ok]]}
      {:ok, result} = MacroExtractor.extract(ast)
      assert MacroExtractor.private?(result)
    end

    test "returns false for defmacro" do
      ast = {:defmacro, [], [{:foo, [], []}, [do: :ok]]}
      {:ok, result} = MacroExtractor.extract(ast)
      refute MacroExtractor.private?(result)
    end
  end

  describe "hygienic?/1" do
    test "returns true for hygienic macro" do
      ast = {:defmacro, [], [{:foo, [], []}, [do: :ok]]}
      {:ok, result} = MacroExtractor.extract(ast)
      assert MacroExtractor.hygienic?(result)
    end

    test "returns false for unhygienic macro" do
      body = {:quote, [], [[do: {:=, [], [{:var!, [], [{:x, [], nil}]}, 1]}]]}
      ast = {:defmacro, [], [{:unhygienic, [], []}, [do: body]]}
      {:ok, result} = MacroExtractor.extract(ast)
      refute MacroExtractor.hygienic?(result)
    end
  end

  describe "has_guard?/1" do
    test "returns true for macro with guard" do
      ast =
        {:defmacro, [],
         [
           {:when, [], [{:guarded, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]},
           [do: :ok]
         ]}

      {:ok, result} = MacroExtractor.extract(ast)
      assert MacroExtractor.has_guard?(result)
    end

    test "returns false for macro without guard" do
      ast = {:defmacro, [], [{:no_guard, [], []}, [do: :ok]]}
      {:ok, result} = MacroExtractor.extract(ast)
      refute MacroExtractor.has_guard?(result)
    end
  end

  describe "macro_id/1" do
    test "returns name/arity for zero-arity macro" do
      ast = {:defmacro, [], [{:foo, [], []}, [do: :ok]]}
      {:ok, result} = MacroExtractor.extract(ast)
      assert MacroExtractor.macro_id(result) == "foo/0"
    end

    test "returns name/arity for multi-arity macro" do
      ast = {:defmacro, [], [{:bar, [], [{:a, [], nil}, {:b, [], nil}]}, [do: :ok]]}
      {:ok, result} = MacroExtractor.extract(ast)
      assert MacroExtractor.macro_id(result) == "bar/2"
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/2 error handling" do
    test "returns error for def" do
      ast = {:def, [], [{:foo, [], []}, [do: :ok]]}
      assert {:error, _} = MacroExtractor.extract(ast)
    end

    test "returns error for @spec" do
      ast = {:@, [], [{:spec, [], [{:"::", [], [{:foo, [], []}, :ok]}]}]}
      assert {:error, _} = MacroExtractor.extract(ast)
    end

    test "returns error for nil" do
      assert {:error, _} = MacroExtractor.extract(nil)
    end
  end

  describe "extract!/2" do
    test "returns result on success" do
      ast = {:defmacro, [], [{:foo, [], []}, [do: :ok]]}
      result = MacroExtractor.extract!(ast)
      assert result.name == :foo
    end

    test "raises on error" do
      ast = {:def, [], [{:foo, [], []}, [do: :ok]]}

      assert_raise ArgumentError, fn ->
        MacroExtractor.extract!(ast)
      end
    end
  end

  # ===========================================================================
  # Integration Tests with quote
  # ===========================================================================

  describe "integration with quote" do
    test "extracts simple macro from quoted code" do
      {:defmacro, _, _} =
        ast =
        quote do
          defmacro my_macro(x) do
            quote do
              unquote(x) + 1
            end
          end
        end

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.name == :my_macro
      assert result.arity == 1
      assert result.visibility == :public
    end

    test "extracts private macro from quoted code" do
      {:defmacrop, _, _} =
        ast =
        quote do
          defmacrop private_helper do
            quote do
              :ok
            end
          end
        end

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.name == :private_helper
      assert result.visibility == :private
    end

    test "extracts macro with guard from quoted code" do
      {:defmacro, _, _} =
        ast =
        quote do
          defmacro guarded(x) when is_atom(x) do
            quote do
              unquote(x)
            end
          end
        end

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.name == :guarded
      assert MacroExtractor.has_guard?(result)
    end

    test "detects var! in quoted macro" do
      {:defmacro, _, _} =
        ast =
        quote do
          defmacro unhygienic do
            quote do
              var!(x) = 1
            end
          end
        end

      assert {:ok, result} = MacroExtractor.extract(ast)
      assert result.is_hygienic == false
      assert result.metadata.uses_var_bang == true
    end
  end
end
