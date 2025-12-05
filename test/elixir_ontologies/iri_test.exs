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
      assert IRI.escape_name("-") == "-"  # hyphen is safe
      assert IRI.escape_name("*") == "%2A"
      assert IRI.escape_name("/") == "%2F"
      assert IRI.escape_name("<>") == "%3C%3E"
      assert IRI.escape_name("++") == "%2B%2B"
      assert IRI.escape_name("--") == "--"  # hyphens are safe
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
      assert to_string(IRI.for_clause(func_iri, 1)) == "https://example.org/code#MyApp/get/1/clause/1"
      assert to_string(IRI.for_clause(func_iri, 2)) == "https://example.org/code#MyApp/get/1/clause/2"
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
      assert to_string(IRI.for_parameter(clause_iri, 0)) == "https://example.org/code#MyApp/get/2/clause/0/param/0"
      assert to_string(IRI.for_parameter(clause_iri, 1)) == "https://example.org/code#MyApp/get/2/clause/0/param/1"
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
      assert to_string(iri) == "https://example.org/code#file/lib/my_app/web/controllers/api/v1/user_controller.ex"
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
      assert to_string(param_iri) == "https://example.org/code#MyApp.Users/get_user/1/clause/0/param/0"
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
      assert to_string(commit_iri) =~ ~r"^https://example.org/code#repo/[a-f0-9]{8}/commit/abc123$"
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
end
