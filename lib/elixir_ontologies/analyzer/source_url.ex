defmodule ElixirOntologies.Analyzer.SourceUrl do
  @moduledoc """
  Generates source URLs (permalinks) for code elements.

  This module creates platform-specific URLs for files, lines, and line ranges
  in Git hosting platforms like GitHub, GitLab, and Bitbucket.

  ## Usage

      iex> alias ElixirOntologies.Analyzer.SourceUrl
      iex> SourceUrl.for_file(:github, "owner", "repo", "abc123", "lib/foo.ex")
      "https://github.com/owner/repo/blob/abc123/lib/foo.ex"

  ## Supported Platforms

  - `:github` - GitHub.com and GitHub Enterprise
  - `:gitlab` - GitLab.com and self-hosted GitLab
  - `:bitbucket` - Bitbucket.org and Bitbucket Server
  """

  alias ElixirOntologies.Analyzer.Git.Repository

  @type platform :: :github | :gitlab | :bitbucket | :unknown
  @type line_number :: pos_integer()

  # Maximum allowed line number to prevent absurd values
  @max_line_number 1_000_000

  # Valid characters for URL segments (owner, repo, commit)
  # Allows alphanumeric, dash, underscore, dot (common in git hosting)
  @valid_segment_regex ~r/^[a-zA-Z0-9._-]+$/

  # ===========================================================================
  # Platform Detection
  # ===========================================================================

  @doc """
  Detects the hosting platform from a hostname.

  Uses strict domain suffix matching to prevent misclassification of
  similar-looking domains (e.g., "my-github-clone.com" won't match GitHub).

  ## Examples

      iex> SourceUrl.detect_platform("github.com")
      :github

      iex> SourceUrl.detect_platform("gitlab.com")
      :gitlab

      iex> SourceUrl.detect_platform("bitbucket.org")
      :bitbucket

      iex> SourceUrl.detect_platform("git.example.com")
      :unknown

      iex> SourceUrl.detect_platform("my-github-clone.com")
      :unknown
  """
  @spec detect_platform(String.t()) :: platform()
  def detect_platform(host) when is_binary(host) do
    host_lower = String.downcase(host)

    # First check custom platforms from config
    case custom_platform_match(host_lower) do
      {:ok, platform} ->
        platform

      :no_match ->
        cond do
          github_host?(host_lower) -> :github
          gitlab_host?(host_lower) -> :gitlab
          bitbucket_host?(host_lower) -> :bitbucket
          true -> :unknown
        end
    end
  end

  def detect_platform(_), do: :unknown

  # Strict domain matching for GitHub
  defp github_host?(host) do
    host == "github.com" or String.ends_with?(host, ".github.com") or
      String.ends_with?(host, ".github.io")
  end

  # Strict domain matching for GitLab
  defp gitlab_host?(host) do
    host == "gitlab.com" or String.ends_with?(host, ".gitlab.com") or
      String.ends_with?(host, ".gitlab.io")
  end

  # Strict domain matching for Bitbucket
  defp bitbucket_host?(host) do
    host == "bitbucket.org" or String.ends_with?(host, ".bitbucket.org") or
      String.ends_with?(host, ".bitbucket.io")
  end

  # Check custom platform configuration
  defp custom_platform_match(host) do
    custom_platforms = get_custom_platforms()

    Enum.find_value(custom_platforms, :no_match, fn config ->
      cond do
        # Match by exact host
        is_binary(config[:host]) and host == config[:host] ->
          {:ok, config[:platform]}

        # Match by regex pattern
        is_struct(config[:host_pattern], Regex) and Regex.match?(config[:host_pattern], host) ->
          {:ok, config[:platform]}

        # Match by suffix
        is_binary(config[:host_suffix]) and String.ends_with?(host, config[:host_suffix]) ->
          {:ok, config[:platform]}

        true ->
          nil
      end
    end)
  end

  @doc """
  Returns the configured custom git platforms.

  ## Configuration

  Custom platforms can be configured in your application config:

      config :elixir_ontologies, SourceUrl,
        custom_platforms: [
          %{host: "git.mycompany.com", platform: :github},
          %{host_pattern: ~r/^github\\.mycompany\\.com$/, platform: :github},
          %{host_suffix: ".git.internal", platform: :gitlab}
        ]

  Each entry must have:
  - `:platform` - One of `:github`, `:gitlab`, `:bitbucket`
  - One of:
    - `:host` - Exact hostname to match
    - `:host_pattern` - Regex to match against hostname
    - `:host_suffix` - Suffix to match (e.g., ".github.mycompany.com")
  """
  @spec get_custom_platforms() :: [map()]
  def get_custom_platforms do
    Application.get_env(:elixir_ontologies, __MODULE__, [])[:custom_platforms] || []
  end

  @doc """
  Detects the platform from a Repository struct.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git
      iex> {:ok, repo} = Git.repository(".")
      iex> platform = SourceUrl.platform_from_repo(repo)
      iex> platform in [:github, :gitlab, :bitbucket, :unknown]
      true
  """
  @spec platform_from_repo(Repository.t()) :: platform()
  def platform_from_repo(%Repository{host: host}) when is_binary(host) do
    detect_platform(host)
  end

  def platform_from_repo(_), do: :unknown

  # ===========================================================================
  # URL Generation - File
  # ===========================================================================

  @doc """
  Generates a URL for a file at a specific commit.

  ## Parameters

  - `platform` - The hosting platform (`:github`, `:gitlab`, `:bitbucket`)
  - `owner` - Repository owner/organization
  - `repo` - Repository name
  - `commit` - Commit SHA or branch name
  - `path` - File path relative to repository root

  ## Examples

      iex> SourceUrl.for_file(:github, "elixir-lang", "elixir", "abc123", "lib/elixir.ex")
      "https://github.com/elixir-lang/elixir/blob/abc123/lib/elixir.ex"

      iex> SourceUrl.for_file(:gitlab, "owner", "repo", "main", "src/app.ex")
      "https://gitlab.com/owner/repo/-/blob/main/src/app.ex"

      iex> SourceUrl.for_file(:bitbucket, "team", "project", "abc123", "lib/mod.ex")
      "https://bitbucket.org/team/project/src/abc123/lib/mod.ex"

      iex> SourceUrl.for_file(:unknown, "owner", "repo", "sha", "file.ex")
      nil

      # Invalid segments return nil
      iex> SourceUrl.for_file(:github, "evil/../other", "repo", "sha", "file.ex")
      nil
  """
  @spec for_file(platform(), String.t(), String.t(), String.t(), String.t()) :: String.t() | nil
  def for_file(platform, owner, repo, commit, path) do
    with :ok <- validate_url_segment(owner),
         :ok <- validate_url_segment(repo),
         :ok <- validate_url_segment(commit) do
      case platform do
        :github ->
          "https://github.com/#{owner}/#{repo}/blob/#{commit}/#{normalize_path(path)}"

        :gitlab ->
          "https://gitlab.com/#{owner}/#{repo}/-/blob/#{commit}/#{normalize_path(path)}"

        :bitbucket ->
          "https://bitbucket.org/#{owner}/#{repo}/src/#{commit}/#{normalize_path(path)}"

        :unknown ->
          nil
      end
    else
      :error -> nil
    end
  end

  @doc """
  Generates a URL for a file using a Repository struct.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git.Repository
      iex> repo = %Repository{host: "github.com", owner: "owner", name: "repo", current_commit: "abc123"}
      iex> SourceUrl.for_file(repo, "lib/foo.ex")
      "https://github.com/owner/repo/blob/abc123/lib/foo.ex"
  """
  @spec for_file(Repository.t(), String.t()) :: String.t() | nil
  def for_file(%Repository{} = repo, path) do
    with {:ok, platform} <- get_platform(repo),
         {:ok, owner} <- get_owner(repo),
         {:ok, name} <- get_name(repo),
         {:ok, commit} <- get_commit(repo) do
      for_file(platform, owner, name, commit, path)
    else
      _ -> nil
    end
  end

  # ===========================================================================
  # URL Generation - Line
  # ===========================================================================

  @doc """
  Generates a URL for a specific line in a file.

  ## Examples

      iex> SourceUrl.for_line(:github, "owner", "repo", "abc123", "lib/foo.ex", 42)
      "https://github.com/owner/repo/blob/abc123/lib/foo.ex#L42"

      iex> SourceUrl.for_line(:gitlab, "owner", "repo", "main", "src/app.ex", 10)
      "https://gitlab.com/owner/repo/-/blob/main/src/app.ex#L10"

      iex> SourceUrl.for_line(:bitbucket, "team", "project", "abc123", "lib/mod.ex", 5)
      "https://bitbucket.org/team/project/src/abc123/lib/mod.ex#lines-5"

      iex> SourceUrl.for_line(:unknown, "owner", "repo", "sha", "file.ex", 1)
      nil
  """
  @spec for_line(platform(), String.t(), String.t(), String.t(), String.t(), line_number()) ::
          String.t() | nil
  def for_line(platform, owner, repo, commit, path, line)
      when is_integer(line) and line > 0 and line <= @max_line_number do
    with :ok <- validate_url_segment(owner),
         :ok <- validate_url_segment(repo),
         :ok <- validate_url_segment(commit) do
      case platform do
        :github ->
          "https://github.com/#{owner}/#{repo}/blob/#{commit}/#{normalize_path(path)}#L#{line}"

        :gitlab ->
          "https://gitlab.com/#{owner}/#{repo}/-/blob/#{commit}/#{normalize_path(path)}#L#{line}"

        :bitbucket ->
          "https://bitbucket.org/#{owner}/#{repo}/src/#{commit}/#{normalize_path(path)}#lines-#{line}"

        :unknown ->
          nil
      end
    else
      :error -> nil
    end
  end

  # Catch-all for invalid line numbers (returns nil instead of raising)
  def for_line(_platform, _owner, _repo, _commit, _path, _line), do: nil

  @doc """
  Generates a URL for a line using a Repository struct.

  Returns `nil` if the repository is missing required metadata (host, owner,
  name, or current_commit) or if the platform cannot be determined.

  ## Parameters

  - `repo` - Repository struct with git metadata
  - `path` - File path relative to repository root
  - `line` - Line number (must be between 1 and 1,000,000)

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git.Repository
      iex> repo = %Repository{host: "github.com", owner: "owner", name: "repo", current_commit: "abc123"}
      iex> SourceUrl.for_line(repo, "lib/foo.ex", 42)
      "https://github.com/owner/repo/blob/abc123/lib/foo.ex#L42"
  """
  @spec for_line(Repository.t(), String.t(), line_number()) :: String.t() | nil
  def for_line(%Repository{} = repo, path, line) do
    with {:ok, platform} <- get_platform(repo),
         {:ok, owner} <- get_owner(repo),
         {:ok, name} <- get_name(repo),
         {:ok, commit} <- get_commit(repo) do
      for_line(platform, owner, name, commit, path, line)
    else
      _ -> nil
    end
  end

  # ===========================================================================
  # URL Generation - Range
  # ===========================================================================

  @doc """
  Generates a URL for a line range in a file.

  ## Examples

      iex> SourceUrl.for_range(:github, "owner", "repo", "abc123", "lib/foo.ex", 10, 20)
      "https://github.com/owner/repo/blob/abc123/lib/foo.ex#L10-L20"

      iex> SourceUrl.for_range(:gitlab, "owner", "repo", "main", "src/app.ex", 5, 15)
      "https://gitlab.com/owner/repo/-/blob/main/src/app.ex#L5-15"

      iex> SourceUrl.for_range(:bitbucket, "team", "project", "abc123", "lib/mod.ex", 1, 10)
      "https://bitbucket.org/team/project/src/abc123/lib/mod.ex#lines-1:10"

      iex> SourceUrl.for_range(:unknown, "owner", "repo", "sha", "file.ex", 1, 5)
      nil
  """
  @spec for_range(
          platform(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          line_number(),
          line_number()
        ) :: String.t() | nil
  def for_range(platform, owner, repo, commit, path, start_line, end_line)
      when is_integer(start_line) and is_integer(end_line) and
             start_line > 0 and end_line > 0 and
             start_line <= end_line and end_line <= @max_line_number do
    with :ok <- validate_url_segment(owner),
         :ok <- validate_url_segment(repo),
         :ok <- validate_url_segment(commit) do
      case platform do
        :github ->
          "https://github.com/#{owner}/#{repo}/blob/#{commit}/#{normalize_path(path)}#L#{start_line}-L#{end_line}"

        :gitlab ->
          "https://gitlab.com/#{owner}/#{repo}/-/blob/#{commit}/#{normalize_path(path)}#L#{start_line}-#{end_line}"

        :bitbucket ->
          "https://bitbucket.org/#{owner}/#{repo}/src/#{commit}/#{normalize_path(path)}#lines-#{start_line}:#{end_line}"

        :unknown ->
          nil
      end
    else
      :error -> nil
    end
  end

  # Catch-all for invalid line ranges (returns nil instead of raising)
  def for_range(_platform, _owner, _repo, _commit, _path, _start_line, _end_line), do: nil

  @doc """
  Generates a URL for a line range using a Repository struct.

  Returns `nil` if the repository is missing required metadata (host, owner,
  name, or current_commit), if the platform cannot be determined, or if the
  line range is invalid (start > end or exceeds 1,000,000).

  ## Parameters

  - `repo` - Repository struct with git metadata
  - `path` - File path relative to repository root
  - `start_line` - Start line number (must be >= 1)
  - `end_line` - End line number (must be >= start_line and <= 1,000,000)

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git.Repository
      iex> repo = %Repository{host: "github.com", owner: "owner", name: "repo", current_commit: "abc123"}
      iex> SourceUrl.for_range(repo, "lib/foo.ex", 10, 20)
      "https://github.com/owner/repo/blob/abc123/lib/foo.ex#L10-L20"
  """
  @spec for_range(Repository.t(), String.t(), line_number(), line_number()) :: String.t() | nil
  def for_range(%Repository{} = repo, path, start_line, end_line) do
    with {:ok, platform} <- get_platform(repo),
         {:ok, owner} <- get_owner(repo),
         {:ok, name} <- get_name(repo),
         {:ok, commit} <- get_commit(repo) do
      for_range(platform, owner, name, commit, path, start_line, end_line)
    else
      _ -> nil
    end
  end

  # ===========================================================================
  # Error Tuple Variants
  # ===========================================================================

  @doc """
  Generates a URL for a file, returning an error tuple on failure.

  ## Examples

      iex> SourceUrl.for_file_result(:github, "owner", "repo", "abc123", "lib/foo.ex")
      {:ok, "https://github.com/owner/repo/blob/abc123/lib/foo.ex"}

      iex> SourceUrl.for_file_result(:unknown, "owner", "repo", "sha", "file.ex")
      {:error, :unsupported_platform}

      iex> SourceUrl.for_file_result(:github, "../evil", "repo", "sha", "file.ex")
      {:error, :invalid_segment}
  """
  @spec for_file_result(platform(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def for_file_result(platform, owner, repo, commit, path) do
    case for_file(platform, owner, repo, commit, path) do
      nil ->
        cond do
          platform == :unknown -> {:error, :unsupported_platform}
          not valid_segment?(owner) -> {:error, :invalid_segment}
          not valid_segment?(repo) -> {:error, :invalid_segment}
          not valid_segment?(commit) -> {:error, :invalid_segment}
          true -> {:error, :url_generation_failed}
        end

      url ->
        {:ok, url}
    end
  end

  @doc """
  Generates a URL for a line, returning an error tuple on failure.

  ## Examples

      iex> SourceUrl.for_line_result(:github, "owner", "repo", "sha", "file.ex", 42)
      {:ok, "https://github.com/owner/repo/blob/sha/file.ex#L42"}

      iex> SourceUrl.for_line_result(:github, "owner", "repo", "sha", "file.ex", 0)
      {:error, :invalid_line_number}
  """
  @spec for_line_result(platform(), String.t(), String.t(), String.t(), String.t(), line_number()) ::
          {:ok, String.t()} | {:error, atom()}
  def for_line_result(platform, owner, repo, commit, path, line) do
    case for_line(platform, owner, repo, commit, path, line) do
      nil ->
        cond do
          platform == :unknown -> {:error, :unsupported_platform}
          not valid_segment?(owner) -> {:error, :invalid_segment}
          not valid_segment?(repo) -> {:error, :invalid_segment}
          not valid_segment?(commit) -> {:error, :invalid_segment}
          not valid_line?(line) -> {:error, :invalid_line_number}
          true -> {:error, :url_generation_failed}
        end

      url ->
        {:ok, url}
    end
  end

  @doc """
  Generates a URL for a line range, returning an error tuple on failure.

  ## Examples

      iex> SourceUrl.for_range_result(:github, "owner", "repo", "sha", "file.ex", 10, 20)
      {:ok, "https://github.com/owner/repo/blob/sha/file.ex#L10-L20"}

      iex> SourceUrl.for_range_result(:github, "owner", "repo", "sha", "file.ex", 20, 10)
      {:error, :invalid_line_range}
  """
  @spec for_range_result(
          platform(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          line_number(),
          line_number()
        ) :: {:ok, String.t()} | {:error, atom()}
  def for_range_result(platform, owner, repo, commit, path, start_line, end_line) do
    case for_range(platform, owner, repo, commit, path, start_line, end_line) do
      nil ->
        cond do
          platform == :unknown -> {:error, :unsupported_platform}
          not valid_segment?(owner) -> {:error, :invalid_segment}
          not valid_segment?(repo) -> {:error, :invalid_segment}
          not valid_segment?(commit) -> {:error, :invalid_segment}
          not valid_line_range?(start_line, end_line) -> {:error, :invalid_line_range}
          true -> {:error, :url_generation_failed}
        end

      url ->
        {:ok, url}
    end
  end

  # ===========================================================================
  # Bang Variants
  # ===========================================================================

  @doc """
  Generates a URL for a file, raising on failure.

  ## Examples

      iex> SourceUrl.for_file!(:github, "owner", "repo", "abc123", "lib/foo.ex")
      "https://github.com/owner/repo/blob/abc123/lib/foo.ex"
  """
  @spec for_file!(platform(), String.t(), String.t(), String.t(), String.t()) :: String.t()
  def for_file!(platform, owner, repo, commit, path) do
    case for_file_result(platform, owner, repo, commit, path) do
      {:ok, url} -> url
      {:error, reason} -> raise "Failed to generate file URL: #{inspect(reason)}"
    end
  end

  @doc """
  Generates a URL for a line, raising on failure.

  ## Examples

      iex> SourceUrl.for_line!(:github, "owner", "repo", "sha", "file.ex", 42)
      "https://github.com/owner/repo/blob/sha/file.ex#L42"
  """
  @spec for_line!(platform(), String.t(), String.t(), String.t(), String.t(), line_number()) ::
          String.t()
  def for_line!(platform, owner, repo, commit, path, line) do
    case for_line_result(platform, owner, repo, commit, path, line) do
      {:ok, url} -> url
      {:error, reason} -> raise "Failed to generate line URL: #{inspect(reason)}"
    end
  end

  @doc """
  Generates a URL for a line range, raising on failure.

  ## Examples

      iex> SourceUrl.for_range!(:github, "owner", "repo", "sha", "file.ex", 10, 20)
      "https://github.com/owner/repo/blob/sha/file.ex#L10-L20"
  """
  @spec for_range!(
          platform(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          line_number(),
          line_number()
        ) :: String.t()
  def for_range!(platform, owner, repo, commit, path, start_line, end_line) do
    case for_range_result(platform, owner, repo, commit, path, start_line, end_line) do
      {:ok, url} -> url
      {:error, reason} -> raise "Failed to generate range URL: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Convenience Functions
  # ===========================================================================

  @doc """
  Generates a URL for a file/line from a path in the current repository.

  Automatically detects the repository and generates the appropriate URL.

  ## Examples

      iex> {:ok, url} = SourceUrl.url_for_path("lib/elixir_ontologies.ex", line: 10)
      iex> is_binary(url)
      true
  """
  @spec url_for_path(String.t(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def url_for_path(file_path, opts \\ []) do
    alias ElixirOntologies.Analyzer.Git

    with {:ok, repo} <- Git.repository("."),
         {:ok, repo_root} <- Git.detect_repo(".") do
      relative_path = make_relative_path(file_path, repo_root)

      url =
        case {Keyword.get(opts, :line), Keyword.get(opts, :end_line)} do
          {nil, nil} ->
            for_file(repo, relative_path)

          {line, nil} when is_integer(line) ->
            for_line(repo, relative_path, line)

          {start_line, end_line} when is_integer(start_line) and is_integer(end_line) ->
            for_range(repo, relative_path, start_line, end_line)

          _ ->
            nil
        end

      case url do
        nil -> {:error, :url_generation_failed}
        url -> {:ok, url}
      end
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp normalize_path(path) do
    path
    |> String.trim_leading("/")
    |> String.trim_leading("./")
    |> remove_path_traversal()
    |> collapse_slashes()
    |> encode_path_segments()
  end

  # Remove path traversal sequences (.. and variations)
  defp remove_path_traversal(path) do
    path
    |> String.replace(~r/\.\.+/, "")
    |> String.replace(~r/(^|\/)\.\.($|\/)/, "/")
  end

  # Collapse multiple consecutive slashes into single slash
  defp collapse_slashes(path) do
    String.replace(path, ~r/\/+/, "/")
  end

  # Encode path segments while preserving slashes
  defp encode_path_segments(path) do
    path
    |> String.split("/")
    |> Enum.map_join("/", &URI.encode_www_form/1)
  end

  defp get_platform(%Repository{host: host}) when is_binary(host) do
    case detect_platform(host) do
      :unknown -> {:error, :unknown_platform}
      platform -> {:ok, platform}
    end
  end

  defp get_platform(_), do: {:error, :no_host}

  defp get_owner(%Repository{owner: owner}) when is_binary(owner), do: {:ok, owner}
  defp get_owner(_), do: {:error, :no_owner}

  defp get_name(%Repository{name: name}) when is_binary(name), do: {:ok, name}
  defp get_name(_), do: {:error, :no_name}

  defp get_commit(%Repository{current_commit: commit}) when is_binary(commit), do: {:ok, commit}
  defp get_commit(_), do: {:error, :no_commit}

  # Validates URL segments to prevent path injection attacks
  defp validate_url_segment(segment) when is_binary(segment) do
    if String.match?(segment, @valid_segment_regex) do
      :ok
    else
      :error
    end
  end

  defp validate_url_segment(_), do: :error

  # Boolean validation helpers for error tuple functions
  defp valid_segment?(segment) when is_binary(segment) do
    String.match?(segment, @valid_segment_regex)
  end

  defp valid_segment?(_), do: false

  defp valid_line?(line) when is_integer(line) do
    line > 0 and line <= @max_line_number
  end

  defp valid_line?(_), do: false

  defp valid_line_range?(start_line, end_line)
       when is_integer(start_line) and is_integer(end_line) do
    start_line > 0 and end_line > 0 and start_line <= end_line and end_line <= @max_line_number
  end

  defp valid_line_range?(_, _), do: false

  defp make_relative_path(file_path, repo_root) do
    expanded = Path.expand(file_path)
    expanded_root = Path.expand(repo_root)

    if String.starts_with?(expanded, expanded_root) do
      String.trim_leading(expanded, expanded_root <> "/")
    else
      # Already relative or outside repo
      file_path
    end
  end
end
