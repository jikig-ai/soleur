/**
 * GitHub API Fetch Wrapper Tests (Phase 2, #1927)
 *
 * Tests the thin GitHub API wrapper that uses generateInstallationToken()
 * for authentication. Verifies:
 * - Authenticated GET requests
 * - Authenticated POST requests
 * - DELETE method rejection (safety guard)
 * - 403 graceful degradation with permission upgrade message
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
  githubApiGet,
  githubApiPost,
  GitHubApiError,
} from "../server/github-api";
import { GitHubApiError as GitHubApiErrorFromApp } from "../server/github-app";

describe("github-api fetch wrapper", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  // Use unique installationId per test to avoid token cache interference
  let nextInstallationId = 8000;
  function uniqueInstallationId() {
    return nextInstallationId++;
  }

  function mockTokenResponse() {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        token: "ghs_test_token",
        expires_at: new Date(Date.now() + 3_600_000).toISOString(),
      }),
    });
  }

  describe("githubApiGet", () => {
    test("makes authenticated GET request with installation token", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ workflow_runs: [] }),
      });

      const result = await githubApiGet(
        installationId,
        "/repos/alice/my-repo/actions/runs",
      );

      expect(result).toEqual({ workflow_runs: [] });

      // Verify the GET call used token auth
      const getCall = mockFetch.mock.calls[1];
      expect(getCall[0]).toBe(
        "https://api.github.com/repos/alice/my-repo/actions/runs",
      );
      expect(getCall[1].headers.Authorization).toBe("token ghs_test_token");
      expect(getCall[1].method).toBeUndefined(); // GET is default
    });

    test("throws on non-ok response", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 404,
        text: async () => "Not Found",
      });

      await expect(
        githubApiGet(installationId, "/repos/alice/my-repo/actions/runs"),
      ).rejects.toThrow(/404/);
    });

    test("returns permission upgrade message on 403", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 403,
        text: async () => JSON.stringify({
          message: "Resource not accessible by integration",
        }),
      });

      await expect(
        githubApiGet(installationId, "/repos/alice/my-repo/actions/runs"),
      ).rejects.toThrow(/permission/i);
    });
  });

  describe("githubApiPost", () => {
    test("makes authenticated POST request with JSON body", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({
        ok: true,
        status: 204,
        text: async () => "",
        json: async () => null,
      });

      await githubApiPost(
        installationId,
        "/repos/alice/my-repo/actions/workflows/123/dispatches",
        { ref: "main" },
      );

      const postCall = mockFetch.mock.calls[1];
      expect(postCall[0]).toBe(
        "https://api.github.com/repos/alice/my-repo/actions/workflows/123/dispatches",
      );
      expect(postCall[1].method).toBe("POST");
      expect(JSON.parse(postCall[1].body)).toEqual({ ref: "main" });
    });

    test("throws on non-ok response", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 422,
        text: async () => JSON.stringify({ message: "Validation Failed" }),
      });

      await expect(
        githubApiPost(installationId, "/repos/alice/my-repo/pulls", {
          head: "feat",
          base: "main",
          title: "test",
        }),
      ).rejects.toThrow(/422/);
    });

    test("rejects DELETE method calls", async () => {
      const installationId = uniqueInstallationId();
      // Should reject before even making a request
      await expect(
        githubApiPost(
          installationId,
          "/repos/alice/my-repo/git/refs/heads/feat",
          {},
          "DELETE",
        ),
      ).rejects.toThrow(/DELETE.*not allowed/i);

      // No fetch calls should have been made (except none)
      expect(mockFetch).not.toHaveBeenCalled();
    });
  });

  describe("handleErrorResponse — typed errors (#2149)", () => {
    test("404 response throws GitHubApiError with statusCode 404", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 404,
        text: async () => "Not Found",
      });

      let caught: unknown;
      try {
        await githubApiGet(installationId, "/repos/alice/my-repo/contents/missing.md");
      } catch (err) {
        caught = err;
      }

      expect(caught).toBeInstanceOf(GitHubApiError);
      expect((caught as GitHubApiError).statusCode).toBe(404);
      expect((caught as GitHubApiError).message).toMatch(/404/);
    });

    test("403 response throws GitHubApiError with statusCode 403 and permission-denied message", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 403,
        text: async () => JSON.stringify({
          message: "Resource not accessible by integration",
        }),
      });

      let caught: unknown;
      try {
        await githubApiGet(installationId, "/repos/alice/my-repo/contents/secret.md");
      } catch (err) {
        caught = err;
      }

      expect(caught).toBeInstanceOf(GitHubApiError);
      expect((caught as GitHubApiError).statusCode).toBe(403);
      expect((caught as GitHubApiError).message).toMatch(/permission denied/i);
    });

    test("500 response throws GitHubApiError with statusCode 500 and default message format", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      // 500 retries twice (MAX_RETRIES=2) before surfacing — mock all 3 attempts
      for (let i = 0; i < 3; i++) {
        mockFetch.mockResolvedValueOnce({
          ok: false,
          status: 500,
          text: async () => "Internal Server Error",
        });
      }

      let caught: unknown;
      try {
        await githubApiGet(installationId, "/repos/alice/my-repo/contents/boom.md");
      } catch (err) {
        caught = err;
      }

      expect(caught).toBeInstanceOf(GitHubApiError);
      expect((caught as GitHubApiError).statusCode).toBe(500);
      expect((caught as GitHubApiError).message).toMatch(
        /GitHub API request failed: 500/,
      );
    });

    test("GitHubApiError re-exported from github-api is the same class as from github-app", () => {
      // Class identity check — the re-export must not create a phantom second class
      expect(GitHubApiError).toBe(GitHubApiErrorFromApp);
    });
  });
});
