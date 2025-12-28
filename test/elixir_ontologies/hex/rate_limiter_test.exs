defmodule ElixirOntologies.Hex.RateLimiterTest do
  use ExUnit.Case, async: true

  alias ElixirOntologies.Hex.RateLimiter
  alias ElixirOntologies.Hex.RateLimiter.State

  # ===========================================================================
  # Initialization Tests
  # ===========================================================================

  describe "new/1" do
    test "creates state with default values" do
      state = RateLimiter.new()

      assert %State{} = state
      assert state.max_tokens == 10
      assert state.tokens == 10.0
      assert state.refill_rate > 0
      assert is_integer(state.last_refill)
      assert state.api_remaining == nil
      assert state.api_reset == nil
    end

    test "accepts custom rate and burst" do
      state = RateLimiter.new(rate: 60, burst: 5)

      assert state.max_tokens == 5
      assert state.tokens == 5.0
      # 60 per minute = 1 per second = 0.001 per ms
      assert_in_delta state.refill_rate, 0.001, 0.0001
    end

    test "starts with full bucket" do
      state = RateLimiter.new(burst: 3)

      assert state.tokens == 3.0
    end
  end

  describe "default_rate/0" do
    test "returns default rate" do
      assert RateLimiter.default_rate() == 100
    end
  end

  describe "default_burst/0" do
    test "returns default burst" do
      assert RateLimiter.default_burst() == 10
    end
  end

  # ===========================================================================
  # Token Refill Tests
  # ===========================================================================

  describe "refill/1" do
    test "adds tokens based on elapsed time" do
      state = %State{
        tokens: 0.0,
        max_tokens: 10,
        refill_rate: 0.01,
        last_refill: System.monotonic_time(:millisecond) - 100,
        api_remaining: nil,
        api_reset: nil
      }

      refilled = RateLimiter.refill(state)

      # Should have gained ~1 token (100ms * 0.01 tokens/ms)
      assert refilled.tokens >= 0.9
      assert refilled.tokens <= 1.1
    end

    test "caps tokens at max_tokens" do
      state = %State{
        tokens: 9.0,
        max_tokens: 10,
        refill_rate: 0.01,
        last_refill: System.monotonic_time(:millisecond) - 500,
        api_remaining: nil,
        api_reset: nil
      }

      refilled = RateLimiter.refill(state)

      assert refilled.tokens == 10.0
    end

    test "updates last_refill timestamp" do
      state = RateLimiter.new()
      old_refill = state.last_refill

      Process.sleep(10)
      refilled = RateLimiter.refill(state)

      assert refilled.last_refill > old_refill
    end
  end

  # ===========================================================================
  # Token Consumption Tests
  # ===========================================================================

  describe "consume/1" do
    test "returns {:ok, state} when tokens available" do
      state = %State{
        tokens: 5.0,
        max_tokens: 10,
        refill_rate: 0.01,
        last_refill: System.monotonic_time(:millisecond),
        api_remaining: nil,
        api_reset: nil
      }

      assert {:ok, new_state} = RateLimiter.consume(state)
      assert new_state.tokens == 4.0
    end

    test "returns {:wait, ms} when bucket empty" do
      state = %State{
        tokens: 0.0,
        max_tokens: 10,
        refill_rate: 0.01,
        last_refill: System.monotonic_time(:millisecond),
        api_remaining: nil,
        api_reset: nil
      }

      assert {:wait, ms} = RateLimiter.consume(state)
      # Should need ~100ms to get 1 token at 0.01 tokens/ms
      assert ms >= 90
      assert ms <= 110
    end

    test "returns {:wait, ms} when tokens below 1" do
      state = %State{
        tokens: 0.5,
        max_tokens: 10,
        refill_rate: 0.01,
        last_refill: System.monotonic_time(:millisecond),
        api_remaining: nil,
        api_reset: nil
      }

      assert {:wait, ms} = RateLimiter.consume(state)
      # Should need ~50ms to get 0.5 tokens
      assert ms >= 40
      assert ms <= 60
    end
  end

  # ===========================================================================
  # Acquire Tests
  # ===========================================================================

  describe "acquire/1" do
    test "returns state immediately when tokens available" do
      state = RateLimiter.new(burst: 5)

      start_time = System.monotonic_time(:millisecond)
      new_state = RateLimiter.acquire(state)
      elapsed = System.monotonic_time(:millisecond) - start_time

      # Should be very fast
      assert elapsed < 50
      assert new_state.tokens < 5.0
    end

    test "blocks when no tokens available" do
      state = %State{
        tokens: 0.0,
        max_tokens: 10,
        refill_rate: 0.1,
        last_refill: System.monotonic_time(:millisecond),
        api_remaining: nil,
        api_reset: nil
      }

      start_time = System.monotonic_time(:millisecond)
      _new_state = RateLimiter.acquire(state)
      elapsed = System.monotonic_time(:millisecond) - start_time

      # Should have waited for refill
      assert elapsed >= 5
    end
  end

  # ===========================================================================
  # Header Parsing Tests
  # ===========================================================================

  describe "update_from_headers/2" do
    test "parses rate limit headers" do
      state = RateLimiter.new()

      headers = %{
        "x-ratelimit-remaining" => "50",
        "x-ratelimit-reset" => "1234567890"
      }

      updated = RateLimiter.update_from_headers(state, headers)

      assert updated.api_remaining == 50
      assert updated.api_reset == 1_234_567_890
    end

    test "handles list format headers" do
      state = RateLimiter.new()

      headers = [
        {"X-RateLimit-Remaining", "25"},
        {"X-RateLimit-Reset", "1234567890"}
      ]

      updated = RateLimiter.update_from_headers(state, headers)

      assert updated.api_remaining == 25
    end

    test "handles missing headers" do
      state = RateLimiter.new()

      updated = RateLimiter.update_from_headers(state, %{})

      assert updated.api_remaining == nil
      assert updated.api_reset == nil
    end

    test "handles integer values in headers" do
      state = RateLimiter.new()

      headers = %{
        "x-ratelimit-remaining" => 42
      }

      updated = RateLimiter.update_from_headers(state, headers)

      assert updated.api_remaining == 42
    end
  end

  # ===========================================================================
  # Adaptive Delay Tests
  # ===========================================================================

  describe "adaptive_delay/1" do
    test "returns 0 when api_remaining is nil" do
      state = %State{api_remaining: nil, api_reset: nil}

      assert RateLimiter.adaptive_delay(state) == 0
    end

    test "returns 0 when plenty of calls remaining" do
      state = %State{api_remaining: 100, api_reset: nil}

      assert RateLimiter.adaptive_delay(state) == 0
    end

    test "returns delay when calls are low" do
      state = %State{api_remaining: 20, api_reset: nil}

      delay = RateLimiter.adaptive_delay(state)
      assert delay == 1000
    end

    test "returns higher delay when calls very low" do
      state = %State{api_remaining: 5, api_reset: nil}

      delay = RateLimiter.adaptive_delay(state)
      assert delay >= 2000
    end

    test "uses reset time when available" do
      now = System.system_time(:second)
      reset_time = now + 60  # 60 seconds from now

      state = %State{api_remaining: 5, api_reset: reset_time}

      delay = RateLimiter.adaptive_delay(state)
      # Should spread 5 calls over 60 seconds
      assert delay > 0
    end

    test "returns 500 for medium remaining calls" do
      state = %State{api_remaining: 40, api_reset: nil}

      assert RateLimiter.adaptive_delay(state) == 500
    end
  end
end
