import { describe, it, expect, beforeEach, vi } from "vitest";

// Tests for the GitHub App per-request factory (PR-H Phase 3 + PR-H+1 #4098).
//
// Mock @octokit/app + audit-writer to:
//   1. Avoid network/keyfile dependency at unit-test time.
//   2. Let us assert that every call creates a fresh App instance —
//      the load-bearing "no module-scope state" invariant.
//   3. Capture the hook.after / hook.error handlers attached by the
//      factory so we can invoke them and verify recordGithubApiCall
//      is called with the correct (founderId, installationId, endpoint,
//      repoFullName, responseStatus) shape.

const { AppCtor, getInstallationOctokit, hookAfter, hookError, recordCalls } =
  vi.hoisted(() => ({
    AppCtor: vi.fn(),
    getInstallationOctokit: vi.fn(),
    hookAfter: vi.fn(),
    hookError: vi.fn(),
    recordCalls: vi.fn(),
  }));

vi.mock("@octokit/app", () => ({
  App: vi.fn().mockImplementation((opts: unknown) => {
    AppCtor(opts);
    return { getInstallationOctokit };
  }),
}));

vi.mock("@/server/github/audit-writer", () => ({
  recordGithubApiCall: recordCalls,
  extractEndpoint: (s: string) => {
    if (!s) return "";
    try {
      const base = "https://api.github.com";
      const u =
        s.startsWith("http://") || s.startsWith("https://")
          ? new URL(s)
          : new URL(s, base);
      return u.pathname;
    } catch {
      return s;
    }
  },
  extractRepoFullName: (s: string) => {
    const m = /^\/repos\/([^/]+)\/([^/]+)(?:\/|$)/.exec(
      s.startsWith("http") ? new URL(s).pathname : s,
    );
    return m ? `${m[1]}/${m[2]}` : null;
  },
}));

const STUB_PRIVATE_KEY =
  "-----BEGIN RSA PRIVATE KEY-----\nstubpk\n-----END RSA PRIVATE KEY-----";

const SYNTHETIC_FOUNDER_ID = "00000000-0000-4000-8000-000000000001";

