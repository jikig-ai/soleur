/**
 * findRepoOwnerInstallationForUser tests
 * (feat-one-shot-concierge-gh-403-token-diagnosis, P1 review fix).
 *
 * The Concierge installation self-heal must select the repo-owner's
 * installation (full grant) — but ONLY when the dispatching user is actually
 * ENTITLED to it. A bare account-login match would let an OUTSIDE read-only
 * collaborator on an org repo (who can connect it because the read probe
 * passes) get promoted to the org's WRITE-capable installation — a cross-tenant
 * privilege escalation (security-sentinel P1). The entitlement gate: the owner
 * account is the user's OWN account, OR the user is a verified member of the
 * owner org (GET /orgs/{owner}/members/{login} → 204, the same check
 * findOrgInstallationForUser uses).
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

vi.mock("../server/observability", () => ({ reportSilentFallback: vi.fn() }));

import { findRepoOwnerInstallationForUser } from "../server/github-app";
import { loadGithubFixture } from "./fixtures/github/load";

let nextOwnerId = 700_000;
function uniqueOwnerId() {
  return nextOwnerId++;
}

// Synthetic personal (User) install that co-exists with the repo-owning org
// install in the list (cq-test-fixtures-synthesized-only). The login is read
// from the synthesized fixture; the org entry is parametric per test.
const PERSONAL_INSTALL = loadGithubFixture<
  { id: number; account: { login: string; type: string } }[]
>("installations-list").find((i) => i.account.type === "User")!;

function mockInstallList(ownerId: number, ownerLogin: string) {
  mockFetch.mockResolvedValueOnce({
    ok: true,
    status: 200,
    json: async () => [
      {
        id: PERSONAL_INSTALL.id,
        account: { login: PERSONAL_INSTALL.account.login, type: "User" },
      },
      { id: ownerId, account: { login: ownerLogin, type: "Organization" } },
    ],
  });
}
function mockTokenMint() {
  const body = loadGithubFixture<{ token: string; expires_at: string }>(
    "installation-access-token",
  );
  mockFetch.mockResolvedValueOnce({
    ok: true,
    status: 200,
    json: async () => ({
      ...body,
      expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    }),
    text: async () => "",
  });
}
function mockMembership(status: number) {
  mockFetch.mockResolvedValueOnce({
    ok: status === 204,
    status,
    text: async () => "",
  });
}

describe("findRepoOwnerInstallationForUser — entitlement-gated owner selection", () => {
  beforeEach(() => mockFetch.mockReset());

  test("promotes to org install when the user is a verified org member (204)", async () => {
    const ownerId = uniqueOwnerId();
    mockInstallList(ownerId, "synthetic-org");
    mockTokenMint();
    mockMembership(204);
    const result = await findRepoOwnerInstallationForUser(
      "synthetic-org",
      PERSONAL_INSTALL.account.login,
    );
    expect(result).toBe(ownerId);
  });

  test("BLOCKS promotion when the user is NOT an org member (404) — escalation guard", async () => {
    const ownerId = uniqueOwnerId();
    mockInstallList(ownerId, "victim-org");
    mockTokenMint();
    mockMembership(404);
    const result = await findRepoOwnerInstallationForUser(
      "victim-org",
      "outside-collaborator",
    );
    expect(result).toBeNull();
  });

  test("returns owner install WITHOUT a membership check when owner == user's own account", async () => {
    const ownerId = uniqueOwnerId();
    mockInstallList(ownerId, "octocat");
    // No token mint / membership mock — the self-account path must not probe.
    const result = await findRepoOwnerInstallationForUser("octocat", "OCTOCAT");
    expect(result).toBe(ownerId);
  });

  test("returns null when no installation matches the owner account", async () => {
    mockInstallList(uniqueOwnerId(), "some-org");
    const result = await findRepoOwnerInstallationForUser("absent-org", "user");
    expect(result).toBeNull();
  });

  test("returns null (degrades) when githubLogin is null", async () => {
    const result = await findRepoOwnerInstallationForUser("synthetic-org", null);
    expect(result).toBeNull();
    // Must not even list installations without a login to gate on.
    expect(mockFetch).not.toHaveBeenCalled();
  });
});
