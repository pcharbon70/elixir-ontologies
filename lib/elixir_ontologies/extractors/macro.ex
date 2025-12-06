defmodule ElixirOntologies.Extractors.Macro do
  @moduledoc """
  Extracts macro definitions from AST nodes.

  This module analyzes Elixir AST nodes representing macro definitions
  (defmacro, defmacrop) and extracts information including macro name,
  arity, visibility, parameters, guards, body, and hygiene settings.

  ## Ontology Classes

  From `elixir-structure.ttl`:
  - `Macro` - Base class for macro definitions
  - `PublicMacro`, `PrivateMacro` - Visibility subclasses
  - `macroName`, `macroArity` properties
  - `isHygienic` property for hygiene detection

  ## Usage

      iex> alias ElixirOntologies.Extractors.Macro
      iex> ast = {:defmacro, [], [{:my_macro, [], [{:x, [], nil}]}, [do: {:x, [], nil}]]}
      iex> {:ok, result} = Macro.extract(ast)
      iex> result.name
      :my_macro
      iex> result.visibility
      :public

      iex> alias ElixirOntologies.Extractors.Macro
      iex> ast = {:defmacrop, [], [{:private_macro, [], []}, [do: :ok]]}
      iex> {:ok, result} = Macro.extract(ast)
      iex> result.visibility
      :private
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of macro definition extraction.

  - `:name` - Macro name as atom
  - `:arity` - Number of parameters
  - `:visibility` - :public or :private
  - `:parameters` - List of parameter AST nodes
  - `:guard` - Guard expression if present
  - `:body` - Macro body AST
  - `:is_hygienic` - Whether macro is hygienic
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          name: atom(),
          arity: non_neg_integer(),
          visibility: :public | :private,
          parameters: [Macro.t()],
          guard: Macro.t() | nil,
          body: Macro.t(),
          is_hygienic: boolean(),
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct [
    :name,
    :arity,
    :visibility,
    :body,
    parameters: [],
    guard: nil,
    is_hygienic: true,
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Macro Definition Forms
  # ===========================================================================

  @macro_forms [:defmacro, :defmacrop]

  # ===========================================================================
  # Macro Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a macro definition.

  ## Examples

      iex> ElixirOntologies.Extractors.Macro.macro?({:defmacro, [], [{:foo, [], []}, [do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.Macro.macro?({:defmacrop, [], [{:bar, [], []}, [do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.Macro.macro?({:def, [], [{:foo, [], []}, [do: :ok]]})
      false

      iex> ElixirOntologies.Extractors.Macro.macro?(nil)
      false
  """
  @spec macro?(Macro.t()) :: boolean()
  def macro?({form, _, _}) when form in @macro_forms, do: true
  def macro?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a macro definition from an AST node.

  Returns `{:ok, %Macro{}}` on success, or `{:error, reason}` if the node
  is not a macro definition.

  ## Examples

      iex> ast = {:defmacro, [], [{:my_macro, [], [{:x, [], nil}]}, [do: {:x, [], nil}]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Macro.extract(ast)
      iex> result.name
      :my_macro
      iex> result.arity
      1
      iex> result.visibility
      :public

      iex> ast = {:defmacrop, [], [{:private_macro, [], []}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Macro.extract(ast)
      iex> result.visibility
      :private
      iex> result.arity
      0

      iex> ast = {:defmacro, [], [{:when, [], [{:guarded, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Macro.extract(ast)
      iex> result.name
      :guarded
      iex> result.metadata.has_guard
      true
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  # defmacro/defmacrop with guard: defmacro name(args) when guard do body end
  def extract({form, meta, [{:when, _, [call, guard]}, body_opts]}, _opts)
      when form in @macro_forms do
    {name, params} = extract_name_and_params(call)
    body = extract_body(body_opts)
    visibility = form_to_visibility(form)
    location = Helpers.extract_location({form, meta, []})
    {is_hygienic, hygiene_info} = analyze_hygiene(body)

    {:ok,
     %__MODULE__{
       name: name,
       arity: length(params),
       visibility: visibility,
       parameters: params,
       guard: guard,
       body: body,
       is_hygienic: is_hygienic,
       location: location,
       metadata: Map.merge(hygiene_info, %{has_guard: true})
     }}
  end

  # defmacro/defmacrop without guard: defmacro name(args) do body end
  def extract({form, meta, [call, body_opts]}, _opts)
      when form in @macro_forms do
    {name, params} = extract_name_and_params(call)
    body = extract_body(body_opts)
    visibility = form_to_visibility(form)
    location = Helpers.extract_location({form, meta, []})
    {is_hygienic, hygiene_info} = analyze_hygiene(body)

    {:ok,
     %__MODULE__{
       name: name,
       arity: length(params),
       visibility: visibility,
       parameters: params,
       guard: nil,
       body: body,
       is_hygienic: is_hygienic,
       location: location,
       metadata: Map.merge(hygiene_info, %{has_guard: false})
     }}
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Not a macro definition", node)}
  end

  @doc """
  Extracts a macro definition from an AST node, raising on error.

  ## Examples

      iex> ast = {:defmacro, [], [{:foo, [], []}, [do: :ok]]}
      iex> result = ElixirOntologies.Extractors.Macro.extract!(ast)
      iex> result.name
      :foo
  """
  @spec extract!(Macro.t(), keyword()) :: t()
  def extract!(node, opts \\ []) do
    case extract(node, opts) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
  end

  # ===========================================================================
  # Bulk Extraction
  # ===========================================================================

  @doc """
  Extracts all macro definitions from a module body.

  Returns a list of extracted macro definitions in the order they appear.

  ## Examples

      iex> body = {:__block__, [], [
      ...>   {:defmacro, [], [{:foo, [], []}, [do: :ok]]},
      ...>   {:defmacrop, [], [{:bar, [], []}, [do: :ok]]},
      ...>   {:def, [], [{:baz, [], []}, [do: :ok]]}
      ...> ]}
      iex> results = ElixirOntologies.Extractors.Macro.extract_all(body)
      iex> length(results)
      2
      iex> Enum.map(results, & &1.name)
      [:foo, :bar]
  """
  @spec extract_all(Macro.t()) :: [t()]
  def extract_all(nil), do: []

  def extract_all({:__block__, _, statements}) when is_list(statements) do
    statements
    |> Enum.filter(&macro?/1)
    |> Enum.map(fn node ->
      case extract(node) do
        {:ok, result} -> result
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def extract_all(statement) do
    if macro?(statement) do
      case extract(statement) do
        {:ok, result} -> [result]
        {:error, _} -> []
      end
    else
      []
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Returns true if the macro is public (defmacro).

  ## Examples

      iex> ast = {:defmacro, [], [{:foo, [], []}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Macro.extract(ast)
      iex> ElixirOntologies.Extractors.Macro.public?(result)
      true

      iex> ast = {:defmacrop, [], [{:bar, [], []}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Macro.extract(ast)
      iex> ElixirOntologies.Extractors.Macro.public?(result)
      false
  """
  @spec public?(t()) :: boolean()
  def public?(%__MODULE__{visibility: :public}), do: true
  def public?(_), do: false

  @doc """
  Returns true if the macro is private (defmacrop).

  ## Examples

      iex> ast = {:defmacrop, [], [{:bar, [], []}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Macro.extract(ast)
      iex> ElixirOntologies.Extractors.Macro.private?(result)
      true
  """
  @spec private?(t()) :: boolean()
  def private?(%__MODULE__{visibility: :private}), do: true
  def private?(_), do: false

  @doc """
  Returns true if the macro is hygienic.

  A macro is considered hygienic if it doesn't use `var!` or other
  hygiene-breaking constructs.

  ## Examples

      iex> ast = {:defmacro, [], [{:hygienic, [], []}, [do: {:quote, [], [[do: :ok]]}]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Macro.extract(ast)
      iex> ElixirOntologies.Extractors.Macro.hygienic?(result)
      true
  """
  @spec hygienic?(t()) :: boolean()
  def hygienic?(%__MODULE__{is_hygienic: true}), do: true
  def hygienic?(_), do: false

  @doc """
  Returns true if the macro has a guard clause.

  ## Examples

      iex> ast = {:defmacro, [], [{:when, [], [{:guarded, [], [{:x, [], nil}]}, {:is_atom, [], [{:x, [], nil}]}]}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Macro.extract(ast)
      iex> ElixirOntologies.Extractors.Macro.has_guard?(result)
      true

      iex> ast = {:defmacro, [], [{:no_guard, [], []}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Macro.extract(ast)
      iex> ElixirOntologies.Extractors.Macro.has_guard?(result)
      false
  """
  @spec has_guard?(t()) :: boolean()
  def has_guard?(%__MODULE__{guard: guard}) when not is_nil(guard), do: true
  def has_guard?(_), do: false

  @doc """
  Returns a macro identifier string.

  ## Examples

      iex> ast = {:defmacro, [], [{:my_macro, [], [{:a, [], nil}, {:b, [], nil}]}, [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Macro.extract(ast)
      iex> ElixirOntologies.Extractors.Macro.macro_id(result)
      "my_macro/2"
  """
  @spec macro_id(t()) :: String.t()
  def macro_id(%__MODULE__{name: name, arity: arity}) do
    "#{name}/#{arity}"
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp extract_name_and_params({name, _, nil}) when is_atom(name) do
    {name, []}
  end

  defp extract_name_and_params({name, _, context}) when is_atom(name) and is_atom(context) do
    {name, []}
  end

  defp extract_name_and_params({name, _, params}) when is_atom(name) and is_list(params) do
    {name, params}
  end

  defp extract_name_and_params(_), do: {nil, []}

  defp extract_body(body_opts) when is_list(body_opts) do
    Keyword.get(body_opts, :do)
  end

  defp extract_body(_), do: nil

  defp form_to_visibility(:defmacro), do: :public
  defp form_to_visibility(:defmacrop), do: :private

  defp analyze_hygiene(body) do
    uses_var_bang = contains_var_bang?(body)
    uses_macro_escape = contains_macro_escape?(body)

    is_hygienic = not uses_var_bang

    hygiene_info = %{
      uses_var_bang: uses_var_bang,
      uses_macro_escape: uses_macro_escape
    }

    {is_hygienic, hygiene_info}
  end

  defp contains_var_bang?(ast) do
    ast
    |> find_calls(:var!)
    |> Enum.any?()
  end

  defp contains_macro_escape?(ast) do
    case ast do
      {{:., _, [{:__aliases__, _, [:Macro]}, :escape]}, _, _} ->
        true

      {_, _, args} when is_list(args) ->
        Enum.any?(args, &contains_macro_escape?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_macro_escape?/1)

      {left, right} ->
        contains_macro_escape?(left) or contains_macro_escape?(right)

      _ ->
        false
    end
  end

  defp find_calls(ast, target_name) do
    {_, calls} =
      Macro.prewalk(ast, [], fn
        {^target_name, _, args} = node, acc when is_list(args) ->
          {node, [node | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end
end
