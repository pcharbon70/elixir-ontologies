defmodule ElixirOntologies.Analyzer.Git.Cache do
  @moduledoc """
  Agent-based caching layer for git operations.

  Provides TTL-based caching for expensive git metadata operations
  to avoid repeated subprocess calls when analyzing large codebases.

  ## Usage

      # Start the cache (usually in your application supervision tree)
      {:ok, _pid} = Git.Cache.start_link()

      # Use cached repository info
      {:ok, repo} = Git.Cache.get_or_fetch_repository(".")

      # Clear cache if needed
      :ok = Git.Cache.clear()

  ## Configuration

  The cache TTL defaults to 5 minutes but can be configured:

      config :elixir_ontologies, Git.Cache, ttl: :timer.minutes(10)
  """

  use Agent

  alias ElixirOntologies.Analyzer.Git

  @default_ttl :timer.minutes(5)

  @type cache_entry :: {term(), integer()}
  @type cache_state :: %{
          repositories: %{String.t() => cache_entry()},
          commits: %{String.t() => cache_entry()}
        }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts the cache agent.

  ## Options

  - `:name` - The name to register the agent under (default: `__MODULE__`)
  - `:ttl` - Cache TTL in milliseconds (default: 5 minutes)
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> initial_state() end, name: name)
  end

  @doc """
  Gets or fetches repository info with caching.

  If the repository info is cached and not expired, returns the cached value.
  Otherwise, fetches fresh data and caches it.
  """
  @spec get_or_fetch_repository(String.t(), keyword()) ::
          {:ok, Git.Repository.t()} | {:error, atom()}
  def get_or_fetch_repository(path, opts \\ []) do
    cache_name = Keyword.get(opts, :cache, __MODULE__)
    ttl = get_ttl(opts)

    cache_key = normalize_cache_key(path)

    case get_cached(cache_name, :repositories, cache_key, ttl) do
      {:ok, repo} ->
        {:ok, repo}

      :miss ->
        case Git.repository(path) do
          {:ok, repo} = result ->
            put_cached(cache_name, :repositories, cache_key, repo)
            result

          error ->
            error
        end
    end
  end

  @doc """
  Gets or fetches current commit with caching.
  """
  @spec get_or_fetch_commit(String.t(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def get_or_fetch_commit(path, opts \\ []) do
    cache_name = Keyword.get(opts, :cache, __MODULE__)
    ttl = get_ttl(opts)

    cache_key = normalize_cache_key(path)

    case get_cached(cache_name, :commits, cache_key, ttl) do
      {:ok, commit} ->
        {:ok, commit}

      :miss ->
        case Git.current_commit(path) do
          {:ok, commit} = result ->
            put_cached(cache_name, :commits, cache_key, commit)
            result

          error ->
            error
        end
    end
  end

  @doc """
  Clears all cached data.
  """
  @spec clear(atom()) :: :ok
  def clear(cache_name \\ __MODULE__) do
    Agent.update(cache_name, fn _ -> initial_state() end)
  end

  @doc """
  Clears cached data for a specific repository path.
  """
  @spec invalidate(String.t(), atom()) :: :ok
  def invalidate(path, cache_name \\ __MODULE__) do
    cache_key = normalize_cache_key(path)

    Agent.update(cache_name, fn state ->
      state
      |> update_in([:repositories], &Map.delete(&1, cache_key))
      |> update_in([:commits], &Map.delete(&1, cache_key))
    end)
  end

  @doc """
  Returns cache statistics for monitoring.
  """
  @spec stats(atom()) :: %{repositories: non_neg_integer(), commits: non_neg_integer()}
  def stats(cache_name \\ __MODULE__) do
    Agent.get(cache_name, fn state ->
      %{
        repositories: map_size(state.repositories),
        commits: map_size(state.commits)
      }
    end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp initial_state do
    %{repositories: %{}, commits: %{}}
  end

  defp get_ttl(opts) do
    Keyword.get(opts, :ttl) ||
      Application.get_env(:elixir_ontologies, __MODULE__, [])[:ttl] ||
      @default_ttl
  end

  defp normalize_cache_key(path) do
    Path.expand(path)
  end

  defp get_cached(cache_name, bucket, key, ttl) do
    now = System.monotonic_time(:millisecond)

    Agent.get(cache_name, fn state ->
      case get_in(state, [bucket, key]) do
        {value, timestamp} when now - timestamp < ttl ->
          {:ok, value}

        _ ->
          :miss
      end
    end)
  end

  defp put_cached(cache_name, bucket, key, value) do
    now = System.monotonic_time(:millisecond)

    Agent.update(cache_name, fn state ->
      put_in(state, [bucket, key], {value, now})
    end)
  end
end
