import { describe, it, expect, vi, beforeEach } from "vitest";

const mockLogger = vi.hoisted(() => ({
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: mockLogger,
  createChildLogger: () => mockLogger,
}));

const mockSentry = vi.hoisted(() => ({ captureException: vi.fn() }));

// Wholesale factory, matching the house convention. Safe HERE specifically because
// `@/server/logger` is mocked above — logger.ts is the only module in this import graph
// that consumes Sentry's other exports, so nothing is left to break on the omission.
vi.mock("@sentry/nextjs", () => mockSentry);

import {
  sendInngestWithRetry,
  isTransientFetchError,
} from "@/server/inngest/send-with-retry";

describe("isTransientFetchError", () => {
  it("returns true for TypeError: fetch failed", () => {
    expect(isTransientFetchError(new TypeError("fetch failed"))).toBe(true);
  });

  it("returns true for DOMException TimeoutError", () => {
    const err = new DOMException("signal timed out", "TimeoutError");
    expect(isTransientFetchError(err)).toBe(true);
  });

  it("returns true for ECONNREFUSED", () => {
    const err = Object.assign(new Error("connect ECONNREFUSED"), {
      code: "ECONNREFUSED",
    });
    expect(isTransientFetchError(err)).toBe(true);
  });

  it("returns true for ECONNRESET", () => {
    const err = Object.assign(new Error("socket hang up"), {
      code: "ECONNRESET",
    });
    expect(isTransientFetchError(err)).toBe(true);
  });

  it("returns true for UND_ERR_CONNECT_TIMEOUT", () => {
    const err = Object.assign(new Error("timeout"), {
      code: "UND_ERR_CONNECT_TIMEOUT",
    });
    expect(isTransientFetchError(err)).toBe(true);
  });

  it("returns true for ENOTFOUND", () => {
    const err = Object.assign(new Error("getaddrinfo ENOTFOUND"), {
      code: "ENOTFOUND",
    });
    expect(isTransientFetchError(err)).toBe(true);
  });

  it("returns true for ENETDOWN", () => {
    const err = Object.assign(new Error("network is down"), {
      code: "ENETDOWN",
    });
    expect(isTransientFetchError(err)).toBe(true);
  });

  it("returns false for generic Error", () => {
    expect(isTransientFetchError(new Error("something else"))).toBe(false);
  });

  it("returns false for non-Error values", () => {
    expect(isTransientFetchError("string error")).toBe(false);
    expect(isTransientFetchError(null)).toBe(false);
  });
});

