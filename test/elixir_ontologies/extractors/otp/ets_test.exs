defmodule ElixirOntologies.Extractors.OTP.ETSTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.OTP.ETS
  alias ElixirOntologies.Extractors.OTP.ETS.ETSTable

  # Run doctests
  doctest ElixirOntologies.Extractors.OTP.ETS

  # ============================================================================
  # Detection Tests
  # ============================================================================

  describe "has_ets?/1" do
    test "returns true for module with :ets.new call" do
      code = """
      defmodule Cache do
        def init do
          :ets.new(:cache, [:set, :public])
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      assert ETS.has_ets?(body)
    end

    test "returns false for module without ETS" do
      code = """
      defmodule Other do
        def foo, do: :ok
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      refute ETS.has_ets?(body)
    end

    test "returns true for single :ets.new call" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:table, [:set])")
      assert ETS.has_ets?(ast)
    end
  end

  describe "ets_new?/1" do
    test "returns true for :ets.new/2 call" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:table, [:set])")
      assert ETS.ets_new?(ast)
    end

    test "returns false for :ets.lookup call" do
      {:ok, ast} = Code.string_to_quoted(":ets.lookup(:table, :key)")
      refute ETS.ets_new?(ast)
    end

    test "returns false for :ets.insert call" do
      {:ok, ast} = Code.string_to_quoted(":ets.insert(:table, {:key, :value})")
      refute ETS.ets_new?(ast)
    end

    test "returns false for non-ETS calls" do
      {:ok, ast} = Code.string_to_quoted("GenServer.call(pid, :msg)")
      refute ETS.ets_new?(ast)
    end
  end

  describe "ets_call?/1" do
    test "returns true for :ets.new" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:table, [:set])")
      assert ETS.ets_call?(ast)
    end

    test "returns true for :ets.lookup" do
      {:ok, ast} = Code.string_to_quoted(":ets.lookup(:table, :key)")
      assert ETS.ets_call?(ast)
    end

    test "returns true for :ets.insert" do
      {:ok, ast} = Code.string_to_quoted(":ets.insert(:table, {:key, :value})")
      assert ETS.ets_call?(ast)
    end

    test "returns true for :ets.delete" do
      {:ok, ast} = Code.string_to_quoted(":ets.delete(:table)")
      assert ETS.ets_call?(ast)
    end

    test "returns false for non-ETS calls" do
      {:ok, ast} = Code.string_to_quoted("Enum.map(list, fn x -> x end)")
      refute ETS.ets_call?(ast)
    end
  end

  # ============================================================================
  # Extraction Tests
  # ============================================================================

  describe "extract/1" do
    test "extracts simple :ets.new call" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:cache, [:set, :public])")
      {:ok, table} = ETS.extract(ast)

      assert %ETSTable{} = table
      assert table.name == :cache
      assert table.table_type == :set
      assert table.access_type == :public
    end

    test "extracts table name" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:my_table, [:set])")
      {:ok, table} = ETS.extract(ast)
      assert table.name == :my_table
    end

    test "returns error when no ETS found" do
      {:ok, ast} = Code.string_to_quoted("Agent.start_link(fn -> 0 end)")
      assert {:error, "No ETS tables found"} = ETS.extract(ast)
    end

    test "extracts from module body" do
      code = """
      defmodule Cache do
        def init do
          :ets.new(:cache, [:set, :named_table])
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, table} = ETS.extract(body)

      assert table.name == :cache
      assert table.named_table == true
    end

    test "extracts multiple tables" do
      code = """
      defmodule Multi do
        def init do
          :ets.new(:table1, [:set])
          :ets.new(:table2, [:bag])
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, tables} = ETS.extract(body)

      assert is_list(tables)
      assert length(tables) == 2
    end
  end

  describe "extract_all/1" do
    test "returns list of all tables" do
      code = """
      defmodule Multi do
        def init do
          :ets.new(:t1, [:set])
          :ets.new(:t2, [:bag])
          :ets.new(:t3, [:ordered_set])
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      tables = ETS.extract_all(body)

      assert length(tables) == 3
      assert Enum.any?(tables, &(&1.name == :t1))
      assert Enum.any?(tables, &(&1.name == :t2))
      assert Enum.any?(tables, &(&1.name == :t3))
    end

    test "returns empty list when no ETS found" do
      {:ok, ast} = Code.string_to_quoted("foo()")
      assert ETS.extract_all(ast) == []
    end
  end

  # ============================================================================
  # Table Type Tests
  # ============================================================================

  describe "table type extraction" do
    test "extracts :set type" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set])")
      {:ok, table} = ETS.extract(ast)
      assert table.table_type == :set
    end

    test "extracts :ordered_set type" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:ordered_set])")
      {:ok, table} = ETS.extract(ast)
      assert table.table_type == :ordered_set
    end

    test "extracts :bag type" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:bag])")
      {:ok, table} = ETS.extract(ast)
      assert table.table_type == :bag
    end

    test "extracts :duplicate_bag type" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:duplicate_bag])")
      {:ok, table} = ETS.extract(ast)
      assert table.table_type == :duplicate_bag
    end

    test "defaults to :set when no type specified" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:public])")
      {:ok, table} = ETS.extract(ast)
      assert table.table_type == :set
    end
  end

  describe "table type helpers" do
    test "set?/1 returns true for set tables" do
      assert ETS.set?(%ETSTable{table_type: :set})
      refute ETS.set?(%ETSTable{table_type: :bag})
    end

    test "ordered_set?/1 returns true for ordered_set tables" do
      assert ETS.ordered_set?(%ETSTable{table_type: :ordered_set})
      refute ETS.ordered_set?(%ETSTable{table_type: :set})
    end

    test "bag?/1 returns true for bag tables" do
      assert ETS.bag?(%ETSTable{table_type: :bag})
      refute ETS.bag?(%ETSTable{table_type: :set})
    end

    test "duplicate_bag?/1 returns true for duplicate_bag tables" do
      assert ETS.duplicate_bag?(%ETSTable{table_type: :duplicate_bag})
      refute ETS.duplicate_bag?(%ETSTable{table_type: :bag})
    end
  end

  # ============================================================================
  # Access Type Tests
  # ============================================================================

  describe "access type extraction" do
    test "extracts :public access" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set, :public])")
      {:ok, table} = ETS.extract(ast)
      assert table.access_type == :public
    end

    test "extracts :protected access" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set, :protected])")
      {:ok, table} = ETS.extract(ast)
      assert table.access_type == :protected
    end

    test "extracts :private access" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set, :private])")
      {:ok, table} = ETS.extract(ast)
      assert table.access_type == :private
    end

    test "defaults to :protected when no access specified" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set])")
      {:ok, table} = ETS.extract(ast)
      assert table.access_type == :protected
    end
  end

  describe "access type helpers" do
    test "public?/1 returns true for public tables" do
      assert ETS.public?(%ETSTable{access_type: :public})
      refute ETS.public?(%ETSTable{access_type: :protected})
    end

    test "protected?/1 returns true for protected tables" do
      assert ETS.protected?(%ETSTable{access_type: :protected})
      refute ETS.protected?(%ETSTable{access_type: :public})
    end

    test "private?/1 returns true for private tables" do
      assert ETS.private?(%ETSTable{access_type: :private})
      refute ETS.private?(%ETSTable{access_type: :public})
    end
  end

  # ============================================================================
  # Named Table Tests
  # ============================================================================

  describe "named_table option" do
    test "extracts :named_table option" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set, :named_table])")
      {:ok, table} = ETS.extract(ast)
      assert table.named_table == true
    end

    test "defaults to false when :named_table not specified" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set])")
      {:ok, table} = ETS.extract(ast)
      assert table.named_table == false
    end
  end

  # ============================================================================
  # Concurrency Options Tests
  # ============================================================================

  describe "concurrency options" do
    test "extracts read_concurrency: true" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set, read_concurrency: true])")
      {:ok, table} = ETS.extract(ast)
      assert table.read_concurrency == true
    end

    test "extracts write_concurrency: true" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set, write_concurrency: true])")
      {:ok, table} = ETS.extract(ast)
      assert table.write_concurrency == true
    end

    test "extracts both concurrency options" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set, read_concurrency: true, write_concurrency: true])")
      {:ok, table} = ETS.extract(ast)
      assert table.read_concurrency == true
      assert table.write_concurrency == true
    end

    test "defaults concurrency to false" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set])")
      {:ok, table} = ETS.extract(ast)
      assert table.read_concurrency == false
      assert table.write_concurrency == false
    end

    test "extracts write_concurrency: :auto" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set, write_concurrency: :auto])")
      {:ok, table} = ETS.extract(ast)
      assert table.write_concurrency == true
    end
  end

  describe "concurrency helpers" do
    test "read_concurrent?/1 returns true when enabled" do
      assert ETS.read_concurrent?(%ETSTable{read_concurrency: true})
      refute ETS.read_concurrent?(%ETSTable{read_concurrency: false})
    end

    test "write_concurrent?/1 returns true when enabled" do
      assert ETS.write_concurrent?(%ETSTable{write_concurrency: true})
      refute ETS.write_concurrent?(%ETSTable{write_concurrency: false})
    end
  end

  # ============================================================================
  # Compressed Option Tests
  # ============================================================================

  describe "compressed option" do
    test "extracts :compressed option" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set, :compressed])")
      {:ok, table} = ETS.extract(ast)
      assert table.compressed == true
    end

    test "defaults to false when :compressed not specified" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set])")
      {:ok, table} = ETS.extract(ast)
      assert table.compressed == false
    end
  end

  # ============================================================================
  # OTP Behaviour Tests
  # ============================================================================

  describe "otp_behaviour/0" do
    test "returns :ets" do
      assert ETS.otp_behaviour() == :ets
    end
  end

  # ============================================================================
  # ETSTable Struct Tests
  # ============================================================================

  describe "ETSTable struct" do
    test "has expected fields" do
      table = %ETSTable{}
      assert Map.has_key?(table, :name)
      assert Map.has_key?(table, :table_type)
      assert Map.has_key?(table, :access_type)
      assert Map.has_key?(table, :named_table)
      assert Map.has_key?(table, :read_concurrency)
      assert Map.has_key?(table, :write_concurrency)
      assert Map.has_key?(table, :compressed)
      assert Map.has_key?(table, :heir)
      assert Map.has_key?(table, :location)
      assert Map.has_key?(table, :metadata)
    end

    test "has correct defaults" do
      table = %ETSTable{}
      assert table.name == nil
      assert table.table_type == :set
      assert table.access_type == :protected
      assert table.named_table == false
      assert table.read_concurrency == false
      assert table.write_concurrency == false
      assert table.compressed == false
      assert table.heir == nil
    end
  end

  # ============================================================================
  # Real-World Pattern Tests
  # ============================================================================

  describe "real-world patterns" do
    test "extracts typical GenServer cache table" do
      code = """
      defmodule CacheServer do
        use GenServer

        def init(_) do
          table = :ets.new(:cache, [:set, :named_table, :public, read_concurrency: true])
          {:ok, %{table: table}}
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, table} = ETS.extract(body)

      assert table.name == :cache
      assert table.table_type == :set
      assert table.access_type == :public
      assert table.named_table == true
      assert table.read_concurrency == true
    end

    test "extracts ordered_set for sorted data" do
      code = """
      defmodule SortedStore do
        def init do
          :ets.new(:sorted_data, [:ordered_set, :private])
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, table} = ETS.extract(body)

      assert table.table_type == :ordered_set
      assert table.access_type == :private
    end

    test "extracts bag for multi-value storage" do
      code = """
      defmodule EventStore do
        def init do
          :ets.new(:events, [:bag, :public, write_concurrency: true])
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, table} = ETS.extract(body)

      assert table.table_type == :bag
      assert table.write_concurrency == true
    end

    test "extracts table from assignment" do
      code = """
      defmodule Store do
        def init do
          table = :ets.new(:data, [:set, :public])
          {:ok, table}
        end
      end
      """
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, table} = ETS.extract(body)

      assert table.name == :data
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "handles empty options list" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [])")
      {:ok, table} = ETS.extract(ast)

      assert table.table_type == :set
      assert table.access_type == :protected
    end

    test "handles combined options" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:ordered_set, :public, :named_table, :compressed, read_concurrency: true])")
      {:ok, table} = ETS.extract(ast)

      assert table.table_type == :ordered_set
      assert table.access_type == :public
      assert table.named_table == true
      assert table.compressed == true
      assert table.read_concurrency == true
    end
  end

  # ============================================================================
  # Heir Option Tests
  # ============================================================================

  describe "heir option extraction" do
    test "extracts heir option with pid placeholder" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set, {:heir, self(), :heir_data}])")
      {:ok, table} = ETS.extract(ast)

      assert table.heir != nil
    end

    test "extracts heir option with :none value" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set, {:heir, :none}])")
      {:ok, table} = ETS.extract(ast)

      assert table.heir == :none
    end

    test "heir is nil when not specified" do
      {:ok, ast} = Code.string_to_quoted(":ets.new(:t, [:set])")
      {:ok, table} = ETS.extract(ast)

      assert table.heir == nil
    end
  end
end
