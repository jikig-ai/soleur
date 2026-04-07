// Generate a real RSA key for JWT signing during tests.
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
// Mock global fetch for GitHub API calls
// ---------------------------------------------------------------------------

const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;

afterAll(() => {
  globalThis.fetch = originalFetch;
});

// Import AFTER env and fetch mocking
import { findInstallationForLogin } from "../server/github-app";

describe("findInstallationForLogin", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  test("returns installation ID when app is installed on user account", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        id: 42,
        account: { login: "testuser", id: 1, type: "User" },
      }),
    });

    const result = await findInstallationForLogin("testuser");

    expect(result).toBe(42);
    expect(mockFetch).toHaveBeenCalledOnce();
    expect(mockFetch.mock.calls[0][0]).toContain(
      "/users/testuser/installation",
    );
  });

  test("returns null when no personal or org installation found", async () => {
    // Personal check: 404
    mockFetch.mockResolvedValueOnce({ ok: false, status: 404 });
    // Org fallback: no installations
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ([]),
    });

    const result = await findInstallationForLogin("noinstall-user");

    expect(result).toBeNull();
  });

  test("returns null on unexpected API error with no org installations", async () => {
    mockFetch.mockResolvedValueOnce({ ok: false, status: 500 });
    // Org fallback: list fails too
    mockFetch.mockResolvedValueOnce({ ok: false, status: 500 });

    const result = await findInstallationForLogin("error-user");

    expect(result).toBeNull();
  });

  test("returns null when response has no id field", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ account: { login: "testuser" } }),
    });
    // Org fallback: no installations
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ([]),
    });

    const result = await findInstallationForLogin("testuser");

    expect(result).toBeNull();
  });

  test("finds org installation when user is a member", async () => {
    // Personal check: 404
    mockFetch.mockResolvedValueOnce({ ok: false, status: 404 });
    // Org fallback: list installations
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ([
        { id: 99, account: { login: "my-org", type: "Organization" } },
      ]),
    });
    // Membership check: 204 = is a member
    mockFetch.mockResolvedValueOnce({ status: 204 });

    const result = await findInstallationForLogin("orgmember");

    expect(result).toBe(99);
    expect(mockFetch.mock.calls[2][0]).toContain("/orgs/my-org/members/orgmember");
  });

  test("skips non-org installations in fallback", async () => {
    // Personal check: 404
    mockFetch.mockResolvedValueOnce({ ok: false, status: 404 });
    // Org fallback: only User-type installations
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ([
        { id: 50, account: { login: "otheruser", type: "User" } },
      ]),
    });

    const result = await findInstallationForLogin("testuser");

    expect(result).toBeNull();
    // Only 2 calls: personal check + list installations (no membership checks)
    expect(mockFetch).toHaveBeenCalledTimes(2);
  });

  test("encodes special characters in login", async () => {
    mockFetch.mockResolvedValueOnce({ ok: false, status: 404 });
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ([]),
    });

    await findInstallationForLogin("user with spaces");

    expect(mockFetch.mock.calls[0][0]).toContain(
      "/users/user%20with%20spaces/installation",
    );
  });
});
