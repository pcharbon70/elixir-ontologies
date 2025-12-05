defmodule ElixirOntologies.ConfigTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Config

  describe "default/0" do
    test "returns a Config struct with default values" do
      config = Config.default()

      assert %Config{} = config
      assert config.base_iri == "https://example.org/code#"
      assert config.include_source_text == false
      assert config.include_git_info == true
      assert config.output_format == :turtle
    end
  end

  describe "merge/2" do
    test "overrides base_iri" do
      config = Config.default()
      merged = Config.merge(config, base_iri: "https://myproject.org/")

      assert merged.base_iri == "https://myproject.org/"
      # Other defaults preserved
      assert merged.include_source_text == false
      assert merged.include_git_info == true
    end

    test "overrides multiple options" do
      config = Config.default()

      merged =
        Config.merge(config,
          base_iri: "https://custom.org/",
          include_source_text: true,
          include_git_info: false,
          output_format: :jsonld
        )

      assert merged.base_iri == "https://custom.org/"
      assert merged.include_source_text == true
      assert merged.include_git_info == false
      assert merged.output_format == :jsonld
    end

    test "ignores unknown options" do
      config = Config.default()
      merged = Config.merge(config, unknown_option: "value", another: 123)

      assert merged == config
    end
  end

  describe "validate/1" do
    test "returns {:ok, config} for valid configuration" do
      config = Config.default()

      assert {:ok, ^config} = Config.validate(config)
    end

    test "returns error for empty base_iri" do
      config = %Config{Config.default() | base_iri: ""}

      assert {:error, reasons} = Config.validate(config)
      assert "base_iri must be a non-empty string" in reasons
    end

    test "returns error for invalid output_format" do
      config = %Config{Config.default() | output_format: :invalid}

      assert {:error, reasons} = Config.validate(config)
      assert Enum.any?(reasons, &String.contains?(&1, "output_format"))
    end

    test "returns error for non-boolean include_source_text" do
      config = %Config{Config.default() | include_source_text: "yes"}

      assert {:error, reasons} = Config.validate(config)
      assert "include_source_text must be a boolean" in reasons
    end

    test "returns multiple errors for multiple invalid fields" do
      config = %Config{
        base_iri: "",
        include_source_text: "yes",
        include_git_info: "no",
        output_format: :invalid
      }

      assert {:error, reasons} = Config.validate(config)
      assert length(reasons) == 4
    end
  end

  describe "validate!/1" do
    test "returns config for valid configuration" do
      config = Config.default()

      assert ^config = Config.validate!(config)
    end

    test "raises ArgumentError for invalid configuration" do
      config = %Config{Config.default() | base_iri: ""}

      assert_raise ArgumentError, ~r/Invalid config/, fn ->
        Config.validate!(config)
      end
    end
  end

  describe "new/1" do
    test "creates config with defaults when no options provided" do
      config = Config.new()

      assert config == Config.default()
    end

    test "creates config with custom options" do
      config = Config.new(base_iri: "https://custom.org/", include_source_text: true)

      assert config.base_iri == "https://custom.org/"
      assert config.include_source_text == true
      assert config.include_git_info == true
    end

    test "raises for invalid options" do
      assert_raise ArgumentError, ~r/Invalid config/, fn ->
        Config.new(base_iri: "")
      end
    end
  end
end
