// Tests for the git-data cross-tenant isolation boundary — epic #5274 Phase 3
// Sub-PR 3.C / ADR-068 §6 (AC3). Security invariants asserted at the RPC/argv
// entry (never via an LLM prompt): a non-member session (a) CANNOT read
// tenant-B git-data (fetch authz, GitDataAuthorizationError, no transport call),
// (b) CANNOT write tenant-B git-data (D2 write-boundary sentinel in
// replicateToGitData — TS-1: no push), and (c) a non-member / indeterminate RPC
// fails CLOSED. The whole boundary is inert at flag-off (dark until the 3.D flip).

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const gitTransport = vi.fn().mockResolvedValue(Buffer.from("")); // push + fetch
const sshProvision = vi.fn().mockResolvedValue(Buffer.from(""));
const execFileSyncMock = vi.fn((..._args: unknown[]) => Buffer.from("")); // local `git remote`
const rpcMock = vi.fn();
const warnSpy = vi.fn();
const reportSpy = vi.fn();

vi.mock("@/server/git-auth", () => ({
  gitWithPrivateKeyAuth: (...args: unknown[]) => gitTransport(...args),
  sshWithPrivateKeyAuth: (...args: unknown[]) => sshProvision(...args),
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: rpcMock })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  warnSilentFallback: (...args: unknown[]) => warnSpy(...args),
  reportSilentFallback: (...args: unknown[]) => reportSpy(...args),
}));
vi.mock("child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("child_process")>()),
  execFileSync: (...args: unknown[]) => execFileSyncMock(...args),
}));

import {
  authorizeGitDataAccess,
  fetchFromGitData,
  GitDataAuthorizationError,
} from "@/server/git-data-client";
import { replicateToGitData } from "@/server/git-data-replication";
import { RuntimeAuthError } from "@/lib/supabase/tenant";

const WS_A = "11111111-1111-1111-1111-111111111111";
const WS_B = "22222222-2222-2222-2222-222222222222";
const USER_A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const WT = "33333333-3333-3333-3333-333333333333";

beforeEach(() => {
  gitTransport.mockClear().mockResolvedValue(Buffer.from(""));
  sshProvision.mockClear().mockResolvedValue(Buffer.from(""));
  execFileSyncMock.mockClear().mockReturnValue(Buffer.from(""));
  rpcMock.mockReset();
  warnSpy.mockClear();
  reportSpy.mockClear();
  vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
  vi.stubEnv("GIT_TRANSPORT_SSH_PRIVATE_KEY", "transport-key");
  vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "provision-key");
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("authorizeGitDataAccess — fail-closed membership gate", () => {
  it("authorizes a confirmed member (RPC → true)", async () => {
    rpcMock.mockResolvedValue({ data: true, error: null });
    const ok = await authorizeGitDataAccess({ userId: USER_A, workspaceId: WS_A, op: "fetch" });
    expect(ok).toBe(true);
    expect(rpcMock).toHaveBeenCalledWith("is_workspace_member", {
      p_workspace_id: WS_A,
      p_user_id: USER_A,
    });
    expect(warnSpy).not.toHaveBeenCalled();
    expect(reportSpy).not.toHaveBeenCalled();
  });

  it("(c) DENIES a confirmed non-member (RPC → false) + security breadcrumb", async () => {
    rpcMock.mockResolvedValue({ data: false, error: null });
    const ok = await authorizeGitDataAccess({ userId: USER_A, workspaceId: WS_B, op: "fetch" });
    expect(ok).toBe(false);
    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(warnSpy.mock.calls[0][1]).toMatchObject({
      feature: "git-data-authz",
      op: "fetch-deny",
    });
    // The raw workspaceId must NOT appear in telemetry extra (hashed).
    expect(warnSpy.mock.calls[0][1].extra).not.toHaveProperty("workspaceId");
  });

  it("DENIES (fail-closed) on RPC error + error breadcrumb", async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: "boom", code: "42501" } });
    const ok = await authorizeGitDataAccess({ userId: USER_A, workspaceId: WS_A, op: "write" });
    expect(ok).toBe(false);
    expect(reportSpy).toHaveBeenCalledTimes(1);
    expect(reportSpy.mock.calls[0][1]).toMatchObject({ feature: "git-data-authz", op: "write-deny" });
  });

  it("DENIES (fail-closed) when userId is missing", async () => {
    const ok = await authorizeGitDataAccess({ userId: undefined, workspaceId: WS_A, op: "write" });
    expect(ok).toBe(false);
    expect(rpcMock).not.toHaveBeenCalled();
    expect(reportSpy).toHaveBeenCalledTimes(1);
  });

  it("DENIES (fail-closed) when the tenant client throws RuntimeAuthError", async () => {
    const { getFreshTenantClient } = await import("@/lib/supabase/tenant");
    vi.mocked(getFreshTenantClient).mockRejectedValueOnce(new RuntimeAuthError("jwt_mint", "no jwt"));
    const ok = await authorizeGitDataAccess({ userId: USER_A, workspaceId: WS_A, op: "fetch" });
    expect(ok).toBe(false);
    expect(reportSpy).toHaveBeenCalledTimes(1);
  });
});

