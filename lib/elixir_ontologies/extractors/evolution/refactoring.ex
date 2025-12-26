defmodule ElixirOntologies.Extractors.Evolution.Refactoring do
  @moduledoc """
  Detects and classifies refactoring activities from code changes.

  This module analyzes git diffs to identify common refactoring patterns
  like function extraction, module extraction, renames, and inlining.

  ## Refactoring Types

  | Type | Description |
  |------|-------------|
  | `:extract_function` | Code moved to new function |
  | `:extract_module` | Code moved to new module |
  | `:rename_function` | Function name changed |
  | `:rename_module` | Module name changed |
  | `:rename_variable` | Variable name changed |
  | `:inline_function` | Function body inlined at call sites |
  | `:move_function` | Function moved between modules |

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.{Refactoring, Commit}

      # Detect refactorings in a commit
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      {:ok, refactorings} = Refactoring.detect_refactorings(".", commit)

      # Check specific refactoring types
      extractions = Enum.filter(refactorings, &(&1.type == :extract_function))
  """

  alias ElixirOntologies.Extractors.Evolution.Commit
  alias ElixirOntologies.Extractors.Evolution.GitUtils

  # ===========================================================================
  # Type Definitions
  # ===========================================================================

  @type refactoring_type ::
          :extract_function
          | :extract_module
          | :rename_function
          | :rename_module
          | :rename_variable
          | :inline_function
          | :move_function

  @type confidence :: :high | :medium | :low

  # ===========================================================================
  # Nested Structs
  # ===========================================================================

  defmodule Source do
    @moduledoc """
    Represents the source location of a refactoring.
    """

    @type t :: %__MODULE__{
            file: String.t() | nil,
            module: String.t() | nil,
            function: {atom(), non_neg_integer()} | nil,
            line_range: {pos_integer(), pos_integer()} | nil,
            code: String.t() | nil
          }

    defstruct file: nil,
              module: nil,
              function: nil,
              line_range: nil,
              code: nil
  end

  defmodule Target do
    @moduledoc """
    Represents the target location of a refactoring.
    """

    @type t :: %__MODULE__{
            file: String.t() | nil,
            module: String.t() | nil,
            function: {atom(), non_neg_integer()} | nil,
            line_range: {pos_integer(), pos_integer()} | nil,
            code: String.t() | nil
          }

    defstruct file: nil,
              module: nil,
              function: nil,
              line_range: nil,
              code: nil
  end

  defmodule DiffHunk do
    @moduledoc """
    Represents a parsed diff hunk with additions and deletions.
    """

    @type t :: %__MODULE__{
            file: String.t(),
            old_file: String.t() | nil,
            status: :added | :deleted | :modified | :renamed,
            additions: [{pos_integer(), String.t()}],
            deletions: [{pos_integer(), String.t()}],
            similarity: non_neg_integer() | nil
          }

    defstruct file: nil,
              old_file: nil,
              status: :modified,
              additions: [],
              deletions: [],
              similarity: nil
  end

  # ===========================================================================
  # Main Struct
  # ===========================================================================

  @type t :: %__MODULE__{
          type: refactoring_type(),
          source: Source.t(),
          target: Target.t(),
          commit: Commit.t(),
          confidence: confidence(),
          metadata: map()
        }

  @enforce_keys [:type, :commit]
  defstruct [:type, :source, :target, :commit, confidence: :medium, metadata: %{}]

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Returns all supported refactoring types.
  """
  @spec refactoring_types() :: [refactoring_type()]
  def refactoring_types do
    [
      :extract_function,
      :extract_module,
      :rename_function,
      :rename_module,
      :rename_variable,
      :inline_function,
      :move_function
    ]
  end

  @doc """
  Detects refactorings in a commit.

  Analyzes the diff of a commit to identify refactoring patterns.

  ## Options

  - `:types` - List of refactoring types to detect (default: all)

  ## Examples

      {:ok, refactorings} = Refactoring.detect_refactorings(".", commit)
      {:ok, renames} = Refactoring.detect_refactorings(".", commit, types: [:rename_function])
  """
  @spec detect_refactorings(String.t(), Commit.t(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def detect_refactorings(repo_path, %Commit{} = commit, opts \\ []) do
    types = Keyword.get(opts, :types, refactoring_types())

    with {:ok, diff_hunks} <- get_commit_diff(repo_path, commit) do
      refactorings =
        types
        |> Enum.flat_map(fn type ->
          detect_by_type(type, repo_path, commit, diff_hunks)
        end)
        |> Enum.sort_by(& &1.confidence, :desc)

      {:ok, refactorings}
    end
  end

  @doc """
  Detects refactorings in a commit, raising on error.
  """
  @spec detect_refactorings!(String.t(), Commit.t(), keyword()) :: [t()]
  def detect_refactorings!(repo_path, commit, opts \\ []) do
    case detect_refactorings(repo_path, commit, opts) do
      {:ok, refactorings} -> refactorings
      {:error, reason} -> raise ArgumentError, "Failed to detect refactorings: #{inspect(reason)}"
    end
  end

  @doc """
  Detects refactorings across multiple commits.
  """
  @spec detect_refactorings_in_commits(String.t(), [Commit.t()], keyword()) ::
          {:ok, [{Commit.t(), [t()]}]} | {:error, term()}
  def detect_refactorings_in_commits(repo_path, commits, opts \\ []) do
    results =
      commits
      |> Enum.map(fn commit ->
        case detect_refactorings(repo_path, commit, opts) do
          {:ok, refactorings} -> {commit, refactorings}
          {:error, _} -> {commit, []}
        end
      end)

    {:ok, results}
  end

  # ===========================================================================
  # Diff Parsing
  # ===========================================================================

  @doc """
  Extracts structured diff information from a commit.
  """
  @spec get_commit_diff(String.t(), Commit.t()) :: {:ok, [DiffHunk.t()]} | {:error, term()}
  def get_commit_diff(repo_path, %Commit{sha: sha}) do
    # Use -M to detect renames, --numstat for statistics
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

      {file, old_file, status, similarity} ->
        {additions, deletions} = parse_diff_changes(lines)

        %DiffHunk{
          file: file,
          old_file: old_file,
          status: status,
          additions: additions,
          deletions: deletions,
          similarity: similarity
        }
    end
  end

  defp parse_diff_header([first_line | rest]) do
    # Parse: a/old_path b/new_path
    case Regex.run(~r/a\/(.+?) b\/(.+?)$/, first_line) do
      [_, old_path, new_path] ->
        {status, similarity} = determine_status(rest, old_path, new_path)
        {new_path, if(old_path != new_path, do: old_path), status, similarity}

      _ ->
        nil
    end
  end

  defp parse_diff_header([]), do: nil

  defp determine_status(lines, old_path, new_path) do
    cond do
      Enum.any?(lines, &String.starts_with?(&1, "new file")) ->
        {:added, nil}

      Enum.any?(lines, &String.starts_with?(&1, "deleted file")) ->
        {:deleted, nil}

      old_path != new_path ->
        similarity = extract_similarity(lines)
        {:renamed, similarity}

      true ->
        {:modified, nil}
    end
  end

  defp extract_similarity(lines) do
    lines
    |> Enum.find_value(fn line ->
      case Regex.run(~r/similarity index (\d+)%/, line) do
        [_, pct] -> String.to_integer(pct)
        _ -> nil
      end
    end)
  end

  defp parse_diff_changes(lines) do
    lines
    |> Enum.reduce({[], [], nil}, fn line, {adds, dels, line_num} ->
      cond do
        String.starts_with?(line, "@@") ->
          # Parse hunk header: @@ -old_start,old_count +new_start,new_count @@
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

  # ===========================================================================
  # Detection by Type
  # ===========================================================================

  defp detect_by_type(:extract_function, repo_path, commit, hunks) do
    detect_function_extractions(repo_path, commit, hunks)
  end

  defp detect_by_type(:extract_module, repo_path, commit, hunks) do
    detect_module_extractions(repo_path, commit, hunks)
  end

  defp detect_by_type(:rename_function, repo_path, commit, hunks) do
    detect_function_renames(repo_path, commit, hunks)
  end

  defp detect_by_type(:rename_module, repo_path, commit, hunks) do
    detect_module_renames(repo_path, commit, hunks)
  end

  defp detect_by_type(:rename_variable, _repo_path, _commit, _hunks) do
    # Variable rename detection requires more sophisticated analysis
    # Not implemented in this phase
    []
  end

  defp detect_by_type(:inline_function, repo_path, commit, hunks) do
    detect_function_inlines(repo_path, commit, hunks)
  end

  defp detect_by_type(:move_function, repo_path, commit, hunks) do
    detect_function_moves(repo_path, commit, hunks)
  end

  # ===========================================================================
  # Function Extraction Detection
  # ===========================================================================

  @doc """
  Detects function extraction refactorings.

  Looks for patterns where:
  1. A new function is defined
  2. Code was deleted from another location
  3. A call to the new function appears where code was deleted
  """
  @spec detect_function_extractions(String.t(), Commit.t(), [DiffHunk.t()]) :: [t()]
  def detect_function_extractions(_repo_path, commit, hunks) do
    # Find new function definitions in additions
    new_functions = find_new_function_definitions(hunks)

    # Find deleted code blocks
    deleted_blocks = find_deleted_code_blocks(hunks)

    # Find new function calls in additions (where code was replaced)
    new_calls = find_new_function_calls(hunks)

    # Match extractions: new function + call to it replacing deleted code
    new_functions
    |> Enum.flat_map(fn {file, func_name, func_arity, func_code, line_range} ->
      # Check if there's a call to this function added
      matching_calls =
        new_calls
        |> Enum.filter(fn {_call_file, called_name, _line} ->
          called_name == func_name
        end)

      if Enum.any?(matching_calls) do
        # High confidence: we found both new function and call to it
        [
          %__MODULE__{
            type: :extract_function,
            source: %Source{
              file: file,
              code: find_matching_deleted_code(deleted_blocks, func_code)
            },
            target: %Target{
              file: file,
              module: extract_module_from_file(file),
              function: {String.to_atom(func_name), func_arity},
              line_range: line_range,
              code: func_code
            },
            commit: commit,
            confidence: :high,
            metadata: %{
              calls_found: length(matching_calls)
            }
          }
        ]
      else
        # Medium confidence: new function but no obvious call
        if has_similar_deleted_code?(deleted_blocks, func_code) do
          [
            %__MODULE__{
              type: :extract_function,
              source: %Source{
                file: file,
                code: find_matching_deleted_code(deleted_blocks, func_code)
              },
              target: %Target{
                file: file,
                module: extract_module_from_file(file),
                function: {String.to_atom(func_name), func_arity},
                line_range: line_range,
                code: func_code
              },
              commit: commit,
              confidence: :medium,
              metadata: %{}
            }
          ]
        else
          []
        end
      end
    end)
  end

  defp find_new_function_definitions(hunks) do
    hunks
    |> Enum.filter(&is_elixir_file?(&1.file))
    |> Enum.flat_map(fn hunk ->
      additions_text =
        hunk.additions
        |> Enum.map(fn {_, line} -> line end)
        |> Enum.join("\n")

      # Pattern to match function definitions
      # Matches: def/defp name(args) do/when
      regex = ~r/\b(defp?)\s+([a-z_][a-z0-9_]*[!?]?)\s*\(([^)]*)\)/

      Regex.scan(regex, additions_text)
      |> Enum.map(fn [_full, _def_type, name, args] ->
        arity = count_args(args)
        # Get the full function code
        func_code = extract_function_code(hunk.additions, name)
        line_range = get_function_line_range(hunk.additions, name)
        {hunk.file, name, arity, func_code, line_range}
      end)
    end)
  end

  defp find_deleted_code_blocks(hunks) do
    hunks
    |> Enum.filter(&is_elixir_file?(&1.file))
    |> Enum.flat_map(fn hunk ->
      # Group consecutive deletions into blocks
      hunk.deletions
      |> Enum.chunk_by(fn {line_num, _} ->
        # Group lines that are close together
        div(line_num, 10)
      end)
      |> Enum.map(fn lines ->
        code = lines |> Enum.map(fn {_, line} -> line end) |> Enum.join("\n")
        {start_line, _} = List.first(lines) || {0, ""}
        {end_line, _} = List.last(lines) || {0, ""}
        {hunk.file, code, {start_line, end_line}}
      end)
    end)
  end

  defp find_new_function_calls(hunks) do
    hunks
    |> Enum.filter(&is_elixir_file?(&1.file))
    |> Enum.flat_map(fn hunk ->
      hunk.additions
      |> Enum.flat_map(fn {line_num, line} ->
        # Match function calls: name(args) or Module.name(args)
        ~r/\b([a-z_][a-z0-9_]*[!?]?)\s*\(/
        |> Regex.scan(line)
        |> Enum.map(fn [_, name] -> {hunk.file, name, line_num} end)
      end)
    end)
  end

  defp extract_function_code(additions, func_name) do
    lines = Enum.map(additions, fn {_, line} -> line end)

    # Find function start
    start_idx =
      Enum.find_index(lines, fn line ->
        String.match?(line, ~r/\b(defp?)\s+#{Regex.escape(func_name)}\s*\(/)
      end)

    if start_idx do
      # Extract until we find matching end
      lines
      |> Enum.drop(start_idx)
      |> extract_until_end()
      |> Enum.join("\n")
    else
      ""
    end
  end

  defp extract_until_end(lines) do
    {result, _depth} =
      Enum.reduce_while(lines, {[], 0}, fn line, {acc, depth} ->
        new_depth =
          depth +
            count_occurrences(line, ~r/\b(do|fn)\b/) -
            count_occurrences(line, ~r/\bend\b/)

        if depth > 0 and new_depth == 0 do
          {:halt, {acc ++ [line], 0}}
        else
          new_depth = if depth == 0 and String.match?(line, ~r/\bdo\b/), do: 1, else: new_depth
          {:cont, {acc ++ [line], max(new_depth, 0)}}
        end
      end)

    result
  end

  defp count_occurrences(string, regex) do
    regex |> Regex.scan(string) |> length()
  end

  defp get_function_line_range(additions, func_name) do
    with_indices = Enum.with_index(additions)

    start_idx =
      Enum.find_value(with_indices, fn {{line_num, line}, _idx} ->
        if String.match?(line, ~r/\b(defp?)\s+#{Regex.escape(func_name)}\s*\(/) do
          line_num
        end
      end)

    if start_idx do
      # Find end of function
      lines_from_start =
        additions
        |> Enum.drop_while(fn {num, _} -> num < start_idx end)

      end_line = find_function_end_line(lines_from_start)
      {start_idx, end_line || start_idx}
    else
      nil
    end
  end

  defp find_function_end_line(lines) do
    {end_line, _depth} =
      Enum.reduce_while(lines, {nil, 0}, fn {line_num, line}, {_, depth} ->
        new_depth =
          depth +
            count_occurrences(line, ~r/\b(do|fn)\b/) -
            count_occurrences(line, ~r/\bend\b/)

        if depth > 0 and new_depth == 0 do
          {:halt, {line_num, 0}}
        else
          new_depth = if depth == 0 and String.match?(line, ~r/\bdo\b/), do: 1, else: new_depth
          {:cont, {line_num, max(new_depth, 0)}}
        end
      end)

    end_line
  end

  defp find_matching_deleted_code(deleted_blocks, _func_code) do
    # Return the largest deleted block as potential source
    deleted_blocks
    |> Enum.max_by(fn {_, code, _} -> String.length(code) end, fn -> {nil, nil, nil} end)
    |> elem(1)
  end

  defp has_similar_deleted_code?(deleted_blocks, func_code) do
    func_tokens = tokenize_code(func_code)

    Enum.any?(deleted_blocks, fn {_, deleted_code, _} ->
      deleted_tokens = tokenize_code(deleted_code)
      similarity = jaccard_similarity(func_tokens, deleted_tokens)
      similarity > 0.3
    end)
  end

  defp tokenize_code(code) when is_binary(code) do
    code
    |> String.split(~r/\s+|[^\w]+/, trim: true)
    |> Enum.reject(&(&1 in ~w(def defp do end fn if else case cond with)))
    |> MapSet.new()
  end

  defp tokenize_code(_), do: MapSet.new()

  defp jaccard_similarity(set1, set2) do
    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()

    if union == 0, do: 0.0, else: intersection / union
  end

  # ===========================================================================
  # Module Extraction Detection
  # ===========================================================================

  @doc """
  Detects module extraction refactorings.

  Looks for patterns where:
  1. A new module file is created
  2. Functions were deleted from existing modules
  3. The new module contains similar function signatures
  """
  @spec detect_module_extractions(String.t(), Commit.t(), [DiffHunk.t()]) :: [t()]
  def detect_module_extractions(_repo_path, commit, hunks) do
    # Find newly added module files
    new_modules =
      hunks
      |> Enum.filter(&(&1.status == :added and is_elixir_file?(&1.file)))
      |> Enum.map(fn hunk ->
        module_name = extract_module_name_from_additions(hunk.additions)
        functions = extract_function_names_from_additions(hunk.additions)
        {hunk.file, module_name, functions}
      end)
      |> Enum.reject(fn {_, mod, _} -> is_nil(mod) end)

    # Find deleted functions from existing modules
    deleted_functions =
      hunks
      |> Enum.filter(&(&1.status == :modified and is_elixir_file?(&1.file)))
      |> Enum.flat_map(fn hunk ->
        extract_function_names_from_deletions(hunk.deletions)
        |> Enum.map(fn func -> {hunk.file, func} end)
      end)

    # Match: new module has functions that were deleted elsewhere
    new_modules
    |> Enum.flat_map(fn {new_file, new_module, new_functions} ->
      matching_deleted =
        deleted_functions
        |> Enum.filter(fn {_file, {name, arity}} ->
          Enum.any?(new_functions, fn {n, a} -> n == name and a == arity end)
        end)

      if Enum.any?(matching_deleted) do
        {source_file, _} = List.first(matching_deleted)

        [
          %__MODULE__{
            type: :extract_module,
            source: %Source{
              file: source_file,
              module: extract_module_from_file(source_file)
            },
            target: %Target{
              file: new_file,
              module: new_module
            },
            commit: commit,
            confidence: :high,
            metadata: %{
              functions_moved: length(matching_deleted),
              function_names: Enum.map(matching_deleted, fn {_, func} -> func end)
            }
          }
        ]
      else
        []
      end
    end)
  end

  defp extract_module_name_from_additions(additions) do
    additions
    |> Enum.find_value(fn {_, line} ->
      case Regex.run(~r/defmodule\s+([A-Z][\w.]+)/, line) do
        [_, name] -> name
        _ -> nil
      end
    end)
  end

  defp extract_function_names_from_additions(additions) do
    additions
    |> Enum.flat_map(fn {_, line} ->
      case Regex.run(~r/\b(defp?)\s+([a-z_][a-z0-9_]*[!?]?)\s*\(([^)]*)\)/, line) do
        [_, _, name, args] -> [{name, count_args(args)}]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp extract_function_names_from_deletions(deletions) do
    deletions
    |> Enum.flat_map(fn {_, line} ->
      case Regex.run(~r/\b(defp?)\s+([a-z_][a-z0-9_]*[!?]?)\s*\(([^)]*)\)/, line) do
        [_, _, name, args] -> [{name, count_args(args)}]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  # ===========================================================================
  # Rename Detection
  # ===========================================================================

  @doc """
  Detects function rename refactorings.

  Looks for patterns where:
  1. A function is deleted
  2. A similar function with different name is added
  3. Function bodies have high similarity
  """
  @spec detect_function_renames(String.t(), Commit.t(), [DiffHunk.t()]) :: [t()]
  def detect_function_renames(_repo_path, commit, hunks) do
    hunks
    |> Enum.filter(&(&1.status == :modified and is_elixir_file?(&1.file)))
    |> Enum.flat_map(fn hunk ->
      deleted_funcs = extract_functions_with_body(hunk.deletions)
      added_funcs = extract_functions_with_body(hunk.additions)

      # Match by body similarity
      deleted_funcs
      |> Enum.flat_map(fn {del_name, del_arity, del_body} ->
        added_funcs
        |> Enum.filter(fn {add_name, add_arity, add_body} ->
          # Different name, same arity, similar body
          del_name != add_name and
            del_arity == add_arity and
            code_similarity(del_body, add_body) > 0.7
        end)
        |> Enum.map(fn {add_name, add_arity, _add_body} ->
          %__MODULE__{
            type: :rename_function,
            source: %Source{
              file: hunk.file,
              module: extract_module_from_file(hunk.file),
              function: {String.to_atom(del_name), del_arity}
            },
            target: %Target{
              file: hunk.file,
              module: extract_module_from_file(hunk.file),
              function: {String.to_atom(add_name), add_arity}
            },
            commit: commit,
            confidence: :high,
            metadata: %{}
          }
        end)
      end)
    end)
  end

  defp extract_functions_with_body(lines) do
    lines_text = Enum.map(lines, fn {_, line} -> line end)

    # Find function definitions and their bodies
    lines_text
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, idx} ->
      case Regex.run(~r/\b(defp?)\s+([a-z_][a-z0-9_]*[!?]?)\s*\(([^)]*)\)/, line) do
        [_, _, name, args] ->
          arity = count_args(args)
          body = extract_function_body(lines_text, idx)
          [{name, arity, body}]

        _ ->
          []
      end
    end)
  end

  defp extract_function_body(lines, start_idx) do
    lines
    |> Enum.drop(start_idx)
    |> extract_until_end()
    |> Enum.join("\n")
  end

  defp code_similarity(code1, code2) do
    tokens1 = tokenize_code(code1)
    tokens2 = tokenize_code(code2)
    jaccard_similarity(tokens1, tokens2)
  end

  @doc """
  Detects module rename refactorings.

  Uses git's rename detection or module declaration changes.
  """
  @spec detect_module_renames(String.t(), Commit.t(), [DiffHunk.t()]) :: [t()]
  def detect_module_renames(_repo_path, commit, hunks) do
    # Check for file renames with high similarity
    hunks
    |> Enum.filter(&(&1.status == :renamed and is_elixir_file?(&1.file)))
    |> Enum.map(fn hunk ->
      old_module = extract_module_from_file(hunk.old_file)
      new_module = extract_module_from_file(hunk.file)

      %__MODULE__{
        type: :rename_module,
        source: %Source{
          file: hunk.old_file,
          module: old_module
        },
        target: %Target{
          file: hunk.file,
          module: new_module
        },
        commit: commit,
        confidence: if(hunk.similarity && hunk.similarity >= 90, do: :high, else: :medium),
        metadata: %{
          similarity: hunk.similarity
        }
      }
    end)
  end

  # ===========================================================================
  # Inline Detection
  # ===========================================================================

  @doc """
  Detects function inline refactorings.

  Looks for patterns where:
  1. A function definition is deleted
  2. The function body appears at former call sites
  """
  @spec detect_function_inlines(String.t(), Commit.t(), [DiffHunk.t()]) :: [t()]
  def detect_function_inlines(_repo_path, commit, hunks) do
    hunks
    |> Enum.filter(&(&1.status == :modified and is_elixir_file?(&1.file)))
    |> Enum.flat_map(fn hunk ->
      # Find deleted function definitions
      deleted_funcs = extract_functions_with_body(hunk.deletions)

      # Find added code blocks (potential inlined code)
      added_code =
        hunk.additions
        |> Enum.map(fn {_, line} -> line end)
        |> Enum.join("\n")

      # Check if deleted function body appears in additions
      deleted_funcs
      |> Enum.filter(fn {_name, _arity, body} ->
        body_tokens = tokenize_code(body)
        added_tokens = tokenize_code(added_code)

        # Check if most of the function body tokens appear in additions
        if MapSet.size(body_tokens) > 0 do
          common = MapSet.intersection(body_tokens, added_tokens) |> MapSet.size()
          common / MapSet.size(body_tokens) > 0.6
        else
          false
        end
      end)
      |> Enum.map(fn {name, arity, body} ->
        %__MODULE__{
          type: :inline_function,
          source: %Source{
            file: hunk.file,
            module: extract_module_from_file(hunk.file),
            function: {String.to_atom(name), arity},
            code: body
          },
          target: %Target{
            file: hunk.file
          },
          commit: commit,
          confidence: :medium,
          metadata: %{}
        }
      end)
    end)
  end

  # ===========================================================================
  # Move Function Detection
  # ===========================================================================

  @doc """
  Detects function move refactorings.

  Looks for patterns where:
  1. A function is deleted from one module
  2. A similar function is added to another module
  """
  @spec detect_function_moves(String.t(), Commit.t(), [DiffHunk.t()]) :: [t()]
  def detect_function_moves(_repo_path, commit, hunks) do
    elixir_hunks = Enum.filter(hunks, &is_elixir_file?(&1.file))

    # Collect all deleted and added functions across files
    deleted =
      elixir_hunks
      |> Enum.flat_map(fn hunk ->
        extract_functions_with_body(hunk.deletions)
        |> Enum.map(fn {name, arity, body} -> {hunk.file, name, arity, body} end)
      end)

    added =
      elixir_hunks
      |> Enum.flat_map(fn hunk ->
        extract_functions_with_body(hunk.additions)
        |> Enum.map(fn {name, arity, body} -> {hunk.file, name, arity, body} end)
      end)

    # Match functions moved between different files
    deleted
    |> Enum.flat_map(fn {del_file, del_name, del_arity, del_body} ->
      added
      |> Enum.filter(fn {add_file, add_name, add_arity, add_body} ->
        # Different file, same name and arity, similar body
        del_file != add_file and
          del_name == add_name and
          del_arity == add_arity and
          code_similarity(del_body, add_body) > 0.7
      end)
      |> Enum.map(fn {add_file, add_name, add_arity, _} ->
        %__MODULE__{
          type: :move_function,
          source: %Source{
            file: del_file,
            module: extract_module_from_file(del_file),
            function: {String.to_atom(del_name), del_arity}
          },
          target: %Target{
            file: add_file,
            module: extract_module_from_file(add_file),
            function: {String.to_atom(add_name), add_arity}
          },
          commit: commit,
          confidence: :high,
          metadata: %{}
        }
      end)
    end)
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
    # Simple arg counting - split by comma, accounting for nested structures
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