describe("createGitHubAppClient (PR-H Phase 3 + PR-H+1 audit hook)", () => {
  beforeEach(() => {
    AppCtor.mockClear();
    getInstallationOctokit.mockReset();
    hookAfter.mockReset();
    hookError.mockReset();
    recordCalls.mockReset();
    getInstallationOctokit.mockImplementation(async (id: number) => ({
      __installationId: id,
      hook: {
        after: hookAfter,
        error: hookError,
      },
    }));
    process.env.GITHUB_APP_ID = "111";
    process.env.GITHUB_APP_PRIVATE_KEY = STUB_PRIVATE_KEY;
  });

  it("creates a fresh App per call (AC14: no module-scope state)", async () => {
    const mod = await import("@/server/github/app-client");
    await mod.createGitHubAppClient(42, SYNTHETIC_FOUNDER_ID);
    await mod.createGitHubAppClient(43, SYNTHETIC_FOUNDER_ID);
    await mod.createGitHubAppClient(44, SYNTHETIC_FOUNDER_ID);

    expect(AppCtor).toHaveBeenCalledTimes(3);
  });

  it("reads GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY from process.env on every call", async () => {
    const mod = await import("@/server/github/app-client");
    process.env.GITHUB_APP_ID = "first";
    await mod.createGitHubAppClient(1, SYNTHETIC_FOUNDER_ID);
    process.env.GITHUB_APP_ID = "second";
    await mod.createGitHubAppClient(1, SYNTHETIC_FOUNDER_ID);

    expect(AppCtor.mock.calls[0][0]).toMatchObject({ appId: "first" });
    expect(AppCtor.mock.calls[1][0]).toMatchObject({ appId: "second" });
  });

  it("passes the installationId through to getInstallationOctokit", async () => {
    const mod = await import("@/server/github/app-client");
    await mod.createGitHubAppClient(987654, SYNTHETIC_FOUNDER_ID);
    expect(getInstallationOctokit).toHaveBeenCalledWith(987654);
  });

  it("throws when GITHUB_APP_ID is missing (fail-closed on env drift)", async () => {
    const mod = await import("@/server/github/app-client");
    delete process.env.GITHUB_APP_ID;
    await expect(
      mod.createGitHubAppClient(1, SYNTHETIC_FOUNDER_ID),
    ).rejects.toThrow(/GITHUB_APP_ID is unset/);
  });

  it("throws when GITHUB_APP_PRIVATE_KEY is missing (fail-closed on env drift)", async () => {
    const mod = await import("@/server/github/app-client");
    delete process.env.GITHUB_APP_PRIVATE_KEY;
    await expect(
      mod.createGitHubAppClient(1, SYNTHETIC_FOUNDER_ID),
    ).rejects.toThrow(/GITHUB_APP_PRIVATE_KEY is unset/);
  });

  it("attaches an octokit.hook.after('request', ...) handler that records the audit row", async () => {
    const mod = await import("@/server/github/app-client");
    await mod.createGitHubAppClient(42, SYNTHETIC_FOUNDER_ID);

    expect(hookAfter).toHaveBeenCalledTimes(1);
    expect(hookAfter.mock.calls[0][0]).toBe("request");

    const handler = hookAfter.mock.calls[0][1] as (
      response: { status: number },
      options: { url: string },
    ) => unknown;
    await handler(
      { status: 200 },
      { url: "https://api.github.com/repos/jikig-ai/soleur/pulls/4098" },
    );

    expect(recordCalls).toHaveBeenCalledTimes(1);
    expect(recordCalls).toHaveBeenCalledWith({
      founderId: SYNTHETIC_FOUNDER_ID,
      installationId: 42,
      endpoint: "/repos/jikig-ai/soleur/pulls/4098",
      repoFullName: "jikig-ai/soleur",
      responseStatus: 200,
    });
  });

  it("attaches an octokit.hook.error('request', ...) handler that records the audit row AND re-throws", async () => {
    const mod = await import("@/server/github/app-client");
    await mod.createGitHubAppClient(42, SYNTHETIC_FOUNDER_ID);

    expect(hookError).toHaveBeenCalledTimes(1);
    const handler = hookError.mock.calls[0][1] as (
      error: { status?: number; message?: string },
      options: { url: string },
    ) => unknown;

    const apiError = { status: 422, message: "Validation Failed" };

    await expect(
      handler(apiError, {
        url: "https://api.github.com/repos/jikig-ai/soleur/issues",
      }),
    ).rejects.toBe(apiError);

    expect(recordCalls).toHaveBeenCalledTimes(1);
    expect(recordCalls).toHaveBeenCalledWith({
      founderId: SYNTHETIC_FOUNDER_ID,
      installationId: 42,
      endpoint: "/repos/jikig-ai/soleur/issues",
      repoFullName: "jikig-ai/soleur",
      responseStatus: 422,
    });
  });

  it("records app-level endpoints with repoFullName=null", async () => {
    const mod = await import("@/server/github/app-client");
    await mod.createGitHubAppClient(42, SYNTHETIC_FOUNDER_ID);

    const handler = hookAfter.mock.calls[0][1] as (
      response: { status: number },
      options: { url: string },
    ) => unknown;
    await handler(
      { status: 200 },
      { url: "https://api.github.com/installation/repositories" },
    );

    expect(recordCalls).toHaveBeenCalledWith(
      expect.objectContaining({
        endpoint: "/installation/repositories",
        repoFullName: null,
      }),
    );
  });

  it("threads founderId per factory call (audit row attribution across simultaneous founders)", async () => {
    const FOUNDER_A = "00000000-0000-4000-8000-00000000000a";
    const FOUNDER_B = "00000000-0000-4000-8000-00000000000b";
    const mod = await import("@/server/github/app-client");
    await mod.createGitHubAppClient(42, FOUNDER_A);
    await mod.createGitHubAppClient(42, FOUNDER_B);

    expect(hookAfter).toHaveBeenCalledTimes(2);
    const handlerA = hookAfter.mock.calls[0][1] as (
      response: { status: number },
      options: { url: string },
    ) => unknown;
    const handlerB = hookAfter.mock.calls[1][1] as (
      response: { status: number },
      options: { url: string },
    ) => unknown;

    await handlerA({ status: 200 }, { url: "/repos/founder-a/repo/issues" });
    await handlerB({ status: 200 }, { url: "/repos/founder-b/repo/issues" });

    expect(recordCalls.mock.calls[0][0]).toMatchObject({
      founderId: FOUNDER_A,
    });
    expect(recordCalls.mock.calls[1][0]).toMatchObject({
      founderId: FOUNDER_B,
    });
  });
});
