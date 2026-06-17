import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// cron-workspace-sync-health — read-only daily scan that reports workspaces
// which are repo_status='ready' but github_installation_id IS NULL (so the
// webhook reconcile, which filters on github_installation_id, can never reach
// them). Detection only: no DB mutation.
//
// Drives the handler directly with an eager mock `step`.

const ORIGINAL_ENV = {
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_DEV: process.env.INNGEST_DEV,
};
function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) delete process.env[key];
  else process.env[key] = ORIGINAL_ENV[key];
}

// Rows returned by the workspaces query, and the captured filter args.
let WORKSPACE_ROWS: { id: string; repo_url: string | null }[] = [];
let WORKSPACE_QUERY_ERROR: { message: string } | null = null;
// Rows returned by the `users` scan — shared by arm 2 (#4712) and arm 3 (#4717).
// repo_url + github_installation_id are arm-3 columns (optional for arm-2 rows).
let USERS_ROWS: {
  id: string;
  kb_sync_history: unknown;
  repo_url?: string | null;
  github_installation_id?: number | null;
}[] = [];
let USERS_QUERY_ERROR: { message: string } | null = null;
// #5470: per-row install is resolved from the user's solo WORKSPACE via
// resolveInstallationIdForWorkspace (from("workspaces").eq("id", id).maybeSingle()).
// Backfilled-solo invariant (mig 080): the solo workspace install mirrors the
// user's install, so by default the workspace lookup returns the matching
// USERS_ROWS row's github_installation_id. WORKSPACE_INSTALL_BY_ID overrides that
// per-id — used by the newly-connected scenarios (NULL users install, populated
// workspaces install) that the old users-predicate would have false-excluded.
let WORKSPACE_INSTALL_BY_ID: Record<string, number | null> = {};
const eqSpy = vi.fn();
const isSpy = vi.fn();
const notSpy = vi.fn();

function resolveWorkspaceInstall(id: string | undefined): number | null {
  if (id !== undefined && id in WORKSPACE_INSTALL_BY_ID) {
    return WORKSPACE_INSTALL_BY_ID[id];
  }
  return USERS_ROWS.find((r) => r.id === id)?.github_installation_id ?? null;
}

const serviceFrom = vi.fn((table: string) => {
  if (table === "workspaces") {
    // Two consumers share this chain: the arm-1 scan
    // (.select().eq("repo_status","ready").is("github_installation_id",null) → await)
    // and the per-row resolver (.select().eq("id", wsId).maybeSingle()). Capture
    // the id-eq so maybeSingle returns that workspace's install.
    let idEqVal: string | undefined;
    const chain = {
      select: () => chain,
      eq: (col: string, val: unknown) => {
        eqSpy(col, val);
        if (col === "id") idEqVal = val as string;
        return chain;
      },
      is: (col: string, val: unknown) => {
        isSpy(col, val);
        return chain;
      },
      maybeSingle: () =>
        Promise.resolve({
          data: { github_installation_id: resolveWorkspaceInstall(idEqVal) },
          error: null,
        }),
      then: (resolve: (v: unknown) => unknown) =>
        Promise.resolve({
          data: WORKSPACE_QUERY_ERROR ? null : WORKSPACE_ROWS,
          error: WORKSPACE_QUERY_ERROR,
        }).then(resolve),
    } as Record<string, unknown>;
    return chain;
  }
  if (table === "users") {
    // item-2 scan: .select("id, kb_sync_history").eq("repo_status","ready").not("github_installation_id","is",null)
    const chain = {
      select: () => chain,
      eq: (col: string, val: unknown) => {
        eqSpy(col, val);
        return chain;
      },
      not: (col: string, op: string, val: unknown) => {
        notSpy(col, op, val);
        return chain;
      },
      then: (resolve: (v: unknown) => unknown) =>
        Promise.resolve({
          data: USERS_QUERY_ERROR ? null : USERS_ROWS,
          error: USERS_QUERY_ERROR,
        }).then(resolve),
    } as Record<string, unknown>;
    return chain;
  }
  throw new Error(`unexpected service table ${table}`);
});

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ from: serviceFrom }),
}));

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: vi.fn(),
  hashUserId: (s: string) => `hash-${s}`,
}));

const postSentryHeartbeatSpy = vi.fn(async () => {});
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/server/inngest/functions/_cron-shared")>();
  return { ...actual, postSentryHeartbeat: postSentryHeartbeatSpy };
});

