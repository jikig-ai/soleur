import { describe, test, expect, vi, beforeEach } from "vitest";
import { stripHostGitBlock } from "../helpers/host-git-block";

// ---------------------------------------------------------------------------
// ADR-044 PR-B — session-sync write relocation (Test Scenarios 7,8,9,10).
//
// `updateLastSynced(service, workspaceId)` writes `workspaces.repo_last_synced_at`
// via `writeRepoColsToWorkspace` (service client injected by the allowlisted
// agent-runner caller), NOT a `users` UPDATE. The id is the caller's ONE
// membership-verified resolved workspace id, so a team-active member's sync
// lands on the TEAM workspace, never their solo userId (Scenario 10, the
// write-side equivalent of the webhook misattribution — load-bearing).
// ---------------------------------------------------------------------------

const {
  mockGitWithInstallationAuth,
  mockGetFreshTenantClient,
  mockResolveInstallationId,
  mockWriteRepoCols,
  mockTenantUpdate,
  mockTenantUpdateEq,
  mockPublish,
  mockHead,
  mergeHead,
  mockMirrorWarn,
} = vi.hoisted(() => {
  const mockTenantUpdateEq = vi.fn().mockResolvedValue({ error: null });
  const mockTenantUpdate = vi.fn(() => ({ eq: mockTenantUpdateEq }));
  return {
    mockGitWithInstallationAuth: vi.fn().mockResolvedValue(Buffer.from("")),
    mockGetFreshTenantClient: vi.fn(),
    mockResolveInstallationId: vi.fn().mockResolvedValue(123),
    mockWriteRepoCols: vi.fn().mockResolvedValue(undefined),
    mockTenantUpdate,
    mockTenantUpdateEq,
    // #12600: the KB-only publish is the seam (its git is asserted on real git in the battery).
    mockPublish: vi.fn(),
    mockHead: vi.fn(),
    mergeHead: { present: false },
    mockMirrorWarn: vi.fn(),
  };
});

// A tenant client whose `.from("users").update(...)` would record a call —
// used to PROVE no `users` write to repo_last_synced_at happens.
function makeTenantClient() {
  return {
    from: (_table: string) => ({
      select: () => ({
        eq: () => ({
          maybeSingle: vi.fn().mockResolvedValue({ data: { id: "u" }, error: null }),
          single: vi.fn().mockResolvedValue({ data: { kb_sync_history: [] }, error: null }),
        }),
      }),
      update: mockTenantUpdate,
    }),
  };
}

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: mockGetFreshTenantClient,
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/server/git-auth", () => ({
  gitWithInstallationAuth: mockGitWithInstallationAuth,
}));

vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: mockResolveInstallationId,
}));

vi.mock("@/server/workspace-repo-mirror", () => ({
  writeRepoColsToWorkspace: mockWriteRepoCols,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: mockMirrorWarn,
  hashUserId: (s: string) => `hash(${s})`,
}));

// git helpers used inside syncPull/syncPush — stub the child_process surface so
// hasRemote/hasLocalCommits report a remote with local commits and the
// auto-commit sweep no-ops cleanly.
vi.mock("child_process", () => ({
  execFileSync: vi.fn((_bin: string, rawArgv: string[]) => {
    const argv = stripHostGitBlock(rawArgv);
    if (argv[0] === "remote") return Buffer.from("origin\tgit@x (fetch)\n");
    if (argv[0] === "rev-list") return Buffer.from("1\n"); // hasLocalCommits → push
    if (argv[0] === "status") return Buffer.from(""); // no allowlisted changes
    return Buffer.from("");
  }),
}));

vi.mock("fs", () => ({
  readdirSync: vi.fn(() => []),
  lstatSync: vi.fn((p: string) => {
    if (mergeHead.present && p.endsWith("MERGE_HEAD")) return {}; // a conflicted session-start merge
    throw Object.assign(new Error("ENOENT"), { code: "ENOENT" }); // host-git shape guard: the fake workspace has no .git
  }),
}));

vi.mock("@/server/approval/workspace-head", () => ({ readWorkspaceHeadRef: mockHead }));
vi.mock("@/server/kb-sync-publish", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/kb-sync-publish")>()),
  publishKbOnly: mockPublish,
}));

import { syncPull, syncPush } from "@/server/session-sync";

const SERVICE = { __service: true } as never;
const USER_ID = "user-solo-1";
const TEAM_WORKSPACE_ID = "team-ws-uuid-99";
const SOLO_WORKSPACE_ID = USER_ID; // solo invariant: workspaces.id == users.id
const WS_PATH = "/tmp/ws/x";

