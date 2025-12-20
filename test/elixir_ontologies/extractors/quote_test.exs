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
  # QuoteOptions Struct Tests (15.3.1)
  # ===========================================================================

  describe "QuoteOptions struct" do
    alias Quote.QuoteOptions

    test "new/1 creates struct with all fields" do
      opts = QuoteOptions.new(
        bind_quoted: [x: 1],
        context: :match,
        location: :keep,
        unquote: false,
        line: 42,
        file: "test.ex",
        generated: true
      )

      assert opts.bind_quoted == [x: 1]
      assert opts.context == :match
      assert opts.location == :keep
      assert opts.unquote == false
      assert opts.line == 42
      assert opts.file == "test.ex"
      assert opts.generated == true
    end

    test "new/0 creates struct with defaults" do
      opts = QuoteOptions.new()

      assert opts.bind_quoted == nil
      assert opts.context == nil
      assert opts.location == nil
      assert opts.unquote == true
      assert opts.line == nil
      assert opts.file == nil
      assert opts.generated == nil
    end

    test "location_keep?/1 returns true for location: :keep" do
      assert QuoteOptions.location_keep?(QuoteOptions.new(location: :keep))
      refute QuoteOptions.location_keep?(QuoteOptions.new())
    end

    test "unquoting_disabled?/1 returns true for unquote: false" do
      assert QuoteOptions.unquoting_disabled?(QuoteOptions.new(unquote: false))
      refute QuoteOptions.unquoting_disabled?(QuoteOptions.new())
    end

    test "has_bind_quoted?/1 checks for bind_quoted" do
      assert QuoteOptions.has_bind_quoted?(QuoteOptions.new(bind_quoted: [x: 1]))
      refute QuoteOptions.has_bind_quoted?(QuoteOptions.new(bind_quoted: []))
      refute QuoteOptions.has_bind_quoted?(QuoteOptions.new())
    end

    test "bind_quoted_vars/1 gets variable names" do
      assert QuoteOptions.bind_quoted_vars(QuoteOptions.new(bind_quoted: [x: 1, y: 2])) == [:x, :y]
      assert QuoteOptions.bind_quoted_vars(QuoteOptions.new()) == []
    end

    test "has_context?/1 checks for context" do
      assert QuoteOptions.has_context?(QuoteOptions.new(context: :match))
      refute QuoteOptions.has_context?(QuoteOptions.new())
    end

    test "generated?/1 checks for generated" do
      assert QuoteOptions.generated?(QuoteOptions.new(generated: true))
      refute QuoteOptions.generated?(QuoteOptions.new(generated: false))
      refute QuoteOptions.generated?(QuoteOptions.new())
    end

    test "has_line?/1 checks for line" do
      assert QuoteOptions.has_line?(QuoteOptions.new(line: 42))
      refute QuoteOptions.has_line?(QuoteOptions.new())
    end

    test "has_file?/1 checks for file" do
      assert QuoteOptions.has_file?(QuoteOptions.new(file: "test.ex"))
      refute QuoteOptions.has_file?(QuoteOptions.new())
    end
  end

  # ===========================================================================
  # Quote Option Extraction Tests (15.3.1)
  # ===========================================================================

  describe "extract/2 additional options" do
    test "extracts line option" do
      ast = {:quote, [], [[line: 42], [do: :ok]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.options.line == 42
    end

    test "extracts file option" do
      ast = {:quote, [], [[file: "my_macro.ex"], [do: :ok]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.options.file == "my_macro.ex"
    end

    test "extracts generated option" do
      ast = {:quote, [], [[generated: true], [do: :ok]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.options.generated == true
    end

    test "extracts combined options" do
      ast = {:quote, [], [[
        bind_quoted: [x: 1],
        context: :match,
        location: :keep,
        line: 100,
        generated: true
      ], [do: :ok]]}

      assert {:ok, result} = Quote.extract(ast)
      assert result.options.bind_quoted == [x: 1]
      assert result.options.context == :match
      assert result.options.location == :keep
      assert result.options.line == 100
      assert result.options.generated == true
    end

    test "returns QuoteOptions struct" do
      ast = {:quote, [], [[do: :ok]]}

      assert {:ok, result} = Quote.extract(ast)
      assert %Quote.QuoteOptions{} = result.options
    end
  end

  # ===========================================================================
  # New Helper Function Tests (15.3.1)
  # ===========================================================================

  describe "location_keep?/1" do
    test "returns true when location: :keep is set" do
      ast = {:quote, [], [[location: :keep], [do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.location_keep?(result)
    end

    test "returns false when location is not set" do
      ast = {:quote, [], [[do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      refute Quote.location_keep?(result)
    end
  end

  describe "unquoting_disabled?/1" do
    test "returns true when unquote: false" do
      ast = {:quote, [], [[unquote: false], [do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.unquoting_disabled?(result)
    end

    test "returns false by default" do
      ast = {:quote, [], [[do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      refute Quote.unquoting_disabled?(result)
    end
  end

  describe "bind_quoted_vars/1" do
    test "returns variable names when bind_quoted is set" do
      ast = {:quote, [], [[bind_quoted: [x: 1, y: 2, z: 3]], [do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.bind_quoted_vars(result) == [:x, :y, :z]
    end

    test "returns empty list when bind_quoted is not set" do
      ast = {:quote, [], [[do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.bind_quoted_vars(result) == []
    end
  end

  describe "get_context/1" do
    test "returns context when set" do
      ast = {:quote, [], [[context: :match], [do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.get_context(result) == :match
    end

    test "returns nil when context is not set" do
      ast = {:quote, [], [[do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.get_context(result) == nil
    end
  end

  describe "generated?/1" do
    test "returns true when generated: true" do
      ast = {:quote, [], [[generated: true], [do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.generated?(result)
    end

    test "returns false when generated is not set" do
      ast = {:quote, [], [[do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      refute Quote.generated?(result)
    end
  end

  describe "get_line/1" do
    test "returns line when set" do
      ast = {:quote, [], [[line: 42], [do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.get_line(result) == 42
    end

    test "returns nil when line is not set" do
      ast = {:quote, [], [[do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.get_line(result) == nil
    end
  end

  describe "get_file/1" do
    test "returns file when set" do
      ast = {:quote, [], [[file: "test.ex"], [do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.get_file(result) == "test.ex"
    end

    test "returns nil when file is not set" do
      ast = {:quote, [], [[do: :ok]]}
      {:ok, result} = Quote.extract(ast)
      assert Quote.get_file(result) == nil
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
