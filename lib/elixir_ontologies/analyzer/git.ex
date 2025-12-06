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
      metadata: %{}
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
end
