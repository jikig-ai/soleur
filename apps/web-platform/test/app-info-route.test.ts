// Tests for getAppSlug() and GET /api/repo/app-info
//
// getAppSlug() should:
//   1. Call GET /app with JWT and return the slug field
//   2. Cache the result on second call (no extra API request)
//   3. Fall back to NEXT_PUBLIC_GITHUB_APP_SLUG when GITHUB_APP_ID is not set
//
// GET /api/repo/app-info should:
//   4. Return 401 for unauthenticated users
//   5. Return { slug } for authenticated users

import { generateKeyPairSync } from "crypto";

const { privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "pkcs1", format: "pem" },
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
});

// Set env BEFORE any imports that read them at load time
process.env.GITHUB_APP_ID = "99999";
process.env.GITHUB_APP_PRIVATE_KEY = privateKey;
process.env.NEXT_PUBLIC_GITHUB_APP_SLUG = "fallback-slug";

import { describe, test, expect, vi, beforeEach, afterAll } from "vitest";

// ---------------------------------------------------------------------------
// Mock global fetch for GitHub API calls
// ---------------------------------------------------------------------------

const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;

afterAll(() => {
  globalThis.fetch = originalFetch;
});

// ---------------------------------------------------------------------------
// getAppSlug — unit tests
// ---------------------------------------------------------------------------

import { getAppSlug, _resetSlugCacheForTesting } from "../server/github-app";

describe("getAppSlug", () => {
  beforeEach(() => {
    mockFetch.mockReset();
    _resetSlugCacheForTesting();
  });

  test("calls GET /app with JWT and returns the slug field", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ slug: "soleur-ai", id: 99999 }),
    });

    const slug = await getAppSlug();
    expect(slug).toBe("soleur-ai");

    // Verify the fetch was called with the correct URL and auth header
    expect(mockFetch).toHaveBeenCalledTimes(1);
    const [url, options] = mockFetch.mock.calls[0];
    expect(url).toBe("https://api.github.com/app");
    expect(options.headers.Authorization).toMatch(/^Bearer /);
  });

  test("returns cached value on second call without making another API request", async () => {
    // Populate cache first within this test (no cross-test dependency)
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ slug: "soleur-ai", id: 99999 }),
    });
    await getAppSlug();
    mockFetch.mockReset();

    const slug = await getAppSlug();
    expect(slug).toBe("soleur-ai");
    expect(mockFetch).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// getAppSlug fallback — separate describe with different env
// ---------------------------------------------------------------------------

describe("getAppSlug fallback when GITHUB_APP_ID is not set", () => {
  let savedAppId: string | undefined;
  let savedPrivateKey: string | undefined;

  beforeEach(() => {
    savedAppId = process.env.GITHUB_APP_ID;
    savedPrivateKey = process.env.GITHUB_APP_PRIVATE_KEY;
  });

  afterAll(() => {
    process.env.GITHUB_APP_ID = savedAppId;
    process.env.GITHUB_APP_PRIVATE_KEY = savedPrivateKey;
  });

  test("returns NEXT_PUBLIC_GITHUB_APP_SLUG env var instead of throwing", async () => {
    _resetSlugCacheForTesting();
    delete process.env.GITHUB_APP_ID;
    delete process.env.GITHUB_APP_PRIVATE_KEY;

    const slug = await getAppSlug();
    expect(slug).toBe("fallback-slug");
    expect(mockFetch).not.toHaveBeenCalled();
  });
});
