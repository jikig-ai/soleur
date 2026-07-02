// Tests for the git-data replication transport (server/git-data-replication.ts,
// #5817 PR B part 2 / ADR-068). Verifies: the lease-gen + worktree-id push-options
// ride the git-data push; the gated-off path issues NO provision/push; a push
// failure (e.g. a fence reject) FAILS LOUD (mirrors to Sentry) and re-throws; and
// an unsafe workspace_id is rejected before any SSH.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const gitPush = vi.fn().mockResolvedValue(Buffer.from(""));
const sshProvision = vi.fn().mockResolvedValue(Buffer.from(""));
const reportSilentFallback = vi.fn();
const execFileSyncMock = vi.fn((..._args: unknown[]) => Buffer.from("")); // local `git remote` calls
// D2 write sentinel (Sub-PR 3.C): replicateToGitData now authorizes membership via
// is_workspace_member through a fresh tenant client BEFORE the push. Default the RPC
// to member=true so these WRITE-transport tests exercise the push; the cross-tenant
// DENY path is covered in git-data-client.test.ts.
const rpcMock = vi.fn(async () => ({ data: true, error: null }));

vi.mock("../server/git-auth", () => ({
  gitWithPrivateKeyAuth: (...args: unknown[]) => gitPush(...args),
  sshWithPrivateKeyAuth: (...args: unknown[]) => sshProvision(...args),
}));
// Partial mock: keep warnSilentFallback + hashUserId REAL — git-data-replication
// now transitively imports git-data-client, which uses them; a wholesale factory
// would drop those exports and crash the sibling at call time.
vi.mock("../server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../server/observability")>()),
  reportSilentFallback: (...args: unknown[]) => reportSilentFallback(...args),
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: rpcMock })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));
vi.mock("child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("child_process")>()),
  execFileSync: (...args: unknown[]) => execFileSyncMock(...args),
}));

import {
  replicateToGitData,
  assertSafeWorkspaceId,
  gitDataRemoteUrl,
} from "../server/git-data-replication";

const WS = "ws-uuid-123";
// Per-user worktree id (ADR-068 D0). A UUID in prod; any safe token here.
const WT = "55555555-5555-5555-5555-555555555555";
const USER = "44444444-4444-4444-4444-444444444444";

beforeEach(() => {
  gitPush.mockClear().mockResolvedValue(Buffer.from(""));
  sshProvision.mockClear().mockResolvedValue(Buffer.from(""));
  reportSilentFallback.mockClear();
  execFileSyncMock.mockClear().mockReturnValue(Buffer.from(""));
  rpcMock.mockClear().mockResolvedValue({ data: true, error: null });
  vi.stubEnv("GIT_TRANSPORT_SSH_PRIVATE_KEY", "transport-key");
  vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "provision-key");
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("gitDataRemoteUrl / assertSafeWorkspaceId", () => {
  it("composes an ssh:// URL under the reconciled /repositories path", () => {
    expect(gitDataRemoteUrl(WS)).toBe(`ssh://git@10.0.1.20/repositories/${WS}.git`);
  });

  it("rejects path-traversal / unsafe workspace ids (CWE-22)", () => {
    for (const bad of ["..", ".", "a/b", "a b", "a;rm", ""]) {
      expect(() => assertSafeWorkspaceId(bad)).toThrow();
    }
  });
});

describe("replicateToGitData — gated off (GIT_DATA_STORE_ENABLED unset)", () => {
  it("issues NO provision, no remote config, no push", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "");
    await replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 4 , userId: USER });
    expect(sshProvision).not.toHaveBeenCalled();
    expect(gitPush).not.toHaveBeenCalled();
    expect(execFileSyncMock).not.toHaveBeenCalled();
  });
});

describe("replicateToGitData — gated on", () => {
  beforeEach(() => vi.stubEnv("GIT_DATA_STORE_ENABLED", "true"));

  it("pushes to the PER-USER namespaced refspec (D0-ref) carrying lease-gen + per-user worktree-id", async () => {
    await replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 7 , userId: USER });

    // Provision ran first (idempotent init before the first push).
    expect(sshProvision).toHaveBeenCalledTimes(1);
    expect(sshProvision.mock.calls[0][1]).toBe(WS); // opaque remote arg = workspace_id

    expect(gitPush).toHaveBeenCalledTimes(1);
    const pushArgs = gitPush.mock.calls[0][0] as string[];
    expect(pushArgs).toContain("push");
    expect(pushArgs).toContain("git-data");
    // Fence push-options ride this push — worktree-id is now PER-USER, not "primary".
    expect(pushArgs).toContain("--push-option=lease-gen=7");
    expect(pushArgs).toContain(`--push-option=worktree-id=${WT}`);
    expect(pushArgs).not.toContain("--push-option=worktree-id=primary");
    // Heads + tags land under refs/soleur/worktrees/<worktreeId>/ — this user is
    // the SOLE writer of its namespace, so --force stays safe under a 2nd writer.
    expect(pushArgs).toContain(`refs/heads/*:refs/soleur/worktrees/${WT}/heads/*`);
    expect(pushArgs).toContain(`refs/tags/*:refs/soleur/worktrees/${WT}/tags/*`);
    // D0-ref NEGATIVE: the clobbering shared-ref refspec MUST be gone — under a
    // 2nd writer `refs/heads/*:refs/heads/*` --force silently overwrites a peer's
    // commits (the whole reason 3.B must land before the flag flip).
    expect(pushArgs).not.toContain("refs/heads/*:refs/heads/*");
    // The push uses the TRANSPORT key, not the provision key.
    expect(gitPush.mock.calls[0][1]).toBe("transport-key");
  });

  it("rejects an unsafe worktree_id BEFORE any provision/push (CWE-22)", async () => {
    await expect(
      replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: "../evil", leaseGeneration: 1 , userId: USER }),
    ).rejects.toThrow(/worktree.?id/i);
    expect(sshProvision).not.toHaveBeenCalled();
    expect(gitPush).not.toHaveBeenCalled();
  });

  it("FAILS LOUD on a push failure (fence reject): mirrors to Sentry + re-throws", async () => {
    gitPush.mockRejectedValueOnce(
      new Error("remote: git-data fence: stale lease generation 3 < stored max 5 — rejected"),
    );

    await expect(
      replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 3 , userId: USER }),
    ).rejects.toThrow(/stale lease generation/);

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const opts = reportSilentFallback.mock.calls[0][1] as { feature: string; op: string };
    expect(opts.feature).toBe("worktree_lease");
    expect(opts.op).toBe("git_data_replication_push");
  });

  it("rejects an unsafe workspace_id BEFORE any provision/push", async () => {
    await expect(
      replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: "../evil", worktreeId: WT, leaseGeneration: 1 , userId: USER }),
    ).rejects.toThrow();
    expect(sshProvision).not.toHaveBeenCalled();
    expect(gitPush).not.toHaveBeenCalled();
  });
});