describe("sendInngestWithRetry", () => {
  it("succeeds on first attempt without retrying", async () => {
    const fn = vi.fn().mockResolvedValue(undefined);
    await sendInngestWithRetry(fn, { feature: "test" });
    expect(fn).toHaveBeenCalledTimes(1);
    expect(mockLogger.warn).not.toHaveBeenCalled();
  });

  it("retries on transient fetch error and succeeds", async () => {
    const fn = vi
      .fn()
      .mockRejectedValueOnce(new TypeError("fetch failed"))
      .mockResolvedValueOnce(undefined);
    await sendInngestWithRetry(fn, { feature: "test" });
    expect(fn).toHaveBeenCalledTimes(2);
    expect(mockLogger.warn).toHaveBeenCalledTimes(1);
  });

  it("exhausts retries and throws the last error", async () => {
    const err = new TypeError("fetch failed");
    const fn = vi.fn().mockRejectedValue(err);
    await expect(
      sendInngestWithRetry(fn, { feature: "test" }),
    ).rejects.toThrow("fetch failed");
    expect(fn).toHaveBeenCalledTimes(3);
  });

  it("does not retry non-transient errors", async () => {
    const fn = vi.fn().mockRejectedValue(new Error("auth failed"));
    await expect(
      sendInngestWithRetry(fn, { feature: "test" }),
    ).rejects.toThrow("auth failed");
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("includes context fields in warn log", async () => {
    const fn = vi
      .fn()
      .mockRejectedValueOnce(new TypeError("fetch failed"))
      .mockResolvedValueOnce(undefined);
    await sendInngestWithRetry(fn, {
      feature: "github-webhook",
      deliveryId: "d-123",
    });
    expect(mockLogger.warn).toHaveBeenCalledWith(
      expect.objectContaining({
        attempt: 1,
        maxAttempts: 3,
        feature: "github-webhook",
        deliveryId: "d-123",
      }),
      expect.stringContaining("1/3"),
    );
  });
});

// --- #7144 finding 5: the terminal failure must reach a queryable signal -------------
//
// Every test above asserts only that the error is thrown. Nothing asserted that the
// failure is OBSERVABLE, and it was not: the sole logger.warn is gated on
// `attempt < MAX_RETRIES && isTransientFetchError(err)`, so the final attempt emitted
// nothing and rethrew bare. Two consequences, both measured in the #7144 review:
//
//   - A 401 (the shape a post-reconcile key mismatch produces) matches none of
//     isTransientFetchError's cases, so it never retries AND never warns. Zero rows.
//   - The plan's own econnrefused column therefore drops to 0 after a repoint — which
//     a responder reads as FIXED — while send_failed keeps climbing.
//
// The route-level `Sentry.captureException(err, { tags: { op: "inngest-send" } })` does
// not cover it either: the preceding `logger.error({ err })` mirrors to Sentry first via
// the pino hook, which marks that Error instance already-captured, so the tagged call
// early-returns. That is the mechanism behind the measured 0 issues for op:inngest-send.
// Capturing a WRAPPER (a distinct instance carrying `cause`) is what survives that dedup,
// and linkedErrorsIntegration walks `cause` so the underlying chain is preserved.
describe("sendInngestWithRetry terminal-failure diagnosability (#7144 finding 5)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // A 401 from inngest: an Error with no `code`, so isTransientFetchError is false.
  const authError = () => new Error("401 Unauthorized: invalid signing key");

  it("emits a queryable error row for a non-transient failure", async () => {
    const err = authError();
    await expect(
      sendInngestWithRetry(vi.fn().mockRejectedValue(err), {
        feature: "resend-inbound-webhook",
        deliveryId: "svix-1",
      }),
    ).rejects.toThrow(err);

    expect(mockLogger.error).toHaveBeenCalledWith(
      expect.objectContaining({
        feature: "resend-inbound-webhook",
        deliveryId: "svix-1",
        err,
      }),
      expect.stringContaining("inngest.send"),
    );
  });

  it("captures the failure tagged op=inngest-send", async () => {
    await expect(
      sendInngestWithRetry(vi.fn().mockRejectedValue(authError()), {
        feature: "resend-inbound-webhook",
      }),
    ).rejects.toThrow();

    expect(mockSentry.captureException).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        tags: expect.objectContaining({
          feature: "resend-inbound-webhook",
          op: "inngest-send",
        }),
      }),
    );
  });

  // The sharp one. Capturing the ORIGINAL instance is what the route already does and
  // what silently no-ops once anything has mirrored it. A distinct wrapper is the only
  // form that survives, and `cause` is what keeps the undici chain attached.
  it("captures a WRAPPER carrying the original as cause, not the thrown instance", async () => {
    const err = authError();
    await expect(
      sendInngestWithRetry(vi.fn().mockRejectedValue(err), { feature: "f" }),
    ).rejects.toThrow(err);

    const captured = mockSentry.captureException.mock.calls[0]?.[0] as Error;
    expect(captured).toBeInstanceOf(Error);
    expect(captured).not.toBe(err);
    expect((captured as Error & { cause?: unknown }).cause).toBe(err);
  });

  // The actual #7144 shape: ECONNREFUSED on every attempt for ~3 days. It retried into a
  // closed port and the FINAL attempt emitted nothing at all.
  it("emits on an EXHAUSTED transient failure, not just a non-transient one", async () => {
    const err = Object.assign(new Error("connect ECONNREFUSED 10.0.1.40:8288"), {
      code: "ECONNREFUSED",
    });
    const fn = vi.fn().mockRejectedValue(err);

    await expect(
      sendInngestWithRetry(fn, { feature: "resend-inbound-webhook" }),
    ).rejects.toThrow(err);

    expect(fn).toHaveBeenCalledTimes(3);
    expect(mockLogger.error).toHaveBeenCalledTimes(1);
    expect(mockSentry.captureException).toHaveBeenCalledTimes(1);
  });

  it("still rethrows the ORIGINAL error so callers' handling is unchanged", async () => {
    const err = authError();
    await expect(
      sendInngestWithRetry(vi.fn().mockRejectedValue(err), { feature: "f" }),
    ).rejects.toBe(err);
  });

  it("stays silent on success", async () => {
    await sendInngestWithRetry(vi.fn().mockResolvedValue(undefined), { feature: "f" });
    expect(mockLogger.error).not.toHaveBeenCalled();
    expect(mockSentry.captureException).not.toHaveBeenCalled();
  });
});
