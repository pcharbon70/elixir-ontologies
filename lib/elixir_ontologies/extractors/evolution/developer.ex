defmodule ElixirOntologies.Extractors.Evolution.Developer do
  @moduledoc """
  Extracts and aggregates developer identity from Git commits.

  This module provides functions to extract author and committer information
  from commits and build a unified developer identity across multiple commits.
  It works with the `ElixirOntologies.Extractors.Evolution.Commit` module.

  ## Developer Identity

  Developers are identified primarily by email address. A single developer may
  have multiple name variations across commits (e.g., "John Doe", "John D.",
  "jdoe"), but the email serves as the stable identifier.

  ## Author vs Committer

  Git distinguishes between:
  - **Author**: Person who originally wrote the code
  - **Committer**: Person who created the commit

  These differ in scenarios like rebasing, cherry-picking, or applying patches.
  This module tracks both roles separately.

  ## Usage

      alias ElixirOntologies.Extractors.Evolution.{Developer, Commit}

      # Extract developers from repository
      {:ok, developers} = Developer.extract_developers(".", limit: 100)

      # Get author from a commit
      {:ok, commit} = Commit.extract_commit(".", "HEAD")
      author = Developer.author_from_commit(commit)

      # Aggregate from multiple commits
      {:ok, commits} = Commit.extract_commits(".", limit: 50)
      developers = Developer.from_commits(commits)

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Developer
      iex> {:ok, developers} = Developer.extract_developers(".", limit: 5)
      iex> is_list(developers)
      true
  """

  alias ElixirOntologies.Extractors.Evolution.Commit
  alias ElixirOntologies.Analyzer.Git

  # ===========================================================================
  # Developer Struct
  # ===========================================================================

  @typedoc """
  Represents a developer with aggregated commit activity.

  ## Fields

  - `:email` - Primary identifier (email address)
  - `:name` - Primary display name (most recently used)
  - `:names` - All names used with this email
  - `:authored_commits` - List of commit SHAs where this person is author
  - `:committed_commits` - List of commit SHAs where this person is committer
  - `:first_authored` - Earliest author date
  - `:last_authored` - Most recent author date
  - `:first_committed` - Earliest commit date
  - `:last_committed` - Most recent commit date
  - `:commit_count` - Total unique commits (as author or committer)
  - `:metadata` - Additional metadata
  """
  @type t :: %__MODULE__{
          email: String.t(),
          name: String.t() | nil,
          names: MapSet.t(String.t()),
          authored_commits: [String.t()],
          committed_commits: [String.t()],
          first_authored: DateTime.t() | nil,
          last_authored: DateTime.t() | nil,
          first_committed: DateTime.t() | nil,
          last_committed: DateTime.t() | nil,
          commit_count: non_neg_integer(),
          metadata: map()
        }

  @enforce_keys [:email]
  defstruct [
    :email,
    :name,
    :first_authored,
    :last_authored,
    :first_committed,
    :last_committed,
    names: MapSet.new(),
    authored_commits: [],
    committed_commits: [],
    commit_count: 0,
    metadata: %{}
  ]

  # ===========================================================================
  # Repository-Level Extraction
  # ===========================================================================

  @doc """
  Extracts all developers from a repository.

  Scans commit history and aggregates developer information across commits.

  ## Options

  - `:limit` - Maximum number of commits to scan (default: 100)
  - `:from` - Starting commit reference (default: "HEAD")

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Developer
      iex> {:ok, developers} = Developer.extract_developers(".", limit: 10)
      iex> is_list(developers)
      true
  """
  @spec extract_developers(String.t(), keyword()) :: {:ok, [t()]} | {:error, atom()}
  def extract_developers(path, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    from = Keyword.get(opts, :from, "HEAD")

    with {:ok, _repo_path} <- Git.detect_repo(path),
         {:ok, commits} <- Commit.extract_commits(path, limit: limit, from: from) do
      developers = from_commits(commits)
      {:ok, developers}
    end
  end

  @doc """
  Extracts a specific developer by email.

  Scans commit history for commits by the specified email address.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Developer
      iex> result = Developer.extract_developer(".", "user@example.com")
      iex> match?({:ok, _} | {:error, :not_found}, result)
      true
  """
  @spec extract_developer(String.t(), String.t(), keyword()) ::
          {:ok, t()} | {:error, atom()}
  def extract_developer(path, email, opts \\ []) do
    with {:ok, developers} <- extract_developers(path, opts) do
      case Enum.find(developers, fn dev -> dev.email == email end) do
        nil -> {:error, :not_found}
        developer -> {:ok, developer}
      end
    end
  end

  # ===========================================================================
  # Single Commit Extraction
  # ===========================================================================

  @doc """
  Extracts the author as a Developer from a Commit.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Developer, Commit}
      iex> {:ok, commit} = Commit.extract_commit(".", "HEAD")
      iex> author = Developer.author_from_commit(commit)
      iex> is_binary(author.email)
      true
  """
  @spec author_from_commit(Commit.t()) :: t()
  def author_from_commit(%Commit{} = commit) do
    # Use unique fallback per commit to avoid aggregating unrelated commits
    email = commit.author_email || unknown_email_fallback(commit.sha)

    %__MODULE__{
      email: email,
      name: commit.author_name,
      names: names_set(commit.author_name),
      authored_commits: [commit.sha],
      committed_commits: [],
      first_authored: commit.author_date,
      last_authored: commit.author_date,
      first_committed: nil,
      last_committed: nil,
      commit_count: 1,
      metadata: %{}
    }
  end

  @doc """
  Extracts the committer as a Developer from a Commit.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Developer, Commit}
      iex> {:ok, commit} = Commit.extract_commit(".", "HEAD")
      iex> committer = Developer.committer_from_commit(commit)
      iex> is_binary(committer.email)
      true
  """
  @spec committer_from_commit(Commit.t()) :: t()
  def committer_from_commit(%Commit{} = commit) do
    # Use unique fallback per commit to avoid aggregating unrelated commits
    email = commit.committer_email || unknown_email_fallback(commit.sha)

    %__MODULE__{
      email: email,
      name: commit.committer_name,
      names: names_set(commit.committer_name),
      authored_commits: [],
      committed_commits: [commit.sha],
      first_authored: nil,
      last_authored: nil,
      first_committed: commit.commit_date,
      last_committed: commit.commit_date,
      commit_count: 1,
      metadata: %{}
    }
  end

  @doc """
  Extracts both author and committer from a Commit.

  Returns a list of one or two developers (one if author == committer by email).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Developer, Commit}
      iex> {:ok, commit} = Commit.extract_commit(".", "HEAD")
      iex> developers = Developer.from_commit(commit)
      iex> length(developers) in [1, 2]
      true
  """
  @spec from_commit(Commit.t()) :: [t()]
  def from_commit(%Commit{} = commit) do
    author = author_from_commit(commit)
    committer = committer_from_commit(commit)

    if author.email == committer.email do
      # Same person, merge the records
      [merge_developers(author, committer)]
    else
      [author, committer]
    end
  end

  # ===========================================================================
  # Aggregation
  # ===========================================================================

  @doc """
  Aggregates developers from a list of commits.

  Groups by email and merges developer records.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.{Developer, Commit}
      iex> {:ok, commits} = Commit.extract_commits(".", limit: 5)
      iex> developers = Developer.from_commits(commits)
      iex> is_list(developers)
      true
  """
  @spec from_commits([Commit.t()]) :: [t()]
  def from_commits(commits) when is_list(commits) do
    commits
    |> Enum.flat_map(&from_commit/1)
    |> group_by_email()
    |> Enum.map(fn {_email, developers} ->
      Enum.reduce(developers, &merge_developers/2)
    end)
    |> Enum.sort_by(& &1.commit_count, :desc)
  end

  @doc """
  Merges two Developer records with the same email.

  Combines commit lists, name variations, and updates timestamps.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Developer
      iex> dev1 = %Developer{email: "dev@example.com", name: "Dev", names: MapSet.new(["Dev"]), authored_commits: ["abc"], commit_count: 1}
      iex> dev2 = %Developer{email: "dev@example.com", name: "Developer", names: MapSet.new(["Developer"]), authored_commits: ["def"], commit_count: 1}
      iex> merged = Developer.merge_developers(dev1, dev2)
      iex> length(merged.authored_commits)
      2
  """
  @spec merge_developers(t(), t()) :: t()
  def merge_developers(%__MODULE__{} = dev1, %__MODULE__{} = dev2) do
    # Use the most recent name as primary
    name = most_recent_name(dev1, dev2)

    # Combine all names
    all_names = MapSet.union(dev1.names, dev2.names)

    # Combine commit lists (unique)
    all_authored = Enum.uniq(dev1.authored_commits ++ dev2.authored_commits)
    all_committed = Enum.uniq(dev1.committed_commits ++ dev2.committed_commits)

    # Calculate unique commit count
    all_commits = Enum.uniq(all_authored ++ all_committed)

    %__MODULE__{
      email: dev1.email,
      name: name,
      names: all_names,
      authored_commits: all_authored,
      committed_commits: all_committed,
      first_authored: earliest_date(dev1.first_authored, dev2.first_authored),
      last_authored: latest_date(dev1.last_authored, dev2.last_authored),
      first_committed: earliest_date(dev1.first_committed, dev2.first_committed),
      last_committed: latest_date(dev1.last_committed, dev2.last_committed),
      commit_count: length(all_commits),
      metadata: Map.merge(dev1.metadata, dev2.metadata)
    }
  end

  # ===========================================================================
  # Query Functions
  # ===========================================================================

  @doc """
  Checks if a developer has authored any commits.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Developer
      iex> dev = %Developer{email: "dev@example.com", authored_commits: ["abc"]}
      iex> Developer.author?(dev)
      true
  """
  @spec author?(t()) :: boolean()
  def author?(%__MODULE__{authored_commits: commits}), do: commits != []

  @doc """
  Checks if a developer has committed any commits (as committer).

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Developer
      iex> dev = %Developer{email: "dev@example.com", committed_commits: ["abc"]}
      iex> Developer.committer?(dev)
      true
  """
  @spec committer?(t()) :: boolean()
  def committer?(%__MODULE__{committed_commits: commits}), do: commits != []

  @doc """
  Returns the number of authored commits.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Developer
      iex> dev = %Developer{email: "dev@example.com", authored_commits: ["a", "b", "c"]}
      iex> Developer.authored_count(dev)
      3
  """
  @spec authored_count(t()) :: non_neg_integer()
  def authored_count(%__MODULE__{authored_commits: commits}), do: length(commits)

  @doc """
  Returns the number of committed commits.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Developer
      iex> dev = %Developer{email: "dev@example.com", committed_commits: ["a", "b"]}
      iex> Developer.committed_count(dev)
      2
  """
  @spec committed_count(t()) :: non_neg_integer()
  def committed_count(%__MODULE__{committed_commits: commits}), do: length(commits)

  @doc """
  Checks if a developer has multiple name variations.

  ## Examples

      iex> alias ElixirOntologies.Extractors.Evolution.Developer
      iex> dev = %Developer{email: "dev@example.com", names: MapSet.new(["John Doe", "J. Doe"])}
      iex> Developer.has_name_variations?(dev)
      true
  """
  @spec has_name_variations?(t()) :: boolean()
  def has_name_variations?(%__MODULE__{names: names}), do: MapSet.size(names) > 1

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp names_set(nil), do: MapSet.new()
  defp names_set(name), do: MapSet.new([name])

  defp group_by_email(developers) do
    Enum.group_by(developers, & &1.email)
  end

  defp most_recent_name(dev1, dev2) do
    # Use the most recent authored or committed date to determine which name to use
    dev1_date = dev1.last_authored || dev1.last_committed
    dev2_date = dev2.last_authored || dev2.last_committed

    cond do
      is_nil(dev1_date) and is_nil(dev2_date) -> dev1.name || dev2.name
      is_nil(dev1_date) -> dev2.name
      is_nil(dev2_date) -> dev1.name
      DateTime.compare(dev1_date, dev2_date) == :gt -> dev1.name
      true -> dev2.name
    end
  end

  defp earliest_date(nil, date), do: date
  defp earliest_date(date, nil), do: date

  defp earliest_date(date1, date2) do
    case DateTime.compare(date1, date2) do
      :lt -> date1
      _ -> date2
    end
  end

  defp latest_date(nil, date), do: date
  defp latest_date(date, nil), do: date

  defp latest_date(date1, date2) do
    case DateTime.compare(date1, date2) do
      :gt -> date1
      _ -> date2
    end
  end

  # Generate unique fallback email per commit to prevent aggregating
  # unrelated commits with missing author/committer emails
  defp unknown_email_fallback(sha) do
    short_sha = String.slice(sha || "unknown", 0, 7)
    "unknown-#{short_sha}@unknown"
  end
end
