defmodule ElixirOntologies.Extractors.Evolution.EntityVersion do
  @moduledoc """
  Models code elements as PROV-O entities with version relationships.

  This module tracks how modules and functions evolve across commits,
  implementing version chains and `prov:wasDerivedFrom` relationships.

  ## Version Identification

  Version IDs are computed as `{entity_name}@{short_sha}`:
  - `MyApp.UserController@abc123d`
  - `MyApp.UserController.create/1@abc123d`

  ## Change Detection

  To detect actual changes (not just commits that touched the file),
  we compute a content hash of the entity's source code. Two versions
  with the same content hash are considered identical.

  ## PROV-O Alignment

  This module aligns with the elixir-evolution.ttl ontology:
  - `evolution:CodeVersion` - A versioned snapshot of code
  - `evolution:ModuleVersion` - A specific version of a module
  - `evolution:FunctionVersion` - A specific version of a function
  - `evolution:wasRevisionOf` - Links versions in a chain

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.EntityVersion

      # Track module versions across commits
      {:ok, versions} = EntityVersion.track_module_versions(
        ".",
        "MyApp.UserController",
        limit: 10
      )

      # Get version at specific commit
      {:ok, version} = EntityVersion.extract_module_version(
        ".",
        "MyApp.UserController",
        "abc123..."
      )

      # Build derivation chain
      derivations = EntityVersion.build_derivation_chain(versions)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.EntityVersion
      iex> {:ok, version} = EntityVersion.extract_module_version(".", "ElixirOntologies", "HEAD")
      iex> is_binary(version.version_id)
      true
  """

  alias ElixirOntologies.Analyzer.Git
  alias ElixirOntologies.Extractors.Evolution.GitUtils
  alias ElixirOntologies.Utils.IdGenerator

  # ===========================================================================
  # Entity Type
  # ===========================================================================

  @type entity_type :: :module | :function | :type | :macro

  # ===========================================================================
  # ModuleVersion Struct
  # ===========================================================================

  defmodule ModuleVersion do
    @moduledoc """
    Represents a specific version of an Elixir module.

    Aligns with `evolution:ModuleVersion` from elixir-evolution.ttl.
    """

    @type t :: %__MODULE__{
            module_name: String.t(),
            version_id: String.t(),
            commit_sha: String.t(),
            short_sha: String.t(),
            previous_version: String.t() | nil,
            file_path: String.t(),
            content_hash: String.t(),
            functions: [String.t()],
            line_count: non_neg_integer(),
            timestamp: DateTime.t() | nil,
            metadata: map()
          }

    @enforce_keys [:module_name, :version_id, :commit_sha, :short_sha, :file_path, :content_hash]
    defstruct [
      :module_name,
      :version_id,
      :commit_sha,
      :short_sha,
      :previous_version,
      :file_path,
      :content_hash,
      :timestamp,
      functions: [],
      line_count: 0,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # FunctionVersion Struct
  # ===========================================================================

  defmodule FunctionVersion do
    @moduledoc """
    Represents a specific version of a function.

    Aligns with `evolution:FunctionVersion` from elixir-evolution.ttl.
    """

    @type t :: %__MODULE__{
            module_name: String.t(),
            function_name: atom(),
            arity: non_neg_integer(),
            version_id: String.t(),
            commit_sha: String.t(),
            short_sha: String.t(),
            previous_version: String.t() | nil,
            content_hash: String.t(),
            line_range: {pos_integer(), pos_integer()} | nil,
            clause_count: non_neg_integer(),
            timestamp: DateTime.t() | nil,
            metadata: map()
          }

    @enforce_keys [
      :module_name,
      :function_name,
      :arity,
      :version_id,
      :commit_sha,
      :short_sha,
      :content_hash
    ]

    defstruct [
      :module_name,
      :function_name,
      :arity,
      :version_id,
      :commit_sha,
      :short_sha,
      :previous_version,
      :content_hash,
      :line_range,
      :timestamp,
      clause_count: 1,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Derivation Struct
  # ===========================================================================

  defmodule Derivation do
    @moduledoc """
    Represents a PROV-O derivation relationship between entities.

    Aligns with `prov:wasDerivedFrom` and its subproperties:
    - `:revision` - `prov:wasRevisionOf` (updated version)
    - `:quotation` - `prov:wasQuotedFrom` (code copied/adapted)
    - `:primary_source` - `prov:hadPrimarySource` (original source)
    """

    @type derivation_type :: :revision | :quotation | :primary_source

    @type t :: %__MODULE__{
            derived_entity: String.t(),
            source_entity: String.t(),
            derivation_type: derivation_type(),
            activity: String.t() | nil,
            timestamp: DateTime.t() | nil,
            metadata: map()
          }

    @enforce_keys [:derived_entity, :source_entity, :derivation_type]
    defstruct [
      :derived_entity,
      :source_entity,
      :derivation_type,
      :activity,
      :timestamp,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Public API - Module Versions
  # ===========================================================================

  @doc """
  Extracts a module version at a specific commit.

  ## Options

  - `:include_functions` - Include list of function names (default: false)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.EntityVersion
      iex> {:ok, version} = EntityVersion.extract_module_version(".", "ElixirOntologies", "HEAD")
      iex> version.module_name
      "ElixirOntologies"
  """
  @spec extract_module_version(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, ModuleVersion.t()} | {:error, atom()}
  def extract_module_version(repo_path, module_name, commit_ref, opts \\ []) do
    include_functions = Keyword.get(opts, :include_functions, false)

    if not GitUtils.valid_ref?(commit_ref) do
      {:error, :invalid_ref}
    else
      with {:ok, repo_root} <- Git.detect_repo(repo_path),
           {:ok, file_path} <- find_module_file(repo_root, module_name, commit_ref),
           {:ok, content} <- extract_file_at_commit(repo_root, file_path, commit_ref),
           {:ok, module_source} <- extract_module_source(content, module_name),
           {:ok, commit_info} <- get_commit_info(repo_root, commit_ref) do
      content_hash = compute_content_hash(module_source)
      short_sha = String.slice(commit_info.sha, 0, 7)
      version_id = "#{module_name}@#{short_sha}"

      functions =
        if include_functions do
          extract_function_names(module_source)
        else
          []
        end

        {:ok,
         %ModuleVersion{
           module_name: module_name,
           version_id: version_id,
           commit_sha: commit_info.sha,
           short_sha: short_sha,
           file_path: file_path,
           content_hash: content_hash,
           functions: functions,
           line_count: count_lines(module_source),
           timestamp: commit_info.timestamp,
           metadata: %{}
         }}
      end
    end
  end

  @doc """
  Extracts a module version, raising on error.
  """
  @spec extract_module_version!(String.t(), String.t(), String.t(), keyword()) :: ModuleVersion.t()
  def extract_module_version!(repo_path, module_name, commit_ref, opts \\ []) do
    case extract_module_version(repo_path, module_name, commit_ref, opts) do
      {:ok, version} -> version
      {:error, reason} -> raise ArgumentError, "Failed to extract module version: #{reason}"
    end
  end

  @doc """
  Tracks module versions across commits.

  Returns a list of versions ordered from newest to oldest, with
  `previous_version` links populated.

  ## Options

  - `:limit` - Maximum number of versions to retrieve (default: 100)
  - `:include_functions` - Include function names in each version (default: false)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.EntityVersion
      iex> {:ok, versions} = EntityVersion.track_module_versions(".", "ElixirOntologies", limit: 5)
      iex> is_list(versions)
      true
  """
  @spec track_module_versions(String.t(), String.t(), keyword()) ::
          {:ok, [ModuleVersion.t()]} | {:error, atom()}
  def track_module_versions(repo_path, module_name, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    include_functions = Keyword.get(opts, :include_functions, false)

    with {:ok, repo_root} <- Git.detect_repo(repo_path),
         {:ok, file_path} <- find_module_file(repo_root, module_name, "HEAD"),
         {:ok, commits} <- get_commits_for_file(repo_root, file_path, limit) do
      versions =
        commits
        |> Enum.map(fn commit_sha ->
          extract_module_version(repo_root, module_name, commit_sha,
            include_functions: include_functions
          )
        end)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, v} -> v end)
        |> deduplicate_by_content_hash()
        |> link_previous_versions()

      {:ok, versions}
    end
  end

  @doc """
  Tracks module versions, raising on error.
  """
  @spec track_module_versions!(String.t(), String.t(), keyword()) :: [ModuleVersion.t()]
  def track_module_versions!(repo_path, module_name, opts \\ []) do
    case track_module_versions(repo_path, module_name, opts) do
      {:ok, versions} -> versions
      {:error, reason} -> raise ArgumentError, "Failed to track module versions: #{reason}"
    end
  end

  # ===========================================================================
  # Public API - Function Versions
  # ===========================================================================

  @doc """
  Extracts a function version at a specific commit.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.EntityVersion
      iex> result = EntityVersion.extract_function_version(".", "ElixirOntologies", :start, 2, "HEAD")
      iex> match?({:ok, _} | {:error, _}, result)
      true
  """
  @spec extract_function_version(String.t(), String.t(), atom(), non_neg_integer(), String.t()) ::
          {:ok, FunctionVersion.t()} | {:error, atom()}
  def extract_function_version(repo_path, module_name, function_name, arity, commit_ref) do
    if not GitUtils.valid_ref?(commit_ref) do
      {:error, :invalid_ref}
    else
      with {:ok, repo_root} <- Git.detect_repo(repo_path),
           {:ok, file_path} <- find_module_file(repo_root, module_name, commit_ref),
           {:ok, content} <- extract_file_at_commit(repo_root, file_path, commit_ref),
           {:ok, function_source, line_range} <-
             extract_function_source(content, function_name, arity),
           {:ok, commit_info} <- get_commit_info(repo_root, commit_ref) do
        content_hash = compute_content_hash(function_source)
        short_sha = String.slice(commit_info.sha, 0, 7)
        version_id = "#{module_name}.#{function_name}/#{arity}@#{short_sha}"

        {:ok,
         %FunctionVersion{
           module_name: module_name,
           function_name: function_name,
           arity: arity,
           version_id: version_id,
           commit_sha: commit_info.sha,
           short_sha: short_sha,
           content_hash: content_hash,
           line_range: line_range,
           clause_count: count_function_clauses(function_source, function_name),
           timestamp: commit_info.timestamp,
           metadata: %{}
         }}
      end
    end
  end

  @doc """
  Extracts a function version, raising on error.
  """
  @spec extract_function_version!(
          String.t(),
          String.t(),
          atom(),
          non_neg_integer(),
          String.t()
        ) ::
          FunctionVersion.t()
  def extract_function_version!(repo_path, module_name, function_name, arity, commit_ref) do
    case extract_function_version(repo_path, module_name, function_name, arity, commit_ref) do
      {:ok, version} -> version
      {:error, reason} -> raise ArgumentError, "Failed to extract function version: #{reason}"
    end
  end

  @doc """
  Tracks function versions across commits.

  Returns a list of versions ordered from newest to oldest, with
  `previous_version` links populated.

  ## Options

  - `:limit` - Maximum number of versions to retrieve (default: 100)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.EntityVersion
      iex> result = EntityVersion.track_function_versions(".", "ElixirOntologies", :start, 2, limit: 5)
      iex> match?({:ok, _} | {:error, _}, result)
      true
  """
  @spec track_function_versions(String.t(), String.t(), atom(), non_neg_integer(), keyword()) ::
          {:ok, [FunctionVersion.t()]} | {:error, atom()}
  def track_function_versions(repo_path, module_name, function_name, arity, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    with {:ok, repo_root} <- Git.detect_repo(repo_path),
         {:ok, file_path} <- find_module_file(repo_root, module_name, "HEAD"),
         {:ok, commits} <- get_commits_for_file(repo_root, file_path, limit) do
      versions =
        commits
        |> Enum.map(fn commit_sha ->
          extract_function_version(repo_root, module_name, function_name, arity, commit_sha)
        end)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, v} -> v end)
        |> deduplicate_by_content_hash()
        |> link_previous_versions()

      {:ok, versions}
    end
  end

  @doc """
  Tracks function versions, raising on error.
  """
  @spec track_function_versions!(String.t(), String.t(), atom(), non_neg_integer(), keyword()) ::
          [FunctionVersion.t()]
  def track_function_versions!(repo_path, module_name, function_name, arity, opts \\ []) do
    case track_function_versions(repo_path, module_name, function_name, arity, opts) do
      {:ok, versions} -> versions
      {:error, reason} -> raise ArgumentError, "Failed to track function versions: #{reason}"
    end
  end

  # ===========================================================================
  # Public API - Derivation Relationships
  # ===========================================================================

  @doc """
  Builds a derivation relationship between two versions.

  ## Options

  - `:type` - Derivation type (default: `:revision`)
  - `:activity` - The activity (commit) that caused the derivation

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.EntityVersion
      iex> alias ElixirOntologies.Extractors.Evolution.EntityVersion.Derivation
      iex> derivation = EntityVersion.build_derivation("v2", "v1", type: :revision)
      iex> derivation.derivation_type
      :revision
  """
  @spec build_derivation(String.t(), String.t(), keyword()) :: Derivation.t()
  def build_derivation(derived_entity, source_entity, opts \\ []) do
    type = Keyword.get(opts, :type, :revision)
    activity = Keyword.get(opts, :activity)
    timestamp = Keyword.get(opts, :timestamp)

    %Derivation{
      derived_entity: derived_entity,
      source_entity: source_entity,
      derivation_type: type,
      activity: activity,
      timestamp: timestamp,
      metadata: %{}
    }
  end

  @doc """
  Builds a chain of derivation relationships from a list of versions.

  The versions should be ordered from newest to oldest. Each version
  will have a derivation relationship to the next (older) version.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.EntityVersion
      iex> versions = [%{version_id: "v3", commit_sha: "c"}, %{version_id: "v2", commit_sha: "b"}, %{version_id: "v1", commit_sha: "a"}]
      iex> derivations = EntityVersion.build_derivation_chain(versions)
      iex> length(derivations)
      2
  """
  @spec build_derivation_chain([ModuleVersion.t() | FunctionVersion.t() | map()]) :: [
          Derivation.t()
        ]
  def build_derivation_chain(versions) when is_list(versions) do
    versions
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [newer, older] ->
      build_derivation(
        newer.version_id,
        older.version_id,
        type: :revision,
        activity: newer.commit_sha,
        timestamp: Map.get(newer, :timestamp)
      )
    end)
  end

  # ===========================================================================
  # Public API - Query Functions
  # ===========================================================================

  @doc """
  Checks if two versions have the same content.
  """
  @spec same_content?(ModuleVersion.t() | FunctionVersion.t(), ModuleVersion.t() | FunctionVersion.t()) ::
          boolean()
  def same_content?(version1, version2) do
    version1.content_hash == version2.content_hash
  end

  @doc """
  Gets the version chain as a list of version IDs.
  """
  @spec version_chain([ModuleVersion.t() | FunctionVersion.t()]) :: [String.t()]
  def version_chain(versions) do
    Enum.map(versions, & &1.version_id)
  end

  @doc """
  Finds the first version where content changed from the previous.
  """
  @spec find_change_introducing_version([ModuleVersion.t() | FunctionVersion.t()]) ::
          ModuleVersion.t() | FunctionVersion.t() | nil
  def find_change_introducing_version([]), do: nil
  def find_change_introducing_version([single]), do: single

  def find_change_introducing_version([newest | _] = versions) do
    versions
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [newer, older] ->
      if newer.content_hash != older.content_hash, do: newer
    end)
    |> Kernel.||(newest)
  end

  # ===========================================================================
  # Private - File Extraction
  # ===========================================================================

  defp extract_file_at_commit(repo_path, file_path, commit_ref) do
    args = ["show", "#{commit_ref}:#{file_path}"]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> {:error, :file_not_found_at_commit}
    end
  end

  defp find_module_file(repo_path, module_name, commit_ref) do
    # Convert module name to expected file path
    expected_path =
      module_name
      |> String.replace(".", "/")
      |> Macro.underscore()

    # Try common locations
    possible_paths = [
      "lib/#{expected_path}.ex",
      "lib/#{expected_path}.exs",
      "test/#{expected_path}_test.exs"
    ]

    result =
      Enum.find_value(possible_paths, fn path ->
        case extract_file_at_commit(repo_path, path, commit_ref) do
          {:ok, content} ->
            if content_contains_module?(content, module_name), do: path

          _ ->
            nil
        end
      end)

    case result do
      nil -> {:error, :module_not_found}
      path -> {:ok, path}
    end
  end

  defp content_contains_module?(content, module_name) do
    # Check if the content defines the expected module
    pattern = ~r/defmodule\s+#{Regex.escape(module_name)}\b/
    Regex.match?(pattern, content)
  end

  # ===========================================================================
  # Private - Source Extraction
  # ===========================================================================

  defp extract_module_source(content, module_name) do
    # Parse the content and extract the module definition using line-based approach
    lines = String.split(content, "\n")
    # Match "defmodule ModuleName do" with optional whitespace before/after
    pattern = ~r/^\s*defmodule\s+#{Regex.escape(module_name)}\s+do\s*$/

    case find_module_start_line(lines, pattern) do
      nil ->
        {:error, :module_not_found}

      start_line ->
        case find_module_end_line(lines, start_line) do
          nil ->
            {:error, :malformed_module}

          end_line ->
            source =
              lines
              |> Enum.slice((start_line - 1)..(end_line - 1))
              |> Enum.join("\n")

            {:ok, source}
        end
    end
  end

  defp find_module_start_line(lines, pattern) do
    lines
    |> Enum.with_index(1)
    |> Enum.find_value(fn {line, idx} ->
      if Regex.match?(pattern, line), do: idx
    end)
  end

  defp find_module_end_line(lines, start_line) do
    # Count do/end blocks to find matching end
    # Start from the line AFTER the defmodule line, with depth 1
    # (the defmodule line itself opens the block)
    lines
    |> Enum.drop(start_line)
    |> Enum.with_index(start_line + 1)
    |> Enum.reduce_while({1, nil}, fn {line, line_num}, {depth, _} ->
      new_depth = update_block_depth(line, depth)

      if new_depth == 0 do
        {:halt, {0, line_num}}
      else
        {:cont, {new_depth, nil}}
      end
    end)
    |> elem(1)
  end

  defp update_block_depth(line, depth) do
    trimmed = String.trim(line)

    # Count block openers (do at end of line or standalone do blocks)
    openers =
      cond do
        # Standalone "do" keyword (e.g., "do" on its own line)
        trimmed == "do" -> 1
        # Block openers: defmodule, def, defp, if, case, cond, try, receive, etc.
        String.match?(trimmed, ~r/\bdo\s*$/) -> 1
        String.match?(trimmed, ~r/\bdo\s*#/) -> 1
        true -> 0
      end

    # Count block closers
    closers =
      cond do
        # Standalone "end" (the only case we care about for module end)
        trimmed == "end" -> 1
        true -> 0
      end

    depth + openers - closers
  end

  defp extract_function_source(content, function_name, arity) do
    # Look for function definition with the given name
    func_str = Atom.to_string(function_name)

    case find_function_definitions(content, func_str) do
      [] ->
        {:error, :function_not_found}

      definitions ->
        # Filter by arity
        matching =
          Enum.filter(definitions, fn {_start, _end, def_arity} ->
            def_arity == arity
          end)

        case matching do
          [] ->
            {:error, :function_not_found}

          [{start_line, end_line, _} | rest] ->
            # Get all clauses
            all_clauses = [{start_line, end_line, arity} | rest]
            first_line = Enum.min(Enum.map(all_clauses, fn {s, _, _} -> s end))
            last_line = Enum.max(Enum.map(all_clauses, fn {_, e, _} -> e end))

            lines = String.split(content, "\n")
            source = lines |> Enum.slice((first_line - 1)..(last_line - 1)) |> Enum.join("\n")
            {:ok, source, {first_line, last_line}}
        end
    end
  end

  defp find_function_definitions(content, function_name) do
    lines = String.split(content, "\n")
    pattern = ~r/^\s*(def|defp)\s+#{Regex.escape(function_name)}\s*\(/

    lines
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {line, line_num}, acc ->
      if Regex.match?(pattern, line) do
        arity = extract_arity_from_line(line, function_name)
        end_line = find_function_end(lines, line_num)
        [{line_num, end_line, arity} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp extract_arity_from_line(line, function_name) do
    # Extract parameters to count arity
    pattern = ~r/(def|defp)\s+#{Regex.escape(function_name)}\s*\(([^)]*)\)/

    case Regex.run(pattern, line) do
      [_, _, ""] ->
        0

      [_, _, params] ->
        # Count commas at the top level (not inside nested structures)
        count_top_level_params(params)

      _ ->
        0
    end
  end

  defp count_top_level_params(params) do
    params = String.trim(params)
    if params == "", do: 0, else: do_count_params(params, 0, 0)
  end

  defp do_count_params("", _depth, count), do: count + 1

  defp do_count_params(<<"(", rest::binary>>, depth, count) do
    do_count_params(rest, depth + 1, count)
  end

  defp do_count_params(<<"[", rest::binary>>, depth, count) do
    do_count_params(rest, depth + 1, count)
  end

  defp do_count_params(<<"{", rest::binary>>, depth, count) do
    do_count_params(rest, depth + 1, count)
  end

  defp do_count_params(<<")", rest::binary>>, depth, count) do
    do_count_params(rest, max(0, depth - 1), count)
  end

  defp do_count_params(<<"]", rest::binary>>, depth, count) do
    do_count_params(rest, max(0, depth - 1), count)
  end

  defp do_count_params(<<"}", rest::binary>>, depth, count) do
    do_count_params(rest, max(0, depth - 1), count)
  end

  defp do_count_params(<<",", rest::binary>>, 0, count) do
    do_count_params(rest, 0, count + 1)
  end

  defp do_count_params(<<_char, rest::binary>>, depth, count) do
    do_count_params(rest, depth, count)
  end

  defp find_function_end(lines, start_line) do
    # Simple approach: find the next line that starts with def/defp or end of module
    remaining = Enum.drop(lines, start_line)

    end_offset =
      Enum.find_index(remaining, fn line ->
        trimmed = String.trim(line)
        # Next function or end of block
        String.match?(trimmed, ~r/^(def|defp|defmacro|defmacrop)\s/) or
          trimmed == "end"
      end)

    case end_offset do
      nil -> length(lines)
      0 -> start_line
      n -> start_line + n - 1
    end
  end

  # ===========================================================================
  # Private - Content Hashing
  # ===========================================================================

  defp compute_content_hash(content) do
    # Normalize whitespace and compute content hash
    normalized =
      content
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    IdGenerator.content_id(normalized)
  end

  # ===========================================================================
  # Private - Version Linking
  # ===========================================================================

  defp deduplicate_by_content_hash(versions) do
    # Remove consecutive versions with the same content hash
    versions
    |> Enum.reduce([], fn version, acc ->
      case acc do
        [] ->
          [version]

        [prev | _] ->
          if version.content_hash == prev.content_hash do
            acc
          else
            [version | acc]
          end
      end
    end)
    |> Enum.reverse()
  end

  defp link_previous_versions(versions) do
    versions
    |> Enum.with_index()
    |> Enum.map(fn {version, idx} ->
      next_idx = idx + 1

      previous =
        if next_idx < length(versions) do
          Enum.at(versions, next_idx).version_id
        else
          nil
        end

      %{version | previous_version: previous}
    end)
  end

  # ===========================================================================
  # Private - Git Helpers
  # ===========================================================================

  defp get_commits_for_file(repo_path, file_path, limit) do
    safe_limit = min(limit, GitUtils.max_commits())
    args = ["log", "--format=%H", "-n", "#{safe_limit}", "--follow", "--", file_path]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, output} ->
        commits =
          output
          |> String.trim()
          |> String.split("\n", trim: true)

        {:ok, commits}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_commit_info(repo_path, commit_ref) do
    args = ["show", "-s", "--format=%H%n%aI", commit_ref]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, output} ->
        lines = String.split(String.trim(output), "\n")

        case lines do
          [sha, timestamp_str | _] ->
            timestamp =
              case DateTime.from_iso8601(timestamp_str) do
                {:ok, dt, _} -> dt
                _ -> nil
              end

            {:ok, %{sha: sha, timestamp: timestamp}}

          _ ->
            {:error, :parse_error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ===========================================================================
  # Private - Utility Functions
  # ===========================================================================

  defp count_lines(content) do
    content |> String.split("\n") |> length()
  end

  defp extract_function_names(module_source) do
    pattern = ~r/^\s*(def|defp)\s+([a-z_][a-zA-Z0-9_]*[!?]?)/m

    Regex.scan(pattern, module_source)
    |> Enum.map(fn [_, _, name] -> name end)
    |> Enum.uniq()
  end

  defp count_function_clauses(function_source, function_name) do
    func_str = Atom.to_string(function_name)
    pattern = ~r/^\s*(def|defp)\s+#{Regex.escape(func_str)}\s*\(/m

    Regex.scan(pattern, function_source) |> length()
  end
end
