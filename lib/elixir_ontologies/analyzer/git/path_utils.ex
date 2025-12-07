defmodule ElixirOntologies.Analyzer.Git.PathUtils do
  @moduledoc """
  Path utilities for git repository operations.

  Provides functions for normalizing, validating, and manipulating
  file paths in the context of git repositories.

  ## Usage

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.normalize("lib//foo.ex")
      "lib/foo.ex"

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.relative_to_root("lib/foo.ex", "/home/user/project")
      {:ok, "lib/foo.ex"}
  """

  # ===========================================================================
  # Path Normalization
  # ===========================================================================

  @doc """
  Normalizes a file path for consistent representation.

  - Converts backslashes to forward slashes (Windows compatibility)
  - Removes redundant separators
  - Resolves `.` components (but preserves leading `./`)

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.normalize("lib//foo.ex")
      "lib/foo.ex"

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.normalize("lib/./foo.ex")
      "lib/foo.ex"

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.normalize("lib\\\\foo.ex")
      "lib/foo.ex"
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(path) when is_binary(path) do
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
  Converts an absolute file path to a path relative to the repository root.

  ## Parameters

  - `file_path` - The file path (absolute or relative)
  - `repo_path` - The repository root path

  ## Returns

  - `{:ok, relative_path}` - The path relative to repo root
  - `{:error, :outside_repo}` - If file is outside the repository
  - `{:error, :invalid_path}` - If path doesn't exist

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.relative_to_root("/home/user/project/lib/foo.ex", "/home/user/project")
      {:ok, "lib/foo.ex"}

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.relative_to_root("mix.exs", "/home/user/project")
      {:ok, "mix.exs"}
  """
  @spec relative_to_root(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :outside_repo | :invalid_path}
  def relative_to_root(file_path, repo_path) do
    expanded_file = Path.expand(file_path)
    expanded_repo = Path.expand(repo_path)
    repo_prefix = ensure_trailing_separator(expanded_repo)

    cond do
      # File path is exactly the repo root
      expanded_file == expanded_repo ->
        {:ok, "."}

      # File is within repo
      String.starts_with?(expanded_file, repo_prefix) ->
        relative = String.trim_leading(expanded_file, repo_prefix)
        {:ok, normalize(relative)}

      # File might be a relative path already
      Path.type(file_path) != :absolute ->
        # Check if resolving relative to repo puts it inside
        resolved = Path.join(expanded_repo, file_path) |> Path.expand()

        if String.starts_with?(resolved, repo_prefix) or resolved == expanded_repo do
          {:ok, normalize(file_path)}
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

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.in_repo?("mix.exs", "/home/user/project")
      true

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.in_repo?("/etc/passwd", "/home/user/project")
      false
  """
  @spec in_repo?(String.t(), String.t()) :: boolean()
  def in_repo?(file_path, repo_path) do
    case relative_to_root(file_path, repo_path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Ensures a path ends with a separator.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.ensure_trailing_separator("/home/user/project")
      "/home/user/project/"

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.ensure_trailing_separator("/home/user/project/")
      "/home/user/project/"
  """
  @spec ensure_trailing_separator(String.t()) :: String.t()
  def ensure_trailing_separator(path) do
    if String.ends_with?(path, "/") do
      path
    else
      path <> "/"
    end
  end

  @doc """
  Removes path traversal sequences from a path.

  This is a security measure to prevent path injection attacks.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.remove_traversal("lib/../etc/passwd")
      "lib/etc/passwd"

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.remove_traversal("../../../etc/passwd")
      "etc/passwd"
  """
  @spec remove_traversal(String.t()) :: String.t()
  def remove_traversal(path) do
    path
    |> String.replace(~r/\.\.+/, "")
    |> String.replace(~r/(^|\/)\.\.($|\/)/, "/")
    |> String.trim_leading("/")
  end

  @doc """
  Joins paths with proper normalization.

  ## Examples

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.join("/home/user/project", "lib/foo.ex")
      "/home/user/project/lib/foo.ex"

      iex> alias ElixirOntologies.Analyzer.Git.PathUtils
      iex> PathUtils.join("/home/user/project/", "./lib/foo.ex")
      "/home/user/project/lib/foo.ex"
  """
  @spec join(String.t(), String.t()) :: String.t()
  def join(base, path) do
    Path.join(base, path) |> normalize()
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp normalize_leading_dot(path) do
    case path do
      "./" <> rest -> rest
      other -> other
    end
  end
end
