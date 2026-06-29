// #5340 / #5240 design item #2 — warm-query reconnect coverage for the
// Concierge (cc) path.
//
// LOAD-BEARING (deepen finding): the cc `realSdkQueryFactory` (which holds the
// existing `ensureWorkspaceRepoCloned` self-heal at cc-dispatcher.ts:1469) runs
// ONLY on a COLD conversation — on warm-query reuse it is NOT re-invoked. The
// reconnect scenario the epic targets is frequently a *warm* resume, so the
// re-provision + result publish must run per-dispatch (not only inside the cold
// factory). This module is the per-dispatch resolve, mirroring the
// fire-and-forget `resolveBashAutonomous` warm-query resolve at
// cc-dispatcher.ts:2348. It publishes the `ReprovisionOutcome` the
// honest-message branch reads on BOTH cold and warm turns.

import { describe, it, expect, vi, beforeEach } from "vitest";

const {
  mockFetchUserWorkspacePath,
  mockResolveInstallationId,
  mockGetCurrentRepoUrl,
  mockResolveEffectiveInstallationId,
  mockEnsureWorkspaceRepoCloned,
  mockReportSilentFallback,
  mockGetFreshTenantClient,
  mockResolveActiveWorkspace,
  mockExistsSync,
} = vi.hoisted(() => ({
  mockFetchUserWorkspacePath: vi.fn(),
  mockResolveInstallationId: vi.fn(),
  mockGetCurrentRepoUrl: vi.fn(),
  mockResolveEffectiveInstallationId: vi.fn(),
  mockEnsureWorkspaceRepoCloned: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockGetFreshTenantClient: vi.fn(),
  mockResolveActiveWorkspace: vi.fn(),
  mockExistsSync: vi.fn(),
}));

vi.mock("@/server/kb-document-resolver", () => ({
  fetchUserWorkspacePath: mockFetchUserWorkspacePath,
}));
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: mockResolveInstallationId,
}));
vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: mockGetCurrentRepoUrl,
}));
vi.mock("@/server/cc-effective-installation", () => ({
  resolveEffectiveInstallationId: mockResolveEffectiveInstallationId,
}));
vi.mock("@/server/ensure-workspace-repo", () => ({
  ensureWorkspaceRepoCloned: mockEnsureWorkspaceRepoCloned,
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));
// ADR-044 PR-3: the membership-verified single-resolve seam. `getFreshTenantClient`
// is the tenant client `resolveActiveWorkspace` reads through; both are mocked at
// the module boundary so the reprovision path's resolve-once-and-thread is testable
// without a live DB.
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: mockGetFreshTenantClient,
}));
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspace: mockResolveActiveWorkspace,
}));
// #5715 — the `.git` short-circuit hoisted INTO reprovisionWorkspaceOnDispatch
// stats the resolved workspace path before the install/repo resolves + clone.
// Mock `existsSync` so the early-return discriminator is deterministic (default
// false → `.git` ABSENT → proceed to clone, preserving the pre-#5715 tests).
vi.mock("node:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs")>();
  return { ...actual, existsSync: mockExistsSync };
});

import { reprovisionWorkspaceOnDispatch } from "@/server/cc-reprovision";
// The breadcrumb module is NOT mocked — it runs for real and emits through the
// mocked `reportSilentFallback`, so AC4 asserts the breadcrumb's security-safe
// shape end-to-end. Its module-level dedupe set must be reset between cases.
import { _resetResolverDivergenceDedupeForTests } from "@/server/repo-resolver-divergence";

const USER = "user-1";
const ACTIVE = "ws-active-id"; // membership-verified active workspace id (solo owner: === USER)
const TEAM = "team-ws-id"; // a team-workspace claim id
const WS = "/workspaces/ws-uuid";
const REPO = "https://github.com/acme/widget";
const INSTALL = 4242;

beforeEach(() => {
  vi.clearAllMocks();
  _resetResolverDivergenceDedupeForTests();
  mockGetFreshTenantClient.mockResolvedValue({});
  // Default: solo owner — the membership-verified resolve returns the caller's
  // own workspace, no reset.
  mockResolveActiveWorkspace.mockResolvedValue({ ok: true, workspaceId: ACTIVE });
  mockFetchUserWorkspacePath.mockResolvedValue(WS);
  mockResolveInstallationId.mockResolvedValue(INSTALL);
  mockGetCurrentRepoUrl.mockResolvedValue(REPO);
  // Default: effective-install promotion is a pass-through (stored === owner).
  mockResolveEffectiveInstallationId.mockImplementation(
    async ({ installationId }: { installationId: number | null }) => installationId,
  );
  mockEnsureWorkspaceRepoCloned.mockResolvedValue("ok");
  // Default: `.git` ABSENT (reclaimed workspace) so the recovery proceeds to the
  // clone — the pre-#5715 behavior these suites assert.
  mockExistsSync.mockReturnValue(false);
});

