defmodule ElixirOntologies.Extractors.Capture do
  @moduledoc """
  Extracts capture operator expressions from Elixir AST.

  This module provides extraction of function captures created with the `&` operator,
  including named function captures and shorthand anonymous function captures.

  ## Capture Types

  ### Named Local Captures
  ```elixir
  &foo/1           # Local function capture
  &bar/2           # Local function with arity 2
  ```

  ### Named Remote Captures
  ```elixir
  &String.upcase/1      # Elixir module function
  &Module.func/2        # Any module function
  &:erlang.element/2    # Erlang module function
  ```

  ### Shorthand Captures
  ```elixir
  &(&1 + 1)             # Single-arg shorthand
  &(&1 + &2)            # Multi-arg shorthand
  &String.split(&1, ",") # Remote call with placeholder
  ```

  ## Examples

      iex> ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      iex> ElixirOntologies.Extractors.Capture.capture?(ast)
      true

      iex> ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      iex> {:ok, capture} = ElixirOntologies.Extractors.Capture.extract(ast)
      iex> capture.type
      :named_local
      iex> capture.function
      :foo
      iex> capture.arity
      1
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Capture Struct
  # ===========================================================================

  @typedoc """
  The result of capture extraction.

  - `:type` - The capture type: :named_local, :named_remote, or :shorthand
  - `:module` - Module for remote captures (nil for local/shorthand)
  - `:function` - Function name for named captures (nil for shorthand)
  - `:arity` - Arity (explicit for named, calculated from placeholders for shorthand)
  - `:expression` - Body expression for shorthand captures (nil for named)
  - `:placeholders` - List of placeholder positions found (for shorthand)
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type capture_type :: :named_local | :named_remote | :shorthand

  @type t :: %__MODULE__{
          type: capture_type(),
          module: module() | atom() | nil,
          function: atom() | nil,
          arity: non_neg_integer(),
          expression: Macro.t() | nil,
          placeholders: [pos_integer()],
          location: map() | nil,
          metadata: map()
        }

  @enforce_keys [:type, :arity]
  defstruct [
    :type,
    :module,
    :function,
    :arity,
    :expression,
    placeholders: [],
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a capture expression.

  ## Examples

      iex> ElixirOntologies.Extractors.Capture.capture?({:&, [], [{:/, [], [{:foo, [], nil}, 1]}]})
      true

      iex> ElixirOntologies.Extractors.Capture.capture?({:&, [], [{:+, [], [{:&, [], [1]}, 1]}]})
      true

      iex> ElixirOntologies.Extractors.Capture.capture?({:fn, [], []})
      false

      iex> ElixirOntologies.Extractors.Capture.capture?(:not_ast)
      false
  """
  @spec capture?(Macro.t()) :: boolean()
  def capture?({:&, _meta, [_content]}), do: true
  def capture?(_), do: false

  @doc """
  Checks if an AST node represents a capture placeholder (&1, &2, etc.).

  ## Examples

      iex> ElixirOntologies.Extractors.Capture.placeholder?({:&, [], [1]})
      true

      iex> ElixirOntologies.Extractors.Capture.placeholder?({:&, [], [2]})
      true

      iex> ElixirOntologies.Extractors.Capture.placeholder?({:&, [], [{:+, [], [{:&, [], [1]}, 1]}]})
      false
  """
  @spec placeholder?(Macro.t()) :: boolean()
  def placeholder?({:&, _meta, [n]}) when is_integer(n) and n > 0, do: true
  def placeholder?(_), do: false

  # ===========================================================================
  # Extraction
  # ===========================================================================

  @doc """
  Extracts a capture expression from an AST node.

  Returns `{:ok, %Capture{}}` on success, or `{:error, reason}` on failure.

  ## Examples

      iex> ast = {:&, [], [{:/, [], [{:foo, [], Elixir}, 1]}]}
      iex> {:ok, capture} = ElixirOntologies.Extractors.Capture.extract(ast)
      iex> capture.type
      :named_local
      iex> capture.function
      :foo

      iex> ElixirOntologies.Extractors.Capture.extract({:fn, [], []})
      {:error, :not_capture}
  """
  @spec extract(Macro.t()) :: {:ok, t()} | {:error, atom()}
  def extract({:&, _meta, [content]} = node) do
    location = Helpers.extract_location(node)

    case classify_and_extract(content) do
      {:ok, capture_data} ->
        {:ok, struct(__MODULE__, Map.put(capture_data, :location, location))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def extract(_), do: {:error, :not_capture}

  @doc """
  Extracts all capture expressions from an AST.

  Traverses the AST and extracts all capture operator expressions found.

  ## Examples

      iex> ast = quote do
      ...>   &foo/1
      ...>   &(&1 + 1)
      ...> end
      iex> results = ElixirOntologies.Extractors.Capture.extract_all(ast)
      iex> length(results)
      2
  """
  @spec extract_all(Macro.t()) :: [t()]
  def extract_all(ast) do
    ast
    |> find_all_captures()
    |> Enum.map(fn node ->
      {:ok, result} = extract(node)
      result
    end)
  end

  @doc """
  Finds all placeholder positions in a capture expression.

  Returns a sorted list of unique placeholder positions.

  ## Examples

      iex> ast = {:+, [], [{:&, [], [1]}, {:&, [], [2]}]}
      iex> ElixirOntologies.Extractors.Capture.find_placeholders(ast)
      [1, 2]

      iex> ast = {:+, [], [{:&, [], [1]}, 1]}
      iex> ElixirOntologies.Extractors.Capture.find_placeholders(ast)
      [1]
  """
  @spec find_placeholders(Macro.t()) :: [pos_integer()]
  def find_placeholders(ast) do
    {_, placeholders} =
      Macro.prewalk(ast, [], fn
        {:&, _meta, [n]} = node, acc when is_integer(n) and n > 0 ->
          {node, [n | acc]}

        node, acc ->
          {node, acc}
      end)

    placeholders
    |> Enum.uniq()
    |> Enum.sort()
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Classify the capture content and extract data
  defp classify_and_extract({:/, _meta, [target, arity]}) when is_integer(arity) do
    extract_named_capture(target, arity)
  end

  # Shorthand capture - expression contains placeholders
  defp classify_and_extract(expression) do
    placeholders = find_placeholders(expression)

    if placeholders == [] do
      # No placeholders found - this might be a malformed capture or zero-arity
      {:ok,
       %{
         type: :shorthand,
         module: nil,
         function: nil,
         arity: 0,
         expression: expression,
         placeholders: [],
         metadata: %{}
       }}
    else
      arity = Enum.max(placeholders)

      {:ok,
       %{
         type: :shorthand,
         module: nil,
         function: nil,
         arity: arity,
         expression: expression,
         placeholders: placeholders,
         metadata: %{}
       }}
    end
  end

  # Local function capture: &foo/1
  defp extract_named_capture({name, _meta, context}, arity)
       when is_atom(name) and is_atom(context) do
    {:ok,
     %{
       type: :named_local,
       module: nil,
       function: name,
       arity: arity,
       expression: nil,
       placeholders: [],
       metadata: %{}
     }}
  end

  # Remote function capture: &Module.func/1 or &:erlang.func/1
  defp extract_named_capture({{:., _dot_meta, [module_ast, function]}, _call_meta, []}, arity)
       when is_atom(function) do
    module = extract_module(module_ast)

    {:ok,
     %{
       type: :named_remote,
       module: module,
       function: function,
       arity: arity,
       expression: nil,
       placeholders: [],
       metadata: %{module_ast: module_ast}
     }}
  end

  # Fallback for unrecognized named capture patterns
  defp extract_named_capture(_target, _arity) do
    {:error, :unrecognized_capture_pattern}
  end

  # Extract module from AST
  defp extract_module({:__aliases__, _meta, parts}) when is_list(parts) do
    Module.concat(parts)
  end

  defp extract_module(atom) when is_atom(atom) do
    atom
  end

  defp extract_module(_), do: nil

  # Find all capture expressions in AST (excluding placeholders inside captures)
  defp find_all_captures(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        # Don't recurse into capture - just collect it and skip children
        {:&, _meta, [content]} = node, acc ->
          if is_integer(content) do
            # This is a placeholder (&1, &2), not a capture expression
            {node, acc}
          else
            # This is a real capture - collect it but don't recurse into content
            # Return nil to skip recursion into children
            {nil, [node | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end
end
