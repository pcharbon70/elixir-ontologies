defmodule ElixirOntologies.Extractors.CaseWith do
  @moduledoc """
  Extracts case, with, and receive expressions from Elixir AST.

  This module provides extraction of pattern matching expressions including:
  - **case** - pattern matching against a subject value
  - **with** - chained pattern matching operations
  - **receive** - message pattern matching from process mailbox

  ## Case Expressions

  Case expressions match a subject against multiple patterns:

      case value do
        {:ok, result} -> result
        {:error, reason} -> handle_error(reason)
        _ -> :default
      end

  ## With Expressions

  With expressions chain pattern matching operations:

      with {:ok, a} <- get_a(),
           {:ok, b} <- get_b(a) do
        {:ok, a + b}
      else
        {:error, reason} -> {:error, reason}
      end

  ## Receive Expressions

  Receive expressions wait for messages from the process mailbox:

      receive do
        {:msg, data} -> handle(data)
        :ping -> :pong
      after
        5000 -> :timeout
      end

  ## Examples

      iex> ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}
      iex> ElixirOntologies.Extractors.CaseWith.case_expression?(ast)
      true

      iex> ast = {:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.CaseWith.with_expression?(ast)
      true

      iex> ast = {:receive, [], [[do: [{:->, [], [[:ping], :pong]}]]]}
      iex> ElixirOntologies.Extractors.CaseWith.receive_expression?(ast)
      true
  """

  alias ElixirOntologies.Extractors.Helpers
  alias ElixirOntologies.Analyzer.Location.SourceLocation

  # ===========================================================================
  # Struct Definitions
  # ===========================================================================

  defmodule CaseClause do
    @moduledoc """
    Represents a clause in a case expression.

    ## Fields

    - `:index` - 0-based position in the case
    - `:pattern` - The pattern to match against
    - `:guard` - Guard expression if present
    - `:body` - The clause body
    - `:has_guard` - Whether the clause has a guard
    - `:location` - Source location if available
    """

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            pattern: Macro.t(),
            guard: Macro.t() | nil,
            body: Macro.t(),
            has_guard: boolean(),
            location: SourceLocation.t() | nil
          }

    @enforce_keys [:index, :pattern, :body]
    defstruct [:index, :pattern, :guard, :body, has_guard: false, location: nil]
  end

  defmodule CaseExpression do
    @moduledoc """
    Represents a case expression extracted from AST.

    ## Fields

    - `:subject` - The expression being matched against
    - `:clauses` - List of CaseClause structs
    - `:location` - Source location if available
    - `:metadata` - Additional information
    """

    @type t :: %__MODULE__{
            subject: Macro.t(),
            clauses: [ElixirOntologies.Extractors.CaseWith.CaseClause.t()],
            location: SourceLocation.t() | nil,
            metadata: map()
          }

    @enforce_keys [:subject]
    defstruct [:subject, :location, clauses: [], metadata: %{}]
  end

  defmodule WithClause do
    @moduledoc """
    Represents a clause in a with expression.

    ## Fields

    - `:index` - 0-based position in the with
    - `:type` - Clause type (:match for `<-`, :bare_match for `=`)
    - `:pattern` - The pattern to match
    - `:expression` - The expression being matched
    - `:location` - Source location if available
    """

    @type clause_type :: :match | :bare_match

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            type: clause_type(),
            pattern: Macro.t(),
            expression: Macro.t(),
            location: SourceLocation.t() | nil
          }

    @enforce_keys [:index, :type, :pattern, :expression]
    defstruct [:index, :type, :pattern, :expression, :location]
  end

  defmodule WithExpression do
    @moduledoc """
    Represents a with expression extracted from AST.

    ## Fields

    - `:clauses` - List of WithClause structs
    - `:body` - The do block body
    - `:else_clauses` - List of else clauses (as CaseClause)
    - `:has_else` - Whether the with has an else block
    - `:location` - Source location if available
    - `:metadata` - Additional information
    """

    @type t :: %__MODULE__{
            clauses: [ElixirOntologies.Extractors.CaseWith.WithClause.t()],
            body: Macro.t(),
            else_clauses: [ElixirOntologies.Extractors.CaseWith.CaseClause.t()],
            has_else: boolean(),
            location: SourceLocation.t() | nil,
            metadata: map()
          }

    @enforce_keys [:clauses, :body]
    defstruct [:clauses, :body, :location, else_clauses: [], has_else: false, metadata: %{}]
  end

  defmodule AfterClause do
    @moduledoc """
    Represents an after clause in a receive expression.

    ## Fields

    - `:timeout` - The timeout expression (usually an integer)
    - `:body` - The body to execute on timeout
    - `:is_immediate` - True if timeout is literal 0
    - `:location` - Source location if available
    """

    @type t :: %__MODULE__{
            timeout: Macro.t(),
            body: Macro.t(),
            is_immediate: boolean(),
            location: SourceLocation.t() | nil
          }

    @enforce_keys [:timeout, :body]
    defstruct [:timeout, :body, :location, is_immediate: false]
  end

  defmodule ReceiveExpression do
    @moduledoc """
    Represents a receive expression extracted from AST.

    ## Fields

    - `:clauses` - List of message pattern clauses (as CaseClause)
    - `:after_clause` - The after timeout clause if present
    - `:has_after` - Whether the receive has an after block
    - `:location` - Source location if available
    - `:metadata` - Additional information (is_blocking, clause_count)
    """

    @type t :: %__MODULE__{
            clauses: [ElixirOntologies.Extractors.CaseWith.CaseClause.t()],
            after_clause: ElixirOntologies.Extractors.CaseWith.AfterClause.t() | nil,
            has_after: boolean(),
            location: SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct [:after_clause, :location, clauses: [], has_after: false, metadata: %{}]
  end

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if the given AST node represents a case expression.

  ## Examples

      iex> ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}
      iex> ElixirOntologies.Extractors.CaseWith.case_expression?(ast)
      true

      iex> ast = {:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.CaseWith.case_expression?(ast)
      false

      iex> ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.CaseWith.case_expression?(ast)
      false
  """
  @spec case_expression?(Macro.t()) :: boolean()
  def case_expression?({:case, _meta, [_subject, opts]}) when is_list(opts), do: true
  def case_expression?(_), do: false

  @doc """
  Checks if the given AST node represents a with expression.

  ## Examples

      iex> ast = {:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.CaseWith.with_expression?(ast)
      true

      iex> ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}
      iex> ElixirOntologies.Extractors.CaseWith.with_expression?(ast)
      false

      iex> ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.CaseWith.with_expression?(ast)
      false
  """
  @spec with_expression?(Macro.t()) :: boolean()
  def with_expression?({:with, _meta, [_ | _]}), do: true
  def with_expression?(_), do: false

  @doc """
  Checks if the given AST node represents a receive expression.

  ## Examples

      iex> ast = {:receive, [], [[do: [{:->, [], [[:ping], :pong]}]]]}
      iex> ElixirOntologies.Extractors.CaseWith.receive_expression?(ast)
      true

      iex> ast = {:receive, [], [[do: [], after: [{:->, [], [[0], :timeout]}]]]}
      iex> ElixirOntologies.Extractors.CaseWith.receive_expression?(ast)
      true

      iex> ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}
      iex> ElixirOntologies.Extractors.CaseWith.receive_expression?(ast)
      false
  """
  @spec receive_expression?(Macro.t()) :: boolean()
  def receive_expression?({:receive, _meta, [opts]}) when is_list(opts), do: true
  def receive_expression?(_), do: false

  # ===========================================================================
  # Case Extraction
  # ===========================================================================

  @doc """
  Extracts a case expression from an AST node.

  Returns `{:ok, %CaseExpression{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}, {:->, [], [[:b], 2]}]]]}
      iex> {:ok, expr} = ElixirOntologies.Extractors.CaseWith.extract_case(ast)
      iex> expr.subject
      {:x, [], nil}
      iex> length(expr.clauses)
      2

      iex> ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[{:when, [], [{:n, [], nil}, {:>, [], [{:n, [], nil}, 0]}]}], :pos]}]]]}
      iex> {:ok, expr} = ElixirOntologies.Extractors.CaseWith.extract_case(ast)
      iex> hd(expr.clauses).has_guard
      true

      iex> ast = {:if, [], [{:x, [], nil}, [do: :ok]]}
      iex> ElixirOntologies.Extractors.CaseWith.extract_case(ast)
      {:error, {:not_a_case, "Not a case expression: {:if, [], [{:x, [], nil}, [do: :ok]]}"}}
  """
  @spec extract_case(Macro.t(), keyword()) :: {:ok, CaseExpression.t()} | {:error, term()}
  def extract_case(ast, opts \\ [])

  def extract_case({:case, _meta, [subject, body_opts]} = ast, opts) do
    do_clauses = Keyword.get(body_opts, :do, [])
    location = Helpers.extract_location_if(ast, opts)

    clauses = build_case_clauses(do_clauses, opts)

    {:ok,
     %CaseExpression{
       subject: subject,
       clauses: clauses,
       location: location,
       metadata: %{
         clause_count: length(clauses),
         has_guards: Enum.any?(clauses, & &1.has_guard)
       }
     }}
  end

  def extract_case(ast, _opts) do
    {:error, {:not_a_case, Helpers.format_error("Not a case expression", ast)}}
  end

  @doc """
  Extracts a case expression, raising on error.

  ## Examples

      iex> ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]}
      iex> expr = ElixirOntologies.Extractors.CaseWith.extract_case!(ast)
      iex> expr.subject
      {:x, [], nil}
  """
  @spec extract_case!(Macro.t(), keyword()) :: CaseExpression.t()
  def extract_case!(ast, opts \\ []) do
    case extract_case(ast, opts) do
      {:ok, expr} -> expr
      {:error, reason} -> raise ArgumentError, "Failed to extract case: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # With Extraction
  # ===========================================================================

  @doc """
  Extracts a with expression from an AST node.

  Returns `{:ok, %WithExpression{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:with, [], [{:<-, [], [{:ok, {:a, [], nil}}, {:get, [], []}]}, [do: {:a, [], nil}]]}
      iex> {:ok, expr} = ElixirOntologies.Extractors.CaseWith.extract_with(ast)
      iex> length(expr.clauses)
      1
      iex> hd(expr.clauses).type
      :match
      iex> expr.has_else
      false

      iex> ast = {:with, [], [
      ...>   {:<-, [], [:ok, {:validate, [], []}]},
      ...>   {:=, [], [{:user, [], nil}, {:fetch, [], []}]},
      ...>   [do: :ok]
      ...> ]}
      iex> {:ok, expr} = ElixirOntologies.Extractors.CaseWith.extract_with(ast)
      iex> length(expr.clauses)
      2
      iex> Enum.map(expr.clauses, & &1.type)
      [:match, :bare_match]

      iex> ast = {:case, [], [{:x, [], nil}, [do: []]]}
      iex> ElixirOntologies.Extractors.CaseWith.extract_with(ast)
      {:error, {:not_a_with, "Not a with expression: {:case, [], [{:x, [], nil}, [do: []]]}"}}
  """
  @spec extract_with(Macro.t(), keyword()) :: {:ok, WithExpression.t()} | {:error, term()}
  def extract_with(ast, opts \\ [])

  def extract_with({:with, _meta, [_ | _] = args} = ast, opts) do
    # Last element contains [do: body] or [do: body, else: else_clauses]
    {clause_args, [body_opts]} = Enum.split(args, -1)

    body = Keyword.get(body_opts, :do)
    else_clauses_ast = Keyword.get(body_opts, :else, [])

    location = Helpers.extract_location_if(ast, opts)

    clauses = build_with_clauses(clause_args, opts)
    else_clauses = build_case_clauses(else_clauses_ast, opts)

    {:ok,
     %WithExpression{
       clauses: clauses,
       body: body,
       else_clauses: else_clauses,
       has_else: else_clauses_ast != [],
       location: location,
       metadata: %{
         clause_count: length(clauses),
         else_clause_count: length(else_clauses),
         has_bare_match: Enum.any?(clauses, &(&1.type == :bare_match))
       }
     }}
  end

  def extract_with(ast, _opts) do
    {:error, {:not_a_with, Helpers.format_error("Not a with expression", ast)}}
  end

  @doc """
  Extracts a with expression, raising on error.

  ## Examples

      iex> ast = {:with, [], [{:<-, [], [:ok, {:get, [], []}]}, [do: :ok]]}
      iex> expr = ElixirOntologies.Extractors.CaseWith.extract_with!(ast)
      iex> length(expr.clauses)
      1
  """
  @spec extract_with!(Macro.t(), keyword()) :: WithExpression.t()
  def extract_with!(ast, opts \\ []) do
    case extract_with(ast, opts) do
      {:ok, expr} -> expr
      {:error, reason} -> raise ArgumentError, "Failed to extract with: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Bulk Extraction
  # ===========================================================================

  @doc """
  Extracts all case expressions from an AST.

  Walks the entire AST tree and extracts all case expressions.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)
  - `:max_depth` - Maximum recursion depth (default: 100)

  ## Examples

      iex> body = [
      ...>   {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:a], 1]}]]]},
      ...>   {:foo, [], []},
      ...>   {:case, [], [{:y, [], nil}, [do: [{:->, [], [[:b], 2]}]]]}
      ...> ]
      iex> exprs = ElixirOntologies.Extractors.CaseWith.extract_case_expressions(body)
      iex> length(exprs)
      2

      iex> ast = {:def, [], [{:run, [], nil}, [do: {:case, [], [{:x, [], nil}, [do: []]]}]]}
      iex> exprs = ElixirOntologies.Extractors.CaseWith.extract_case_expressions(ast)
      iex> length(exprs)
      1
  """
  @spec extract_case_expressions(Macro.t(), keyword()) :: [CaseExpression.t()]
  def extract_case_expressions(ast, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, Helpers.max_recursion_depth())
    extract_expressions_recursive(ast, :case, opts, 0, max_depth)
  end

  @doc """
  Extracts all with expressions from an AST.

  Walks the entire AST tree and extracts all with expressions.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)
  - `:max_depth` - Maximum recursion depth (default: 100)

  ## Examples

      iex> body = [
      ...>   {:with, [], [{:<-, [], [:ok, {:a, [], []}]}, [do: :ok]]},
      ...>   {:foo, [], []},
      ...>   {:with, [], [{:<-, [], [:ok, {:b, [], []}]}, [do: :ok]]}
      ...> ]
      iex> exprs = ElixirOntologies.Extractors.CaseWith.extract_with_expressions(body)
      iex> length(exprs)
      2
  """
  @spec extract_with_expressions(Macro.t(), keyword()) :: [WithExpression.t()]
  def extract_with_expressions(ast, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, Helpers.max_recursion_depth())
    extract_expressions_recursive(ast, :with, opts, 0, max_depth)
  end

  # ===========================================================================
  # Receive Extraction
  # ===========================================================================

  @doc """
  Extracts a receive expression from an AST node.

  Returns `{:ok, %ReceiveExpression{}}` on success, `{:error, reason}` on failure.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)

  ## Examples

      iex> ast = {:receive, [], [[do: [{:->, [], [[:ping], :pong]}]]]}
      iex> {:ok, expr} = ElixirOntologies.Extractors.CaseWith.extract_receive(ast)
      iex> length(expr.clauses)
      1
      iex> expr.has_after
      false

      iex> ast = {:receive, [], [[do: [{:->, [], [[:msg], :ok]}], after: [{:->, [], [[5000], :timeout]}]]]}
      iex> {:ok, expr} = ElixirOntologies.Extractors.CaseWith.extract_receive(ast)
      iex> expr.has_after
      true
      iex> expr.after_clause.timeout
      5000

      iex> ast = {:case, [], [{:x, [], nil}, [do: []]]}
      iex> ElixirOntologies.Extractors.CaseWith.extract_receive(ast)
      {:error, {:not_a_receive, "Not a receive expression: {:case, [], [{:x, [], nil}, [do: []]]}"}}
  """
  @spec extract_receive(Macro.t(), keyword()) :: {:ok, ReceiveExpression.t()} | {:error, term()}
  def extract_receive(ast, opts \\ [])

  def extract_receive({:receive, _meta, [body_opts]} = ast, opts) do
    do_clauses = get_receive_clauses(Keyword.get(body_opts, :do, []))
    after_clauses = Keyword.get(body_opts, :after, [])
    location = Helpers.extract_location_if(ast, opts)

    clauses = build_case_clauses(do_clauses, opts)
    after_clause = build_after_clause(after_clauses, opts)

    has_after = after_clause != nil
    is_blocking = !has_after || (after_clause && !after_clause.is_immediate)

    {:ok,
     %ReceiveExpression{
       clauses: clauses,
       after_clause: after_clause,
       has_after: has_after,
       location: location,
       metadata: %{
         clause_count: length(clauses),
         is_blocking: is_blocking,
         has_immediate_timeout: after_clause != nil && after_clause.is_immediate
       }
     }}
  end

  def extract_receive(ast, _opts) do
    {:error, {:not_a_receive, Helpers.format_error("Not a receive expression", ast)}}
  end

  @doc """
  Extracts a receive expression, raising on error.

  ## Examples

      iex> ast = {:receive, [], [[do: [{:->, [], [[:ping], :pong]}]]]}
      iex> expr = ElixirOntologies.Extractors.CaseWith.extract_receive!(ast)
      iex> length(expr.clauses)
      1
  """
  @spec extract_receive!(Macro.t(), keyword()) :: ReceiveExpression.t()
  def extract_receive!(ast, opts \\ []) do
    case extract_receive(ast, opts) do
      {:ok, expr} -> expr
      {:error, reason} -> raise ArgumentError, "Failed to extract receive: #{inspect(reason)}"
    end
  end

  @doc """
  Extracts all receive expressions from an AST.

  Walks the entire AST tree and extracts all receive expressions.

  ## Options

  - `:include_location` - Whether to extract source location (default: true)
  - `:max_depth` - Maximum recursion depth (default: 100)

  ## Examples

      iex> body = [
      ...>   {:receive, [], [[do: [{:->, [], [[:a], 1]}]]]},
      ...>   {:foo, [], []},
      ...>   {:receive, [], [[do: [{:->, [], [[:b], 2]}]]]}
      ...> ]
      iex> exprs = ElixirOntologies.Extractors.CaseWith.extract_receive_expressions(body)
      iex> length(exprs)
      2
  """
  @spec extract_receive_expressions(Macro.t(), keyword()) :: [ReceiveExpression.t()]
  def extract_receive_expressions(ast, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, Helpers.max_recursion_depth())
    extract_expressions_recursive(ast, :receive, opts, 0, max_depth)
  end

  # ===========================================================================
  # Private Functions - Case Clause Building
  # ===========================================================================

  defp build_case_clauses(clauses, opts) when is_list(clauses) do
    clauses
    |> Enum.with_index()
    |> Enum.map(fn {clause_ast, index} ->
      build_case_clause(clause_ast, index, opts)
    end)
  end

  defp build_case_clause({:->, _meta, [[pattern_with_guard], body]} = ast, index, opts) do
    {pattern, guard, has_guard} = extract_pattern_and_guard(pattern_with_guard)
    location = Helpers.extract_location_if(ast, opts)

    %CaseClause{
      index: index,
      pattern: pattern,
      guard: guard,
      body: body,
      has_guard: has_guard,
      location: location
    }
  end

  defp build_case_clause(malformed, index, _opts) do
    %CaseClause{
      index: index,
      pattern: malformed,
      guard: nil,
      body: nil,
      has_guard: false,
      location: nil
    }
  end

  defp extract_pattern_and_guard({:when, _meta, [pattern, guard]}) do
    {pattern, guard, true}
  end

  defp extract_pattern_and_guard(pattern) do
    {pattern, nil, false}
  end

  # ===========================================================================
  # Private Functions - With Clause Building
  # ===========================================================================

  defp build_with_clauses(clause_args, opts) do
    clause_args
    |> Enum.with_index()
    |> Enum.map(fn {clause_ast, index} ->
      build_with_clause(clause_ast, index, opts)
    end)
  end

  defp build_with_clause({:<-, _meta, [pattern, expression]} = ast, index, opts) do
    location = Helpers.extract_location_if(ast, opts)

    %WithClause{
      index: index,
      type: :match,
      pattern: pattern,
      expression: expression,
      location: location
    }
  end

  defp build_with_clause({:=, _meta, [pattern, expression]} = ast, index, opts) do
    location = Helpers.extract_location_if(ast, opts)

    %WithClause{
      index: index,
      type: :bare_match,
      pattern: pattern,
      expression: expression,
      location: location
    }
  end

  defp build_with_clause(other, index, _opts) do
    # Handle other expressions that might appear in with
    %WithClause{
      index: index,
      type: :match,
      pattern: other,
      expression: other,
      location: nil
    }
  end

  # ===========================================================================
  # Private Functions - Receive Clause Building
  # ===========================================================================

  # Handle empty do block (receive do after 0 -> ... end)
  defp get_receive_clauses({:__block__, _, []}), do: []
  defp get_receive_clauses(clauses) when is_list(clauses), do: clauses
  defp get_receive_clauses(_), do: []

  defp build_after_clause([], _opts), do: nil

  defp build_after_clause([{:->, _meta, [[timeout], body]} = ast], opts) do
    location = Helpers.extract_location_if(ast, opts)
    is_immediate = timeout == 0

    %AfterClause{
      timeout: timeout,
      body: body,
      is_immediate: is_immediate,
      location: location
    }
  end

  defp build_after_clause(_, _opts), do: nil

  # ===========================================================================
  # Private Functions - Recursive Extraction
  # ===========================================================================

  defp extract_expressions_recursive(_ast, _type, _opts, depth, max_depth)
       when depth > max_depth do
    []
  end

  defp extract_expressions_recursive(statements, type, opts, depth, max_depth)
       when is_list(statements) do
    Enum.flat_map(statements, &extract_expressions_recursive(&1, type, opts, depth, max_depth))
  end

  defp extract_expressions_recursive({:__block__, _meta, statements}, type, opts, depth, max) do
    extract_expressions_recursive(statements, type, opts, depth, max)
  end

  # Handle case expression
  defp extract_expressions_recursive(
         {:case, _meta, [_subject, body_opts]} = ast,
         type,
         opts,
         depth,
         max
       ) do
    result =
      if type == :case do
        case extract_case(ast, opts) do
          {:ok, expr} -> [expr]
          {:error, _} -> []
        end
      else
        []
      end

    # Also search in clause bodies
    do_clauses = Keyword.get(body_opts, :do, [])
    nested = extract_from_case_clauses(do_clauses, type, opts, depth + 1, max)

    result ++ nested
  end

  # Handle with expression
  defp extract_expressions_recursive({:with, _meta, [_ | _] = args} = ast, type, opts, depth, max) do
    result =
      if type == :with do
        case extract_with(ast, opts) do
          {:ok, expr} -> [expr]
          {:error, _} -> []
        end
      else
        []
      end

    # Also search in body and else clauses
    {_clause_args, [body_opts]} = Enum.split(args, -1)
    body = Keyword.get(body_opts, :do)
    else_clauses = Keyword.get(body_opts, :else, [])

    nested_body = extract_expressions_recursive(body, type, opts, depth + 1, max)
    nested_else = extract_from_case_clauses(else_clauses, type, opts, depth + 1, max)

    result ++ nested_body ++ nested_else
  end

  # Handle receive expression
  defp extract_expressions_recursive({:receive, _meta, [body_opts]} = ast, type, opts, depth, max) do
    result =
      if type == :receive do
        case extract_receive(ast, opts) do
          {:ok, expr} -> [expr]
          {:error, _} -> []
        end
      else
        []
      end

    # Also search in clause bodies
    do_clauses = get_receive_clauses(Keyword.get(body_opts, :do, []))
    after_clauses = Keyword.get(body_opts, :after, [])

    nested_do = extract_from_case_clauses(do_clauses, type, opts, depth + 1, max)
    nested_after = extract_from_case_clauses(after_clauses, type, opts, depth + 1, max)

    result ++ nested_do ++ nested_after
  end

  # Handle other AST nodes - recurse into args
  defp extract_expressions_recursive({_name, _meta, args}, type, opts, depth, max)
       when is_list(args) do
    extract_expressions_recursive(args, type, opts, depth + 1, max)
  end

  # Handle two-element tuples
  defp extract_expressions_recursive({left, right}, type, opts, depth, max) do
    extract_expressions_recursive(left, type, opts, depth + 1, max) ++
      extract_expressions_recursive(right, type, opts, depth + 1, max)
  end

  # Handle three-element tuples that aren't AST nodes
  defp extract_expressions_recursive({a, b, c}, type, opts, depth, max)
       when not is_atom(a) or not is_list(b) do
    extract_expressions_recursive(a, type, opts, depth + 1, max) ++
      extract_expressions_recursive(b, type, opts, depth + 1, max) ++
      extract_expressions_recursive(c, type, opts, depth + 1, max)
  end

  defp extract_expressions_recursive(_other, _type, _opts, _depth, _max) do
    []
  end

  # Extract from case clause bodies
  defp extract_from_case_clauses(clauses, type, opts, depth, max) when is_list(clauses) do
    Enum.flat_map(clauses, fn
      {:->, _, [[_pattern], body]} ->
        extract_expressions_recursive(body, type, opts, depth, max)

      _ ->
        []
    end)
  end
end
