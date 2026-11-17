import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
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
  mockMerge,
  mockAdopt,
  mockWriteHeld,
  mockCompute,
  mockRecovered,
  mockReport,
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
    // #12718: the hardened pull's two steps are the seam here (their git is asserted on real git in
    // test/session-sync-pull-isolated-real-git.test.ts); this suite pins only the stamp around them.
    mockMerge: vi.fn(),
    mockAdopt: vi.fn(),
    // #12714: the held-files write and its computation are the seams (the count's git is asserted on real git in
    // test/kb-sync-held-real-git.test.ts; the helper's own UPDATE in test/workspace-repo-mirror.test.ts).
    mockWriteHeld: vi.fn().mockResolvedValue(undefined),
    mockCompute: vi.fn(),
    mockRecovered: vi.fn(),
    mockReport: vi.fn(),
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
  writeKbSyncHeldCols: mockWriteHeld,
}));

vi.mock("@/server/kb-sync-held", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/kb-sync-held")>()),
  computeHeldFiles: mockCompute,
  readRecoveredKbSyncTips: mockRecovered,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: mockMirrorWarn,
  mirrorWithDebounce: vi.fn(),
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

vi.mock("@/server/current-repo-url", () => ({ getCurrentRepoUrl: async () => "https://github.com/acme/widget" }));
vi.mock("@/server/git-isolated-push-dir", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/git-isolated-push-dir")>()),
  createIsolatedPushDir: () => ({ gitDir: "/tmp/iso", dispose: () => {} }),
}));
vi.mock("@/server/kb-sync-pull", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/kb-sync-pull")>()),
  mergeVerifiedDefault: mockMerge,
  adoptSideTip: mockAdopt,
}));

import { syncPull, syncPush } from "@/server/session-sync";
import { KbSyncError, type KbPublishInput } from "@/server/kb-sync-publish";

const SERVICE = { __service: true } as never;
const USER_ID = "user-solo-1";
const TEAM_WORKSPACE_ID = "team-ws-uuid-99";
const SOLO_WORKSPACE_ID = USER_ID; // solo invariant: workspaces.id == users.id
const WS_PATH = "/tmp/ws/x";
const T_SHA = "f".repeat(40);
const HEAD_SHA = "c".repeat(40);
const ISO_DIR = { gitDir: "/tmp/iso", dispose: () => {} };

/** The publish seam as `publishKbOnly` behaves: the hook runs before the isolated dir is disposed, on every exit past the
 * remote read (held exits and throws included). `hook: false` is an exit before the remote read (no dir, no tip). */
function publishWith(outcome: { result?: unknown; throws?: unknown; hook?: boolean }) {
  return async (input: KbPublishInput) => {
    if (outcome.hook !== false) await input.onHeldFiles?.({ isolatedDir: ISO_DIR as never, T: T_SHA, headSha: input.headSha });
    if (outcome.throws !== undefined) throw outcome.throws;
    return outcome.result;
  };
}

const heldWrites = (): Array<[string, { heldFiles: number | null; checkedAt: Date }]> =>
  mockWriteHeld.mock.calls.map(([, ws, patch]) => [ws, patch]);

