# Test fixture: Deeply nested structures
defmodule NestedStructures do
  @moduledoc "Module with deeply nested code structures"

  def deeply_nested(x) do
    if x > 0 do
      case x do
        1 ->
          cond do
            x == 1 -> :one
            true -> :other
          end

        n when n > 10 ->
          with {:ok, a} <- validate(n),
               {:ok, b} <- transform(a),
               {:ok, c} <- finalize(b) do
            {:ok, c}
          else
            {:error, reason} -> {:error, reason}
          end

        _ ->
          try do
            result = dangerous_operation(x)
            {:ok, result}
          rescue
            e in RuntimeError -> {:error, e.message}
          catch
            :exit, reason -> {:exit, reason}
          after
            cleanup()
          end
      end
    else
      {:error, :negative}
    end
  end

  def nested_anonymous_functions do
    fn x ->
      fn y ->
        fn z ->
          x + y + z
        end
      end
    end
  end

  def nested_comprehensions(data) do
    for outer <- data,
        is_list(outer),
        inner <- outer,
        is_map(inner),
        {key, value} <- inner,
        is_atom(key) do
      {key, value * 2}
    end
  end

  defp validate(n), do: {:ok, n}
  defp transform(n), do: {:ok, n * 2}
  defp finalize(n), do: {:ok, n + 1}
  defp dangerous_operation(x), do: x / 1
  defp cleanup, do: :ok
end

defmodule NestedStructures.Inner do
  @moduledoc "Nested module definition"

  defmodule DeepInner do
    @moduledoc "Deeply nested module"

    def deep_function, do: :deep
  end

  def call_deep, do: DeepInner.deep_function()
end
