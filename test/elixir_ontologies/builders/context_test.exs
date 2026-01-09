defmodule ElixirOntologies.Builders.ContextTest do
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias ElixirOntologies.Builders.Context

  doctest Context

  describe "new/1" do
    test "creates context with required base_iri" do
      context = Context.new(base_iri: "https://example.org/code#")

      assert context.base_iri == "https://example.org/code#"
      assert context.file_path == nil
      assert context.parent_module == nil
      assert context.config == %{}
      assert context.metadata == %{}
    end

    test "creates context with all fields" do
      parent_iri = ~I<https://example.org/code#MyApp>

      context =
        Context.new(
          base_iri: "https://example.org/code#",
          file_path: "lib/my_app.ex",
          parent_module: parent_iri,
          config: %{include_private: false},
          metadata: %{version: "1.0.0"}
        )

      assert context.base_iri == "https://example.org/code#"
      assert context.file_path == "lib/my_app.ex"
      assert context.parent_module == parent_iri
      assert context.config == %{include_private: false}
      assert context.metadata == %{version: "1.0.0"}
    end

    test "raises if base_iri is missing" do
      assert_raise KeyError, fn ->
        Context.new([])
      end
    end

    test "accepts RDF.IRI as base_iri" do
      base_iri = ~I<https://example.org/code#>
      context = Context.new(base_iri: base_iri)

      assert context.base_iri == base_iri
    end
  end

  describe "with_parent_module/2" do
    test "creates new context with parent module" do
      context = Context.new(base_iri: "https://example.org/code#")
      parent_iri = ~I<https://example.org/code#MyApp>

      new_context = Context.with_parent_module(context, parent_iri)

      assert new_context.parent_module == parent_iri
      assert new_context.base_iri == context.base_iri
    end

    test "replaces existing parent module" do
      parent1 = ~I<https://example.org/code#MyApp>
      parent2 = ~I<https://example.org/code#MyApp.Users>

      context =
        Context.new(base_iri: "https://example.org/code#", parent_module: parent1)

      new_context = Context.with_parent_module(context, parent2)

      assert new_context.parent_module == parent2
    end
  end

  describe "with_metadata/2" do
    test "adds metadata to empty context" do
      context = Context.new(base_iri: "https://example.org/code#")
      metadata = %{version: "1.0.0", author: "dev"}

      new_context = Context.with_metadata(context, metadata)

      assert new_context.metadata == metadata
    end

    test "merges with existing metadata" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{version: "1.0.0"}
        )

      new_context = Context.with_metadata(context, %{author: "dev"})

      assert new_context.metadata == %{version: "1.0.0", author: "dev"}
    end

    test "overwrites existing keys" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{version: "1.0.0"}
        )

      new_context = Context.with_metadata(context, %{version: "2.0.0"})

      assert new_context.metadata == %{version: "2.0.0"}
    end
  end

  describe "with_config/2" do
    test "adds config to empty context" do
      context = Context.new(base_iri: "https://example.org/code#")
      config = %{include_private: false, include_docs: true}

      new_context = Context.with_config(context, config)

      assert new_context.config == config
    end

    test "merges with existing config" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_private: true}
        )

      new_context = Context.with_config(context, %{include_docs: false})

      assert new_context.config == %{include_private: true, include_docs: false}
    end
  end

  describe "with_file_path/2" do
    test "sets file path on context" do
      context = Context.new(base_iri: "https://example.org/code#")

      new_context = Context.with_file_path(context, "lib/users.ex")

      assert new_context.file_path == "lib/users.ex"
    end

    test "replaces existing file path" do
      context =
        Context.new(base_iri: "https://example.org/code#", file_path: "lib/old.ex")

      new_context = Context.with_file_path(context, "lib/new.ex")

      assert new_context.file_path == "lib/new.ex"
    end
  end

  describe "get_config/3" do
    test "returns config value if present" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_private: false}
        )

      assert Context.get_config(context, :include_private) == false
    end

    test "returns default if key not present" do
      context = Context.new(base_iri: "https://example.org/code#")

      assert Context.get_config(context, :include_private, true) == true
    end

    test "returns nil as default if not specified" do
      context = Context.new(base_iri: "https://example.org/code#")

      assert Context.get_config(context, :missing_key) == nil
    end
  end

  describe "get_metadata/3" do
    test "returns metadata value if present" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          metadata: %{version: "1.0.0"}
        )

      assert Context.get_metadata(context, :version) == "1.0.0"
    end

    test "returns default if key not present" do
      context = Context.new(base_iri: "https://example.org/code#")

      assert Context.get_metadata(context, :version, "0.0.1") == "0.0.1"
    end
  end

  describe "validate/1" do
    test "validates context with base_iri" do
      context = Context.new(base_iri: "https://example.org/code#")

      assert Context.validate(context) == :ok
    end

    test "validates context with RDF.IRI base_iri" do
      context = Context.new(base_iri: ~I<https://example.org/code#>)

      assert Context.validate(context) == :ok
    end

    test "returns error for nil base_iri" do
      context = %Context{base_iri: nil}

      assert Context.validate(context) == {:error, :missing_base_iri}
    end

    test "returns error for invalid context" do
      assert Context.validate(%{}) == {:error, :invalid_context}
    end
  end

  describe "context immutability" do
    test "transformation functions return new context" do
      original = Context.new(base_iri: "https://example.org/code#")
      modified = Context.with_metadata(original, %{test: true})

      assert original.metadata == %{}
      assert modified.metadata == %{test: true}
      refute original == modified
    end
  end

  describe "full_mode?/1" do
    test "returns true when include_expressions is true in config" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true}
        )

      assert Context.full_mode?(context) == true
    end

    test "returns false when include_expressions is false in config" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: false}
        )

      assert Context.full_mode?(context) == false
    end

    test "returns false when config is empty" do
      context = Context.new(base_iri: "https://example.org/code#")

      assert Context.full_mode?(context) == false
    end

    test "returns false when config does not have include_expressions key" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{other_key: true}
        )

      assert Context.full_mode?(context) == false
    end
  end

  describe "full_mode_for_file?/2" do
    test "returns true when full mode enabled and project file" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true}
        )

      assert Context.full_mode_for_file?(context, "lib/my_app/users.ex") == true
    end

    test "returns false when full mode enabled but dependency file" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true}
        )

      assert Context.full_mode_for_file?(context, "deps/decimal/lib/decimal.ex") == false
    end

    test "returns false when full mode disabled and project file" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: false}
        )

      assert Context.full_mode_for_file?(context, "lib/my_app/users.ex") == false
    end

    test "returns false for nil file path" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true}
        )

      assert Context.full_mode_for_file?(context, nil) == false
    end

    test "returns true for src/ files when full mode enabled" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true}
        )

      assert Context.full_mode_for_file?(context, "src/my_app/users.ex") == true
    end
  end

  describe "light_mode?/1" do
    test "returns true when include_expressions is false" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: false}
        )

      assert Context.light_mode?(context) == true
    end

    test "returns false when include_expressions is true" do
      context =
        Context.new(
          base_iri: "https://example.org/code#",
          config: %{include_expressions: true}
        )

      assert Context.light_mode?(context) == false
    end

    test "returns true when config is empty" do
      context = Context.new(base_iri: "https://example.org/code#")

      assert Context.light_mode?(context) == true
    end
  end
end