// Arm 3 (#4717) probes GitHub via getDefaultBranchHeadCommitAt. Mock the whole
// module so no real network/token IO runs; each arm-3 test sets its own return.
// (Declared before vi.mock per the file's existing spy pattern — the factory is
// lazy, invoked at import time after this const is initialized.)
const getDefaultBranchHeadCommitAtSpy = vi.fn(
  async (_installationId: number, _owner: string, _repo: string): Promise<number | null> => null,
);
vi.mock("@/server/github-app", () => ({
  getDefaultBranchHeadCommitAt: (...args: unknown[]) =>
    getDefaultBranchHeadCommitAtSpy(...(args as [number, string, string])),
}));

const logger = { warn: vi.fn(), info: vi.fn(), error: vi.fn() };

function makeStep() {
  const calls: { name: string }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      const result = await cb();
      calls.push({ name });
      return result;
    },
  };
}

beforeEach(() => {
  WORKSPACE_ROWS = [];
  WORKSPACE_QUERY_ERROR = null;
  USERS_ROWS = [];
  USERS_QUERY_ERROR = null;
  WORKSPACE_INSTALL_BY_ID = {};
  serviceFrom.mockClear();
  eqSpy.mockClear();
  isSpy.mockClear();
  notSpy.mockClear();
  reportSilentFallbackSpy.mockReset();
  postSentryHeartbeatSpy.mockClear();
  getDefaultBranchHeadCommitAtSpy.mockReset();
  getDefaultBranchHeadCommitAtSpy.mockResolvedValue(null);
  vi.resetModules();
  process.env.INNGEST_SIGNING_KEY = "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY = "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  process.env.INNGEST_DEV = "1";
});
afterEach(() => {
  restoreEnv("INNGEST_SIGNING_KEY");
  restoreEnv("INNGEST_EVENT_KEY");
  restoreEnv("INNGEST_DEV");
  vi.useRealTimers(); // the gap==N boundary test fakes time; restore for siblings
});

async function importHandler() {
  const mod = await import("@/server/inngest/functions/cron-workspace-sync-health");
  return mod.cronWorkspaceSyncHealthHandler;
}

describe("cron-workspace-sync-health — filters", () => {
  it("scans for repo_status='ready' AND github_installation_id IS NULL", async () => {
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(eqSpy).toHaveBeenCalledWith("repo_status", "ready");
    expect(isSpy).toHaveBeenCalledWith("github_installation_id", null);
  });
});

describe("cron-workspace-sync-health — reporting", () => {
  it("reports each ready+NULL-install workspace to Sentry via reportSilentFallback", async () => {
    WORKSPACE_ROWS = [
      { id: "ws-A", repo_url: "https://github.com/jikig-ai/soleur" },
      { id: "ws-B", repo_url: "https://github.com/acme/widget" },
    ];
    const handler = await importHandler();
    const result = await handler({ step: makeStep(), logger });

    expect(result).toEqual({
      ok: true,
      findings: [
        { workspaceId: "ws-A", repoUrl: "https://github.com/jikig-ai/soleur" },
        { workspaceId: "ws-B", repoUrl: "https://github.com/acme/widget" },
      ],
      error: null,
    });
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(2);
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "workspace-sync-health",
        op: "ready-null-installation",
        extra: expect.objectContaining({ workspaceId: "ws-A" }),
      }),
    );
    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
  });

  it("reports nothing when no workspace is in the unreachable state", async () => {
    WORKSPACE_ROWS = [];
    const handler = await importHandler();
    const result = await handler({ step: makeStep(), logger });

    expect(result).toEqual({ ok: true, findings: [], error: null });
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
  });
});

describe("cron-workspace-sync-health — DB error", () => {
  it("reports the scan failure once and returns ok:false with no findings", async () => {
    WORKSPACE_QUERY_ERROR = { message: "connection refused" };
    const handler = await importHandler();
    const result = await handler({ step: makeStep(), logger });

    expect(result).toEqual({ ok: false, findings: [], error: "connection refused" });
    // One report for the scan failure; none for findings.
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "workspace-sync-health", op: "scan" }),
    );
    // Heartbeat reflects the probe failure.
    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: false }),
    );
  });

  it("does NOT mutate workspaces (read-only: no update/upsert/delete on the chain)", async () => {
    WORKSPACE_ROWS = [{ id: "ws-A", repo_url: "https://github.com/x/y" }];
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    // The mock chain only exposes select/eq/is/then; any update/upsert/delete
    // call would throw "is not a function". Reaching here proves read-only.
    expect(serviceFrom).toHaveBeenCalledWith("workspaces");
  });
});

