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
  # CapturePlaceholder Struct
  # ===========================================================================

  defmodule Placeholder do
    @moduledoc """
    Represents a capture placeholder (&1, &2, etc.) with usage information.

    ## Fields

    - `:position` - The placeholder number (1 for &1, 2 for &2, etc.)
    - `:usage_count` - Number of times this placeholder appears
    - `:locations` - List of source locations where this placeholder is used
    - `:metadata` - Additional information
    """

    alias ElixirOntologies.Analyzer.Location.SourceLocation

    @type t :: %__MODULE__{
            position: pos_integer(),
            usage_count: pos_integer(),
            locations: [SourceLocation.t()],
            metadata: map()
          }

    @enforce_keys [:position, :usage_count]
    defstruct [
      :position,
      :usage_count,
      locations: [],
      metadata: %{}
    ]
  end

  # ===========================================================================
  # PlaceholderAnalysis Struct
  # ===========================================================================

  defmodule PlaceholderAnalysis do
    @moduledoc """
    Complete analysis of placeholders in a shorthand capture expression.

    ## Fields

    - `:placeholders` - List of Placeholder structs with detailed info
    - `:highest` - Highest placeholder number (determines arity)
    - `:arity` - Derived arity from highest placeholder
    - `:gaps` - List of missing placeholder numbers (e.g., [2] if &1, &3 used)
    - `:has_gaps` - Whether there are gaps in placeholder numbering
    - `:total_usages` - Total number of placeholder usages
    - `:metadata` - Additional information
    """

    alias ElixirOntologies.Extractors.Capture.Placeholder

    @type t :: %__MODULE__{
            placeholders: [Placeholder.t()],
            highest: pos_integer() | nil,
            arity: non_neg_integer(),
            gaps: [pos_integer()],
            has_gaps: boolean(),
            total_usages: non_neg_integer(),
            metadata: map()
          }

    @enforce_keys [:placeholders, :arity]
    defstruct [
      :placeholders,
      :highest,
      :arity,
      gaps: [],
      has_gaps: false,
      total_usages: 0,
      metadata: %{}
    ]
  end

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
  # Placeholder Analysis
  # ===========================================================================

  @doc """
  Extracts all capture placeholders from an AST with location information.

  Returns a list of `%Placeholder{}` structs, each containing the position,
  usage count, and locations where that placeholder appears.

  ## Examples

      iex> ast = {:+, [], [{:&, [line: 1, column: 1], [1]}, {:&, [line: 1, column: 5], [2]}]}
      iex> placeholders = ElixirOntologies.Extractors.Capture.extract_capture_placeholders(ast)
      iex> length(placeholders)
      2
      iex> Enum.map(placeholders, & &1.position)
      [1, 2]
  """
  @spec extract_capture_placeholders(Macro.t()) :: [Placeholder.t()]
  def extract_capture_placeholders(ast) do
    # Find all placeholder nodes with their metadata
    {_, placeholder_nodes} =
      Macro.prewalk(ast, [], fn
        {:&, meta, [n]} = node, acc when is_integer(n) and n > 0 ->
          {node, [{n, meta} | acc]}

        node, acc ->
          {node, acc}
      end)

    # Group by position and build Placeholder structs
    placeholder_nodes
    |> Enum.group_by(fn {position, _meta} -> position end)
    |> Enum.map(fn {position, occurrences} ->
      locations =
        occurrences
        |> Enum.map(fn {_pos, meta} ->
          extract_placeholder_location(meta)
        end)
        |> Enum.reject(&is_nil/1)

      %Placeholder{
        position: position,
        usage_count: length(occurrences),
        locations: locations,
        metadata: %{}
      }
    end)
    |> Enum.sort_by(& &1.position)
  end

  @doc """
  Performs complete analysis of placeholders in a shorthand capture expression.

  Returns a `%PlaceholderAnalysis{}` struct with all placeholder details,
  including gap detection and arity calculation.

  ## Examples

      iex> ast = {:+, [], [{:&, [], [1]}, {:&, [], [2]}]}
      iex> {:ok, analysis} = ElixirOntologies.Extractors.Capture.analyze_placeholders(ast)
      iex> analysis.arity
      2
      iex> analysis.has_gaps
      false

      iex> ast = {:+, [], [{:&, [], [1]}, {:&, [], [3]}]}
      iex> {:ok, analysis} = ElixirOntologies.Extractors.Capture.analyze_placeholders(ast)
      iex> analysis.has_gaps
      true
      iex> analysis.gaps
      [2]
  """
  @spec analyze_placeholders(Macro.t()) :: {:ok, PlaceholderAnalysis.t()}
  def analyze_placeholders(ast) do
    placeholders = extract_capture_placeholders(ast)
    positions = Enum.map(placeholders, & &1.position)

    highest = if positions == [], do: nil, else: Enum.max(positions)
    arity = highest || 0

    # Detect gaps - positions that are missing between 1 and highest
    gaps =
      if highest do
        expected = MapSet.new(1..highest)
        actual = MapSet.new(positions)
        MapSet.difference(expected, actual) |> MapSet.to_list() |> Enum.sort()
      else
        []
      end

    total_usages = Enum.sum(Enum.map(placeholders, & &1.usage_count))

    {:ok,
     %PlaceholderAnalysis{
       placeholders: placeholders,
       highest: highest,
       arity: arity,
       gaps: gaps,
       has_gaps: gaps != [],
       total_usages: total_usages,
       metadata: %{}
     }}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Extract location from placeholder metadata
  defp extract_placeholder_location(meta) when is_list(meta) do
    line = Keyword.get(meta, :line)
    column = Keyword.get(meta, :column)

    if line && column do
      %{start_line: line, start_column: column, end_line: nil, end_column: nil}
    else
      nil
    end
  end

  defp extract_placeholder_location(_), do: nil

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
