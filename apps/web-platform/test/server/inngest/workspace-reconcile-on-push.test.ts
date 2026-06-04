import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { normalizeRepoUrl } from "@/lib/repo-url";

// ADR-044 — Inngest reconcile on `platform/workspace.reconcile.requested`.
//
// Re-architected from founder/users-keyed to a WORKSPACE FAN-OUT: a push
// fans out to every workspace connected to (installation_id, repo), where
// repo = normalizeRepoUrl("https://github.com/" + event.data.fullName).
// Workspace path = <WORKSPACES_ROOT>/<workspace_id>; readiness = filesystem
// existence; kb_sync_history is attributed to each workspace's owner.
//
// Drives the handler directly with a mock `step` (eager step.run).

const ORIGINAL_ENV = {
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_DEV: process.env.INNGEST_DEV,
  WORKSPACES_ROOT: process.env.WORKSPACES_ROOT,
};
function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) delete process.env[key];
  else process.env[key] = ORIGINAL_ENV[key];
}

// --- workspace + membership fixtures ---------------------------------------
// workspaces matching the (installation_id, repo_url) query.
let WORKSPACE_ROWS: { id: string }[] = [];
let WORKSPACE_QUERY_ERROR: { message: string } | null = null;
// workspace_id -> owner user_id
const OWNERS = new Map<string, string>();
// captured (col, val) of the repo_url filter on the workspaces query
const repoUrlFilterSpy = vi.fn();

const serviceFrom = vi.fn((table: string) => {
  if (table === "workspaces") {
    const chain = {
      select: () => chain,
      eq: (col: string, val: unknown) => {
        if (col === "repo_url") repoUrlFilterSpy(val);
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
  if (table === "workspace_members") {
    let wsId = "";
    const chain = {
      select: () => chain,
      eq: (col: string, val: string) => {
        if (col === "workspace_id") wsId = val;
        return chain;
      },
      maybeSingle: async () => {
        const owner = OWNERS.get(wsId);
        return { data: owner ? { user_id: owner } : null, error: null };
      },
    } as Record<string, unknown>;
    return chain;
  }
  throw new Error(`unexpected service table ${table}`);
});

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ from: serviceFrom }),
}));

const syncWorkspaceSpy = vi.fn();
vi.mock("@/server/kb-route-helpers", () => ({ syncWorkspace: syncWorkspaceSpy }));

// kb_sync_history appends keyed by owner userId.
const APPENDS = new Map<string, Record<string, unknown>[]>();
const appendKbSyncRowSpy = vi.fn(async (userId: string, row: Record<string, unknown>) => {
  APPENDS.set(userId, [...(APPENDS.get(userId) ?? []), row]);
});
vi.mock("@/server/session-sync", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/session-sync")>();
  return { ...actual, appendKbSyncRow: appendKbSyncRowSpy };
});

const reportSilentFallbackSpy = vi.fn();
const warnSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: warnSilentFallbackSpy,
  hashUserId: (s: string) => `hash-${s}`,
}));

// The handler logs the benign no-workspace-match skip to pino (Better Stack
// drain) via the module-level `@/server/logger` default export — NOT the
// per-step logger arg. Override ONLY the default export's methods with spies;
// preserve every named export (e.g. `createChildLogger`, which transitive
// imports like `server/github-app.ts` and `server/git-auth.ts` call at module
// init) via importOriginal so the module graph still loads.
const loggerInfoSpy = vi.fn();
const loggerWarnSpy = vi.fn();
const loggerErrorSpy = vi.fn();
vi.mock("@/server/logger", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/logger")>();
  return {
    ...actual,
    default: { info: loggerInfoSpy, warn: loggerWarnSpy, error: loggerErrorSpy },
  };
});

// Filesystem existence: directories present in EXISTING_DIRS exist.
const EXISTING_DIRS = new Set<string>();
vi.mock("node:fs", () => ({
  promises: {
    stat: async (p: string) => {
      if (EXISTING_DIRS.has(p)) return { isDirectory: () => true };
      throw new Error("ENOENT");
    },
  },
}));

