defmodule ElixirOntologies.Extractors.Quote do
  @moduledoc """
  Extracts quote/unquote metaprogramming constructs from AST nodes.

  This module analyzes Elixir AST nodes representing metaprogramming
  constructs including quote blocks, unquote expressions, and
  unquote_splicing expressions.

  ## Ontology Classes

  From `elixir-structure.ttl`:
  - `QuotedExpression` - A quote block
  - `quotesExpression` - Links quote to its body
  - `quoteContext` - The context option
  - `UnquoteExpression` - An unquote call
  - `UnquoteSplicingExpression` - An unquote_splicing call

  ## Usage

      iex> alias ElixirOntologies.Extractors.Quote
      iex> ast = {:quote, [], [[do: {:+, [], [1, 2]}]]}
      iex> {:ok, result} = Quote.extract(ast)
      iex> result.body
      {:+, [], [1, 2]}

      iex> alias ElixirOntologies.Extractors.Quote
      iex> ast = {:unquote, [], [{:x, [], nil}]}
      iex> {:ok, result} = Quote.extract_unquote(ast)
      iex> result.kind
      :unquote
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # QuotedExpression Struct
  # ===========================================================================

  defmodule QuotedExpression do
    @moduledoc """
    Represents a quote block extraction result.
    """

    @type t :: %__MODULE__{
            body: Macro.t(),
            options: map(),
            unquotes: [ElixirOntologies.Extractors.Quote.UnquoteExpression.t()],
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct [
      :body,
      :location,
      options: %{},
      unquotes: [],
      metadata: %{}
    ]
  end

  # ===========================================================================
  # UnquoteExpression Struct
  # ===========================================================================

  defmodule UnquoteExpression do
    @moduledoc """
    Represents an unquote or unquote_splicing extraction result.
    """

    @type t :: %__MODULE__{
            kind: :unquote | :unquote_splicing,
            value: Macro.t(),
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct [
      :kind,
      :value,
      :location,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Quote Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a quote block.

  ## Examples

      iex> ElixirOntologies.Extractors.Quote.quote?({:quote, [], [[do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.Quote.quote?({:quote, [], [[context: :match], [do: :ok]]})
      true

      iex> ElixirOntologies.Extractors.Quote.quote?({:unquote, [], [{:x, [], nil}]})
      false

      iex> ElixirOntologies.Extractors.Quote.quote?(nil)
      false
  """
  @spec quote?(Macro.t()) :: boolean()
  def quote?({:quote, _, _}), do: true
  def quote?(_), do: false

  @doc """
  Checks if an AST node represents an unquote expression.

  ## Examples

      iex> ElixirOntologies.Extractors.Quote.unquote?({:unquote, [], [{:x, [], nil}]})
      true

      iex> ElixirOntologies.Extractors.Quote.unquote?({:unquote_splicing, [], [{:list, [], nil}]})
      false

      iex> ElixirOntologies.Extractors.Quote.unquote?({:quote, [], [[do: :ok]]})
      false
  """
  @spec unquote?(Macro.t()) :: boolean()
  def unquote?({:unquote, _, [_]}), do: true
  def unquote?(_), do: false

  @doc """
  Checks if an AST node represents an unquote_splicing expression.

  ## Examples

      iex> ElixirOntologies.Extractors.Quote.unquote_splicing?({:unquote_splicing, [], [{:list, [], nil}]})
      true

      iex> ElixirOntologies.Extractors.Quote.unquote_splicing?({:unquote, [], [{:x, [], nil}]})
      false
  """
  @spec unquote_splicing?(Macro.t()) :: boolean()
  def unquote_splicing?({:unquote_splicing, _, [_]}), do: true
  def unquote_splicing?(_), do: false

  # ===========================================================================
  # Quote Extraction
  # ===========================================================================

  @doc """
  Extracts a quote block from an AST node.

  Returns `{:ok, %QuotedExpression{}}` on success, or `{:error, reason}` if the
  node is not a quote block.

  ## Examples

      iex> ast = {:quote, [], [[do: {:+, [], [1, 2]}]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> result.body
      {:+, [], [1, 2]}

      iex> ast = {:quote, [], [[context: :match], [do: {:x, [], nil}]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> result.options.context
      :match

      iex> ast = {:quote, [], [[bind_quoted: [x: 1]], [do: {:x, [], nil}]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> result.options.bind_quoted
      [x: 1]
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, QuotedExpression.t()} | {:error, String.t()}
  def extract(node, opts \\ [])

  # quote do: expr (no options)
  def extract({:quote, meta, [[do: body]]} = _node, _opts) do
    location = Helpers.extract_location({:quote, meta, []})
    unquotes = find_unquotes(body)

    {:ok,
     %QuotedExpression{
       body: body,
       options: %{
         bind_quoted: nil,
         context: nil,
         location: nil,
         unquote: true
       },
       unquotes: unquotes,
       location: location,
       metadata: %{
         unquote_count: length(unquotes),
         has_unquote_splicing: Enum.any?(unquotes, &(&1.kind == :unquote_splicing))
       }
     }}
  end

  # quote opts, do: expr (with options)
  def extract({:quote, meta, [options, [do: body]]} = _node, _opts) when is_list(options) do
    location = Helpers.extract_location({:quote, meta, []})
    parsed_options = parse_quote_options(options)
    unquotes = if parsed_options.unquote, do: find_unquotes(body), else: []

    {:ok,
     %QuotedExpression{
       body: body,
       options: parsed_options,
       unquotes: unquotes,
       location: location,
       metadata: %{
         unquote_count: length(unquotes),
         has_unquote_splicing: Enum.any?(unquotes, &(&1.kind == :unquote_splicing))
       }
     }}
  end

  def extract(node, _opts) do
    {:error, Helpers.format_error("Not a quote block", node)}
  end

  @doc """
  Extracts a quote block from an AST node, raising on error.

  ## Examples

      iex> ast = {:quote, [], [[do: :ok]]}
      iex> result = ElixirOntologies.Extractors.Quote.extract!(ast)
      iex> result.body
      :ok
  """
  @spec extract!(Macro.t(), keyword()) :: QuotedExpression.t()
  def extract!(node, opts \\ []) do
    case extract(node, opts) do
      {:ok, result} -> result
      {:error, message} -> raise ArgumentError, message
    end
  end

  # ===========================================================================
  # Unquote Extraction
  # ===========================================================================

  @doc """
  Extracts an unquote or unquote_splicing expression from an AST node.

  Returns `{:ok, %UnquoteExpression{}}` on success.

  ## Examples

      iex> ast = {:unquote, [], [{:x, [], nil}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract_unquote(ast)
      iex> result.kind
      :unquote
      iex> result.value
      {:x, [], nil}

      iex> ast = {:unquote_splicing, [], [{:list, [], nil}]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract_unquote(ast)
      iex> result.kind
      :unquote_splicing
  """
  @spec extract_unquote(Macro.t(), keyword()) ::
          {:ok, UnquoteExpression.t()} | {:error, String.t()}
  def extract_unquote(node, opts \\ [])

  def extract_unquote({:unquote, meta, [value]} = _node, _opts) do
    location = Helpers.extract_location({:unquote, meta, []})

    {:ok,
     %UnquoteExpression{
       kind: :unquote,
       value: value,
       location: location,
       metadata: %{}
     }}
  end

  def extract_unquote({:unquote_splicing, meta, [value]} = _node, _opts) do
    location = Helpers.extract_location({:unquote_splicing, meta, []})

    {:ok,
     %UnquoteExpression{
       kind: :unquote_splicing,
       value: value,
       location: location,
       metadata: %{}
     }}
  end

  def extract_unquote(node, _opts) do
    {:error, Helpers.format_error("Not an unquote expression", node)}
  end

  # ===========================================================================
  # Finding Unquotes
  # ===========================================================================

  @doc """
  Finds all unquote and unquote_splicing expressions within an AST.

  Does not descend into nested quote blocks.

  ## Examples

      iex> ast = {:+, [], [{:unquote, [], [{:x, [], nil}]}, 1]}
      iex> results = ElixirOntologies.Extractors.Quote.find_unquotes(ast)
      iex> length(results)
      1
      iex> hd(results).kind
      :unquote

      iex> ast = [{:unquote_splicing, [], [{:list, [], nil}]}, :end]
      iex> results = ElixirOntologies.Extractors.Quote.find_unquotes(ast)
      iex> length(results)
      1
      iex> hd(results).kind
      :unquote_splicing
  """
  @spec find_unquotes(Macro.t()) :: [UnquoteExpression.t()]
  def find_unquotes(ast) do
    {_, unquotes} = do_find_unquotes(ast, [])
    Enum.reverse(unquotes)
  end

  defp do_find_unquotes({:quote, _, _} = _node, acc) do
    # Don't descend into nested quotes
    {nil, acc}
  end

  defp do_find_unquotes({:unquote, meta, [value]} = _node, acc) do
    unquote_expr = %UnquoteExpression{
      kind: :unquote,
      value: value,
      location: Helpers.extract_location({:unquote, meta, []}),
      metadata: %{}
    }

    {nil, [unquote_expr | acc]}
  end

  defp do_find_unquotes({:unquote_splicing, meta, [value]} = _node, acc) do
    unquote_expr = %UnquoteExpression{
      kind: :unquote_splicing,
      value: value,
      location: Helpers.extract_location({:unquote_splicing, meta, []}),
      metadata: %{}
    }

    {nil, [unquote_expr | acc]}
  end

  defp do_find_unquotes({_form, _meta, args} = _node, acc) when is_list(args) do
    {_, new_acc} =
      Enum.reduce(args, {nil, acc}, fn arg, {_, acc} -> do_find_unquotes(arg, acc) end)

    {nil, new_acc}
  end

  defp do_find_unquotes(list, acc) when is_list(list) do
    {_, new_acc} =
      Enum.reduce(list, {nil, acc}, fn item, {_, acc} -> do_find_unquotes(item, acc) end)

    {nil, new_acc}
  end

  defp do_find_unquotes({left, right}, acc) do
    {_, acc} = do_find_unquotes(left, acc)
    do_find_unquotes(right, acc)
  end

  defp do_find_unquotes(_other, acc) do
    {nil, acc}
  end

  # ===========================================================================
  # Bulk Extraction
  # ===========================================================================

  @doc """
  Extracts all quote blocks from an AST.

  Searches the entire AST for quote expressions.

  ## Examples

      iex> ast = {:__block__, [], [
      ...>   {:quote, [], [[do: :a]]},
      ...>   {:def, [], [{:foo, [], nil}, [do: :ok]]},
      ...>   {:quote, [], [[do: :b]]}
      ...> ]}
      iex> results = ElixirOntologies.Extractors.Quote.extract_all(ast)
      iex> length(results)
      2
      iex> Enum.map(results, & &1.body)
      [:a, :b]
  """
  @spec extract_all(Macro.t()) :: [QuotedExpression.t()]
  def extract_all(ast) do
    {_, quotes} = do_extract_all(ast, [])
    Enum.reverse(quotes)
  end

  defp do_extract_all({:quote, _, _} = node, acc) do
    case extract(node) do
      {:ok, result} -> {nil, [result | acc]}
      {:error, _} -> {nil, acc}
    end
  end

  defp do_extract_all({_form, _meta, args} = _node, acc) when is_list(args) do
    {_, new_acc} = Enum.reduce(args, {nil, acc}, fn arg, {_, acc} -> do_extract_all(arg, acc) end)
    {nil, new_acc}
  end

  defp do_extract_all(list, acc) when is_list(list) do
    {_, new_acc} =
      Enum.reduce(list, {nil, acc}, fn item, {_, acc} -> do_extract_all(item, acc) end)

    {nil, new_acc}
  end

  defp do_extract_all({left, right}, acc) do
    {_, acc} = do_extract_all(left, acc)
    do_extract_all(right, acc)
  end

  defp do_extract_all(_other, acc) do
    {nil, acc}
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Returns true if the quote has a bind_quoted option.

  ## Examples

      iex> ast = {:quote, [], [[bind_quoted: [x: 1]], [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.has_bind_quoted?(result)
      true

      iex> ast = {:quote, [], [[do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.has_bind_quoted?(result)
      false
  """
  @spec has_bind_quoted?(QuotedExpression.t()) :: boolean()
  def has_bind_quoted?(%QuotedExpression{options: %{bind_quoted: bind_quoted}})
      when not is_nil(bind_quoted),
      do: true

  def has_bind_quoted?(_), do: false

  @doc """
  Returns true if the quote has a context option.

  ## Examples

      iex> ast = {:quote, [], [[context: :match], [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.has_context?(result)
      true
  """
  @spec has_context?(QuotedExpression.t()) :: boolean()
  def has_context?(%QuotedExpression{options: %{context: context}}) when not is_nil(context),
    do: true

  def has_context?(_), do: false

  @doc """
  Returns true if the quote contains any unquotes.

  ## Examples

      iex> ast = {:quote, [], [[do: {:+, [], [{:unquote, [], [{:x, [], nil}]}, 1]}]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.has_unquotes?(result)
      true

      iex> ast = {:quote, [], [[do: {:+, [], [1, 2]}]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.has_unquotes?(result)
      false
  """
  @spec has_unquotes?(QuotedExpression.t()) :: boolean()
  def has_unquotes?(%QuotedExpression{unquotes: [_ | _]}), do: true
  def has_unquotes?(_), do: false

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp parse_quote_options(options) when is_list(options) do
    %{
      bind_quoted: Keyword.get(options, :bind_quoted),
      context: Keyword.get(options, :context),
      location: Keyword.get(options, :location),
      unquote: Keyword.get(options, :unquote, true)
    }
  end
end
