defmodule ElixirOntologies.Extractors.OTP.ETS do
  @moduledoc """
  Extracts ETS (Erlang Term Storage) table definitions from module AST nodes.

  This module analyzes Elixir AST nodes to detect `:ets.new/2` calls and
  extract table configuration including:
  - Table name
  - Table type (set, ordered_set, bag, duplicate_bag)
  - Access type (public, protected, private)
  - Concurrency options (read_concurrency, write_concurrency)
  - Named table and compression settings

  Supports the OTP-related classes from elixir-otp.ttl for ETS constructs.

  ## Detection

  ETS table creation is detected via `:ets.new/2` calls:

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> code = ":ets.new(:my_table, [:set, :public])"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> ETS.ets_new?(ast)
      true

  ## Extracting Table Details

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> code = ":ets.new(:cache, [:set, :named_table, :public])"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, table} = ETS.extract(ast)
      iex> table.name
      :cache
      iex> table.table_type
      :set
      iex> table.access_type
      :public
      iex> table.named_table
      true
  """

  alias ElixirOntologies.Extractors.Helpers

  # ===========================================================================
  # ETSTable Struct
  # ===========================================================================

  defmodule ETSTable do
    @moduledoc """
    Represents an extracted ETS table definition.

    ## Table Types

    - `:set` - Unique keys, one value per key (default)
    - `:ordered_set` - Unique keys, ordered by key
    - `:bag` - Multiple objects per key, but no duplicates
    - `:duplicate_bag` - Multiple identical objects per key allowed

    ## Access Types

    - `:protected` - Owner can read/write, others can read (default)
    - `:public` - Any process can read/write
    - `:private` - Only owner can read/write

    ## Fields

    - `:name` - Table name (atom or nil for unnamed tables)
    - `:table_type` - Type of table (:set, :ordered_set, :bag, :duplicate_bag)
    - `:access_type` - Access permissions (:public, :protected, :private)
    - `:named_table` - Whether the table is named (accessible by name)
    - `:read_concurrency` - Optimized for concurrent reads
    - `:write_concurrency` - Optimized for concurrent writes
    - `:compressed` - Whether data is stored compressed
    - `:heir` - Heir process for table ownership transfer
    - `:location` - Source location of the :ets.new call
    - `:metadata` - Additional information
    """

    @type table_type :: :set | :ordered_set | :bag | :duplicate_bag
    @type access_type :: :public | :protected | :private

    @type t :: %__MODULE__{
            name: atom() | nil,
            table_type: table_type(),
            access_type: access_type(),
            named_table: boolean(),
            read_concurrency: boolean(),
            write_concurrency: boolean(),
            compressed: boolean(),
            heir: term() | nil,
            location: ElixirOntologies.Analyzer.Location.SourceLocation.t() | nil,
            metadata: map()
          }

    defstruct [
      name: nil,
      table_type: :set,
      access_type: :protected,
      named_table: false,
      read_concurrency: false,
      write_concurrency: false,
      compressed: false,
      heir: nil,
      location: nil,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Detection
  # ===========================================================================

  @doc """
  Checks if an AST node contains ETS table creation.

  Returns true if the AST contains an `:ets.new/2` call.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> code = ":ets.new(:table, [:set])"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> ETS.has_ets?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> code = "defmodule M do def foo, do: :ok end"
      iex> {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      iex> ETS.has_ets?(body)
      false
  """
  @spec has_ets?(Macro.t()) :: boolean()
  def has_ets?(body) do
    statements = Helpers.normalize_body(body)
    has_ets_new?(statements)
  end

  @doc """
  Checks if a single AST node is an `:ets.new/2` call.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> code = ":ets.new(:table, [:set])"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> ETS.ets_new?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> code = ":ets.lookup(:table, :key)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> ETS.ets_new?(ast)
      false
  """
  @spec ets_new?(Macro.t()) :: boolean()
  def ets_new?({{:., _, [:ets, :new]}, _, [_name, _opts]}), do: true
  def ets_new?(_), do: false

  @doc """
  Checks if a single AST node is any `:ets.*` call.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> code = ":ets.lookup(:table, :key)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> ETS.ets_call?(ast)
      true

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> code = "GenServer.call(pid, :msg)"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> ETS.ets_call?(ast)
      false
  """
  @spec ets_call?(Macro.t()) :: boolean()
  def ets_call?({{:., _, [:ets, _func]}, _, _args}), do: true
  def ets_call?(_), do: false

  # ===========================================================================
  # Extraction
  # ===========================================================================

  @doc """
  Extracts ETS table definitions from an AST node.

  Returns `{:ok, [tables]}` with all ETS tables found, or `{:error, reason}` if none.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> code = ":ets.new(:cache, [:set, :public])"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, table} = ETS.extract(ast)
      iex> table.name
      :cache
      iex> table.table_type
      :set
      iex> table.access_type
      :public

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> code = ":ets.new(:data, [:ordered_set, :named_table])"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> {:ok, table} = ETS.extract(ast)
      iex> table.table_type
      :ordered_set
      iex> table.named_table
      true
  """
  @spec extract(Macro.t(), keyword()) :: {:ok, ETSTable.t()} | {:ok, [ETSTable.t()]} | {:error, String.t()}
  def extract(body, opts \\ []) do
    statements = Helpers.normalize_body(body)
    tables = find_ets_tables(statements, opts)

    case tables do
      [] -> {:error, "No ETS tables found"}
      [single] -> {:ok, single}
      multiple -> {:ok, multiple}
    end
  end

  @doc """
  Extracts all ETS table definitions from an AST node.

  Always returns a list (possibly empty).

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> code = ":ets.new(:t1, [:set])"
      iex> {:ok, ast} = Code.string_to_quoted(code)
      iex> tables = ETS.extract_all(ast)
      iex> length(tables)
      1
  """
  @spec extract_all(Macro.t(), keyword()) :: [ETSTable.t()]
  def extract_all(body, opts \\ []) do
    statements = Helpers.normalize_body(body)
    find_ets_tables(statements, opts)
  end

  # ===========================================================================
  # Table Type Helpers
  # ===========================================================================

  @doc """
  Checks if a table is a set type.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> alias ElixirOntologies.Extractors.OTP.ETS.ETSTable
      iex> ETS.set?(%ETSTable{table_type: :set})
      true

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> alias ElixirOntologies.Extractors.OTP.ETS.ETSTable
      iex> ETS.set?(%ETSTable{table_type: :bag})
      false
  """
  @spec set?(ETSTable.t()) :: boolean()
  def set?(%ETSTable{table_type: :set}), do: true
  def set?(_), do: false

  @doc """
  Checks if a table is an ordered_set type.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> alias ElixirOntologies.Extractors.OTP.ETS.ETSTable
      iex> ETS.ordered_set?(%ETSTable{table_type: :ordered_set})
      true
  """
  @spec ordered_set?(ETSTable.t()) :: boolean()
  def ordered_set?(%ETSTable{table_type: :ordered_set}), do: true
  def ordered_set?(_), do: false

  @doc """
  Checks if a table is a bag type.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> alias ElixirOntologies.Extractors.OTP.ETS.ETSTable
      iex> ETS.bag?(%ETSTable{table_type: :bag})
      true
  """
  @spec bag?(ETSTable.t()) :: boolean()
  def bag?(%ETSTable{table_type: :bag}), do: true
  def bag?(_), do: false

  @doc """
  Checks if a table is a duplicate_bag type.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> alias ElixirOntologies.Extractors.OTP.ETS.ETSTable
      iex> ETS.duplicate_bag?(%ETSTable{table_type: :duplicate_bag})
      true
  """
  @spec duplicate_bag?(ETSTable.t()) :: boolean()
  def duplicate_bag?(%ETSTable{table_type: :duplicate_bag}), do: true
  def duplicate_bag?(_), do: false

  # ===========================================================================
  # Access Type Helpers
  # ===========================================================================

  @doc """
  Checks if a table has public access.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> alias ElixirOntologies.Extractors.OTP.ETS.ETSTable
      iex> ETS.public?(%ETSTable{access_type: :public})
      true
  """
  @spec public?(ETSTable.t()) :: boolean()
  def public?(%ETSTable{access_type: :public}), do: true
  def public?(_), do: false

  @doc """
  Checks if a table has protected access.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> alias ElixirOntologies.Extractors.OTP.ETS.ETSTable
      iex> ETS.protected?(%ETSTable{access_type: :protected})
      true
  """
  @spec protected?(ETSTable.t()) :: boolean()
  def protected?(%ETSTable{access_type: :protected}), do: true
  def protected?(_), do: false

  @doc """
  Checks if a table has private access.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> alias ElixirOntologies.Extractors.OTP.ETS.ETSTable
      iex> ETS.private?(%ETSTable{access_type: :private})
      true
  """
  @spec private?(ETSTable.t()) :: boolean()
  def private?(%ETSTable{access_type: :private}), do: true
  def private?(_), do: false

  # ===========================================================================
  # Concurrency Helpers
  # ===========================================================================

  @doc """
  Checks if a table has read_concurrency enabled.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> alias ElixirOntologies.Extractors.OTP.ETS.ETSTable
      iex> ETS.read_concurrent?(%ETSTable{read_concurrency: true})
      true
  """
  @spec read_concurrent?(ETSTable.t()) :: boolean()
  def read_concurrent?(%ETSTable{read_concurrency: true}), do: true
  def read_concurrent?(_), do: false

  @doc """
  Checks if a table has write_concurrency enabled.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> alias ElixirOntologies.Extractors.OTP.ETS.ETSTable
      iex> ETS.write_concurrent?(%ETSTable{write_concurrency: true})
      true
  """
  @spec write_concurrent?(ETSTable.t()) :: boolean()
  def write_concurrent?(%ETSTable{write_concurrency: true}), do: true
  def write_concurrent?(_), do: false

  @doc """
  Returns the OTP behaviour type for this extractor.

  ## Examples

      iex> alias ElixirOntologies.Extractors.OTP.ETS
      iex> ETS.otp_behaviour()
      :ets
  """
  @spec otp_behaviour() :: :ets
  def otp_behaviour, do: :ets

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp has_ets_new?(statements) do
    find_ets_tables(statements, []) != []
  end

  defp find_ets_tables(statements, opts) do
    statements
    |> Enum.flat_map(&find_ets_in_statement(&1, opts))
    |> Enum.filter(&(&1 != nil))
  end

  defp find_ets_in_statement({{:., _, [:ets, :new]}, meta, [name, options]} = _ast, opts) do
    [parse_ets_new(name, options, meta, opts)]
  end

  defp find_ets_in_statement({:def, _, [_, body]}, opts) do
    find_ets_in_body(body, opts)
  end

  defp find_ets_in_statement({:defp, _, [_, body]}, opts) do
    find_ets_in_body(body, opts)
  end

  defp find_ets_in_statement({:__block__, _, statements}, opts) do
    Enum.flat_map(statements, &find_ets_in_statement(&1, opts))
  end

  defp find_ets_in_statement({:=, _, [_lhs, rhs]}, opts) do
    find_ets_in_statement(rhs, opts)
  end

  defp find_ets_in_statement(_, _opts), do: []

  defp find_ets_in_body([do: body], opts), do: find_ets_in_statement(body, opts)
  defp find_ets_in_body({:__block__, _, statements}, opts) do
    Enum.flat_map(statements, &find_ets_in_statement(&1, opts))
  end
  defp find_ets_in_body(body, opts), do: find_ets_in_statement(body, opts)

  defp parse_ets_new(name, options, meta, opts) do
    table_name = extract_table_name(name)
    parsed_opts = parse_options(options)
    location = extract_location(meta, opts)

    %ETSTable{
      name: table_name,
      table_type: parsed_opts.table_type,
      access_type: parsed_opts.access_type,
      named_table: parsed_opts.named_table,
      read_concurrency: parsed_opts.read_concurrency,
      write_concurrency: parsed_opts.write_concurrency,
      compressed: parsed_opts.compressed,
      heir: parsed_opts.heir,
      location: location,
      metadata: %{
        raw_options: options,
        has_concurrency_opts: parsed_opts.read_concurrency or parsed_opts.write_concurrency
      }
    }
  end

  defp extract_table_name(name) when is_atom(name), do: name
  defp extract_table_name({:__aliases__, _, parts}), do: Module.concat(parts)
  defp extract_table_name(_), do: nil

  defp parse_options(options) when is_list(options) do
    %{
      table_type: extract_table_type(options),
      access_type: extract_access_type(options),
      named_table: :named_table in options,
      read_concurrency: extract_keyword_bool(options, :read_concurrency),
      write_concurrency: extract_keyword_bool(options, :write_concurrency),
      compressed: :compressed in options,
      heir: extract_heir_option(options)
    }
  end

  defp parse_options(_), do: %{
    table_type: :set,
    access_type: :protected,
    named_table: false,
    read_concurrency: false,
    write_concurrency: false,
    compressed: false,
    heir: nil
  }

  defp extract_table_type(options) do
    cond do
      :ordered_set in options -> :ordered_set
      :duplicate_bag in options -> :duplicate_bag
      :bag in options -> :bag
      :set in options -> :set
      true -> :set  # default
    end
  end

  defp extract_access_type(options) do
    cond do
      :public in options -> :public
      :private in options -> :private
      :protected in options -> :protected
      true -> :protected  # default
    end
  end

  defp extract_keyword_bool(options, key) do
    case Keyword.get(options, key) do
      true -> true
      :auto -> true
      _ -> false
    end
  end

  defp extract_heir_option(options) do
    # heir is specified as {:heir, pid, data} - a 3-tuple, not keyword format
    Enum.find_value(options, fn
      {:heir, pid, data} -> {pid, data}
      # Handle AST 3-tuple format {:{}, meta, [:heir, pid, data]}
      {:{}, _, [:heir, pid, data]} -> {pid, data}
      # Handle {:heir, :none} format
      {:heir, :none} -> :none
      {:{}, _, [:heir, :none]} -> :none
      _ -> nil
    end)
  end

  defp extract_location(meta, opts) do
    case {Keyword.get(meta, :line), Keyword.get(meta, :column)} do
      {nil, _} -> Helpers.extract_location_if(nil, opts)
      {line, column} ->
        %ElixirOntologies.Analyzer.Location.SourceLocation{
          start_line: line,
          start_column: column || 1
        }
    end
  end
end
