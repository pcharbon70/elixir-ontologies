defmodule ElixirOntologies.Extractors.CaptureTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Capture

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "capture?/1" do
    test "returns true for local function capture" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      assert Capture.capture?(ast)
    end

    test "returns true for remote function capture" do
      ast =
        {:&, [],
         [
           {:/, [],
            [{{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], []}, 1]}
         ]}

      assert Capture.capture?(ast)
    end

    test "returns true for shorthand capture" do
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, 1]}]}
      assert Capture.capture?(ast)
    end

    test "returns false for anonymous function" do
      ast = {:fn, [], [{:->, [], [[], :ok]}]}
      refute Capture.capture?(ast)
    end

    test "returns false for regular function call" do
      ast = {:foo, [], [1, 2]}
      refute Capture.capture?(ast)
    end

    test "returns false for non-AST" do
      refute Capture.capture?(:not_ast)
      refute Capture.capture?("string")
      refute Capture.capture?(123)
    end
  end

  describe "placeholder?/1" do
    test "returns true for &1" do
      assert Capture.placeholder?({:&, [], [1]})
    end

    test "returns true for &2" do
      assert Capture.placeholder?({:&, [], [2]})
    end

    test "returns true for higher numbered placeholders" do
      assert Capture.placeholder?({:&, [], [10]})
    end

    test "returns false for capture expression" do
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, 1]}]}
      refute Capture.placeholder?(ast)
    end

    test "returns false for &0" do
      refute Capture.placeholder?({:&, [], [0]})
    end

    test "returns false for negative placeholder" do
      refute Capture.placeholder?({:&, [], [-1]})
    end
  end

  # ===========================================================================
  # Local Function Capture Tests
  # ===========================================================================

  describe "extract/1 with local function captures" do
    test "extracts simple local function capture" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :named_local
      assert capture.function == :foo
      assert capture.arity == 1
      assert capture.module == nil
    end

    test "extracts local function with higher arity" do
      ast = {:&, [], [{:/, [], [{:bar, [], Elixir}, 3]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :named_local
      assert capture.function == :bar
      assert capture.arity == 3
    end

    test "extracts zero-arity local function" do
      ast = {:&, [], [{:/, [], [{:get_value, [], Elixir}, 0]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :named_local
      assert capture.function == :get_value
      assert capture.arity == 0
    end
  end

  # ===========================================================================
  # Remote Function Capture Tests
  # ===========================================================================

  describe "extract/1 with remote function captures" do
    test "extracts Elixir module function capture" do
      ast =
        {:&, [],
         [
           {:/, [],
            [{{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], []}, 1]}
         ]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :named_remote
      assert capture.module == String
      assert capture.function == :upcase
      assert capture.arity == 1
    end

    test "extracts nested module function capture" do
      ast =
        {:&, [],
         [
           {:/, [],
            [
              {{:., [], [{:__aliases__, [], [:MyApp, :Utils, :String]}, :format]}, [], []},
              2
            ]}
         ]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :named_remote
      assert capture.module == MyApp.Utils.String
      assert capture.function == :format
      assert capture.arity == 2
    end

    test "extracts Erlang module function capture" do
      ast =
        {:&, [],
         [{:/, [], [{{:., [], [:erlang, :element]}, [], []}, 2]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :named_remote
      assert capture.module == :erlang
      assert capture.function == :element
      assert capture.arity == 2
    end

    test "extracts :lists module function capture" do
      ast =
        {:&, [],
         [{:/, [], [{{:., [], [:lists, :reverse]}, [], []}, 1]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :named_remote
      assert capture.module == :lists
      assert capture.function == :reverse
      assert capture.arity == 1
    end
  end

  # ===========================================================================
  # Shorthand Capture Tests
  # ===========================================================================

  describe "extract/1 with shorthand captures" do
    test "extracts simple shorthand capture" do
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, 1]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :shorthand
      assert capture.arity == 1
      assert capture.placeholders == [1]
      assert capture.expression == {:+, [], [{:&, [], [1]}, 1]}
    end

    test "extracts multi-arg shorthand capture" do
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, {:&, [], [2]}]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :shorthand
      assert capture.arity == 2
      assert capture.placeholders == [1, 2]
    end

    test "extracts shorthand with remote call" do
      ast =
        {:&, [],
         [
           {{:., [], [{:__aliases__, [], [:String]}, :split]}, [],
            [{:&, [], [1]}, ","]}
         ]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :shorthand
      assert capture.arity == 1
      assert capture.placeholders == [1]
    end

    test "extracts shorthand with multiple placeholders in different positions" do
      # &(&2 - &1) - placeholders not in order
      ast = {:&, [], [{:-, [], [{:&, [], [2]}, {:&, [], [1]}]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :shorthand
      assert capture.arity == 2
      assert capture.placeholders == [1, 2]
    end

    test "extracts complex nested shorthand" do
      # &(&1 + &2 * &3)
      ast =
        {:&, [],
         [
           {:+, [],
            [
              {:&, [], [1]},
              {:*, [], [{:&, [], [2]}, {:&, [], [3]}]}
            ]}
         ]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :shorthand
      assert capture.arity == 3
      assert capture.placeholders == [1, 2, 3]
    end

    test "handles shorthand with gaps in placeholders" do
      # &(&1 + &3) - skipping &2
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, {:&, [], [3]}]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :shorthand
      # Arity is max placeholder
      assert capture.arity == 3
      assert capture.placeholders == [1, 3]
    end

    test "handles shorthand with repeated placeholders" do
      # &(&1 + &1)
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, {:&, [], [1]}]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.type == :shorthand
      assert capture.arity == 1
      # Deduplicated
      assert capture.placeholders == [1]
    end
  end

  # ===========================================================================
  # find_placeholders/1 Tests
  # ===========================================================================

  describe "find_placeholders/1" do
    test "finds single placeholder" do
      ast = {:+, [], [{:&, [], [1]}, 1]}
      assert Capture.find_placeholders(ast) == [1]
    end

    test "finds multiple placeholders" do
      ast = {:+, [], [{:&, [], [1]}, {:&, [], [2]}]}
      assert Capture.find_placeholders(ast) == [1, 2]
    end

    test "returns sorted unique placeholders" do
      ast =
        {:+, [],
         [
           {:&, [], [3]},
           {:*, [], [{:&, [], [1]}, {:&, [], [2]}]}
         ]}

      assert Capture.find_placeholders(ast) == [1, 2, 3]
    end

    test "deduplicates repeated placeholders" do
      ast =
        {:+, [],
         [
           {:&, [], [1]},
           {:&, [], [1]}
         ]}

      assert Capture.find_placeholders(ast) == [1]
    end

    test "returns empty list for no placeholders" do
      ast = {:+, [], [1, 2]}
      assert Capture.find_placeholders(ast) == []
    end

    test "finds placeholders in deeply nested expressions" do
      ast =
        {:if, [],
         [
           {:>, [], [{:&, [], [1]}, 0]},
           [
             do: {:&, [], [2]},
             else: {:&, [], [3]}
           ]
         ]}

      assert Capture.find_placeholders(ast) == [1, 2, 3]
    end
  end

  # ===========================================================================
  # extract_all/1 Tests
  # ===========================================================================

  describe "extract_all/1" do
    test "finds all captures in block" do
      ast =
        quote do
          &foo/1
          &(&1 + 1)
        end

      results = Capture.extract_all(ast)
      assert length(results) == 2
      assert Enum.any?(results, &(&1.type == :named_local))
      assert Enum.any?(results, &(&1.type == :shorthand))
    end

    test "finds captures in nested expressions" do
      ast =
        quote do
          list
          |> Enum.map(&String.upcase/1)
          |> Enum.filter(&(&1 != ""))
        end

      results = Capture.extract_all(ast)
      assert length(results) == 2
    end

    test "returns empty list for no captures" do
      ast = quote do: fn x -> x + 1 end
      assert Capture.extract_all(ast) == []
    end
  end

  # ===========================================================================
  # Error Handling Tests
  # ===========================================================================

  describe "extract/1 error handling" do
    test "returns error for non-capture" do
      ast = {:fn, [], [{:->, [], [[], :ok]}]}
      assert {:error, :not_capture} = Capture.extract(ast)
    end

    test "returns error for regular function call" do
      ast = {:foo, [], [1, 2]}
      assert {:error, :not_capture} = Capture.extract(ast)
    end

    test "returns error for atom" do
      assert {:error, :not_capture} = Capture.extract(:foo)
    end
  end

  # ===========================================================================
  # Metadata Tests
  # ===========================================================================

  describe "capture metadata" do
    test "captures have empty placeholders for named captures" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.placeholders == []
    end

    test "named captures have nil expression" do
      ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.expression == nil
    end

    test "shorthand captures have nil module and function" do
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, 1]}]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.module == nil
      assert capture.function == nil
    end

    test "remote captures store module_ast in metadata" do
      ast =
        {:&, [],
         [
           {:/, [],
            [{{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], []}, 1]}
         ]}

      assert {:ok, capture} = Capture.extract(ast)
      assert capture.metadata[:module_ast] == {:__aliases__, [], [:String]}
    end
  end

  # ===========================================================================
  # Doctest Verification
  # ===========================================================================

  doctest ElixirOntologies.Extractors.Capture
end
