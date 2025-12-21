defmodule ElixirOntologies.Extractors.Call do
  @moduledoc """
  Extracts function call information from Elixir AST.

  This module provides extraction of function calls, starting with local calls
  (calls to functions in the same module). Future phases will add remote calls
  (Module.function) and dynamic calls (apply, anonymous function calls).

  ## Architecture Note

  This extractor is designed for composable, on-demand call graph analysis. It is
  intentionally **not** automatically invoked by the main Pipeline module. This
  separation allows:

  - Lightweight module extraction when call details aren't needed
  - Targeted call graph analysis when building dependency graphs
  - Flexibility to use extractors individually or in combination

  ## Call vs Variable Distinction

  In Elixir AST, local calls and variable references have similar structure but
  differ in the third element:

      # Variable reference - context is nil or atom
      {:x, [line: 1], nil}
      {:x, [line: 1], Elixir}

      # Local function call - args is a list
      {:foo, [line: 1], []}
      {:bar, [line: 1], [{:x, [], nil}]}

  This module correctly distinguishes these cases.

  ## Examples

      iex> ast = {:foo, [line: 1], []}
      iex> ElixirOntologies.Extractors.Call.local_call?(ast)
      true

      iex> ast = {:foo, [line: 1], [1, 2]}
      iex> {:ok, call} = ElixirOntologies.Extractors.Call.extract(ast)
      iex> call.name
      :foo
      iex> call.arity
      2

      iex> ast = {:x, [line: 1], nil}
      iex> ElixirOntologies.Extractors.Call.local_call?(ast)
      false
  """

  alias ElixirOntologies.Extractors.Helpers
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # ===========================================================================
  # Struct Definition
  # ===========================================================================

  defmodule FunctionCall do
    @moduledoc """
    Represents a function call extracted from AST.

    ## Fields

    - `:type` - Call type (:local, :remote, or :dynamic)
    - `:name` - Function name as atom
    - `:arity` - Number of arguments
    - `:arguments` - List of argument AST nodes (raw AST)
    - `:location` - Source location if available
    - `:metadata` - Additional information (e.g., containing function)
    """

    @typedoc """
    The type of function call.

    - `:local` - Call to function in same module
    - `:remote` - Call via Module.function syntax
    - `:dynamic` - Call via apply or anonymous function
    """
    @type call_type :: :local | :remote | :dynamic

    @type t :: %__MODULE__{
            type: call_type(),
            name: atom(),
            arity: non_neg_integer(),
            arguments: [Macro.t()],
            location: SourceLocation.t() | nil,
            metadata: map()
          }

    @enforce_keys [:type, :name, :arity]
    defstruct [:type, :name, :arity, arguments: [], location: nil, metadata: %{}]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if the given AST node represents a local function call.

  Returns `true` for calls to local functions (functions in the same module).
  Returns `false` for variable references, special forms, operators, and
  remote calls.

  ## Key Distinction

  The third element of the AST tuple determines if it's a call or variable:
  - List (even empty) → function call
  - nil or atom → variable reference

  ## Examples

      iex> ElixirOntologies.Extractors.Call.local_call?({:foo, [], []})
      true

      iex> ElixirOntologies.Extractors.Call.local_call?({:bar, [line: 1], [1, 2]})
      true

      iex> ElixirOntologies.Extractors.Call.local_call?({:x, [], nil})
      false

      iex> ElixirOntologies.Extractors.Call.local_call?({:def, [], [[do: :ok]]})
      false

      iex> ElixirOntologies.Extractors.Call.local_call?({:if, [], [true, [do: 1]]})
      false

      iex> ElixirOntologies.Extractors.Call.local_call?(:not_a_call)
      false
  """
  @spec local_call?(Macro.t()) :: boolean()
  def local_call?({name, _meta, args})
      when is_atom(name) and is_list(args) do
    not Helpers.special_form?(name) and not operator?(name)
  end

  def local_call?(_), do: false

  # Operators that might appear with list args but aren't local calls
  @operators [:+, :-, :*, :/, :==, :!=, :===, :!==, :<, :>, :<=, :>=, :&&, :||, :!, :and, :or, :not,
              :++, :--, :<>, :in, :@, :when, :"not in"]

  defp operator?(name), do: name in @operators

  # ===========================================================================
  # Single Extraction
  # ===========================================================================

  @doc """
  Extracts a local function call from an AST node.

  Returns `{:ok, %FunctionCall{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:foo, [line: 5], []}
      iex> {:ok, call} = ElixirOntologies.Extractors.Call.extract(ast)
      iex> call.name
      :foo
      iex> call.arity
      0
      iex> call.type
      :local

      iex> ast = {:bar, [], [1, {:x, [], nil}]}
      iex> {:ok, call} = ElixirOntologies.Extractors.Call.extract(ast)
      iex> call.name
      :bar
      iex> call.arity
      2
      iex> length(call.arguments)
      2

      iex> ElixirOntologies.Extractors.Call.extract({:x, [], nil})
      {:error, {:not_a_local_call, "Not a local function call: {:x, [], nil}"}}
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, FunctionCall.t()} | {:error, term()}
  def extract(ast, opts \\ [])

  def extract({name, _meta, args} = node, opts)
      when is_atom(name) and is_list(args) do
    if local_call?(node) do
      build_local_call(name, args, node, opts)
    else
      {:error, {:not_a_local_call, Helpers.format_error("Not a local function call", node)}}
    end
  end

  def extract(node, _opts) do
    {:error, {:not_a_local_call, Helpers.format_error("Not a local function call", node)}}
  end

  @doc """
  Extracts a local function call, raising on error.

  ## Examples

      iex> ast = {:foo, [], [1, 2]}
      iex> call = ElixirOntologies.Extractors.Call.extract!(ast)
      iex> call.name
      :foo
      iex> call.arity
      2
  """
  @spec extract!(Macro.t(), keyword()) :: FunctionCall.t()
  def extract!(ast, opts \\ []) do
    case extract(ast, opts) do
      {:ok, call} -> call
      {:error, reason} -> raise ArgumentError, "Failed to extract call: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Bulk Extraction
  # ===========================================================================

  @doc """
  Extracts all local function calls from an AST.

  Walks the entire AST tree and extracts all local function calls found.
  This includes calls in function bodies, nested blocks, and within arguments
  of other calls.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)
  - `:max_depth` - Maximum recursion depth (default: 100)

  ## Examples

      iex> body = [
      ...>   {:foo, [], []},
      ...>   {:bar, [], [1, 2]},
      ...>   {:def, [], [{:test, [], nil}, [do: {:baz, [], []}]]}
      ...> ]
      iex> calls = ElixirOntologies.Extractors.Call.extract_local_calls(body)
      iex> Enum.map(calls, & &1.name)
      [:foo, :bar, :baz]

      iex> ast = {:if, [], [true, [do: {:foo, [], []}]]}
      iex> calls = ElixirOntologies.Extractors.Call.extract_local_calls(ast)
      iex> Enum.map(calls, & &1.name)
      [:foo]
  """
  @spec extract_local_calls(Macro.t(), keyword()) :: [FunctionCall.t()]
  def extract_local_calls(ast, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, Helpers.max_recursion_depth())
    extract_calls_recursive(ast, opts, 0, max_depth)
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp build_local_call(name, args, node, opts) do
    location = Helpers.extract_location_if(node, opts)

    {:ok,
     %FunctionCall{
       type: :local,
       name: name,
       arity: length(args),
       arguments: args,
       location: location,
       metadata: %{}
     }}
  end

  # Recursive extraction with depth tracking
  defp extract_calls_recursive(_ast, _opts, depth, max_depth) when depth > max_depth do
    []
  end

  # Handle list of statements
  defp extract_calls_recursive(statements, opts, depth, max_depth) when is_list(statements) do
    Enum.flat_map(statements, &extract_calls_recursive(&1, opts, depth, max_depth))
  end

  # Handle __block__
  defp extract_calls_recursive({:__block__, _meta, statements}, opts, depth, max_depth) do
    extract_calls_recursive(statements, opts, depth, max_depth)
  end

  # Handle local function call - extract it and recurse into args
  defp extract_calls_recursive({name, _meta, args} = node, opts, depth, max_depth)
       when is_atom(name) and is_list(args) do
    calls_from_args = extract_calls_recursive(args, opts, depth + 1, max_depth)

    if local_call?(node) do
      case extract(node, opts) do
        {:ok, call} -> [call | calls_from_args]
        {:error, _} -> calls_from_args
      end
    else
      # Still recurse into args for special forms like if, case, etc.
      calls_from_args
    end
  end

  # Handle two-element tuples (e.g., keyword pairs, {key, value})
  defp extract_calls_recursive({left, right}, opts, depth, max_depth) do
    extract_calls_recursive(left, opts, depth + 1, max_depth) ++
      extract_calls_recursive(right, opts, depth + 1, max_depth)
  end

  # Handle three-element tuples that aren't AST nodes (rare)
  defp extract_calls_recursive({a, b, c}, opts, depth, max_depth)
       when not is_atom(a) or not is_list(b) do
    extract_calls_recursive(a, opts, depth + 1, max_depth) ++
      extract_calls_recursive(b, opts, depth + 1, max_depth) ++
      extract_calls_recursive(c, opts, depth + 1, max_depth)
  end

  # Ignore atoms, literals, and other non-tuple forms
  defp extract_calls_recursive(_other, _opts, _depth, _max_depth) do
    []
  end
end
