import { describe, it, expect, beforeEach, vi } from "vitest";

// Tests for the GitHub App per-request factory (Phase 3 / AC14).
//
// Mock @octokit/app to:
//   1. Avoid network/keyfile dependency at unit-test time.
//   2. Let us assert that every call creates a fresh App instance —
//      the load-bearing "no module-scope state" invariant. If a future
//      refactor introduces memoization, the call-count assertion in
//      "creates a fresh App per call" fails.

const AppCtor = vi.fn();
const getInstallationOctokit = vi.fn(async (id: number) => ({
  __installationId: id,
}));

vi.mock("@octokit/app", () => ({
  App: vi.fn().mockImplementation((opts: unknown) => {
    AppCtor(opts);
    return { getInstallationOctokit };
  }),
}));

// Test-only RSA stub. The Octokit App constructor parses the private
// key on instantiation in real code; under the mock it does not, so a
// short sentinel string is sufficient for assertion purposes.
const STUB_PRIVATE_KEY = "-----BEGIN RSA PRIVATE KEY-----\nstubpk\n-----END RSA PRIVATE KEY-----";

describe("createGitHubAppClient (PR-H Phase 3)", () => {
  beforeEach(() => {
    AppCtor.mockClear();
    getInstallationOctokit.mockClear();
    process.env.GITHUB_APP_ID = "111";
    process.env.GITHUB_APP_PRIVATE_KEY = STUB_PRIVATE_KEY;
  });

  it("creates a fresh App per call (AC14: no module-scope state)", async () => {
    const mod = await import("@/server/github/app-client");
    await mod.createGitHubAppClient(42);
    await mod.createGitHubAppClient(43);
    await mod.createGitHubAppClient(44);

    // Three calls -> three App instantiations. A memoized singleton
    // would only create one. This is the load-bearing invariant.
    expect(AppCtor).toHaveBeenCalledTimes(3);
  });

  it("reads GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY from process.env on every call", async () => {
    const mod = await import("@/server/github/app-client");
    process.env.GITHUB_APP_ID = "first";
    await mod.createGitHubAppClient(1);
    process.env.GITHUB_APP_ID = "second";
    await mod.createGitHubAppClient(1);

    expect(AppCtor.mock.calls[0][0]).toMatchObject({ appId: "first" });
    expect(AppCtor.mock.calls[1][0]).toMatchObject({ appId: "second" });
  });

  it("passes the installationId through to getInstallationOctokit", async () => {
    const mod = await import("@/server/github/app-client");
    await mod.createGitHubAppClient(987654);
    expect(getInstallationOctokit).toHaveBeenCalledWith(987654);
  });

  it("throws when GITHUB_APP_ID is missing (fail-closed on env drift)", async () => {
    const mod = await import("@/server/github/app-client");
    delete process.env.GITHUB_APP_ID;
    await expect(mod.createGitHubAppClient(1)).rejects.toThrow(/GITHUB_APP_ID is unset/);
  });

  it("throws when GITHUB_APP_PRIVATE_KEY is missing (fail-closed on env drift)", async () => {
    const mod = await import("@/server/github/app-client");
    delete process.env.GITHUB_APP_PRIVATE_KEY;
    await expect(mod.createGitHubAppClient(1)).rejects.toThrow(
      /GITHUB_APP_PRIVATE_KEY is unset/,
    );
  });
});
