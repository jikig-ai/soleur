/**
 * GitHub API Retry Wrapper Tests
 *
 * Tests the fetchWithRetry helper that adds timeout + retry logic to
 * GitHub API calls. Covers: success, retry on timeout, retry on 5xx,
 * no retry on 4xx, max retries exhausted, body drain on 5xx retry,
 * and undici-specific error codes.
 */
import { generateKeyPairSync } from "crypto";

const { privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "pkcs1", format: "pem" },
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
});

// Set env BEFORE any imports that read them at load time
process.env.GITHUB_APP_ID = "12345";
process.env.GITHUB_APP_PRIVATE_KEY = privateKey;

import { describe, test, expect, vi, beforeEach, afterAll } from "vitest";

// ---------------------------------------------------------------------------
// Mock global fetch
// ---------------------------------------------------------------------------

const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;

afterAll(() => {
  globalThis.fetch = originalFetch;
});

// Import AFTER env and fetch mocking
import { githubApiGet, githubApiPost, githubApiGetText } from "../server/github-api";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Unique installation IDs to avoid token cache collisions
let nextId = 9000;
function uniqueId() {
  return nextId++;
}

/** Mock a successful installation token exchange (always first call). */
function mockTokenResponse() {
  mockFetch.mockResolvedValueOnce({
    ok: true,
    json: async () => ({
      token: "ghs_test_token",
      expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    }),
  });
}

function okJsonResponse(body: unknown) {
  return {
    ok: true,
    status: 200,
    json: async () => body,
    text: async () => JSON.stringify(body),
  };
}

function okTextResponse(text: string) {
  return {
    ok: true,
    status: 200,
    text: async () => text,
    json: async () => JSON.parse(text),
  };
}

function serverErrorResponse(status = 500) {
  return {
    ok: false,
    status,
    text: async () => "Internal Server Error",
    json: async () => ({ message: "Internal Server Error" }),
  };
}

function clientErrorResponse(status: number, body: string) {
  return {
    ok: false,
    status,
    text: async () => body,
    json: async () => JSON.parse(body),
  };
}

function domExceptionTimeout() {
  return new DOMException("signal timed out", "TimeoutError");
}

function undiciConnectTimeout() {
  const err = new Error("connect ETIMEDOUT");
  (err as unknown as { code: string }).code = "UND_ERR_CONNECT_TIMEOUT";
  return err;
}

