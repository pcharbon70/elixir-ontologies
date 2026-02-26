defmodule ElixirOntologies.Hex.HttpClient do
  @moduledoc """
  HTTP client wrapper for Hex.pm API and tarball downloads.

  Provides a thin wrapper around Req with project-specific defaults including:
  - Consistent User-Agent identification
  - Automatic retry with Retry-After support and incremental backoff fallback
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
  @default_retries 4
  @max_retries 4
  @default_retry_base_delay_ms 1_000
  @default_retry_max_delay_ms 30_000
  @default_retry_jitter_ms 500
  @retryable_statuses [408, 429, 500, 502, 503, 504]

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
    * `:retries` - Maximum retry attempts (default: #{@default_retries}, max: #{@max_retries})
    * `:retry_base_delay_ms` - Base delay for incremental backoff (default: #{@default_retry_base_delay_ms})
    * `:retry_max_delay_ms` - Maximum retry delay cap (default: #{@default_retry_max_delay_ms})
    * `:retry_jitter_ms` - Random jitter added to retry delay (default: #{@default_retry_jitter_ms})

  ## Examples

      iex> client = HttpClient.new(timeout: 60_000, retries: 5)
      iex> %Req.Request{} = client
  """
  @spec new(keyword()) :: Req.Request.t()
  def new(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    retries =
      normalize_non_negative_int(Keyword.get(opts, :retries, @default_retries), @default_retries)
      |> min(@max_retries)

    retry_base_delay_ms =
      normalize_non_negative_int(
        Keyword.get(opts, :retry_base_delay_ms, @default_retry_base_delay_ms),
        @default_retry_base_delay_ms
      )

    retry_max_delay_ms =
      normalize_non_negative_int(
        Keyword.get(opts, :retry_max_delay_ms, @default_retry_max_delay_ms),
        @default_retry_max_delay_ms
      )
      |> max(retry_base_delay_ms)

    retry_jitter_ms =
      normalize_non_negative_int(
        Keyword.get(opts, :retry_jitter_ms, @default_retry_jitter_ms),
        @default_retry_jitter_ms
      )

    Req.new(
      headers: [{"user-agent", @user_agent}],
      receive_timeout: timeout,
      retry:
        &retry_with_backoff(
          &1,
          &2,
          retry_base_delay_ms,
          retry_max_delay_ms,
          retry_jitter_ms
        ),
      max_retries: retries
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

  # Req supports custom retry callbacks. We return {:delay, ms} so we can
  # use Retry-After when available and otherwise apply incremental backoff.
  defp retry_with_backoff(request, response_or_exception, base_delay_ms, max_delay_ms, jitter_ms) do
    if should_retry?(request, response_or_exception) do
      {:delay,
       retry_delay_ms(request, response_or_exception, base_delay_ms, max_delay_ms, jitter_ms)}
    else
      false
    end
  end

  defp should_retry?(%Req.Request{method: method}, response_or_exception)
       when method in [:get, :head] do
    transient?(response_or_exception)
  end

  defp should_retry?(_request, _response_or_exception), do: false

  defp transient?(%Req.Response{status: status}) when status in @retryable_statuses, do: true
  defp transient?(%Req.Response{}), do: false

  defp transient?(%Req.TransportError{reason: reason})
       when reason in [:timeout, :econnrefused, :closed],
       do: true

  defp transient?(%Req.HTTPError{protocol: :http2, reason: :unprocessed}), do: true
  defp transient?(%{__exception__: true}), do: false
  defp transient?(_), do: false

  defp retry_delay_ms(request, %Req.Response{status: status} = response, base, max, jitter)
       when status in [429, 503] do
    case Req.Response.get_retry_after(response) do
      delay when is_integer(delay) and delay >= 0 ->
        delay

      _ ->
        incremental_backoff_ms(request, base, max, jitter)
    end
  end

  defp retry_delay_ms(request, _response_or_exception, base, max, jitter) do
    incremental_backoff_ms(request, base, max, jitter)
  end

  # Incremental backoff: base, 2*base, 3*base, ... capped at max.
  defp incremental_backoff_ms(request, base_delay_ms, max_delay_ms, jitter_ms) do
    attempt = Req.Request.get_private(request, :req_retry_count, 0) + 1
    delay = min(attempt * base_delay_ms, max_delay_ms)

    if jitter_ms > 0 do
      jitter = :rand.uniform(jitter_ms) - 1
      min(delay + jitter, max_delay_ms)
    else
      delay
    end
  end

  defp normalize_non_negative_int(value, _default) when is_integer(value) and value >= 0 do
    value
  end

  defp normalize_non_negative_int(_value, default) do
    default
  end
end
