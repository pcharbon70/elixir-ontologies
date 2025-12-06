defmodule ElixirOntologies.Extractors.StructTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Extractors.Struct

  doctest Struct

  # ===========================================================================
  # Type Detection Tests
  # ===========================================================================

  describe "struct?/1" do
    test "returns true for defstruct node" do
      ast = {:defstruct, [], [[:name, :email]]}
      assert Struct.struct?(ast)
    end

    test "returns false for defmodule node" do
      ast = {:defmodule, [], [{:__aliases__, [], [:MyModule]}, [do: nil]]}
      refute Struct.struct?(ast)
    end

    test "returns false for atoms" do
      refute Struct.struct?(:not_a_struct)
    end
  end

  # ===========================================================================
  # Direct Extraction Tests
  # ===========================================================================

  describe "extract/2" do
    test "extracts simple struct with atom fields" do
      code = "defstruct [:name, :email]"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract(ast)
      assert length(result.fields) == 2

      names = Enum.map(result.fields, & &1.name)
      assert :name in names
      assert :email in names
    end

    test "extracts struct with default values" do
      code = "defstruct name: nil, age: 0, active: true"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract(ast)
      assert length(result.fields) == 3

      age_field = Enum.find(result.fields, & &1.name == :age)
      assert age_field.has_default == true
      assert age_field.default_value == 0

      active_field = Enum.find(result.fields, & &1.name == :active)
      assert active_field.has_default == true
      assert active_field.default_value == true
    end

    test "extracts mixed fields (atoms and keyword)" do
      code = "defstruct [:name, :email, age: 0]"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract(ast)
      assert length(result.fields) == 3

      name_field = Enum.find(result.fields, & &1.name == :name)
      assert name_field.has_default == false

      age_field = Enum.find(result.fields, & &1.name == :age)
      assert age_field.has_default == true
    end

    test "returns error for non-struct" do
      assert {:error, message} = Struct.extract({:def, [], []})
      assert message =~ "Not a defstruct"
    end

    test "handles empty struct" do
      code = "defstruct []"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract(ast)
      assert result.fields == []
    end
  end

  describe "extract!/2" do
    test "returns result on success" do
      code = "defstruct [:name]"
      {:ok, ast} = Code.string_to_quoted(code)

      result = Struct.extract!(ast)
      assert hd(result.fields).name == :name
    end

    test "raises on error" do
      assert_raise ArgumentError, ~r/Not a defstruct/, fn ->
        Struct.extract!(:not_struct)
      end
    end
  end

  # ===========================================================================
  # Body Extraction Tests
  # ===========================================================================

  describe "extract_from_body/2" do
    test "extracts struct from module body" do
      code = "defmodule User do defstruct [:name, :email] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_from_body(body)
      assert length(result.fields) == 2
    end

    test "extracts @enforce_keys" do
      code = "defmodule User do @enforce_keys [:name]; defstruct [:name, :email] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_from_body(body)
      assert result.enforce_keys == [:name]
    end

    test "extracts multiple @enforce_keys" do
      code = """
      defmodule User do
        @enforce_keys [:a]
        @enforce_keys [:b]
        defstruct [:a, :b, :c]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_from_body(body)
      assert :a in result.enforce_keys
      assert :b in result.enforce_keys
    end

    test "extracts @derive directives" do
      code = "defmodule User do @derive Inspect; defstruct [:name] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_from_body(body)
      assert length(result.derives) == 1
    end

    test "extracts multiple @derive protocols" do
      code = "defmodule User do @derive [Inspect, Enumerable]; defstruct [:name] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_from_body(body)
      assert length(result.derives) == 1
      assert length(hd(result.derives).protocols) == 2
    end

    test "returns error when no defstruct" do
      code = "defmodule Plain do def foo, do: :ok end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert {:error, "No defstruct found in module body"} = Struct.extract_from_body(body)
    end
  end

  describe "extract_from_body!/2" do
    test "returns result on success" do
      code = "defmodule U do defstruct [:a] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Struct.extract_from_body!(body)
      assert hd(result.fields).name == :a
    end

    test "raises on error" do
      code = "defmodule Plain do end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert_raise ArgumentError, ~r/No defstruct/, fn ->
        Struct.extract_from_body!(body)
      end
    end
  end

  describe "defines_struct?/1" do
    test "returns true when module has defstruct" do
      code = "defmodule User do defstruct [:name] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert Struct.defines_struct?(body)
    end

    test "returns false when module has no defstruct" do
      code = "defmodule Plain do def foo, do: :ok end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      refute Struct.defines_struct?(body)
    end
  end

  describe "extract_enforce_keys/1" do
    test "extracts enforce_keys from body" do
      code = "defmodule U do @enforce_keys [:a, :b]; defstruct [:a, :b, :c] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert Struct.extract_enforce_keys(body) == [:a, :b]
    end

    test "returns empty list when no enforce_keys" do
      code = "defmodule U do defstruct [:a] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert Struct.extract_enforce_keys(body) == []
    end
  end

  # ===========================================================================
  # Utility Function Tests
  # ===========================================================================

  describe "field_names/1" do
    test "returns list of field names" do
      code = "defstruct [:name, :email, age: 0]"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract(ast)

      assert Struct.field_names(result) == [:name, :email, :age]
    end
  end

  describe "get_field/2" do
    test "returns field by name" do
      code = "defstruct [:name, age: 21]"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract(ast)

      field = Struct.get_field(result, :age)
      assert field.name == :age
      assert field.has_default == true
      assert field.default_value == 21
    end

    test "returns nil for unknown field" do
      code = "defstruct [:name]"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract(ast)

      assert Struct.get_field(result, :unknown) == nil
    end
  end

  describe "enforced?/2" do
    test "returns true for enforced field" do
      code = "defmodule U do @enforce_keys [:name]; defstruct [:name, :email] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_from_body(body)

      assert Struct.enforced?(result, :name)
    end

    test "returns false for non-enforced field" do
      code = "defmodule U do @enforce_keys [:name]; defstruct [:name, :email] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_from_body(body)

      refute Struct.enforced?(result, :email)
    end
  end

  describe "has_default?/2" do
    test "returns true for field with default" do
      code = "defstruct [:name, age: 0]"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract(ast)

      assert Struct.has_default?(result, :age)
    end

    test "returns false for field without default" do
      code = "defstruct [:name, age: 0]"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract(ast)

      refute Struct.has_default?(result, :name)
    end

    test "returns false for unknown field" do
      code = "defstruct [:name]"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract(ast)

      refute Struct.has_default?(result, :unknown)
    end
  end

  describe "default_value/2" do
    test "returns default value for field" do
      code = "defstruct age: 21"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract(ast)

      assert Struct.default_value(result, :age) == 21
    end

    test "returns nil for field without default" do
      code = "defstruct [:name]"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract(ast)

      assert Struct.default_value(result, :name) == nil
    end
  end

  describe "fields_with_defaults/1" do
    test "returns only fields with defaults" do
      code = "defstruct [:name, age: 0, active: true]"
      {:ok, ast} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract(ast)

      fields = Struct.fields_with_defaults(result)
      names = Enum.map(fields, & &1.name)

      assert length(fields) == 2
      assert :age in names
      assert :active in names
      refute :name in names
    end
  end

  describe "required_fields/1" do
    test "returns enforced fields without defaults" do
      code = "defmodule U do @enforce_keys [:name, :age]; defstruct [:name, :email, age: 0] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_from_body(body)

      required = Struct.required_fields(result)
      # :name is enforced and has no default
      # :age is enforced but has default, so not required
      assert length(required) == 1
      assert hd(required).name == :name
    end
  end

  describe "has_derives?/1" do
    test "returns true when has derives" do
      code = "defmodule U do @derive Inspect; defstruct [:a] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_from_body(body)

      assert Struct.has_derives?(result)
    end

    test "returns false when no derives" do
      code = "defmodule U do defstruct [:a] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_from_body(body)

      refute Struct.has_derives?(result)
    end
  end

  describe "derived_protocols/1" do
    test "returns list of derived protocol names" do
      code = "defmodule U do @derive [Inspect, Enumerable]; defstruct [:a] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_from_body(body)

      protocols = Struct.derived_protocols(result)
      assert [:Inspect] in protocols
      assert [:Enumerable] in protocols
    end

    test "returns empty list when no derives" do
      code = "defmodule U do defstruct [:a] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_from_body(body)

      assert Struct.derived_protocols(result) == []
    end
  end

  # ===========================================================================
  # Real World Scenario Tests
  # ===========================================================================

  describe "real world scenarios" do
    test "typical User struct" do
      code = """
      defmodule User do
        @moduledoc "User struct"
        @derive {Jason.Encoder, only: [:id, :name, :email]}
        @enforce_keys [:email]

        defstruct [
          :id,
          :email,
          name: "",
          active: true,
          role: :user,
          inserted_at: nil
        ]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_from_body(body)

      assert length(result.fields) == 6
      assert result.enforce_keys == [:email]
      assert Struct.enforced?(result, :email)
      assert Struct.has_default?(result, :role)
      assert Struct.default_value(result, :role) == :user
      assert Struct.has_derives?(result)
    end

    test "Ecto schema-like struct" do
      code = """
      defmodule Post do
        @enforce_keys [:title, :user_id]

        defstruct [
          :id,
          :title,
          :body,
          :user_id,
          published: false,
          view_count: 0
        ]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_from_body(body)

      required = Struct.required_fields(result)
      required_names = Enum.map(required, & &1.name)

      assert :title in required_names
      assert :user_id in required_names
      refute :id in required_names  # not enforced
    end

    test "config struct with all defaults" do
      code = """
      defmodule Config do
        defstruct [
          host: "localhost",
          port: 4000,
          ssl: false,
          pool_size: 10
        ]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_from_body(body)

      # All fields have defaults
      assert length(Struct.fields_with_defaults(result)) == 4
      assert Struct.required_fields(result) == []
    end
  end

  # ===========================================================================
  # Exception Type Detection Tests
  # ===========================================================================

  describe "exception?/1" do
    test "returns true for defexception node" do
      ast = {:defexception, [], [[:message]]}
      assert Struct.exception?(ast)
    end

    test "returns false for defstruct node" do
      ast = {:defstruct, [], [[:name]]}
      refute Struct.exception?(ast)
    end

    test "returns false for atoms" do
      refute Struct.exception?(:not_exception)
    end
  end

  # ===========================================================================
  # Exception Direct Extraction Tests
  # ===========================================================================

  describe "extract_exception/2" do
    test "extracts simple exception" do
      code = "defexception [:message]"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_exception(ast)
      assert length(result.fields) == 1
      assert hd(result.fields).name == :message
    end

    test "extracts exception with default message" do
      code = "defexception message: \"not found\""
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_exception(ast)
      assert result.default_message == "not found"
    end

    test "extracts exception with multiple fields" do
      code = "defexception [:field, :reason, message: \"error\"]"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_exception(ast)
      assert length(result.fields) == 3
      assert result.default_message == "error"
    end

    test "returns nil default_message when no message field" do
      code = "defexception [:field, :reason]"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_exception(ast)
      assert result.default_message == nil
    end

    test "returns nil default_message when message has no default" do
      code = "defexception [:message]"
      {:ok, ast} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_exception(ast)
      assert result.default_message == nil
    end

    test "returns error for non-exception" do
      assert {:error, message} = Struct.extract_exception({:defstruct, [], []})
      assert message =~ "Not a defexception"
    end
  end

  describe "extract_exception!/2" do
    test "returns result on success" do
      code = "defexception [:message]"
      {:ok, ast} = Code.string_to_quoted(code)

      result = Struct.extract_exception!(ast)
      assert hd(result.fields).name == :message
    end

    test "raises on error" do
      assert_raise ArgumentError, ~r/Not a defexception/, fn ->
        Struct.extract_exception!(:not_exception)
      end
    end
  end

  # ===========================================================================
  # Exception Body Extraction Tests
  # ===========================================================================

  describe "extract_exception_from_body/2" do
    test "extracts exception from module body" do
      code = "defmodule MyError do defexception [:message] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_exception_from_body(body)
      assert length(result.fields) == 1
    end

    test "detects custom message/1 function" do
      code = """
      defmodule MyError do
        defexception [:field]

        def message(%{field: f}), do: "error: \#{f}"
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_exception_from_body(body)
      assert result.has_custom_message == true
    end

    test "detects no custom message when not present" do
      code = "defmodule MyError do defexception message: \"oops\" end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_exception_from_body(body)
      assert result.has_custom_message == false
    end

    test "extracts @enforce_keys for exception" do
      code = """
      defmodule MyError do
        @enforce_keys [:reason]
        defexception [:reason, :message]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert {:ok, result} = Struct.extract_exception_from_body(body)
      assert result.enforce_keys == [:reason]
    end

    test "returns error when no defexception" do
      code = "defmodule Plain do def foo, do: :ok end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert {:error, "No defexception found in module body"} =
               Struct.extract_exception_from_body(body)
    end
  end

  describe "extract_exception_from_body!/2" do
    test "returns result on success" do
      code = "defmodule E do defexception [:a] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      result = Struct.extract_exception_from_body!(body)
      assert hd(result.fields).name == :a
    end

    test "raises on error" do
      code = "defmodule Plain do end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert_raise ArgumentError, ~r/No defexception/, fn ->
        Struct.extract_exception_from_body!(body)
      end
    end
  end

  describe "defines_exception?/1" do
    test "returns true when module has defexception" do
      code = "defmodule MyError do defexception [:message] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      assert Struct.defines_exception?(body)
    end

    test "returns false when module has defstruct" do
      code = "defmodule Plain do defstruct [:name] end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      refute Struct.defines_exception?(body)
    end

    test "returns false when module has neither" do
      code = "defmodule Plain do def foo, do: :ok end"
      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)

      refute Struct.defines_exception?(body)
    end
  end

  # ===========================================================================
  # Real World Exception Tests
  # ===========================================================================

  describe "real world exception scenarios" do
    test "ArgumentError-like exception" do
      code = """
      defmodule MyArgumentError do
        defexception message: "argument error"
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_exception_from_body(body)

      assert result.default_message == "argument error"
      assert result.has_custom_message == false
    end

    test "KeyError-like exception with custom message" do
      code = """
      defmodule MyKeyError do
        defexception [:key, :term]

        @impl true
        def message(%{key: key, term: term}) do
          "key \#{inspect(key)} not found in: \#{inspect(term)}"
        end
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_exception_from_body(body)

      assert result.has_custom_message == true
      assert result.default_message == nil
      assert length(result.fields) == 2
    end

    test "custom validation exception" do
      code = """
      defmodule ValidationError do
        @enforce_keys [:errors]
        defexception [:errors, message: "validation failed"]

        @impl true
        def message(%{errors: errors}) do
          "Validation failed: \#{inspect(errors)}"
        end
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_exception_from_body(body)

      assert result.enforce_keys == [:errors]
      assert result.default_message == "validation failed"
      assert result.has_custom_message == true
    end
  end

  describe "edge cases" do
    test "@enforce_keys with non-existent field" do
      # In Elixir, @enforce_keys can reference fields that don't exist in defstruct.
      # This is a compile-time error in real code, but we should extract what's declared.
      code = """
      defmodule BadStruct do
        @enforce_keys [:name, :non_existent]
        defstruct [:name, :email]
      end
      """

      {:ok, {:defmodule, _, [_, [do: body]]}} = Code.string_to_quoted(code)
      {:ok, result} = Struct.extract_from_body(body)

      # We extract enforce_keys as declared, even if they don't match fields
      assert result.enforce_keys == [:name, :non_existent]
      assert Struct.field_names(result) == [:name, :email]

      # :non_existent is in enforce_keys but not in fields
      assert Struct.enforced?(result, :name) == true
      assert Struct.enforced?(result, :non_existent) == true
      assert Struct.enforced?(result, :email) == false

      # required_fields only includes fields that exist AND are enforced
      required = Struct.required_fields(result)
      required_names = Enum.map(required, & &1.name)
      assert :name in required_names
      refute :non_existent in required_names  # Not a field, so not required
    end
  end
end