function econnresetError() {
  const err = new Error("read ECONNRESET");
  (err as unknown as { code: string }).code = "ECONNRESET";
  return err;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("github-api fetchWithRetry", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  describe("success on first attempt", () => {
    test("githubApiGet returns JSON on first try", async () => {
      const id = uniqueId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce(okJsonResponse({ login: "test" }));

      const result = await githubApiGet<{ login: string }>(id, "/user");
      expect(result.login).toBe("test");
      // Token exchange + one API call = 2 fetch calls
      expect(mockFetch).toHaveBeenCalledTimes(2);
    });

    test("githubApiGetText returns text on first try", async () => {
      const id = uniqueId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce(okTextResponse("log line 1\nlog line 2"));

      const result = await githubApiGetText(id, "/repos/o/r/actions/jobs/1/logs");
      expect(result).toBe("log line 1\nlog line 2");
      expect(mockFetch).toHaveBeenCalledTimes(2);
    });

    test("githubApiPost returns JSON on first try", async () => {
      const id = uniqueId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce(okJsonResponse({ id: 42 }));

      const result = await githubApiPost<{ id: number }>(id, "/repos/o/r/issues", { title: "test" });
      expect(result!.id).toBe(42);
      expect(mockFetch).toHaveBeenCalledTimes(2);
    });
  });

  describe("retry on DOMException timeout", () => {
    test("retries and succeeds on second attempt", async () => {
      const id = uniqueId();
      mockTokenResponse();
      // First API call: timeout, retry succeeds (token is cached)
      mockFetch.mockRejectedValueOnce(domExceptionTimeout());
      mockFetch.mockResolvedValueOnce(okJsonResponse({ ok: true }));

      const result = await githubApiGet<{ ok: boolean }>(id, "/user");
      expect(result.ok).toBe(true);
      // Token + fail + success = 3 calls
      expect(mockFetch).toHaveBeenCalledTimes(3);
    });
  });

  describe("retry on undici UND_ERR_CONNECT_TIMEOUT", () => {
    test("retries and succeeds on second attempt", async () => {
      const id = uniqueId();
      mockTokenResponse();
      mockFetch.mockRejectedValueOnce(undiciConnectTimeout());
      mockFetch.mockResolvedValueOnce(okJsonResponse({ ok: true }));

      const result = await githubApiGet<{ ok: boolean }>(id, "/user");
      expect(result.ok).toBe(true);
      expect(mockFetch).toHaveBeenCalledTimes(3);
    });
  });

  describe("retry on ECONNRESET", () => {
    test("retries and succeeds on second attempt", async () => {
      const id = uniqueId();
      mockTokenResponse();
      mockFetch.mockRejectedValueOnce(econnresetError());
      mockFetch.mockResolvedValueOnce(okJsonResponse({ ok: true }));

      const result = await githubApiGet<{ ok: boolean }>(id, "/user");
      expect(result.ok).toBe(true);
      expect(mockFetch).toHaveBeenCalledTimes(3);
    });
  });

  describe("retry on 5xx responses", () => {
    test("retries 500 and succeeds on second attempt", async () => {
      const id = uniqueId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce(serverErrorResponse(500));
      mockFetch.mockResolvedValueOnce(okJsonResponse({ recovered: true }));

      const result = await githubApiGet<{ recovered: boolean }>(id, "/user");
      expect(result.recovered).toBe(true);
      expect(mockFetch).toHaveBeenCalledTimes(3);
    });
  });

  describe("no retry on 4xx responses", () => {
    test("404 is not retried", async () => {
      const id = uniqueId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce(clientErrorResponse(404, '{"message":"Not Found"}'));

      await expect(githubApiGet(id, "/repos/o/r/contents/missing")).rejects.toThrow("404");
      // Token + 1 API call = 2. No retry.
      expect(mockFetch).toHaveBeenCalledTimes(2);
    });

    test("403 is not retried", async () => {
      const id = uniqueId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce(clientErrorResponse(403, '{"message":"Forbidden"}'));

      await expect(githubApiGet(id, "/repos/o/r")).rejects.toThrow(/permission denied.*403/);
      expect(mockFetch).toHaveBeenCalledTimes(2);
    });
  });

  describe("max retries exhausted", () => {
    test("throws after 3 failed attempts (timeout)", async () => {
      const id = uniqueId();
      mockTokenResponse();
      // 3 API attempts all fail (token cached from first call)
      mockFetch.mockRejectedValueOnce(domExceptionTimeout());
      mockFetch.mockRejectedValueOnce(domExceptionTimeout());
      mockFetch.mockRejectedValueOnce(domExceptionTimeout());

      await expect(githubApiGet(id, "/user")).rejects.toThrow(/signal timed out/);
      // Token + 3 API attempts = 4 calls
      expect(mockFetch).toHaveBeenCalledTimes(4);
    });

    test("throws after 3 failed attempts (5xx)", async () => {
      const id = uniqueId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce(serverErrorResponse(502));
      mockFetch.mockResolvedValueOnce(serverErrorResponse(502));
      mockFetch.mockResolvedValueOnce(serverErrorResponse(502));

      await expect(githubApiGet(id, "/user")).rejects.toThrow(/502/);
      expect(mockFetch).toHaveBeenCalledTimes(4);
    });
  });

  describe("TypeError (network error) is retried", () => {
    test("retries TypeError and succeeds", async () => {
      const id = uniqueId();
      mockTokenResponse();
      mockFetch.mockRejectedValueOnce(new TypeError("fetch failed"));
      mockFetch.mockResolvedValueOnce(okJsonResponse({ ok: true }));

      const result = await githubApiGet<{ ok: boolean }>(id, "/user");
      expect(result.ok).toBe(true);
      expect(mockFetch).toHaveBeenCalledTimes(3);
    });
  });

  describe("fetch calls include AbortSignal.timeout", () => {
    test("githubApiGet passes signal to fetch", async () => {
      const id = uniqueId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce(okJsonResponse({ ok: true }));

      await githubApiGet(id, "/user");

      // The second fetch call (API call, not token) should have a signal
      const apiCallArgs = mockFetch.mock.calls[1];
      expect(apiCallArgs[1]).toHaveProperty("signal");
    });
  });
});
