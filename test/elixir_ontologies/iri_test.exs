defmodule ElixirOntologies.IRITest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.IRI

  @base_iri "https://example.org/code#"

  describe "escape_name/1" do
    test "passes through normal names unchanged" do
      assert IRI.escape_name("normal_name") == "normal_name"
      assert IRI.escape_name("CamelCase") == "CamelCase"
      assert IRI.escape_name("with123numbers") == "with123numbers"
    end

    test "escapes question mark" do
      assert IRI.escape_name("valid?") == "valid%3F"
      assert IRI.escape_name("is_empty?") == "is_empty%3F"
    end

    test "escapes exclamation mark" do
      assert IRI.escape_name("update!") == "update%21"
      assert IRI.escape_name("save!") == "save%21"
    end

    test "escapes pipe operator" do
      assert IRI.escape_name("|>") == "%7C%3E"
    end

    test "escapes other operators" do
      assert IRI.escape_name("+") == "%2B"
      # hyphen is safe
      assert IRI.escape_name("-") == "-"
      assert IRI.escape_name("*") == "%2A"
      assert IRI.escape_name("/") == "%2F"
      assert IRI.escape_name("<>") == "%3C%3E"
      assert IRI.escape_name("++") == "%2B%2B"
      # hyphens are safe
      assert IRI.escape_name("--") == "--"
      assert IRI.escape_name("&&") == "%26%26"
      assert IRI.escape_name("||") == "%7C%7C"
    end

    test "handles atoms" do
      assert IRI.escape_name(:valid?) == "valid%3F"
      assert IRI.escape_name(:update!) == "update%21"
      assert IRI.escape_name(:normal) == "normal"
    end

    test "preserves dots for module names" do
      assert IRI.escape_name("MyApp.Users") == "MyApp.Users"
      assert IRI.escape_name("MyApp.Accounts.User") == "MyApp.Accounts.User"
    end
  end

  describe "for_module/2" do
    test "generates IRI for simple module" do
      iri = IRI.for_module(@base_iri, "MyApp")
      assert %RDF.IRI{} = iri
      assert to_string(iri) == "https://example.org/code#MyApp"
    end

    test "generates IRI for nested module" do
      iri = IRI.for_module(@base_iri, "MyApp.Accounts.User")
      assert to_string(iri) == "https://example.org/code#MyApp.Accounts.User"
    end

    test "handles module atoms" do
      iri = IRI.for_module(@base_iri, MyApp.Users)
      assert to_string(iri) == "https://example.org/code#MyApp.Users"
    end

    test "handles deeply nested modules" do
      iri = IRI.for_module(@base_iri, "MyApp.Web.Controllers.UserController")
      assert to_string(iri) == "https://example.org/code#MyApp.Web.Controllers.UserController"
    end

    test "works with RDF.IRI as base" do
      base = RDF.iri(@base_iri)
      iri = IRI.for_module(base, "MyApp")
      assert to_string(iri) == "https://example.org/code#MyApp"
    end
  end

  describe "for_function/4" do
    test "generates IRI for simple function" do
      iri = IRI.for_function(@base_iri, "MyApp.Users", "get_user", 1)
      assert %RDF.IRI{} = iri
      assert to_string(iri) == "https://example.org/code#MyApp.Users/get_user/1"
    end

    test "generates IRI for function with zero arity" do
      iri = IRI.for_function(@base_iri, "MyApp", "init", 0)
      assert to_string(iri) == "https://example.org/code#MyApp/init/0"
    end

    test "escapes question mark in function name" do
      iri = IRI.for_function(@base_iri, "MyApp", "valid?", 1)
      assert to_string(iri) == "https://example.org/code#MyApp/valid%3F/1"
    end

    test "escapes exclamation mark in function name" do
      iri = IRI.for_function(@base_iri, "MyApp", "save!", 1)
      assert to_string(iri) == "https://example.org/code#MyApp/save%21/1"
    end

    test "handles operator functions" do
      iri = IRI.for_function(@base_iri, "MyApp", "|>", 2)
      assert to_string(iri) == "https://example.org/code#MyApp/%7C%3E/2"
    end

    test "handles atom arguments" do
      iri = IRI.for_function(@base_iri, MyApp.Users, :get_user, 1)
      assert to_string(iri) == "https://example.org/code#MyApp.Users/get_user/1"
    end

    test "handles high arity functions" do
      iri = IRI.for_function(@base_iri, "MyApp", "many_args", 10)
      assert to_string(iri) == "https://example.org/code#MyApp/many_args/10"
    end
  end

  describe "for_clause/2" do
    test "generates IRI for first clause" do
      func_iri = RDF.iri("https://example.org/code#MyApp/get/1")
      iri = IRI.for_clause(func_iri, 0)
      assert %RDF.IRI{} = iri
      assert to_string(iri) == "https://example.org/code#MyApp/get/1/clause/0"
    end

    test "generates IRI for subsequent clauses" do
      func_iri = RDF.iri("https://example.org/code#MyApp/get/1")

      assert to_string(IRI.for_clause(func_iri, 1)) ==
               "https://example.org/code#MyApp/get/1/clause/1"

      assert to_string(IRI.for_clause(func_iri, 2)) ==
               "https://example.org/code#MyApp/get/1/clause/2"
    end

    test "works with string IRI" do
      iri = IRI.for_clause("https://example.org/code#MyApp/get/1", 0)
      assert to_string(iri) == "https://example.org/code#MyApp/get/1/clause/0"
    end
  end

  describe "for_parameter/2" do
    test "generates IRI for first parameter" do
      clause_iri = RDF.iri("https://example.org/code#MyApp/get/1/clause/0")
      iri = IRI.for_parameter(clause_iri, 0)
      assert %RDF.IRI{} = iri
      assert to_string(iri) == "https://example.org/code#MyApp/get/1/clause/0/param/0"
    end

    test "generates IRI for subsequent parameters" do
      clause_iri = RDF.iri("https://example.org/code#MyApp/get/2/clause/0")

      assert to_string(IRI.for_parameter(clause_iri, 0)) ==
               "https://example.org/code#MyApp/get/2/clause/0/param/0"

      assert to_string(IRI.for_parameter(clause_iri, 1)) ==
               "https://example.org/code#MyApp/get/2/clause/0/param/1"
    end

    test "works with string IRI" do
      iri = IRI.for_parameter("https://example.org/code#MyApp/get/1/clause/0", 0)
      assert to_string(iri) == "https://example.org/code#MyApp/get/1/clause/0/param/0"
    end
  end

  describe "for_source_file/2" do
    test "generates IRI for lib file" do
      iri = IRI.for_source_file(@base_iri, "lib/my_app/users.ex")
      assert %RDF.IRI{} = iri
      assert to_string(iri) == "https://example.org/code#file/lib/my_app/users.ex"
    end

    test "generates IRI for test file" do
      iri = IRI.for_source_file(@base_iri, "test/my_app/users_test.exs")
      assert to_string(iri) == "https://example.org/code#file/test/my_app/users_test.exs"
    end

    test "handles deeply nested paths" do
      iri = IRI.for_source_file(@base_iri, "lib/my_app/web/controllers/api/v1/user_controller.ex")

      assert to_string(iri) ==
               "https://example.org/code#file/lib/my_app/web/controllers/api/v1/user_controller.ex"
    end

    test "normalizes Windows path separators" do
      iri = IRI.for_source_file(@base_iri, "lib\\my_app\\users.ex")
      assert to_string(iri) == "https://example.org/code#file/lib/my_app/users.ex"
    end

    test "escapes special characters in filenames" do
      iri = IRI.for_source_file(@base_iri, "lib/my app/file name.ex")
      assert to_string(iri) == "https://example.org/code#file/lib/my%20app/file%20name.ex"
    end
  end

  describe "for_source_location/3" do
    test "generates IRI for line range" do
      file_iri = RDF.iri("https://example.org/code#file/lib/users.ex")
      iri = IRI.for_source_location(file_iri, 10, 25)
      assert %RDF.IRI{} = iri
      assert to_string(iri) == "https://example.org/code#file/lib/users.ex/L10-25"
    end

    test "generates IRI for single line" do
      file_iri = RDF.iri("https://example.org/code#file/lib/users.ex")
      iri = IRI.for_source_location(file_iri, 5, 5)
      assert to_string(iri) == "https://example.org/code#file/lib/users.ex/L5-5"
    end

    test "works with string IRI" do
      iri = IRI.for_source_location("https://example.org/code#file/lib/users.ex", 1, 100)
      assert to_string(iri) == "https://example.org/code#file/lib/users.ex/L1-100"
    end
  end

  describe "for_repository/2" do
    test "generates IRI for repository" do
      iri = IRI.for_repository(@base_iri, "https://github.com/user/repo")
      assert %RDF.IRI{} = iri
      assert to_string(iri) =~ ~r"^https://example.org/code#repo/[a-f0-9]{8}$"
    end

    test "generates consistent IRI for same URL" do
      iri1 = IRI.for_repository(@base_iri, "https://github.com/user/repo")
      iri2 = IRI.for_repository(@base_iri, "https://github.com/user/repo")
      assert iri1 == iri2
    end

    test "generates different IRI for different URLs" do
      iri1 = IRI.for_repository(@base_iri, "https://github.com/user/repo1")
      iri2 = IRI.for_repository(@base_iri, "https://github.com/user/repo2")
      assert iri1 != iri2
    end

    test "handles various URL formats" do
      # HTTPS
      iri1 = IRI.for_repository(@base_iri, "https://github.com/user/repo.git")
      assert %RDF.IRI{} = iri1

      # SSH
      iri2 = IRI.for_repository(@base_iri, "git@github.com:user/repo.git")
      assert %RDF.IRI{} = iri2

      # Different hosts produce different IRIs
      assert iri1 != iri2
    end
  end

  describe "for_commit/2" do
    test "generates IRI for commit" do
      repo_iri = RDF.iri("https://example.org/code#repo/a1b2c3d4")
      iri = IRI.for_commit(repo_iri, "abc123def456")
      assert %RDF.IRI{} = iri
      assert to_string(iri) == "https://example.org/code#repo/a1b2c3d4/commit/abc123def456"
    end

    test "handles short SHA" do
      repo_iri = RDF.iri("https://example.org/code#repo/a1b2c3d4")
      iri = IRI.for_commit(repo_iri, "abc123")
      assert to_string(iri) == "https://example.org/code#repo/a1b2c3d4/commit/abc123"
    end

    test "handles full SHA" do
      repo_iri = RDF.iri("https://example.org/code#repo/a1b2c3d4")
      sha = "abc123def456789012345678901234567890abcd"
      iri = IRI.for_commit(repo_iri, sha)
      assert to_string(iri) == "https://example.org/code#repo/a1b2c3d4/commit/#{sha}"
    end

    test "works with string IRI" do
      iri = IRI.for_commit("https://example.org/code#repo/a1b2c3d4", "abc123")
      assert to_string(iri) == "https://example.org/code#repo/a1b2c3d4/commit/abc123"
    end
  end

  describe "IRI composition" do
    test "can compose complete IRI chain for function parameter" do
      # Module -> Function -> Clause -> Parameter
      mod_iri = IRI.for_module(@base_iri, "MyApp.Users")
      func_iri = IRI.for_function(@base_iri, "MyApp.Users", "get_user", 1)
      clause_iri = IRI.for_clause(func_iri, 0)
      param_iri = IRI.for_parameter(clause_iri, 0)

      assert to_string(mod_iri) == "https://example.org/code#MyApp.Users"
      assert to_string(func_iri) == "https://example.org/code#MyApp.Users/get_user/1"
      assert to_string(clause_iri) == "https://example.org/code#MyApp.Users/get_user/1/clause/0"

      assert to_string(param_iri) ==
               "https://example.org/code#MyApp.Users/get_user/1/clause/0/param/0"
    end

    test "can compose complete IRI chain for source location" do
      # File -> Location
      file_iri = IRI.for_source_file(@base_iri, "lib/my_app/users.ex")
      loc_iri = IRI.for_source_location(file_iri, 10, 20)

      assert to_string(file_iri) == "https://example.org/code#file/lib/my_app/users.ex"
      assert to_string(loc_iri) == "https://example.org/code#file/lib/my_app/users.ex/L10-20"
    end

    test "can compose complete IRI chain for commit" do
      # Repository -> Commit
      repo_iri = IRI.for_repository(@base_iri, "https://github.com/user/repo")
      commit_iri = IRI.for_commit(repo_iri, "abc123")

      assert to_string(repo_iri) =~ ~r"^https://example.org/code#repo/[a-f0-9]{8}$"

      assert to_string(commit_iri) =~
               ~r"^https://example.org/code#repo/[a-f0-9]{8}/commit/abc123$"
    end
  end

  describe "generated IRIs are valid" do
    test "all generated IRIs are valid RDF IRIs" do
      iris = [
        IRI.for_module(@base_iri, "MyApp"),
        IRI.for_function(@base_iri, "MyApp", "func", 1),
        IRI.for_clause(RDF.iri("#{@base_iri}MyApp/func/1"), 0),
        IRI.for_parameter(RDF.iri("#{@base_iri}MyApp/func/1/clause/0"), 0),
        IRI.for_source_file(@base_iri, "lib/app.ex"),
        IRI.for_source_location(RDF.iri("#{@base_iri}file/lib/app.ex"), 1, 10),
        IRI.for_repository(@base_iri, "https://github.com/user/repo"),
        IRI.for_commit(RDF.iri("#{@base_iri}repo/abc"), "123")
      ]

      for iri <- iris do
        assert %RDF.IRI{} = iri
        assert RDF.IRI.valid?(iri)
      end
    end
  end

  # ===========================================================================
  # IRI Utilities Tests (Task 1.3.2)
  # ===========================================================================

  describe "valid?/1" do
    test "returns true for valid RDF IRIs" do
      assert IRI.valid?(RDF.iri("https://example.org/code#MyApp"))
      assert IRI.valid?(RDF.iri("https://example.org/code#MyApp/func/1"))
    end

    test "returns true for valid IRI strings" do
      assert IRI.valid?("https://example.org/code#MyApp")
    end

    test "returns false for invalid IRIs" do
      refute IRI.valid?("not a valid iri")
      refute IRI.valid?("")
      refute IRI.valid?(nil)
    end
  end

  describe "unescape_name/1" do
    test "unescapes question mark" do
      assert IRI.unescape_name("valid%3F") == "valid?"
    end

    test "unescapes exclamation mark" do
      assert IRI.unescape_name("update%21") == "update!"
    end

    test "unescapes pipe operator" do
      assert IRI.unescape_name("%7C%3E") == "|>"
    end

    test "preserves normal names" do
      assert IRI.unescape_name("normal_name") == "normal_name"
    end

    test "round-trip with escape_name" do
      names = ["valid?", "update!", "|>", "++", "normal", "MyApp.Users"]

      for name <- names do
        assert IRI.unescape_name(IRI.escape_name(name)) == name
      end
    end
  end

  describe "parse/1" do
    test "parses module IRI" do
      iri = RDF.iri("https://example.org/code#MyApp.Users")
      assert {:ok, result} = IRI.parse(iri)
      assert result.type == :module
      assert result.base_iri == "https://example.org/code#"
      assert result.module == "MyApp.Users"
    end

    test "parses function IRI" do
      iri = RDF.iri("https://example.org/code#MyApp.Users/get_user/1")
      assert {:ok, result} = IRI.parse(iri)
      assert result.type == :function
      assert result.base_iri == "https://example.org/code#"
      assert result.module == "MyApp.Users"
      assert result.function == "get_user"
      assert result.arity == 1
    end

    test "parses function IRI with escaped characters" do
      iri = RDF.iri("https://example.org/code#MyApp/valid%3F/1")
      assert {:ok, result} = IRI.parse(iri)
      assert result.type == :function
      assert result.function == "valid?"
    end

    test "parses clause IRI" do
      iri = RDF.iri("https://example.org/code#MyApp/get/2/clause/0")
      assert {:ok, result} = IRI.parse(iri)
      assert result.type == :clause
      assert result.module == "MyApp"
      assert result.function == "get"
      assert result.arity == 2
      assert result.clause == 0
    end

    test "parses parameter IRI" do
      iri = RDF.iri("https://example.org/code#MyApp/get/2/clause/0/param/1")
      assert {:ok, result} = IRI.parse(iri)
      assert result.type == :parameter
      assert result.module == "MyApp"
      assert result.function == "get"
      assert result.clause == 0
      assert result.parameter == 1
    end

    test "parses file IRI" do
      iri = RDF.iri("https://example.org/code#file/lib/my_app/users.ex")
      assert {:ok, result} = IRI.parse(iri)
      assert result.type == :file
      assert result.base_iri == "https://example.org/code#"
      assert result.path == "lib/my_app/users.ex"
    end

    test "parses file IRI with spaces" do
      iri = RDF.iri("https://example.org/code#file/lib/my%20app/users.ex")
      assert {:ok, result} = IRI.parse(iri)
      assert result.type == :file
      assert result.path == "lib/my app/users.ex"
    end

    test "parses location IRI" do
      iri = RDF.iri("https://example.org/code#file/lib/users.ex/L10-25")
      assert {:ok, result} = IRI.parse(iri)
      assert result.type == :location
      assert result.path == "lib/users.ex"
      assert result.start_line == 10
      assert result.end_line == 25
    end

    test "parses repository IRI" do
      iri = RDF.iri("https://example.org/code#repo/a1b2c3d4")
      assert {:ok, result} = IRI.parse(iri)
      assert result.type == :repository
      assert result.base_iri == "https://example.org/code#"
      assert result.repo_hash == "a1b2c3d4"
    end

    test "parses commit IRI" do
      iri = RDF.iri("https://example.org/code#repo/a1b2c3d4/commit/abc123def")
      assert {:ok, result} = IRI.parse(iri)
      assert result.type == :commit
      assert result.repo_hash == "a1b2c3d4"
      assert result.sha == "abc123def"
    end

    test "returns error for unknown pattern" do
      assert {:error, _} = IRI.parse("https://example.org/unknown")
    end

    test "works with string input" do
      assert {:ok, result} = IRI.parse("https://example.org/code#MyApp")
      assert result.type == :module
    end
  end

  describe "module_from_iri/1" do
    test "extracts module from module IRI" do
      iri = RDF.iri("https://example.org/code#MyApp.Users")
      assert {:ok, "MyApp.Users"} = IRI.module_from_iri(iri)
    end

    test "extracts module from function IRI" do
      iri = RDF.iri("https://example.org/code#MyApp.Users/get_user/1")
      assert {:ok, "MyApp.Users"} = IRI.module_from_iri(iri)
    end

    test "extracts module from clause IRI" do
      iri = RDF.iri("https://example.org/code#MyApp.Users/get/1/clause/0")
      assert {:ok, "MyApp.Users"} = IRI.module_from_iri(iri)
    end

    test "extracts module from parameter IRI" do
      iri = RDF.iri("https://example.org/code#MyApp.Users/get/1/clause/0/param/0")
      assert {:ok, "MyApp.Users"} = IRI.module_from_iri(iri)
    end

    test "returns error for file IRI" do
      iri = RDF.iri("https://example.org/code#file/lib/app.ex")
      assert {:error, "Not a module or function IRI"} = IRI.module_from_iri(iri)
    end

    test "returns error for repository IRI" do
      iri = RDF.iri("https://example.org/code#repo/abc123")
      assert {:error, "Not a module or function IRI"} = IRI.module_from_iri(iri)
    end
  end

  describe "function_from_iri/1" do
    test "extracts function from function IRI" do
      iri = RDF.iri("https://example.org/code#MyApp.Users/get_user/1")
      assert {:ok, {"MyApp.Users", "get_user", 1}} = IRI.function_from_iri(iri)
    end

    test "extracts function with escaped characters" do
      iri = RDF.iri("https://example.org/code#MyApp/valid%3F/1")
      assert {:ok, {"MyApp", "valid?", 1}} = IRI.function_from_iri(iri)
    end

    test "extracts function from clause IRI" do
      iri = RDF.iri("https://example.org/code#MyApp/get/2/clause/0")
      assert {:ok, {"MyApp", "get", 2}} = IRI.function_from_iri(iri)
    end

    test "extracts function from parameter IRI" do
      iri = RDF.iri("https://example.org/code#MyApp/get/2/clause/0/param/1")
      assert {:ok, {"MyApp", "get", 2}} = IRI.function_from_iri(iri)
    end

    test "returns error for module IRI" do
      iri = RDF.iri("https://example.org/code#MyApp.Users")
      assert {:error, "Not a function IRI"} = IRI.function_from_iri(iri)
    end

    test "returns error for file IRI" do
      iri = RDF.iri("https://example.org/code#file/lib/app.ex")
      assert {:error, "Not a function IRI"} = IRI.function_from_iri(iri)
    end
  end

  describe "round-trip: generate → parse → verify" do
    test "module round-trip" do
      module_name = "MyApp.Accounts.User"
      iri = IRI.for_module(@base_iri, module_name)
      assert {:ok, parsed} = IRI.parse(iri)
      assert parsed.type == :module
      assert parsed.module == module_name
    end

    test "function round-trip" do
      module = "MyApp.Users"
      func = "get_user"
      arity = 2

      iri = IRI.for_function(@base_iri, module, func, arity)
      assert {:ok, parsed} = IRI.parse(iri)
      assert parsed.type == :function
      assert parsed.module == module
      assert parsed.function == func
      assert parsed.arity == arity
    end

    test "function with special characters round-trip" do
      module = "MyApp"
      func = "valid?"
      arity = 1

      iri = IRI.for_function(@base_iri, module, func, arity)
      assert {:ok, parsed} = IRI.parse(iri)
      assert parsed.function == func
    end

    test "clause round-trip" do
      func_iri = IRI.for_function(@base_iri, "MyApp", "get", 1)
      clause_iri = IRI.for_clause(func_iri, 2)

      assert {:ok, parsed} = IRI.parse(clause_iri)
      assert parsed.type == :clause
      assert parsed.module == "MyApp"
      assert parsed.function == "get"
      assert parsed.arity == 1
      assert parsed.clause == 2
    end

    test "parameter round-trip" do
      func_iri = IRI.for_function(@base_iri, "MyApp", "get", 2)
      clause_iri = IRI.for_clause(func_iri, 0)
      param_iri = IRI.for_parameter(clause_iri, 1)

      assert {:ok, parsed} = IRI.parse(param_iri)
      assert parsed.type == :parameter
      assert parsed.module == "MyApp"
      assert parsed.function == "get"
      assert parsed.clause == 0
      assert parsed.parameter == 1
    end

    test "file round-trip" do
      path = "lib/my_app/users.ex"
      iri = IRI.for_source_file(@base_iri, path)

      assert {:ok, parsed} = IRI.parse(iri)
      assert parsed.type == :file
      assert parsed.path == path
    end

    test "location round-trip" do
      file_iri = IRI.for_source_file(@base_iri, "lib/users.ex")
      loc_iri = IRI.for_source_location(file_iri, 10, 25)

      assert {:ok, parsed} = IRI.parse(loc_iri)
      assert parsed.type == :location
      assert parsed.path == "lib/users.ex"
      assert parsed.start_line == 10
      assert parsed.end_line == 25
    end

    test "repository round-trip" do
      iri = IRI.for_repository(@base_iri, "https://github.com/user/repo")
      assert {:ok, parsed} = IRI.parse(iri)
      assert parsed.type == :repository
      assert String.length(parsed.repo_hash) == 8
    end

    test "commit round-trip" do
      repo_iri = IRI.for_repository(@base_iri, "https://github.com/user/repo")
      commit_iri = IRI.for_commit(repo_iri, "abc123def")

      assert {:ok, parsed} = IRI.parse(commit_iri)
      assert parsed.type == :commit
      assert parsed.sha == "abc123def"
    end

    test "module_from_iri round-trip" do
      module = "MyApp.Accounts.User"
      iri = IRI.for_module(@base_iri, module)
      assert {:ok, ^module} = IRI.module_from_iri(iri)
    end

    test "function_from_iri round-trip" do
      module = "MyApp.Users"
      func = "update!"
      arity = 2

      iri = IRI.for_function(@base_iri, module, func, arity)
      assert {:ok, {^module, ^func, ^arity}} = IRI.function_from_iri(iri)
    end
  end

  # ===========================================================================
  # Error Path Tests (for 90%+ coverage)
  # ===========================================================================

  describe "error paths" do
    test "parse returns error for completely malformed IRI" do
      assert {:error, _} = IRI.parse("not-a-valid-iri")
      assert {:error, _} = IRI.parse("https://example.org/no-hash-separator")
    end

    test "parse returns error for IRI with lowercase module name" do
      # Module names must start with uppercase
      assert {:error, _} = IRI.parse("https://example.org/code#lowercase")
    end

    test "parse returns error for empty fragment" do
      assert {:error, _} = IRI.parse("https://example.org/code#")
    end

    test "module_from_iri returns error for completely invalid IRI" do
      assert {:error, _} = IRI.module_from_iri("not-valid")
    end

    test "module_from_iri returns error for location IRI" do
      iri = RDF.iri("https://example.org/code#file/lib/app.ex/L10-20")
      assert {:error, "Not a module or function IRI"} = IRI.module_from_iri(iri)
    end

    test "module_from_iri returns error for commit IRI" do
      iri = RDF.iri("https://example.org/code#repo/abc12345/commit/def67890")
      assert {:error, "Not a module or function IRI"} = IRI.module_from_iri(iri)
    end

    test "function_from_iri returns error for completely invalid IRI" do
      assert {:error, _} = IRI.function_from_iri("not-valid")
    end

    test "function_from_iri returns error for location IRI" do
      iri = RDF.iri("https://example.org/code#file/lib/app.ex/L10-20")
      assert {:error, "Not a function IRI"} = IRI.function_from_iri(iri)
    end

    test "function_from_iri returns error for repository IRI" do
      iri = RDF.iri("https://example.org/code#repo/abc12345")
      assert {:error, "Not a function IRI"} = IRI.function_from_iri(iri)
    end

    test "function_from_iri returns error for commit IRI" do
      iri = RDF.iri("https://example.org/code#repo/abc12345/commit/def67890")
      assert {:error, "Not a function IRI"} = IRI.function_from_iri(iri)
    end
  end

  describe "input validation" do
    test "for_source_location validates line numbers are positive" do
      file_iri = IRI.for_source_file(@base_iri, "lib/app.ex")

      # Valid case
      assert %RDF.IRI{} = IRI.for_source_location(file_iri, 1, 10)

      # Invalid: zero or negative start_line
      assert_raise FunctionClauseError, fn ->
        IRI.for_source_location(file_iri, 0, 10)
      end

      assert_raise FunctionClauseError, fn ->
        IRI.for_source_location(file_iri, -1, 10)
      end
    end

    test "for_source_location validates end_line >= start_line" do
      file_iri = IRI.for_source_file(@base_iri, "lib/app.ex")

      # Valid: end_line == start_line (single line)
      assert %RDF.IRI{} = IRI.for_source_location(file_iri, 5, 5)

      # Invalid: end_line < start_line
      assert_raise FunctionClauseError, fn ->
        IRI.for_source_location(file_iri, 10, 5)
      end
    end

    test "for_clause validates clause_order is non-negative" do
      func_iri = IRI.for_function(@base_iri, "MyApp", "get", 1)

      # Valid case
      assert %RDF.IRI{} = IRI.for_clause(func_iri, 0)

      # Invalid: negative clause order
      assert_raise FunctionClauseError, fn ->
        IRI.for_clause(func_iri, -1)
      end
    end

    test "for_parameter validates position is non-negative" do
      func_iri = IRI.for_function(@base_iri, "MyApp", "get", 1)
      clause_iri = IRI.for_clause(func_iri, 0)

      # Valid case
      assert %RDF.IRI{} = IRI.for_parameter(clause_iri, 0)

      # Invalid: negative position
      assert_raise FunctionClauseError, fn ->
        IRI.for_parameter(clause_iri, -1)
      end
    end

    test "for_function validates arity is non-negative" do
      # Valid case
      assert %RDF.IRI{} = IRI.for_function(@base_iri, "MyApp", "get", 0)

      # Invalid: negative arity
      assert_raise FunctionClauseError, fn ->
        IRI.for_function(@base_iri, "MyApp", "get", -1)
      end
    end
  end
end
