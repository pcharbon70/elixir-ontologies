defmodule ElixirOntologies.Extractors.Comprehension do
  @moduledoc """
  Extracts for comprehensions from AST nodes.

  This module analyzes Elixir AST nodes representing `for` comprehensions and
  extracts their generators, filters, options, and body expressions. Supports
  all comprehension features defined in the elixir-core.ttl ontology:

  - Generators: `x <- enumerable` - iterate over a collection
  - Bitstring Generators: `<<c <- binary>>` - iterate over binary data
  - Filters: Boolean expressions that filter results
  - Options: `:into`, `:reduce`, `:uniq`

  ## Generator Ordering

  Generators and filters are extracted in source order, which is semantically
  significant. Multiple generators create nested loops (left-to-right is
  outer-to-inner), and filters are applied at each iteration point.

  ## Usage

      iex> alias ElixirOntologies.Extractors.Comprehension
      iex> ast = {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2, 3]]}, [do: {:x, [], nil}]]}
      iex> {:ok, result} = Comprehension.extract(ast)
      iex> result.type
      :for
      iex> length(result.generators)
      1

      iex> alias ElixirOntologies.Extractors.Comprehension
      iex> ast = {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2]]}, {:>, [], [{:x, [], nil}, 0]}, [do: {:x, [], nil}]]}
      iex> {:ok, result} = Comprehension.extract(ast)
      iex> length(result.filters)
      1
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # Result Structs
  # ===========================================================================

  @typedoc """
  The result of comprehension extraction.

  - `:type` - Always `:for` for comprehensions
  - `:generators` - List of generator structs (regular and bitstring)
  - `:filters` - List of filter expressions
  - `:body` - The body expression that produces output
  - `:options` - Map of comprehension options (into, reduce, uniq)
  - `:location` - Source location if available
  - `:metadata` - Additional information
  """
  @type t :: %__MODULE__{
          type: :for,
          generators: [generator()],
          filters: [Macro.t()],
          body: Macro.t(),
          options: options(),
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @typedoc """
  A generator in a comprehension.

  - `:type` - Either `:generator` or `:bitstring_generator`
  - `:pattern` - The pattern to match against each element
  - `:enumerable` - The collection being iterated
  - `:location` - Source location if available
  """
  @type generator :: %{
          type: :generator | :bitstring_generator,
          pattern: Macro.t(),
          enumerable: Macro.t(),
          location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil
        }

  @typedoc """
  Comprehension options map.
  """
  @type options :: %{
          into: Macro.t() | nil,
          reduce: Macro.t() | nil,
          uniq: boolean()
        }

  defstruct [
    :type,
    generators: [],
    filters: [],
    body: nil,
    options: %{},
    location: nil,
    metadata: %{}
  ]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a for comprehension.

  ## Examples

      iex> ElixirOntologies.Extractors.Comprehension.comprehension?({:for, [], [[do: nil]]})
      true

      iex> ElixirOntologies.Extractors.Comprehension.comprehension?({:for, [], [{:<-, [], [{:x, [], nil}, [1]]}]})
      true

      iex> ElixirOntologies.Extractors.Comprehension.comprehension?({:if, [], [true, [do: 1]]})
      false

      iex> ElixirOntologies.Extractors.Comprehension.comprehension?(:atom)
      false
  """
  @spec comprehension?(Macro.t()) :: boolean()
  def comprehension?({:for, _meta, args}) when is_list(args), do: true
  def comprehension?(_), do: false

  @doc """
  Checks if an AST node is a generator expression (`pattern <- enumerable`).

  ## Examples

      iex> ElixirOntologies.Extractors.Comprehension.generator?({:<-, [], [{:x, [], nil}, [1, 2]]})
      true

      iex> ElixirOntologies.Extractors.Comprehension.generator?({:>, [], [{:x, [], nil}, 0]})
      false
  """
  @spec generator?(Macro.t()) :: boolean()
  def generator?({:<-, _meta, [_pattern, _enumerable]}), do: true
  def generator?(_), do: false

  @doc """
  Checks if an AST node is a bitstring generator (`<<pattern <- binary>>`).

  ## Examples

      iex> ElixirOntologies.Extractors.Comprehension.bitstring_generator?({:<<>>, [], [{:<-, [], [{:c, [], nil}, "hello"]}]})
      true

      iex> ElixirOntologies.Extractors.Comprehension.bitstring_generator?({:<-, [], [{:x, [], nil}, [1]]})
      false
  """
  @spec bitstring_generator?(Macro.t()) :: boolean()
  def bitstring_generator?({:<<>>, _meta, [{:<-, _arrow_meta, [_pattern, _binary]}]}), do: true
  def bitstring_generator?(_), do: false

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a for comprehension from an AST node.

  Returns `{:ok, %Comprehension{}}` on success, or `{:error, reason}` if the
  node is not a for comprehension.

  ## Examples

      iex> ast = {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2, 3]]}, [do: {:x, [], nil}]]}
      iex> {:ok, result} = ElixirOntologies.Extractors.Comprehension.extract(ast)
      iex> result.type
      :for
      iex> length(result.generators)
      1
      iex> result.body
      {:x, [], nil}

      iex> {:error, _} = ElixirOntologies.Extractors.Comprehension.extract({:if, [], [true]})
  """
  @spec extract(Macro.t()) :: {:ok, t()} | {:error, String.t()}
  def extract({:for, _meta, args} = node) when is_list(args) do
    {generators, filters, opts} = parse_comprehension_args(args)
    {body, options} = extract_body_and_options(opts)

    result = %__MODULE__{
      type: :for,
      generators: generators,
      filters: filters,
      body: body,
      options: options,
      location: Helpers.extract_location(node),
      metadata: %{
        generator_count: length(generators),
        filter_count: length(filters),
        has_into: options.into != nil,
        has_reduce: options.reduce != nil,
        has_uniq: options.uniq
      }
    }

    {:ok, result}
  end

  def extract(node) do
    {:error, Helpers.format_error("Not a for comprehension", node)}
  end

  @doc """
  Extracts a for comprehension, raising on error.

  ## Examples

      iex> ast = {:for, [], [{:<-, [], [{:x, [], nil}, [1, 2]]}, [do: {:*, [], [{:x, [], nil}, 2]}]]}
      iex> result = ElixirOntologies.Extractors.Comprehension.extract!(ast)
      iex> result.type
      :for
  """
  @spec extract!(Macro.t()) :: t()
  def extract!(node) do
    case extract(node) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ===========================================================================
  # Generator Extraction
  # ===========================================================================

  @doc """
  Extracts a generator from an AST node.

  ## Examples

      iex> ast = {:<-, [], [{:x, [], nil}, [1, 2, 3]]}
      iex> gen = ElixirOntologies.Extractors.Comprehension.extract_generator(ast)
      iex> gen.type
      :generator
      iex> gen.pattern
      {:x, [], nil}
      iex> gen.enumerable
      [1, 2, 3]
  """
  @spec extract_generator(Macro.t()) :: generator()
  def extract_generator({:<-, _meta, [pattern, enumerable]} = node) do
    %{
      type: :generator,
      pattern: pattern,
      enumerable: enumerable,
      location: Helpers.extract_location(node)
    }
  end

  @doc """
  Extracts a bitstring generator from an AST node.

  ## Examples

      iex> ast = {:<<>>, [], [{:<-, [], [{:c, [], nil}, "hello"]}]}
      iex> gen = ElixirOntologies.Extractors.Comprehension.extract_bitstring_generator(ast)
      iex> gen.type
      :bitstring_generator
      iex> gen.pattern
      {:c, [], nil}
      iex> gen.enumerable
      "hello"
  """
  @spec extract_bitstring_generator(Macro.t()) :: generator()
  def extract_bitstring_generator({:<<>>, _meta, [{:<-, _arrow_meta, [pattern, binary]}]} = node) do
    %{
      type: :bitstring_generator,
      pattern: pattern,
      enumerable: binary,
      location: Helpers.extract_location(node)
    }
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Returns true if the comprehension has an `:into` option.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Comprehension
      iex> comp = %Comprehension{type: :for, options: %{into: {:%{}, [], []}, reduce: nil, uniq: false}}
      iex> Comprehension.has_into?(comp)
      true

      iex> alias ElixirOntologies.Extractors.Comprehension
      iex> comp = %Comprehension{type: :for, options: %{into: nil, reduce: nil, uniq: false}}
      iex> Comprehension.has_into?(comp)
      false
  """
  @spec has_into?(t()) :: boolean()
  def has_into?(%__MODULE__{options: %{into: into}}), do: into != nil
  def has_into?(_), do: false

  @doc """
  Returns true if the comprehension has a `:reduce` option.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Comprehension
      iex> comp = %Comprehension{type: :for, options: %{into: nil, reduce: 0, uniq: false}}
      iex> Comprehension.has_reduce?(comp)
      true

      iex> alias ElixirOntologies.Extractors.Comprehension
      iex> comp = %Comprehension{type: :for, options: %{into: nil, reduce: nil, uniq: false}}
      iex> Comprehension.has_reduce?(comp)
      false
  """
  @spec has_reduce?(t()) :: boolean()
  def has_reduce?(%__MODULE__{options: %{reduce: reduce}}), do: reduce != nil
  def has_reduce?(_), do: false

  @doc """
  Returns true if the comprehension has the `:uniq` option set to true.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Comprehension
      iex> comp = %Comprehension{type: :for, options: %{into: nil, reduce: nil, uniq: true}}
      iex> Comprehension.has_uniq?(comp)
      true
  """
  @spec has_uniq?(t()) :: boolean()
  def has_uniq?(%__MODULE__{options: %{uniq: uniq}}), do: uniq == true
  def has_uniq?(_), do: false

  @doc """
  Returns the list of all patterns bound in the comprehension's generators.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Comprehension
      iex> gen1 = %{type: :generator, pattern: {:x, [], nil}, enumerable: [1], location: nil}
      iex> gen2 = %{type: :generator, pattern: {:y, [], nil}, enumerable: [2], location: nil}
      iex> comp = %Comprehension{type: :for, generators: [gen1, gen2]}
      iex> Comprehension.generator_patterns(comp)
      [{:x, [], nil}, {:y, [], nil}]
  """
  @spec generator_patterns(t()) :: [Macro.t()]
  def generator_patterns(%__MODULE__{generators: generators}) do
    Enum.map(generators, & &1.pattern)
  end

  def generator_patterns(_), do: []

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Parse comprehension arguments into generators, filters, and options
  defp parse_comprehension_args(args) do
    {generators, filters, opts} =
      Enum.reduce(args, {[], [], []}, fn arg, {gens, filts, opts} ->
        cond do
          # Keyword list (options including :do, :into, :reduce, :uniq)
          is_list(arg) and Keyword.keyword?(arg) ->
            {gens, filts, opts ++ [arg]}

          # Regular generator: pattern <- enumerable
          generator?(arg) ->
            gen = extract_generator(arg)
            {gens ++ [gen], filts, opts}

          # Bitstring generator: <<pattern <- binary>>
          bitstring_generator?(arg) ->
            gen = extract_bitstring_generator(arg)
            {gens ++ [gen], filts, opts}

          # Filter expression (anything else)
          true ->
            {gens, filts ++ [arg], opts}
        end
      end)

    # Flatten options lists
    flat_opts = List.flatten(opts)
    {generators, filters, flat_opts}
  end

  # Extract body and options from keyword list
  defp extract_body_and_options(opts) do
    # Handle reduce comprehension which has clauses instead of simple body
    body = extract_body(opts)
    into = Keyword.get(opts, :into)
    reduce = Keyword.get(opts, :reduce)
    uniq = Keyword.get(opts, :uniq, false)

    options = %{
      into: into,
      reduce: reduce,
      uniq: uniq
    }

    {body, options}
  end

  # Extract body from options - handles both simple :do and reduce clauses
  defp extract_body(opts) do
    case Keyword.get(opts, :do) do
      # Reduce comprehension has clauses in :do
      [_ | _] = clauses ->
        # Check if it's arrow clauses (reduce) or just a list body
        case hd(clauses) do
          {:->, _, _} -> clauses
          _ -> clauses
        end

      # Simple body expression
      body ->
        body
    end
  end
end
