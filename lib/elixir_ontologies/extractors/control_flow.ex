defmodule ElixirOntologies.Extractors.ControlFlow do
  @moduledoc """
  Extracts control flow expressions from AST nodes.

  This module analyzes Elixir AST nodes representing control flow constructs and
  extracts their type classification, conditions, clauses, and structure. Supports
  all control flow types defined in the elixir-core.ttl ontology:

  - If: `if condition, do: then_branch, else: else_branch`
  - Unless: `unless condition, do: body`
  - Case: `case value do pattern -> body end`
  - Cond: `cond do condition -> body end`
  - With: `with pattern <- expr do body else fallback end`
  - Try: `try do body rescue/catch/after clauses end`
  - Receive: `receive do pattern -> body after timeout -> fallback end`
  - Raise: `raise message` or `raise ExceptionModule, opts`
  - Throw: `throw value`

  ## Clause Ordering

  Clauses are extracted in source order, which is semantically significant
  for pattern matching (case), conditions (cond), and validation (with).
  The first matching clause wins, so order preservation is critical.

  ## Usage

      iex> alias ElixirOntologies.Extractors.ControlFlow
      iex> ast = {:if, [], [{:>, [], [{:x, [], nil}, 0]}, [do: :positive, else: :negative]]}
      iex> {:ok, result} = ControlFlow.extract(ast)
      iex> result.type
      :if
      iex> result.metadata.has_else
      true

      iex> alias ElixirOntologies.Extractors.ControlFlow
      iex> ast = {:case, [], [{:x, [], nil}, [do: [{:->, [], [[:ok], :success]}]]]}
      iex> {:ok, result} = ControlFlow.extract(ast)
      iex> result.type
      :case
      iex> length(result.clauses)
      1
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Control Flow Type Constants
  # ===========================================================================

  @control_flow_types [:if, :unless, :case, :cond, :with, :try, :receive, :raise, :throw]

  # ===========================================================================
  # Result Structs
  # ===========================================================================

  @typedoc """
  The result of control flow expression extraction.

  - `:type` - The control flow type classification
  - `:condition` - The condition expression (for if/unless/case)
  - `:clauses` - List of extracted clauses (for case/cond/with/try/receive)
  - `:branches` - Map of branch AST nodes
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          type: control_flow_type(),
          condition: Macro.t() | nil,
          clauses: [clause()],
          branches: branches(),
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @type control_flow_type ::
          :if | :unless | :case | :cond | :with | :try | :receive | :raise | :throw

  @type branches :: %{
          optional(:then) => Macro.t() | nil,
          optional(:else) => Macro.t() | nil,
          optional(:do) => Macro.t() | nil,
          optional(:rescue) => [clause()],
          optional(:catch) => [clause()],
          optional(:after) => Macro.t() | nil
        }

  @typedoc """
  A clause in a control flow expression (case, cond, etc.).

  - `:patterns` - List of pattern ASTs for matching
  - `:guard` - Optional guard expression
  - `:body` - The clause body
  """
  @type clause :: %{
          patterns: [Macro.t()],
          guard: Macro.t() | nil,
          body: Macro.t()
        }

  defstruct [:type, :condition, clauses: [], branches: %{}, location: nil, metadata: %{}]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a control flow expression.

  ## Examples

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow?({:if, [], [true, [do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow?({:case, [], [{:x, [], nil}, [do: []]]})
      true

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow?({:def, [], [{:foo, [], nil}]})
      false

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow?(:atom)
      false
  """
  @spec control_flow?(Macro.t()) :: boolean()
  def control_flow?(node), do: control_flow_type(node) != nil

  @doc """
  Returns the control flow type classification, or `nil` if not a control flow expression.

  ## Examples

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow_type({:if, [], [true, [do: :ok]]})
      :if

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow_type({:unless, [], [false, [do: :ok]]})
      :unless

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow_type({:case, [], [{:x, [], nil}, [do: []]]})
      :case

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow_type({:cond, [], [[do: []]]})
      :cond

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow_type({:with, [], [[do: :ok]]})
      :with

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow_type({:try, [], [[do: :ok]]})
      :try

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow_type({:receive, [], [[do: []]]})
      :receive

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow_type({:raise, [], ["error"]})
      :raise

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow_type({:throw, [], [:value]})
      :throw

      iex> ElixirOntologies.Extractors.ControlFlow.control_flow_type({:def, [], nil})
      nil
  """
  @spec control_flow_type(Macro.t()) :: control_flow_type() | nil
  def control_flow_type({type, _meta, args}) when type in @control_flow_types and is_list(args) do
    type
  end

  def control_flow_type(_), do: nil

  # ===========================================================================
  # Convenience Validation Functions
  # ===========================================================================

  @doc """
  Checks if a control flow result has an else branch.

  ## Examples

      iex> alias ElixirOntologies.Extractors.ControlFlow
      iex> ast = {:if, [], [true, [do: :ok, else: :error]]}
      iex> {:ok, result} = ControlFlow.extract(ast)
      iex> ControlFlow.has_else?(result)
      true

      iex> alias ElixirOntologies.Extractors.ControlFlow
      iex> ast = {:if, [], [true, [do: :ok]]}
      iex> {:ok, result} = ControlFlow.extract(ast)
      iex> ControlFlow.has_else?(result)
      false
  """
  @spec has_else?(t()) :: boolean()
  def has_else?(%__MODULE__{metadata: %{has_else: has_else}}), do: has_else
  def has_else?(_), do: false

  @doc """
  Checks if a receive expression has a timeout.

  ## Examples

      iex> alias ElixirOntologies.Extractors.ControlFlow
      iex> ast = {:receive, [], [[do: [], after: [{:->, [], [[5000], :timeout]}]]]}
      iex> {:ok, result} = ControlFlow.extract(ast)
      iex> ControlFlow.has_timeout?(result)
      true

      iex> alias ElixirOntologies.Extractors.ControlFlow
      iex> ast = {:receive, [], [[do: []]]}
      iex> {:ok, result} = ControlFlow.extract(ast)
      iex> ControlFlow.has_timeout?(result)
      false
  """
  @spec has_timeout?(t()) :: boolean()
  def has_timeout?(%__MODULE__{metadata: %{has_timeout: has_timeout}}), do: has_timeout
  def has_timeout?(_), do: false

  @doc """
  Checks if a try expression has a rescue clause.

  ## Examples

      iex> alias ElixirOntologies.Extractors.ControlFlow
      iex> ast = {:try, [], [[do: :ok, rescue: [{:->, [], [[{:e, [], nil}], :error]}]]]}
      iex> {:ok, result} = ControlFlow.extract(ast)
      iex> ControlFlow.has_rescue?(result)
      true
  """
  @spec has_rescue?(t()) :: boolean()
  def has_rescue?(%__MODULE__{metadata: %{has_rescue: has_rescue}}), do: has_rescue
  def has_rescue?(_), do: false

  @doc """
  Checks if a try expression has a catch clause.

  ## Examples

      iex> alias ElixirOntologies.Extractors.ControlFlow
      iex> ast = {:try, [], [[do: :ok, catch: [{:->, [], [[:exit, :reason], :caught]}]]]}
      iex> {:ok, result} = ControlFlow.extract(ast)
      iex> ControlFlow.has_catch?(result)
      true
  """
  @spec has_catch?(t()) :: boolean()
  def has_catch?(%__MODULE__{metadata: %{has_catch: has_catch}}), do: has_catch
  def has_catch?(_), do: false

  @doc """
  Checks if a try expression has an after clause.

  ## Examples

      iex> alias ElixirOntologies.Extractors.ControlFlow
      iex> ast = {:try, [], [[do: :ok, after: {:cleanup, [], []}]]}
      iex> {:ok, result} = ControlFlow.extract(ast)
      iex> ControlFlow.has_after?(result)
      true
  """
  @spec has_after?(t()) :: boolean()
  def has_after?(%__MODULE__{metadata: %{has_after: has_after}}), do: has_after
  def has_after?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a control flow expression from an AST node.

  Returns `{:ok, %ControlFlow{}}` on success, or `{:error, reason}` if the node
  is not a recognized control flow expression.

  ## Examples

      iex> ast = {:if, [], [{:x, [], nil}, [do: :ok, else: :error]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.ControlFlow.extract(ast)
      iex> result.type
      :if

      iex> {:error, _} = ElixirOntologies.Extractors.ControlFlow.extract({:def, [], nil})
  """
  @spec extract(Macro.t()) :: {:ok, t()} | {:error, String.t()}
  def extract(node) do
    case control_flow_type(node) do
      nil -> {:error, Helpers.format_error("Not a control flow expression", node)}
      :if -> {:ok, extract_if(node)}
      :unless -> {:ok, extract_unless(node)}
      :case -> {:ok, extract_case(node)}
      :cond -> {:ok, extract_cond(node)}
      :with -> {:ok, extract_with(node)}
      :try -> {:ok, extract_try(node)}
      :receive -> {:ok, extract_receive(node)}
      :raise -> {:ok, extract_raise(node)}
      :throw -> {:ok, extract_throw(node)}
    end
  end

  @doc """
  Extracts a control flow expression from an AST node, raising on error.

  ## Examples

      iex> ast = {:if, [], [true, [do: :ok]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract!(ast)
      iex> result.type
      :if
  """
  @spec extract!(Macro.t()) :: t()
  def extract!(node) do
    case extract(node) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ===========================================================================
  # Type-Specific Extractors
  # ===========================================================================

  @doc """
  Extracts an if expression.

  ## Examples

      iex> ast = {:if, [], [{:x, [], nil}, [do: :then_branch, else: :else_branch]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_if(ast)
      iex> result.type
      :if
      iex> result.metadata.has_else
      true
      iex> result.branches.then
      :then_branch
      iex> result.branches.else
      :else_branch

      iex> ast = {:if, [], [{:x, [], nil}, [do: :only_then]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_if(ast)
      iex> result.metadata.has_else
      false
      iex> result.branches.else
      nil
  """
  @spec extract_if(Macro.t()) :: t()
  def extract_if({:if, meta, [condition, opts]}) do
    build_conditional(:if, meta, condition, opts)
  end

  @doc """
  Extracts an unless expression.

  ## Examples

      iex> ast = {:unless, [], [{:x, [], nil}, [do: :body, else: :fallback]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_unless(ast)
      iex> result.type
      :unless
      iex> result.metadata.has_else
      true

      iex> ast = {:unless, [], [{:x, [], nil}, [do: :body]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_unless(ast)
      iex> result.metadata.has_else
      false
  """
  @spec extract_unless(Macro.t()) :: t()
  def extract_unless({:unless, meta, [condition, opts]}) do
    build_conditional(:unless, meta, condition, opts)
  end

  @doc """
  Extracts a case expression.

  ## Examples

      iex> clauses = [{:->, [], [[:ok], :success]}, {:->, [], [[:error], :failure]}]
      iex> ast = {:case, [], [{:value, [], nil}, [do: clauses]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_case(ast)
      iex> result.type
      :case
      iex> length(result.clauses)
      2
  """
  @spec extract_case(Macro.t()) :: t()
  def extract_case({:case, _meta, [value, opts]} = node) do
    do_clauses = Keyword.get(opts, :do, [])
    extracted_clauses = extract_clauses(do_clauses)

    %__MODULE__{
      type: :case,
      condition: value,
      clauses: extracted_clauses,
      branches: %{
        do: do_clauses
      },
      location: Helpers.extract_location(node),
      metadata: %{
        clause_count: length(extracted_clauses)
      }
    }
  end

  @doc """
  Extracts a cond expression.

  ## Examples

      iex> clauses = [{:->, [], [[true], :ok]}]
      iex> ast = {:cond, [], [[do: clauses]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_cond(ast)
      iex> result.type
      :cond
      iex> length(result.clauses)
      1
  """
  @spec extract_cond(Macro.t()) :: t()
  def extract_cond({:cond, _meta, [opts]} = node) do
    do_clauses = Keyword.get(opts, :do, [])
    extracted_clauses = extract_cond_clauses(do_clauses)

    %__MODULE__{
      type: :cond,
      condition: nil,
      clauses: extracted_clauses,
      branches: %{
        do: do_clauses
      },
      location: Helpers.extract_location(node),
      metadata: %{
        clause_count: length(extracted_clauses)
      }
    }
  end

  @doc """
  Extracts a with expression.

  ## Examples

      iex> match_clause = {:<-, [], [{:ok, {:x, [], nil}}, {:get, [], []}]}
      iex> ast = {:with, [], [match_clause, [do: {:ok, {:x, [], nil}}]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_with(ast)
      iex> result.type
      :with
      iex> result.metadata.has_else
      false
      iex> length(result.clauses)
      1
  """
  @spec extract_with(Macro.t()) :: t()
  def extract_with({:with, _meta, []} = node) do
    # Handle empty with expression
    %__MODULE__{
      type: :with,
      condition: nil,
      clauses: [],
      branches: %{do: nil, else: []},
      location: Helpers.extract_location(node),
      metadata: %{
        has_else: false,
        match_clause_count: 0,
        else_clause_count: 0,
        error: :empty_args
      }
    }
  end

  def extract_with({:with, _meta, [_ | _] = args} = node) do
    # Separate match clauses from the final options
    {match_clauses, opts_list} = Enum.split(args, -1)

    opts =
      case opts_list do
        [opts] when is_list(opts) -> opts
        _ -> []
      end

    do_body = Keyword.get(opts, :do)
    else_clauses = Keyword.get(opts, :else, [])

    extracted_match_clauses = extract_with_match_clauses(match_clauses)
    extracted_else_clauses = extract_clauses(else_clauses)

    %__MODULE__{
      type: :with,
      condition: nil,
      clauses: extracted_match_clauses,
      branches: %{
        do: do_body,
        else: extracted_else_clauses
      },
      location: Helpers.extract_location(node),
      metadata: %{
        has_else: else_clauses != [],
        match_clause_count: length(extracted_match_clauses),
        else_clause_count: length(extracted_else_clauses)
      }
    }
  end

  @doc """
  Extracts a try expression.

  ## Examples

      iex> ast = {:try, [], [[do: {:risky, [], []}, rescue: [{:->, [], [[{:e, [], nil}], :error]}]]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_try(ast)
      iex> result.type
      :try
      iex> result.metadata.has_rescue
      true
      iex> result.metadata.has_catch
      false
      iex> result.metadata.has_after
      false
  """
  @spec extract_try(Macro.t()) :: t()
  def extract_try({:try, _meta, [opts]} = node) do
    do_body = Keyword.get(opts, :do)
    rescue_clauses = Keyword.get(opts, :rescue, [])
    catch_clauses = Keyword.get(opts, :catch, [])
    after_body = Keyword.get(opts, :after)

    extracted_rescue = extract_rescue_clauses(rescue_clauses)
    extracted_catch = extract_catch_clauses(catch_clauses)

    %__MODULE__{
      type: :try,
      condition: nil,
      clauses: [],
      branches: %{
        do: do_body,
        rescue: extracted_rescue,
        catch: extracted_catch,
        after: after_body
      },
      location: Helpers.extract_location(node),
      metadata: %{
        has_rescue: rescue_clauses != [],
        has_catch: catch_clauses != [],
        has_after: after_body != nil,
        rescue_clause_count: length(extracted_rescue),
        catch_clause_count: length(extracted_catch)
      }
    }
  end

  @doc """
  Extracts a receive expression.

  ## Examples

      iex> clauses = [{:->, [], [[ok: {:msg, [], nil}], {:msg, [], nil}]}]
      iex> ast = {:receive, [], [[do: clauses]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_receive(ast)
      iex> result.type
      :receive
      iex> result.metadata.has_timeout
      false

      iex> clauses = [{:->, [], [[ok: {:msg, [], nil}], {:msg, [], nil}]}]
      iex> after_clause = [{:->, [], [[5000], :timeout]}]
      iex> ast = {:receive, [], [[do: clauses, after: after_clause]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_receive(ast)
      iex> result.metadata.has_timeout
      true
      iex> result.metadata.timeout_value
      5000
  """
  @spec extract_receive(Macro.t()) :: t()
  def extract_receive({:receive, _meta, [opts]} = node) do
    do_clauses = Keyword.get(opts, :do, [])
    after_clauses = Keyword.get(opts, :after, [])

    extracted_do = extract_clauses(do_clauses)
    {timeout_value, after_body} = extract_timeout(after_clauses)

    %__MODULE__{
      type: :receive,
      condition: nil,
      clauses: extracted_do,
      branches: %{
        do: do_clauses,
        after: after_body
      },
      location: Helpers.extract_location(node),
      metadata: %{
        has_timeout: after_clauses != [],
        timeout_value: timeout_value,
        clause_count: length(extracted_do)
      }
    }
  end

  @doc """
  Extracts a raise expression.

  ## Examples

      iex> ast = {:raise, [], ["error message"]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_raise(ast)
      iex> result.type
      :raise
      iex> result.metadata.raise_type
      :message
      iex> result.metadata.message
      "error message"

      iex> ast = {:raise, [], [{:__aliases__, [], [:RuntimeError]}, [message: "error"]]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_raise(ast)
      iex> result.metadata.raise_type
      :exception
      iex> result.metadata.exception_module
      [:RuntimeError]
  """
  @spec extract_raise(Macro.t()) :: t()
  def extract_raise({:raise, _meta, args} = node) do
    {raise_type, exception_info} = classify_raise(args)

    %__MODULE__{
      type: :raise,
      condition: nil,
      clauses: [],
      branches: %{},
      location: Helpers.extract_location(node),
      metadata: Map.merge(%{raise_type: raise_type}, exception_info)
    }
  end

  @doc """
  Extracts a throw expression.

  ## Examples

      iex> ast = {:throw, [], [:value]}
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_throw(ast)
      iex> result.type
      :throw
      iex> result.metadata.thrown_value
      :value
  """
  @spec extract_throw(Macro.t()) :: t()
  def extract_throw({:throw, _meta, [value]} = node) do
    %__MODULE__{
      type: :throw,
      condition: nil,
      clauses: [],
      branches: %{},
      location: Helpers.extract_location(node),
      metadata: %{
        thrown_value: value
      }
    }
  end

  # ===========================================================================
  # Clause Extraction Helpers
  # ===========================================================================

  @doc """
  Extracts clauses from a list of arrow expressions.

  ## Examples

      iex> clauses = [{:->, [], [[:ok], :success]}, {:->, [], [[:error], :failure]}]
      iex> result = ElixirOntologies.Extractors.ControlFlow.extract_clauses(clauses)
      iex> length(result)
      2
      iex> hd(result).patterns
      [:ok]
      iex> hd(result).body
      :success
  """
  @spec extract_clauses([Macro.t()]) :: [clause()]
  def extract_clauses(clauses) when is_list(clauses) do
    Enum.map(clauses, &extract_single_clause/1)
  end

  # Arrow clause with patterns and body
  defp extract_single_clause({:->, _meta, [patterns, body]}) do
    {actual_patterns, guard} = extract_patterns_and_guard(patterns)

    %{
      patterns: actual_patterns,
      guard: guard,
      body: body
    }
  end

  # Fallback for malformed clauses
  defp extract_single_clause(malformed) do
    %{
      patterns: [],
      guard: nil,
      body: malformed
    }
  end

  defp extract_patterns_and_guard(patterns) when is_list(patterns) do
    # Check for guard in patterns (when clause)
    case patterns do
      [{:when, _, [pattern | guards]}] ->
        guard = Helpers.combine_guards(guards)
        {[pattern], guard}

      _ ->
        {patterns, nil}
    end
  end

  # Cond clauses have conditions as patterns
  defp extract_cond_clauses(clauses) when is_list(clauses) do
    Enum.map(clauses, &extract_cond_clause/1)
  end

  defp extract_cond_clause({:->, _meta, [[condition], body]}) do
    %{
      patterns: [condition],
      guard: nil,
      body: body
    }
  end

  # Fallback for malformed cond clauses
  defp extract_cond_clause(malformed) do
    %{
      patterns: [],
      guard: nil,
      body: malformed
    }
  end

  # With match clauses use <- operator
  defp extract_with_match_clauses(clauses) do
    Enum.map(clauses, &extract_with_clause/1)
  end

  defp extract_with_clause({:<-, _meta, [pattern, expr]}) do
    %{
      patterns: [pattern],
      guard: nil,
      body: expr
    }
  end

  # Bare expressions in with (used as validators)
  defp extract_with_clause(expr) do
    %{
      patterns: [],
      guard: expr,
      body: nil
    }
  end

  # Rescue clauses handle exception patterns
  defp extract_rescue_clauses(clauses) when is_list(clauses) do
    Enum.map(clauses, &extract_rescue_clause/1)
  end

  defp extract_rescue_clause({:->, _meta, [patterns, body]}) do
    %{
      patterns: patterns,
      guard: nil,
      body: body
    }
  end

  # Fallback for malformed rescue clauses
  defp extract_rescue_clause(malformed) do
    %{
      patterns: [],
      guard: nil,
      body: malformed
    }
  end

  # Catch clauses handle kind/value pairs
  defp extract_catch_clauses(clauses) when is_list(clauses) do
    Enum.map(clauses, &extract_catch_clause/1)
  end

  defp extract_catch_clause({:->, _meta, [patterns, body]}) do
    %{
      patterns: patterns,
      guard: nil,
      body: body
    }
  end

  # Fallback for malformed catch clauses
  defp extract_catch_clause(malformed) do
    %{
      patterns: [],
      guard: nil,
      body: malformed
    }
  end

  # ===========================================================================
  # Private Helper Functions
  # ===========================================================================

  # Shared builder for if/unless expressions
  defp build_conditional(type, meta, condition, opts) do
    then_branch = Keyword.get(opts, :do)
    else_branch = Keyword.get(opts, :else)

    %__MODULE__{
      type: type,
      condition: condition,
      clauses: [],
      branches: %{
        then: then_branch,
        else: else_branch
      },
      location: Helpers.extract_location({type, meta, [condition, opts]}),
      metadata: %{
        has_else: else_branch != nil
      }
    }
  end

  defp extract_timeout([{:->, _meta, [[timeout], body]}]) when is_integer(timeout) do
    {timeout, body}
  end

  defp extract_timeout([{:->, _meta, [[timeout_expr], body]}]) do
    {timeout_expr, body}
  end

  defp extract_timeout([]) do
    {nil, nil}
  end

  # Fallback for malformed timeout
  defp extract_timeout(_) do
    {nil, nil}
  end

  defp classify_raise([message]) when is_binary(message) do
    {:message, %{message: message}}
  end

  defp classify_raise([{:__aliases__, _meta, parts}]) do
    {:exception, %{exception_module: parts, options: []}}
  end

  defp classify_raise([{:__aliases__, _meta, parts}, opts]) do
    {:exception, %{exception_module: parts, options: opts}}
  end

  defp classify_raise([exception_var]) do
    {:reraise, %{exception: exception_var}}
  end

  defp classify_raise(args) do
    {:unknown, %{args: args}}
  end
end
