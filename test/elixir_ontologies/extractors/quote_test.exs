defmodule ElixirOntologies.Extractors.QuoteTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Quote

  doctest Quote

  # ===========================================================================
  # Quote Detection Tests
  # ===========================================================================

  describe "quote?/1" do
    test "returns true for simple quote" do
      ast = {:quote, [], [[do: :ok]]}
      assert Quote.quote?(ast)
    end

    test "returns true for quote with options" do
      ast = {:quote, [], [[context: :match], [do: :ok]]}
      assert Quote.quote?(ast)
    end

    test "returns false for unquote" do
      ast = {:unquote, [], [{:x, [], nil}]}
      refute Quote.quote?(ast)
    end

    test "returns false for def" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      refute Quote.quote?(ast)
    end

    test "returns false for nil" do
      refute Quote.quote?(nil)
    end
  end

  describe "unquote?/1" do
    test "returns true for unquote" do
      ast = {:unquote, [], [{:x, [], nil}]}
      assert Quote.unquote?(ast)
    end

    test "returns false for unquote_splicing" do
      ast = {:unquote_splicing, [], [{:list, [], nil}]}
      refute Quote.unquote?(ast)
    end

    test "returns false for quote" do
      ast = {:quote, [], [[do: :ok]]}
      refute Quote.unquote?(ast)
    end
  end

  describe "unquote_splicing?/1" do
    test "returns true for unquote_splicing" do
      ast = {:unquote_splicing, [], [{:list, [], nil}]}
      assert Quote.unquote_splicing?(ast)
    end

    test "returns false for unquote" do
      ast = {:unquote, [], [{:x, [], nil}]}
      refute Quote.unquote_splicing?(ast)
    end
  end

  # ===========================================================================
  # Quote Extraction Tests
  # ===========================================================================

  describe "extract/2 simple quotes" do
    test "extracts simple quote body" do
      ast = {:quote, [], [[do: {:+, [], [1, 2]}]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.body == {:+, [], [1, 2]}
    end

    test "extracts quote with atom body" do
      ast = {:quote, [], [[do: :ok]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.body == :ok
    end

    test "sets default options for simple quote" do
      ast = {:quote, [], [[do: :ok]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.options.bind_quoted == nil
      assert result.options.context == nil
      assert result.options.location == nil
      assert result.options.unquote == true
    end
  end

  describe "extract/2 quote with options" do
    test "extracts bind_quoted option" do
      ast = {:quote, [], [[bind_quoted: [x: 1, y: 2]], [do: :ok]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.options.bind_quoted == [x: 1, y: 2]
    end

    test "extracts context option" do
      ast = {:quote, [], [[context: :match], [do: :ok]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.options.context == :match
    end

    test "extracts location option" do
      ast = {:quote, [], [[location: :keep], [do: :ok]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.options.location == :keep
    end

    test "extracts unquote: false option" do
      ast = {:quote, [], [[unquote: false], [do: {:unquote, [], [{:x, [], nil}]}]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.options.unquote == false
      # Should not find unquotes when unquote: false
      assert result.unquotes == []
    end

    test "extracts multiple options" do
      ast = {:quote, [], [[context: :match, location: :keep], [do: :ok]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.options.context == :match
      assert result.options.location == :keep
    end
  end

  describe "extract/2 quote with unquotes" do
    test "finds unquote in quote body" do
      body = {:+, [], [{:unquote, [], [{:x, [], nil}]}, 1]}
      ast = {:quote, [], [[do: body]]}

      assert {:ok, result} = Quote.extract(ast)
      assert length(result.unquotes) == 1
      assert hd(result.unquotes).kind == :unquote
    end

    test "finds multiple unquotes" do
      body = {:+, [], [{:unquote, [], [{:x, [], nil}]}, {:unquote, [], [{:y, [], nil}]}]}
      ast = {:quote, [], [[do: body]]}

      assert {:ok, result} = Quote.extract(ast)
      assert length(result.unquotes) == 2
    end

    test "finds unquote_splicing" do
      body = [{:unquote_splicing, [], [{:list, [], nil}]}, :end]
      ast = {:quote, [], [[do: body]]}

      assert {:ok, result} = Quote.extract(ast)
      assert length(result.unquotes) == 1
      assert hd(result.unquotes).kind == :unquote_splicing
    end

    test "sets metadata for unquotes" do
      body = {:+, [], [{:unquote, [], [{:x, [], nil}]}, 1]}
      ast = {:quote, [], [[do: body]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.metadata.unquote_count == 1
      assert result.metadata.has_unquote_splicing == false
    end

    test "sets has_unquote_splicing metadata" do
      body = [{:unquote_splicing, [], [{:list, [], nil}]}, :end]
      ast = {:quote, [], [[do: body]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.metadata.has_unquote_splicing == true
    end
  end

  # ===========================================================================
  # Unquote Extraction Tests
  # ===========================================================================

  describe "extract_unquote/2" do
    test "extracts unquote" do
      ast = {:unquote, [], [{:x, [], nil}]}

      assert {:ok, result} = Quote.extract_unquote(ast)
      assert result.kind == :unquote
      assert result.value == {:x, [], nil}
    end

    test "extracts unquote_splicing" do
      ast = {:unquote_splicing, [], [{:list, [], nil}]}

      assert {:ok, result} = Quote.extract_unquote(ast)
      assert result.kind == :unquote_splicing
      assert result.value == {:list, [], nil}
    end

    test "returns error for non-unquote" do
      ast = {:quote, [], [[do: :ok]]}
      assert {:error, _} = Quote.extract_unquote(ast)
    end
  end

  # ===========================================================================
  # Find Unquotes Tests
  # ===========================================================================

  describe "find_unquotes/1" do
    test "finds unquote in simple expression" do
      ast = {:+, [], [{:unquote, [], [{:x, [], nil}]}, 1]}

      results = Quote.find_unquotes(ast)
      assert length(results) == 1
      assert hd(results).kind == :unquote
    end

    test "finds multiple unquotes" do
      ast = {:+, [], [{:unquote, [], [{:x, [], nil}]}, {:unquote, [], [{:y, [], nil}]}]}

      results = Quote.find_unquotes(ast)
      assert length(results) == 2
    end

    test "finds unquote_splicing in list" do
      ast = [{:unquote_splicing, [], [{:list, [], nil}]}, :end]

      results = Quote.find_unquotes(ast)
      assert length(results) == 1
      assert hd(results).kind == :unquote_splicing
    end

    test "does not descend into nested quotes" do
      # The inner quote contains an unquote that should not be found
      inner_quote = {:quote, [], [[do: {:unquote, [], [{:hidden, [], nil}]}]]}
      ast = {:+, [], [{:unquote, [], [{:x, [], nil}]}, inner_quote]}

      results = Quote.find_unquotes(ast)
      assert length(results) == 1
      assert hd(results).value == {:x, [], nil}
    end

    test "returns empty list for no unquotes" do
      ast = {:+, [], [1, 2]}

      results = Quote.find_unquotes(ast)
      assert results == []
    end
  end

  # ===========================================================================
  # Bulk Extraction Tests
  # ===========================================================================

  describe "extract_all/1" do
    test "extracts all quotes from block" do
      ast =
        {:__block__, [],
         [
           {:quote, [], [[do: :a]]},
           {:def, [], [{:foo, [], nil}, [do: :ok]]},
           {:quote, [], [[do: :b]]}
         ]}

      results = Quote.extract_all(ast)
      assert length(results) == 2
      assert Enum.map(results, & &1.body) == [:a, :b]
    end

    test "extracts single quote" do
      ast = {:quote, [], [[do: :ok]]}

      results = Quote.extract_all(ast)
      assert length(results) == 1
    end

    test "finds nested quotes in expressions" do
      ast =
        {:def, [],
         [
           {:foo, [], nil},
           [do: {:quote, [], [[do: :in_function]]}]
         ]}

      results = Quote.extract_all(ast)
      assert length(results) == 1
      assert hd(results).body == :in_function
    end

    test "returns empty list for no quotes" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}

      results = Quote.extract_all(ast)
      assert results == []
    end
  end

  # ===========================================================================
  # Helper Function Tests
  # ===========================================================================

  describe "has_bind_quoted?/1" do
    test "returns true when bind_quoted present" do
      ast = {:quote, [], [[bind_quoted: [x: 1]], [do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.has_bind_quoted?(result)
    end

    test "returns false when bind_quoted absent" do
      ast = {:quote, [], [[do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      refute Quote.has_bind_quoted?(result)
    end
  end

  describe "has_context?/1" do
    test "returns true when context present" do
      ast = {:quote, [], [[context: :match], [do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.has_context?(result)
    end

    test "returns false when context absent" do
      ast = {:quote, [], [[do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      refute Quote.has_context?(result)
    end
  end

  describe "has_unquotes?/1" do
    test "returns true when unquotes present" do
      body = {:unquote, [], [{:x, [], nil}]}
      ast = {:quote, [], [[do: body]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.has_unquotes?(result)
    end

    test "returns false when no unquotes" do
      ast = {:quote, [], [[do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      refute Quote.has_unquotes?(result)
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/2 error handling" do
    test "returns error for non-quote" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}
      assert {:error, _} = Quote.extract(ast)
    end

    test "returns error for nil" do
      assert {:error, _} = Quote.extract(nil)
    end
  end

  describe "extract!/2" do
    test "returns result on success" do
      ast = {:quote, [], [[do: :ok]]}
      result = Quote.extract!(ast)
      assert result.body == :ok
    end

    test "raises on error" do
      ast = {:def, [], [{:foo, [], nil}, [do: :ok]]}

      assert_raise ArgumentError, fn ->
        Quote.extract!(ast)
      end
    end
  end

  # ===========================================================================
  # Integration Tests with quote
  # ===========================================================================

  describe "integration with quote" do
    test "extracts simple quote from quoted code" do
      {:quote, _, _} =
        ast =
        quote do
          quote do
            1 + 2
          end
        end

      assert {:ok, result} = Quote.extract(ast)
      # Body should be an addition
      assert match?({:+, _, [1, 2]}, result.body)
    end

    test "extracts quote with unquote from quoted code" do
      {:quote, _, _} =
        ast =
        quote do
          quote do
            unquote(x) + 1
          end
        end

      assert {:ok, result} = Quote.extract(ast)
      assert length(result.unquotes) == 1
    end

    test "extracts quote with bind_quoted from quoted code" do
      {:quote, _, _} =
        ast =
        quote do
          quote bind_quoted: [x: x] do
            x + 1
          end
        end

      assert {:ok, result} = Quote.extract(ast)
      assert Quote.has_bind_quoted?(result)
    end

    test "extracts quote with context from quoted code" do
      {:quote, _, _} =
        ast =
        quote do
          quote context: :match do
            {a, b}
          end
        end

      assert {:ok, result} = Quote.extract(ast)
      assert result.options.context == :match
    end
  end
end