// Item 2 (#4712): ready + INSTALLED users whose LATEST kb_sync_history row is
// ok:false. Scans `users` (where kb_sync_history lives), reports op:"stale-sync-failed".
describe("cron-workspace-sync-health — stale-sync-failed (item 2)", () => {
  const okFalse = { at: "2026-05-30T00:00:00Z", trigger: "webhook_push", ok: false, error_class: "sync_failed", sync_completed_at: 1 };
  const okTrue = { at: "2026-05-31T00:00:00Z", trigger: "webhook_push", ok: true, sync_completed_at: 2 };
  const legacy = { date: "2026-05-29", count: 3 };

  it("scans users for ready (no install predicate — #5470 dropped users.github_installation_id)", async () => {
    USERS_ROWS = [{ id: "user-X", kb_sync_history: [okTrue, okFalse] }];
    WORKSPACE_INSTALL_BY_ID = { "user-X": 42 };
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(serviceFrom).toHaveBeenCalledWith("users");
    expect(eqSpy).toHaveBeenCalledWith("repo_status", "ready");
    // The users scan no longer carries the install predicate (it would break at
    // PR-2b's column drop); install is resolved per-row from workspaces instead.
    expect(notSpy).not.toHaveBeenCalledWith("github_installation_id", "is", null);
    expect(eqSpy).toHaveBeenCalledWith("id", "user-X"); // per-row workspaces resolve
  });

  it("reports a user whose LATEST row is ok:false exactly once (op:stale-sync-failed, hashed userId)", async () => {
    // Installed user (backfilled-solo: the workspace install mirrors the user's).
    USERS_ROWS = [{ id: "user-X", kb_sync_history: [okTrue, okFalse], github_installation_id: 99 }];
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "workspace-sync-health",
        op: "stale-sync-failed",
        extra: expect.objectContaining({ userId: "user-X" }),
      }),
    );
  });

  it("does NOT report when the latest row is ok:true (even if an older row failed)", async () => {
    USERS_ROWS = [{ id: "user-recovered", kb_sync_history: [okFalse, okTrue] }];
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("does NOT report when the latest row is a legacy {date,count} row", async () => {
    USERS_ROWS = [{ id: "user-legacy", kb_sync_history: [okFalse, legacy] }];
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("does NOT report when history is empty (went-quiet / NULL-install class, deferred #4717)", async () => {
    USERS_ROWS = [{ id: "user-empty", kb_sync_history: [] }];
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("#5470 Test Scenario 6: reports a newly-connected user (NULL legacy users install, populated workspaces install) — the old predicate false-excluded this row", async () => {
    // users.github_installation_id is NULL (newly-connected, post-PR-2 write-
    // cutover) but the solo workspace install IS populated. The old
    // .not("github_installation_id","is",null) users-predicate would have
    // excluded this row → false negative; the per-row workspaces resolve catches it.
    USERS_ROWS = [
      { id: "user-new", kb_sync_history: [okTrue, okFalse], github_installation_id: null },
    ];
    WORKSPACE_INSTALL_BY_ID = { "user-new": 777 };
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "workspace-sync-health",
        op: "stale-sync-failed",
        extra: expect.objectContaining({ userId: "user-new" }),
      }),
    );
  });

  it("#5470: skips a row whose solo workspace has no install (per-row equivalent of the dropped predicate)", async () => {
    // Latest ok:false but the workspace install is NULL → genuinely not connected
    // → skipped (not reported), exactly as the old predicate filtered it out.
    USERS_ROWS = [
      { id: "user-noinstall", kb_sync_history: [okTrue, okFalse], github_installation_id: null },
    ];
    WORKSPACE_INSTALL_BY_ID = { "user-noinstall": null };
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("reports the users-scan DB error once (op:scan-stale) and does not crash the function", async () => {
    USERS_QUERY_ERROR = { message: "users scan failed" };
    const handler = await importHandler();
    const result = await handler({ step: makeStep(), logger });

    // Top-level return is unchanged (item-1 ScanResult); item-2 reports in-place.
    expect(result).toEqual({ ok: true, findings: [], error: null });
    // Arm 2 (op:scan-stale) AND arm 3 (op:scan-went-quiet) both scan `users`, so
    // a shared users-table outage blinds both and each reports once. Assert BOTH
    // ops explicitly rather than a bare count(2) — the count silently encodes
    // "two arms read users" and would mask an arm-3 regression that double-reports
    // scan-stale; per-op assertions point a future failure at the right arm.
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "workspace-sync-health", op: "scan-stale" }),
    );
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "workspace-sync-health", op: "scan-went-quiet" }),
    );
  });
});