const logger = { warn: vi.fn(), info: vi.fn(), error: vi.fn() };

interface MockStep {
  calls: { name: string }[];
  run<T>(name: string, cb: () => Promise<T>): Promise<T>;
}
function makeStep(): MockStep {
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

const ROOT = "/tmp/wsroot";
function wsPath(id: string) {
  return `${ROOT}/${id}`;
}

function makeEvent(overrides: Partial<ReturnType<typeof baseData>> = {}) {
  return {
    name: "platform/workspace.reconcile.requested" as const,
    v: "2" as const,
    data: { ...baseData(), ...overrides },
  };
}
function baseData() {
  return {
    founderId: "founder-A",
    installationId: 42,
    deliveryId: "delivery-1",
    defaultBranch: "main",
    headSha: "abc1234567890abcdef1234567890abcdef12345",
    beforeSha: "def4567890abcdef1234567890abcdef12345678",
    fullName: "acme-co/widget",
    pushReceivedAt: 1_700_000_000_000,
  };
}

beforeEach(() => {
  WORKSPACE_ROWS = [];
  WORKSPACE_QUERY_ERROR = null;
  OWNERS.clear();
  APPENDS.clear();
  EXISTING_DIRS.clear();
  serviceFrom.mockClear();
  repoUrlFilterSpy.mockClear();
  syncWorkspaceSpy.mockReset();
  appendKbSyncRowSpy.mockClear();
  reportSilentFallbackSpy.mockReset();
  warnSilentFallbackSpy.mockReset();
  loggerInfoSpy.mockReset();
  loggerWarnSpy.mockReset();
  loggerErrorSpy.mockReset();
  vi.resetModules();
  process.env.INNGEST_SIGNING_KEY = "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY = "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  process.env.INNGEST_DEV = "1";
  process.env.WORKSPACES_ROOT = ROOT;
});
afterEach(() => {
  restoreEnv("INNGEST_SIGNING_KEY");
  restoreEnv("INNGEST_EVENT_KEY");
  restoreEnv("INNGEST_DEV");
  restoreEnv("WORKSPACES_ROOT");
});

async function importHandler() {
  const mod = await import("@/server/inngest/functions/workspace-reconcile-on-push");
  return mod.workspaceReconcileOnPushHandler;
}

describe("reconcile — happy path (single workspace)", () => {
  it("syncs the matching workspace and appends {ok:true} for its owner", async () => {
    WORKSPACE_ROWS = [{ id: "ws-A" }];
    OWNERS.set("ws-A", "owner-A");
    EXISTING_DIRS.add(wsPath("ws-A"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: true, synced: 1 });
    expect(syncWorkspaceSpy).toHaveBeenCalledTimes(1);
    expect(syncWorkspaceSpy).toHaveBeenCalledWith(
      42,
      wsPath("ws-A"),
      expect.anything(),
      expect.objectContaining({ userId: "owner-A", op: "push" }),
    );
    const rows = APPENDS.get("owner-A")!;
    expect(rows.at(-1)).toEqual(
      expect.objectContaining({ trigger: "webhook_push", ok: true }),
    );
    // #4728 — the ok:true reconcile row carries the workspace discriminator.
    expect(rows.at(-1)).toEqual(expect.objectContaining({ workspace_id: "ws-A" }));
  });
});

describe("reconcile — fan-out (AC6)", () => {
  it("syncs BOTH workspaces that share one installation_id + repo", async () => {
    WORKSPACE_ROWS = [{ id: "ws-A" }, { id: "ws-B" }];
    OWNERS.set("ws-A", "owner-A");
    OWNERS.set("ws-B", "owner-B");
    EXISTING_DIRS.add(wsPath("ws-A"));
    EXISTING_DIRS.add(wsPath("ws-B"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: true, synced: 2 });
    expect(syncWorkspaceSpy).toHaveBeenCalledTimes(2);
    expect(syncWorkspaceSpy.mock.calls.map((c) => c[1]).sort()).toEqual(
      [wsPath("ws-A"), wsPath("ws-B")].sort(),
    );
    expect(APPENDS.get("owner-A")).toHaveLength(1);
    expect(APPENDS.get("owner-B")).toHaveLength(1);
    // #4728 — each owner's row carries ITS OWN workspace discriminator. Guards
    // against a producer bug that writes a single captured id to every row (the
    // exact multi-workspace attribution #4728 exists to enable).
    expect(APPENDS.get("owner-A")!.at(-1)).toEqual(
      expect.objectContaining({ workspace_id: "ws-A" }),
    );
    expect(APPENDS.get("owner-B")!.at(-1)).toEqual(
      expect.objectContaining({ workspace_id: "ws-B" }),
    );
  });
});

describe("reconcile — slug→URL parity (AC7)", () => {
  it("composes https://github.com/<fullName> and normalizes BEFORE the repo_url filter", async () => {
    WORKSPACE_ROWS = [{ id: "ws-A" }];
    OWNERS.set("ws-A", "owner-A");
    EXISTING_DIRS.add(wsPath("ws-A"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    await handler({
      event: makeEvent({ fullName: "Acme-Co/Widget" }),
      step: makeStep(),
      logger,
    });

    // The match key is the composed + normalized URL (host lowercased,
    // path case preserved) — never the bare slug.
    expect(repoUrlFilterSpy).toHaveBeenCalledWith("https://github.com/Acme-Co/Widget");
    expect(repoUrlFilterSpy).not.toHaveBeenCalledWith("Acme-Co/Widget");
  });
});

describe("reconcile — schema gate (v=1 drains)", () => {
  it("deadletters a v=1 in-flight event without syncing", async () => {
    WORKSPACE_ROWS = [{ id: "ws-A" }];
    const handler = await importHandler();
    const result = (await handler({
      event: { ...makeEvent(), v: "1" },
      step: makeStep(),
      logger,
    })) as { ok: boolean; reason?: string };

    expect(result.ok).toBe(false);
    expect(result.reason).toMatch(/schema_v=1/);
    expect(syncWorkspaceSpy).not.toHaveBeenCalled();
    // Expected drain of an in-flight v=1 envelope -> observable at warning
    // level (previously returned silently with no Sentry mirror).
    expect(warnSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "deadletter-schema-version" }),
    );
  });
});

describe("reconcile — no workspace match (pino-only, no Sentry)", () => {
  it("logs the expected skip to pino (Better Stack) and does NOT mirror to Sentry", async () => {
    WORKSPACE_ROWS = [];
    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: false, reason: "no-workspace-match" });
    expect(syncWorkspaceSpy).not.toHaveBeenCalled();

    // Benign, by-design skip -> pino-only. An in-process debounce could not
    // bound it across container churn, so it must NOT create Sentry issues:
    // neither the warn-level warnSilentFallback nor the error-level
    // reportSilentFallback may fire.
    expect(warnSilentFallbackSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();

    expect(loggerInfoSpy).toHaveBeenCalledTimes(1);
    const [ctx, message] = loggerInfoSpy.mock.calls[0]!;
    expect(ctx).toMatchObject({
      feature: "workspace-reconcile-push",
      op: "skip-no-workspace-match",
      installationId: 42,
      deliveryId: "delivery-1",
      targetRepoUrl: normalizeRepoUrl("https://github.com/acme-co/widget"),
    });
    expect(message).toBe("Reconcile skipped — no workspace connected to this repo");
  });
});