describe("reprovisionWorkspaceOnDispatch (warm-query reconnect coverage)", () => {
  it("resolves the membership-scoped inputs and calls the recovery once", async () => {
    await reprovisionWorkspaceOnDispatch(USER);
    // ADR-044 PR-3: the active workspace is resolved ONCE (membership-verified)
    // and the single id is threaded into all three consumers — no bare-userId
    // (raw-claim) re-derivation.
    expect(mockResolveActiveWorkspace).toHaveBeenCalledTimes(1);
    expect(mockGetFreshTenantClient).toHaveBeenCalledTimes(1);
    expect(mockFetchUserWorkspacePath).toHaveBeenCalledWith(USER, ACTIVE);
    expect(mockResolveInstallationId).toHaveBeenCalledWith(USER, ACTIVE);
    expect(mockGetCurrentRepoUrl).toHaveBeenCalledWith(USER, ACTIVE);
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledTimes(1);
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith({
      userId: USER,
      workspacePath: WS,
      installationId: INSTALL,
      repoUrl: REPO,
    });
  });

  it("clones with the PROMOTED (effective) install, not the raw stored one — parity with the cold factory (review finding)", async () => {
    const OWNER_INSTALL = 9999;
    // Stored personal install does not own the org repo → promoted to owner.
    mockResolveEffectiveInstallationId.mockResolvedValue(OWNER_INSTALL);
    await reprovisionWorkspaceOnDispatch(USER);
    expect(mockResolveEffectiveInstallationId).toHaveBeenCalledWith({
      userId: USER,
      installationId: INSTALL,
      repoUrl: REPO,
    });
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
      expect.objectContaining({ installationId: OWNER_INSTALL }),
    );
  });

  it("propagates the recovery outcome — 'ok' when the repo is present/cloned", async () => {
    mockEnsureWorkspaceRepoCloned.mockResolvedValue("ok");
    await expect(reprovisionWorkspaceOnDispatch(USER)).resolves.toBe("ok");
  });

  it("propagates 'failed' when the re-clone genuinely fails (the honest-message signal)", async () => {
    mockEnsureWorkspaceRepoCloned.mockResolvedValue("failed");
    await expect(reprovisionWorkspaceOnDispatch(USER)).resolves.toBe("failed");
  });

  // #5715 AC11 — forced-slow-path observability: a resolver outage that yields
  // no path cannot stat `.git`, so it fails soft to "ok" (no false reclaim
  // message) BUT emits a distinct breadcrumb so the slow-path forcing is
  // queryable in Sentry, not silent.
  it("AC11: workspace path unresolved → fail-soft 'ok' + distinct 'workspace-path-unresolved' breadcrumb, NO clone", async () => {
    mockFetchUserWorkspacePath.mockResolvedValue("");

    await expect(reprovisionWorkspaceOnDispatch(USER)).resolves.toBe("ok");

    expect(mockExistsSync).not.toHaveBeenCalled();
    expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "cc-dispatcher",
      op: "reprovision-on-dispatch-path-unresolved",
      extra: { reason: "workspace-path-unresolved" },
    });
  });

  // #5715 AC2/AC4 — `.git` PRESENT short-circuit hoisted before the heavy
  // install/repo resolves + clone. One membership-verified resolve feeds the
  // stat; a present `.git` is NEVER re-cloned (safety invariant).
  it("AC2/AC4: `.git` present → early-return 'ok', NO install/repo resolve, NO clone", async () => {
    mockExistsSync.mockReturnValue(true);
    await expect(reprovisionWorkspaceOnDispatch(USER)).resolves.toBe("ok");
    // The workspace path WAS resolved (it is what we stat) ...
    expect(mockFetchUserWorkspacePath).toHaveBeenCalledWith(USER, ACTIVE);
    expect(mockExistsSync).toHaveBeenCalledTimes(1);
    expect(mockExistsSync.mock.calls[0][0]).toContain(WS);
    expect(mockExistsSync.mock.calls[0][0]).toContain(".git");
    // ... but the heavier resolves + the clone are skipped entirely.
    expect(mockResolveInstallationId).not.toHaveBeenCalled();
    expect(mockGetCurrentRepoUrl).not.toHaveBeenCalled();
    expect(mockResolveEffectiveInstallationId).not.toHaveBeenCalled();
    expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
  });

  it("fail-soft: a resolver error returns 'ok' (NOT 'failed') and mirrors to Sentry", async () => {
    // A transient resolve failure is NOT a clone failure — returning "failed"
    // would surface a false honest "workspace reclaimed" message. Fail closed to
    // the generic route and mirror so it is queryable.
    mockFetchUserWorkspacePath.mockRejectedValue(new Error("resolve boom"));
    await expect(reprovisionWorkspaceOnDispatch(USER)).resolves.toBe("ok");
    expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "cc-dispatcher",
      op: "reprovision-on-dispatch",
    });
  });
});

