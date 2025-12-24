defmodule ElixirOntologies.Extractors.ClosureTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Closure
  alias ElixirOntologies.Extractors.Closure.{FreeVariable, FreeVariableAnalysis}
  alias ElixirOntologies.Extractors.AnonymousFunction

  doctest Closure

  # ===========================================================================
  # FreeVariable Struct Tests
  # ===========================================================================

  describe "FreeVariable struct" do
    test "creates struct with required fields" do
      free_var = %FreeVariable{name: :x, reference_count: 1}
      assert free_var.name == :x
      assert free_var.reference_count == 1
      assert free_var.reference_locations == []
      assert free_var.captured_at == nil
      assert free_var.metadata == %{}
    end

    test "creates struct with all fields" do
      location = %{start_line: 1, start_column: 5}

      free_var = %FreeVariable{
        name: :outer,
        reference_count: 3,
        reference_locations: [location],
        captured_at: %{start_line: 1},
        metadata: %{usage: :read}
      }

      assert free_var.name == :outer
      assert free_var.reference_count == 3
      assert length(free_var.reference_locations) == 1
    end
  end

  # ===========================================================================
  # FreeVariableAnalysis Struct Tests
  # ===========================================================================

  describe "FreeVariableAnalysis struct" do
    test "creates struct with required fields" do
      analysis = %FreeVariableAnalysis{
        free_variables: [],
        bound_variables: [:x, :y]
      }

      assert analysis.free_variables == []
      assert analysis.bound_variables == [:x, :y]
      assert analysis.all_references == []
      assert analysis.has_captures == false
      assert analysis.total_capture_count == 0
    end

    test "creates struct with free variables" do
      free_var = %FreeVariable{name: :outer, reference_count: 2}

      analysis = %FreeVariableAnalysis{
        free_variables: [free_var],
        bound_variables: [:x],
        all_references: [:x, :outer],
        has_captures: true,
        total_capture_count: 2
      }

      assert length(analysis.free_variables) == 1
      assert analysis.has_captures == true
    end
  end

  # ===========================================================================
  # find_variable_references/1 Tests
  # ===========================================================================

  describe "find_variable_references/1" do
    test "finds simple variable references" do
      ast = quote do: x + y
      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      assert names == [:x, :y]
    end

    test "handles literals without variables" do
      ast = quote do: 1 + 2
      refs = Closure.find_variable_references(ast)
      assert refs == []
    end

    test "handles atoms" do
      ast = quote do: :ok
      refs = Closure.find_variable_references(ast)
      assert refs == []
    end

    test "finds variables in function calls" do
      ast = quote do: String.upcase(x)
      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end)
      assert names == [:x]
    end

    test "does not include module names as variables" do
      ast = quote do: Enum.map(list, func)
      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      assert names == [:func, :list]
    end

    test "finds variables in nested expressions" do
      ast = quote do: if(x > 0, do: y + z, else: a - b)
      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      assert names == [:a, :b, :x, :y, :z]
    end

    test "finds variables in lists" do
      ast = quote do: [a, b, c]
      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      assert names == [:a, :b, :c]
    end

    test "finds variables in tuples" do
      ast = quote do: {x, y, z}
      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      assert names == [:x, :y, :z]
    end

    test "finds variables in maps" do
      ast = quote do: %{key: value, other: data}
      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      assert names == [:data, :value]
    end

    test "does not count underscore as variable" do
      ast = quote do: {x, _}
      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end)
      assert names == [:x]
    end

    test "handles pipe operators" do
      ast = quote do: x |> func() |> other(y)
      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      assert names == [:x, :y]
    end
  end

  # ===========================================================================
  # find_variable_references/1 - Scope-aware Tests
  # ===========================================================================

  describe "find_variable_references/1 with nested scopes" do
    test "does not include variables bound in nested fn" do
      # fn x -> x end - x is bound, not free
      ast = quote do: fn x -> x end
      refs = Closure.find_variable_references(ast)
      assert refs == []
    end

    test "finds free variables in nested fn" do
      # fn x -> x + y end - y is free
      ast = quote do: fn x -> x + y end
      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end)
      assert names == [:y]
    end

    test "handles case expression bindings" do
      # In case, pattern bindings are local to clause
      ast =
        quote do
          case result do
            {:ok, value} -> value + x
            {:error, reason} -> reason
          end
        end

      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      # result and x are free, value and reason are bound
      assert names == [:result, :x]
    end

    test "handles for comprehension bindings" do
      ast = quote do: for(item <- list, do: item + x)
      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      # list and x are free, item is bound
      assert names == [:list, :x]
    end

    test "handles with expression bindings" do
      ast =
        quote do
          with {:ok, a} <- fetch_a(),
               {:ok, b} <- fetch_b(a) do
            a + b + x
          end
        end

      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      # x is free, a and b are bound by with
      assert names == [:x]
    end

    test "finds pin operator references" do
      ast =
        quote do
          case x do
            ^existing -> :matched
            other -> other
          end
        end

      refs = Closure.find_variable_references(ast)
      names = Enum.map(refs, fn {name, _} -> name end) |> Enum.sort()
      # x and existing are referenced (existing via pin)
      assert names == [:existing, :x]
    end
  end

  # ===========================================================================
  # detect_free_variables/2 Tests
  # ===========================================================================

  describe "detect_free_variables/2" do
    test "identifies free variables correctly" do
      refs = [{:x, [line: 1]}, {:y, [line: 2]}, {:z, [line: 3]}]
      bound = [:x]

      {:ok, analysis} = Closure.detect_free_variables(refs, bound)

      assert analysis.has_captures == true
      assert length(analysis.free_variables) == 2

      free_names = Enum.map(analysis.free_variables, & &1.name)
      assert :y in free_names
      assert :z in free_names
      refute :x in free_names
    end

    test "returns empty free variables when all are bound" do
      refs = [{:x, [line: 1]}, {:y, [line: 2]}]
      bound = [:x, :y]

      {:ok, analysis} = Closure.detect_free_variables(refs, bound)

      assert analysis.has_captures == false
      assert analysis.free_variables == []
    end

    test "counts multiple references to same variable" do
      refs = [{:x, [line: 1]}, {:x, [line: 2]}, {:x, [line: 3]}]
      bound = []

      {:ok, analysis} = Closure.detect_free_variables(refs, bound)

      assert length(analysis.free_variables) == 1
      free_var = hd(analysis.free_variables)
      assert free_var.name == :x
      assert free_var.reference_count == 3
    end

    test "tracks total capture count" do
      refs = [{:x, []}, {:x, []}, {:y, []}]
      bound = []

      {:ok, analysis} = Closure.detect_free_variables(refs, bound)

      assert analysis.total_capture_count == 3
    end

    test "sorts free variables by name" do
      refs = [{:z, []}, {:a, []}, {:m, []}]
      bound = []

      {:ok, analysis} = Closure.detect_free_variables(refs, bound)

      names = Enum.map(analysis.free_variables, & &1.name)
      assert names == [:a, :m, :z]
    end

    test "includes location information" do
      refs = [{:x, [line: 5, column: 10]}]
      bound = []

      {:ok, analysis} = Closure.detect_free_variables(refs, bound)

      free_var = hd(analysis.free_variables)
      assert length(free_var.reference_locations) == 1
      loc = hd(free_var.reference_locations)
      assert loc.start_line == 5
      assert loc.start_column == 10
    end

    test "includes captured_at location" do
      refs = [{:x, []}]
      bound = []
      capture_location = %{start_line: 1}

      {:ok, analysis} = Closure.detect_free_variables(refs, bound, capture_location)

      free_var = hd(analysis.free_variables)
      assert free_var.captured_at == capture_location
    end
  end

  # ===========================================================================
  # analyze_closure/1 Tests
  # ===========================================================================

  describe "analyze_closure/1" do
    test "detects closure with free variable" do
      ast = quote do: fn x -> x + y end
      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      assert length(analysis.free_variables) == 1
      assert hd(analysis.free_variables).name == :y
      assert :x in analysis.bound_variables
    end

    test "detects non-closure (no free variables)" do
      ast = quote do: fn x -> x + 1 end
      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == false
      assert analysis.free_variables == []
    end

    test "handles multi-argument functions" do
      ast = quote do: fn x, y -> x + y + z end
      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      assert length(analysis.free_variables) == 1
      assert hd(analysis.free_variables).name == :z
      assert :x in analysis.bound_variables
      assert :y in analysis.bound_variables
    end

    test "handles multi-clause anonymous functions" do
      ast =
        quote do
          fn
            0 -> zero_val
            n -> n + offset
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      free_names = Enum.map(analysis.free_variables, & &1.name) |> Enum.sort()
      assert free_names == [:offset, :zero_val]
    end

    test "handles anonymous function with guard" do
      ast =
        quote do
          fn
            x when is_integer(x) -> x + offset
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      assert hd(analysis.free_variables).name == :offset
    end

    test "handles complex body with case" do
      ast =
        quote do
          fn input ->
            case input do
              {:ok, value} -> value + multiplier
              {:error, _} -> default
            end
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      free_names = Enum.map(analysis.free_variables, & &1.name) |> Enum.sort()
      # input is bound, value is bound in case clause
      # multiplier and default are free
      assert free_names == [:default, :multiplier]
    end

    test "handles nested anonymous functions" do
      ast =
        quote do
          fn x ->
            fn y ->
              x + y + z
            end
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      # The outer fn only captures z (x is its param, inner fn's y is in inner scope)
      # Actually, the outer fn's body contains a reference to z
      assert analysis.has_captures == true
      assert hd(analysis.free_variables).name == :z
    end

    test "handles body with for comprehension" do
      ast =
        quote do
          fn list ->
            for item <- list, do: item * factor
          end
        end

      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      assert hd(analysis.free_variables).name == :factor
    end

    test "handles zero-arity function with free variables" do
      ast = quote do: fn -> x + y end
      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      assert analysis.bound_variables == []
      free_names = Enum.map(analysis.free_variables, & &1.name) |> Enum.sort()
      assert free_names == [:x, :y]
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "empty function body" do
      ast = quote do: fn -> nil end
      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == false
    end

    test "function that only uses literals" do
      ast = quote do: fn x -> 1 + 2 end
      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == false
    end

    test "function with pattern matching in parameters" do
      ast = quote do: fn {a, b} -> a + b + c end
      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      assert hd(analysis.free_variables).name == :c
      assert :a in analysis.bound_variables
      assert :b in analysis.bound_variables
    end

    test "function with map pattern in parameters" do
      ast = quote do: fn %{name: n, value: v} -> n <> v <> suffix end
      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      assert hd(analysis.free_variables).name == :suffix
    end

    test "tracks reference count for multiple uses" do
      ast = quote do: fn x -> y + y + y end
      {:ok, anon} = AnonymousFunction.extract(ast)
      {:ok, analysis} = Closure.analyze_closure(anon)

      assert analysis.has_captures == true
      free_var = hd(analysis.free_variables)
      assert free_var.name == :y
      assert free_var.reference_count == 3
      assert analysis.total_capture_count == 3
    end
  end
end
