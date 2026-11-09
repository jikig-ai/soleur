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

// Capture the Sentry mirror so the 403-honest-messaging contract
// (cq-silent-fallback-must-mirror-to-sentry) is assertable.
const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));
vi.mock("../server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) =>
    mockReportSilentFallback(...args),
}));

// Record what the github-api child logger is asked to write, so a scrubbed-mode test can prove no sink carries a path.
const { logCalls } = vi.hoisted(() => ({ logCalls: [] as Array<{ level: string; args: unknown[] }> }));
vi.mock("../server/logger", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../server/logger")>();
  return {
    ...actual,
    createChildLogger: (context: string) => {
      const real = actual.createChildLogger(context);
      if (context !== "github-api") return real;
      const rec = (level: string) => (...args: unknown[]) => {
        logCalls.push({ level, args });
      };
      return { ...real, warn: rec("warn"), error: rec("error"), info: rec("info"), debug: rec("debug") };
    },
  };
});

// Import AFTER env and fetch mocking
import {
  githubApiDelete,
  githubApiGet,
  githubApiGetText,
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

    // #12469: the cc read tools pass `redirect: "manual"`; these rows pin it at the layer that matters (the init handed to fetch),
    // because every reader-level test sits above this seam and a dropped spread there left them all green.
    test("redirect:'manual' reaches fetch's init; a plain call has NO redirect key", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({}) });
      await githubApiGet(installationId, "/repos/alice/my-repo", { redirect: "manual" });
      expect(mockFetch.mock.calls[1][1].redirect).toBe("manual");

      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({}) });
      await githubApiGet(uniqueInstallationId(), "/repos/alice/my-repo");
      expect("redirect" in mockFetch.mock.calls[3][1]).toBe(false);
    });

    test("a 302 under redirect:'manual' throws a GitHubApiError with status 302 and is not retried", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({ ok: false, status: 302, text: async () => "" });
      const err = await githubApiGet(installationId, "/repos/alice/secret-repo", { redirect: "manual" }).catch((e) => e);
      expect(err).toBeInstanceOf(GitHubApiError);
      expect((err as InstanceType<typeof GitHubApiError>).statusCode).toBe(302);
      expect(mockFetch).toHaveBeenCalledTimes(2); // token mint + exactly one GET
    });

    test("scrubbed mode (redirect:'manual'): a 403 reaches NO sink with the path (a private repo's name) or GitHub's text, and sends no undebounced Sentry event", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 403,
        text: async () => JSON.stringify({ message: "Resource not accessible by integration for secret-org/secret-repo" }),
      });
      mockReportSilentFallback.mockClear();
      logCalls.length = 0;
      const err = (await githubApiGet(installationId, "/repos/secret-org/secret-repo", { redirect: "manual" }).catch((e) => e)) as Error;
      expect(err.message).not.toMatch(/secret-org|secret-repo|Resource not accessible/);
      // The caller's debounced onFault is the Sentry signal; this site has no user/tool identity, so it must not mirror per call.
      expect(mockReportSilentFallback).not.toHaveBeenCalled();
      expect(JSON.stringify(logCalls)).not.toMatch(/secret-org|secret-repo|Resource not accessible/);
      expect(logCalls).toEqual([{ level: "warn", args: [{ status: 403, limited: false }, "GitHub API 403 (scrubbed)"] }]);
    });

    test.each([
      [404, "not found"],
      [422, "unprocessable"],
      [302, "redirect"],
    ])("scrubbed mode: a %i reaches NO sink and no message with the path", async (status, body) => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({ ok: false, status, text: async () => `${body} for secret-org/secret-repo` });
      mockReportSilentFallback.mockClear();
      logCalls.length = 0;
      const err = (await githubApiGet(installationId, "/repos/secret-org/secret-repo", { redirect: "manual" }).catch((e) => e)) as InstanceType<typeof GitHubApiError>;
      expect(err.statusCode).toBe(status);
      expect(err.message).not.toMatch(/secret-org|secret-repo/);
      expect(JSON.stringify(mockReportSilentFallback.mock.calls)).not.toMatch(/secret-org|secret-repo/);
      expect(JSON.stringify(logCalls)).not.toMatch(/secret-org|secret-repo/);
      expect(logCalls).toHaveLength(1);
    });

    test("scrubbed mode: a 403 whose body stream aborts is still an access fault (403), never a plain transport error", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 403,
        text: async () => {
          throw new TypeError("terminated");
        },
      });
      const err = (await githubApiGet(installationId, "/repos/a/b", { redirect: "manual" }).catch((e) => e)) as InstanceType<typeof GitHubApiError>;
      expect(err).toBeInstanceOf(GitHubApiError);
      expect(err.statusCode).toBe(403);
      expect(err.message).toMatch(/cannot access this resource/);
    });

    test("scrubbed mode: retry breadcrumbs carry no url (it embeds owner/repo); the default mode still logs it", async () => {
      vi.useFakeTimers({ toFake: ["setTimeout"] });
      try {
        const scrubbedId = uniqueInstallationId();
        mockTokenResponse();
        mockFetch.mockResolvedValueOnce({ ok: false, status: 502, text: async () => "" });
        mockFetch.mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({}) });
        logCalls.length = 0;
        const p = githubApiGet(scrubbedId, "/repos/secret-org/secret-repo", { redirect: "manual" });
        await vi.advanceTimersByTimeAsync(60_000);
        await p;
        expect(logCalls.some((c) => c.level === "warn")).toBe(true);
        expect(JSON.stringify(logCalls)).not.toMatch(/secret-org|secret-repo|api\.github\.com/);

        mockTokenResponse();
        mockFetch.mockResolvedValueOnce({ ok: false, status: 502, text: async () => "" });
        mockFetch.mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({}) });
        logCalls.length = 0;
        const q = githubApiGet(uniqueInstallationId(), "/repos/alice/my-repo");
        await vi.advanceTimersByTimeAsync(60_000);
        await q;
        expect(JSON.stringify(logCalls)).toMatch(/my-repo/);
      } finally {
        vi.useRealTimers();
      }
    });

    test("scrubbed mode keeps ONE fact: a secondary-rate-limit 403 is still distinguishable from an access fault", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 403,
        text: async () => JSON.stringify({ message: "You have exceeded a secondary rate limit" }),
      });
      const err = (await githubApiGet(installationId, "/repos/a/b", { redirect: "manual" }).catch((e) => e)) as Error;
      expect(err.message).toMatch(/rate limit/);
    });

    test("the default (unscrubbed) 403 diagnostic is unchanged: path and GitHub message still mirror", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 403,
        text: async () => JSON.stringify({ message: "Resource not accessible by integration" }),
      });
      mockReportSilentFallback.mockClear();
      await githubApiGet(installationId, "/repos/alice/my-repo").catch(() => {});
      expect(JSON.stringify(mockReportSilentFallback.mock.calls)).toMatch(/my-repo.*Resource not accessible/s);
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

    test("surfaces the real GitHub message on 403 (no false re-consent advice)", async () => {
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
      ).rejects.toThrow(/Resource not accessible by integration/);
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

    test("403 response throws GitHubApiError with statusCode 403, real GitHub message, no false re-consent advice, and mirrors to Sentry", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      mockReportSilentFallback.mockClear();
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
      const msg = (caught as GitHubApiError).message;
      expect((caught as GitHubApiError).statusCode).toBe(403);
      // Surfaces the ACTUAL GitHub message — the disambiguating evidence.
      expect(msg).toMatch(/Resource not accessible by integration/);
      // Kills the false-confidence diagnosis: no re-consent / scope-gap advice.
      expect(msg).not.toMatch(/approve new permissions/i);
      expect(msg).not.toMatch(/issues:write/i);
      expect(msg).not.toMatch(/installation settings/i);
      // cq-silent-fallback-must-mirror-to-sentry: 403s are queryable.
      expect(mockReportSilentFallback).toHaveBeenCalled();
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

  // #8623: the C4 staging deadline must stop GitHub work, not just stop waiting.
  describe("githubApiGet caller signal", () => {
    test("the caller's signal is combined into the fetch signal", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      const ac = new AbortController();
      mockFetch.mockImplementationOnce(async (_url: string, init: RequestInit) => {
        ac.abort(new Error("stage: deadline"));
        // The per-attempt signal must reflect the caller's abort.
        expect(init.signal?.aborted).toBe(true);
        return { ok: true, status: 200, json: async () => ({}) };
      });
      await githubApiGet(installationId, "/repos/o/r/contents/x", { signal: ac.signal });
    });

    test("an abort during a 5xx retry stops after ONE attempt and rejects with the abort reason", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      const ac = new AbortController();
      mockFetch.mockImplementationOnce(async () => {
        ac.abort(new Error("stage: deadline"));
        return { ok: false, status: 502, text: async () => "", json: async () => ({}) };
      });
      await expect(
        githubApiGet(installationId, "/repos/o/r/contents/x", { signal: ac.signal }),
      ).rejects.toThrow("stage: deadline");
      // 1 token call + 1 API attempt; no retry after the caller gave up.
      expect(mockFetch).toHaveBeenCalledTimes(2);
    }, 10_000);

    test("an already-aborted signal makes no API request", async () => {
      const installationId = uniqueInstallationId();
      mockTokenResponse();
      const ac = new AbortController();
      ac.abort(new Error("gone"));
      await expect(
        githubApiGet(installationId, "/repos/o/r/contents/x", { signal: ac.signal }),
      ).rejects.toThrow("gone");
      expect(mockFetch).toHaveBeenCalledTimes(1); // token only
    });
  });

  // #8857 / CodeQL alert #234: a path that cannot bind to api.github.com must
  // throw BEFORE generateInstallationToken — a refused request mints nothing.
  describe("egress guard (server/github-url.ts)", () => {
    beforeEach(() => {
      mockReportSilentFallback.mockClear();
    });

    test("a non-GitHub-bound path throws before any token mint or fetch", async () => {
      const installationId = uniqueInstallationId();
      await expect(
        githubApiGet(installationId, "@evil.example/x"),
      ).rejects.toThrow(/egress denied/);
      // 0 calls: resolveApiUrl fires before generateInstallationToken's fetch.
      expect(mockFetch).toHaveBeenCalledTimes(0);
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({ feature: "github-api", op: "url-refused" }),
      );
    });

    test("a dot-segment path is refused on the raw input, before normalization", async () => {
      const installationId = uniqueInstallationId();
      await expect(
        githubApiPost(
          installationId,
          "/repos/o/" + "../".repeat(2) + "admin",
          {},
        ),
      ).rejects.toThrow(/egress denied/);
      expect(mockFetch).toHaveBeenCalledTimes(0);
    });

    test.each([
      ["githubApiGetText", (id: number) => githubApiGetText(id, "@evil.example/x")],
      ["githubApiDelete", (id: number) => githubApiDelete(id, "@evil.example/x", {})],
    ])("%s refuses before minting", async (_name, call) => {
      const installationId = uniqueInstallationId();
      await expect(call(installationId)).rejects.toThrow(/egress denied/);
      expect(mockFetch).toHaveBeenCalledTimes(0);
    });
  });
});
