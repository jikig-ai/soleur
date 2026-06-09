import { describe, it, expect, vi } from "vitest";
import {
  isRetryableStorageError,
  withStorageRetry,
  type StorageErrorLike,
} from "@/server/storage-retry";

// Unit tests for server/storage-retry.ts — the dependency-free Supabase-Storage
// transient-retry leaf (the github-retry.ts shape). storage-js file-API methods
// are RESULT-RETURNING ({ data, error }), so the loop classifies the RETURNED
// error, never a caught exception. Backoff is asserted from an injected sleep
// mock's call args (no fake timers); attempt counts are EXACT across ALL
// attempts (2026-04-19 retry-masking learning).

describe("isRetryableStorageError — classification truth table", () => {
  it.each([500, 502, 503, 504, 429])("status %i → retryable (U1)", (status) => {
    expect(isRetryableStorageError({ message: "boom", status })).toBe(true);
  });

  it.each([400, 403, 404, 409, 413])("status %i → not retryable (U2)", (status) => {
    expect(isRetryableStorageError({ message: "boom", status })).toBe(false);
  });

  it("StorageUnknownError (network wrap, no status) → retryable (U3)", () => {
    expect(
      isRetryableStorageError({ name: "StorageUnknownError", message: "fetch failed" }),
    ).toBe(true);
  });

  it("plain { message } error (no status, no name match) → not retryable (U4)", () => {
    expect(isRetryableStorageError({ message: "db down" })).toBe(false);
  });

  it("null error → not retryable (U5)", () => {
    expect(isRetryableStorageError(null)).toBe(false);
  });
});

describe("withStorageRetry — loop semantics", () => {
  const transient: StorageErrorLike = { message: "Service Unavailable", status: 503 };

  it("success-first: returns after 1 op call, sleep never called", async () => {
    const op = vi.fn().mockResolvedValue({ data: { path: "x" }, error: null });
    const sleep = vi.fn().mockResolvedValue(undefined);
    const result = await withStorageRetry(op, { sleep });
    expect(result.error).toBeNull();
    expect(op).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("non-retryable error: returns after 1 op call, sleep never called", async () => {
    const op = vi.fn().mockResolvedValue({ data: null, error: { message: "bad", status: 400 } });
    const sleep = vi.fn().mockResolvedValue(undefined);
    const result = await withStorageRetry(op, { sleep });
    expect(result.error).toMatchObject({ status: 400 });
    expect(op).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("persistent 503: 3 op calls, sleep args [500, 1000], final result carries the error (U6)", async () => {
    const op = vi.fn().mockResolvedValue({ data: null, error: transient });
    const sleep = vi.fn().mockResolvedValue(undefined);
    const result = await withStorageRetry(op, { sleep });
    expect(op).toHaveBeenCalledTimes(3);
    expect(sleep.mock.calls.map((c) => c[0])).toEqual([500, 1000]);
    expect(result.error).toBe(transient);
  });

  it("transient-then-success: 2 op calls, onRetry called once with (1, error) (U7)", async () => {
    const op = vi
      .fn()
      .mockResolvedValueOnce({ data: null, error: transient })
      .mockResolvedValueOnce({ data: { path: "x" }, error: null });
    const sleep = vi.fn().mockResolvedValue(undefined);
    const onRetry = vi.fn();
    const result = await withStorageRetry(op, { sleep, onRetry });
    expect(result.error).toBeNull();
    expect(op).toHaveBeenCalledTimes(2);
    expect(onRetry).toHaveBeenCalledTimes(1);
    expect(onRetry).toHaveBeenCalledWith(1, transient);
    expect(sleep.mock.calls.map((c) => c[0])).toEqual([500]);
  });

  it("respects maxRetries override: maxRetries 0 → exactly 1 op call even on transient", async () => {
    const op = vi.fn().mockResolvedValue({ data: null, error: transient });
    const sleep = vi.fn().mockResolvedValue(undefined);
    await withStorageRetry(op, { sleep, maxRetries: 0 });
    expect(op).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("respects baseDelayMs override: 100 → sleep args [100, 200]", async () => {
    const op = vi.fn().mockResolvedValue({ data: null, error: transient });
    const sleep = vi.fn().mockResolvedValue(undefined);
    await withStorageRetry(op, { sleep, baseDelayMs: 100 });
    expect(sleep.mock.calls.map((c) => c[0])).toEqual([100, 200]);
  });

  it("non-StorageError throws propagate unchanged: op called once, sleep never called", async () => {
    const boom = new TypeError("programming error");
    const op = vi.fn().mockRejectedValue(boom);
    const sleep = vi.fn().mockResolvedValue(undefined);
    await expect(withStorageRetry(op, { sleep })).rejects.toBe(boom);
    expect(op).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("a throwing onRetry observer does not abort the retry loop", async () => {
    const op = vi
      .fn()
      .mockResolvedValueOnce({ data: null, error: transient })
      .mockResolvedValueOnce({ data: { path: "x" }, error: null });
    const sleep = vi.fn().mockResolvedValue(undefined);
    const onRetry = vi.fn(() => {
      throw new Error("observer bug");
    });
    const result = await withStorageRetry(op, { sleep, onRetry });
    expect(result.error).toBeNull();
    expect(op).toHaveBeenCalledTimes(2);
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  it("network-class StorageUnknownError is retried", async () => {
    const op = vi
      .fn()
      .mockResolvedValueOnce({
        data: null,
        error: { name: "StorageUnknownError", message: "fetch failed" },
      })
      .mockResolvedValueOnce({ data: { path: "x" }, error: null });
    const sleep = vi.fn().mockResolvedValue(undefined);
    const result = await withStorageRetry(op, { sleep });
    expect(result.error).toBeNull();
    expect(op).toHaveBeenCalledTimes(2);
  });
});
