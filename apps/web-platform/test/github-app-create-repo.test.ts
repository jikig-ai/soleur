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
  KB_TEMPLATE_NAME,
  KB_TEMPLATE_OWNER,
} from "../server/github-app";
import { loadGithubFixture } from "./fixtures/github/load";

// Resolve a fetch call by URL substring rather than positional index, so
// inserting a preflight call (cache miss, retry, etc.) won't silently shift
// assertions onto the wrong call.
function findFetchCall(urlSubstring: string): [string, RequestInit] {
  const match = mockFetch.mock.calls.find((c) =>
    String(c[0]).includes(urlSubstring),
  );
  if (!match) {
    throw new Error(
      `No fetch call observed against URL containing "${urlSubstring}". Calls: ${mockFetch.mock.calls.map((c) => c[0]).join(", ")}`,
    );
  }
  return match as [string, RequestInit];
}

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
    // Body shape sourced from the synthesized installation fixture; the test's
    // account fields override the canonical synthetic ones (the per-test
    // login/id/type are load-bearing for routing assertions).
    const base =
      account.type === "Organization"
        ? loadGithubFixture<{ account: object }>("installation-account-org")
        : loadGithubFixture<{ account: object }>("installation-account-user");
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ ...base, account }),
    });
  }

  function mockTokenResponse() {
    const body = loadGithubFixture<{ token: string; expires_at: string }>(
      "installation-access-token",
    );
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        ...body,
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
        ...loadGithubFixture("repo-create-201"),
        name: "new-repo",
        full_name: "my-org/new-repo",
        private: true,
        html_url: "https://github.com/my-org/new-repo",
      }),
    });

    const result = await createRepo(installationId, "new-repo", true);

    expect(result).toEqual({
      repoUrl: "https://github.com/my-org/new-repo",
      fullName: "my-org/new-repo",
    });

    // Verify the repo creation URL is /orgs/my-org/repos
    const [repoCreateUrl] = findFetchCall("/orgs/my-org/repos");
    expect(repoCreateUrl).toBe("https://api.github.com/orgs/my-org/repos");
  });

  test("user installation: routes to template /generate", async () => {
    const installationId = uniqueInstallationId();

    // Mock 1: GET /app/installations/{id} — getInstallationAccount
    mockInstallationAccountResponse({
      login: "alice",
      id: 2,
      type: "User",
    });

    // Mock 2: POST /app/installations/{id}/access_tokens
    mockTokenResponse();

    // Mock 3: POST /repos/jikig-ai/kb-template/generate — repo creation
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({
        ...loadGithubFixture("template-generate-201"),
        name: "my-repo",
        full_name: "alice/my-repo",
        private: true,
        html_url: "https://github.com/alice/my-repo",
      }),
    });

    const result = await createRepo(installationId, "my-repo", true);

    expect(result).toEqual({
      repoUrl: "https://github.com/alice/my-repo",
      fullName: "alice/my-repo",
    });

    // Verify the repo creation URL is /repos/{KB_TEMPLATE_OWNER}/{KB_TEMPLATE_NAME}/generate
    const expectedUrl = `https://api.github.com/repos/${KB_TEMPLATE_OWNER}/${KB_TEMPLATE_NAME}/generate`;
    const [generateUrl, generateInit] = findFetchCall("/generate");
    expect(generateUrl).toBe(expectedUrl);

    // Verify load-bearing body fields. objectContaining tolerates harmless
    // future additions (auto_init, etc.) without flipping the assertion.
    const body = JSON.parse(generateInit.body as string);
    expect(body).toEqual(
      expect.objectContaining({
        owner: "alice",
        name: "my-repo",
        private: true,
        description: "Knowledge base managed by Soleur",
      }),
    );
    expect(body.include_all_branches).toBe(false);
  });

  test("user installation: forwards private:false when isPrivate=false", async () => {
    const installationId = uniqueInstallationId();

    mockInstallationAccountResponse({
      login: "bob",
      id: 3,
      type: "User",
    });
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({
        ...loadGithubFixture("template-generate-201"),
        name: "public-repo",
        full_name: "bob/public-repo",
        private: false,
        html_url: "https://github.com/bob/public-repo",
      }),
    });

    await createRepo(installationId, "public-repo", false);

    const [, generateInit] = findFetchCall("/generate");
    const body = JSON.parse(generateInit.body as string);
    expect(body.private).toBe(false);
    expect(body.owner).toBe("bob");
  });

  test("user installation: throws GitHubApiError(502) on malformed /generate response", async () => {
    const installationId = uniqueInstallationId();

    mockInstallationAccountResponse({
      login: "alice",
      id: 2,
      type: "User",
    });
    mockTokenResponse();
    // Simulate a malformed 201 (e.g., 202-async or stripped payload).
    // Without the runtime guard, the helper would return
    // { repoUrl: undefined, fullName: undefined } as a 200 success.
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({}),
    });

    await expect(
      createRepo(installationId, "my-repo", true),
    ).rejects.toSatisfy((err: unknown) => {
      expect(err).toBeInstanceOf(GitHubApiError);
      expect((err as GitHubApiError).statusCode).toBe(502);
      return true;
    });
  });

  test("user installation: throws GitHubApiError(422) when template not marked is_template", async () => {
    const installationId = uniqueInstallationId();

    mockInstallationAccountResponse({
      login: "alice",
      id: 2,
      type: "User",
    });
    mockTokenResponse();
    // GitHub returns 422 when /generate target is not a template repo
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 422,
      text: async () =>
        JSON.stringify(loadGithubFixture("error-422-not-template")),
    });

    await expect(
      createRepo(installationId, "my-repo", true),
    ).rejects.toSatisfy((err: unknown) => {
      expect(err).toBeInstanceOf(GitHubApiError);
      expect((err as GitHubApiError).statusCode).toBe(422);
      expect((err as GitHubApiError).message).toMatch(/template/);
      return true;
    });
  });

  test("user installation: throws GitHubApiError(404) when template repo missing", async () => {
    const installationId = uniqueInstallationId();

    mockInstallationAccountResponse({
      login: "alice",
      id: 2,
      type: "User",
    });
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404,
      text: async () => JSON.stringify(loadGithubFixture("error-404")),
    });

    await expect(
      createRepo(installationId, "my-repo", true),
    ).rejects.toSatisfy((err: unknown) => {
      expect(err).toBeInstanceOf(GitHubApiError);
      expect((err as GitHubApiError).statusCode).toBe(404);
      return true;
    });
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
      text: async () => JSON.stringify(loadGithubFixture("error-422-duplicate")),
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
      text: async () => JSON.stringify(loadGithubFixture("error-403")),
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
      json: async () => loadGithubFixture("error-404"),
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
        ...loadGithubFixture<{ account: object }>("installation-account-org"),
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
      json: async () => loadGithubFixture("error-404"),
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