describe("reprovisionWorkspaceOnDispatch — membership-verified single resolve (ADR-044 PR-3)", () => {
  it("(a) solo owner: claim === userId → path/install/repo all key to userId, no breadcrumb", async () => {
    mockResolveActiveWorkspace.mockResolvedValue({ ok: true, workspaceId: USER });

    await reprovisionWorkspaceOnDispatch(USER);

    expect(mockResolveActiveWorkspace).toHaveBeenCalledTimes(1);
    expect(mockFetchUserWorkspacePath).toHaveBeenCalledWith(USER, USER);
    expect(mockResolveInstallationId).toHaveBeenCalledWith(USER, USER);
    expect(mockGetCurrentRepoUrl).toHaveBeenCalledWith(USER, USER);
    // No reset → no divergence breadcrumb (the only reportSilentFallback consumer
    // here would be the breadcrumb; the success path mirrors nothing).
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("(b) member of team: confirmed team claim → path/install/repo all key to the TEAM id (no solo/team split)", async () => {
    mockResolveActiveWorkspace.mockResolvedValue({ ok: true, workspaceId: TEAM });
    // Make the resolved path team-derived so the clone-target assertion below
    // genuinely distinguishes team-vs-solo (not just the threading args).
    const TEAM_WS = `/workspaces/${TEAM}`;
    mockFetchUserWorkspacePath.mockResolvedValue(TEAM_WS);

    await reprovisionWorkspaceOnDispatch(USER);

    expect(mockFetchUserWorkspacePath).toHaveBeenCalledWith(USER, TEAM);
    expect(mockResolveInstallationId).toHaveBeenCalledWith(USER, TEAM);
    expect(mockGetCurrentRepoUrl).toHaveBeenCalledWith(USER, TEAM);
    // The clone targets the membership-verified team workspace path, not solo.
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
      expect.objectContaining({ userId: USER, workspacePath: TEAM_WS }),
    );
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("(c) non-member/stale claim reset: probe resets to solo → all consumers key userId, AND the divergence breadcrumb fires (op=reprovision-non-member-claim-reset)", async () => {
    mockResolveActiveWorkspace.mockResolvedValue({
      ok: true,
      workspaceId: USER,
      resetFromClaim: TEAM,
    });

    await reprovisionWorkspaceOnDispatch(USER);

    // Reset → all three consumers key the caller's OWN solo workspace, never the team.
    expect(mockFetchUserWorkspacePath).toHaveBeenCalledWith(USER, USER);
    expect(mockResolveInstallationId).toHaveBeenCalledWith(USER, USER);
    expect(mockGetCurrentRepoUrl).toHaveBeenCalledWith(USER, USER);

    // AC4 — the breadcrumb fires through reportSilentFallback with the new op and
    // the security-safe two-workspace-id extra shape (no repoUrl/installationId).
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, ctx] = mockReportSilentFallback.mock.calls[0];
    expect((err as Error).message).toBe("repo_resolver_divergence");
    expect(ctx.feature).toBe("repo-resolver-divergence");
    expect(ctx.op).toBe("reprovision-non-member-claim-reset");
    expect(ctx.extra).toMatchObject({
      activeClaimWorkspaceId: TEAM,
      resolvedWorkspaceId: USER,
    });
    expect(ctx.extra).not.toHaveProperty("repoUrl");
    expect(ctx.extra).not.toHaveProperty("installationId");
  });

  it("(d) membership-probe db-error: resolve {ok:false} → reprovision SKIPPED (returns 'ok', no clone into an unverified location), no breadcrumb", async () => {
    mockResolveActiveWorkspace.mockResolvedValue({ ok: false, reason: "db-error" });

    await expect(reprovisionWorkspaceOnDispatch(USER)).resolves.toBe("ok");

    // Skip is fail-closed: never resolve consumers / clone into an unverified
    // location, never throw, never emit a false divergence breadcrumb. (The
    // db-error itself is mirrored inside resolveActiveWorkspace, mocked here.)
    expect(mockFetchUserWorkspacePath).not.toHaveBeenCalled();
    expect(mockResolveInstallationId).not.toHaveBeenCalled();
    expect(mockGetCurrentRepoUrl).not.toHaveBeenCalled();
    expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });
});
