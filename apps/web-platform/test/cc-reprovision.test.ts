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
} = vi.hoisted(() => ({
  mockFetchUserWorkspacePath: vi.fn(),
  mockResolveInstallationId: vi.fn(),
  mockGetCurrentRepoUrl: vi.fn(),
  mockResolveEffectiveInstallationId: vi.fn(),
  mockEnsureWorkspaceRepoCloned: vi.fn(),
  mockReportSilentFallback: vi.fn(),
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

import { reprovisionWorkspaceOnDispatch } from "@/server/cc-reprovision";

const USER = "user-1";
const WS = "/workspaces/ws-uuid";
const REPO = "https://github.com/acme/widget";
const INSTALL = 4242;

beforeEach(() => {
  vi.clearAllMocks();
  mockFetchUserWorkspacePath.mockResolvedValue(WS);
  mockResolveInstallationId.mockResolvedValue(INSTALL);
  mockGetCurrentRepoUrl.mockResolvedValue(REPO);
  // Default: effective-install promotion is a pass-through (stored === owner).
  mockResolveEffectiveInstallationId.mockImplementation(
    async ({ installationId }: { installationId: number | null }) => installationId,
  );
  mockEnsureWorkspaceRepoCloned.mockResolvedValue("ok");
});

describe("reprovisionWorkspaceOnDispatch (warm-query reconnect coverage)", () => {
  it("resolves the membership-scoped inputs and calls the recovery once", async () => {
    await reprovisionWorkspaceOnDispatch(USER);
    expect(mockFetchUserWorkspacePath).toHaveBeenCalledWith(USER);
    expect(mockResolveInstallationId).toHaveBeenCalledWith(USER);
    expect(mockGetCurrentRepoUrl).toHaveBeenCalledWith(USER);
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
