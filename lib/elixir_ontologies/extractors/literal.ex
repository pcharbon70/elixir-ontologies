defmodule ElixirOntologies.Extractors.Literal do
  @moduledoc """
  Extracts literal values from AST nodes.

  This module analyzes Elixir AST nodes representing literals and extracts their
  values along with type classification and metadata. Supports all 12 literal types
  defined in the elixir-core.ttl ontology:

  - Atoms (`:ok`, `:error`, `true`, `false`, `nil`)
  - Integers (`42`, `0xFF`, `0b1010`)
  - Floats (`3.14`, `1.0e10`)
  - Strings (`"hello"`, with or without interpolation)
  - Lists (`[1, 2, 3]`, including cons cells)
  - Tuples (`{:ok, value}`)
  - Maps (`%{key: value}`)
  - Keyword Lists (`[name: "John", age: 30]`)
  - Binaries (`<<1, 2, 3>>`)
  - Charlists (`~c"hello"`)
  - Sigils (`~r/pattern/i`, `~s(string)`, `~w(words)`)
  - Ranges (`1..10`, `1..10//2`)

  ## Usage

      iex> alias ElixirOntologies.Extractors.Literal
      iex> {:ok, result} = Literal.extract(:ok)
      iex> result.type
      :atom
      iex> result.value
      :ok

      iex> alias ElixirOntologies.Extractors.Literal
      iex> {:ok, result} = Literal.extract({:.., [], [1, 10]})
      iex> result.type
      :range
      iex> result.metadata.range_start
      1
      iex> result.metadata.range_end
      10
  """

  alias ElixirOntologies.Analyzer.Location

  # ===========================================================================
  # Result Struct
  # ===========================================================================

  @typedoc """
  The result of literal extraction.

  - `:type` - The literal type classification
  - `:value` - The extracted value (or structural representation for complex types)
  - `:location` - Source location if available from AST metadata
  - `:metadata` - Type-specific additional information
  """
  @type t :: %__MODULE__{
          type: literal_type(),
          value: term(),
          location: Location.SourceLocation.t() | nil,
          metadata: map()
        }

  @type literal_type ::
          :atom
          | :integer
          | :float
          | :string
          | :list
          | :tuple
          | :map
          | :keyword_list
          | :binary
          | :charlist
          | :sigil
          | :range

  defstruct [:type, :value, :location, metadata: %{}]

  # ===========================================================================
  # Type Detection
  # ===========================================================================

  @doc """
  Checks if an AST node represents a literal value.

  Returns `true` for atoms, integers, floats, strings, lists, tuples, maps,
  keyword lists, binaries, charlists, sigils, and ranges.

  ## Examples

      iex> ElixirOntologies.Extractors.Literal.literal?(:ok)
      true

      iex> ElixirOntologies.Extractors.Literal.literal?(42)
      true

      iex> ElixirOntologies.Extractors.Literal.literal?({:%{}, [], [a: 1]})
      true

      iex> ElixirOntologies.Extractors.Literal.literal?({:.., [], [1, 10]})
      true

      iex> ElixirOntologies.Extractors.Literal.literal?({:def, [], [{:foo, [], nil}]})
      false
  """
  @spec literal?(Macro.t()) :: boolean()
  def literal?(node), do: literal_type(node) != nil

  @doc """
  Returns the literal type of an AST node, or `nil` if not a literal.

  ## Examples

      iex> ElixirOntologies.Extractors.Literal.literal_type(:ok)
      :atom

      iex> ElixirOntologies.Extractors.Literal.literal_type(42)
      :integer

      iex> ElixirOntologies.Extractors.Literal.literal_type(3.14)
      :float

      iex> ElixirOntologies.Extractors.Literal.literal_type("hello")
      :string

      iex> ElixirOntologies.Extractors.Literal.literal_type([1, 2, 3])
      :list

      iex> ElixirOntologies.Extractors.Literal.literal_type([name: "John"])
      :keyword_list

      iex> ElixirOntologies.Extractors.Literal.literal_type({1, 2})
      :tuple

      iex> ElixirOntologies.Extractors.Literal.literal_type({:%{}, [], [a: 1]})
      :map

      iex> ElixirOntologies.Extractors.Literal.literal_type({:sigil_r, [], [{:<<>>, [], ["pattern"]}, []]})
      :sigil

      iex> ElixirOntologies.Extractors.Literal.literal_type({:sigil_c, [], [{:<<>>, [], ["hello"]}, []]})
      :charlist

      iex> ElixirOntologies.Extractors.Literal.literal_type({:.., [], [1, 10]})
      :range

      iex> ElixirOntologies.Extractors.Literal.literal_type({:..//, [], [1, 10, 2]})
      :range

      iex> ElixirOntologies.Extractors.Literal.literal_type({:def, [], [{:foo, [], nil}]})
      nil
  """
  @spec literal_type(Macro.t()) :: literal_type() | nil
  def literal_type(node) do
    cond do
      is_atom(node) -> :atom
      is_integer(node) -> :integer
      is_float(node) -> :float
      is_binary(node) -> :string
      charlist_ast?(node) -> :charlist
      sigil_ast?(node) -> :sigil
      range_ast?(node) -> :range
      map_ast?(node) -> :map
      binary_ast?(node) -> :binary
      interpolated_string_ast?(node) -> :string
      keyword_list?(node) -> :keyword_list
      is_list(node) -> :list
      simple_tuple?(node) -> :tuple
      true -> nil
    end
  end

  # ===========================================================================
  # Main Extraction
  # ===========================================================================

  @doc """
  Extracts a literal from an AST node.

  Returns `{:ok, %Literal{}}` on success, or `{:error, reason}` if the node
  is not a recognized literal type.

  ## Examples

      iex> {:ok, result} = ElixirOntologies.Extractors.Literal.extract(:ok)
      iex> result.type
      :atom
      iex> result.value
      :ok

      iex> {:ok, result} = ElixirOntologies.Extractors.Literal.extract(42)
      iex> result.type
      :integer

      iex> {:ok, result} = ElixirOntologies.Extractors.Literal.extract([a: 1, b: 2])
      iex> result.type
      :keyword_list

      iex> {:error, _} = ElixirOntologies.Extractors.Literal.extract({:def, [], nil})
  """
  @spec extract(Macro.t()) :: {:ok, t()} | {:error, String.t()}
  def extract(node) do
    case literal_type(node) do
      nil -> {:error, "Not a literal: #{inspect(node)}"}
      :atom -> {:ok, extract_atom(node)}
      :integer -> {:ok, extract_integer(node)}
      :float -> {:ok, extract_float(node)}
      :string -> {:ok, extract_string(node)}
      :list -> {:ok, extract_list(node)}
      :tuple -> {:ok, extract_tuple(node)}
      :map -> {:ok, extract_map(node)}
      :keyword_list -> {:ok, extract_keyword_list(node)}
      :binary -> {:ok, extract_binary(node)}
      :charlist -> {:ok, extract_charlist(node)}
      :sigil -> {:ok, extract_sigil(node)}
      :range -> {:ok, extract_range(node)}
    end
  end

  @doc """
  Extracts a literal from an AST node, raising on error.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Literal.extract!(:ok)
      iex> result.type
      :atom
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
  Extracts an atom literal.

  Handles special atoms like `true`, `false`, and `nil` with appropriate metadata.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Literal.extract_atom(:ok)
      iex> result.value
      :ok
      iex> result.metadata.special_atom
      false

      iex> result = ElixirOntologies.Extractors.Literal.extract_atom(true)
      iex> result.metadata.special_atom
      true
      iex> result.metadata.atom_kind
      :boolean

      iex> result = ElixirOntologies.Extractors.Literal.extract_atom(nil)
      iex> result.metadata.atom_kind
      :nil
  """
  @spec extract_atom(atom()) :: t()
  def extract_atom(atom) when is_atom(atom) do
    %__MODULE__{
      type: :atom,
      value: atom,
      location: nil,
      metadata: atom_metadata(atom)
    }
  end

  @doc """
  Extracts an integer literal.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Literal.extract_integer(42)
      iex> result.value
      42

      iex> result = ElixirOntologies.Extractors.Literal.extract_integer(-100)
      iex> result.value
      -100
  """
  @spec extract_integer(integer()) :: t()
  def extract_integer(int) when is_integer(int) do
    %__MODULE__{
      type: :integer,
      value: int,
      location: nil,
      metadata: %{}
    }
  end

  @doc """
  Extracts a float literal.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Literal.extract_float(3.14)
      iex> result.value
      3.14

      iex> result = ElixirOntologies.Extractors.Literal.extract_float(1.0e10)
      iex> result.value
      1.0e10
  """
  @spec extract_float(float()) :: t()
  def extract_float(float) when is_float(float) do
    %__MODULE__{
      type: :float,
      value: float,
      location: nil,
      metadata: %{}
    }
  end

  @doc """
  Extracts a string literal.

  Handles both simple strings and strings with interpolation.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Literal.extract_string("hello")
      iex> result.value
      "hello"
      iex> result.metadata.interpolated
      false

      iex> ast = {:<<>>, [], ["hello ", {:"::", [], [{{:., [], [Kernel, :to_string]}, [from_interpolation: true], [{:world, [], Elixir}]}, {:binary, [], Elixir}]}]}
      iex> result = ElixirOntologies.Extractors.Literal.extract_string(ast)
      iex> result.metadata.interpolated
      true
  """
  @spec extract_string(binary() | tuple()) :: t()
  def extract_string(string) when is_binary(string) do
    %__MODULE__{
      type: :string,
      value: string,
      location: nil,
      metadata: %{interpolated: false}
    }
  end

  def extract_string({:<<>>, meta, parts} = ast) do
    location = extract_location(meta)

    %__MODULE__{
      type: :string,
      value: ast,
      location: location,
      metadata: %{
        interpolated: has_interpolation?(parts),
        parts: parts
      }
    }
  end

  @doc """
  Extracts a list literal.

  Handles both regular lists and cons cell notation.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Literal.extract_list([1, 2, 3])
      iex> result.value
      [1, 2, 3]
      iex> result.metadata.cons_cell
      false

      iex> result = ElixirOntologies.Extractors.Literal.extract_list([{:|, [], [1, {:rest, [], Elixir}]}])
      iex> result.metadata.cons_cell
      true
  """
  @spec extract_list(list()) :: t()
  def extract_list(list) when is_list(list) do
    has_cons = has_cons_cell?(list)

    %__MODULE__{
      type: :list,
      value: list,
      location: nil,
      metadata: %{
        cons_cell: has_cons,
        length: if(has_cons, do: nil, else: length(list))
      }
    }
  end

  @doc """
  Extracts a tuple literal.

  Handles both 2-element tuples (which quote as themselves) and larger tuples
  which are represented as `{:{}, meta, elements}` in AST form.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Literal.extract_tuple({1, 2})
      iex> result.value
      {1, 2}
      iex> result.metadata.size
      2

      iex> result = ElixirOntologies.Extractors.Literal.extract_tuple({:ok, {:value, [], Elixir}})
      iex> result.metadata.size
      2

      iex> result = ElixirOntologies.Extractors.Literal.extract_tuple({:{}, [], [1, 2, 3, 4]})
      iex> result.metadata.size
      4
  """
  @spec extract_tuple(tuple()) :: t()
  def extract_tuple({:{}, meta, elements}) when is_list(elements) do
    location = extract_location(meta)

    %__MODULE__{
      type: :tuple,
      value: List.to_tuple(elements),
      location: location,
      metadata: %{size: length(elements), ast_form: :explicit}
    }
  end

  def extract_tuple(tuple) when is_tuple(tuple) do
    %__MODULE__{
      type: :tuple,
      value: tuple,
      location: nil,
      metadata: %{size: tuple_size(tuple), ast_form: :implicit}
    }
  end

  @doc """
  Extracts a map literal.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Literal.extract_map({:%{}, [], [a: 1, b: 2]})
      iex> result.metadata.key_types
      [:atom]

      iex> result = ElixirOntologies.Extractors.Literal.extract_map({:%{}, [], [{"key", "value"}]})
      iex> result.metadata.key_types
      [:string]
  """
  @spec extract_map(tuple()) :: t()
  def extract_map({:%{}, meta, pairs}) do
    location = extract_location(meta)
    key_types = analyze_map_keys(pairs)

    %__MODULE__{
      type: :map,
      value: pairs,
      location: location,
      metadata: %{
        pair_count: length(pairs),
        key_types: key_types
      }
    }
  end

  @doc """
  Extracts a keyword list literal.

  A keyword list is a list of 2-tuples where the first element is always an atom.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Literal.extract_keyword_list([name: "John", age: 30])
      iex> result.value
      [name: "John", age: 30]
      iex> result.metadata.keys
      [:name, :age]
  """
  @spec extract_keyword_list(list()) :: t()
  def extract_keyword_list(list) when is_list(list) do
    keys = Keyword.keys(list)

    %__MODULE__{
      type: :keyword_list,
      value: list,
      location: nil,
      metadata: %{
        keys: keys,
        length: length(list)
      }
    }
  end

  @doc """
  Extracts a binary/bitstring literal.

  ## Examples

      iex> result = ElixirOntologies.Extractors.Literal.extract_binary({:<<>>, [], [1, 2, 3]})
      iex> result.metadata.segments
      [1, 2, 3]
  """
  @spec extract_binary(tuple()) :: t()
  def extract_binary({:<<>>, meta, segments}) do
    location = extract_location(meta)

    %__MODULE__{
      type: :binary,
      value: segments,
      location: location,
      metadata: %{
        segments: segments,
        has_size_specs: has_size_specs?(segments)
      }
    }
  end

  @doc """
  Extracts a charlist literal (sigil_c).

  ## Examples

      iex> ast = {:sigil_c, [delimiter: "\\""], [{:<<>>, [], ["hello"]}, []]}
      iex> result = ElixirOntologies.Extractors.Literal.extract_charlist(ast)
      iex> result.metadata.content
      "hello"
  """
  @spec extract_charlist(tuple()) :: t()
  def extract_charlist({:sigil_c, meta, [{:<<>>, _, [content]}, modifiers]})
      when is_binary(content) do
    location = extract_location(meta)

    %__MODULE__{
      type: :charlist,
      value: String.to_charlist(content),
      location: location,
      metadata: %{
        content: content,
        modifiers: modifiers,
        delimiter: Keyword.get(meta, :delimiter)
      }
    }
  end

  def extract_charlist({:sigil_c, meta, [{:<<>>, _, parts}, modifiers]}) do
    location = extract_location(meta)

    %__MODULE__{
      type: :charlist,
      value: parts,
      location: location,
      metadata: %{
        content: parts,
        modifiers: modifiers,
        delimiter: Keyword.get(meta, :delimiter),
        interpolated: true
      }
    }
  end

  @doc """
  Extracts a sigil literal.

  Handles all built-in and custom sigils.

  ## Examples

      iex> ast = {:sigil_r, [delimiter: "/"], [{:<<>>, [], ["pattern"]}, []]}
      iex> result = ElixirOntologies.Extractors.Literal.extract_sigil(ast)
      iex> result.metadata.sigil_char
      "r"
      iex> result.metadata.content
      "pattern"
      iex> result.metadata.modifiers
      []

      iex> ast = {:sigil_r, [delimiter: "/"], [{:<<>>, [], ["pattern"]}, ~c"i"]}
      iex> result = ElixirOntologies.Extractors.Literal.extract_sigil(ast)
      iex> result.metadata.modifiers
      ~c"i"
  """
  @spec extract_sigil(tuple()) :: t()
  def extract_sigil({sigil_name, meta, [{:<<>>, _, [content]}, modifiers]})
      when is_atom(sigil_name) and is_binary(content) do
    location = extract_location(meta)
    sigil_char = extract_sigil_char(sigil_name)

    %__MODULE__{
      type: :sigil,
      value: {sigil_char, content, modifiers},
      location: location,
      metadata: %{
        sigil_char: sigil_char,
        content: content,
        modifiers: modifiers,
        delimiter: Keyword.get(meta, :delimiter)
      }
    }
  end

  def extract_sigil({sigil_name, meta, [{:<<>>, _, parts}, modifiers]})
      when is_atom(sigil_name) do
    location = extract_location(meta)
    sigil_char = extract_sigil_char(sigil_name)

    %__MODULE__{
      type: :sigil,
      value: {sigil_char, parts, modifiers},
      location: location,
      metadata: %{
        sigil_char: sigil_char,
        content: parts,
        modifiers: modifiers,
        delimiter: Keyword.get(meta, :delimiter),
        interpolated: true
      }
    }
  end

  @doc """
  Extracts a range literal.

  Handles both simple ranges (1..10) and ranges with steps (1..10//2).

  ## Examples

      iex> ast = {:.., [], [1, 10]}
      iex> result = ElixirOntologies.Extractors.Literal.extract_range(ast)
      iex> result.metadata.range_start
      1
      iex> result.metadata.range_end
      10
      iex> result.metadata.range_step
      nil

      iex> ast = {:..//, [], [1, 10, 2]}
      iex> result = ElixirOntologies.Extractors.Literal.extract_range(ast)
      iex> result.metadata.range_step
      2
  """
  @spec extract_range(tuple()) :: t()
  def extract_range({:.., meta, [range_start, range_end]})
      when is_integer(range_start) and is_integer(range_end) do
    location = extract_location(meta)
    # Determine step based on direction to avoid warning
    step = if range_end >= range_start, do: 1, else: -1

    %__MODULE__{
      type: :range,
      value: Range.new(range_start, range_end, step),
      location: location,
      metadata: %{
        range_start: range_start,
        range_end: range_end,
        range_step: nil
      }
    }
  end

  def extract_range({:.., meta, [range_start, range_end]}) do
    # Non-integer range bounds (expressions) - store AST form
    location = extract_location(meta)

    %__MODULE__{
      type: :range,
      value: {:.., range_start, range_end},
      location: location,
      metadata: %{
        range_start: range_start,
        range_end: range_end,
        range_step: nil
      }
    }
  end

  def extract_range({:..//, meta, [range_start, range_end, step]})
      when is_integer(range_start) and is_integer(range_end) and is_integer(step) do
    location = extract_location(meta)

    %__MODULE__{
      type: :range,
      value: Range.new(range_start, range_end, step),
      location: location,
      metadata: %{
        range_start: range_start,
        range_end: range_end,
        range_step: step
      }
    }
  end

  def extract_range({:..//, meta, [range_start, range_end, step]}) do
    # Non-integer range bounds (expressions) - store AST form
    location = extract_location(meta)

    %__MODULE__{
      type: :range,
      value: {:..//, range_start, range_end, step},
      location: location,
      metadata: %{
        range_start: range_start,
        range_end: range_end,
        range_step: step
      }
    }
  end

  # ===========================================================================
  # Private Helpers - Type Detection
  # ===========================================================================

  defp charlist_ast?({:sigil_c, _meta, _args}), do: true
  defp charlist_ast?(_), do: false

  defp sigil_ast?({sigil_name, _meta, _args}) when is_atom(sigil_name) do
    name = Atom.to_string(sigil_name)
    String.starts_with?(name, "sigil_") and name != "sigil_c"
  end

  defp sigil_ast?(_), do: false

  defp range_ast?({:.., _meta, [_, _]}), do: true
  defp range_ast?({:..//, _meta, [_, _, _]}), do: true
  defp range_ast?(_), do: false

  defp map_ast?({:%{}, _meta, _pairs}), do: true
  defp map_ast?(_), do: false

  defp binary_ast?({:<<>>, _meta, parts}) do
    not interpolated_string_ast?({:<<>>, nil, parts})
  end

  defp binary_ast?(_), do: false

  defp interpolated_string_ast?({:<<>>, _meta, parts}) do
    has_interpolation?(parts)
  end

  defp interpolated_string_ast?(_), do: false

  defp keyword_list?(list) when is_list(list) and list != [] do
    Keyword.keyword?(list)
  end

  defp keyword_list?(_), do: false

  defp simple_tuple?({:{}, _meta, _elements}), do: true

  defp simple_tuple?(tuple) when is_tuple(tuple) do
    # Exclude 3-tuples that look like AST nodes
    case tuple do
      {atom, meta, args} when is_atom(atom) and is_list(meta) ->
        # Could be AST node - check if args is nil or a list
        not (args == nil or is_list(args))

      _ ->
        true
    end
  end

  defp simple_tuple?(_), do: false

  # ===========================================================================
  # Private Helpers - Metadata Extraction
  # ===========================================================================

  defp atom_metadata(true), do: %{special_atom: true, atom_kind: :boolean}
  defp atom_metadata(false), do: %{special_atom: true, atom_kind: :boolean}
  defp atom_metadata(nil), do: %{special_atom: true, atom_kind: :nil}
  defp atom_metadata(_), do: %{special_atom: false}

  defp has_interpolation?(parts) when is_list(parts) do
    Enum.any?(parts, fn
      {:"::", _, [{{:., _, [Kernel, :to_string]}, [{:from_interpolation, true} | _], _}, _]} ->
        true

      _ ->
        false
    end)
  end

  defp has_cons_cell?(list) when is_list(list) do
    Enum.any?(list, fn
      {:|, _, _} -> true
      _ -> false
    end)
  end

  defp analyze_map_keys(pairs) do
    pairs
    |> Enum.map(fn
      {key, _value} when is_atom(key) -> :atom
      {key, _value} when is_binary(key) -> :string
      {{key, _value}} when is_atom(key) -> :atom
      {{key, _value}} when is_binary(key) -> :string
      _ -> :other
    end)
    |> Enum.uniq()
  end

  defp has_size_specs?(segments) when is_list(segments) do
    Enum.any?(segments, fn
      {:"::", _, _} -> true
      _ -> false
    end)
  end

  defp extract_sigil_char(sigil_name) do
    sigil_name
    |> Atom.to_string()
    |> String.replace_prefix("sigil_", "")
  end

  defp extract_location(meta) when is_list(meta) do
    case Location.extract_range(meta) do
      {:ok, location} -> location
      _ -> nil
    end
  end

  defp extract_location(_), do: nil
end
