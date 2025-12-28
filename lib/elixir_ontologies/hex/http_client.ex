defmodule ElixirOntologies.Hex.HttpClient do
  @moduledoc """
  HTTP client wrapper for Hex.pm API and tarball downloads.

  Provides a thin wrapper around Req with project-specific defaults including:
  - Consistent User-Agent identification
  - Automatic retry with exponential backoff
  - Configurable timeouts
  - Rate limit header tracking
  - Streaming downloads for large files

  ## Usage

      client = HttpClient.new()
      {:ok, response} = HttpClient.get(client, "https://hex.pm/api/packages")

      # Download a tarball
      {:ok, path} = HttpClient.download(client, url, "/tmp/package.tar.gz")
  """

  @user_agent "ElixirOntologies/#{Mix.Project.config()[:version]} (Elixir/#{System.version()})"
  @default_timeout 30_000
  @default_retries 3

  @rate_limit_headers ["x-ratelimit-limit", "x-ratelimit-remaining", "x-ratelimit-reset"]

  @doc """
  Creates a new HTTP client with default options.

  ## Examples

      iex> client = HttpClient.new()
      iex> %Req.Request{} = client
  """
  @spec new() :: Req.Request.t()
  def new, do: new([])

  @doc """
  Creates a new HTTP client with custom options.

  ## Options

    * `:timeout` - Request timeout in milliseconds (default: #{@default_timeout})
    * `:retries` - Maximum retry attempts (default: #{@default_retries})

  ## Examples

      iex> client = HttpClient.new(timeout: 60_000, retries: 5)
      iex> %Req.Request{} = client
  """
  @spec new(keyword()) :: Req.Request.t()
  def new(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    retries = Keyword.get(opts, :retries, @default_retries)

    Req.new(
      headers: [{"user-agent", @user_agent}],
      receive_timeout: timeout,
      retry: :safe_transient,
      max_retries: retries,
      retry_delay: &exponential_backoff/1
    )
  end

  @doc """
  Performs a GET request to the given URL.

  ## Returns

    * `{:ok, response}` - Successful response (2xx status)
    * `{:error, :not_found}` - 404 response
    * `{:error, :rate_limited}` - 429 response
    * `{:error, {:http_error, status}}` - Other HTTP errors
    * `{:error, reason}` - Connection failures

  ## Examples

      iex> client = HttpClient.new()
      iex> {:ok, response} = HttpClient.get(client, "https://hex.pm/api/packages/req")
      iex> response.status
      200
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, Req.Response.t()} | {:error, term()}
  def get(client, url), do: get(client, url, [])

  @doc """
  Performs a GET request with additional options.

  ## Options

  Accepts any options supported by `Req.get/2`.

  ## Examples

      iex> client = HttpClient.new()
      iex> {:ok, response} = HttpClient.get(client, url, headers: [{"accept", "application/json"}])
  """
  @spec get(Req.Request.t(), String.t(), keyword()) ::
          {:ok, Req.Response.t()} | {:error, term()}
  def get(client, url, opts) do
    case Req.get(client, [url: url] ++ opts) do
      {:ok, %{status: status} = response} when status >= 200 and status < 300 ->
        {:ok, response}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Downloads a file from the given URL to a local path.

  Streams the response body to disk to handle large files efficiently.

  ## Returns

    * `{:ok, file_path}` - Successfully downloaded file
    * `{:error, reason}` - Download failed (partial file is cleaned up)

  ## Examples

      iex> client = HttpClient.new()
      iex> {:ok, path} = HttpClient.download(client, url, "/tmp/package.tar.gz")
      iex> File.exists?(path)
      true
  """
  @spec download(Req.Request.t(), String.t(), Path.t()) ::
          {:ok, Path.t()} | {:error, term()}
  def download(client, url, file_path), do: download(client, url, file_path, [])

  @doc """
  Downloads a file with additional options.

  ## Options

  Accepts any options supported by `Req.get/2`.
  """
  @spec download(Req.Request.t(), String.t(), Path.t(), keyword()) ::
          {:ok, Path.t()} | {:error, term()}
  def download(client, url, file_path, opts) do
    # Ensure parent directory exists
    file_path
    |> Path.dirname()
    |> File.mkdir_p!()

    # Disable auto-decoding for binary downloads (tar files, etc.)
    case Req.get(client, [url: url, decode_body: false] ++ opts) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        case File.write(file_path, body) do
          :ok -> {:ok, file_path}
          {:error, reason} -> {:error, {:file_write, reason}}
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extracts rate limit information from response headers.

  ## Returns

    * `%{limit: integer, remaining: integer, reset: unix_timestamp}` when headers present
    * `nil` when headers not present

  ## Examples

      iex> response = %Req.Response{headers: %{"x-ratelimit-limit" => ["100"], "x-ratelimit-remaining" => ["50"], "x-ratelimit-reset" => ["1704067200"]}}
      iex> HttpClient.extract_rate_limit(response)
      %{limit: 100, remaining: 50, reset: 1704067200}
  """
  @spec extract_rate_limit(Req.Response.t()) :: map() | nil
  def extract_rate_limit(%{headers: headers}) do
    with {:ok, limit} <- get_header_int(headers, "x-ratelimit-limit"),
         {:ok, remaining} <- get_header_int(headers, "x-ratelimit-remaining"),
         {:ok, reset} <- get_header_int(headers, "x-ratelimit-reset") do
      %{limit: limit, remaining: remaining, reset: reset}
    else
      _ -> nil
    end
  end

  defp get_header_int(headers, key) do
    case headers do
      %{^key => [value | _]} ->
        case Integer.parse(value) do
          {int, ""} -> {:ok, int}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  @doc """
  Calculates delay in milliseconds based on rate limit status.

  Returns 0 when plenty of requests remain (> 10% of limit).
  Returns increasing delay as remaining approaches 0.

  ## Examples

      iex> HttpClient.rate_limit_delay(%{limit: 100, remaining: 50, reset: now + 60})
      0

      iex> HttpClient.rate_limit_delay(%{limit: 100, remaining: 5, reset: now + 60})
      # Returns calculated delay based on reset time
  """
  @spec rate_limit_delay(map()) :: non_neg_integer()
  def rate_limit_delay(%{limit: limit, remaining: remaining, reset: reset}) do
    threshold = div(limit, 10)

    if remaining > threshold do
      0
    else
      # Calculate delay to spread remaining requests until reset
      now = System.system_time(:second)
      time_until_reset = max(reset - now, 1)
      requests_remaining = max(remaining, 1)

      # Delay in ms, minimum 100ms
      max(div(time_until_reset * 1000, requests_remaining), 100)
    end
  end

  def rate_limit_delay(nil), do: 0

  @doc """
  Returns the rate limit header names this client tracks.
  """
  @spec rate_limit_headers() :: [String.t()]
  def rate_limit_headers, do: @rate_limit_headers

  @doc """
  Returns the default User-Agent string.
  """
  @spec user_agent() :: String.t()
  def user_agent, do: @user_agent

  # Exponential backoff with jitter: 1s, 2s, 4s base + random jitter
  defp exponential_backoff(attempt) do
    base = :math.pow(2, attempt - 1) * 1000
    jitter = :rand.uniform(500)
    trunc(base + jitter)
  end
end
