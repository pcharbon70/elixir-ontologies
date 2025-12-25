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

  # ===========================================================================
  # Module Constants
  # ===========================================================================

  # Repository hash length (first N characters of SHA256)
  @repo_hash_length 8

  # Compile-time regex patterns for IRI parsing
  @regex_parameter ~r/^(.+)\/clause\/(\d+)\/param\/(\d+)$/
  @regex_clause ~r/^(.+)\/(\d+)\/clause\/(\d+)$/
  @regex_location ~r/^(.+)\/L(\d+)-(\d+)$/
  @regex_commit ~r/^(.+#repo\/[a-f0-9]+)\/commit\/([a-f0-9]+)$/
  @regex_repository ~r/^(.+#)repo\/([a-f0-9]+)$/
  @regex_file ~r/^(.+#)file\/(.+)$/
  @regex_function ~r/^(.+#)([A-Z][A-Za-z0-9_.%]*)\/([^\/]+)\/(\d+)$/
  @regex_module ~r/^(.+#)([A-Z][A-Za-z0-9_.%]*)$/
  @regex_function_prefix ~r/^(.+#)([A-Z][A-Za-z0-9_.%]*)\/([^\/]+)$/
  @regex_strip_clause ~r/^(.+)\/clause\/\d+$/
  @regex_strip_param ~r/^(.+)\/param\/\d+$/

  # ===========================================================================
  # Name Escaping
  # ===========================================================================

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
    URI.encode(name, &uri_safe_char?/1)
  end

  # Characters that are safe in our IRI paths (don't need encoding)
  defp uri_safe_char?(char) do
    char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char in [?_, ?., ?-]
  end

  # ===========================================================================
  # IRI Generation
  # ===========================================================================

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
    name = module_name |> module_to_string() |> escape_name()
    build_iri(base_iri, name)
  end

  @doc """
  Generates an IRI for a function.

  Functions are identified by their module, name, and arity.

  ## Parameters

  - `base_iri` - The base IRI
  - `module` - The module name
  - `function_name` - The function name
  - `arity` - The function arity (must be non-negative)

  ## Examples

      iex> ElixirOntologies.IRI.for_function("https://example.org/code#", "MyApp.Users", "get_user", 1)
      ~I<https://example.org/code#MyApp.Users/get_user/1>

      iex> ElixirOntologies.IRI.for_function("https://example.org/code#", "MyApp", "valid?", 1)
      ~I<https://example.org/code#MyApp/valid%3F/1>
  """
  @spec for_function(
          String.t() | RDF.IRI.t(),
          String.t() | atom(),
          String.t() | atom(),
          non_neg_integer()
        ) :: RDF.IRI.t()
  def for_function(base_iri, module, function_name, arity)
      when is_integer(arity) and arity >= 0 do
    mod = module |> module_to_string() |> escape_name()
    func = escape_name(function_name)
    build_iri(base_iri, "#{mod}/#{func}/#{arity}")
  end

  @doc """
  Generates an IRI for a function clause.

  Clauses are ordered by their position (0-indexed).

  ## Parameters

  - `function_iri` - The IRI of the function
  - `clause_order` - The clause position (0-indexed, must be non-negative)

  ## Examples

      iex> func_iri = RDF.iri("https://example.org/code#MyApp/get/1")
      iex> ElixirOntologies.IRI.for_clause(func_iri, 0)
      ~I<https://example.org/code#MyApp/get/1/clause/0>
  """
  @spec for_clause(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_clause(function_iri, clause_order)
      when is_integer(clause_order) and clause_order >= 0 do
    append_to_iri(function_iri, "clause/#{clause_order}")
  end

  @doc """
  Generates an IRI for a function parameter.

  Parameters are identified by their position within a clause (0-indexed).

  ## Parameters

  - `clause_iri` - The IRI of the function clause
  - `position` - The parameter position (0-indexed, must be non-negative)

  ## Examples

      iex> clause_iri = RDF.iri("https://example.org/code#MyApp/get/1/clause/0")
      iex> ElixirOntologies.IRI.for_parameter(clause_iri, 0)
      ~I<https://example.org/code#MyApp/get/1/clause/0/param/0>
  """
  @spec for_parameter(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_parameter(clause_iri, position)
      when is_integer(position) and position >= 0 do
    append_to_iri(clause_iri, "param/#{position}")
  end

  @doc """
  Generates an IRI for a type definition.

  Types are identified by their module, name, and arity.

  ## Parameters

  - `base_iri` - The base IRI
  - `module` - The module name
  - `type_name` - The type name
  - `arity` - The type arity (number of type parameters, must be non-negative)

  ## Examples

      iex> ElixirOntologies.IRI.for_type("https://example.org/code#", "MyApp.Types", "user_t", 0)
      ~I<https://example.org/code#MyApp.Types/type/user_t/0>

      iex> ElixirOntologies.IRI.for_type("https://example.org/code#", "MyApp", "my_list", 1)
      ~I<https://example.org/code#MyApp/type/my_list/1>
  """
  @spec for_type(
          String.t() | RDF.IRI.t(),
          String.t() | atom(),
          String.t() | atom(),
          non_neg_integer()
        ) :: RDF.IRI.t()
  def for_type(base_iri, module, type_name, arity)
      when is_integer(arity) and arity >= 0 do
    mod = module |> module_to_string() |> escape_name()
    type = escape_name(type_name)
    build_iri(base_iri, "#{mod}/type/#{type}/#{arity}")
  end

  @doc """
  Generates an IRI for a macro invocation.

  Macro invocations are identified by module, macro identifier, and index.

  ## Parameters

  - `base_iri` - The base IRI
  - `module` - The module where the invocation occurs
  - `macro_id` - Identifier for the macro (e.g., "Kernel.def")
  - `index` - Index or line number to uniquely identify the invocation

  ## Examples

      iex> ElixirOntologies.IRI.for_macro_invocation("https://example.org/code#", "MyApp.Users", "Kernel.def", 15)
      ~I<https://example.org/code#MyApp.Users/invocation/Kernel.def/15>

      iex> ElixirOntologies.IRI.for_macro_invocation("https://example.org/code#", "MyApp", "Logger.debug", 0)
      ~I<https://example.org/code#MyApp/invocation/Logger.debug/0>
  """
  @spec for_macro_invocation(
          String.t() | RDF.IRI.t(),
          String.t() | atom(),
          String.t(),
          non_neg_integer()
        ) :: RDF.IRI.t()
  def for_macro_invocation(base_iri, module, macro_id, index)
      when is_integer(index) and index >= 0 do
    mod = module |> module_to_string() |> escape_name()
    macro = escape_name(macro_id)
    build_iri(base_iri, "#{mod}/invocation/#{macro}/#{index}")
  end

  @doc """
  Generates an IRI for a module attribute.

  Attributes are identified by module and attribute name. For accumulated
  attributes or multiple instances, an optional index can be provided.

  ## Parameters

  - `base_iri` - The base IRI
  - `module` - The module name
  - `attr_name` - The attribute name
  - `index` - Optional index for accumulated/multiple attributes (default: nil)

  ## Examples

      iex> ElixirOntologies.IRI.for_attribute("https://example.org/code#", "MyApp.Users", "moduledoc")
      ~I<https://example.org/code#MyApp.Users/attribute/moduledoc>

      iex> ElixirOntologies.IRI.for_attribute("https://example.org/code#", "MyApp", "my_attr", 0)
      ~I<https://example.org/code#MyApp/attribute/my_attr/0>

      iex> ElixirOntologies.IRI.for_attribute("https://example.org/code#", "MyApp", :doc)
      ~I<https://example.org/code#MyApp/attribute/doc>
  """
  @spec for_attribute(
          String.t() | RDF.IRI.t(),
          String.t() | atom(),
          String.t() | atom(),
          non_neg_integer() | nil
        ) :: RDF.IRI.t()
  def for_attribute(base_iri, module, attr_name, index \\ nil) do
    mod = module |> module_to_string() |> escape_name()
    attr = escape_name(attr_name)

    if index do
      build_iri(base_iri, "#{mod}/attribute/#{attr}/#{index}")
    else
      build_iri(base_iri, "#{mod}/attribute/#{attr}")
    end
  end

  @doc """
  Generates an IRI for a quote block.

  Quote blocks are identified by module and index.

  ## Parameters

  - `base_iri` - The base IRI
  - `module` - The module containing the quote
  - `index` - Index to uniquely identify the quote within the module

  ## Examples

      iex> ElixirOntologies.IRI.for_quote("https://example.org/code#", "MyApp.Macros", 0)
      ~I<https://example.org/code#MyApp.Macros/quote/0>

      iex> ElixirOntologies.IRI.for_quote("https://example.org/code#", "MyApp", 5)
      ~I<https://example.org/code#MyApp/quote/5>
  """
  @spec for_quote(
          String.t() | RDF.IRI.t(),
          String.t() | atom(),
          non_neg_integer()
        ) :: RDF.IRI.t()
  def for_quote(base_iri, module, index) when is_integer(index) and index >= 0 do
    mod = module |> module_to_string() |> escape_name()
    build_iri(base_iri, "#{mod}/quote/#{index}")
  end

  @doc """
  Generates an IRI for an unquote expression within a quote block.

  ## Parameters

  - `quote_iri` - The IRI of the containing quote block
  - `index` - Index of the unquote within the quote

  ## Examples

      iex> quote_iri = RDF.iri("https://example.org/code#MyApp.Macros/quote/0")
      iex> ElixirOntologies.IRI.for_unquote(quote_iri, 0)
      ~I<https://example.org/code#MyApp.Macros/quote/0/unquote/0>
  """
  @spec for_unquote(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_unquote(quote_iri, index) when is_integer(index) and index >= 0 do
    append_to_iri(quote_iri, "unquote/#{index}")
  end

  @doc """
  Generates an IRI for a hygiene violation within a quote block.

  ## Parameters

  - `quote_iri` - The IRI of the containing quote block
  - `index` - Index of the hygiene violation within the quote

  ## Examples

      iex> quote_iri = RDF.iri("https://example.org/code#MyApp.Macros/quote/0")
      iex> ElixirOntologies.IRI.for_hygiene_violation(quote_iri, 0)
      ~I<https://example.org/code#MyApp.Macros/quote/0/hygiene/0>
  """
  @spec for_hygiene_violation(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_hygiene_violation(quote_iri, index) when is_integer(index) and index >= 0 do
    append_to_iri(quote_iri, "hygiene/#{index}")
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
    path = relative_path |> String.replace("\\", "/") |> encode_path()
    build_iri(base_iri, "file/#{path}")
  end

  @doc """
  Generates an IRI for a source location (line range).

  ## Parameters

  - `file_iri` - The IRI of the source file
  - `start_line` - The starting line number (must be positive)
  - `end_line` - The ending line number (must be >= start_line)

  ## Examples

      iex> file_iri = RDF.iri("https://example.org/code#file/lib/users.ex")
      iex> ElixirOntologies.IRI.for_source_location(file_iri, 10, 25)
      ~I<https://example.org/code#file/lib/users.ex/L10-25>

      iex> file_iri = RDF.iri("https://example.org/code#file/lib/users.ex")
      iex> ElixirOntologies.IRI.for_source_location(file_iri, 5, 5)
      ~I<https://example.org/code#file/lib/users.ex/L5-5>
  """
  @spec for_source_location(String.t() | RDF.IRI.t(), pos_integer(), pos_integer()) :: RDF.IRI.t()
  def for_source_location(file_iri, start_line, end_line)
      when is_integer(start_line) and start_line > 0 and
             is_integer(end_line) and end_line >= start_line do
    append_to_iri(file_iri, "L#{start_line}-#{end_line}")
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
    hash =
      :crypto.hash(:sha256, repo_url)
      |> Base.encode16(case: :lower)
      |> String.slice(0, @repo_hash_length)

    build_iri(base_iri, "repo/#{hash}")
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
    append_to_iri(repo_iri, "commit/#{sha}")
  end

  # ===========================================================================
  # Module Directive IRIs
  # ===========================================================================

  @doc """
  Generates an IRI for a module alias directive.

  Pattern: `{base}#Module/alias/{index}`

  ## Parameters

  - `module_iri` - The IRI of the containing module
  - `index` - Zero-based index of the alias within the module

  ## Examples

      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> ElixirOntologies.IRI.for_alias(module_iri, 0)
      ~I<https://example.org/code#MyApp/alias/0>

      iex> module_iri = RDF.iri("https://example.org/code#MyApp.Users")
      iex> ElixirOntologies.IRI.for_alias(module_iri, 2)
      ~I<https://example.org/code#MyApp.Users/alias/2>
  """
  @spec for_alias(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_alias(module_iri, index) when is_integer(index) and index >= 0 do
    append_to_iri(module_iri, "alias/#{index}")
  end

  @doc """
  Generates an IRI for a module import directive.

  Pattern: `{base}#Module/import/{index}`

  ## Parameters

  - `module_iri` - The IRI of the containing module
  - `index` - Zero-based index of the import within the module

  ## Examples

      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> ElixirOntologies.IRI.for_import(module_iri, 0)
      ~I<https://example.org/code#MyApp/import/0>
  """
  @spec for_import(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_import(module_iri, index) when is_integer(index) and index >= 0 do
    append_to_iri(module_iri, "import/#{index}")
  end

  @doc """
  Generates an IRI for a module require directive.

  Pattern: `{base}#Module/require/{index}`

  ## Parameters

  - `module_iri` - The IRI of the containing module
  - `index` - Zero-based index of the require within the module

  ## Examples

      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> ElixirOntologies.IRI.for_require(module_iri, 0)
      ~I<https://example.org/code#MyApp/require/0>
  """
  @spec for_require(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_require(module_iri, index) when is_integer(index) and index >= 0 do
    append_to_iri(module_iri, "require/#{index}")
  end

  @doc """
  Generates an IRI for a module use directive.

  Pattern: `{base}#Module/use/{index}`

  ## Parameters

  - `module_iri` - The IRI of the containing module
  - `index` - Zero-based index of the use within the module

  ## Examples

      iex> module_iri = RDF.iri("https://example.org/code#MyApp.Server")
      iex> ElixirOntologies.IRI.for_use(module_iri, 0)
      ~I<https://example.org/code#MyApp.Server/use/0>
  """
  @spec for_use(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_use(module_iri, index) when is_integer(index) and index >= 0 do
    append_to_iri(module_iri, "use/#{index}")
  end

  @doc """
  Generates an IRI for a use directive option.

  Pattern: `{use_iri}/option/{index}`

  ## Parameters

  - `use_iri` - The IRI of the containing use directive
  - `index` - Zero-based index of the option within the use directive

  ## Examples

      iex> use_iri = RDF.iri("https://example.org/code#MyApp/use/0")
      iex> ElixirOntologies.IRI.for_use_option(use_iri, 0)
      ~I<https://example.org/code#MyApp/use/0/option/0>

      iex> use_iri = RDF.iri("https://example.org/code#MyApp.Server/use/1")
      iex> ElixirOntologies.IRI.for_use_option(use_iri, 2)
      ~I<https://example.org/code#MyApp.Server/use/1/option/2>
  """
  @spec for_use_option(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_use_option(use_iri, index) when is_integer(index) and index >= 0 do
    append_to_iri(use_iri, "option/#{index}")
  end

  @doc """
  Generates an IRI for an anonymous function.

  Anonymous functions don't have names, so identification is based on either:
  - The containing function/module and an index
  - A file path and line number

  Pattern: `{base}#Module/anon/{index}` or `{base}#file/{path}/anon/L{line}`

  ## Parameters

  - `context_iri` - The IRI of the containing context (module, function, or file)
  - `index_or_line` - Index within the context or line number

  ## Examples

      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> ElixirOntologies.IRI.for_anonymous_function(module_iri, 0)
      ~I<https://example.org/code#MyApp/anon/0>

      iex> func_iri = RDF.iri("https://example.org/code#MyApp/get_user/1")
      iex> ElixirOntologies.IRI.for_anonymous_function(func_iri, 2)
      ~I<https://example.org/code#MyApp/get_user/1/anon/2>
  """
  @spec for_anonymous_function(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_anonymous_function(context_iri, index) when is_integer(index) and index >= 0 do
    append_to_iri(context_iri, "anon/#{index}")
  end

  @doc """
  Generates an IRI for an anonymous function clause.

  Pattern: `{anon_iri}/clause/{N}`

  ## Parameters

  - `anon_iri` - The IRI of the anonymous function
  - `clause_order` - The clause position (0-indexed)

  ## Examples

      iex> anon_iri = RDF.iri("https://example.org/code#MyApp/anon/0")
      iex> ElixirOntologies.IRI.for_anonymous_clause(anon_iri, 0)
      ~I<https://example.org/code#MyApp/anon/0/clause/0>

      iex> anon_iri = RDF.iri("https://example.org/code#MyApp/get_user/1/anon/2")
      iex> ElixirOntologies.IRI.for_anonymous_clause(anon_iri, 1)
      ~I<https://example.org/code#MyApp/get_user/1/anon/2/clause/1>
  """
  @spec for_anonymous_clause(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_anonymous_clause(anon_iri, clause_order)
      when is_integer(clause_order) and clause_order >= 0 do
    append_to_iri(anon_iri, "clause/#{clause_order}")
  end

  @doc """
  Generates an IRI for a captured variable in a closure.

  Pattern: `{anon_iri}/capture/{variable_name}`

  ## Parameters

  - `anon_iri` - The IRI of the anonymous function/closure
  - `variable_name` - The name of the captured variable (atom or string)

  ## Examples

      iex> anon_iri = RDF.iri("https://example.org/code#MyApp/anon/0")
      iex> ElixirOntologies.IRI.for_captured_variable(anon_iri, :x)
      ~I<https://example.org/code#MyApp/anon/0/capture/x>

      iex> anon_iri = RDF.iri("https://example.org/code#MyApp/get_user/1/anon/2")
      iex> ElixirOntologies.IRI.for_captured_variable(anon_iri, "counter")
      ~I<https://example.org/code#MyApp/get_user/1/anon/2/capture/counter>
  """
  @spec for_captured_variable(String.t() | RDF.IRI.t(), atom() | String.t()) :: RDF.IRI.t()
  def for_captured_variable(anon_iri, variable_name) do
    var_name = escape_name(variable_name)
    append_to_iri(anon_iri, "capture/#{var_name}")
  end

  @doc """
  Generates an IRI for a capture operator expression.

  Pattern: `{context_iri}/&/{index}`

  ## Parameters

  - `context_iri` - The IRI of the containing context (module or file)
  - `index` - Index of the capture within its context

  ## Examples

      iex> module_iri = RDF.iri("https://example.org/code#MyApp")
      iex> ElixirOntologies.IRI.for_capture(module_iri, 0)
      ~I<https://example.org/code#MyApp/&/0>

      iex> module_iri = RDF.iri("https://example.org/code#MyApp.Server")
      iex> ElixirOntologies.IRI.for_capture(module_iri, 2)
      ~I<https://example.org/code#MyApp.Server/&/2>
  """
  @spec for_capture(String.t() | RDF.IRI.t(), non_neg_integer()) :: RDF.IRI.t()
  def for_capture(context_iri, index) when is_integer(index) and index >= 0 do
    append_to_iri(context_iri, "&/#{index}")
  end

  @doc """
  Generates an IRI for a child specification within a supervisor.

  The IRI follows the pattern: `{supervisor_iri}/child/{child_id}/{index}`

  ## Parameters

  - `supervisor_iri` - The IRI of the supervisor module
  - `child_id` - The child specification ID
  - `index` - Position in the children list (for disambiguation)

  ## Examples

      iex> supervisor_iri = RDF.iri("https://example.org/code#MySupervisor")
      iex> ElixirOntologies.IRI.for_child_spec(supervisor_iri, :worker1, 0)
      ~I<https://example.org/code#MySupervisor/child/worker1/0>

      iex> supervisor_iri = RDF.iri("https://example.org/code#MyApp.Supervisor")
      iex> ElixirOntologies.IRI.for_child_spec(supervisor_iri, MyWorker, 2)
      ~I<https://example.org/code#MyApp.Supervisor/child/MyWorker/2>
  """
  @spec for_child_spec(String.t() | RDF.IRI.t(), atom() | term(), non_neg_integer()) :: RDF.IRI.t()
  def for_child_spec(supervisor_iri, child_id, index) when is_integer(index) and index >= 0 do
    id_string = format_child_id(child_id) |> escape_name()
    append_to_iri(supervisor_iri, "child/#{id_string}/#{index}")
  end

  # Format child ID for IRI (atom, module, or other term)
  defp format_child_id(id) when is_atom(id), do: Atom.to_string(id) |> String.replace("Elixir.", "")
  defp format_child_id(id), do: inspect(id)

  # ===========================================================================
  # Supervision Tree IRIs
  # ===========================================================================

  @doc """
  Generates an IRI for a supervision tree.

  ## Parameters

  - `base_iri` - Base IRI string
  - `app_name` - Application name (atom or string)

  ## Returns

  An RDF.IRI for the supervision tree.

  ## Examples

      iex> ElixirOntologies.IRI.for_supervision_tree("https://example.org/code#", :my_app)
      ~I<https://example.org/code#tree/my_app>

      iex> ElixirOntologies.IRI.for_supervision_tree("https://example.org/code#", "MyApp")
      ~I<https://example.org/code#tree/MyApp>
  """
  @spec for_supervision_tree(String.t(), atom() | String.t()) :: RDF.IRI.t()
  def for_supervision_tree(base_iri, app_name) when is_atom(app_name) do
    for_supervision_tree(base_iri, Atom.to_string(app_name))
  end

  def for_supervision_tree(base_iri, app_name) when is_binary(base_iri) and is_binary(app_name) do
    RDF.iri("#{base_iri}tree/#{escape_name(app_name)}")
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
      match = Regex.run(@regex_parameter, iri_string) ->
        [_, parent, clause, param] = match
        {:ok, parse_parameter(parent, clause, param)}

      match = Regex.run(@regex_clause, iri_string) ->
        [_, parent, arity, clause] = match
        {:ok, parse_clause(parent, arity, clause)}

      match = Regex.run(@regex_location, iri_string) ->
        [_, file_iri, start_line, end_line] = match
        {:ok, parse_location(file_iri, start_line, end_line)}

      match = Regex.run(@regex_commit, iri_string) ->
        [_, repo_iri, sha] = match
        {:ok, parse_commit(repo_iri, sha)}

      match = Regex.run(@regex_repository, iri_string) ->
        [_, base, hash] = match
        {:ok, %{type: :repository, base_iri: base, repo_hash: hash}}

      match = Regex.run(@regex_file, iri_string) ->
        [_, base, path] = match
        {:ok, %{type: :file, base_iri: base, path: URI.decode(path)}}

      match = Regex.run(@regex_function, iri_string) ->
        [_, base, module, func, arity] = match

        {:ok,
         %{
           type: :function,
           base_iri: base,
           module: URI.decode(module),
           function: URI.decode(func),
           arity: String.to_integer(arity)
         }}

      match = Regex.run(@regex_module, iri_string) ->
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
  @spec function_from_iri(String.t() | RDF.IRI.t()) ::
          {:ok, {String.t(), String.t(), non_neg_integer()}} | {:error, String.t()}
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
  # Private Helpers - IRI Building
  # ===========================================================================

  # Build an IRI by appending a suffix to a base IRI
  defp build_iri(base_iri, suffix) do
    RDF.iri("#{to_string(base_iri)}#{suffix}")
  end

  # Append a path segment to an existing IRI
  defp append_to_iri(parent_iri, suffix) do
    RDF.iri("#{to_string(parent_iri)}/#{suffix}")
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
    |> Enum.map_join("/", &escape_name/1)
  end

  # ===========================================================================
  # Private Helpers - IRI Parsing
  # ===========================================================================

  defp parse_parameter(parent, clause, param) do
    case Regex.run(@regex_function, parent) do
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
        %{
          type: :parameter,
          clause: String.to_integer(clause),
          parameter: String.to_integer(param)
        }
    end
  end

  defp parse_clause(parent, arity, clause) do
    case Regex.run(@regex_function_prefix, parent) do
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
    case Regex.run(@regex_file, file_iri) do
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
    case Regex.run(@regex_repository, repo_iri) do
      [_, base, hash] ->
        %{type: :commit, base_iri: base, repo_hash: hash, sha: sha}

      _ ->
        %{type: :commit, sha: sha}
    end
  end

  # ===========================================================================
  # Private Helpers - Component Extraction
  # ===========================================================================

  defp extract_module_from_clause(iri) do
    with {:ok, func_iri} <- strip_suffix(iri, @regex_strip_clause) do
      module_from_iri(func_iri)
    else
      :error -> {:error, "Could not extract module from clause IRI"}
    end
  end

  defp extract_module_from_parameter(iri) do
    with {:ok, clause_iri} <- strip_suffix(iri, @regex_strip_param) do
      extract_module_from_clause(clause_iri)
    else
      :error -> {:error, "Could not extract module from parameter IRI"}
    end
  end

  defp extract_function_from_clause(iri) do
    with {:ok, func_iri} <- strip_suffix(iri, @regex_strip_clause) do
      function_from_iri(func_iri)
    else
      :error -> {:error, "Could not extract function from clause IRI"}
    end
  end

  defp extract_function_from_parameter(iri) do
    with {:ok, clause_iri} <- strip_suffix(iri, @regex_strip_param) do
      extract_function_from_clause(clause_iri)
    else
      :error -> {:error, "Could not extract function from parameter IRI"}
    end
  end

  defp strip_suffix(iri, regex) do
    iri_string = to_string(iri)

    case Regex.run(regex, iri_string) do
      [_, parent] -> {:ok, parent}
      _ -> :error
    end
  end
end
