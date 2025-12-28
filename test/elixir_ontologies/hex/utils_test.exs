defmodule ElixirOntologies.Hex.UtilsTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.Utils

  describe "parse_datetime/1" do
    test "parses valid ISO8601 datetime" do
      result = Utils.parse_datetime("2024-01-15T10:30:00Z")
      assert %DateTime{year: 2024, month: 1, day: 15} = result
    end

    test "parses datetime with offset" do
      result = Utils.parse_datetime("2024-06-20T14:45:30+02:00")
      assert %DateTime{year: 2024, month: 6, day: 20} = result
    end

    test "returns nil for nil input" do
      assert Utils.parse_datetime(nil) == nil
    end

    test "returns nil for invalid datetime string" do
      assert Utils.parse_datetime("not a date") == nil
    end

    test "returns nil for empty string" do
      assert Utils.parse_datetime("") == nil
    end
  end

  describe "format_duration_ms/1" do
    test "formats milliseconds" do
      assert Utils.format_duration_ms(500) == "500ms"
      assert Utils.format_duration_ms(0) == "0ms"
    end

    test "formats seconds" do
      assert Utils.format_duration_ms(1500) == "1.5s"
      assert Utils.format_duration_ms(5000) == "5.0s"
    end

    test "formats minutes and seconds" do
      assert Utils.format_duration_ms(90_000) == "1m 30s"
      assert Utils.format_duration_ms(60_000) == "1m 0s"
      assert Utils.format_duration_ms(125_000) == "2m 5s"
    end
  end

  describe "format_duration_seconds/1" do
    test "formats seconds" do
      assert Utils.format_duration_seconds(45) == "45 seconds"
      assert Utils.format_duration_seconds(1) == "1 seconds"
    end

    test "formats minutes and seconds" do
      assert Utils.format_duration_seconds(90) == "1m 30s"
      assert Utils.format_duration_seconds(60) == "1m 0s"
    end

    test "formats hours, minutes and seconds" do
      assert Utils.format_duration_seconds(3665) == "1h 1m 5s"
      assert Utils.format_duration_seconds(7200) == "2h 0m 0s"
    end
  end

  describe "tarball_url/2" do
    test "generates correct URL for standard package" do
      assert Utils.tarball_url("phoenix", "1.7.10") ==
               "https://repo.hex.pm/tarballs/phoenix-1.7.10.tar"
    end

    test "encodes special characters in package name" do
      assert Utils.tarball_url("my%package", "1.0.0") ==
               "https://repo.hex.pm/tarballs/my%25package-1.0.0.tar"
    end

    test "handles version with prerelease suffix" do
      assert Utils.tarball_url("ecto", "3.12.0-rc.1") ==
               "https://repo.hex.pm/tarballs/ecto-3.12.0-rc.1.tar"
    end
  end

  describe "tarball_filename/2" do
    test "generates correct filename" do
      assert Utils.tarball_filename("phoenix", "1.7.10") == "phoenix-1.7.10.tar"
    end

    test "handles prerelease version" do
      assert Utils.tarball_filename("plug", "2.0.0-beta.1") == "plug-2.0.0-beta.1.tar"
    end
  end
end