describe("fetchFromGitData — authorized read", () => {
  it("(a) a non-member CANNOT read tenant-B git-data (throws, no transport)", async () => {
    rpcMock.mockResolvedValue({ data: false, error: null });
    await expect(
      fetchFromGitData({ userId: USER_A, workspaceId: WS_B, worktreeId: WT, workspacePath: "/tmp/ws" }),
    ).rejects.toBeInstanceOf(GitDataAuthorizationError);
    expect(gitTransport).not.toHaveBeenCalled();
  });

  it("a confirmed member fetches its own worktree namespace into REMOTE-TRACKING refs (never local heads — 3.D data-loss guard)", async () => {
    rpcMock.mockResolvedValue({ data: true, error: null });
    await fetchFromGitData({ userId: USER_A, workspaceId: WS_A, worktreeId: WT, workspacePath: "/tmp/ws" });
    expect(gitTransport).toHaveBeenCalledTimes(1);
    const argv = gitTransport.mock.calls[0][0] as string[];
    expect(argv).toContain("fetch");
    // CTO ruling (3.D): the fetch lands in refs/remotes/git-data/* — a remote-
    // tracking namespace git can NEVER refuse and that can never discard a
    // checked-out branch. The caller (ensure-workspace-repo fresh-graft) does a
    // guarded `reset --hard refs/remotes/git-data/<primary>` to overlay the tip.
    expect(argv).toContain(`+refs/soleur/worktrees/${WT}/heads/*:refs/remotes/git-data/*`);
    expect(argv).toContain(`+refs/soleur/worktrees/${WT}/tags/*:refs/tags/*`);
    // NEGATIVE (the data-loss hazard the retarget closes): NO refspec destination
    // may map into a local branch — a `+…:refs/heads/*` force-fetch into a live
    // checked-out branch discards local-only commits.
    expect(argv.some((a) => a.includes(":refs/heads/"))).toBe(false);
    // The transport target MUST be the EXPLICIT URL built from the authorized
    // workspaceId — never a local remote NAME that could point at another tenant.
    expect(argv).toContain(`ssh://git@10.0.1.20/repositories/${WS_A}.git`);
    expect(argv).not.toContain("git-data");
  });

  it("is a NO-OP at flag-off (no authz, no transport)", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "");
    await fetchFromGitData({ userId: USER_A, workspaceId: WS_A, worktreeId: WT, workspacePath: "/tmp/ws" });
    expect(rpcMock).not.toHaveBeenCalled();
    expect(gitTransport).not.toHaveBeenCalled();
  });
});

describe("replicateToGitData — D2 write-boundary sentinel (TS-1)", () => {
  it("(b) a non-member CANNOT write tenant-B git-data (rejects, NO push)", async () => {
    rpcMock.mockResolvedValue({ data: false, error: null });
    await expect(
      replicateToGitData({
        workspacePath: "/tmp/ws",
        workspaceId: WS_B,
        worktreeId: WT,
        leaseGeneration: 4,
        userId: USER_A,
      }),
    ).rejects.toBeInstanceOf(GitDataAuthorizationError);
    // TS-1: the transport push MUST NOT fire on a denied write.
    expect(gitTransport).not.toHaveBeenCalled();
    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(warnSpy.mock.calls[0][1]).toMatchObject({ feature: "git-data-authz", op: "write-deny" });
  });

  it("a confirmed member's write proceeds to the fenced push", async () => {
    rpcMock.mockResolvedValue({ data: true, error: null });
    await replicateToGitData({
      workspacePath: "/tmp/ws",
      workspaceId: WS_A,
      worktreeId: WT,
      leaseGeneration: 4,
      userId: USER_A,
    });
    expect(gitTransport).toHaveBeenCalledTimes(1);
    const argv = gitTransport.mock.calls[0][0] as string[];
    expect(argv).toContain("push");
    expect(argv).toContain(`refs/heads/*:refs/soleur/worktrees/${WT}/heads/*`);
  });

  it("DENIES (fail-closed) and does NOT push on an indeterminate RPC error", async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: "db down" } });
    await expect(
      replicateToGitData({
        workspacePath: "/tmp/ws",
        workspaceId: WS_A,
        worktreeId: WT,
        leaseGeneration: 4,
        userId: USER_A,
      }),
    ).rejects.toBeInstanceOf(GitDataAuthorizationError);
    expect(gitTransport).not.toHaveBeenCalled();
  });
});
