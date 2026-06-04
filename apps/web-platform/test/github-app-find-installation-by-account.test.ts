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

// Mirrors the prod reproduce-harness output: a personal (User) install and the
// repo-owning org install, both reachable.
function mockInstallationsList() {
  mockFetch.mockResolvedValueOnce({
    ok: true,
    status: 200,
    json: async () => [
      { id: 130018654, account: { login: "Elvalio", type: "User" } },
      { id: 122213433, account: { login: "jikig-ai", type: "Organization" } },
    ],
  });
}

describe("findInstallationByAccountLogin", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  test("returns the org install (122213433) for the repo owner 'jikig-ai'", async () => {
    mockInstallationsList();
    const result = await findInstallationByAccountLogin("jikig-ai");
    expect(result).toBe(122213433);
  });

  test("matches account login case-insensitively", async () => {
    mockInstallationsList();
    const result = await findInstallationByAccountLogin("JIKIG-AI");
    expect(result).toBe(122213433);
  });

  test("returns the personal install when the owner is the personal account", async () => {
    mockInstallationsList();
    const result = await findInstallationByAccountLogin("Elvalio");
    expect(result).toBe(130018654);
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
    const result = await findInstallationByAccountLogin("jikig-ai");
    expect(result).toBeNull();
  });
});