describe("reconcile — ignored internal repo (stop the source)", () => {
  it("returns ignored-internal-repo with no sync, no log, no Sentry when ZERO workspaces match", async () => {
    // #4666 intent preserved: an ignored repo (the platform's own dev repo)
    // with no connected workspace is a fully-silent skip. The ignore check now
    // runs AFTER resolution, gated on zero matches — so the workspace query DID
    // run (one indexed select), but nothing else fires.
    WORKSPACE_ROWS = [];
    const handler = await importHandler();
    const result = await handler({
      event: makeEvent({ fullName: "jikig-ai/soleur" }),
      step: makeStep(),
      logger,
    });

    expect(result).toEqual({ ok: false, reason: "ignored-internal-repo" });
    // The resolution query runs (ignore is now post-resolution), but the skip
    // itself is silent: no sync, no benign-skip log, no Sentry.
    expect(syncWorkspaceSpy).not.toHaveBeenCalled();
    expect(loggerInfoSpy).not.toHaveBeenCalled();
    expect(warnSilentFallbackSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("RECONCILES an ignored repo that HAS a connected workspace, logs at info, does not page (regression: dogfood KB freeze + #4706 over-warn)", async () => {
    // The bug: the ignore check ran BEFORE resolution, so a real connected
    // workspace on an ignored repo (founder dogfooding their KB from the
    // platform's own repo) was silently starved for ~5 weeks. #4706 fixed that
    // (reconcile-anyway) but added a Sentry WARNING on the shadowed-workspace
    // sub-case — which is the EXPECTED steady state for the dogfood repo, so it
    // became a per-push alert flood with zero signal. Now the ignored repo is
    // reconciled because it has a workspace, and the shadowed-workspace state is
    // recorded at pino `info` (Better Stack audit trail) instead of paging Sentry.
    WORKSPACE_ROWS = [{ id: "ws-A" }];
    OWNERS.set("ws-A", "owner-A");
    EXISTING_DIRS.add(wsPath("ws-A"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    const result = await handler({
      event: makeEvent({ fullName: "jikig-ai/soleur" }),
      step: makeStep(),
      logger,
    });

    expect(result).toEqual({ ok: true, synced: 1 });
    expect(syncWorkspaceSpy).toHaveBeenCalledTimes(1);
    expect(syncWorkspaceSpy).toHaveBeenCalledWith(
      42,
      wsPath("ws-A"),
      expect.anything(),
      expect.objectContaining({ userId: "owner-A", op: "push" }),
    );
    expect(APPENDS.get("owner-A")!.at(-1)).toEqual(
      expect.objectContaining({ trigger: "webhook_push", ok: true }),
    );
    // Shadowed-workspace state is recorded at info, NOT mirrored to Sentry.
    expect(warnSilentFallbackSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    // Only the ignored-repo-has-workspaces info-log fires for this case
    // (rows.length === 1, ignored repo → no skip-no-workspace-match log). Assert
    // on the op list so a future regression that adds a second info-log on this
    // path names the unexpected op rather than a bare count mismatch.
    expect(loggerInfoSpy.mock.calls.map((c) => (c[0] as { op?: string }).op)).toEqual([
      "ignored-repo-has-workspaces",
    ]);
    expect(loggerInfoSpy).toHaveBeenCalledWith(
      expect.objectContaining({ op: "ignored-repo-has-workspaces", workspaceCount: 1 }),
      "Reconcile ignore-list shadows a connected workspace — reconciling anyway (info; review WORKSPACE_RECONCILE_IGNORE_REPOS if unexpected)",
    );
  });

  it("does NOT short-circuit a customer repo whose slug merely shares the ignored prefix", async () => {
    // `jikig-ai/soleur-fork` contains `jikig-ai/soleur` as a substring; an
    // unanchored includes() match would have silently dropped it. Exact
    // owner/repo matching must let it through to the normal (zero-match) path.
    WORKSPACE_ROWS = [];
    const handler = await importHandler();
    const result = await handler({
      event: makeEvent({ fullName: "jikig-ai/soleur-fork" }),
      step: makeStep(),
      logger,
    });

    expect(result).toEqual({ ok: false, reason: "no-workspace-match" });
    // Took the normal path: ran the workspace query and logged the benign skip.
    expect(repoUrlFilterSpy).toHaveBeenCalled();
    expect(loggerInfoSpy).toHaveBeenCalledTimes(1);
  });
});

describe("reconcile — workspace dir not provisioned", () => {
  it("skips the workspace, appends {workspace_not_ready}, returns no-workspace-synced", async () => {
    WORKSPACE_ROWS = [{ id: "ws-A" }];
    OWNERS.set("ws-A", "owner-A");
    // EXISTING_DIRS intentionally empty → dir missing.
    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(syncWorkspaceSpy).not.toHaveBeenCalled();
    expect(result).toEqual({ ok: false, reason: "no-workspace-synced" });
    expect(APPENDS.get("owner-A")!.at(-1)).toEqual(
      expect.objectContaining({
        ok: false,
        error_class: "workspace_not_ready",
        // #4728 — failure rows also carry the workspace discriminator.
        workspace_id: "ws-A",
      }),
    );
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "skip-not-ready" }),
    );
  });
});

describe("reconcile — sync failure", () => {
  it("propagates the REAL error_class from syncResult (sync_failed) + Sentry mirror op=sync", async () => {
    WORKSPACE_ROWS = [{ id: "ws-A" }];
    OWNERS.set("ws-A", "owner-A");
    EXISTING_DIRS.add(wsPath("ws-A"));
    syncWorkspaceSpy.mockResolvedValue({
      ok: false,
      error: new Error("auth failed"),
      errorClass: "sync_failed",
    });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: false, reason: "no-workspace-synced" });
    expect(APPENDS.get("owner-A")!.at(-1)).toEqual(
      expect.objectContaining({
        ok: false,
        error_class: "sync_failed",
        // #4728 — failure rows also carry the workspace discriminator.
        workspace_id: "ws-A",
      }),
    );
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "workspace-reconcile-push", op: "sync" }),
    );
  });

  it("propagates error_class:non_fast_forward when syncResult classifies a diverged clone (AC-B2)", async () => {
    WORKSPACE_ROWS = [{ id: "ws-A" }];
    OWNERS.set("ws-A", "owner-A");
    EXISTING_DIRS.add(wsPath("ws-A"));
    syncWorkspaceSpy.mockResolvedValue({
      ok: false,
      error: new Error("Not possible to fast-forward, aborting."),
      errorClass: "non_fast_forward",
    });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: false, reason: "no-workspace-synced" });
    expect(APPENDS.get("owner-A")!.at(-1)).toEqual(
      expect.objectContaining({
        ok: false,
        error_class: "non_fast_forward",
        workspace_id: "ws-A",
      }),
    );
  });

  it("records recovered:true ok-row when syncWorkspace self-healed a diverged clone (AC-B4)", async () => {
    WORKSPACE_ROWS = [{ id: "ws-A" }];
    OWNERS.set("ws-A", "owner-A");
    EXISTING_DIRS.add(wsPath("ws-A"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true, recovered: true });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: true, synced: 1 });
    expect(APPENDS.get("owner-A")!.at(-1)).toEqual(
      expect.objectContaining({
        ok: true,
        recovered: true,
        workspace_id: "ws-A",
      }),
    );
  });
});

describe("reconcile — cross-tenant isolation (fan-out per workspace)", () => {
  it("each workspace syncs ONLY its own derived path", async () => {
    WORKSPACE_ROWS = [{ id: "ws-A" }, { id: "ws-B" }];
    OWNERS.set("ws-A", "owner-A");
    OWNERS.set("ws-B", "owner-B");
    EXISTING_DIRS.add(wsPath("ws-A"));
    EXISTING_DIRS.add(wsPath("ws-B"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    await handler({ event: makeEvent(), step: makeStep(), logger });

    const aCall = syncWorkspaceSpy.mock.calls.find((c) => c[3].userId === "owner-A")!;
    const bCall = syncWorkspaceSpy.mock.calls.find((c) => c[3].userId === "owner-B")!;
    expect(aCall[1]).toBe(wsPath("ws-A"));
    expect(bCall[1]).toBe(wsPath("ws-B"));
    expect(aCall[1]).not.toBe(bCall[1]);
  });
});
