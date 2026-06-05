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
import { createPullRequest, createIssue } from "../server/github-app";

describe("createPullRequest", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  // Use unique installationId per test to avoid token cache interference
  let nextInstallationId = 9000;
  function uniqueInstallationId() {
    return nextInstallationId++;
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

  test("happy path: creates PR and returns url, number, htmlUrl", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({
        number: 42,
        html_url: "https://github.com/alice/my-repo/pull/42",
        url: "https://api.github.com/repos/alice/my-repo/pulls/42",
        title: "feat: new feature",
        state: "open",
      }),
    });

    const result = await createPullRequest(
      installationId, "alice", "my-repo", "feat-branch", "main", "feat: new feature",
    );

    expect(result).toEqual({
      number: 42,
      htmlUrl: "https://github.com/alice/my-repo/pull/42",
      url: "https://api.github.com/repos/alice/my-repo/pulls/42",
    });

    // Verify the GitHub API call
    const prCall = mockFetch.mock.calls[1];
    expect(prCall[0]).toBe("https://api.github.com/repos/alice/my-repo/pulls");
    const body = JSON.parse(prCall[1].body);
    expect(body.head).toBe("feat-branch");
    expect(body.base).toBe("main");
    expect(body.title).toBe("feat: new feature");
  });

  test("passes optional body parameter", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({
        number: 43,
        html_url: "https://github.com/alice/my-repo/pull/43",
        url: "https://api.github.com/repos/alice/my-repo/pulls/43",
      }),
    });

    await createPullRequest(
      installationId, "alice", "my-repo", "feat-branch", "main",
      "feat: thing", "## Summary\nSome description",
    );

    const prCall = mockFetch.mock.calls[1];
    const body = JSON.parse(prCall[1].body);
    expect(body.body).toBe("## Summary\nSome description");
  });

  test("throws on 422 error: no commits between branches", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 422,
      text: async () => JSON.stringify({
        message: "Validation Failed",
        errors: [{ message: "No commits between main and feat-branch" }],
      }),
    });

    await expect(
      createPullRequest(installationId, "alice", "my-repo", "feat-branch", "main", "title"),
    ).rejects.toThrow(/No commits between/);
  });

  test("throws on 422 error: PR already exists", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 422,
      text: async () => JSON.stringify({
        message: "Validation Failed",
        errors: [{ message: "A pull request already exists for alice:feat-branch" }],
      }),
    });

    await expect(
      createPullRequest(installationId, "alice", "my-repo", "feat-branch", "main", "title"),
    ).rejects.toThrow(/pull request already exists/);
  });

  test("throws on 404 error: repo not found", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404,
      text: async () => JSON.stringify({ message: "Not Found" }),
    });

    await expect(
      createPullRequest(installationId, "alice", "my-repo", "feat-branch", "main", "title"),
    ).rejects.toThrow(/404/);
  });

  test("propagates token generation failure", async () => {
    const installationId = uniqueInstallationId();
    // Token request fails — generateInstallationToken retries on 401 with
    // exponential backoff (3 total attempts: initial + 2 retries), so we need
    // THREE 401 responses to trigger the final throw. See #122537945.
    mockFetch
      .mockResolvedValueOnce({
        ok: false,
        status: 401,
        text: async () => "Unauthorized",
      })
      .mockResolvedValueOnce({
        ok: false,
        status: 401,
        text: async () => "Unauthorized",
      })
      .mockResolvedValueOnce({
        ok: false,
        status: 401,
        text: async () => "Unauthorized",
      });

    await expect(
      createPullRequest(installationId, "alice", "my-repo", "feat-branch", "main", "title"),
    ).rejects.toThrow(/installation token/);
  });
});

describe("createIssue", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  // Use unique installationId per test to avoid token cache interference
  let nextInstallationId = 9500;
  function uniqueInstallationId() {
    return nextInstallationId++;
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

  test("happy path: creates issue and returns number, htmlUrl, url", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({
        number: 7,
        html_url: "https://github.com/alice/my-repo/issues/7",
        url: "https://api.github.com/repos/alice/my-repo/issues/7",
        title: "Something broke",
        state: "open",
      }),
    });

    const result = await createIssue(
      installationId, "alice", "my-repo", "Something broke",
    );

    expect(result).toEqual({
      number: 7,
      htmlUrl: "https://github.com/alice/my-repo/issues/7",
      url: "https://api.github.com/repos/alice/my-repo/issues/7",
    });

    // Verify the GitHub API call POSTs to the issues endpoint
    const issueCall = mockFetch.mock.calls[1];
    expect(issueCall[0]).toBe("https://api.github.com/repos/alice/my-repo/issues");
    expect(issueCall[1].method).toBe("POST");
    const body = JSON.parse(issueCall[1].body);
    expect(body.title).toBe("Something broke");
  });

  test("passes optional body and labels parameters", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({
        number: 8,
        html_url: "https://github.com/alice/my-repo/issues/8",
        url: "https://api.github.com/repos/alice/my-repo/issues/8",
      }),
    });

    await createIssue(
      installationId, "alice", "my-repo", "Bug report",
      "## Details\nFull description", ["bug", "triage"],
    );

    const issueCall = mockFetch.mock.calls[1];
    const body = JSON.parse(issueCall[1].body);
    expect(body.title).toBe("Bug report");
    expect(body.body).toBe("## Details\nFull description");
    expect(body.labels).toEqual(["bug", "triage"]);
  });

  test("throws on 404 error: repo not found", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404,
      text: async () => JSON.stringify({ message: "Not Found" }),
    });

    await expect(
      createIssue(installationId, "alice", "my-repo", "title"),
    ).rejects.toThrow(/404/);
  });

  test("throws on 422 validation error", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 422,
      text: async () => JSON.stringify({
        message: "Validation Failed",
        errors: [{ message: "Issues are disabled for this repo" }],
      }),
    });

    await expect(
      createIssue(installationId, "alice", "my-repo", "title"),
    ).rejects.toThrow(/Issues are disabled/);
  });

  test("propagates token generation failure", async () => {
    const installationId = uniqueInstallationId();
    mockFetch
      .mockResolvedValueOnce({ ok: false, status: 401, text: async () => "Unauthorized" })
      .mockResolvedValueOnce({ ok: false, status: 401, text: async () => "Unauthorized" })
      .mockResolvedValueOnce({ ok: false, status: 401, text: async () => "Unauthorized" });

    await expect(
      createIssue(installationId, "alice", "my-repo", "title"),
    ).rejects.toThrow(/installation token/);
  });
});
