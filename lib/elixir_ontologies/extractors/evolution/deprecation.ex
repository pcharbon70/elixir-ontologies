defmodule ElixirOntologies.Extractors.Evolution.Deprecation do
  @moduledoc """
  Tracks deprecation activities and their timeline.

  This module detects `@deprecated` attributes in Elixir code and tracks
  when functions/modules are deprecated and eventually removed.

  ## Deprecation Patterns

  Elixir uses the `@deprecated` module attribute to mark deprecated functions:

      @deprecated "Use new_function/1 instead"
      def old_function(arg), do: ...

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.{Deprecation, Commit}

      # Detect deprecations in a commit
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, deprecations} = Deprecation.detect_deprecations(".", commit)

      # Track deprecation history for a file
      {:ok, timeline} = Deprecation.track_deprecations(".", "lib/my_module.ex")

  ## Replacement Extraction

  The module parses deprecation messages to extract replacement suggestions:

      iex> Deprecation.parse_replacement("Use new_func/2 instead")
      %Replacement{text: "Use new_func/2 instead", function: {:new_func, 2}}

      iex> Deprecation.parse_replacement("See MyModule.other_func/1")
      %Replacement{text: "See MyModule.other_func/1", module: "MyModule", function: {:other_func, 1}}
  """

  alias ElixirOntologies.Extractors.Evolution.Commit
  alias ElixirOntologies.Extractors.Evolution.GitUtils
  alias ElixirOntologies.Extractors.Evolution.Refactoring.DiffHunk

  # ===========================================================================
  # Type Definitions
  # ===========================================================================

  @type element_type :: :function | :module | :macro | :callback | :type

  # ===========================================================================
  # Nested Structs
  # ===========================================================================

  defmodule DeprecationEvent do
    @moduledoc """
    Represents when and where a deprecation was announced.
    """

    @type t :: %__MODULE__{
            commit: Commit.t() | nil,
            file: String.t(),
            line: pos_integer() | nil
          }

    defstruct commit: nil,
              file: nil,
              line: nil
  end

  defmodule RemovalEvent do
    @moduledoc """
    Represents when and where a deprecated element was removed.
    """

    @type t :: %__MODULE__{
            commit: Commit.t() | nil,
            file: String.t()
          }

    defstruct commit: nil,
              file: nil
  end

  defmodule Replacement do
    @moduledoc """
    Represents a suggested replacement for a deprecated element.
    """

    @type t :: %__MODULE__{
            text: String.t(),
            function: {atom(), non_neg_integer()} | nil,
            module: String.t() | nil
          }

    defstruct text: nil,
              function: nil,
              module: nil
  end

  # ===========================================================================
  # Main Struct
  # ===========================================================================

  @type t :: %__MODULE__{
          element_type: element_type(),
          element_name: String.t(),
          module: String.t() | nil,
          function: {atom(), non_neg_integer()} | nil,
          deprecated_in: DeprecationEvent.t() | nil,
          removed_in: RemovalEvent.t() | nil,
          replacement: Replacement.t() | nil,
          message: String.t(),
          metadata: map()
        }

  @enforce_keys [:element_type, :element_name, :message]
  defstruct [
    :element_type,
    :element_name,
    :module,
    :function,
    :deprecated_in,
    :removed_in,
    :replacement,
    :message,
    metadata: %{}
  ]

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Returns all supported element types that can be deprecated.
  """
  @spec element_types() :: [element_type()]
  def element_types do
    [:function, :module, :macro, :callback, :type]
  end

  @doc """
  Detects deprecations added in a commit.

  Analyzes the diff to find new `@deprecated` attributes.

  ## Examples

      {:ok, deprecations} = Deprecation.detect_deprecations(".", commit)
  """
  @spec detect_deprecations(String.t(), Commit.t()) :: {:ok, [t()]} | {:error, term()}
  def detect_deprecations(repo_path, %Commit{} = commit) do
    with {:ok, diff_hunks} <- get_commit_diff(repo_path, commit) do
      deprecations =
        diff_hunks
        |> Enum.filter(&is_elixir_file?(&1.file))
        |> Enum.flat_map(fn hunk ->
          detect_deprecations_in_hunk(hunk, commit)
        end)

      {:ok, deprecations}
    end
  end

  @doc """
  Detects deprecations in a commit, raising on error.
  """
  @spec detect_deprecations!(String.t(), Commit.t()) :: [t()]
  def detect_deprecations!(repo_path, commit) do
    case detect_deprecations(repo_path, commit) do
      {:ok, deprecations} -> deprecations
      {:error, reason} -> raise ArgumentError, "Failed to detect deprecations: #{inspect(reason)}"
    end
  end

  @doc """
  Tracks deprecation history for a file.

  Returns a list of deprecations found in the file's history.
  """
  @spec track_deprecations(String.t(), String.t(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def track_deprecations(repo_path, file_path, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    with {:ok, commits} <- get_file_commits(repo_path, file_path, limit) do
      deprecations =
        commits
        |> Enum.flat_map(fn commit ->
          case detect_deprecations(repo_path, commit) do
            {:ok, deps} -> Enum.filter(deps, &(&1.deprecated_in.file == file_path))
            {:error, _} -> []
          end
        end)

      {:ok, deprecations}
    end
  end

  @doc """
  Finds commits that add deprecation annotations.
  """
  @spec find_deprecation_commits(String.t(), keyword()) ::
          {:ok, [Commit.t()]} | {:error, term()}
  def find_deprecation_commits(repo_path, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    # Search for commits that add @deprecated
    args = [
      "log",
      "--all",
      "-S",
      "@deprecated",
      "--pretty=format:%H",
      "-n",
      to_string(limit)
    ]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, output} ->
        shas =
          output
          |> String.split("\n", trim: true)

        commits =
          shas
          |> Enum.map(fn sha ->
            case Commit.extract_commit(repo_path, sha) do
              {:ok, commit} -> commit
              {:error, _} -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, commits}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Detects removed deprecated elements in a commit.

  Finds functions/modules that were previously deprecated and are now removed.
  """
  @spec detect_removals(String.t(), Commit.t()) :: {:ok, [t()]} | {:error, term()}
  def detect_removals(repo_path, %Commit{} = commit) do
    with {:ok, diff_hunks} <- get_commit_diff(repo_path, commit) do
      removals =
        diff_hunks
        |> Enum.filter(&is_elixir_file?(&1.file))
        |> Enum.flat_map(fn hunk ->
          detect_removals_in_hunk(hunk, commit)
        end)

      {:ok, removals}
    end
  end

  @doc """
  Parses a deprecation message to extract replacement information.

  ## Patterns Recognized

  - "Use X instead" / "use X instead"
  - "See X" / "see X"
  - "Replaced by X" / "replaced by X"
  - Function references: `func/arity` or `Module.func/arity`

  ## Examples

      iex> Deprecation.parse_replacement("Use new_func/2 instead")
      %Replacement{text: "Use new_func/2 instead", function: {:new_func, 2}}

      iex> Deprecation.parse_replacement("See MyModule.other/1 for details")
      %Replacement{text: "See MyModule.other/1 for details", module: "MyModule", function: {:other, 1}}
  """
  @spec parse_replacement(String.t()) :: Replacement.t() | nil
  def parse_replacement(nil), do: nil
  def parse_replacement(""), do: nil

  def parse_replacement(message) when is_binary(message) do
    # Try to extract function reference
    func_ref = extract_function_reference(message)

    if func_ref do
      %Replacement{
        text: message,
        function: func_ref.function,
        module: func_ref.module
      }
    else
      # Just return the text if no function reference found
      %Replacement{text: message}
    end
  end

  @doc """
  Checks if a deprecation has a known replacement.
  """
  @spec has_replacement?(t()) :: boolean()
  def has_replacement?(%__MODULE__{replacement: nil}), do: false

  def has_replacement?(%__MODULE__{replacement: %Replacement{function: nil, module: nil}}),
    do: false

  def has_replacement?(%__MODULE__{}), do: true

  @doc """
  Checks if a deprecated element has been removed.
  """
  @spec removed?(t()) :: boolean()
  def removed?(%__MODULE__{removed_in: nil}), do: false
  def removed?(%__MODULE__{removed_in: %RemovalEvent{}}), do: true

  # ===========================================================================
  # Deprecation Detection
  # ===========================================================================

  defp detect_deprecations_in_hunk(hunk, commit) do
    additions = hunk.additions

    # Find @deprecated attributes in additions
    additions
    |> Enum.with_index()
    |> Enum.flat_map(fn {{line_num, line}, idx} ->
      case parse_deprecated_attribute(line) do
        {:ok, message} ->
          # Find the following function/macro definition
          element = find_following_element(additions, idx)

          [
            build_deprecation(
              element,
              message,
              hunk.file,
              line_num,
              commit
            )
          ]

        :error ->
          []
      end
    end)
  end

  defp parse_deprecated_attribute(line) do
    # Match @deprecated "message" or @deprecated ~s/message/ etc.
    patterns = [
      # Double-quoted string
      ~r/@deprecated\s+"([^"]+)"/,
      # Single-quoted charlist
      ~r/@deprecated\s+'([^']+)'/,
      # Heredoc (simplified - just captures first line)
      ~r/@deprecated\s+~[sS]\[([^\]]+)\]/,
      # Sigil with different delimiters
      ~r/@deprecated\s+~[sS]\/([^\/]+)\//,
      ~r/@deprecated\s+~[sS]\(([^)]+)\)/,
      ~r/@deprecated\s+~[sS]\{([^}]+)\}/,
      # Boolean true (no message)
      ~r/@deprecated\s+true/
    ]

    Enum.find_value(patterns, :error, fn pattern ->
      case Regex.run(pattern, line) do
        [_, message] -> {:ok, message}
        [_] -> {:ok, "Deprecated"}
        nil -> nil
      end
    end)
  end

  defp find_following_element(additions, start_idx) do
    additions
    |> Enum.drop(start_idx + 1)
    |> Enum.find_value(fn {_line_num, line} ->
      cond do
        # Function definition
        match = Regex.run(~r/\bdef\s+([a-z_][a-z0-9_]*[!?]?)\s*\(([^)]*)\)/, line) ->
          [_, name, args] = match
          {:function, name, count_args(args)}

        # Private function
        match = Regex.run(~r/\bdefp\s+([a-z_][a-z0-9_]*[!?]?)\s*\(([^)]*)\)/, line) ->
          [_, name, args] = match
          {:function, name, count_args(args)}

        # Macro
        match = Regex.run(~r/\bdefmacro\s+([a-z_][a-z0-9_]*[!?]?)\s*\(([^)]*)\)/, line) ->
          [_, name, args] = match
          {:macro, name, count_args(args)}

        # Private macro
        match = Regex.run(~r/\bdefmacrop\s+([a-z_][a-z0-9_]*[!?]?)\s*\(([^)]*)\)/, line) ->
          [_, name, args] = match
          {:macro, name, count_args(args)}

        # Callback
        match = Regex.run(~r/@callback\s+([a-z_][a-z0-9_]*[!?]?)\s*\(/, line) ->
          [_, name] = match
          {:callback, name, nil}

        # Type
        match = Regex.run(~r/@type\s+([a-z_][a-z0-9_]*)\s*::/, line) ->
          [_, name] = match
          {:type, name, nil}

        # Module (for module-level deprecation)
        match = Regex.run(~r/defmodule\s+([A-Z][\w.]+)/, line) ->
          [_, name] = match
          {:module, name, nil}

        # Skip empty lines and comments, continue searching
        String.trim(line) == "" or String.starts_with?(String.trim(line), "#") ->
          nil

        # Stop if we hit another attribute (might be separate deprecation)
        String.starts_with?(String.trim(line), "@") ->
          nil

        true ->
          nil
      end
    end)
  end

  defp build_deprecation(element, message, file, line_num, commit) do
    {element_type, element_name, arity} =
      case element do
        {type, name, arity} -> {type, name, arity}
        nil -> {:unknown, "unknown", nil}
      end

    module_name = extract_module_from_file(file)

    function =
      if arity do
        {String.to_atom(element_name), arity}
      else
        nil
      end

    %__MODULE__{
      element_type: element_type,
      element_name: element_name,
      module: module_name,
      function: function,
      deprecated_in: %DeprecationEvent{
        commit: commit,
        file: file,
        line: line_num
      },
      removed_in: nil,
      replacement: parse_replacement(message),
      message: message,
      metadata: %{}
    }
  end

  # ===========================================================================
  # Removal Detection
  # ===========================================================================

  defp detect_removals_in_hunk(hunk, commit) do
    deletions = hunk.deletions

    # Find deprecated functions/macros being deleted
    # Look for @deprecated followed by def/defp/defmacro in deletions
    find_deprecated_removals(deletions, hunk.file, commit)
  end

  defp find_deprecated_removals(deletions, file, commit) do
    # Group consecutive deletions
    deletion_lines = Enum.map(deletions, fn {_, line} -> line end)

    # Find @deprecated + function pairs
    find_deprecated_function_pairs(deletion_lines, file, commit)
  end

  defp find_deprecated_function_pairs(lines, file, commit) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, idx} ->
      case parse_deprecated_attribute(line) do
        {:ok, message} ->
          # Check if next lines have function definition
          following_lines = Enum.drop(lines, idx + 1)

          case find_element_in_lines(following_lines) do
            {type, name, arity} ->
              module_name = extract_module_from_file(file)

              function =
                if arity do
                  {String.to_atom(name), arity}
                else
                  nil
                end

              [
                %__MODULE__{
                  element_type: type,
                  element_name: name,
                  module: module_name,
                  function: function,
                  deprecated_in: nil,
                  removed_in: %RemovalEvent{
                    commit: commit,
                    file: file
                  },
                  replacement: parse_replacement(message),
                  message: message,
                  metadata: %{previously_deprecated: true}
                }
              ]

            nil ->
              []
          end

        :error ->
          []
      end
    end)
  end

  defp find_element_in_lines(lines) do
    Enum.find_value(lines, fn line ->
      cond do
        match = Regex.run(~r/\bdefp?\s+([a-z_][a-z0-9_]*[!?]?)\s*\(([^)]*)\)/, line) ->
          [_, name, args] = match
          {:function, name, count_args(args)}

        match = Regex.run(~r/\bdefmacrop?\s+([a-z_][a-z0-9_]*[!?]?)\s*\(([^)]*)\)/, line) ->
          [_, name, args] = match
          {:macro, name, count_args(args)}

        String.trim(line) == "" or String.starts_with?(String.trim(line), "#") ->
          nil

        String.starts_with?(String.trim(line), "@") and
            not String.starts_with?(String.trim(line), "@deprecated") ->
          nil

        true ->
          nil
      end
    end)
  end

  # ===========================================================================
  # Replacement Parsing
  # ===========================================================================

  defp extract_function_reference(message) do
    patterns = [
      # Module.function/arity (3 captures: module, func, arity)
      ~r/([A-Z][\w.]+)\.([a-z_][a-z0-9_]*[!?]?)\/(\d+)/,
      # Module.function without arity (2 captures: module, func)
      ~r/([A-Z][\w.]+)\.([a-z_][a-z0-9_]*[!?]?)\b(?!\/)/,
      # function/arity (2 captures: func, arity - func starts with lowercase)
      ~r/\b([a-z_][a-z0-9_]*[!?]?)\/(\d+)/,
      # :module (atom)
      ~r/:([a-z_][a-z0-9_]*)\b/
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, message) do
        # Module.function/arity - 4 elements (full match + 3 captures)
        [_, module, func, arity] ->
          %{module: module, function: {String.to_atom(func), String.to_integer(arity)}}

        # 3 elements - could be Module.func or func/arity
        [_, first, second] ->
          cond do
            # Module.function (module starts uppercase, second is function)
            String.match?(first, ~r/^[A-Z]/) ->
              %{module: first, function: {String.to_atom(second), 0}}

            # function/arity (first is function, second is arity number)
            String.match?(first, ~r/^[a-z]/) and String.match?(second, ~r/^\d+$/) ->
              %{module: nil, function: {String.to_atom(first), String.to_integer(second)}}

            true ->
              nil
          end

        # :atom - 2 elements
        [_, atom] when byte_size(atom) > 0 ->
          %{module: Macro.camelize(atom), function: nil}

        _ ->
          nil
      end
    end)
  end

  # ===========================================================================
  # Git Helpers
  # ===========================================================================

  defp get_commit_diff(repo_path, %Commit{sha: sha}) do
    args = ["diff-tree", "-p", "-M", "--no-commit-id", sha]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, output} ->
        hunks = parse_diff_output(output)
        {:ok, hunks}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_diff_output(output) do
    output
    |> String.split(~r/^diff --git /m, trim: true)
    |> Enum.map(&parse_diff_section/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_diff_section(section) do
    lines = String.split(section, "\n")

    case parse_diff_header(lines) do
      nil ->
        nil

      {file, old_file, status} ->
        {additions, deletions} = parse_diff_changes(lines)

        %DiffHunk{
          file: file,
          old_file: old_file,
          status: status,
          additions: additions,
          deletions: deletions
        }
    end
  end

  defp parse_diff_header([first_line | rest]) do
    case Regex.run(~r/a\/(.+?) b\/(.+?)$/, first_line) do
      [_, old_path, new_path] ->
        status = determine_status(rest)
        {new_path, if(old_path != new_path, do: old_path), status}

      _ ->
        nil
    end
  end

  defp parse_diff_header([]), do: nil

  defp determine_status(lines) do
    cond do
      Enum.any?(lines, &String.starts_with?(&1, "new file")) -> :added
      Enum.any?(lines, &String.starts_with?(&1, "deleted file")) -> :deleted
      true -> :modified
    end
  end

  defp parse_diff_changes(lines) do
    lines
    |> Enum.reduce({[], [], nil}, fn line, {adds, dels, line_num} ->
      cond do
        String.starts_with?(line, "@@") ->
          new_line_num =
            case Regex.run(~r/@@ -\d+(?:,\d+)? \+(\d+)/, line) do
              [_, start] -> String.to_integer(start)
              _ -> 1
            end

          {adds, dels, new_line_num}

        String.starts_with?(line, "+") and not String.starts_with?(line, "+++") ->
          content = String.slice(line, 1..-1//1)
          {[{line_num || 1, content} | adds], dels, (line_num || 1) + 1}

        String.starts_with?(line, "-") and not String.starts_with?(line, "---") ->
          content = String.slice(line, 1..-1//1)
          {adds, [{line_num || 1, content} | dels], line_num}

        line_num != nil ->
          {adds, dels, line_num + 1}

        true ->
          {adds, dels, line_num}
      end
    end)
    |> then(fn {adds, dels, _} -> {Enum.reverse(adds), Enum.reverse(dels)} end)
  end

  defp get_file_commits(repo_path, file_path, limit) do
    args = [
      "log",
      "--follow",
      "--pretty=format:%H",
      "-n",
      to_string(limit),
      "--",
      file_path
    ]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, output} ->
        shas = String.split(output, "\n", trim: true)

        commits =
          shas
          |> Enum.map(fn sha ->
            case Commit.extract_commit(repo_path, sha) do
              {:ok, commit} -> commit
              {:error, _} -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, commits}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp is_elixir_file?(nil), do: false

  defp is_elixir_file?(path) do
    String.ends_with?(path, ".ex") or String.ends_with?(path, ".exs")
  end

  defp count_args(""), do: 0

  defp count_args(args) do
    args
    |> String.trim()
    |> count_top_level_commas()
    |> Kernel.+(1)
  end

  defp count_top_level_commas(str) do
    {count, _depth} =
      str
      |> String.graphemes()
      |> Enum.reduce({0, 0}, fn char, {count, depth} ->
        case char do
          "(" -> {count, depth + 1}
          ")" -> {count, max(depth - 1, 0)}
          "[" -> {count, depth + 1}
          "]" -> {count, max(depth - 1, 0)}
          "{" -> {count, depth + 1}
          "}" -> {count, max(depth - 1, 0)}
          "," when depth == 0 -> {count + 1, depth}
          _ -> {count, depth}
        end
      end)

    count
  end

  defp extract_module_from_file(nil), do: nil

  defp extract_module_from_file(path) do
    path
    |> String.replace(~r/^(lib|test)\//, "")
    |> String.replace(~r/\.exs?$/, "")
    |> String.split("/")
    |> Enum.map(&Macro.camelize/1)
    |> Enum.join(".")
  end
end
