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

  # ===========================================================================
  # IRI Utilities
  # ===========================================================================

  @doc """
  Checks if an IRI is valid.

  Delegates to `RDF.IRI.valid?/1`.

  ## Examples

      iex> ElixirOntologies.IRI.valid?(RDF.iri("https://example.org/code#MyApp"))
      true

      iex> ElixirOntologies.IRI.valid?("not a valid iri")
      false
  """
  @spec valid?(any()) :: boolean()
  def valid?(iri) do
    RDF.IRI.valid?(iri)
  end

  @doc """
  Parses an IRI into its component parts.

  Returns a map with the IRI type and its components, or `{:error, reason}`
  if the IRI doesn't match any known pattern.

  ## Supported Types

  - `:module` - Module IRI (e.g., `base#MyApp.Users`)
  - `:function` - Function IRI (e.g., `base#MyApp/get_user/1`)
  - `:clause` - Clause IRI (e.g., `.../clause/0`)
  - `:parameter` - Parameter IRI (e.g., `.../param/0`)
  - `:file` - File IRI (e.g., `base#file/lib/users.ex`)
  - `:location` - Location IRI (e.g., `.../L10-25`)
  - `:repository` - Repository IRI (e.g., `base#repo/a1b2c3d4`)
  - `:commit` - Commit IRI (e.g., `.../commit/abc123`)

  ## Examples

      iex> {:ok, result} = ElixirOntologies.IRI.parse(RDF.iri("https://example.org/code#MyApp.Users"))
      iex> result.type
      :module
      iex> result.module
      "MyApp.Users"

      iex> {:ok, result} = ElixirOntologies.IRI.parse(RDF.iri("https://example.org/code#MyApp/get/1"))
      iex> result.type
      :function
      iex> result.module
      "MyApp"
      iex> result.function
      "get"
      iex> result.arity
      1
  """
  @spec parse(String.t() | RDF.IRI.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(iri) do
    iri_string = to_string(iri)

    cond do
      # Parameter IRI: .../clause/N/param/N
      match = Regex.run(~r/^(.+)\/clause\/(\d+)\/param\/(\d+)$/, iri_string) ->
        [_, parent, clause, param] = match
        {:ok, parse_parameter(parent, clause, param)}

      # Clause IRI: .../N/clause/N
      match = Regex.run(~r/^(.+)\/(\d+)\/clause\/(\d+)$/, iri_string) ->
        [_, parent, arity, clause] = match
        {:ok, parse_clause(parent, arity, clause)}

      # Location IRI: .../L{start}-{end}
      match = Regex.run(~r/^(.+)\/L(\d+)-(\d+)$/, iri_string) ->
        [_, file_iri, start_line, end_line] = match
        {:ok, parse_location(file_iri, start_line, end_line)}

      # Commit IRI: .../repo/hash/commit/sha
      match = Regex.run(~r/^(.+#repo\/[a-f0-9]+)\/commit\/([a-f0-9]+)$/, iri_string) ->
        [_, repo_iri, sha] = match
        {:ok, parse_commit(repo_iri, sha)}

      # Repository IRI: base#repo/hash
      match = Regex.run(~r/^(.+#)repo\/([a-f0-9]+)$/, iri_string) ->
        [_, base, hash] = match
        {:ok, %{type: :repository, base_iri: base, repo_hash: hash}}

      # File IRI: base#file/path
      match = Regex.run(~r/^(.+#)file\/(.+)$/, iri_string) ->
        [_, base, path] = match
        {:ok, %{type: :file, base_iri: base, path: URI.decode(path)}}

      # Function IRI: base#Module/name/arity
      match = Regex.run(~r/^(.+#)([A-Z][A-Za-z0-9_.%]*)\/([^\/]+)\/(\d+)$/, iri_string) ->
        [_, base, module, func, arity] = match
        {:ok, %{
          type: :function,
          base_iri: base,
          module: URI.decode(module),
          function: URI.decode(func),
          arity: String.to_integer(arity)
        }}

      # Module IRI: base#ModuleName (must start with uppercase)
      match = Regex.run(~r/^(.+#)([A-Z][A-Za-z0-9_.%]*)$/, iri_string) ->
        [_, base, module] = match
        {:ok, %{type: :module, base_iri: base, module: URI.decode(module)}}

      true ->
        {:error, "Unknown IRI pattern: #{iri_string}"}
    end
  end

  @doc """
  Extracts the module name from a module or function IRI.

  ## Examples

      iex> ElixirOntologies.IRI.module_from_iri(RDF.iri("https://example.org/code#MyApp.Users"))
      {:ok, "MyApp.Users"}

      iex> ElixirOntologies.IRI.module_from_iri(RDF.iri("https://example.org/code#MyApp.Users/get_user/1"))
      {:ok, "MyApp.Users"}

      iex> ElixirOntologies.IRI.module_from_iri(RDF.iri("https://example.org/code#file/lib/app.ex"))
      {:error, "Not a module or function IRI"}
  """
  @spec module_from_iri(String.t() | RDF.IRI.t()) :: {:ok, String.t()} | {:error, String.t()}
  def module_from_iri(iri) do
    case parse(iri) do
      {:ok, %{type: :module, module: module}} -> {:ok, module}
      {:ok, %{type: :function, module: module}} -> {:ok, module}
      {:ok, %{type: :clause}} -> extract_module_from_clause(iri)
      {:ok, %{type: :parameter}} -> extract_module_from_parameter(iri)
      {:ok, _} -> {:error, "Not a module or function IRI"}
      {:error, _} = error -> error
    end
  end

  @doc """
  Extracts the function signature from a function IRI.

  Returns `{:ok, {module, function_name, arity}}` or an error.

  ## Examples

      iex> ElixirOntologies.IRI.function_from_iri(RDF.iri("https://example.org/code#MyApp.Users/get_user/1"))
      {:ok, {"MyApp.Users", "get_user", 1}}

      iex> ElixirOntologies.IRI.function_from_iri(RDF.iri("https://example.org/code#MyApp/valid%3F/1"))
      {:ok, {"MyApp", "valid?", 1}}

      iex> ElixirOntologies.IRI.function_from_iri(RDF.iri("https://example.org/code#MyApp.Users"))
      {:error, "Not a function IRI"}
  """
  @spec function_from_iri(String.t() | RDF.IRI.t()) :: {:ok, {String.t(), String.t(), non_neg_integer()}} | {:error, String.t()}
  def function_from_iri(iri) do
    case parse(iri) do
      {:ok, %{type: :function, module: module, function: func, arity: arity}} ->
        {:ok, {module, func, arity}}
      {:ok, %{type: :clause}} ->
        extract_function_from_clause(iri)
      {:ok, %{type: :parameter}} ->
        extract_function_from_parameter(iri)
      {:ok, _} ->
        {:error, "Not a function IRI"}
      {:error, _} = error ->
        error
    end
  end

  @doc """
  Unescapes URL-encoded characters in a name.

  This is the inverse of `escape_name/1`.

  ## Examples

      iex> ElixirOntologies.IRI.unescape_name("valid%3F")
      "valid?"

      iex> ElixirOntologies.IRI.unescape_name("update%21")
      "update!"

      iex> ElixirOntologies.IRI.unescape_name("normal_name")
      "normal_name"
  """
  @spec unescape_name(String.t()) :: String.t()
  def unescape_name(name) when is_binary(name) do
    URI.decode(name)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

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

  # Parse helpers for complex IRI types
  defp parse_parameter(parent, clause, param) do
    # parent is the function IRI: base#Module/func/arity
    # We need to extract module, func, and arity from it
    case Regex.run(~r/^(.+#)([A-Z][A-Za-z0-9_.%]*)\/([^\/]+)\/(\d+)$/, parent) do
      [_, base, module, func, arity] ->
        %{
          type: :parameter,
          base_iri: base,
          module: URI.decode(module),
          function: URI.decode(func),
          arity: String.to_integer(arity),
          clause: String.to_integer(clause),
          parameter: String.to_integer(param)
        }
      _ ->
        %{type: :parameter, clause: String.to_integer(clause), parameter: String.to_integer(param)}
    end
  end

  defp parse_clause(parent, arity, clause) do
    # parent is base#Module/func, arity is the function arity
    case Regex.run(~r/^(.+#)([A-Z][A-Za-z0-9_.%]*)\/([^\/]+)$/, parent) do
      [_, base, module, func] ->
        %{
          type: :clause,
          base_iri: base,
          module: URI.decode(module),
          function: URI.decode(func),
          arity: String.to_integer(arity),
          clause: String.to_integer(clause)
        }
      _ ->
        %{type: :clause, arity: String.to_integer(arity), clause: String.to_integer(clause)}
    end
  end

  defp parse_location(file_iri, start_line, end_line) do
    case Regex.run(~r/^(.+#)file\/(.+)$/, file_iri) do
      [_, base, path] ->
        %{
          type: :location,
          base_iri: base,
          path: URI.decode(path),
          start_line: String.to_integer(start_line),
          end_line: String.to_integer(end_line)
        }
      _ ->
        %{
          type: :location,
          start_line: String.to_integer(start_line),
          end_line: String.to_integer(end_line)
        }
    end
  end

  defp parse_commit(repo_iri, sha) do
    case Regex.run(~r/^(.+#)repo\/([a-f0-9]+)$/, repo_iri) do
      [_, base, hash] ->
        %{type: :commit, base_iri: base, repo_hash: hash, sha: sha}
      _ ->
        %{type: :commit, sha: sha}
    end
  end

  defp extract_module_from_clause(iri) do
    iri_string = to_string(iri)
    # Remove /clause/N from the end, then parse as function
    case Regex.run(~r/^(.+)\/clause\/\d+$/, iri_string) do
      [_, func_iri] -> module_from_iri(func_iri)
      _ -> {:error, "Could not extract module from clause IRI"}
    end
  end

  defp extract_module_from_parameter(iri) do
    iri_string = to_string(iri)
    # Remove /param/N from the end, then delegate to clause extraction
    case Regex.run(~r/^(.+)\/param\/\d+$/, iri_string) do
      [_, clause_iri] -> extract_module_from_clause(clause_iri)
      _ -> {:error, "Could not extract module from parameter IRI"}
    end
  end

  defp extract_function_from_clause(iri) do
    iri_string = to_string(iri)
    # Remove /clause/N from the end, then parse as function
    case Regex.run(~r/^(.+)\/clause\/\d+$/, iri_string) do
      [_, func_iri] -> function_from_iri(func_iri)
      _ -> {:error, "Could not extract function from clause IRI"}
    end
  end

  defp extract_function_from_parameter(iri) do
    iri_string = to_string(iri)
    # Remove /param/N from the end, then delegate to clause extraction
    case Regex.run(~r/^(.+)\/param\/\d+$/, iri_string) do
      [_, clause_iri] -> extract_function_from_clause(clause_iri)
      _ -> {:error, "Could not extract function from parameter IRI"}
    end
  end
end
