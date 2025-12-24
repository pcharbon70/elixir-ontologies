defmodule ElixirOntologies.Extractors.Exception do
  @moduledoc """
  Extracts exception handling constructs from AST nodes.

  This module analyzes Elixir AST nodes representing `try` expressions and
  extracts their body, rescue clauses, catch clauses, else clauses, and after
  blocks. Supports all exception handling features in Elixir:

  - Try body: The expression that may raise an exception
  - Rescue clauses: Handle exceptions by type with optional variable binding
  - Catch clauses: Handle throw/exit/error with kind and pattern
  - Else clauses: Handle successful try results with pattern matching
  - After blocks: Cleanup code that always executes

  ## Usage

      iex> alias ElixirOntologies.Extractors.Exception
      iex> ast = {:try, [], [[do: {:risky, [], nil}, rescue: [{:->, [], [[{:e, [], nil}], {:e, [], nil}]}]]]}
      iex> {:ok, result} = Exception.extract_try(ast)
      iex> result.has_rescue
      true
      iex> length(result.rescue_clauses)
      1
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Nested Structs
  # ===========================================================================

  defmodule RescueClause do
    @moduledoc """
    Represents a rescue clause in a try expression.

    A rescue clause handles exceptions, optionally filtering by exception type
    and binding the exception to a variable.
    """

    @typedoc """
    A rescue clause in a try expression.

    - `:exceptions` - List of exception types to catch, empty for catch-all
    - `:variable` - Variable bound to the exception, or nil
    - `:body` - The body expression to execute
    - `:is_catch_all` - True if no exception types specified
    - `:location` - Source location if available
    """
    @type t :: %__MODULE__{
            exceptions: [atom() | Macro.t()],
            variable: Macro.t() | nil,
            body: Macro.t(),
            is_catch_all: boolean(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
          }

    @enforce_keys [:body]
    defstruct [:variable, :body, :location, exceptions: [], is_catch_all: false]
  end

  defmodule CatchClause do
    @moduledoc """
    Represents a catch clause in a try expression.

    A catch clause handles throw, exit, or error signals with optional
    kind specification and pattern matching.
    """

    @typedoc """
    A catch clause in a try expression.

    - `:kind` - The signal kind (:throw, :exit, :error), or nil if not specified
    - `:pattern` - The pattern to match against the value
    - `:body` - The body expression to execute
    - `:location` - Source location if available
    """
    @type t :: %__MODULE__{
            kind: :throw | :exit | :error | nil,
            pattern: Macro.t(),
            body: Macro.t(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
          }

    @enforce_keys [:pattern, :body]
    defstruct [:kind, :pattern, :body, :location]
  end

  defmodule ElseClause do
    @moduledoc """
    Represents an else clause in a try expression.

    An else clause handles successful try results with pattern matching,
    similar to case clauses.
    """

    @typedoc """
    An else clause in a try expression.

    - `:pattern` - The pattern to match against the try result
    - `:guard` - Guard expression if present
    - `:body` - The body expression to execute
    - `:location` - Source location if available
    """
    @type t :: %__MODULE__{
            pattern: Macro.t(),
            guard: Macro.t() | nil,
            body: Macro.t(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
          }

    @enforce_keys [:pattern, :body]
    defstruct [:pattern, :guard, :body, :location]
  end

  defmodule RaiseExpression do
    @moduledoc """
    Represents a raise or reraise expression.

    A raise expression signals an exception, optionally specifying an
    exception module, message, and/or attributes.
    """

    @typedoc """
    A raise or reraise expression.

    - `:exception` - Exception module or struct, nil for message-only raise
    - `:message` - Message string or expression
    - `:attributes` - Keyword list of exception attributes
    - `:is_reraise` - True if this is a reraise
    - `:stacktrace` - Stacktrace expression for reraise
    - `:location` - Source location if available
    """
    @type t :: %__MODULE__{
            exception: atom() | Macro.t() | nil,
            message: String.t() | Macro.t() | nil,
            attributes: keyword() | nil,
            is_reraise: boolean(),
            stacktrace: Macro.t() | nil,
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
          }

    defstruct [:exception, :message, :attributes, :stacktrace, :location, is_reraise: false]
  end

  defmodule ThrowExpression do
    @moduledoc """
    Represents a throw expression.

    A throw expression throws a value that can be caught with a catch clause.
    """

    @typedoc """
    A throw expression.

    - `:value` - The thrown value
    - `:location` - Source location if available
    """
    @type t :: %__MODULE__{
            value: Macro.t(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
          }

    @enforce_keys [:value]
    defstruct [:value, :location]
  end

  defmodule ExitExpression do
    @moduledoc """
    Represents an exit expression.

    An exit expression terminates the current process with a reason.
    """

    @typedoc """
    An exit expression.

    - `:reason` - The exit reason
    - `:location` - Source location if available
    """
    @type t :: %__MODULE__{
            reason: Macro.t(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
          }

    @enforce_keys [:reason]
    defstruct [:reason, :location]
  end

  # ===========================================================================
  # Main Struct
  # ===========================================================================

  @typedoc """
  The result of try expression extraction.

  - `:body` - The try body expression
  - `:rescue_clauses` - List of rescue clauses
  - `:catch_clauses` - List of catch clauses
  - `:else_clauses` - List of else clauses
  - `:after_body` - After block expression, or nil
  - `:has_rescue` - True if rescue clauses present
  - `:has_catch` - True if catch clauses present
  - `:has_else` - True if else clauses present
  - `:has_after` - True if after block present
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          body: Macro.t(),
          rescue_clauses: [RescueClause.t()],
          catch_clauses: [CatchClause.t()],
          else_clauses: [ElseClause.t()],
          after_body: Macro.t() | nil,
          has_rescue: boolean(),
          has_catch: boolean(),
          has_else: boolean(),
          has_after: boolean(),
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  defstruct [
    :body,
    :after_body,
    :location,
    rescue_clauses: [],
    catch_clauses: [],
    else_clauses: [],
    has_rescue: false,
    has_catch: false,
    has_else: false,
    has_after: false,
    metadata: %{}
  ]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a try expression.

  ## Examples

      iex> ElixirOntologies.Extractors.Exception.try_expression?({:try, [], [[do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.Exception.try_expression?({:if, [], [true, [do: 1]]})
      false

      iex> ElixirOntologies.Extractors.Exception.try_expression?(:atom)
      false
  """
  @spec try_expression?(Macro.t()) :: boolean()
  def try_expression?({:try, _meta, [opts]}) when is_list(opts), do: true
  def try_expression?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a try expression from an AST node.

  Returns `{:ok, %Exception{}}` on success, or `{:error, reason}` if the
  node is not a try expression.

  ## Options

  - `:include_location` - When true, extracts source location (default: true)

  ## Examples

      iex> ast = {:try, [], [[do: {:risky, [], nil}, rescue: [{:->, [], [[{:e, [], nil}], :error]}]]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Exception.extract_try(ast)
      iex> result.has_rescue
      true

      iex> {:error, _} = ElixirOntologies.Extractors.Exception.extract_try({:if, [], [true]})
  """
  @spec extract_try(Macro.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def extract_try(node, opts \\ [])

  def extract_try({:try, _meta, [clauses]} = node, opts) when is_list(clauses) do
    body = Keyword.get(clauses, :do)
    rescue_clauses = extract_rescue_clauses(Keyword.get(clauses, :rescue, []), opts)
    catch_clauses = extract_catch_clauses(Keyword.get(clauses, :catch, []), opts)
    else_clauses = extract_else_clauses(Keyword.get(clauses, :else, []), opts)
    after_body = Keyword.get(clauses, :after)

    result = %__MODULE__{
      body: body,
      rescue_clauses: rescue_clauses,
      catch_clauses: catch_clauses,
      else_clauses: else_clauses,
      after_body: after_body,
      has_rescue: rescue_clauses != [],
      has_catch: catch_clauses != [],
      has_else: else_clauses != [],
      has_after: after_body != nil,
      location: Helpers.extract_location_if(node, opts),
      metadata: %{
        rescue_count: length(rescue_clauses),
        catch_count: length(catch_clauses),
        else_count: length(else_clauses),
        clause_types: build_clause_types(rescue_clauses, catch_clauses, else_clauses, after_body)
      }
    }

    {:ok, result}
  end

  def extract_try(node, _opts) do
    {:error, Helpers.format_error("Not a try expression", node)}
  end

  @doc """
  Extracts a try expression, raising on error.

  ## Examples

      iex> ast = {:try, [], [[do: {:ok, [], nil}, after: {:cleanup, [], nil}]]}
      iex> result = ElixirOntologies.Extractors.Exception.extract_try!(ast)
      iex> result.has_after
      true
  """
  @spec extract_try!(Macro.t(), keyword()) :: t()
  def extract_try!(node, opts \\ []) do
    case extract_try(node, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Extracts all try expressions from an AST.

  Walks the AST recursively to find all try expressions, including
  those nested within other expressions.

  ## Options

  - `:include_location` - When true, extracts source location (default: true)

  ## Examples

      iex> ast = quote do
      ...>   try do :a rescue _ -> :b end
      ...>   try do :c after :d end
      ...> end
      iex> tries = ElixirOntologies.Extractors.Exception.extract_try_expressions(ast)
      iex> length(tries)
      2
  """
  @spec extract_try_expressions(Macro.t(), keyword()) :: [t()]
  def extract_try_expressions(ast, opts \\ []) do
    {_ast, tries} =
      Macro.prewalk(ast, [], fn
        {:try, _meta, _args} = node, acc ->
          case extract_try(node, opts) do
            {:ok, try_expr} -> {node, [try_expr | acc]}
            {:error, _} -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(tries)
  end

  # ===========================================================================
  # Rescue Clause Extraction
  # ===========================================================================

  @doc """
  Extracts rescue clauses from a list of rescue clause AST nodes.

  ## Examples

      iex> clauses = [{:->, [], [[{:e, [], nil}], :error]}]
      iex> [clause] = ElixirOntologies.Extractors.Exception.extract_rescue_clauses(clauses)
      iex> clause.is_catch_all
      true
  """
  @spec extract_rescue_clauses([Macro.t()], keyword()) :: [RescueClause.t()]
  def extract_rescue_clauses(clauses, opts \\ [])
  def extract_rescue_clauses(nil, _opts), do: []
  def extract_rescue_clauses([], _opts), do: []

  def extract_rescue_clauses(clauses, opts) when is_list(clauses) do
    Enum.map(clauses, &extract_single_rescue_clause(&1, opts))
  end

  defp extract_single_rescue_clause({:->, _meta, [[pattern], body]} = node, opts) do
    {exceptions, variable, is_catch_all} = parse_rescue_pattern(pattern)

    %RescueClause{
      exceptions: exceptions,
      variable: variable,
      body: body,
      is_catch_all: is_catch_all,
      location: Helpers.extract_location_if(node, opts)
    }
  end

  # Parse rescue pattern to extract exception types and variable
  defp parse_rescue_pattern({:in, _meta, [variable, exception_types]}) do
    exceptions = normalize_exception_types(exception_types)
    {exceptions, variable, false}
  end

  defp parse_rescue_pattern({:__aliases__, _meta, _parts} = exception_type) do
    {[exception_type], nil, false}
  end

  defp parse_rescue_pattern({:_, _meta, _context}) do
    {[], nil, true}
  end

  defp parse_rescue_pattern(variable) when is_tuple(variable) do
    # Bare variable like {:e, [], nil} - catch-all with variable binding
    {[], variable, true}
  end

  defp parse_rescue_pattern(_pattern) do
    {[], nil, true}
  end

  # Normalize exception types to a list
  defp normalize_exception_types(types) when is_list(types), do: types
  defp normalize_exception_types(type), do: [type]

  # ===========================================================================
  # Catch Clause Extraction
  # ===========================================================================

  @doc """
  Extracts catch clauses from a list of catch clause AST nodes.

  ## Examples

      iex> clauses = [{:->, [], [[:throw, {:value, [], nil}], {:value, [], nil}]}]
      iex> [catch_clause] = ElixirOntologies.Extractors.Exception.extract_catch_clauses(clauses)
      iex> catch_clause.kind
      :throw
  """
  @spec extract_catch_clauses([Macro.t()], keyword()) :: [CatchClause.t()]
  def extract_catch_clauses(clauses, opts \\ [])
  def extract_catch_clauses(nil, _opts), do: []
  def extract_catch_clauses([], _opts), do: []

  def extract_catch_clauses(clauses, opts) when is_list(clauses) do
    Enum.map(clauses, &extract_single_catch_clause(&1, opts))
  end

  defp extract_single_catch_clause({:->, _meta, [[kind, pattern], body]} = node, opts)
       when kind in [:throw, :exit, :error] do
    %CatchClause{
      kind: kind,
      pattern: pattern,
      body: body,
      location: Helpers.extract_location_if(node, opts)
    }
  end

  defp extract_single_catch_clause({:->, _meta, [[pattern], body]} = node, opts) do
    # Catch without explicit kind - defaults to catching throws
    %CatchClause{
      kind: nil,
      pattern: pattern,
      body: body,
      location: Helpers.extract_location_if(node, opts)
    }
  end

  # ===========================================================================
  # Else Clause Extraction
  # ===========================================================================

  @doc """
  Extracts else clauses from a list of else clause AST nodes.

  ## Examples

      iex> clauses = [{:->, [], [[{:ok, {:v, [], nil}}], {:v, [], nil}]}]
      iex> [else_clause] = ElixirOntologies.Extractors.Exception.extract_else_clauses(clauses)
      iex> {:ok, _} = else_clause.pattern
  """
  @spec extract_else_clauses([Macro.t()], keyword()) :: [ElseClause.t()]
  def extract_else_clauses(clauses, opts \\ [])
  def extract_else_clauses(nil, _opts), do: []
  def extract_else_clauses([], _opts), do: []

  def extract_else_clauses(clauses, opts) when is_list(clauses) do
    Enum.map(clauses, &extract_single_else_clause(&1, opts))
  end

  defp extract_single_else_clause(
         {:->, _meta, [[{:when, _, [pattern, guard]}], body]} = node,
         opts
       ) do
    %ElseClause{
      pattern: pattern,
      guard: guard,
      body: body,
      location: Helpers.extract_location_if(node, opts)
    }
  end

  defp extract_single_else_clause({:->, _meta, [[pattern], body]} = node, opts) do
    %ElseClause{
      pattern: pattern,
      guard: nil,
      body: body,
      location: Helpers.extract_location_if(node, opts)
    }
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Returns true if the try expression has any rescue clauses.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Exception
      iex> try_expr = %Exception{body: :ok, has_rescue: true}
      iex> Exception.has_rescue?(try_expr)
      true
  """
  @spec has_rescue?(t()) :: boolean()
  def has_rescue?(%__MODULE__{has_rescue: has_rescue}), do: has_rescue
  def has_rescue?(_), do: false

  @doc """
  Returns true if the try expression has any catch clauses.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Exception
      iex> try_expr = %Exception{body: :ok, has_catch: true}
      iex> Exception.has_catch?(try_expr)
      true
  """
  @spec has_catch?(t()) :: boolean()
  def has_catch?(%__MODULE__{has_catch: has_catch}), do: has_catch
  def has_catch?(_), do: false

  @doc """
  Returns true if the try expression has any else clauses.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Exception
      iex> try_expr = %Exception{body: :ok, has_else: true}
      iex> Exception.has_else?(try_expr)
      true
  """
  @spec has_else?(t()) :: boolean()
  def has_else?(%__MODULE__{has_else: has_else}), do: has_else
  def has_else?(_), do: false

  @doc """
  Returns true if the try expression has an after block.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Exception
      iex> try_expr = %Exception{body: :ok, has_after: true, after_body: {:cleanup, [], nil}}
      iex> Exception.has_after?(try_expr)
      true
  """
  @spec has_after?(t()) :: boolean()
  def has_after?(%__MODULE__{has_after: has_after}), do: has_after
  def has_after?(_), do: false

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp build_clause_types(rescue_clauses, catch_clauses, else_clauses, after_body) do
    []
    |> maybe_add(:rescue, rescue_clauses != [])
    |> maybe_add(:catch, catch_clauses != [])
    |> maybe_add(:else, else_clauses != [])
    |> maybe_add(:after, after_body != nil)
  end

  defp maybe_add(list, type, true), do: [type | list]
  defp maybe_add(list, _type, false), do: list

  # ===========================================================================
  # Raise/Reraise Extraction
  # ===========================================================================

  @doc """
  Checks if an AST node represents a raise or reraise expression.

  ## Examples

      iex> ElixirOntologies.Extractors.Exception.raise_expression?({:raise, [], ["error"]})
      true

      iex> ElixirOntologies.Extractors.Exception.raise_expression?({:reraise, [], [:e, :stack]})
      true

      iex> ElixirOntologies.Extractors.Exception.raise_expression?({:throw, [], [:value]})
      false
  """
  @spec raise_expression?(Macro.t()) :: boolean()
  def raise_expression?({:raise, _meta, args}) when is_list(args), do: true
  def raise_expression?({:reraise, _meta, args}) when is_list(args), do: true
  def raise_expression?(_), do: false

  @doc """
  Extracts a raise or reraise expression from an AST node.

  Returns `{:ok, %RaiseExpression{}}` on success, or `{:error, reason}` if the
  node is not a raise/reraise expression.

  ## Options

  - `:include_location` - When true, extracts source location (default: true)

  ## Examples

      iex> ast = {:raise, [], ["error message"]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Exception.extract_raise(ast)
      iex> result.message
      "error message"

      iex> {:error, _} = ElixirOntologies.Extractors.Exception.extract_raise({:throw, [], [:value]})
  """
  @spec extract_raise(Macro.t(), keyword()) :: {:ok, RaiseExpression.t()} | {:error, String.t()}
  def extract_raise(node, opts \\ [])

  # Reraise with exception and stacktrace
  def extract_raise({:reraise, _meta, [exception, stacktrace]} = node, opts) do
    {exc_module, message, attrs} = parse_raise_exception(exception)

    result = %RaiseExpression{
      exception: exc_module,
      message: message,
      attributes: attrs,
      is_reraise: true,
      stacktrace: stacktrace,
      location: Helpers.extract_location_if(node, opts)
    }

    {:ok, result}
  end

  # Raise with message only
  def extract_raise({:raise, _meta, [message]} = node, opts) when is_binary(message) do
    result = %RaiseExpression{
      exception: nil,
      message: message,
      attributes: nil,
      is_reraise: false,
      stacktrace: nil,
      location: Helpers.extract_location_if(node, opts)
    }

    {:ok, result}
  end

  # Raise with exception module only
  def extract_raise({:raise, _meta, [{:__aliases__, _, _} = exception]} = node, opts) do
    result = %RaiseExpression{
      exception: exception,
      message: nil,
      attributes: nil,
      is_reraise: false,
      stacktrace: nil,
      location: Helpers.extract_location_if(node, opts)
    }

    {:ok, result}
  end

  # Raise with exception struct
  def extract_raise({:raise, _meta, [{:%, _, _} = struct_ast]} = node, opts) do
    result = %RaiseExpression{
      exception: struct_ast,
      message: nil,
      attributes: nil,
      is_reraise: false,
      stacktrace: nil,
      location: Helpers.extract_location_if(node, opts)
    }

    {:ok, result}
  end

  # Raise with exception module and message string
  def extract_raise({:raise, _meta, [exception, message]} = node, opts) when is_binary(message) do
    result = %RaiseExpression{
      exception: exception,
      message: message,
      attributes: nil,
      is_reraise: false,
      stacktrace: nil,
      location: Helpers.extract_location_if(node, opts)
    }

    {:ok, result}
  end

  # Raise with exception module and keyword opts
  def extract_raise({:raise, _meta, [exception, attrs]} = node, opts) when is_list(attrs) do
    message = Keyword.get(attrs, :message)

    result = %RaiseExpression{
      exception: exception,
      message: message,
      attributes: attrs,
      is_reraise: false,
      stacktrace: nil,
      location: Helpers.extract_location_if(node, opts)
    }

    {:ok, result}
  end

  # Raise with expression as message (variable or function call)
  def extract_raise({:raise, _meta, [message_expr]} = node, opts) do
    result = %RaiseExpression{
      exception: nil,
      message: message_expr,
      attributes: nil,
      is_reraise: false,
      stacktrace: nil,
      location: Helpers.extract_location_if(node, opts)
    }

    {:ok, result}
  end

  # Raise with exception and expression (e.g., variable)
  def extract_raise({:raise, _meta, [exception, message_expr]} = node, opts) do
    result = %RaiseExpression{
      exception: exception,
      message: message_expr,
      attributes: nil,
      is_reraise: false,
      stacktrace: nil,
      location: Helpers.extract_location_if(node, opts)
    }

    {:ok, result}
  end

  def extract_raise(node, _opts) do
    {:error, Helpers.format_error("Not a raise/reraise expression", node)}
  end

  @doc """
  Extracts a raise expression, raising on error.

  ## Examples

      iex> ast = {:raise, [], ["error"]}
      iex> result = ElixirOntologies.Extractors.Exception.extract_raise!(ast)
      iex> result.message
      "error"
  """
  @spec extract_raise!(Macro.t(), keyword()) :: RaiseExpression.t()
  def extract_raise!(node, opts \\ []) do
    case extract_raise(node, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Extracts all raise/reraise expressions from an AST.

  ## Examples

      iex> ast = quote do
      ...>   raise "error1"
      ...>   raise "error2"
      ...> end
      iex> raises = ElixirOntologies.Extractors.Exception.extract_raises(ast)
      iex> length(raises)
      2
  """
  @spec extract_raises(Macro.t(), keyword()) :: [RaiseExpression.t()]
  def extract_raises(ast, opts \\ []) do
    {_ast, raises} =
      Macro.prewalk(ast, [], fn
        {:raise, _meta, _args} = node, acc ->
          case extract_raise(node, opts) do
            {:ok, raise_expr} -> {node, [raise_expr | acc]}
            {:error, _} -> {node, acc}
          end

        {:reraise, _meta, _args} = node, acc ->
          case extract_raise(node, opts) do
            {:ok, raise_expr} -> {node, [raise_expr | acc]}
            {:error, _} -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(raises)
  end

  # Parse the exception argument to extract module, message, and attributes
  defp parse_raise_exception(exception) when is_binary(exception) do
    {nil, exception, nil}
  end

  defp parse_raise_exception({:__aliases__, _, _} = module) do
    {module, nil, nil}
  end

  defp parse_raise_exception({:%, _, [module, {:%{}, _, attrs}]}) do
    message = Keyword.get(attrs, :message)
    {module, message, attrs}
  end

  defp parse_raise_exception(other) do
    # Could be a variable or expression holding an exception
    {other, nil, nil}
  end

  # ===========================================================================
  # Throw Extraction
  # ===========================================================================

  @doc """
  Checks if an AST node represents a throw expression.

  ## Examples

      iex> ElixirOntologies.Extractors.Exception.throw_expression?({:throw, [], [:value]})
      true

      iex> ElixirOntologies.Extractors.Exception.throw_expression?({:raise, [], ["error"]})
      false
  """
  @spec throw_expression?(Macro.t()) :: boolean()
  def throw_expression?({:throw, _meta, args}) when is_list(args), do: true
  def throw_expression?(_), do: false

  @doc """
  Extracts a throw expression from an AST node.

  Returns `{:ok, %ThrowExpression{}}` on success, or `{:error, reason}` if the
  node is not a throw expression.

  ## Options

  - `:include_location` - When true, extracts source location (default: true)

  ## Examples

      iex> ast = {:throw, [], [:value]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Exception.extract_throw(ast)
      iex> result.value
      :value

      iex> {:error, _} = ElixirOntologies.Extractors.Exception.extract_throw({:raise, [], ["error"]})
  """
  @spec extract_throw(Macro.t(), keyword()) :: {:ok, ThrowExpression.t()} | {:error, String.t()}
  def extract_throw(node, opts \\ [])

  def extract_throw({:throw, _meta, [value]} = node, opts) do
    result = %ThrowExpression{
      value: value,
      location: Helpers.extract_location_if(node, opts)
    }

    {:ok, result}
  end

  def extract_throw(node, _opts) do
    {:error, Helpers.format_error("Not a throw expression", node)}
  end

  @doc """
  Extracts a throw expression, raising on error.

  ## Examples

      iex> ast = {:throw, [], [:done]}
      iex> result = ElixirOntologies.Extractors.Exception.extract_throw!(ast)
      iex> result.value
      :done
  """
  @spec extract_throw!(Macro.t(), keyword()) :: ThrowExpression.t()
  def extract_throw!(node, opts \\ []) do
    case extract_throw(node, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Extracts all throw expressions from an AST.

  ## Examples

      iex> ast = quote do
      ...>   throw :a
      ...>   throw :b
      ...> end
      iex> throws = ElixirOntologies.Extractors.Exception.extract_throws(ast)
      iex> length(throws)
      2
  """
  @spec extract_throws(Macro.t(), keyword()) :: [ThrowExpression.t()]
  def extract_throws(ast, opts \\ []) do
    {_ast, throws} =
      Macro.prewalk(ast, [], fn
        {:throw, _meta, _args} = node, acc ->
          case extract_throw(node, opts) do
            {:ok, throw_expr} -> {node, [throw_expr | acc]}
            {:error, _} -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(throws)
  end

  # ===========================================================================
  # Exit Extraction
  # ===========================================================================

  @doc """
  Checks if an AST node represents an exit expression.

  ## Examples

      iex> ElixirOntologies.Extractors.Exception.exit_expression?({:exit, [], [:normal]})
      true

      iex> ElixirOntologies.Extractors.Exception.exit_expression?({:throw, [], [:value]})
      false
  """
  @spec exit_expression?(Macro.t()) :: boolean()
  def exit_expression?({:exit, _meta, args}) when is_list(args), do: true
  def exit_expression?(_), do: false

  @doc """
  Extracts an exit expression from an AST node.

  Returns `{:ok, %ExitExpression{}}` on success, or `{:error, reason}` if the
  node is not an exit expression.

  ## Options

  - `:include_location` - When true, extracts source location (default: true)

  ## Examples

      iex> ast = {:exit, [], [:normal]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Exception.extract_exit(ast)
      iex> result.reason
      :normal

      iex> {:error, _} = ElixirOntologies.Extractors.Exception.extract_exit({:throw, [], [:value]})
  """
  @spec extract_exit(Macro.t(), keyword()) :: {:ok, ExitExpression.t()} | {:error, String.t()}
  def extract_exit(node, opts \\ [])

  def extract_exit({:exit, _meta, [reason]} = node, opts) do
    result = %ExitExpression{
      reason: reason,
      location: Helpers.extract_location_if(node, opts)
    }

    {:ok, result}
  end

  def extract_exit(node, _opts) do
    {:error, Helpers.format_error("Not an exit expression", node)}
  end

  @doc """
  Extracts an exit expression, raising on error.

  ## Examples

      iex> ast = {:exit, [], [:shutdown]}
      iex> result = ElixirOntologies.Extractors.Exception.extract_exit!(ast)
      iex> result.reason
      :shutdown
  """
  @spec extract_exit!(Macro.t(), keyword()) :: ExitExpression.t()
  def extract_exit!(node, opts \\ []) do
    case extract_exit(node, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Extracts all exit expressions from an AST.

  ## Examples

      iex> ast = quote do
      ...>   exit(:normal)
      ...>   exit(:shutdown)
      ...> end
      iex> exits = ElixirOntologies.Extractors.Exception.extract_exits(ast)
      iex> length(exits)
      2
  """
  @spec extract_exits(Macro.t(), keyword()) :: [ExitExpression.t()]
  def extract_exits(ast, opts \\ []) do
    {_ast, exits} =
      Macro.prewalk(ast, [], fn
        {:exit, _meta, _args} = node, acc ->
          case extract_exit(node, opts) do
            {:ok, exit_expr} -> {node, [exit_expr | acc]}
            {:error, _} -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(exits)
  end
end
