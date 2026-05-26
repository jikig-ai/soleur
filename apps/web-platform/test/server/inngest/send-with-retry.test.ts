import { describe, it, expect, vi } from "vitest";

const mockLogger = vi.hoisted(() => ({
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: mockLogger,
  createChildLogger: () => mockLogger,
}));

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
