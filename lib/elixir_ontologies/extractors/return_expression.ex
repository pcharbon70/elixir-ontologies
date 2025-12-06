defmodule ElixirOntologies.Extractors.ReturnExpression do
  @moduledoc """
  Extracts return expressions from function bodies.

  This module analyzes Elixir function body AST nodes and extracts the
  return expression (the last expression that determines the function's
  return value). Handles both single-expression and multi-expression bodies.

  ## Ontology Classes

  From `elixir-structure.ttl`:
  - `ReturnExpression` - The expression that a function returns
  - `FunctionBody` with `returnsExpression` property

  ## Usage

      iex> alias ElixirOntologies.Extractors.ReturnExpression
      iex> body = {:+, [], [1, 2]}
      iex> {:ok, result} = ReturnExpression.extract(body)
      iex> result.expression
      {:+, [], [1, 2]}
      iex> result.type
      :call

      iex> alias ElixirOntologies.Extractors.ReturnExpression
      iex> body = {:__block__, [], [{:x, [], nil}, {:y, [], nil}]}
      iex> {:ok, result} = ReturnExpression.extract(body)
      iex> result.expression
      {:y, [], nil}
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of return expression extraction.

  - `:expression` - The AST of the return expression
  - `:type` - Type category of the expression
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          expression: Macro.t(),
          type: :literal | :variable | :call | :control_flow | :block | :other,
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct [
    :expression,
    :type,
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Control Flow Forms
  # ===========================================================================

  @control_flow_forms [:case, :cond, :if, :unless, :with, :try, :receive]

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts the return expression from a function body.

  Returns `{:ok, %ReturnExpression{}}` on success, or `{:error, reason}` if
  extraction fails.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract(:ok)
      iex> result.expression
      :ok
      iex> result.type
      :literal

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract({:x, [], nil})
      iex> result.type
      :variable

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract({:foo, [], [1, 2]})
      iex> result.type
      :call

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract({:case, [], [{:x, [], nil}, [do: []]]})
      iex> result.type
      :control_flow
      iex> result.metadata.control_type
      :case

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract(nil)
      iex> result.metadata.is_nil
      true
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract(body, opts \\ [])

  # Nil body (bodyless function)
  def extract(nil, _opts) do
    {:ok,
     %__MODULE__{
       expression: nil,
       type: :literal,
       location: nil,
       metadata: %{
         multi_return: false,
         control_type: nil,
         is_nil: true
       }
     }}
  end

  # Block expression - extract last expression
  def extract({:__block__, _meta, expressions}, opts) when is_list(expressions) do
    case List.last(expressions) do
      nil -> extract(nil, opts)
      last_expr -> extract(last_expr, opts)
    end
  end

  # Control flow expressions
  def extract({control, meta, args} = expr, _opts) when control in @control_flow_forms do
    location = Helpers.extract_location({control, meta, args})

    {:ok,
     %__MODULE__{
       expression: expr,
       type: :control_flow,
       location: location,
       metadata: %{
         multi_return: true,
         control_type: control,
         is_nil: false
       }
     }}
  end

  # Tuple literal: {a, b, c, ...} (3+ elements)
  # NOTE: Must come before function call pattern
  def extract({:{}, meta, _elements} = expr, _opts) do
    location = Helpers.extract_location({:{}, meta, []})

    {:ok,
     %__MODULE__{
       expression: expr,
       type: :literal,
       location: location,
       metadata: %{
         multi_return: false,
         control_type: nil,
         is_nil: false
       }
     }}
  end

  # Map literal: %{key: value}
  # NOTE: Must come before function call pattern
  def extract({:%{}, meta, _pairs} = expr, _opts) do
    location = Helpers.extract_location({:%{}, meta, []})

    {:ok,
     %__MODULE__{
       expression: expr,
       type: :literal,
       location: location,
       metadata: %{
         multi_return: false,
         control_type: nil,
         is_nil: false
       }
     }}
  end

  # Struct literal: %Module{field: value}
  # NOTE: Must come before function call pattern
  def extract({:%, meta, _args} = expr, _opts) do
    location = Helpers.extract_location({:%, meta, []})

    {:ok,
     %__MODULE__{
       expression: expr,
       type: :literal,
       location: location,
       metadata: %{
         multi_return: false,
         control_type: nil,
         is_nil: false
       }
     }}
  end

  # Remote function call: Module.function(args)
  def extract({{:., _, _}, meta, _args} = expr, _opts) do
    location = Helpers.extract_location({{:., [], []}, meta, []})

    {:ok,
     %__MODULE__{
       expression: expr,
       type: :call,
       location: location,
       metadata: %{
         multi_return: false,
         control_type: nil,
         is_nil: false
       }
     }}
  end

  # Variable reference
  def extract({name, meta, context} = expr, _opts)
      when is_atom(name) and is_atom(context) do
    location = Helpers.extract_location({name, meta, context})

    {:ok,
     %__MODULE__{
       expression: expr,
       type: :variable,
       location: location,
       metadata: %{
         multi_return: false,
         control_type: nil,
         is_nil: false
       }
     }}
  end

  # Function call
  def extract({name, meta, args} = expr, _opts)
      when is_atom(name) and is_list(args) do
    location = Helpers.extract_location({name, meta, args})

    {:ok,
     %__MODULE__{
       expression: expr,
       type: :call,
       location: location,
       metadata: %{
         multi_return: false,
         control_type: nil,
         is_nil: false
       }
     }}
  end

  # 2-tuple: {a, b} (special AST form)
  def extract({_left, right} = expr, _opts) when not is_list(right) do
    {:ok,
     %__MODULE__{
       expression: expr,
       type: :literal,
       location: nil,
       metadata: %{
         multi_return: false,
         control_type: nil,
         is_nil: false
       }
     }}
  end

  # List literal
  def extract(list, _opts) when is_list(list) do
    {:ok,
     %__MODULE__{
       expression: list,
       type: :literal,
       location: nil,
       metadata: %{
         multi_return: false,
         control_type: nil,
         is_nil: false
       }
     }}
  end

  # Atom, number, or string literals
  def extract(literal, _opts)
      when is_atom(literal) or is_number(literal) or is_binary(literal) do
    {:ok,
     %__MODULE__{
       expression: literal,
       type: :literal,
       location: nil,
       metadata: %{
         multi_return: false,
         control_type: nil,
         is_nil: literal == nil
       }
     }}
  end

  # Fallback for other expressions
  def extract(expr, _opts) do
    {:ok,
     %__MODULE__{
       expression: expr,
       type: :other,
       location: nil,
       metadata: %{
         multi_return: false,
         control_type: nil,
         is_nil: false
       }
     }}
  end

  @doc """
  Extracts the return expression from a function body, raising on error.

  ## Examples

      iex> result = ElixirOntologies.Extractors.ReturnExpression.extract!(:ok)
      iex> result.expression
      :ok
  """
  @spec extract!(Macro.t(), keyword()) :: t()
  def extract!(body, opts \\ []) do
    # extract/2 always returns {:ok, result} due to fallback pattern
    {:ok, result} = extract(body, opts)
    result
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Returns true if the return expression represents control flow with multiple branches.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract({:case, [], [{:x, [], nil}, [do: []]]})
      iex> ElixirOntologies.Extractors.ReturnExpression.multi_return?(result)
      true

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract(:ok)
      iex> ElixirOntologies.Extractors.ReturnExpression.multi_return?(result)
      false
  """
  @spec multi_return?(t()) :: boolean()
  def multi_return?(%__MODULE__{metadata: %{multi_return: multi}}), do: multi
  def multi_return?(_), do: false

  @doc """
  Returns true if the return expression is nil (bodyless function).

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract(nil)
      iex> ElixirOntologies.Extractors.ReturnExpression.is_nil_return?(result)
      true

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract(:ok)
      iex> ElixirOntologies.Extractors.ReturnExpression.is_nil_return?(result)
      false
  """
  @spec is_nil_return?(t()) :: boolean()
  def is_nil_return?(%__MODULE__{metadata: %{is_nil: is_nil}}), do: is_nil
  def is_nil_return?(_), do: false

  @doc """
  Returns the control flow type if the return is a control flow expression.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract({:case, [], [{:x, [], nil}, [do: []]]})
      iex> ElixirOntologies.Extractors.ReturnExpression.control_type(result)
      :case

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract(:ok)
      iex> ElixirOntologies.Extractors.ReturnExpression.control_type(result)
      nil
  """
  @spec control_type(t()) :: atom() | nil
  def control_type(%__MODULE__{metadata: %{control_type: type}}), do: type
  def control_type(_), do: nil

  @doc """
  Returns a string describing the return expression type.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract(:ok)
      iex> ElixirOntologies.Extractors.ReturnExpression.describe(result)
      "literal"

      iex> {:ok, result} = ElixirOntologies.Extractors.ReturnExpression.extract({:case, [], [{:x, [], nil}, [do: []]]})
      iex> ElixirOntologies.Extractors.ReturnExpression.describe(result)
      "control_flow:case"
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{type: :control_flow, metadata: %{control_type: type}}) do
    "control_flow:#{type}"
  end

  def describe(%__MODULE__{type: type}), do: Atom.to_string(type)
end
