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
import {
  createRepo,
  getInstallationAccount,
  GitHubApiError,
} from "../server/github-app";

describe("createRepo", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  // Use unique installationId per test to avoid token cache interference
  let nextInstallationId = 8000;
  function uniqueInstallationId() {
    return nextInstallationId++;
  }

  function mockInstallationAccountResponse(account: {
    login: string;
    id: number;
    type: string;
  }) {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ account }),
    });
  }

  function mockTokenResponse() {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        token: "ghs_test_token",
        expires_at: new Date(Date.now() + 3600_000).toISOString(),
      }),
    });
  }

  test("org installation: routes to /orgs/{org}/repos", async () => {
    const installationId = uniqueInstallationId();

    // Mock 1: GET /app/installations/{id} — getInstallationAccount
    mockInstallationAccountResponse({
      login: "my-org",
      id: 1,
      type: "Organization",
    });

    // Mock 2: POST /app/installations/{id}/access_tokens
    mockTokenResponse();

    // Mock 3: POST /orgs/my-org/repos — repo creation
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({
        name: "new-repo",
        full_name: "my-org/new-repo",
        private: true,
        description: "Knowledge base managed by Soleur",
        language: null,
        updated_at: new Date().toISOString(),
        html_url: "https://github.com/my-org/new-repo",
      }),
    });

    const result = await createRepo(installationId, "new-repo", true);

    expect(result).toEqual({
      repoUrl: "https://github.com/my-org/new-repo",
      fullName: "my-org/new-repo",
    });

    // Verify the repo creation URL is /orgs/my-org/repos
    const repoCreateCall = mockFetch.mock.calls[2];
    expect(repoCreateCall[0]).toBe(
      "https://api.github.com/orgs/my-org/repos",
    );
  });

  test("user installation: routes to /user/repos", async () => {
    const installationId = uniqueInstallationId();

    // Mock 1: GET /app/installations/{id} — getInstallationAccount
    mockInstallationAccountResponse({
      login: "alice",
      id: 2,
      type: "User",
    });

    // Mock 2: POST /app/installations/{id}/access_tokens
    mockTokenResponse();

    // Mock 3: POST /user/repos — repo creation
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({
        name: "my-repo",
        full_name: "alice/my-repo",
        private: false,
        description: "Knowledge base managed by Soleur",
        language: null,
        updated_at: new Date().toISOString(),
        html_url: "https://github.com/alice/my-repo",
      }),
    });

    const result = await createRepo(installationId, "my-repo", false);

    expect(result).toEqual({
      repoUrl: "https://github.com/alice/my-repo",
      fullName: "alice/my-repo",
    });

    // Verify the repo creation URL is /user/repos
    const repoCreateCall = mockFetch.mock.calls[2];
    expect(repoCreateCall[0]).toBe("https://api.github.com/user/repos");
  });

  test("throws GitHubApiError with statusCode 422 for duplicate name", async () => {
    const installationId = uniqueInstallationId();

    // Mock 1: GET /app/installations/{id} — org account
    mockInstallationAccountResponse({
      login: "my-org",
      id: 1,
      type: "Organization",
    });

    // Mock 2: POST /app/installations/{id}/access_tokens
    mockTokenResponse();

    // Mock 3: POST /orgs/my-org/repos — 422 error
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 422,
      text: async () =>
        JSON.stringify({
          message: "Validation Failed",
          errors: [{ message: "name already exists on this account" }],
        }),
    });

    await expect(
      createRepo(installationId, "existing-repo", true),
    ).rejects.toSatisfy((err: unknown) => {
      expect(err).toBeInstanceOf(GitHubApiError);
      expect((err as GitHubApiError).statusCode).toBe(422);
      expect((err as GitHubApiError).message).toMatch(
        /name already exists/,
      );
      return true;
    });
  });

  test("throws GitHubApiError with statusCode 403 for permission denied", async () => {
    const installationId = uniqueInstallationId();

    // Mock 1: GET /app/installations/{id} — org account
    mockInstallationAccountResponse({
      login: "my-org",
      id: 1,
      type: "Organization",
    });

    // Mock 2: POST /app/installations/{id}/access_tokens
    mockTokenResponse();

    // Mock 3: POST /orgs/my-org/repos — 403 error
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 403,
      text: async () =>
        JSON.stringify({
          message: "Resource not accessible by integration",
        }),
    });

    await expect(
      createRepo(installationId, "new-repo", true),
    ).rejects.toSatisfy((err: unknown) => {
      expect(err).toBeInstanceOf(GitHubApiError);
      expect((err as GitHubApiError).statusCode).toBe(403);
      return true;
    });
  });

  test("throws on installation 404", async () => {
    const installationId = uniqueInstallationId();

    // Mock 1: GET /app/installations/{id} — 404
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404,
      json: async () => ({ message: "Not Found" }),
    });

    await expect(
      createRepo(installationId, "some-repo", true),
    ).rejects.toThrow(/Installation not found/);
  });
});

describe("getInstallationAccount", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  let nextInstallationId = 8500;
  function uniqueInstallationId() {
    return nextInstallationId++;
  }

  test("returns account for valid installation", async () => {
    const installationId = uniqueInstallationId();

    // Mock: GET /app/installations/{id}
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        account: { login: "my-org", id: 42, type: "Organization" },
      }),
    });

    const account = await getInstallationAccount(installationId);

    expect(account).toEqual({
      login: "my-org",
      id: 42,
      type: "Organization",
    });

    // Verify the correct URL was called
    const call = mockFetch.mock.calls[0];
    expect(call[0]).toBe(
      `https://api.github.com/app/installations/${installationId}`,
    );
  });

  test("throws on 404", async () => {
    const installationId = uniqueInstallationId();

    // Mock: GET /app/installations/{id} — 404
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404,
      json: async () => ({ message: "Not Found" }),
    });

    await expect(
      getInstallationAccount(installationId),
    ).rejects.toThrow(/Installation not found/);
  });

  test("throws on no account in response", async () => {
    const installationId = uniqueInstallationId();

    // Mock: GET /app/installations/{id} — success but no account
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ account: null }),
    });

    await expect(
      getInstallationAccount(installationId),
    ).rejects.toThrow(/Installation has no account/);
  });

  test("throws on non-404 error status", async () => {
    const installationId = uniqueInstallationId();

    // Mock: GET /app/installations/{id} — 500
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: async () => ({ message: "Internal Server Error" }),
    });

    await expect(
      getInstallationAccount(installationId),
    ).rejects.toThrow(/Failed to fetch installation: 500/);
  });
});
