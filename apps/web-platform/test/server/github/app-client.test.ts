import { describe, it, expect, beforeEach, vi } from "vitest";
import { generateKeyPairSync } from "crypto";

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
  // vitest 4: mocks invoked with `new` now construct an instance, so a
  // constructor mock must use the `function` keyword and assign to `this`
  // (an arrow returning an object throws "is not a constructor").
  App: vi.fn().mockImplementation(function (
    this: Record<string, unknown>,
    opts: unknown,
  ) {
    AppCtor(opts);
    this.getInstallationOctokit = getInstallationOctokit;
  }),
}));

// Mock recordGithubApiCall (Supabase RPC + Sentry side-effects) but
// keep the real extractEndpoint / extractRepoFullName so the factory
// hook's wiring is exercised against the production parsers — not a
// drifting test-mock copy.
vi.mock("@/server/github/audit-writer", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/github/audit-writer")
  >("@/server/github/audit-writer");
  return {
    ...actual,
    recordGithubApiCall: recordCalls,
  };
});

// Synthesized throwaway keypair (cq-test-fixtures-synthesized-only). Must be a
// real, parseable PEM: createGitHubAppClient now canonicalizes the key via
// normalizeAppPrivateKey() (crypto.createPrivateKey) before constructing the
// mocked App, so a bogus body would throw at normalization.
const STUB_PRIVATE_KEY = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "spki", format: "pem" },
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
}).privateKey as string;

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
    // Distinct numeric App IDs per call prove the env is re-read each time (not
    // cached). They must be numeric: readAppId() now validates GITHUB_APP_ID
    // before new App(), so a non-numeric placeholder ("first"/"second") would
    // throw before the constructor is reached.
    process.env.GITHUB_APP_ID = "1001";
    await mod.createGitHubAppClient(1, SYNTHETIC_FOUNDER_ID);
    process.env.GITHUB_APP_ID = "2002";
    await mod.createGitHubAppClient(1, SYNTHETIC_FOUNDER_ID);

    expect(AppCtor.mock.calls[0][0]).toMatchObject({ appId: "1001" });
    expect(AppCtor.mock.calls[1][0]).toMatchObject({ appId: "2002" });
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

  it("records responseStatus=null on the error hook when the failure carries no HTTP status (network reset / DNS / abort)", async () => {
    const mod = await import("@/server/github/app-client");
    await mod.createGitHubAppClient(42, SYNTHETIC_FOUNDER_ID);

    const handler = hookError.mock.calls[0][1] as (
      error: unknown,
      options: { url: string },
    ) => unknown;

    const networkError = new Error("ECONNRESET");

    await expect(
      handler(networkError, {
        url: "https://api.github.com/repos/jikig-ai/soleur/pulls/4098",
      }),
    ).rejects.toBe(networkError);

    expect(recordCalls).toHaveBeenCalledTimes(1);
    expect(recordCalls).toHaveBeenCalledWith(
      expect.objectContaining({
        responseStatus: null,
      }),
    );
  });

  it("clamps out-of-range HTTP statuses to null (defense-in-depth on response_status CHECK constraint)", async () => {
    const mod = await import("@/server/github/app-client");
    await mod.createGitHubAppClient(42, SYNTHETIC_FOUNDER_ID);

    const handler = hookError.mock.calls[0][1] as (
      error: unknown,
      options: { url: string },
    ) => unknown;

    const weirdError = { status: 0, message: "synthetic" };

    await expect(
      handler(weirdError, {
        url: "https://api.github.com/repos/jikig-ai/soleur",
      }),
    ).rejects.toBe(weirdError);

    expect(recordCalls).toHaveBeenCalledWith(
      expect.objectContaining({
        responseStatus: null,
      }),
    );
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
