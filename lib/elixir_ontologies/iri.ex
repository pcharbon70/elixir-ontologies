defmodule ElixirOntologies.IRI do
  @moduledoc """
  IRI generation for Elixir code elements.

  This module generates stable, path-based IRIs that reflect Elixir's identity model.
  IRIs are designed to be:
  - **Stable**: Same code element always produces the same IRI
  - **Readable**: IRIs reflect the code structure (Module/function/arity)
  - **Valid**: All special characters are properly URL-encoded

  ## IRI Patterns

  | Element | Pattern | Example |
  |---------|---------|---------|
  | Module | `{base}{ModuleName}` | `https://example.org/code#MyApp.Users` |
  | Function | `{base}{Module}/{name}/{arity}` | `https://example.org/code#MyApp.Users/get_user/1` |
  | Clause | `{function_iri}/clause/{N}` | `...get_user/1/clause/0` |
  | Parameter | `{clause_iri}/param/{N}` | `...clause/0/param/0` |
  | File | `{base}file/{path}` | `https://example.org/code#file/lib/users.ex` |
  | Location | `{file_iri}/L{start}-{end}` | `...users.ex/L10-25` |
  | Repository | `{base}repo/{hash}` | `https://example.org/code#repo/a1b2c3` |
  | Commit | `{repo_iri}/commit/{sha}` | `...repo/a1b2c3/commit/abc123` |

  ## Usage

      alias ElixirOntologies.IRI

      base = "https://example.org/code#"

      # Generate module IRI
      IRI.for_module(base, "MyApp.Users")
      #=> ~I<https://example.org/code#MyApp.Users>

      # Generate function IRI
      IRI.for_function(base, "MyApp.Users", "get_user", 1)
      #=> ~I<https://example.org/code#MyApp.Users/get_user/1>

      # Special characters are escaped
      IRI.for_function(base, "MyApp.Users", "valid?", 1)
      #=> ~I<https://example.org/code#MyApp.Users/valid%3F/1>
  """

  @doc """
  Escapes special characters in a name for safe IRI inclusion.

  Elixir allows characters like `?`, `!`, and operators in function names
  that need to be URL-encoded in IRIs.

  ## Examples

      iex> ElixirOntologies.IRI.escape_name("valid?")
      "valid%3F"

      iex> ElixirOntologies.IRI.escape_name("update!")
      "update%21"

      iex> ElixirOntologies.IRI.escape_name("|>")
      "%7C%3E"

      iex> ElixirOntologies.IRI.escape_name("normal_name")
      "normal_name"
  """
  @spec escape_name(String.t() | atom()) :: String.t()
  def escape_name(name) when is_atom(name), do: escape_name(Atom.to_string(name))

  def escape_name(name) when is_binary(name) do
    # URI.encode/2 with a custom set of allowed characters
    # We allow alphanumerics, underscore, and dot (for module names)
    # Everything else gets percent-encoded
    URI.encode(name, &uri_safe_char?/1)
  end

  # Characters that are safe in our IRI paths (don't need encoding)
  defp uri_safe_char?(char) do
    # alphanumeric, underscore, dot, hyphen
    char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char in [?_, ?., ?-]
  end

  @doc """
  Generates an IRI for a module.

  ## Parameters

  - `base_iri` - The base IRI (should end with `#` or `/`)
  - `module_name` - The module name as string or atom (e.g., `"MyApp.Users"` or `MyApp.Users`)

  ## Examples

      iex> ElixirOntologies.IRI.for_module("https://example.org/code#", "MyApp.Users")
      ~I<https://example.org/code#MyApp.Users>

      iex> ElixirOntologies.IRI.for_module("https://example.org/code#", MyApp.Users)
      ~I<https://example.org/code#MyApp.Users>
  """
  @spec for_module(String.t() | RDF.IRI.t(), String.t() | atom()) :: RDF.IRI.t()
  def for_module(base_iri, module_name) do
    base = to_string(base_iri)
    name = module_to_string(module_name)
    RDF.iri(base <> escape_name(name))
  end

  @doc """
  Generates an IRI for a function.

  Functions are identified by their module, name, and arity.

  ## Parameters

  - `base_iri` - The base IRI
  - `module` - The module name
  - `function_name` - The function name
  - `arity` - The function arity

  ## Examples

      iex> ElixirOntologies.IRI.for_function("https://example.org/code#", "MyApp.Users", "get_user", 1)
      ~I<https://example.org/code#MyApp.Users/get_user/1>

      iex> ElixirOntologies.IRI.for_function("https://example.org/code#", "MyApp", "valid?", 1)
      ~I<https://example.org/code#MyApp/valid%3F/1>
  """
  @spec for_function(String.t() | RDF.IRI.t(), String.t() | atom(), String.t() | atom(), non_neg_integer()) :: RDF.IRI.t()
  def for_function(base_iri, module, function_name, arity) do
    base = to_string(base_iri)
    mod = module_to_string(module)
    func = escape_name(function_name)
    RDF.iri("#{base}#{escape_name(mod)}/#{func}/#{arity}")
  end

  @doc """
  Generates an IRI for a function clause.

  Clauses are ordered by their position (0-indexed).

  ## Parameters

  - `function_iri` - The IRI of the function
  - `clause_order` - The clause position (0-indexed)

  ## Examples

      iex> func_iri = RDF.iri("https://example.org/code#MyApp/get/1")
      iex> ElixirOntologies.IRI.for_clause(func_iri, 0)
      ~I<https://example.org/code#MyApp/get/1/clause/0>
  """
  @spec for_clause(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_clause(function_iri, clause_order) do
    base = to_string(function_iri)
    RDF.iri("#{base}/clause/#{clause_order}")
  end

  @doc """
  Generates an IRI for a function parameter.

  Parameters are identified by their position within a clause (0-indexed).

  ## Parameters

  - `clause_iri` - The IRI of the function clause
  - `position` - The parameter position (0-indexed)

  ## Examples

      iex> clause_iri = RDF.iri("https://example.org/code#MyApp/get/1/clause/0")
      iex> ElixirOntologies.IRI.for_parameter(clause_iri, 0)
      ~I<https://example.org/code#MyApp/get/1/clause/0/param/0>
  """
  @spec for_parameter(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_parameter(clause_iri, position) do
    base = to_string(clause_iri)
    RDF.iri("#{base}/param/#{position}")
  end

  @doc """
  Generates an IRI for a source file.

  ## Parameters

  - `base_iri` - The base IRI
  - `relative_path` - The file path relative to the project root

  ## Examples

      iex> ElixirOntologies.IRI.for_source_file("https://example.org/code#", "lib/my_app/users.ex")
      ~I<https://example.org/code#file/lib/my_app/users.ex>

      iex> ElixirOntologies.IRI.for_source_file("https://example.org/code#", "test/my_app_test.exs")
      ~I<https://example.org/code#file/test/my_app_test.exs>
  """
  @spec for_source_file(String.t() | RDF.IRI.t(), String.t()) :: RDF.IRI.t()
  def for_source_file(base_iri, relative_path) do
    base = to_string(base_iri)
    # Normalize path separators and encode special characters
    path = relative_path |> String.replace("\\", "/") |> encode_path()
    RDF.iri("#{base}file/#{path}")
  end

  @doc """
  Generates an IRI for a source location (line range).

  ## Parameters

  - `file_iri` - The IRI of the source file
  - `start_line` - The starting line number
  - `end_line` - The ending line number

  ## Examples

      iex> file_iri = RDF.iri("https://example.org/code#file/lib/users.ex")
      iex> ElixirOntologies.IRI.for_source_location(file_iri, 10, 25)
      ~I<https://example.org/code#file/lib/users.ex/L10-25>

      iex> file_iri = RDF.iri("https://example.org/code#file/lib/users.ex")
      iex> ElixirOntologies.IRI.for_source_location(file_iri, 5, 5)
      ~I<https://example.org/code#file/lib/users.ex/L5-5>
  """
  @spec for_source_location(String.t() | RDF.IRI.t(), pos_integer(), pos_integer()) :: RDF.IRI.t()
  def for_source_location(file_iri, start_line, end_line) do
    base = to_string(file_iri)
    RDF.iri("#{base}/L#{start_line}-#{end_line}")
  end

  @doc """
  Generates an IRI for a repository.

  The repository URL is hashed to create a stable, shorter identifier.

  ## Parameters

  - `base_iri` - The base IRI
  - `repo_url` - The repository URL (e.g., GitHub URL)

  ## Examples

      iex> iri = ElixirOntologies.IRI.for_repository("https://example.org/code#", "https://github.com/user/repo")
      iex> to_string(iri) |> String.starts_with?("https://example.org/code#repo/")
      true
  """
  @spec for_repository(String.t() | RDF.IRI.t(), String.t()) :: RDF.IRI.t()
  def for_repository(base_iri, repo_url) do
    base = to_string(base_iri)
    # Use first 8 characters of SHA256 hash for shorter, stable identifier
    hash = :crypto.hash(:sha256, repo_url) |> Base.encode16(case: :lower) |> String.slice(0, 8)
    RDF.iri("#{base}repo/#{hash}")
  end

  @doc """
  Generates an IRI for a commit.

  ## Parameters

  - `repo_iri` - The IRI of the repository
  - `sha` - The commit SHA (full or abbreviated)

  ## Examples

      iex> repo_iri = RDF.iri("https://example.org/code#repo/a1b2c3d4")
      iex> ElixirOntologies.IRI.for_commit(repo_iri, "abc123def456")
      ~I<https://example.org/code#repo/a1b2c3d4/commit/abc123def456>
  """
  @spec for_commit(String.t() | RDF.IRI.t(), String.t()) :: RDF.IRI.t()
  def for_commit(repo_iri, sha) do
    base = to_string(repo_iri)
    RDF.iri("#{base}/commit/#{sha}")
  end

  # Helper to convert module atom to string representation
  defp module_to_string(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  defp module_to_string(module) when is_binary(module), do: module

  # Encode path components while preserving slashes
  defp encode_path(path) do
    path
    |> String.split("/")
    |> Enum.map(&escape_name/1)
    |> Enum.join("/")
  end
end