// Item 3 (#4717): the WENT-QUIET class — ready + installed users whose LATEST
// kb_sync_history row is ok:true but whose repo's default branch has commits the
// workspace never synced. Scans `users` (mirrors arm 2 → mutually exclusive by
// latest-row ok-polarity); probes GitHub for the default-branch HEAD commit;
// reports op:"went-quiet" (hashed userId). Read-only; never throws past its step.
describe("cron-workspace-sync-health — went-quiet (item 3, #4717)", () => {
  const DAY = 24 * 60 * 60 * 1000;
  function userRow(
    overrides: Partial<{
      id: string;
      repo_url: string | null;
      github_installation_id: number | null;
      lastOkDaysAgo: number;
      extraHistory: unknown[];
    }> = {},
  ) {
    const {
      id = "user-Q",
      repo_url = "https://github.com/acme/widget",
      github_installation_id = 123,
      lastOkDaysAgo = 10,
      extraHistory = [],
    } = overrides;
    const okAt = Date.now() - lastOkDaysAgo * DAY;
    const okTrue = {
      at: new Date(okAt).toISOString(),
      trigger: "webhook_push",
      ok: true,
      sync_completed_at: okAt,
    };
    return { id, repo_url, github_installation_id, kb_sync_history: [...extraHistory, okTrue] };
  }

  it("fires once when the default-branch HEAD commit is newer than lastOk and gap > N days", async () => {
    USERS_ROWS = [userRow({ lastOkDaysAgo: 10 })];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(Date.now() - 1 * DAY);
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(getDefaultBranchHeadCommitAtSpy).toHaveBeenCalledWith(123, "acme", "widget");
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "workspace-sync-health",
        op: "went-quiet",
        extra: expect.objectContaining({ userId: "user-Q" }),
      }),
    );
  });

  it("does NOT fire when the repo is idle (HEAD commit older than lastOk)", async () => {
    USERS_ROWS = [userRow({ lastOkDaysAgo: 10 })];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(Date.now() - 30 * DAY);
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("does NOT fire (or probe) when the last sync is fresh (gap <= N days)", async () => {
    USERS_ROWS = [userRow({ lastOkDaysAgo: 1 })];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(Date.now());
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(getDefaultBranchHeadCommitAtSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("does NOT fire at the gap == N boundary (fire requires strictly > N days)", async () => {
    vi.useFakeTimers();
    const fixed = new Date("2026-06-01T00:00:00Z").getTime();
    vi.setSystemTime(fixed);
    USERS_ROWS = [
      {
        id: "user-B",
        repo_url: "https://github.com/acme/widget",
        github_installation_id: 123,
        kb_sync_history: [
          { at: new Date(fixed - 3 * DAY).toISOString(), trigger: "webhook_push", ok: true, sync_completed_at: fixed - 3 * DAY },
        ],
      },
    ];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(fixed); // brand-new push
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    // gap == maxGap ⇒ `<= maxGap` ⇒ fresh ⇒ skipped before the probe.
    expect(getDefaultBranchHeadCommitAtSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("respects the cross-clock FRESHNESS_SLACK_MS boundary (commit within slack → no fire; beyond → fire)", async () => {
    // Fake time so the HEAD-vs-lastOk gap is exact (slack = 5min). lastOk is 10d
    // stale (clause b holds), so only clause (a) — the cross-clock slack — decides.
    vi.useFakeTimers();
    const fixed = new Date("2026-06-01T00:00:00Z").getTime();
    vi.setSystemTime(fixed);
    const lastOk = fixed - 10 * DAY;
    const baseRow = {
      id: "user-slack",
      repo_url: "https://github.com/acme/widget",
      github_installation_id: 123,
      kb_sync_history: [
        { at: new Date(lastOk).toISOString(), trigger: "webhook_push", ok: true, sync_completed_at: lastOk },
      ],
    };

    // (i) commit 2min after lastOk — inside the 5min slack → must NOT fire.
    USERS_ROWS = [baseRow];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(lastOk + 2 * 60 * 1000);
    let handler = await importHandler();
    await handler({ step: makeStep(), logger });
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();

    // (ii) commit 6min after lastOk — beyond the slack → fires.
    reportSilentFallbackSpy.mockReset();
    USERS_ROWS = [baseRow];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(lastOk + 6 * 60 * 1000);
    handler = await importHandler();
    await handler({ step: makeStep(), logger });
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "went-quiet", extra: expect.objectContaining({ userId: "user-slack" }) }),
    );
  });

  it("does NOT fire for a latest ok:false row (arm 2 owns it; arm 3 skips)", async () => {
    USERS_ROWS = [
      {
        id: "user-F",
        repo_url: "https://github.com/acme/widget",
        github_installation_id: 123,
        kb_sync_history: [
          { at: new Date(Date.now() - 10 * DAY).toISOString(), trigger: "webhook_push", ok: false, error_class: "sync_failed", sync_completed_at: 1 },
        ],
      },
    ];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(Date.now());
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(getDefaultBranchHeadCommitAtSpy).not.toHaveBeenCalled();
    // Only arm 2 fires for this row.
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "stale-sync-failed" }),
    );
  });

  it("does NOT fire or probe a user missing github_installation_id or repo_url", async () => {
    const oldOk = (id: string) => ({ at: new Date(Date.now() - 10 * DAY).toISOString(), trigger: "webhook_push", ok: true, sync_completed_at: 1, _id: id });
    USERS_ROWS = [
      { id: "user-noinstall", repo_url: "https://github.com/acme/widget", github_installation_id: null, kb_sync_history: [oldOk("a")] },
      { id: "user-norepo", repo_url: null, github_installation_id: 123, kb_sync_history: [oldOk("b")] },
    ];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(Date.now());
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(getDefaultBranchHeadCommitAtSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("does NOT fire when the repo has no commits (helper returns null)", async () => {
    USERS_ROWS = [userRow({ lastOkDaysAgo: 10 })];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(null);
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(getDefaultBranchHeadCommitAtSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("#5470 Test Scenario 7: fires for a newly-connected user (NULL legacy users install, workspaces install resolves the probe)", async () => {
    // users.github_installation_id NULL, but the solo workspace install IS set →
    // the resolver supplies the install for the GitHub probe (keyed id=user.id).
    USERS_ROWS = [userRow({ id: "user-newq", github_installation_id: null, lastOkDaysAgo: 10 })];
    WORKSPACE_INSTALL_BY_ID = { "user-newq": 555 };
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(Date.now() - 1 * DAY);
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    // Probe runs with the WORKSPACE-resolved install (555), not the NULL users col.
    expect(getDefaultBranchHeadCommitAtSpy).toHaveBeenCalledWith(555, "acme", "widget");
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        op: "went-quiet",
        extra: expect.objectContaining({ userId: "user-newq" }),
      }),
    );
  });

  it("does NOT fire for empty or legacy {date,count} history", async () => {
    USERS_ROWS = [
      { id: "user-empty", repo_url: "https://github.com/acme/a", github_installation_id: 123, kb_sync_history: [] },
      { id: "user-legacy", repo_url: "https://github.com/acme/b", github_installation_id: 123, kb_sync_history: [{ date: "2026-05-29", count: 3 }] },
    ];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(Date.now());
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(getDefaultBranchHeadCommitAtSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("reports op:went-quiet-probe and continues when the GitHub probe throws", async () => {
    USERS_ROWS = [userRow({ id: "user-probe", lastOkDaysAgo: 10 })];
    getDefaultBranchHeadCommitAtSpy.mockRejectedValue(new Error("404 repo gone"));
    const handler = await importHandler();
    const result = await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        op: "went-quiet-probe",
        extra: expect.objectContaining({ userId: "user-probe" }),
      }),
    );
    // Arm-1 return + heartbeat unaffected by an arm-3 probe failure.
    expect(result).toEqual({ ok: true, findings: [], error: null });
    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(expect.objectContaining({ ok: true }));
  });

  it("reports op:scan-went-quiet on a users-scan DB error and still posts the heartbeat", async () => {
    USERS_QUERY_ERROR = { message: "users scan failed" };
    const handler = await importHandler();
    const result = await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "workspace-sync-health", op: "scan-went-quiet" }),
    );
    expect(result).toEqual({ ok: true, findings: [], error: null });
    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(expect.objectContaining({ ok: true }));
  });
});
