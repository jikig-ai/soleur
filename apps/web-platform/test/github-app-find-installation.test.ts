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

  test("returns null when app is not installed (404)", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404,
    });

    const result = await findInstallationForLogin("noinstall-user");

    expect(result).toBeNull();
  });

  test("returns null on unexpected API error", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
    });

    const result = await findInstallationForLogin("error-user");

    expect(result).toBeNull();
  });

  test("returns null when response has no id field", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ account: { login: "testuser" } }),
    });

    const result = await findInstallationForLogin("testuser");

    expect(result).toBeNull();
  });

  test("encodes special characters in login", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404,
    });

    await findInstallationForLogin("user with spaces");

    expect(mockFetch.mock.calls[0][0]).toContain(
      "/users/user%20with%20spaces/installation",
    );
  });
});
