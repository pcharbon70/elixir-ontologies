defmodule ElixirOntologies.Hex.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for API calls.

  Implements a token bucket algorithm with adaptive delay based on
  API rate limit headers. Provides smooth rate limiting to avoid
  hitting hex.pm rate limits.

  ## Usage

      # Create a rate limiter
      state = RateLimiter.new(rate: 100, burst: 10)

      # Acquire a token (blocks if necessary)
      state = RateLimiter.acquire(state)

      # Update from API headers
      state = RateLimiter.update_from_headers(state, headers)

      # Get adaptive delay
      delay_ms = RateLimiter.adaptive_delay(state)
  """

  @default_rate 100
  @default_burst 10

  defmodule State do
    @moduledoc "Internal state for the token bucket rate limiter."
    defstruct [
      :tokens,
      :max_tokens,
      :refill_rate,
      :last_refill,
      :api_remaining,
      :api_reset
    ]

    @type t :: %__MODULE__{
            tokens: float(),
            max_tokens: non_neg_integer(),
            refill_rate: float(),
            last_refill: integer(),
            api_remaining: non_neg_integer() | nil,
            api_reset: integer() | nil
          }
  end

  @doc """
  Creates a new rate limiter state.

  ## Options

    * `:rate` - requests per minute (default: #{@default_rate})
    * `:burst` - burst allowance / bucket capacity (default: #{@default_burst})

  ## Examples

      iex> state = RateLimiter.new()
      iex> state.max_tokens
      10

      iex> state = RateLimiter.new(rate: 60, burst: 5)
      iex> state.max_tokens
      5
  """
  @spec new(keyword()) :: State.t()
  def new(opts \\ []) do
    rate = Keyword.get(opts, :rate, @default_rate)
    burst = Keyword.get(opts, :burst, @default_burst)

    # Convert requests per minute to tokens per millisecond
    refill_rate = rate / 60_000.0

    %State{
      tokens: burst * 1.0,
      max_tokens: burst,
      refill_rate: refill_rate,
      last_refill: System.monotonic_time(:millisecond),
      api_remaining: nil,
      api_reset: nil
    }
  end

  @doc """
  Refills tokens based on elapsed time.

  Adds tokens based on the time elapsed since the last refill,
  capped at the maximum bucket capacity.
  """
  @spec refill(State.t()) :: State.t()
  def refill(%State{} = state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_refill

    if elapsed > 0 do
      new_tokens = state.tokens + elapsed * state.refill_rate
      capped_tokens = min(new_tokens, state.max_tokens * 1.0)

      %{state | tokens: capped_tokens, last_refill: now}
    else
      state
    end
  end

  @doc """
  Attempts to consume one token from the bucket.

  Returns `{:ok, state}` if a token was available, or
  `{:wait, milliseconds}` if the bucket is empty.
  """
  @spec consume(State.t()) :: {:ok, State.t()} | {:wait, non_neg_integer()}
  def consume(%State{} = state) do
    if state.tokens >= 1.0 do
      {:ok, %{state | tokens: state.tokens - 1.0}}
    else
      # Calculate wait time to get 1 token
      needed = 1.0 - state.tokens
      wait_ms = ceil(needed / state.refill_rate)
      {:wait, wait_ms}
    end
  end

  @doc """
  Acquires a token, blocking if necessary.

  Refills the bucket, then consumes a token. If no token is available,
  sleeps for the required duration and retries.
  """
  @spec acquire(State.t()) :: State.t()
  def acquire(%State{} = state) do
    state = refill(state)

    case consume(state) do
      {:ok, new_state} ->
        new_state

      {:wait, ms} ->
        Process.sleep(ms)
        acquire(state)
    end
  end

  @doc """
  Updates rate limiter state from API response headers.

  Parses `X-RateLimit-Remaining` and `X-RateLimit-Reset` headers
  to inform adaptive delay calculations.
  """
  @spec update_from_headers(State.t(), map() | list()) :: State.t()
  def update_from_headers(%State{} = state, headers) do
    headers = normalize_headers(headers)

    remaining = parse_header(headers, "x-ratelimit-remaining")
    reset = parse_header(headers, "x-ratelimit-reset")

    %{state | api_remaining: remaining, api_reset: reset}
  end

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)
  end

  defp parse_header(headers, key) do
    case Map.get(headers, key) do
      nil -> nil
      value when is_binary(value) -> String.to_integer(value)
      value when is_integer(value) -> value
    end
  rescue
    _ -> nil
  end

  @doc """
  Calculates adaptive delay based on API rate limit state.

  Returns extra delay in milliseconds when API remaining calls are low.
  Returns 0 when there are plenty of API calls remaining.

  ## Examples

      # Plenty of remaining calls
      iex> state = %State{api_remaining: 100, api_reset: nil}
      iex> RateLimiter.adaptive_delay(state)
      0

      # Low remaining calls
      iex> state = %State{api_remaining: 5, api_reset: nil}
      iex> RateLimiter.adaptive_delay(state) > 0
      true
  """
  @spec adaptive_delay(State.t()) :: non_neg_integer()
  def adaptive_delay(%State{api_remaining: nil}), do: 0

  def adaptive_delay(%State{api_remaining: remaining, api_reset: reset}) do
    cond do
      # Very low - aggressive slowdown
      remaining <= 5 ->
        base_delay = 2000

        if reset do
          # Calculate delay to spread remaining calls until reset
          now = System.system_time(:second)
          time_until_reset = max(reset - now, 1)
          # Spread remaining calls evenly, with buffer
          div(time_until_reset * 1000, max(remaining, 1))
        else
          base_delay
        end

      # Low - moderate slowdown
      remaining <= 20 ->
        1000

      # Medium - slight slowdown
      remaining <= 50 ->
        500

      # Plenty remaining
      true ->
        0
    end
  end

  @doc """
  Returns the default rate (requests per minute).
  """
  @spec default_rate() :: non_neg_integer()
  def default_rate, do: @default_rate

  @doc """
  Returns the default burst size.
  """
  @spec default_burst() :: non_neg_integer()
  def default_burst, do: @default_burst
end
