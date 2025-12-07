defmodule ElixirOntologies.Analyzer.Git do
  @moduledoc """
  Detects git repositories and extracts metadata.

  This module provides functions to detect if a directory is within a git
  repository and extract information such as remote URLs, branch names,
  and repository metadata.

  ## Usage

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, repo} = Git.repository(".")
      iex> is_binary(repo.name)
      true

  ## Repository Detection

  The `detect_repo/1` function traverses up the directory tree looking for
  a `.git` directory, returning the repository root path if found.

  ## Remote URL Parsing

  Supports various remote URL formats:
  - HTTPS: `https://github.com/owner/repo.git`
  - SSH: `ssh://git@github.com/owner/repo.git`
  - Git@: `git@github.com:owner/repo.git`
  - Git: `git://github.com/owner/repo.git`
  """

  # ===========================================================================
  # Repository Struct
  # ===========================================================================

  defmodule Repository do
    @moduledoc """
    Represents a git repository with its metadata.
    """

    @type t :: %__MODULE__{
            path: String.t() | nil,
            name: String.t() | nil,
            remote_url: String.t() | nil,
            host: String.t() | nil,
            owner: String.t() | nil,
            current_branch: String.t() | nil,
            default_branch: String.t() | nil,
            current_commit: String.t() | nil,
            metadata: map()
          }

    defstruct [
      :path,
      :name,
      :remote_url,
      :host,
      :owner,
      :current_branch,
      :default_branch,
      :current_commit,
      metadata: %{}
    ]
  end

  # ===========================================================================
  # Commit Reference Struct
  # ===========================================================================

  defmodule CommitRef do
    @moduledoc """
    Represents a git commit reference with its metadata.
    """

    @type t :: %__MODULE__{
            sha: String.t(),
            short_sha: String.t(),
            message: String.t() | nil,
            tags: [String.t()],
            timestamp: DateTime.t() | nil,
            author: String.t() | nil
          }

    @enforce_keys [:sha, :short_sha]
    defstruct [
      :sha,
      :short_sha,
      :message,
      :timestamp,
      :author,
      tags: []
    ]
  end

  # ===========================================================================
  # Source File Struct
  # ===========================================================================

  defmodule SourceFile do
    @moduledoc """
    Represents a source file within a git repository.

    Links a file to its repository context with both absolute and relative paths.
    """

    @type t :: %__MODULE__{
            absolute_path: String.t(),
            relative_path: String.t(),
            repository_path: String.t() | nil,
            last_commit: String.t() | nil
          }

    @enforce_keys [:absolute_path, :relative_path]
    defstruct [
      :absolute_path,
      :relative_path,
      :repository_path,
      :last_commit
    ]
  end

  # ===========================================================================
  # Parsed URL Struct
  # ===========================================================================

  defmodule ParsedUrl do
    @moduledoc """
    Represents a parsed git remote URL.
    """

    @type t :: %__MODULE__{
            host: String.t() | nil,
            owner: String.t() | nil,
            repo: String.t() | nil,
            protocol: :https | :ssh | :git | nil
          }

    defstruct [:host, :owner, :repo, :protocol]
  end

  # ===========================================================================
  # Repository Detection
  # ===========================================================================

  @doc """
  Detects if a path is within a git repository.

  Traverses up the directory tree looking for a `.git` directory.
  Returns `{:ok, repo_root}` if found, `{:error, reason}` otherwise.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, path} = Git.detect_repo(".")
      iex> File.dir?(Path.join(path, ".git"))
      true

      iex> alias ElixirOntologies.Analyzer.Git
      iex> Git.detect_repo("/nonexistent")
      {:error, :invalid_path}
  """
  @spec detect_repo(String.t()) :: {:ok, String.t()} | {:error, :not_found | :invalid_path}
  def detect_repo(path) do
    case File.exists?(path) do
      true ->
        abs_path = Path.expand(path)
        find_git_root(abs_path)

      false ->
        {:error, :invalid_path}
    end
  end

  @doc """
  Detects repository, raising on error.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> path = Git.detect_repo!(".")
      iex> is_binary(path)
      true
  """
  @spec detect_repo!(String.t()) :: String.t()
  def detect_repo!(path) do
    case detect_repo(path) do
      {:ok, repo_path} -> repo_path
      {:error, reason} -> raise "Failed to detect git repository: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Remote URL Extraction
  # ===========================================================================

  @doc """
  Extracts the origin remote URL from a git repository.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, url} = Git.remote_url(".")
      iex> is_binary(url)
      true
  """
  @spec remote_url(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def remote_url(path) do
    with {:ok, repo_path} <- detect_repo(path) do
      case run_git_command(repo_path, ["config", "--get", "remote.origin.url"]) do
        {:ok, url} -> {:ok, String.trim(url)}
        {:error, _} -> {:error, :no_remote}
      end
    end
  end

  @doc """
  Parses a git remote URL into its components.

  Supports HTTPS, SSH, git@, and git:// URL formats.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, parsed} = Git.parse_remote_url("https://github.com/owner/repo.git")
      iex> parsed.host
      "github.com"
      iex> parsed.owner
      "owner"
      iex> parsed.repo
      "repo"

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, parsed} = Git.parse_remote_url("git@github.com:owner/repo.git")
      iex> parsed.host
      "github.com"
      iex> parsed.owner
      "owner"
      iex> parsed.repo
      "repo"

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, parsed} = Git.parse_remote_url("ssh://git@gitlab.com/owner/repo.git")
      iex> parsed.host
      "gitlab.com"
      iex> parsed.protocol
      :ssh
  """
  @spec parse_remote_url(String.t()) :: {:ok, ParsedUrl.t()} | {:error, :invalid_url}
  def parse_remote_url(url) do
    cond do
      # HTTPS format: https://github.com/owner/repo.git
      String.starts_with?(url, "https://") ->
        parse_https_url(url)

      # SSH format: ssh://git@github.com/owner/repo.git
      String.starts_with?(url, "ssh://") ->
        parse_ssh_url(url)

      # Git@ format: git@github.com:owner/repo.git
      String.starts_with?(url, "git@") ->
        parse_git_at_url(url)

      # Git protocol: git://github.com/owner/repo.git
      String.starts_with?(url, "git://") ->
        parse_git_protocol_url(url)

      true ->
        {:error, :invalid_url}
    end
  end

  # ===========================================================================
  # Branch Information
  # ===========================================================================

  @doc """
  Gets the current branch name.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, branch} = Git.current_branch(".")
      iex> is_binary(branch)
      true
  """
  @spec current_branch(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def current_branch(path) do
    with {:ok, repo_path} <- detect_repo(path) do
      case run_git_command(repo_path, ["rev-parse", "--abbrev-ref", "HEAD"]) do
        {:ok, branch} -> {:ok, String.trim(branch)}
        {:error, _} -> {:error, :no_branch}
      end
    end
  end

  @doc """
  Gets the default branch name (typically main or master).

  Attempts to determine the default branch by checking:
  1. Remote HEAD reference
  2. Common branch names (main, master)

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, branch} = Git.default_branch(".")
      iex> branch in ["main", "master", "develop"]
      true
  """
  @spec default_branch(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def default_branch(path) do
    with {:ok, repo_path} <- detect_repo(path) do
      # Try to get from remote HEAD
      case run_git_command(repo_path, ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"]) do
        {:ok, ref} ->
          # Returns something like "origin/main", extract just the branch name
          branch =
            ref
            |> String.trim()
            |> String.replace_prefix("origin/", "")

          {:ok, branch}

        {:error, _} ->
          # Fallback: check if main or master exists
          find_default_branch(repo_path)
      end
    end
  end

  # ===========================================================================
  # Commit Information
  # ===========================================================================

  @doc """
  Gets the current commit SHA (full 40-character hash).

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, sha} = Git.current_commit(".")
      iex> String.length(sha)
      40
  """
  @spec current_commit(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def current_commit(path) do
    with {:ok, repo_path} <- detect_repo(path) do
      case run_git_command(repo_path, ["rev-parse", "HEAD"]) do
        {:ok, sha} -> {:ok, String.trim(sha)}
        {:error, _} -> {:error, :no_commit}
      end
    end
  end

  @doc """
  Gets the current commit short SHA (7 characters).

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, sha} = Git.current_commit_short(".")
      iex> String.length(sha)
      7
  """
  @spec current_commit_short(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def current_commit_short(path) do
    with {:ok, repo_path} <- detect_repo(path) do
      case run_git_command(repo_path, ["rev-parse", "--short", "HEAD"]) do
        {:ok, sha} -> {:ok, String.trim(sha)}
        {:error, _} -> {:error, :no_commit}
      end
    end
  end

  @doc """
  Gets tags pointing at the current commit (HEAD).

  Returns an empty list if no tags point at HEAD.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, tags} = Git.commit_tags(".")
      iex> is_list(tags)
      true
  """
  @spec commit_tags(String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def commit_tags(path) do
    with {:ok, repo_path} <- detect_repo(path) do
      case run_git_command(repo_path, ["tag", "--points-at", "HEAD"]) do
        {:ok, output} ->
          tags =
            output
            |> String.trim()
            |> String.split("\n", trim: true)

          {:ok, tags}

        {:error, _} ->
          {:ok, []}
      end
    end
  end

  @doc """
  Gets the current commit message (subject line only).

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, message} = Git.commit_message(".")
      iex> is_binary(message)
      true
  """
  @spec commit_message(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def commit_message(path) do
    with {:ok, repo_path} <- detect_repo(path) do
      case run_git_command(repo_path, ["log", "-1", "--format=%s", "HEAD"]) do
        {:ok, message} -> {:ok, String.trim(message)}
        {:error, _} -> {:error, :no_commit}
      end
    end
  end

  @doc """
  Gets the full commit message (subject + body).

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, message} = Git.commit_message_full(".")
      iex> is_binary(message)
      true
  """
  @spec commit_message_full(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def commit_message_full(path) do
    with {:ok, repo_path} <- detect_repo(path) do
      case run_git_command(repo_path, ["log", "-1", "--format=%B", "HEAD"]) do
        {:ok, message} -> {:ok, String.trim(message)}
        {:error, _} -> {:error, :no_commit}
      end
    end
  end

  @doc """
  Creates a CommitRef struct with full commit metadata.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, commit} = Git.commit_ref(".")
      iex> %ElixirOntologies.Analyzer.Git.CommitRef{} = commit
      iex> String.length(commit.sha)
      40
  """
  @spec commit_ref(String.t()) :: {:ok, CommitRef.t()} | {:error, atom()}
  def commit_ref(path) do
    with {:ok, repo_path} <- detect_repo(path),
         {:ok, sha} <- current_commit(repo_path),
         {:ok, short_sha} <- current_commit_short(repo_path) do
      message =
        case commit_message(repo_path) do
          {:ok, msg} -> msg
          {:error, _} -> nil
        end

      tags =
        case commit_tags(repo_path) do
          {:ok, t} -> t
          {:error, _} -> []
        end

      {timestamp, author} = get_commit_metadata(repo_path)

      {:ok,
       %CommitRef{
         sha: sha,
         short_sha: short_sha,
         message: message,
         tags: tags,
         timestamp: timestamp,
         author: author
       }}
    end
  end

  @doc """
  Gets the last commit SHA that modified a specific file.

  Validates that the file path is within the repository before executing
  the git command to prevent information leakage about files outside the repo.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, sha} = Git.file_commit(".", "mix.exs")
      iex> String.length(sha)
      40

      iex> alias ElixirOntologies.Analyzer.Git
      iex> Git.file_commit(".", "/etc/passwd")
      {:error, :outside_repo}
  """
  @spec file_commit(String.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def file_commit(path, file_path) do
    with {:ok, repo_path} <- detect_repo(path),
         {:ok, relative_path} <- relative_to_repo(file_path, repo_path) do
      case run_git_command(repo_path, ["log", "-1", "--format=%H", "--", relative_path]) do
        {:ok, sha} ->
          trimmed = String.trim(sha)

          if trimmed == "" do
            {:error, :file_not_tracked}
          else
            {:ok, trimmed}
          end

        {:error, _} ->
          {:error, :file_not_tracked}
      end
    end
  end

  # ===========================================================================
  # Full Repository Info
  # ===========================================================================

  @doc """
  Creates a Repository struct with full metadata for a path.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, repo} = Git.repository(".")
      iex> %ElixirOntologies.Analyzer.Git.Repository{} = repo
      iex> is_binary(repo.path)
      true
  """
  @spec repository(String.t()) :: {:ok, Repository.t()} | {:error, atom()}
  def repository(path) do
    with {:ok, repo_path} <- detect_repo(path) do
      remote = case remote_url(repo_path) do
        {:ok, url} -> url
        {:error, _} -> nil
      end

      parsed = case remote do
        nil -> nil
        url ->
          case parse_remote_url(url) do
            {:ok, p} -> p
            {:error, _} -> nil
          end
      end

      current = case current_branch(repo_path) do
        {:ok, branch} -> branch
        {:error, _} -> nil
      end

      default = case default_branch(repo_path) do
        {:ok, branch} -> branch
        {:error, _} -> nil
      end

      commit = case current_commit(repo_path) do
        {:ok, sha} -> sha
        {:error, _} -> nil
      end

      name = extract_repo_name(parsed, repo_path)

      {:ok,
       %Repository{
         path: repo_path,
         name: name,
         remote_url: remote,
         host: if(parsed, do: parsed.host),
         owner: if(parsed, do: parsed.owner),
         current_branch: current,
         default_branch: default,
         current_commit: commit,
         metadata: %{
           has_remote: remote != nil,
           protocol: if(parsed, do: parsed.protocol)
         }
       }}
    end
  end

  @doc """
  Creates a Repository struct, raising on error.
  """
  @spec repository!(String.t()) :: Repository.t()
  def repository!(path) do
    case repository(path) do
      {:ok, repo} -> repo
      {:error, reason} -> raise "Failed to get repository info: #{inspect(reason)}"
    end
  end

  @doc """
  Checks if a path is within a git repository.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> Git.git_repo?(".")
      true

      iex> alias ElixirOntologies.Analyzer.Git
      iex> Git.git_repo?("/tmp")
      false
  """
  @spec git_repo?(String.t()) :: boolean()
  def git_repo?(path) do
    case detect_repo(path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # ===========================================================================
  # Path Utilities
  # ===========================================================================

  @doc """
  Converts an absolute file path to a path relative to the repository root.

  ## Parameters

  - `file_path` - The file path (absolute or relative)
  - `repo_path` - The repository root path

  ## Returns

  - `{:ok, relative_path}` - The path relative to repo root
  - `{:error, :outside_repo}` - If file is outside the repository
  - `{:error, :invalid_path}` - If path doesn't exist

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, repo_path} = Git.detect_repo(".")
      iex> {:ok, rel} = Git.relative_to_repo("mix.exs", repo_path)
      iex> rel
      "mix.exs"

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, repo_path} = Git.detect_repo(".")
      iex> abs_path = Path.join(repo_path, "lib/elixir_ontologies.ex")
      iex> {:ok, rel} = Git.relative_to_repo(abs_path, repo_path)
      iex> rel
      "lib/elixir_ontologies.ex"
  """
  @spec relative_to_repo(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :outside_repo | :invalid_path}
  def relative_to_repo(file_path, repo_path) do
    expanded_file = Path.expand(file_path)
    expanded_repo = Path.expand(repo_path)
    # Ensure repo path ends with separator for proper prefix matching
    repo_prefix = ensure_trailing_separator(expanded_repo)

    cond do
      # File path is exactly the repo root
      expanded_file == expanded_repo ->
        {:ok, "."}

      # File is within repo
      String.starts_with?(expanded_file, repo_prefix) ->
        relative = String.trim_leading(expanded_file, repo_prefix)
        {:ok, normalize_path(relative)}

      # File might be a relative path already
      Path.type(file_path) != :absolute ->
        # Check if resolving relative to repo puts it inside
        resolved = Path.join(expanded_repo, file_path) |> Path.expand()

        if String.starts_with?(resolved, repo_prefix) or resolved == expanded_repo do
          {:ok, normalize_path(file_path)}
        else
          {:error, :outside_repo}
        end

      true ->
        {:error, :outside_repo}
    end
  end

  @doc """
  Checks if a file path is within the repository.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, repo_path} = Git.detect_repo(".")
      iex> Git.file_in_repo?("mix.exs", repo_path)
      true

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, repo_path} = Git.detect_repo(".")
      iex> Git.file_in_repo?("/etc/passwd", repo_path)
      false
  """
  @spec file_in_repo?(String.t(), String.t()) :: boolean()
  def file_in_repo?(file_path, repo_path) do
    case relative_to_repo(file_path, repo_path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Normalizes a file path for consistent representation.

  - Converts backslashes to forward slashes (Windows compatibility)
  - Removes redundant separators
  - Resolves `.` components (but preserves leading `./`)

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> Git.normalize_path("lib//foo.ex")
      "lib/foo.ex"

      iex> alias ElixirOntologies.Analyzer.Git
      iex> Git.normalize_path("lib/./foo.ex")
      "lib/foo.ex"

      iex> alias ElixirOntologies.Analyzer.Git
      iex> Git.normalize_path("lib\\\\foo.ex")
      "lib/foo.ex"
  """
  @spec normalize_path(String.t()) :: String.t()
  def normalize_path(path) when is_binary(path) do
    path
    # Convert Windows backslashes to forward slashes
    |> String.replace("\\", "/")
    # Collapse multiple slashes
    |> String.replace(~r{/+}, "/")
    # Remove trailing slash (unless root)
    |> String.trim_trailing("/")
    # Remove ./ in middle of path
    |> String.replace(~r{/\./}, "/")
    # Handle leading ./
    |> normalize_leading_dot()
  end

  @doc """
  Creates a SourceFile struct linking a file to its repository.

  ## Parameters

  - `file_path` - Path to the source file
  - `repo_path` - Path to the repository root

  ## Returns

  - `{:ok, source_file}` - SourceFile struct with paths and commit info
  - `{:error, reason}` - If file cannot be linked

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, repo_path} = Git.detect_repo(".")
      iex> {:ok, sf} = Git.source_file("mix.exs", repo_path)
      iex> sf.relative_path
      "mix.exs"
      iex> is_binary(sf.absolute_path)
      true
  """
  @spec source_file(String.t(), String.t()) :: {:ok, SourceFile.t()} | {:error, atom()}
  def source_file(file_path, repo_path) do
    with {:ok, relative} <- relative_to_repo(file_path, repo_path) do
      absolute = Path.expand(file_path, repo_path)

      last_commit =
        case file_commit(repo_path, relative) do
          {:ok, sha} -> sha
          {:error, _} -> nil
        end

      {:ok,
       %SourceFile{
         absolute_path: absolute,
         relative_path: relative,
         repository_path: Path.expand(repo_path),
         last_commit: last_commit
       }}
    end
  end

  @doc """
  Creates a SourceFile struct from a path, automatically detecting the repository.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, sf} = Git.source_file("mix.exs")
      iex> sf.relative_path
      "mix.exs"
  """
  @spec source_file(String.t()) :: {:ok, SourceFile.t()} | {:error, atom()}
  def source_file(file_path) do
    with {:ok, repo_path} <- detect_repo(file_path) do
      source_file(file_path, repo_path)
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp find_git_root(path) do
    git_path = Path.join(path, ".git")

    cond do
      File.dir?(git_path) ->
        {:ok, path}

      path == "/" or path == Path.dirname(path) ->
        {:error, :not_found}

      true ->
        find_git_root(Path.dirname(path))
    end
  end

  defp run_git_command(repo_path, args) do
    case System.cmd("git", args, cd: repo_path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {_output, _code} -> {:error, :command_failed}
    end
  end

  defp parse_https_url(url) do
    # https://github.com/owner/repo.git
    regex = ~r{^https://([^/]+)/([^/]+)/([^/]+?)(?:\.git)?$}

    case Regex.run(regex, url) do
      [_, host, owner, repo] ->
        {:ok, %ParsedUrl{host: host, owner: owner, repo: repo, protocol: :https}}

      nil ->
        {:error, :invalid_url}
    end
  end

  defp parse_ssh_url(url) do
    # ssh://git@github.com/owner/repo.git
    regex = ~r{^ssh://(?:[^@]+@)?([^/]+)/([^/]+)/([^/]+?)(?:\.git)?$}

    case Regex.run(regex, url) do
      [_, host, owner, repo] ->
        {:ok, %ParsedUrl{host: host, owner: owner, repo: repo, protocol: :ssh}}

      nil ->
        {:error, :invalid_url}
    end
  end

  defp parse_git_at_url(url) do
    # git@github.com:owner/repo.git
    regex = ~r{^git@([^:]+):([^/]+)/([^/]+?)(?:\.git)?$}

    case Regex.run(regex, url) do
      [_, host, owner, repo] ->
        {:ok, %ParsedUrl{host: host, owner: owner, repo: repo, protocol: :ssh}}

      nil ->
        {:error, :invalid_url}
    end
  end

  defp parse_git_protocol_url(url) do
    # git://github.com/owner/repo.git
    regex = ~r{^git://([^/]+)/([^/]+)/([^/]+?)(?:\.git)?$}

    case Regex.run(regex, url) do
      [_, host, owner, repo] ->
        {:ok, %ParsedUrl{host: host, owner: owner, repo: repo, protocol: :git}}

      nil ->
        {:error, :invalid_url}
    end
  end

  defp find_default_branch(repo_path) do
    # Check if main exists
    case run_git_command(repo_path, ["show-ref", "--verify", "--quiet", "refs/heads/main"]) do
      {:ok, _} ->
        {:ok, "main"}

      {:error, _} ->
        # Check if master exists
        case run_git_command(repo_path, ["show-ref", "--verify", "--quiet", "refs/heads/master"]) do
          {:ok, _} -> {:ok, "master"}
          {:error, _} -> {:error, :no_default_branch}
        end
    end
  end

  defp extract_repo_name(nil, repo_path) do
    # No remote, use directory name
    Path.basename(repo_path)
  end

  defp extract_repo_name(%ParsedUrl{repo: repo}, _repo_path) do
    repo
  end

  defp ensure_trailing_separator(path) do
    if String.ends_with?(path, "/") do
      path
    else
      path <> "/"
    end
  end

  defp normalize_leading_dot(path) do
    case path do
      "./" <> rest -> rest
      other -> other
    end
  end

  defp get_commit_metadata(repo_path) do
    timestamp =
      case run_git_command(repo_path, ["log", "-1", "--format=%aI", "HEAD"]) do
        {:ok, date_str} ->
          date_str
          |> String.trim()
          |> DateTime.from_iso8601()
          |> case do
            {:ok, dt, _offset} -> dt
            _ -> nil
          end

        {:error, _} ->
          nil
      end

    author =
      case run_git_command(repo_path, ["log", "-1", "--format=%an", "HEAD"]) do
        {:ok, name} -> String.trim(name)
        {:error, _} -> nil
      end

    {timestamp, author}
  end
end
