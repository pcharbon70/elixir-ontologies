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
  # QuoteOptions Struct
  # ===========================================================================

  defmodule QuoteOptions do
    @moduledoc """
    Represents the options passed to a quote block.

    This struct captures all possible quote options including bind_quoted,
    context, location, unquote control, and code generation metadata.

    ## Fields

    - `:bind_quoted` - Keyword list of bound variables `[x: value]`
    - `:context` - Context for hygiene (atom or module)
    - `:location` - Location option (`:keep` to preserve line info)
    - `:unquote` - Whether unquote is enabled (default: true)
    - `:line` - Override line number
    - `:file` - Override file name
    - `:generated` - Mark as compiler-generated code

    ## Usage

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> opts = QuoteOptions.new(bind_quoted: [x: 1], context: :match)
        iex> opts.bind_quoted
        [x: 1]
        iex> opts.context
        :match
    """

    @type t :: %__MODULE__{
            bind_quoted: keyword() | nil,
            context: module() | atom() | nil,
            location: :keep | nil,
            unquote: boolean(),
            line: pos_integer() | nil,
            file: String.t() | nil,
            generated: boolean() | nil
          }

    defstruct [
      bind_quoted: nil,
      context: nil,
      location: nil,
      unquote: true,
      line: nil,
      file: nil,
      generated: nil
    ]

    @doc """
    Creates a new QuoteOptions with the given options.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> opts = QuoteOptions.new(context: :match, location: :keep)
        iex> opts.context
        :match
        iex> opts.location
        :keep

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> opts = QuoteOptions.new(unquote: false)
        iex> opts.unquote
        false
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        bind_quoted: Keyword.get(opts, :bind_quoted),
        context: Keyword.get(opts, :context),
        location: Keyword.get(opts, :location),
        unquote: Keyword.get(opts, :unquote, true),
        line: Keyword.get(opts, :line),
        file: Keyword.get(opts, :file),
        generated: Keyword.get(opts, :generated)
      }
    end

    @doc """
    Checks if location: :keep is set.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.location_keep?(QuoteOptions.new(location: :keep))
        true

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.location_keep?(QuoteOptions.new())
        false
    """
    @spec location_keep?(t()) :: boolean()
    def location_keep?(%__MODULE__{location: :keep}), do: true
    def location_keep?(_), do: false

    @doc """
    Checks if unquoting is disabled (unquote: false).

    ## Examples

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.unquoting_disabled?(QuoteOptions.new(unquote: false))
        true

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.unquoting_disabled?(QuoteOptions.new())
        false
    """
    @spec unquoting_disabled?(t()) :: boolean()
    def unquoting_disabled?(%__MODULE__{unquote: false}), do: true
    def unquoting_disabled?(_), do: false

    @doc """
    Checks if bind_quoted is set.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.has_bind_quoted?(QuoteOptions.new(bind_quoted: [x: 1]))
        true

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.has_bind_quoted?(QuoteOptions.new())
        false
    """
    @spec has_bind_quoted?(t()) :: boolean()
    def has_bind_quoted?(%__MODULE__{bind_quoted: nil}), do: false
    def has_bind_quoted?(%__MODULE__{bind_quoted: []}), do: false
    def has_bind_quoted?(%__MODULE__{}), do: true

    @doc """
    Gets the list of bound variable names from bind_quoted.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.bind_quoted_vars(QuoteOptions.new(bind_quoted: [x: 1, y: 2]))
        [:x, :y]

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.bind_quoted_vars(QuoteOptions.new())
        []
    """
    @spec bind_quoted_vars(t()) :: [atom()]
    def bind_quoted_vars(%__MODULE__{bind_quoted: nil}), do: []
    def bind_quoted_vars(%__MODULE__{bind_quoted: bindings}) when is_list(bindings) do
      Keyword.keys(bindings)
    end

    @doc """
    Checks if a context is set.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.has_context?(QuoteOptions.new(context: :match))
        true

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.has_context?(QuoteOptions.new())
        false
    """
    @spec has_context?(t()) :: boolean()
    def has_context?(%__MODULE__{context: nil}), do: false
    def has_context?(%__MODULE__{}), do: true

    @doc """
    Checks if the quote is marked as generated.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.generated?(QuoteOptions.new(generated: true))
        true

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.generated?(QuoteOptions.new())
        false
    """
    @spec generated?(t()) :: boolean()
    def generated?(%__MODULE__{generated: true}), do: true
    def generated?(_), do: false

    @doc """
    Checks if a custom line is set.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.has_line?(QuoteOptions.new(line: 42))
        true

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.has_line?(QuoteOptions.new())
        false
    """
    @spec has_line?(t()) :: boolean()
    def has_line?(%__MODULE__{line: nil}), do: false
    def has_line?(%__MODULE__{}), do: true

    @doc """
    Checks if a custom file is set.

    ## Examples

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.has_file?(QuoteOptions.new(file: "my_file.ex"))
        true

        iex> alias ElixirOntologies.Extractors.Quote.QuoteOptions
        iex> QuoteOptions.has_file?(QuoteOptions.new())
        false
    """
    @spec has_file?(t()) :: boolean()
    def has_file?(%__MODULE__{file: nil}), do: false
    def has_file?(%__MODULE__{}), do: true
  end

  # ===========================================================================
  # QuotedExpression Struct
  # ===========================================================================

  defmodule QuotedExpression do
    @moduledoc """
    Represents a quote block extraction result.
    """

    @type t :: %__MODULE__{
            body: Macro.t(),
            options: ElixirOntologies.Extractors.Quote.QuoteOptions.t(),
            unquotes: [ElixirOntologies.Extractors.Quote.UnquoteExpression.t()],
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct [
      :body,
      :location,
      options: %ElixirOntologies.Extractors.Quote.QuoteOptions{},
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
    parsed_options = QuoteOptions.new()
    unquotes = find_unquotes(body)

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
    QuoteOptions.new(
      bind_quoted: Keyword.get(options, :bind_quoted),
      context: Keyword.get(options, :context),
      location: Keyword.get(options, :location),
      unquote: Keyword.get(options, :unquote, true),
      line: Keyword.get(options, :line),
      file: Keyword.get(options, :file),
      generated: Keyword.get(options, :generated)
    )
  end

  # ===========================================================================
  # QuoteOptions Helper Functions
  # ===========================================================================

  @doc """
  Checks if location: :keep is set on the quote.

  ## Examples

      iex> ast = {:quote, [], [[location: :keep], [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.location_keep?(result)
      true

      iex> ast = {:quote, [], [[do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.location_keep?(result)
      false
  """
  @spec location_keep?(QuotedExpression.t()) :: boolean()
  def location_keep?(%QuotedExpression{options: options}) do
    QuoteOptions.location_keep?(options)
  end

  @doc """
  Checks if unquoting is disabled (unquote: false) on the quote.

  ## Examples

      iex> ast = {:quote, [], [[unquote: false], [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.unquoting_disabled?(result)
      true

      iex> ast = {:quote, [], [[do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.unquoting_disabled?(result)
      false
  """
  @spec unquoting_disabled?(QuotedExpression.t()) :: boolean()
  def unquoting_disabled?(%QuotedExpression{options: options}) do
    QuoteOptions.unquoting_disabled?(options)
  end

  @doc """
  Gets the list of bound variable names from bind_quoted.

  ## Examples

      iex> ast = {:quote, [], [[bind_quoted: [x: 1, y: 2]], [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.bind_quoted_vars(result)
      [:x, :y]

      iex> ast = {:quote, [], [[do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.bind_quoted_vars(result)
      []
  """
  @spec bind_quoted_vars(QuotedExpression.t()) :: [atom()]
  def bind_quoted_vars(%QuotedExpression{options: options}) do
    QuoteOptions.bind_quoted_vars(options)
  end

  @doc """
  Gets the context option value from the quote.

  ## Examples

      iex> ast = {:quote, [], [[context: :match], [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.get_context(result)
      :match

      iex> ast = {:quote, [], [[do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.get_context(result)
      nil
  """
  @spec get_context(QuotedExpression.t()) :: module() | atom() | nil
  def get_context(%QuotedExpression{options: %QuoteOptions{context: context}}) do
    context
  end

  @doc """
  Checks if the quote is marked as generated.

  ## Examples

      iex> ast = {:quote, [], [[generated: true], [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.generated?(result)
      true

      iex> ast = {:quote, [], [[do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.generated?(result)
      false
  """
  @spec generated?(QuotedExpression.t()) :: boolean()
  def generated?(%QuotedExpression{options: options}) do
    QuoteOptions.generated?(options)
  end

  @doc """
  Gets the custom line number from the quote options.

  ## Examples

      iex> ast = {:quote, [], [[line: 42], [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.get_line(result)
      42

      iex> ast = {:quote, [], [[do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.get_line(result)
      nil
  """
  @spec get_line(QuotedExpression.t()) :: pos_integer() | nil
  def get_line(%QuotedExpression{options: %QuoteOptions{line: line}}) do
    line
  end

  @doc """
  Gets the custom file name from the quote options.

  ## Examples

      iex> ast = {:quote, [], [[file: "my_file.ex"], [do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.get_file(result)
      "my_file.ex"

      iex> ast = {:quote, [], [[do: :ok]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Quote.extract(ast)
      iex> ElixirOntologies.Extractors.Quote.get_file(result)
      nil
  """
  @spec get_file(QuotedExpression.t()) :: String.t() | nil
  def get_file(%QuotedExpression{options: %QuoteOptions{file: file}}) do
    file
  end
end
