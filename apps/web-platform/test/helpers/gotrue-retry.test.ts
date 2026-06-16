/**
 * Unit tests for the GoTrue rate-limit retry helper.
 *
 * These run in CI WITHOUT any opt-in env flag or live Supabase — the
 * predicate + backoff logic is pure and the wrapper takes an injectable
 * `sleep` so no real time elapses. This is the deterministic core of the
 * Fix-3 harness-determinism work; the wiring into the live integration
 * suites is exercised only under SUPABASE_DEV_INTEGRATION/TENANT_INTEGRATION_TEST.
 */

import { describe, it, expect, vi } from "vitest";
import { isRetryableGoTrueError, withGoTrueRetry } from "./gotrue-retry";

describe("isRetryableGoTrueError", () => {
  it("returns false for null/undefined (the success path)", () => {
    expect(isRetryableGoTrueError(null)).toBe(false);
    expect(isRetryableGoTrueError(undefined)).toBe(false);
  });

  it("retries on HTTP 429 regardless of code/message", () => {
    expect(isRetryableGoTrueError({ status: 429 })).toBe(true);
  });

  it("retries on over_*_rate_limit codes", () => {
    expect(isRetryableGoTrueError({ code: "over_request_rate_limit" })).toBe(
      true,
    );
    expect(
      isRetryableGoTrueError({ code: "over_email_send_rate_limit" }),
    ).toBe(true);
  });

  it("retries on rate-limit / too-many-requests messages", () => {
    expect(
      isRetryableGoTrueError({ message: "Request rate limit reached" }),
    ).toBe(true);
    expect(isRetryableGoTrueError({ message: "Too Many Requests" })).toBe(
      true,
    );
  });

  it("retries on the opaque 'Database error deleting user' transient", () => {
    expect(
      isRetryableGoTrueError({
        status: 500,
        message: "Database error deleting user",
      }),
    ).toBe(true);
  });

  it("does NOT retry on a genuine non-rate-limit error", () => {
    expect(
      isRetryableGoTrueError({ status: 422, code: "user_already_exists" }),
    ).toBe(false);
    expect(
      isRetryableGoTrueError({ status: 400, message: "Invalid login" }),
    ).toBe(false);
  });
});

describe("withGoTrueRetry", () => {
  const noSleep = vi.fn(async () => {});

  it("returns immediately on first success (no retry, no sleep)", async () => {
    const fn = vi.fn(async () => ({ data: { id: "u1" }, error: null }));
    const result = await withGoTrueRetry("createUser", fn, { sleep: noSleep });
    expect(result.error).toBeNull();
    expect(fn).toHaveBeenCalledTimes(1);
    expect(noSleep).not.toHaveBeenCalled();
  });

  it("retries on a rate-limit error then succeeds", async () => {
    const sleep = vi.fn(async () => {});
    let calls = 0;
    const fn = vi.fn(async () => {
      calls += 1;
      if (calls < 3) return { data: null, error: { status: 429 } };
      return { data: { id: "u1" }, error: null };
    });
    const result = await withGoTrueRetry("signIn", fn, { sleep, baseDelayMs: 1 });
    expect(result.error).toBeNull();
    expect(fn).toHaveBeenCalledTimes(3);
    expect(sleep).toHaveBeenCalledTimes(2);
  });

  it("returns the last (still-erroring) result after exhausting attempts", async () => {
    const sleep = vi.fn(async () => {});
    const fn = vi.fn(async () => ({
      data: null,
      error: { status: 429, message: "Request rate limit reached" },
    }));
    const result = await withGoTrueRetry("deleteUser", fn, {
      sleep,
      maxAttempts: 3,
      baseDelayMs: 1,
    });
    expect(result.error).not.toBeNull();
    expect(fn).toHaveBeenCalledTimes(3);
    // sleeps between attempts only — not after the final failed attempt
    expect(sleep).toHaveBeenCalledTimes(2);
  });

  it("does NOT retry a non-rate-limit error (returns it on first call)", async () => {
    const sleep = vi.fn(async () => {});
    const fn = vi.fn(async () => ({
      data: null,
      error: { status: 422, code: "user_already_exists" },
    }));
    const result = await withGoTrueRetry("createUser", fn, { sleep });
    expect(result.error).not.toBeNull();
    expect(fn).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("retries a THROWN retryable error, then rethrows if it never clears", async () => {
    const sleep = vi.fn(async () => {});
    const fn = vi.fn(async () => {
      throw Object.assign(new Error("Request rate limit reached"), {
        status: 429,
      });
    });
    await expect(
      withGoTrueRetry("signIn", fn, { sleep, maxAttempts: 2, baseDelayMs: 1 }),
    ).rejects.toThrow(/rate limit/i);
    expect(fn).toHaveBeenCalledTimes(2);
  });
});
