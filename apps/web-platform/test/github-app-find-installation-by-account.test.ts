/**
 * findInstallationByAccountLogin tests
 * (feat-one-shot-concierge-gh-403-token-diagnosis).
 *
 * Root cause (confirmed by scripts/spike/reproduce-gh-403.ts against prod):
 * a repo can be reachable by TWO installations — the repo-owner's ORG install
 * (full permissions incl. `issues: write`) and a cross-account PERSONAL install
 * (reduced permissions, `issues: read`). When the Concierge resolves the
 * personal install, `POST /issues` 403s ("Resource not accessible by
 * integration") even though a plain repo GET succeeds. The deterministic fix:
 * select the installation whose ACCOUNT LOGIN equals the repo owner — i.e. the
 * installation that actually owns the repo, which carries the full grant.
 *
 * This is selection, NOT a permission change (the org grant already exists).
 */
import { generateKeyPairSync } from "crypto";

const { privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "pkcs1", format: "pem" },
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
});

process.env.GITHUB_APP_ID = "12345";
process.env.GITHUB_APP_PRIVATE_KEY = privateKey;

import { describe, test, expect, vi, beforeEach, afterAll } from "vitest";

const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;

afterAll(() => {
  globalThis.fetch = originalFetch;
});

vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { findInstallationByAccountLogin } from "../server/github-app";
import { loadGithubFixture } from "./fixtures/github/load";

// Synthesized installations-list body (cq-test-fixtures-synthesized-only):
// a personal (User) install and the repo-owning org install, both reachable —
// the same dual-reachability shape the prod reproduce-harness exposed, with
// synthetic logins/IDs. The list's two entries are the load-bearing data; the
// `id` of each is what the selection logic returns.
const INSTALLATIONS =
  loadGithubFixture<{ id: number; account: { login: string; type: string } }[]>(
    "installations-list",
  );
const PERSONAL = INSTALLATIONS.find((i) => i.account.type === "User")!;
const ORG = INSTALLATIONS.find((i) => i.account.type === "Organization")!;

function mockInstallationsList() {
  mockFetch.mockResolvedValueOnce({
    ok: true,
    status: 200,
    json: async () => loadGithubFixture("installations-list"),
  });
}

describe("findInstallationByAccountLogin", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  test(`returns the org install (${ORG.id}) for the repo owner '${ORG.account.login}'`, async () => {
    mockInstallationsList();
    const result = await findInstallationByAccountLogin(ORG.account.login);
    expect(result).toBe(ORG.id);
  });

  test("matches account login case-insensitively", async () => {
    mockInstallationsList();
    const result = await findInstallationByAccountLogin(
      ORG.account.login.toUpperCase(),
    );
    expect(result).toBe(ORG.id);
  });

  test("returns the personal install when the owner is the personal account", async () => {
    mockInstallationsList();
    const result = await findInstallationByAccountLogin(PERSONAL.account.login);
    expect(result).toBe(PERSONAL.id);
  });

  test("returns null when no installation account matches the owner", async () => {
    mockInstallationsList();
    const result = await findInstallationByAccountLogin("someone-else");
    expect(result).toBeNull();
  });

  test("returns null (degrades) when listing installations fails", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 401,
      text: async () => JSON.stringify({ message: "Bad credentials" }),
    });
    const result = await findInstallationByAccountLogin(ORG.account.login);
    expect(result).toBeNull();
  });
});
