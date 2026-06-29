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

// Arm-1 scan rows (ready + NULL install) and the captured filter args.
let WORKSPACE_ROWS: { id: string; repo_url: string | null }[] = [];
let WORKSPACE_QUERY_ERROR: { message: string } | null = null;
// PR-2b Shape B: arms 2 (#4712) and 3 (#4717) now read READINESS from the solo
// `workspaces` row (authoritative per mig 108) — NOT the stale `users.repo_status`.
// Step A scans `workspaces` for repo_status='ready' → {id, repo_url}; arm 3's
// repo_url now comes from HERE, not from `users`. These rows are distinct from
// WORKSPACE_ROWS (arm 1 additionally filters `.is(github_installation_id,null)`;
// the Step-A scan does not). The mock returns READY_WORKSPACE_ROWS only when the
// chain did NOT call `.is(...)`.
let READY_WORKSPACE_ROWS: { id: string; repo_url: string | null }[] = [];
let READY_WORKSPACE_QUERY_ERROR: { message: string } | null = null;
// Step B fetches kb_sync_history from `users` by `.in("id", ids)`. kb_sync_history
// is `users`-only (mig 017) and STAYS a users read. repo_url is NO LONGER selected
// from `users` (PR-2b cutover) — it comes from READY_WORKSPACE_ROWS. github_installation_id
// is the backfilled-solo default source for the per-row workspaces install resolver.
let USERS_ROWS: {
  id: string;
  kb_sync_history?: unknown;
  github_installation_id?: number | null;
  // #5675: arm-1's solo classification + entitlement resolution reads
  // github_username via the same users `.in("id", ids)` chain (select cols are
  // ignored by the mock, so an arm-1 owner row just needs this field present).
  github_username?: string | null;
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
// PER-TABLE eq spies (deepen P1 / AC7): a SINGLE shared eqSpy cannot prove the
// `repo_status='ready'` filter moved to the `workspaces` chain — it stays green
// even if the filter is wrongly applied to `users`. wsEqSpy pins the readiness
// filter to the workspaces chain; usersEqSpy MUST never see ("repo_status","ready").
const wsEqSpy = vi.fn();
const usersEqSpy = vi.fn();
const usersInSpy = vi.fn();
const isSpy = vi.fn();

function resolveWorkspaceInstall(id: string | undefined): number | null {
  if (id !== undefined && id in WORKSPACE_INSTALL_BY_ID) {
    return WORKSPACE_INSTALL_BY_ID[id];
  }
  return USERS_ROWS.find((r) => r.id === id)?.github_installation_id ?? null;
}

const serviceFrom = vi.fn((table: string) => {
  if (table === "workspaces") {
    // THREE consumers share this chain, distinguished by which terminal/filter
    // they call:
    //   (a) arm-1 scan: .eq("repo_status","ready").is("github_installation_id",null) → await
    //   (b) arms 2/3 Step-A scan: .eq("repo_status","ready") → await (NO .is())
    //   (c) per-row resolver: .eq("id", wsId).maybeSingle()
    // `sawIs` separates (a) from (b) at await time; `idEqVal` drives (c).
    let idEqVal: string | undefined;
    let sawIs = false;
    const chain = {
      select: () => chain,
      eq: (col: string, val: unknown) => {
        wsEqSpy(col, val);
        if (col === "id") idEqVal = val as string;
        return chain;
      },
      is: (col: string, val: unknown) => {
        isSpy(col, val);
        sawIs = true;
        return chain;
      },
      maybeSingle: () =>
        Promise.resolve({
          data: { github_installation_id: resolveWorkspaceInstall(idEqVal) },
          error: null,
        }),
      then: (resolve: (v: unknown) => unknown) => {
        // (a) arm-1 (sawIs) → WORKSPACE_ROWS; (b) Step-A scan → READY_WORKSPACE_ROWS.
        const err = sawIs ? WORKSPACE_QUERY_ERROR : READY_WORKSPACE_QUERY_ERROR;
        const rows = sawIs ? WORKSPACE_ROWS : READY_WORKSPACE_ROWS;
        return Promise.resolve({
          data: err ? null : rows,
          error: err,
        }).then(resolve);
      },
    } as Record<string, unknown>;
    return chain;
  }
  if (table === "users") {
    // PR-2b Shape B Step B: .select("id, kb_sync_history").in("id", ids) → await.
    // No `.eq("repo_status",…)` — readiness moved to the workspaces chain.
    const chain = {
      select: () => chain,
      eq: (col: string, val: unknown) => {
        usersEqSpy(col, val);
        return chain;
      },
      in: (col: string, vals: unknown) => {
        usersInSpy(col, vals);
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

// #5675: arm-1 reconcile resolves the owner's entitlement-scoped installs via
// the connect-path resolvers (mocked here so no real github-app/network IO runs)
// and backfills via writeRepoColsToWorkspace (spied to assert AC1/AC5 args).
const resolveReachableSpy = vi.fn(
  async (
    _service: unknown,
    _userId: string,
    _login: string | null,
  ): Promise<number[]> => [],
);
const resolveOwningDetailedSpy = vi.fn(
  async (
    _ids: number[],
    _owner: string,
    _repo: string,
  ): Promise<{ installId: number | null; allDegraded: boolean }> => ({
    installId: null,
    allDegraded: false,
  }),
);
vi.mock("@/server/reachable-installations", () => ({
  resolveReachableInstallationIds: (...a: unknown[]) =>
    resolveReachableSpy(...(a as [unknown, string, string | null])),
  resolveOwningInstallationForRepoDetailed: (...a: unknown[]) =>
    resolveOwningDetailedSpy(...(a as [number[], string, string])),
}));

const writeRepoColsSpy = vi.fn(async (): Promise<void> => {});
vi.mock("@/server/workspace-repo-mirror", () => ({
  writeRepoColsToWorkspace: (...a: unknown[]) =>
    writeRepoColsSpy(...(a as [])),
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
  READY_WORKSPACE_ROWS = [];
  READY_WORKSPACE_QUERY_ERROR = null;
  USERS_ROWS = [];
  USERS_QUERY_ERROR = null;
  WORKSPACE_INSTALL_BY_ID = {};
  serviceFrom.mockClear();
  wsEqSpy.mockClear();
  usersEqSpy.mockClear();
  usersInSpy.mockClear();
  isSpy.mockClear();
  reportSilentFallbackSpy.mockReset();
  postSentryHeartbeatSpy.mockClear();
  getDefaultBranchHeadCommitAtSpy.mockReset();
  getDefaultBranchHeadCommitAtSpy.mockResolvedValue(null);
  resolveReachableSpy.mockReset();
  resolveReachableSpy.mockResolvedValue([]);
  resolveOwningDetailedSpy.mockReset();
  resolveOwningDetailedSpy.mockResolvedValue({ installId: null, allDegraded: false });
  writeRepoColsSpy.mockReset();
  writeRepoColsSpy.mockResolvedValue(undefined);
  logger.info.mockClear();
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

    expect(wsEqSpy).toHaveBeenCalledWith("repo_status", "ready");
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

  it("reads readiness from workspaces (Shape B), then fetches users by .in(id) — NEVER eq(repo_status) on users", async () => {
    READY_WORKSPACE_ROWS = [{ id: "user-X", repo_url: null }];
    USERS_ROWS = [{ id: "user-X", kb_sync_history: [okTrue, okFalse] }];
    WORKSPACE_INSTALL_BY_ID = { "user-X": 42 };
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    // Readiness filter is PINNED to the workspaces chain (deepen P1 / AC7) — a
    // shared eqSpy could not prove this. The users chain must NEVER see it.
    expect(wsEqSpy).toHaveBeenCalledWith("repo_status", "ready");
    expect(usersEqSpy).not.toHaveBeenCalledWith("repo_status", "ready");
    // Step B fetches kb_sync_history from users by the ready workspace ids.
    expect(serviceFrom).toHaveBeenCalledWith("users");
    expect(usersInSpy).toHaveBeenCalledWith("id", ["user-X"]);
    // Per-row workspaces install resolve (eq("id", user.id) on the workspaces chain).
    expect(wsEqSpy).toHaveBeenCalledWith("id", "user-X");
  });

  it("reports a user whose LATEST row is ok:false exactly once (op:stale-sync-failed, hashed userId)", async () => {
    // Installed user (backfilled-solo: the workspace install mirrors the user's).
    READY_WORKSPACE_ROWS = [{ id: "user-X", repo_url: null }];
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
    // Prove the install came through the workspaces resolver (eq("id", user.id)),
    // not a residual users-column read — the mock's backfilled-solo fallback
    // sources both from the same value, so without this assertion the test would
    // pass even if the code reverted to reading users.github_installation_id.
    expect(wsEqSpy).toHaveBeenCalledWith("id", "user-X");
  });

  it("does NOT report when the latest row is ok:true (even if an older row failed)", async () => {
    READY_WORKSPACE_ROWS = [{ id: "user-recovered", repo_url: null }];
    USERS_ROWS = [{ id: "user-recovered", kb_sync_history: [okFalse, okTrue] }];
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("does NOT report when the latest row is a legacy {date,count} row", async () => {
    READY_WORKSPACE_ROWS = [{ id: "user-legacy", repo_url: null }];
    USERS_ROWS = [{ id: "user-legacy", kb_sync_history: [okFalse, legacy] }];
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("does NOT report when history is empty (went-quiet / NULL-install class, deferred #4717)", async () => {
    READY_WORKSPACE_ROWS = [{ id: "user-empty", repo_url: null }];
    USERS_ROWS = [{ id: "user-empty", kb_sync_history: [] }];
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("Direction A (latent-bug fix): reports a newly-connected user (NO users.repo_status write, workspaces.repo_status='ready')", async () => {
    // Pre-PR-2b the arm filtered on STALE users.repo_status, which was never
    // written for newly-connected users → false-EXCLUDED. Shape B scans the
    // authoritative workspaces.repo_status, so this row is now CAUGHT. The
    // backfilled-solo install resolves the per-row workspaces install.
    READY_WORKSPACE_ROWS = [{ id: "user-new", repo_url: null }];
    USERS_ROWS = [{ id: "user-new", kb_sync_history: [okTrue, okFalse] }];
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

  it("Direction B (symmetric drop): does NOT report a stale-users-ready user whose live workspaces.repo_status != 'ready'", async () => {
    // Pre-PR-2b the STALE users.repo_status='ready' kept this user in the scan
    // even though the LIVE workspaces.repo_status flipped to 'error'. workspaces
    // is the source of truth (mig 108): the Step-A scan returns no ready row for
    // this user, so it is never fetched in Step B → not reported. The drop is
    // intentional (deepen P1) — exactly the rows whose users column froze.
    READY_WORKSPACE_ROWS = []; // workspaces.repo_status='error' → excluded from Step A
    USERS_ROWS = [{ id: "user-stale", kb_sync_history: [okTrue, okFalse] }];
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    // Step A returned no ready workspaces → users is never fetched at all.
    expect(usersInSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("zero ready workspaces → step-scoped early return, heartbeat STILL posts (no bubble to handler)", async () => {
    // Step A returns no ready rows → the `ids.length===0` early return fires
    // INSIDE the step.run callback (returns {reported:0}), it does NOT bubble to
    // the handler — so the separate sentry-heartbeat step.run still runs (deepen P2).
    READY_WORKSPACE_ROWS = [];
    const handler = await importHandler();
    const result = await handler({ step: makeStep(), logger });

    expect(usersInSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    expect(postSentryHeartbeatSpy).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
    // Arm-1 top-level return unaffected.
    expect(result).toEqual({ ok: true, findings: [], error: null });
  });

  it("#5470: skips a row whose solo workspace has no install (per-row equivalent of the dropped predicate)", async () => {
    // Latest ok:false but the workspace install is NULL → genuinely not connected
    // → skipped (not reported), exactly as the old predicate filtered it out.
    READY_WORKSPACE_ROWS = [{ id: "user-noinstall", repo_url: null }];
    USERS_ROWS = [
      { id: "user-noinstall", kb_sync_history: [okTrue, okFalse], github_installation_id: null },
    ];
    WORKSPACE_INSTALL_BY_ID = { "user-noinstall": null };
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("reports the users-fetch DB error once (op:scan-stale) and does not crash the function", async () => {
    // Step A returns ready workspaces so Step B (the users .in() fetch) runs and
    // errors. Both arms reuse their existing slugs (no new op minted — plan).
    READY_WORKSPACE_ROWS = [{ id: "user-X", repo_url: "https://github.com/acme/widget" }];
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
  // PR-2b Shape B: repo_url now comes from the `workspaces` Step-A row, NOT users.
  // This helper pushes the workspaces side into READY_WORKSPACE_ROWS and returns
  // the users-side row ({id, kb_sync_history, github_installation_id}) for USERS_ROWS.
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
    // The ready workspace carries the repo_url (Step A); the user carries history.
    READY_WORKSPACE_ROWS.push({ id, repo_url });
    return { id, github_installation_id, kb_sync_history: [...extraHistory, okTrue] };
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

  it("Direction B (symmetric drop): drops a stale-users-ready, would-be-quiet user whose live workspaces.repo_status != 'ready' — at the workspaces gate, NOT a stale users path", async () => {
    // Mirror of arm 2's Direction B. The user looks went-quiet (latest row
    // ok:true, 10d stale, with a default-branch commit since) but workspaces is
    // the source of truth (mig 108): Step A returns NO ready row for this user,
    // so it is never fetched in Step B → never probed → never reported. This
    // proves the drop happens at the workspaces readiness gate, not via any
    // residual stale `users.repo_status` read.
    READY_WORKSPACE_ROWS = []; // workspaces.repo_status='error' → excluded from Step A
    USERS_ROWS = [
      {
        id: "user-quietstale",
        github_installation_id: 123,
        kb_sync_history: [
          { at: new Date(Date.now() - 10 * DAY).toISOString(), trigger: "webhook_push", ok: true, sync_completed_at: 1 },
        ],
      },
    ];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(Date.now()); // brand-new commit
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    // Step A returned no ready workspaces → users is never fetched, the GitHub
    // probe is never called, and nothing is reported.
    expect(usersInSpy).not.toHaveBeenCalled();
    expect(getDefaultBranchHeadCommitAtSpy).not.toHaveBeenCalled();
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
    READY_WORKSPACE_ROWS = [{ id: "user-B", repo_url: "https://github.com/acme/widget" }];
    USERS_ROWS = [
      {
        id: "user-B",
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
    const baseWs = { id: "user-slack", repo_url: "https://github.com/acme/widget" };
    const baseRow = {
      id: "user-slack",
      github_installation_id: 123,
      kb_sync_history: [
        { at: new Date(lastOk).toISOString(), trigger: "webhook_push", ok: true, sync_completed_at: lastOk },
      ],
    };

    // (i) commit 2min after lastOk — inside the 5min slack → must NOT fire.
    READY_WORKSPACE_ROWS = [baseWs];
    USERS_ROWS = [baseRow];
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(lastOk + 2 * 60 * 1000);
    let handler = await importHandler();
    await handler({ step: makeStep(), logger });
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();

    // (ii) commit 6min after lastOk — beyond the slack → fires.
    reportSilentFallbackSpy.mockReset();
    READY_WORKSPACE_ROWS = [baseWs];
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
    READY_WORKSPACE_ROWS = [{ id: "user-F", repo_url: "https://github.com/acme/widget" }];
    USERS_ROWS = [
      {
        id: "user-F",
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
    // repo_url now comes from the workspaces Step-A row: user-norepo's workspace
    // carries a null repo_url; user-noinstall has a repo but no install.
    READY_WORKSPACE_ROWS = [
      { id: "user-noinstall", repo_url: "https://github.com/acme/widget" },
      { id: "user-norepo", repo_url: null },
    ];
    USERS_ROWS = [
      { id: "user-noinstall", github_installation_id: null, kb_sync_history: [oldOk("a")] },
      { id: "user-norepo", github_installation_id: 123, kb_sync_history: [oldOk("b")] },
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
    READY_WORKSPACE_ROWS = [
      { id: "user-empty", repo_url: "https://github.com/acme/a" },
      { id: "user-legacy", repo_url: "https://github.com/acme/b" },
    ];
    USERS_ROWS = [
      { id: "user-empty", github_installation_id: 123, kb_sync_history: [] },
      { id: "user-legacy", github_installation_id: 123, kb_sync_history: [{ date: "2026-05-29", count: 3 }] },
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

  it("reports op:scan-went-quiet on a users-fetch DB error and still posts the heartbeat", async () => {
    // Step A returns a ready workspace so Step B (users .in() fetch) runs and errors.
    READY_WORKSPACE_ROWS = [{ id: "user-X", repo_url: "https://github.com/acme/widget" }];
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

// #5675: arm-1 is no longer a pure reporter — for a ready+NULL-install SOLO
// workspace it backfills github_installation_id, resolving the install via the
// entitlement-scoped connect-path resolvers (solo only; team installs are never
// auto-detected). Unresolvable / team findings keep the visible folded signal;
// a degraded probe no-ops as transient.
describe("cron-workspace-sync-health — arm-1 reconcile (#5675)", () => {
  it("AC1: solo + owner-entitled + owning install resolves → backfills via writeRepoColsToWorkspace, keeps no signal", async () => {
    WORKSPACE_ROWS = [{ id: "solo-1", repo_url: "https://github.com/alice/repo" }];
    USERS_ROWS = [{ id: "solo-1", github_username: "alice" }];
    resolveReachableSpy.mockResolvedValue([501]);
    resolveOwningDetailedSpy.mockResolvedValue({ installId: 501, allDegraded: false });
    const handler = await importHandler();
    const step = makeStep();
    await handler({ step, logger });

    // Entitlement-scoped: keyed on the owner's user_id (== solo workspace id) + github_username.
    expect(resolveReachableSpy).toHaveBeenCalledWith(expect.anything(), "solo-1", "alice");
    expect(resolveOwningDetailedSpy).toHaveBeenCalledWith([501], "alice", "repo");
    // Backfill via the canonical write boundary, keyed on the finding's own id.
    expect(writeRepoColsSpy).toHaveBeenCalledWith(
      expect.anything(),
      "solo-1",
      { github_installation_id: 501 },
    );
    // Reconciled → the workspace becomes reachable; no standing signal emitted.
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    // AC5: ran inside a per-workspace step.run boundary (replay determinism).
    expect(step.calls).toContainEqual({ name: "reconcile-solo-1" });
  });

  it("AC2 (negative, load-bearing): solo org repo whose owner is reachable but does NOT own the repo → skip(needs-reauth), NO write", async () => {
    // The cross-tenant over-grant guard: the owner has SOME reachable install
    // (e.g. their personal account) but it does not own this org repo, so we must
    // never bind an install the owner is not entitled to for THIS repo.
    WORKSPACE_ROWS = [{ id: "solo-2", repo_url: "https://github.com/bigorg/repo" }];
    USERS_ROWS = [{ id: "solo-2", github_username: "bob" }];
    resolveReachableSpy.mockResolvedValue([777]);
    resolveOwningDetailedSpy.mockResolvedValue({ installId: null, allDegraded: false });
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(writeRepoColsSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "workspace-sync-health",
        op: "ready-null-installation",
        extra: expect.objectContaining({ workspaceId: "solo-2", reason: "needs-reauth" }),
      }),
    );
  });

  it("AC3: team workspace (finding id is not a users.id) → skip(team-workspace-never-auto-detect), NO write, NO resolver call", async () => {
    WORKSPACE_ROWS = [{ id: "team-uuid", repo_url: "https://github.com/org/repo" }];
    USERS_ROWS = []; // no users row for this id → not solo
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(resolveReachableSpy).not.toHaveBeenCalled();
    expect(writeRepoColsSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        op: "ready-null-installation",
        extra: expect.objectContaining({
          workspaceId: "team-uuid",
          reason: "team-workspace-never-auto-detect",
        }),
      }),
    );
  });

  it("AC4: empty reachable → skip(needs-reauth), owning probe NOT called, signal kept", async () => {
    WORKSPACE_ROWS = [{ id: "solo-3", repo_url: "https://github.com/alice/repo" }];
    USERS_ROWS = [{ id: "solo-3", github_username: "alice" }];
    resolveReachableSpy.mockResolvedValue([]);
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(resolveOwningDetailedSpy).not.toHaveBeenCalled();
    expect(writeRepoColsSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        op: "ready-null-installation",
        extra: expect.objectContaining({ workspaceId: "solo-3", reason: "needs-reauth" }),
      }),
    );
  });

  it("AC4: all-degraded owning probe → transient, NO write, NO signal", async () => {
    WORKSPACE_ROWS = [{ id: "solo-4", repo_url: "https://github.com/alice/repo" }];
    USERS_ROWS = [{ id: "solo-4", github_username: "alice" }];
    resolveReachableSpy.mockResolvedValue([777]);
    resolveOwningDetailedSpy.mockResolvedValue({ installId: null, allDegraded: true });
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(writeRepoColsSpy).not.toHaveBeenCalled();
    // transient is fail-safe-silent: no write AND no signal (self-recovers next fire).
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("AC4: malformed repo_url (null) on a solo finding → skip(malformed-repo-url), NO write, NO resolver call, but KEEPS the visible signal (still a stuck workspace)", async () => {
    WORKSPACE_ROWS = [{ id: "solo-mal", repo_url: null }];
    USERS_ROWS = [{ id: "solo-mal", github_username: "alice" }];
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    // No repo to parse → no entitlement resolution, no write …
    expect(resolveReachableSpy).not.toHaveBeenCalled();
    expect(writeRepoColsSpy).not.toHaveBeenCalled();
    // … but a ready+NULL-install solo workspace is still stuck, so the standing
    // signal stays visible (this would have been silently dropped if malformed
    // suppressed the signal — the data-integrity review's L2 regression guard).
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        op: "ready-null-installation",
        extra: expect.objectContaining({
          workspaceId: "solo-mal",
          reason: "malformed-repo-url",
        }),
      }),
    );
  });

  it("AC6: arm-1 top-level return is unchanged ScanResult; logs deterministic {reconciled,skipped,transient}", async () => {
    WORKSPACE_ROWS = [
      { id: "solo-1", repo_url: "https://github.com/alice/repo" }, // reconciled
      { id: "team-uuid", repo_url: "https://github.com/org/repo" }, // skip (team)
    ];
    USERS_ROWS = [{ id: "solo-1", github_username: "alice" }];
    resolveReachableSpy.mockResolvedValue([501]);
    resolveOwningDetailedSpy.mockResolvedValue({ installId: 501, allDegraded: false });
    const handler = await importHandler();
    const result = await handler({ step: makeStep(), logger });

    // Handler return contract is unchanged (item-1 ScanResult).
    expect(result).toEqual({
      ok: true,
      findings: [
        { workspaceId: "solo-1", repoUrl: "https://github.com/alice/repo" },
        { workspaceId: "team-uuid", repoUrl: "https://github.com/org/repo" },
      ],
      error: null,
    });
    expect(logger.info).toHaveBeenCalledWith(
      expect.objectContaining({
        fn: "cron-workspace-sync-health",
        reconciled: 1,
        skipped: 1,
        transient: 0,
      }),
      expect.any(String),
    );
  });

  it("AC6: a workspace backfilled by arm-1 does not spuriously fire arm-2 (stale) or arm-3 (went-quiet) in the same invocation", async () => {
    // Exercise the actual intra-fire overlap (L3 hardening): solo-1 is BOTH an
    // arm-1 finding (ready+NULL-install) AND present in arms-2/3's ready scan
    // with an EMPTY kb_sync_history (a freshly-reconciled workspace has never
    // synced). arm-1 backfills it; arms 2/3 re-scan and must skip it because the
    // empty-history gate fires before any stale/went-quiet report — even though
    // the install now resolves non-null. Proves non-coupling at the row level,
    // not merely "arms 2/3 scanned an empty set".
    WORKSPACE_ROWS = [{ id: "solo-1", repo_url: "https://github.com/alice/repo" }];
    READY_WORKSPACE_ROWS = [{ id: "solo-1", repo_url: "https://github.com/alice/repo" }];
    USERS_ROWS = [{ id: "solo-1", github_username: "alice", kb_sync_history: [] }];
    resolveReachableSpy.mockResolvedValue([501]);
    resolveOwningDetailedSpy.mockResolvedValue({ installId: 501, allDegraded: false });
    getDefaultBranchHeadCommitAtSpy.mockResolvedValue(Date.now());
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(writeRepoColsSpy).toHaveBeenCalledTimes(1);
    // arms 2/3 skip on empty history before any probe → no spurious fire.
    expect(getDefaultBranchHeadCommitAtSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "stale-sync-failed" }),
    );
    expect(reportSilentFallbackSpy).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "went-quiet" }),
    );
  });
});