describe("session-sync write relocation (ADR-044 PR-B)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetFreshTenantClient.mockResolvedValue(makeTenantClient());
    mockResolveInstallationId.mockResolvedValue(123);
    mockWriteRepoCols.mockResolvedValue(undefined);
    mockPublish.mockResolvedValue({ kind: "pushed" });
    mockHead.mockReturnValue({ sha: "c".repeat(40), refName: "refs/heads/main" });
    mergeHead.present = false;
  });

  // Scenario 7 — write lands on workspaces, keyed on resolved workspace id.
  test("syncPull → writeRepoColsToWorkspace(service, workspaceId, repo_last_synced_at), no users update", async () => {
    await syncPull(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    expect(mockWriteRepoCols).toHaveBeenCalledTimes(1);
    const [svc, wsId, patch] = mockWriteRepoCols.mock.calls[0];
    expect(svc).toBe(SERVICE);
    expect(wsId).toBe(SOLO_WORKSPACE_ID);
    expect(patch).toHaveProperty("repo_last_synced_at");
    expect(typeof patch.repo_last_synced_at).toBe("string");
    // No tenant `users` UPDATE for repo_last_synced_at.
    expect(mockTenantUpdate).not.toHaveBeenCalledWith(
      expect.objectContaining({ repo_last_synced_at: expect.anything() }),
    );
  });

  // Scenario 8 — read-back parity is structural: the write targets the same
  // workspaces.id the repo/status read keys on. Asserted via the id threading.
  test("syncPush → writes to the SAME workspace id the caller resolved", async () => {
    await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    expect(mockWriteRepoCols).toHaveBeenCalledTimes(1);
    expect(mockWriteRepoCols.mock.calls[0][1]).toBe(SOLO_WORKSPACE_ID);
  });

  // Scenario 9 — best-effort: the 0-row write does not throw. The Sentry-mirror
  // for the 0-row path lives in writeRepoColsToWorkspace (out of this test's
  // scope, which mocks it); session-sync's contract here is only no-throw.
  test("syncPull does not throw when the write is a best-effort no-op", async () => {
    mockWriteRepoCols.mockResolvedValue(undefined);
    await expect(syncPull(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID)).resolves.toBeUndefined();
  });

  // Scenario 10 — team-active member writes to the TEAM workspace, never userId.
  test("team-active member sync writes to the TEAM workspaceId, NOT userId (LOAD-BEARING)", async () => {
    await syncPush(USER_ID, WS_PATH, SERVICE, TEAM_WORKSPACE_ID);
    expect(mockWriteRepoCols).toHaveBeenCalledTimes(1);
    const wsId = mockWriteRepoCols.mock.calls[0][1];
    expect(wsId).toBe(TEAM_WORKSPACE_ID);
    expect(wsId).not.toBe(USER_ID);
  });

  // AC6 (#12600): bookkeeping only after a delivered push. A refused, held or nothing-to-sync turn writes nothing.
  test("held, nothing-to-sync (T == headSha) and failed-fallback turns do not call writeRepoColsToWorkspace", async () => {
    for (const result of [
      { kind: "held", reason: "remote_ahead" },
      { kind: "held", reason: "head_moved" },
      { kind: "noop" },
      { kind: "fallback_failed", fallbackReason: "side_push_rejected", pushErr: new Error("x") },
    ]) {
      mockPublish.mockResolvedValueOnce(result);
      await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    }
    expect(mockPublish).toHaveBeenCalledTimes(4);
    expect(mockWriteRepoCols).not.toHaveBeenCalled();
  });

  test("a refused turn (detached HEAD, merge in progress, publish throws) does not call writeRepoColsToWorkspace", async () => {
    mockHead.mockReturnValueOnce({ sha: "c".repeat(40), refName: null });
    await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    mergeHead.present = true;
    await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    mergeHead.present = false;
    mockPublish.mockRejectedValueOnce(new Error("ls-remote broke"));
    await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    expect(mockPublish).toHaveBeenCalledTimes(1); // only the third turn reached the publish
    expect(mockMirrorWarn.mock.calls.map(([, , , cls]) => cls)).toEqual([
      "kb-sync-push-held:detached_head",
      "kb-sync-push-held:merge_in_progress",
    ]);
    expect(mockWriteRepoCols).not.toHaveBeenCalled();
  });

  test("a delivered protected-branch fallback does write last-synced", async () => {
    mockPublish.mockResolvedValueOnce({ kind: "fallback", prUrl: "https://github.com/acme/widget/pull/1", commitCount: 1 });
    await syncPush(USER_ID, WS_PATH, SERVICE, TEAM_WORKSPACE_ID);
    expect(mockWriteRepoCols).toHaveBeenCalledTimes(1);
    expect(mockWriteRepoCols.mock.calls[0][1]).toBe(TEAM_WORKSPACE_ID);
  });
});
