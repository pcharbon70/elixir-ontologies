defmodule ElixirOntologies.Extractors.Evolution.Release do
  @moduledoc """
  Extracts release information from git tags and mix.exs versions.

  This module provides functions to extract formal release points from
  git repositories, including:

  - Git tags as release markers
  - Version information from mix.exs
  - Semantic version parsing
  - Release progression tracking

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.Release

      # Extract all releases from repository
      {:ok, releases} = Release.extract_releases(".")

      # Extract specific release by tag
      {:ok, release} = Release.extract_release(".", "v1.0.0")

      # Get current version from mix.exs
      {:ok, version} = Release.extract_current_version(".")

      # Parse semantic version
      {:ok, semver} = Release.parse_semver("1.2.3-alpha.1+build.456")

  ## Semantic Versioning

  This module follows the Semantic Versioning 2.0.0 specification (https://semver.org/).
  Versions are parsed into major, minor, patch, pre-release, and build components.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> {:ok, semver} = Release.parse_semver("1.2.3")
      iex> semver.major
      1
  """

  alias ElixirOntologies.Analyzer.Git
  alias ElixirOntologies.Extractors.Evolution.{Commit, GitUtils}

  # ===========================================================================
  # Release Struct
  # ===========================================================================

  @typedoc """
  Represents a release with version and tag information.

  ## Fields

  - `:release_id` - Unique identifier (e.g., "release:v1.2.3")
  - `:version` - Version string (e.g., "1.2.3")
  - `:tag` - Git tag name if from a tag (may be nil)
  - `:commit_sha` - Full 40-character SHA hash
  - `:short_sha` - 7-character abbreviated SHA
  - `:timestamp` - Tag/commit timestamp
  - `:semver` - Parsed semantic version components
  - `:previous_version` - Previous release version (may be nil)
  - `:project_name` - Project name from mix.exs
  - `:metadata` - Additional metadata
  """
  @type t :: %__MODULE__{
          release_id: String.t(),
          version: String.t(),
          tag: String.t() | nil,
          commit_sha: String.t(),
          short_sha: String.t(),
          timestamp: DateTime.t() | nil,
          semver: semver() | nil,
          previous_version: String.t() | nil,
          project_name: atom() | nil,
          metadata: map()
        }

  @typedoc """
  Parsed semantic version components.
  """
  @type semver :: %{
          major: non_neg_integer(),
          minor: non_neg_integer(),
          patch: non_neg_integer(),
          pre_release: String.t() | nil,
          build: String.t() | nil
        }

  @enforce_keys [:release_id, :version, :commit_sha, :short_sha]
  defstruct [
    :release_id,
    :version,
    :tag,
    :commit_sha,
    :short_sha,
    :timestamp,
    :semver,
    :previous_version,
    :project_name,
    metadata: %{}
  ]

  # ===========================================================================
  # Semantic Version Parsing
  # ===========================================================================

  # Regex for semantic versioning (based on semver.org)
  # Captures: major.minor.patch[-pre_release][+build]
  @semver_regex ~r/^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)(?:-(?P<pre>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?P<build>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/

  @doc """
  Parses a semantic version string into its components.

  Follows the Semantic Versioning 2.0.0 specification.

  ## Parameters

  - `version` - Version string to parse (with or without "v" prefix)

  ## Returns

  - `{:ok, semver}` - Parsed semantic version map
  - `{:error, :invalid_version}` - Version string is invalid

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> {:ok, semver} = Release.parse_semver("1.2.3")
      iex> {semver.major, semver.minor, semver.patch}
      {1, 2, 3}

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> {:ok, semver} = Release.parse_semver("v2.0.0-alpha.1")
      iex> semver.pre_release
      "alpha.1"

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> {:ok, semver} = Release.parse_semver("1.0.0+build.123")
      iex> semver.build
      "build.123"

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> Release.parse_semver("invalid")
      {:error, :invalid_version}
  """
  @spec parse_semver(String.t()) :: {:ok, semver()} | {:error, :invalid_version}
  def parse_semver(version) when is_binary(version) do
    # Strip optional "v" prefix
    version_str = String.trim_leading(version, "v")

    case Regex.named_captures(@semver_regex, version_str) do
      nil ->
        {:error, :invalid_version}

      captures ->
        semver = %{
          major: String.to_integer(captures["major"]),
          minor: String.to_integer(captures["minor"]),
          patch: String.to_integer(captures["patch"]),
          pre_release: empty_to_nil(captures["pre"]),
          build: empty_to_nil(captures["build"])
        }

        {:ok, semver}
    end
  end

  def parse_semver(_), do: {:error, :invalid_version}

  @doc """
  Compares two semantic version strings.

  Returns:
  - `:lt` if v1 < v2
  - `:eq` if v1 == v2
  - `:gt` if v1 > v2

  Pre-release versions have lower precedence than normal versions.
  Build metadata is ignored in comparison.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> Release.compare_versions("1.0.0", "2.0.0")
      :lt

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> Release.compare_versions("1.0.0", "1.0.0")
      :eq

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> Release.compare_versions("2.0.0", "1.0.0")
      :gt

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> Release.compare_versions("1.0.0-alpha", "1.0.0")
      :lt
  """
  @spec compare_versions(String.t(), String.t()) :: :lt | :eq | :gt
  def compare_versions(v1, v2) do
    with {:ok, s1} <- parse_semver(v1),
         {:ok, s2} <- parse_semver(v2) do
      compare_semver(s1, s2)
    else
      _ -> compare_string_versions(v1, v2)
    end
  end

  defp compare_semver(s1, s2) do
    # Compare major.minor.patch first
    case {s1.major, s2.major} do
      {m1, m2} when m1 < m2 -> :lt
      {m1, m2} when m1 > m2 -> :gt
      _ ->
        case {s1.minor, s2.minor} do
          {m1, m2} when m1 < m2 -> :lt
          {m1, m2} when m1 > m2 -> :gt
          _ ->
            case {s1.patch, s2.patch} do
              {p1, p2} when p1 < p2 -> :lt
              {p1, p2} when p1 > p2 -> :gt
              _ -> compare_pre_release(s1.pre_release, s2.pre_release)
            end
        end
    end
  end

  defp compare_pre_release(nil, nil), do: :eq
  defp compare_pre_release(nil, _), do: :gt  # Release > pre-release
  defp compare_pre_release(_, nil), do: :lt  # Pre-release < release

  defp compare_pre_release(p1, p2) do
    # Simple string comparison for pre-release
    cond do
      p1 < p2 -> :lt
      p1 > p2 -> :gt
      true -> :eq
    end
  end

  defp compare_string_versions(v1, v2) do
    cond do
      v1 < v2 -> :lt
      v1 > v2 -> :gt
      true -> :eq
    end
  end

  # ===========================================================================
  # Tag Extraction
  # ===========================================================================

  @doc """
  Lists all git tags in the repository.

  ## Parameters

  - `path` - Path to the git repository

  ## Returns

  - `{:ok, tags}` - List of tag names
  - `{:error, reason}` - Error occurred

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> {:ok, tags} = Release.list_tags(".")
      iex> is_list(tags)
      true
  """
  @spec list_tags(String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def list_tags(path) do
    with {:ok, repo_path} <- Git.detect_repo(path) do
      args = ["tag", "--list"]

      case GitUtils.run_git_command(repo_path, args) do
        {:ok, output} ->
          tags =
            output
            |> String.split("\n", trim: true)
            |> Enum.map(&String.trim/1)

          {:ok, tags}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Lists tags that look like version numbers.

  Filters for tags matching patterns like "v1.2.3", "1.2.3", "release-1.0", etc.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> {:ok, tags} = Release.list_version_tags(".")
      iex> is_list(tags)
      true
  """
  @spec list_version_tags(String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def list_version_tags(path) do
    with {:ok, tags} <- list_tags(path) do
      version_tags = Enum.filter(tags, &version_like_tag?/1)
      {:ok, version_tags}
    end
  end

  defp version_like_tag?(tag) do
    # Match common version tag patterns
    Regex.match?(~r/^v?\d+\.\d+/, tag) or
      Regex.match?(~r/^release[_-]?\d+/i, tag)
  end

  @doc """
  Extracts tag information including commit SHA and timestamp.

  ## Parameters

  - `path` - Path to the git repository
  - `tag` - Tag name to extract info for

  ## Returns

  - `{:ok, %{commit_sha: ..., short_sha: ..., timestamp: ...}}` - Tag info
  - `{:error, reason}` - Error occurred
  """
  @spec extract_tag_info(String.t(), String.t()) ::
          {:ok, %{commit_sha: String.t(), short_sha: String.t(), timestamp: DateTime.t() | nil}}
          | {:error, atom()}
  def extract_tag_info(path, tag) do
    with {:ok, repo_path} <- Git.detect_repo(path) do
      # Get the commit SHA the tag points to
      case get_tag_commit(repo_path, tag) do
        {:ok, commit_sha} ->
          # Get timestamp from commit
          case Commit.extract_commit(repo_path, commit_sha) do
            {:ok, commit} ->
              {:ok,
               %{
                 commit_sha: commit.sha,
                 short_sha: commit.short_sha,
                 timestamp: commit.commit_date
               }}

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp get_tag_commit(repo_path, tag) do
    # Use rev-parse to get commit SHA (handles both lightweight and annotated tags)
    args = ["rev-parse", "#{tag}^{commit}"]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, reason} -> {:error, reason}
    end
  end

  # ===========================================================================
  # Version Extraction from mix.exs
  # ===========================================================================

  @doc """
  Extracts the version from mix.exs at a specific commit.

  ## Parameters

  - `path` - Path to the git repository
  - `ref` - Commit reference (default: "HEAD")

  ## Returns

  - `{:ok, version}` - Version string from mix.exs
  - `{:error, reason}` - Error occurred
  """
  @spec extract_version_at_commit(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def extract_version_at_commit(path, ref \\ "HEAD") do
    with {:ok, repo_path} <- Git.detect_repo(path),
         {:ok, content} <- read_mix_exs_at_commit(repo_path, ref) do
      parse_version_from_mix_exs(content)
    end
  end

  @doc """
  Extracts the current version from mix.exs.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> {:ok, version} = Release.extract_current_version(".")
      iex> is_binary(version)
      true
  """
  @spec extract_current_version(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def extract_current_version(path) do
    extract_version_at_commit(path, "HEAD")
  end

  defp read_mix_exs_at_commit(repo_path, ref) do
    args = ["show", "#{ref}:mix.exs"]

    case GitUtils.run_git_command(repo_path, args) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> {:error, :mix_exs_not_found}
    end
  end

  defp parse_version_from_mix_exs(content) do
    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        case find_version_in_ast(ast) do
          nil -> {:error, :version_not_found}
          version when is_binary(version) -> {:ok, version}
          _ -> {:error, :version_not_literal}
        end

      {:error, _} ->
        {:error, :parse_error}
    end
  end

  defp find_version_in_ast(ast) do
    {_, version} = Macro.prewalk(ast, nil, &find_version_value/2)
    version
  end

  # Look for version: "x.x.x" in project config
  defp find_version_value({:version, value}, _acc) when is_binary(value) do
    {{:version, value}, value}
  end

  # Look for @version module attribute
  defp find_version_value({:@, _, [{:version, _, [value]}]}, _acc) when is_binary(value) do
    {{:@, [], [{:version, [], [value]}]}, value}
  end

  defp find_version_value(node, acc), do: {node, acc}

  # ===========================================================================
  # Release Extraction
  # ===========================================================================

  @doc """
  Extracts all releases from git tags.

  Returns releases sorted by version (newest first).

  ## Parameters

  - `path` - Path to the git repository
  - `opts` - Options:
    - `:include_all_tags` - Include non-version tags (default: false)

  ## Returns

  - `{:ok, releases}` - List of Release structs sorted by version
  - `{:error, reason}` - Error occurred

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> {:ok, releases} = Release.extract_releases(".")
      iex> is_list(releases)
      true
  """
  @spec extract_releases(String.t(), keyword()) :: {:ok, [t()]} | {:error, atom()}
  def extract_releases(path, opts \\ []) do
    include_all = Keyword.get(opts, :include_all_tags, false)

    with {:ok, repo_path} <- Git.detect_repo(path),
         {:ok, tags} <- if(include_all, do: list_tags(path), else: list_version_tags(path)) do
      releases =
        tags
        |> Enum.map(fn tag -> extract_release_from_tag(repo_path, tag) end)
        |> Enum.filter(fn
          {:ok, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {:ok, release} -> release end)
        |> sort_releases()
        |> add_previous_versions()

      {:ok, releases}
    end
  end

  @doc """
  Extracts a single release by tag name.

  ## Parameters

  - `path` - Path to the git repository
  - `tag` - Git tag name

  ## Returns

  - `{:ok, release}` - Release struct
  - `{:error, reason}` - Error occurred

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> {:ok, tags} = Release.list_version_tags(".")
      iex> if length(tags) > 0 do
      ...>   {:ok, _release} = Release.extract_release(".", hd(tags))
      ...> else
      ...>   {:ok, %Release{release_id: "test", version: "0.0.0", commit_sha: "abc", short_sha: "abc"}}
      ...> end
      iex> true
      true
  """
  @spec extract_release(String.t(), String.t()) :: {:ok, t()} | {:error, atom()}
  def extract_release(path, tag) do
    with {:ok, repo_path} <- Git.detect_repo(path) do
      extract_release_from_tag(repo_path, tag)
    end
  end

  defp extract_release_from_tag(repo_path, tag) do
    with {:ok, tag_info} <- extract_tag_info(repo_path, tag),
         version <- extract_version_from_tag(tag),
         {:ok, semver} <- parse_semver_or_nil(version),
         project_name <- get_project_name(repo_path, tag_info.commit_sha) do
      release = %__MODULE__{
        release_id: "release:#{tag}",
        version: version,
        tag: tag,
        commit_sha: tag_info.commit_sha,
        short_sha: tag_info.short_sha,
        timestamp: tag_info.timestamp,
        semver: semver,
        previous_version: nil,
        project_name: project_name,
        metadata: %{}
      }

      {:ok, release}
    end
  end

  defp extract_version_from_tag(tag) do
    # Strip common prefixes to get version number
    tag
    |> String.trim_leading("v")
    |> String.trim_leading("release-")
    |> String.trim_leading("release_")
  end

  defp parse_semver_or_nil(version) do
    case parse_semver(version) do
      {:ok, semver} -> {:ok, semver}
      {:error, _} -> {:ok, nil}
    end
  end

  defp get_project_name(repo_path, commit_sha) do
    case extract_version_at_commit(repo_path, commit_sha) do
      {:ok, _} ->
        # If we can read mix.exs, try to get project name
        case read_mix_exs_at_commit(repo_path, commit_sha) do
          {:ok, content} -> extract_app_name(content)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_app_name(content) do
    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        {_, app_name} = Macro.prewalk(ast, nil, &find_app_name/2)
        app_name

      _ ->
        nil
    end
  end

  defp find_app_name({:app, value}, _acc) when is_atom(value) do
    {{:app, value}, value}
  end

  defp find_app_name(node, acc), do: {node, acc}

  # ===========================================================================
  # Release Progression
  # ===========================================================================

  @doc """
  Returns releases sorted by semantic version (newest first).

  ## Parameters

  - `releases` - List of Release structs

  ## Returns

  List of releases sorted by version descending
  """
  @spec sort_releases([t()]) :: [t()]
  def sort_releases(releases) do
    Enum.sort(releases, fn r1, r2 ->
      compare_versions(r1.version, r2.version) == :gt
    end)
  end

  @doc """
  Returns the release progression as an ordered list (oldest first).

  ## Parameters

  - `path` - Path to the git repository

  ## Returns

  - `{:ok, releases}` - Releases ordered from oldest to newest
  - `{:error, reason}` - Error occurred

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Release
      iex> {:ok, progression} = Release.release_progression(".")
      iex> is_list(progression)
      true
  """
  @spec release_progression(String.t()) :: {:ok, [t()]} | {:error, atom()}
  def release_progression(path) do
    with {:ok, releases} <- extract_releases(path) do
      # Reverse to get oldest first
      {:ok, Enum.reverse(releases)}
    end
  end

  defp add_previous_versions([]), do: []
  defp add_previous_versions([first | rest]) do
    add_previous_versions_rec([first], rest)
  end

  defp add_previous_versions_rec(acc, []), do: Enum.reverse(acc)

  defp add_previous_versions_rec([prev | _] = acc, [current | rest]) do
    updated = %{current | previous_version: prev.version}
    add_previous_versions_rec([updated | acc], rest)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(str), do: str
end
