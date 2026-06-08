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
    expect(result.installationId).toBe(ownerId);
    expect(result.outcome).toBe("member");
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
    expect(result.installationId).toBeNull();
    expect(result.outcome).toBe("not-member");
  });

  test("returns owner install WITHOUT a membership check when owner == user's own account", async () => {
    const ownerId = uniqueOwnerId();
    mockInstallList(ownerId, "octocat");
    // No token mint / membership mock — the self-account path must not probe.
    const result = await findRepoOwnerInstallationForUser("octocat", "OCTOCAT");
    expect(result.installationId).toBe(ownerId);
    expect(result.outcome).toBe("personal-repo");
  });

  test("returns null when no installation matches the owner account", async () => {
    mockInstallList(uniqueOwnerId(), "some-org");
    const result = await findRepoOwnerInstallationForUser("absent-org", "user");
    expect(result.installationId).toBeNull();
    expect(result.outcome).toBe("no-owner-install");
  });

  test("returns null (degrades) when githubLogin is null", async () => {
    const result = await findRepoOwnerInstallationForUser("synthetic-org", null);
    expect(result.installationId).toBeNull();
    expect(result.outcome).toBe("no-github-login");
    // Must not even list installations without a login to gate on.
    expect(mockFetch).not.toHaveBeenCalled();
  });
});

/**
 * Bug A (feat-one-shot-concierge-gh-403-self-heal): the membership probe must
 * distinguish a TRANSIENT failure (5xx / AbortSignal.timeout) from an
 * AUTHORITATIVE "not a member" (404/302). The old `status === 204 ? install :
 * null` collapsed both into "deny", so an ENTITLED org member got a permanent
 * 403 purely because GitHub's /members endpoint 5xx'd or timed out for ~3s.
 *
 * Security invariant (fail-closed): a post-retry `indeterminate` DENIES
 * promotion (returns null). Only a confirmed 204 grants. Narrowing the
 * false-negative must NOT widen the entitlement gate (AC2/AC3).
 */
describe("findRepoOwnerInstallationForUser — transient probe robustness (Bug A)", () => {
  beforeEach(() => mockFetch.mockReset());

  function membersProbeCallCount() {
    return mockFetch.mock.calls.filter(([url]) =>
      String(url).includes("/members/"),
    ).length;
  }

  test("AC1 transient-recover: members probe 500 → retry → 204 returns the owner install", async () => {
    vi.useFakeTimers();
    try {
      const ownerId = uniqueOwnerId();
      mockInstallList(ownerId, "synthetic-org");
      mockTokenMint();
      mockMembership(500); // transient
      mockMembership(204); // recovers on retry
      const p = findRepoOwnerInstallationForUser(
        "synthetic-org",
        PERSONAL_INSTALL.account.login,
      );
      await vi.runAllTimersAsync();
      const result = await p;
      expect(result.installationId).toBe(ownerId);
      expect(result.outcome).toBe("member");
      expect(membersProbeCallCount()).toBe(2); // one retry
    } finally {
      vi.useRealTimers();
    }
  });

  test("AC2 transient-persist: members probe 500 on every attempt ⇒ null, deny, no throw", async () => {
    vi.useFakeTimers();
    try {
      const ownerId = uniqueOwnerId();
      mockInstallList(ownerId, "synthetic-org");
      mockTokenMint();
      mockMembership(500);
      mockMembership(500);
      mockMembership(500); // 3 attempts (MAX_RETRIES=2)
      const p = findRepoOwnerInstallationForUser(
        "synthetic-org",
        PERSONAL_INSTALL.account.login,
      );
      await vi.runAllTimersAsync();
      const result = await p; // resolves (does NOT throw out of the function)
      expect(result.installationId).toBeNull();
      expect(result.outcome).toBe("indeterminate");
      expect(membersProbeCallCount()).toBe(3);
    } finally {
      vi.useRealTimers();
    }
  });

  test("AC2 timeout-throw: AbortSignal.timeout on every attempt ⇒ caught → indeterminate → null, no throw", async () => {
    vi.useFakeTimers();
    try {
      const ownerId = uniqueOwnerId();
      mockInstallList(ownerId, "synthetic-org");
      mockTokenMint();
      const timeoutErr = new DOMException("The operation timed out", "TimeoutError");
      mockFetch
        .mockRejectedValueOnce(timeoutErr)
        .mockRejectedValueOnce(timeoutErr)
        .mockRejectedValueOnce(timeoutErr);
      const p = findRepoOwnerInstallationForUser(
        "synthetic-org",
        PERSONAL_INSTALL.account.login,
      );
      await vi.runAllTimersAsync();
      const result = await p;
      expect(result.installationId).toBeNull();
      expect(result.outcome).toBe("indeterminate");
    } finally {
      vi.useRealTimers();
    }
  });

  test("AC3 genuine non-member (404): null, fetch called ONCE for /members (no retry tax)", async () => {
    const ownerId = uniqueOwnerId();
    mockInstallList(ownerId, "victim-org");
    mockTokenMint();
    mockMembership(404);
    const result = await findRepoOwnerInstallationForUser(
      "victim-org",
      "outside-collaborator",
    );
    expect(result.installationId).toBeNull();
    expect(result.outcome).toBe("not-member");
    expect(membersProbeCallCount()).toBe(1); // 404 is authoritative — no retry
  });

  test("AC3 redirect non-member (302): null, fetch called ONCE for /members", async () => {
    const ownerId = uniqueOwnerId();
    mockInstallList(ownerId, "victim-org");
    mockTokenMint();
    mockMembership(302);
    const result = await findRepoOwnerInstallationForUser(
      "victim-org",
      "outside-collaborator",
    );
    expect(result.installationId).toBeNull();
    expect(result.outcome).toBe("not-member");
    expect(membersProbeCallCount()).toBe(1);
  });
});
