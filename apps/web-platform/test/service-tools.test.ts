import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

// Tests import the pure functions from service-tools.ts (zero SDK deps).
// Each function takes an API key + inputs and returns a PlausibleResult.

import {
  plausibleCreateSite,
  plausibleAddGoal,
  plausibleGetStats,
  type PlausibleResult,
} from "../server/service-tools";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function mockFetchResponse(status: number, body: unknown, ok?: boolean) {
  return vi.fn().mockResolvedValue({
    ok: ok ?? (status >= 200 && status < 300),
    status,
    json: () => Promise.resolve(body),
  });
}

function mockFetchJsonError(status: number) {
  return vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.reject(new Error("invalid json")),
  });
}

function mockFetchTimeout() {
  return vi.fn().mockRejectedValue(new DOMException("signal timed out", "TimeoutError"));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("plausibleCreateSite", () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  test("creates site successfully", async () => {
    const responseBody = { domain: "example.com", timezone: "UTC" };
    globalThis.fetch = mockFetchResponse(200, responseBody);

    const result = await plausibleCreateSite("test-api-key", "example.com");

    expect(result.success).toBe(true);
    expect(result.data).toEqual(responseBody);
    expect(globalThis.fetch).toHaveBeenCalledOnce();

    const [url, opts] = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(url).toBe("https://plausible.io/api/v1/sites");
    expect(opts.method).toBe("POST");
    expect(opts.headers.Authorization).toBe("Bearer test-api-key");
  });

  test("returns error on 401 (invalid token)", async () => {
    globalThis.fetch = mockFetchResponse(401, { error: "Unauthorized" }, false);

    const result = await plausibleCreateSite("bad-key", "example.com");

    expect(result.success).toBe(false);
    expect(result.error).toContain("401");
  });

  test("returns error on timeout", async () => {
    globalThis.fetch = mockFetchTimeout();

    const result = await plausibleCreateSite("test-api-key", "example.com");

    expect(result.success).toBe(false);
    expect(result.error).toContain("timeout");
  });

  test("returns error on non-JSON response (HTML error page with 200)", async () => {
    globalThis.fetch = mockFetchJsonError(200);

    const result = await plausibleCreateSite("test-api-key", "example.com");

    expect(result.success).toBe(false);
    expect(result.error).toContain("Non-JSON");
  });

  test("rejects invalid domain format", async () => {
    globalThis.fetch = mockFetchResponse(200, {});

    const result = await plausibleCreateSite("test-api-key", "../admin");

    expect(result.success).toBe(false);
    expect(result.error).toContain("Invalid domain");
    // fetch should NOT have been called — validation rejects before API call
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  test("does not expose API key in error messages", async () => {
    globalThis.fetch = mockFetchResponse(500, { error: "Server Error" }, false);

    const result = await plausibleCreateSite("sk-secret-key-123", "example.com");

    expect(result.success).toBe(false);
    expect(result.error).not.toContain("sk-secret-key-123");
  });
});

describe("plausibleAddGoal", () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  test("adds event goal successfully", async () => {
    const responseBody = { goal_type: "event", event_name: "Signup" };
    globalThis.fetch = mockFetchResponse(200, responseBody);

    const result = await plausibleAddGoal("test-api-key", "example.com", "event", "Signup");

    expect(result.success).toBe(true);
    expect(result.data).toEqual(responseBody);

    const [url, opts] = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(url).toBe("https://plausible.io/api/v1/sites/goals");
    expect(opts.method).toBe("PUT");
  });

  test("rejects site_id with path traversal characters", async () => {
    const result = await plausibleAddGoal("test-api-key", "../admin", "event", "Signup");

    expect(result.success).toBe(false);
    expect(result.error).toContain("Invalid site ID");
  });

  test("rejects invalid goal_type", async () => {
    const result = await plausibleAddGoal("test-api-key", "example.com", "invalid" as "event", "Test");

    expect(result.success).toBe(false);
    expect(result.error).toContain("goal_type");
  });

  test("handles PUT upsert idempotency (success on repeated call)", async () => {
    const responseBody = { goal_type: "event", event_name: "Signup" };
    globalThis.fetch = mockFetchResponse(200, responseBody);

    const result1 = await plausibleAddGoal("test-api-key", "example.com", "event", "Signup");
    const result2 = await plausibleAddGoal("test-api-key", "example.com", "event", "Signup");

    expect(result1.success).toBe(true);
    expect(result2.success).toBe(true);
  });
});

describe("plausibleGetStats", () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  test("gets stats successfully", async () => {
    const responseBody = { results: { visitors: { value: 100 } } };
    globalThis.fetch = mockFetchResponse(200, responseBody);

    const result = await plausibleGetStats("test-api-key", "example.com", "30d");

    expect(result.success).toBe(true);
    expect(result.data).toEqual(responseBody);

    const [url] = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(url).toContain("site_id=example.com");
    expect(url).toContain("period=30d");
  });

  test("rejects site_id with path traversal characters", async () => {
    const result = await plausibleGetStats("test-api-key", "../../etc", "day");

    expect(result.success).toBe(false);
    expect(result.error).toContain("Invalid site ID");
  });

  test("returns error on non-JSON response", async () => {
    globalThis.fetch = mockFetchJsonError(200);

    const result = await plausibleGetStats("test-api-key", "example.com", "day");

    expect(result.success).toBe(false);
    expect(result.error).toContain("Non-JSON");
  });
});