describe("session-sync write relocation (ADR-044 PR-B)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetFreshTenantClient.mockResolvedValue(makeTenantClient());
    mockResolveInstallationId.mockResolvedValue(123);
    mockWriteRepoCols.mockResolvedValue(undefined);
    mockPublish.mockResolvedValue({ kind: "pushed" });
    mockHead.mockReturnValue({ sha: "c".repeat(40), refName: "refs/heads/main" });
    mergeHead.present = false;
    mockMerge.mockResolvedValue({ reason: "merged", remote: { defaultBranch: "main", tip: "f".repeat(40), sideTip: null } });
    mockAdopt.mockResolvedValue(null);
    mockWriteHeld.mockResolvedValue(undefined);
    mockCompute.mockResolvedValue(null);
    mockRecovered.mockReturnValue([]);
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

  // #12718 X1: the stamp follows the pull's reason: in sync with GitHub after up_to_date, merged and autostash_conflict
  // (a merge that exited 0); never after a held, refused or conflicted pull, or a non-default branch.
  test.each([
    ["up_to_date", 1],
    ["merged", 1],
    ["autostash_conflict", 1],
    ["merge_conflict", 0],
    ["merge_refused", 0],
    ["fetch_failed", 0],
    ["tip_mismatch", 0],
    ["remote_state", 0],
    ["non_default_branch", 0],
    // Review Phase 0: the widened reasons never stamp.
    ["untracked_collision", 0],
    ["merge_unverified", 0],
    ["pull_deadline", 0],
    ["side_pr_create_failed", 0],
    ["pull_unexpected", 0],
  ] as const)("syncPull %s -> %i repo_last_synced_at write(s)", async (reason, writes) => {
    mockMerge.mockResolvedValue({ reason, remote: null });
    await expect(syncPull(USER_ID, WS_PATH, SERVICE, TEAM_WORKSPACE_ID)).resolves.toEqual({ heldFiles: null, onRecovered: null, pullReason: reason, checkedAt: null });
    expect(mockWriteRepoCols).toHaveBeenCalledTimes(writes);
    if (writes) expect(mockWriteRepoCols.mock.calls[0][1]).toBe(TEAM_WORKSPACE_ID);
  });

  test("syncPull: a half-done merge (MERGE_HEAD) refuses before the pull: no merge, no stamp", async () => {
    mergeHead.present = true;
    await expect(syncPull(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID)).resolves.toEqual({
      heldFiles: null,
      onRecovered: null,
      pullReason: "unresolved_merge",
      checkedAt: null,
    });
    expect(mockMerge).not.toHaveBeenCalled();
    expect(mockWriteRepoCols).not.toHaveBeenCalled();
  });

  // Scenario 9 — best-effort: the 0-row write does not throw. The Sentry-mirror
  // for the 0-row path lives in writeRepoColsToWorkspace (out of this test's
  // scope, which mocks it); session-sync's contract here is only no-throw.
  test("syncPull does not throw when the write is a best-effort no-op", async () => {
    mockWriteRepoCols.mockResolvedValue(undefined);
    await expect(syncPull(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID)).resolves.toEqual({ heldFiles: null, onRecovered: null, pullReason: "merged", checkedAt: null });
    mockWriteRepoCols.mockRejectedValueOnce(new Error("0 rows"));
    // a write that throws lands in the pull's outer catch: reported, and the pull still resolves
    await expect(syncPull(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID)).resolves.toEqual({ heldFiles: null, onRecovered: null, pullReason: null, checkedAt: null });
  });

  // Scenario 10 (pull side) — team-active member stamps the TEAM workspace, never userId.
  test("team-active member pull stamps the TEAM workspaceId, NOT userId (LOAD-BEARING)", async () => {
    await syncPull(USER_ID, WS_PATH, SERVICE, TEAM_WORKSPACE_ID);
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

  // W5 / D29(9) / AC17: only syncPull stamps `repo_last_synced_at` ("Updated from GitHub" stays true). A delivered push or
  // protected-branch fallback no longer stamps it.
  test("syncPush never stamps repo_last_synced_at (pushed, delivered fallback)", async () => {
    mockPublish.mockResolvedValueOnce({ kind: "pushed" });
    await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    mockPublish.mockResolvedValueOnce({ kind: "fallback", prUrl: "https://github.com/acme/widget/pull/1", commitCount: 1 });
    await syncPush(USER_ID, WS_PATH, SERVICE, TEAM_WORKSPACE_ID);
    expect(mockPublish).toHaveBeenCalledTimes(2);
    expect(mockWriteRepoCols).not.toHaveBeenCalled();
  });
});

// TW2 (#12714, D29(1), D33): every sync that computed a held-files count writes it through the SEPARATE service-client
// helper, with `kb_sync_held_checked_at` advancing; no count computed -> no write (never a guessed 0); a failed write
// sends one mirror and leaves the sync's result unchanged.
describe("held-files write (TW2)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-11-17T10:00:00.000Z"));
    mockGetFreshTenantClient.mockResolvedValue(makeTenantClient());
    mockResolveInstallationId.mockResolvedValue(123);
    mockWriteRepoCols.mockResolvedValue(undefined);
    mockWriteHeld.mockResolvedValue(undefined);
    mockHead.mockReturnValue({ sha: HEAD_SHA, refName: "refs/heads/main" });
    mergeHead.present = false;
    mockRecovered.mockReturnValue([]);
    mockCompute.mockResolvedValue({ total: 2, onRecovered: 0 });
    mockMerge.mockResolvedValue({ reason: "up_to_date", remote: { defaultBranch: "main", tip: T_SHA, sideTip: null } });
    mockAdopt.mockResolvedValue(null);
  });
  afterEach(() => vi.useRealTimers());

  test("push: a held turn writes the count, a later clean sync writes 0, an unchanged value is written again", async () => {
    mockPublish.mockImplementationOnce(publishWith({ result: { kind: "held", reason: "remote_ahead" } }));
    await expect(syncPush(USER_ID, WS_PATH, SERVICE, TEAM_WORKSPACE_ID)).resolves.toBeUndefined();

    vi.setSystemTime(new Date("2026-11-17T11:00:00.000Z"));
    mockCompute.mockResolvedValueOnce({ total: 0, onRecovered: 0 });
    mockPublish.mockImplementationOnce(publishWith({ result: { kind: "pushed" } }));
    await syncPush(USER_ID, WS_PATH, SERVICE, TEAM_WORKSPACE_ID);

    vi.setSystemTime(new Date("2026-11-17T12:00:00.000Z"));
    mockCompute.mockResolvedValueOnce({ total: 0, onRecovered: 0 });
    mockPublish.mockImplementationOnce(publishWith({ result: { kind: "noop" } }));
    await syncPush(USER_ID, WS_PATH, SERVICE, TEAM_WORKSPACE_ID);

    expect(heldWrites()).toEqual([
      [TEAM_WORKSPACE_ID, { heldFiles: 2, checkedAt: new Date("2026-11-17T10:00:00.000Z") }],
      [TEAM_WORKSPACE_ID, { heldFiles: 0, checkedAt: new Date("2026-11-17T11:00:00.000Z") }],
      [TEAM_WORKSPACE_ID, { heldFiles: 0, checkedAt: new Date("2026-11-17T12:00:00.000Z") }],
    ]);
    expect(mockWriteHeld.mock.calls.every(([svc]) => svc === SERVICE)).toBe(true);
    // Separate from the stamp: the push never stamps (W5), so the only workspace write is the held one.
    expect(mockWriteRepoCols).not.toHaveBeenCalled();
  });

  test("push: the count is computed on the publish's isolated dir, over T...frozen HEAD, with the recovered tips", async () => {
    const recovered = ["a".repeat(40)];
    mockRecovered.mockReturnValue(recovered);
    mockPublish.mockImplementationOnce(publishWith({ result: { kind: "held", reason: "remote_ahead" } }));
    await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    expect(mockRecovered).toHaveBeenCalledWith(WS_PATH);
    expect(mockCompute).toHaveBeenCalledTimes(1);
    expect(mockCompute.mock.calls[0][0]).toMatchObject({ isolated: ISO_DIR, base: T_SHA, head: HEAD_SHA, recovered });
  });

  test("push: a thrown turn after the remote read still writes (the finally path), and is still reported", async () => {
    mockPublish.mockImplementationOnce(publishWith({ throws: new KbSyncError("local_git_failed") }));
    await expect(syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID)).resolves.toBeUndefined();
    expect(heldWrites()).toEqual([[SOLO_WORKSPACE_ID, { heldFiles: 2, checkedAt: new Date("2026-11-17T10:00:00.000Z") }]]);
    expect(mockReport.mock.calls.some(([, o]) => o?.op === "syncPush")).toBe(true);
  });

  test("push: no count computed -> no write (no dir, a null count, unreadable recovered refs, a throwing count)", async () => {
    mockPublish.mockImplementationOnce(publishWith({ result: { kind: "held", reason: "remote_branch_absent" }, hook: false }));
    await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    mockCompute.mockResolvedValueOnce(null);
    mockPublish.mockImplementationOnce(publishWith({ result: { kind: "held", reason: "remote_ahead" } }));
    await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    mockRecovered.mockReturnValueOnce(null);
    mockPublish.mockImplementationOnce(publishWith({ result: { kind: "held", reason: "remote_ahead" } }));
    await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    mockCompute.mockRejectedValueOnce(new Error("spawn failed"));
    mockPublish.mockImplementationOnce(publishWith({ result: { kind: "pushed" } }));
    await expect(syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID)).resolves.toBeUndefined();
    expect(mockPublish).toHaveBeenCalledTimes(4);
    expect(mockCompute).toHaveBeenCalledTimes(2); // the null-recovered turn never computes
    expect(mockWriteHeld).not.toHaveBeenCalled();
  });

  test("push: a refused turn before the publish (merge in progress, detached HEAD) writes nothing", async () => {
    mergeHead.present = true;
    await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    mergeHead.present = false;
    mockHead.mockReturnValueOnce({ sha: HEAD_SHA, refName: null });
    await syncPush(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID);
    expect(mockPublish).not.toHaveBeenCalled();
    expect(mockWriteHeld).not.toHaveBeenCalled();
  });

  test("push: a failed held write sends exactly one mirror and the sync result is unchanged", async () => {
    const real = await vi.importActual<typeof import("@/server/workspace-repo-mirror")>("@/server/workspace-repo-mirror");
    mockWriteHeld.mockImplementation(real.writeKbSyncHeldCols);
    const failing = {
      from: () => ({
        update: () => ({ eq: () => ({ select: async () => ({ data: null, error: { code: "42703", message: "column missing" } }) }) }),
      }),
    } as never;
    mockPublish.mockImplementationOnce(publishWith({ result: { kind: "pushed" } }));
    await expect(syncPush(USER_ID, WS_PATH, failing, SOLO_WORKSPACE_ID)).resolves.toBeUndefined();
    const heldMirrors = mockReport.mock.calls.filter(([, o]) => String(o?.op).startsWith("write-kb-sync-held"));
    expect(heldMirrors).toHaveLength(1);
    expect(mockReport.mock.calls.filter(([, o]) => o?.op === "syncPush")).toHaveLength(0);
  });

  test("pull: after the merge and the adoption, the count is computed over T...the fresh HEAD and written", async () => {
    const merged = "d".repeat(40);
    mockMerge.mockResolvedValue({ reason: "merged", remote: { defaultBranch: "main", tip: T_SHA, sideTip: "e".repeat(40) } });
    mockAdopt.mockImplementation(async () => {
      mockHead.mockReturnValue({ sha: merged, refName: "refs/heads/main" }); // the adoption moved HEAD
      return null;
    });
    mockCompute.mockResolvedValue({ total: 3, onRecovered: 1 });
    await expect(syncPull(USER_ID, WS_PATH, SERVICE, TEAM_WORKSPACE_ID)).resolves.toEqual({
      heldFiles: 3,
      onRecovered: 1,
      pullReason: "merged",
      checkedAt: "2026-11-17T10:00:00.000Z",
    });
    expect(mockAdopt.mock.invocationCallOrder[0]).toBeLessThan(mockCompute.mock.invocationCallOrder[0]);
    expect(mockCompute.mock.calls[0][0]).toMatchObject({ isolated: expect.objectContaining({ gitDir: "/tmp/iso" }), base: T_SHA, head: merged, recovered: [] });
    expect(heldWrites()).toEqual([[TEAM_WORKSPACE_ID, { heldFiles: 3, checkedAt: new Date("2026-11-17T10:00:00.000Z") }]]);
    // The stamp is its own write (D29(1): never folded together).
    expect(mockWriteRepoCols).toHaveBeenCalledTimes(1);
    expect(mockWriteRepoCols.mock.calls[0][2]).not.toHaveProperty("kb_sync_held_files");
  });

  test("pull: up_to_date computes and writes too; 0 is written", async () => {
    mockCompute.mockResolvedValue({ total: 0, onRecovered: 0 });
    await expect(syncPull(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID)).resolves.toEqual({
      heldFiles: 0,
      onRecovered: 0,
      pullReason: "up_to_date",
      checkedAt: "2026-11-17T10:00:00.000Z",
    });
    expect(heldWrites()).toEqual([[SOLO_WORKSPACE_ID, { heldFiles: 0, checkedAt: new Date("2026-11-17T10:00:00.000Z") }]]);
  });

  test("pull: no remote read (remote null), a null count or an unresolved merge -> no count, no write", async () => {
    mockMerge.mockResolvedValueOnce({ reason: "fetch_failed", remote: null });
    await expect(syncPull(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID)).resolves.toEqual({
      heldFiles: null,
      onRecovered: null,
      pullReason: "fetch_failed",
      checkedAt: null,
    });
    mockCompute.mockResolvedValueOnce(null);
    await expect(syncPull(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID)).resolves.toMatchObject({ heldFiles: null, checkedAt: null });
    mergeHead.present = true;
    await expect(syncPull(USER_ID, WS_PATH, SERVICE, SOLO_WORKSPACE_ID)).resolves.toMatchObject({
      heldFiles: null,
      pullReason: "unresolved_merge",
    });
    expect(mockCompute).toHaveBeenCalledTimes(1);
    expect(mockWriteHeld).not.toHaveBeenCalled();
  });

  test("pull: a failed held write sends one mirror; the stamp stays written and the result is unchanged", async () => {
    const real = await vi.importActual<typeof import("@/server/workspace-repo-mirror")>("@/server/workspace-repo-mirror");
    mockWriteHeld.mockImplementation(real.writeKbSyncHeldCols);
    const failing = {
      from: () => ({ update: () => ({ eq: () => ({ select: async () => { throw new Error("socket hang up"); } }) }) }),
    } as never;
    await expect(syncPull(USER_ID, WS_PATH, failing, SOLO_WORKSPACE_ID)).resolves.toEqual({
      heldFiles: 2,
      onRecovered: 0,
      pullReason: "up_to_date",
      checkedAt: "2026-11-17T10:00:00.000Z",
    });
    expect(mockWriteRepoCols).toHaveBeenCalledTimes(1);
    expect(mockReport.mock.calls.filter(([, o]) => String(o?.op).startsWith("write-kb-sync-held"))).toHaveLength(1);
    expect(mockReport.mock.calls.filter(([, o]) => o?.op === "syncPull")).toHaveLength(0);
  });
});
