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
// Rows returned by the item-2 `users` scan (#4712), and its captured filter args.
let USERS_ROWS: { id: string; kb_sync_history: unknown }[] = [];
let USERS_QUERY_ERROR: { message: string } | null = null;
const eqSpy = vi.fn();
const isSpy = vi.fn();
const notSpy = vi.fn();

const serviceFrom = vi.fn((table: string) => {
  if (table === "workspaces") {
    const chain = {
      select: () => chain,
      eq: (col: string, val: unknown) => {
        eqSpy(col, val);
        return chain;
      },
      is: (col: string, val: unknown) => {
        isSpy(col, val);
        return chain;
      },
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
  serviceFrom.mockClear();
  eqSpy.mockClear();
  isSpy.mockClear();
  notSpy.mockClear();
  reportSilentFallbackSpy.mockReset();
  postSentryHeartbeatSpy.mockClear();
  vi.resetModules();
  process.env.INNGEST_SIGNING_KEY = "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY = "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  process.env.INNGEST_DEV = "1";
});
afterEach(() => {
  restoreEnv("INNGEST_SIGNING_KEY");
  restoreEnv("INNGEST_EVENT_KEY");
  restoreEnv("INNGEST_DEV");
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

  it("scans users for ready + installed (github_installation_id IS NOT NULL)", async () => {
    const handler = await importHandler();
    await handler({ step: makeStep(), logger });

    expect(serviceFrom).toHaveBeenCalledWith("users");
    expect(eqSpy).toHaveBeenCalledWith("repo_status", "ready");
    expect(notSpy).toHaveBeenCalledWith("github_installation_id", "is", null);
  });

  it("reports a user whose LATEST row is ok:false exactly once (op:stale-sync-failed, hashed userId)", async () => {
    USERS_ROWS = [{ id: "user-X", kb_sync_history: [okTrue, okFalse] }];
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

  it("reports the users-scan DB error once (op:scan-stale) and does not crash the function", async () => {
    USERS_QUERY_ERROR = { message: "users scan failed" };
    const handler = await importHandler();
    const result = await handler({ step: makeStep(), logger });

    // Top-level return is unchanged (item-1 ScanResult); item-2 reports in-place.
    expect(result).toEqual({ ok: true, findings: [], error: null });
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "workspace-sync-health", op: "scan-stale" }),
    );
  });
});
