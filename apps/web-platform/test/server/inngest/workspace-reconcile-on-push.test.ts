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
// workspace_id -> owner user_id (single-owner convenience; back-compat).
const OWNERS = new Map<string, string>();
// #5733 — workspaces support N co-owners by design. workspace_id -> ordered
// owner rows (created_at ascending). When set, overrides OWNERS for that ws.
const OWNER_ROWS = new Map<string, { user_id: string; created_at: string }[]>();
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
    // Resolve the ordered owner rows for the captured workspace_id. OWNER_ROWS
    // (multi-owner) takes precedence; else a single OWNERS entry becomes a
    // one-row array; else empty (genuinely owner-less).
    const rowsFor = (): { user_id: string; created_at: string }[] => {
      if (OWNER_ROWS.has(wsId)) return OWNER_ROWS.get(wsId)!;
      const single = OWNERS.get(wsId);
      return single
        ? [{ user_id: single, created_at: "2026-01-01T00:00:00.000Z" }]
        : [];
    };
    const chain = {
      select: () => chain,
      eq: (col: string, val: string) => {
        if (col === "workspace_id") wsId = val;
        return chain;
      },
      // #5733 — owner attribution now selects ALL owner rows (ordered), no
      // `.maybeSingle()`. The awaited chain yields `{ data: rows[], error }`.
      order: () => chain,
      then: (resolve: (v: unknown) => unknown) =>
        Promise.resolve({ data: rowsFor(), error: null }).then(resolve),
      // Retained for any residual single-owner caller (none after #5733).
      // FIDELITY: PostgREST `.maybeSingle()` ERRORS when >1 row matches — the
      // exact prod condition #5733 reproduces (a workspace with 2 legitimate
      // owners). This is what made the pre-fix code false-report "owner-less".
      maybeSingle: async () => {
        const rows = rowsFor();
        if (rows.length > 1) {
          return {
            data: null,
            error: {
              code: "PGRST116",
              message: "JSON object requested, multiple (or no) rows returned",
            },
          };
        }
        return { data: rows[0] ? { user_id: rows[0].user_id } : null, error: null };
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

// --- validity-aware readiness gate + re-clone (this fix) -------------------
// Readiness now gates on git work-tree VALIDITY (isValidGitWorkTree), not mere
// dir existence. The default implementation reads EXISTING_DIRS so the legacy
// valid-path fixtures (which add the dir to EXISTING_DIRS) keep their meaning:
// "dir present" ⇒ "valid .git". The reclone cases below override per-call.
// #5733 — reconcile readiness now gates on isReadyGitWorkTree (lstat-valid AND
// not a stale gitdir-pointer FILE). The default spy keeps "dir present ⇒ ready"
// so the legacy valid-path fixtures (which add the dir to EXISTING_DIRS) retain
// their meaning; reclone cases override per-call.
const isReadyGitWorkTreeSpy = vi.fn();
// #5733 — the shared host-confirm gate (default "ready" so the existing lstat
// branch still owns clone-vs-sync) + the unrecovered-branch shape probe.
const evaluateAgentReadinessSpy = vi.fn(
  async (_p: string, _ctx: unknown): Promise<"ready" | "block"> => "ready",
);
const probeGitWorktreeShapeSpy = vi.fn(
  (_p: string): { kind: string; gitdirEscapesWorkspace?: boolean } => ({
    kind: "absent",
  }),
);
vi.mock("@/server/git-worktree-validity", () => ({
  isReadyGitWorkTree: (p: string) => isReadyGitWorkTreeSpy(p),
  evaluateAgentReadiness: (p: string, ctx: unknown) =>
    evaluateAgentReadinessSpy(p, ctx),
  probeGitWorktreeShape: (p: string) => probeGitWorktreeShapeSpy(p),
}));
// #5733 — spy the agent-readiness self-stop so the benign-skip emit is asserted
// directly WITHOUT routing through the shared reportSilentFallback spy (keeping
// every existing reportSilentFallback assertion in this file untouched).
const reportAgentReadinessSelfStopSpy = vi.fn();
vi.mock("@/server/repo-resolver-divergence", () => ({
  reportAgentReadinessSelfStop: (args: unknown) =>
    reportAgentReadinessSelfStopSpy(args),
}));
// The corrupt/absent-.git re-clone primitive. Returns "ok" | "failed".
const ensureWorkspaceRepoClonedSpy = vi.fn();
vi.mock("@/server/ensure-workspace-repo", () => ({
  ensureWorkspaceRepoCloned: (args: unknown) => ensureWorkspaceRepoClonedSpy(args),
}));
// Sentry breadcrumb capture (best-effort transaction-trace context).
const addBreadcrumbSpy = vi.fn();
vi.mock("@sentry/nextjs", () => ({ addBreadcrumb: (b: unknown) => addBreadcrumbSpy(b) }));

// kb_sync_history appends keyed by owner userId (owner-attributed path).
const APPENDS = new Map<string, Record<string, unknown>[]>();
const appendKbSyncRowSpy = vi.fn(async (userId: string, row: Record<string, unknown>) => {
  APPENDS.set(userId, [...(APPENDS.get(userId) ?? []), row]);
});
// #4906 — workspace-keyed appends for owner-less workspaces, keyed by workspace id.
// The handler passes the service-role client as the first arg (createServiceClient
// stays in the handler, off session-sync's tenant-only allowlist), so the spy
// signature is (client, workspaceId, row).
const WS_APPENDS = new Map<string, Record<string, unknown>[]>();
const appendKbSyncRowForWorkspaceSpy = vi.fn(
  async (
    _client: unknown,
    workspaceId: string,
    row: Record<string, unknown>,
  ) => {
    WS_APPENDS.set(workspaceId, [...(WS_APPENDS.get(workspaceId) ?? []), row]);
  },
);
vi.mock("@/server/session-sync", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/session-sync")>();
  return {
    ...actual,
    appendKbSyncRow: appendKbSyncRowSpy,
    appendKbSyncRowForWorkspace: appendKbSyncRowForWorkspaceSpy,
  };
});

const reportSilentFallbackSpy = vi.fn();
const warnSilentFallbackSpy = vi.fn();
// #4906 — owner-less drift warn routes through the per-workspace debounced
// warn (mirrorWarnWithDebounce(err, ctx, key, errorClass)) to bound the
// per-push Sentry volume under a systemic owner-canary regression.
const mirrorWarnWithDebounceSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: warnSilentFallbackSpy,
  mirrorWarnWithDebounce: mirrorWarnWithDebounceSpy,
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
    v: "3" as const,
    data: { ...baseData(), ...overrides },
  };
}
function baseData() {
  return {
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
  OWNER_ROWS.clear();
  APPENDS.clear();
  WS_APPENDS.clear();
  EXISTING_DIRS.clear();
  serviceFrom.mockClear();
  repoUrlFilterSpy.mockClear();
  syncWorkspaceSpy.mockReset();
  appendKbSyncRowSpy.mockClear();
  appendKbSyncRowForWorkspaceSpy.mockClear();
  reportSilentFallbackSpy.mockReset();
  warnSilentFallbackSpy.mockReset();
  mirrorWarnWithDebounceSpy.mockReset();
  loggerInfoSpy.mockReset();
  loggerWarnSpy.mockReset();
  loggerErrorSpy.mockReset();
  // Default: a workspace whose dir is provisioned (in EXISTING_DIRS) reads as a
  // VALID .git, so the legacy valid-path fixtures take the existing sync path.
  // Reclone cases override per-call with mockReturnValueOnce/mockReturnValue.
  isReadyGitWorkTreeSpy.mockReset();
  isReadyGitWorkTreeSpy.mockImplementation((p: string) => EXISTING_DIRS.has(p));
  // #5733 — default the shared host-confirm gate to "ready" (existing lstat branch
  // owns clone-vs-sync); the unrecovered-branch shape probe defaults to "absent".
  evaluateAgentReadinessSpy.mockReset();
  evaluateAgentReadinessSpy.mockResolvedValue("ready");
  probeGitWorktreeShapeSpy.mockReset();
  probeGitWorktreeShapeSpy.mockReturnValue({ kind: "absent" });
  reportAgentReadinessSelfStopSpy.mockReset();
  ensureWorkspaceRepoClonedSpy.mockReset();
  ensureWorkspaceRepoClonedSpy.mockResolvedValue("ok");
  addBreadcrumbSpy.mockReset();
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
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    EXISTING_DIRS.add(wsPath("77777777-7777-4777-8777-777777777777"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: true, synced: 1 });
    expect(syncWorkspaceSpy).toHaveBeenCalledTimes(1);
    expect(syncWorkspaceSpy).toHaveBeenCalledWith(
      42,
      wsPath("77777777-7777-4777-8777-777777777777"),
      expect.anything(),
      expect.objectContaining({ userId: "55555555-5555-4555-8555-555555555555", op: "push" }),
    );
    const rows = APPENDS.get("55555555-5555-4555-8555-555555555555")!;
    expect(rows.at(-1)).toEqual(
      expect.objectContaining({ trigger: "webhook_push", ok: true }),
    );
    // #4728 — the ok:true reconcile row carries the workspace discriminator.
    expect(rows.at(-1)).toEqual(expect.objectContaining({ workspace_id: "77777777-7777-4777-8777-777777777777" }));
  });
});

describe("reconcile — fan-out (AC6)", () => {
  it("syncs BOTH workspaces that share one installation_id + repo", async () => {
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }, { id: "88888888-8888-4888-8888-888888888888" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    OWNERS.set("88888888-8888-4888-8888-888888888888", "66666666-6666-4666-8666-666666666666");
    EXISTING_DIRS.add(wsPath("77777777-7777-4777-8777-777777777777"));
    EXISTING_DIRS.add(wsPath("88888888-8888-4888-8888-888888888888"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: true, synced: 2 });
    expect(syncWorkspaceSpy).toHaveBeenCalledTimes(2);
    expect(syncWorkspaceSpy.mock.calls.map((c) => c[1]).sort()).toEqual(
      [wsPath("77777777-7777-4777-8777-777777777777"), wsPath("88888888-8888-4888-8888-888888888888")].sort(),
    );
    expect(APPENDS.get("55555555-5555-4555-8555-555555555555")).toHaveLength(1);
    expect(APPENDS.get("66666666-6666-4666-8666-666666666666")).toHaveLength(1);
    // #4728 — each owner's row carries ITS OWN workspace discriminator. Guards
    // against a producer bug that writes a single captured id to every row (the
    // exact multi-workspace attribution #4728 exists to enable).
    expect(APPENDS.get("55555555-5555-4555-8555-555555555555")!.at(-1)).toEqual(
      expect.objectContaining({ workspace_id: "77777777-7777-4777-8777-777777777777" }),
    );
    expect(APPENDS.get("66666666-6666-4666-8666-666666666666")!.at(-1)).toEqual(
      expect.objectContaining({ workspace_id: "88888888-8888-4888-8888-888888888888" }),
    );
  });
});

describe("reconcile — slug→URL parity (AC7)", () => {
  it("composes https://github.com/<fullName> and normalizes BEFORE the repo_url filter", async () => {
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    EXISTING_DIRS.add(wsPath("77777777-7777-4777-8777-777777777777"));
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
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }];
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
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    EXISTING_DIRS.add(wsPath("77777777-7777-4777-8777-777777777777"));
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
      wsPath("77777777-7777-4777-8777-777777777777"),
      expect.anything(),
      expect.objectContaining({ userId: "55555555-5555-4555-8555-555555555555", op: "push" }),
    );
    expect(APPENDS.get("55555555-5555-4555-8555-555555555555")!.at(-1)).toEqual(
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

describe("reconcile — workspace dir not provisioned (now reclone-not-recovered)", () => {
  it("routes an invalid/absent .git to ensureWorkspaceRepoCloned (no skip-not-ready); a non-heal writes {workspace_not_ready}", async () => {
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    // EXISTING_DIRS intentionally empty → isValidGitWorkTree false on both probes.
    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    // Re-clone primitive is invoked instead of the removed skip-not-ready gate.
    expect(ensureWorkspaceRepoClonedSpy).toHaveBeenCalledTimes(1);
    expect(syncWorkspaceSpy).not.toHaveBeenCalled();
    expect(result).toEqual({ ok: false, reason: "no-workspace-synced" });
    expect(APPENDS.get("55555555-5555-4555-8555-555555555555")!.at(-1)).toEqual(
      expect.objectContaining({
        ok: false,
        error_class: "workspace_not_ready",
        // #4728 — failure rows also carry the workspace discriminator.
        workspace_id: "77777777-7777-4777-8777-777777777777",
      }),
    );
    // The removed gate's paging signal must NOT fire on the reclone path
    // (data-integrity P2): no skip-not-ready reportSilentFallback here.
    expect(reportSilentFallbackSpy).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "skip-not-ready" }),
    );
  });

  // #5733 — un-blind the RECONCILE benign-skip (the 26×-dark surface): a clone
  // that returns "ok" WITHOUT healing leaves the workspace not-ready, and the
  // handler now emits the agent-readiness self-stop so the strand is queryable on
  // the path that actually fired (host pre-heal emit OR the benign-skip emit).
  it("#5733: a benign-skip that did NOT heal emits the agent-readiness self-stop", async () => {
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    // EXISTING_DIRS empty → isReadyGitWorkTree false → enters the heal branch.
    // ensureWorkspaceRepoCloned returns "ok" (default) but does NOT heal (dir stays
    // absent) → recovered=false → unrecovered branch fires the self-stop.
    probeGitWorktreeShapeSpy.mockReturnValue({ kind: "absent" });
    const handler = await importHandler();
    await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(reportAgentReadinessSelfStopSpy).toHaveBeenCalledTimes(1);
    expect(reportAgentReadinessSelfStopSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        activeWorkspaceId: "77777777-7777-4777-8777-777777777777",
        gitKind: "absent",
        source: "host-pre-heal",
      }),
    );
  });

  // #5733 AC8 — exactly ONE host `rev-parse` confirm per reconcile event (single
  // workspace per invocation): the verdict is computed once and reused for both the
  // gate decision and the `recovered` re-probe.
  it("#5733 AC8: evaluateAgentReadiness is called exactly once per event (verdict reused for the recovered re-probe)", async () => {
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    // Unrecovered path (EXISTING_DIRS empty): the top-of-handler verdict is reused
    // for the `recovered` decision — no second host `rev-parse` spawn.
    const handler = await importHandler();
    await handler({ event: makeEvent(), step: makeStep(), logger });
    expect(evaluateAgentReadinessSpy).toHaveBeenCalledTimes(1);
  });
});

describe("reconcile — sync failure", () => {
  it("propagates the REAL error_class from syncResult (sync_failed) + Sentry mirror op=sync", async () => {
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    EXISTING_DIRS.add(wsPath("77777777-7777-4777-8777-777777777777"));
    syncWorkspaceSpy.mockResolvedValue({
      ok: false,
      error: new Error("auth failed"),
      errorClass: "sync_failed",
    });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: false, reason: "no-workspace-synced" });
    expect(APPENDS.get("55555555-5555-4555-8555-555555555555")!.at(-1)).toEqual(
      expect.objectContaining({
        ok: false,
        error_class: "sync_failed",
        // #4728 — failure rows also carry the workspace discriminator.
        workspace_id: "77777777-7777-4777-8777-777777777777",
      }),
    );
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "workspace-reconcile-push", op: "sync" }),
    );
  });

  it("propagates error_class:non_fast_forward when syncResult classifies a diverged clone (AC-B2)", async () => {
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    EXISTING_DIRS.add(wsPath("77777777-7777-4777-8777-777777777777"));
    syncWorkspaceSpy.mockResolvedValue({
      ok: false,
      error: new Error("Not possible to fast-forward, aborting."),
      errorClass: "non_fast_forward",
    });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: false, reason: "no-workspace-synced" });
    expect(APPENDS.get("55555555-5555-4555-8555-555555555555")!.at(-1)).toEqual(
      expect.objectContaining({
        ok: false,
        error_class: "non_fast_forward",
        workspace_id: "77777777-7777-4777-8777-777777777777",
      }),
    );
  });

  it("records recovered:true ok-row when syncWorkspace self-healed a diverged clone (AC-B4)", async () => {
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    EXISTING_DIRS.add(wsPath("77777777-7777-4777-8777-777777777777"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true, recovered: true });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: true, synced: 1 });
    expect(APPENDS.get("55555555-5555-4555-8555-555555555555")!.at(-1)).toEqual(
      expect.objectContaining({
        ok: true,
        recovered: true,
        workspace_id: "77777777-7777-4777-8777-777777777777",
      }),
    );
  });
});

describe("reconcile — owner-less workspace (#4906, workspace-keyed audit)", () => {
  // An owner-less workspace = a ws.id NOT in the OWNERS map, so the
  // workspace_members owner lookup resolves null. #4901 makes it self-heal and
  // the KB content syncs, but the owner gate previously skipped the audit row;
  // now it writes via the workspace-keyed path and emits an owner-drift warn.

  it("AC-T1 (AC5): owner-less + {ok:true, recovered:true} → workspace-keyed row, owner path NOT called", async () => {
    WORKSPACE_ROWS = [{ id: "99999999-9999-4999-8999-999999999999" }]; // no OWNERS entry → ownerId null
    EXISTING_DIRS.add(wsPath("99999999-9999-4999-8999-999999999999"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true, recovered: true });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: true, synced: 1 });
    // Owner-attributed path must NOT fire for an owner-less workspace.
    expect(appendKbSyncRowSpy).not.toHaveBeenCalled();
    // The recovery lands on the workspace-keyed path, keyed by ws.id.
    expect(appendKbSyncRowForWorkspaceSpy).toHaveBeenCalledTimes(1);
    expect(WS_APPENDS.get("99999999-9999-4999-8999-999999999999")!.at(-1)).toEqual(
      expect.objectContaining({
        trigger: "webhook_push",
        ok: true,
        recovered: true,
        workspace_id: "99999999-9999-4999-8999-999999999999",
      }),
    );
  });

  it("AC-T2 (AC3): owner-less + {ok:false, sync_failed} → workspace-keyed failure row AND reportSilentFallback op=sync still fires", async () => {
    WORKSPACE_ROWS = [{ id: "99999999-9999-4999-8999-999999999999" }];
    EXISTING_DIRS.add(wsPath("99999999-9999-4999-8999-999999999999"));
    syncWorkspaceSpy.mockResolvedValue({
      ok: false,
      error: new Error("auth failed"),
      errorClass: "sync_failed",
    });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: false, reason: "no-workspace-synced" });
    expect(appendKbSyncRowSpy).not.toHaveBeenCalled();
    expect(WS_APPENDS.get("99999999-9999-4999-8999-999999999999")!.at(-1)).toEqual(
      expect.objectContaining({
        ok: false,
        error_class: "sync_failed",
        workspace_id: "99999999-9999-4999-8999-999999999999",
      }),
    );
    // The genuine failure is still paged — unchanged from the owner path.
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "workspace-reconcile-push", op: "sync" }),
    );
  });

  it("AC-T3 (AC4): owner-less → exactly one debounced warn op=ownerless-reconcile keyed on workspace_id; no error mirror for the benign recovery", async () => {
    WORKSPACE_ROWS = [{ id: "99999999-9999-4999-8999-999999999999" }];
    EXISTING_DIRS.add(wsPath("99999999-9999-4999-8999-999999999999"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true, recovered: true });

    const handler = await importHandler();
    await handler({ event: makeEvent(), step: makeStep(), logger });

    // The drift warn routes through mirrorWarnWithDebounce(err, ctx, key,
    // errorClass) — keyed on ws.id so a systemic cohort drift does not flood
    // Sentry once-per-push.
    expect(mirrorWarnWithDebounceSpy).toHaveBeenCalledTimes(1);
    const [, ctx, key, errorClass] = mirrorWarnWithDebounceSpy.mock.calls[0]!;
    expect(ctx).toEqual(
      expect.objectContaining({
        op: "ownerless-reconcile",
        extra: expect.objectContaining({ workspaceId: "99999999-9999-4999-8999-999999999999" }),
      }),
    );
    expect(key).toBe("99999999-9999-4999-8999-999999999999");
    expect(errorClass).toBe("ownerless-reconcile");
    // The benign recovery must NOT page an error-level Sentry issue.
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("AC-T4 (AC4): owner-less + invalid/absent .git not recovered → workspace-keyed workspace_not_ready row (no skip-not-ready)", async () => {
    WORKSPACE_ROWS = [{ id: "99999999-9999-4999-8999-999999999999" }];
    // EXISTING_DIRS intentionally empty → isValidGitWorkTree false on both probes.
    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(ensureWorkspaceRepoClonedSpy).toHaveBeenCalledTimes(1);
    expect(syncWorkspaceSpy).not.toHaveBeenCalled();
    expect(result).toEqual({ ok: false, reason: "no-workspace-synced" });
    expect(appendKbSyncRowSpy).not.toHaveBeenCalled();
    expect(WS_APPENDS.get("99999999-9999-4999-8999-999999999999")!.at(-1)).toEqual(
      expect.objectContaining({
        ok: false,
        error_class: "workspace_not_ready",
        workspace_id: "99999999-9999-4999-8999-999999999999",
      }),
    );
    // The removed gate's paging signal must NOT fire (data-integrity P2).
    expect(reportSilentFallbackSpy).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "skip-not-ready" }),
    );
    // …and the owner-drift warn still fires exactly once for this workspace.
    expect(mirrorWarnWithDebounceSpy).toHaveBeenCalledTimes(1);
    expect(mirrorWarnWithDebounceSpy.mock.calls[0]![2]).toBe("99999999-9999-4999-8999-999999999999");
  });

  it("AC-T5 (AC8): owner-PRESENT workspaces are unaffected — owner path fires, workspace-keyed path does NOT", async () => {
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    EXISTING_DIRS.add(wsPath("77777777-7777-4777-8777-777777777777"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(appendKbSyncRowSpy).toHaveBeenCalledTimes(1);
    expect(appendKbSyncRowForWorkspaceSpy).not.toHaveBeenCalled();
    // No owner-drift warn on the healthy owner-attributed path.
    expect(mirrorWarnWithDebounceSpy).not.toHaveBeenCalled();
  });
});

describe("reconcile — multi-owner attribution (#5733: N co-owners by design)", () => {
  // The soleur-prod shape: a SOLO workspace whose id == its self-owner's
  // user_id, plus a legitimate second co-owner. The former `.maybeSingle()`
  // owner lookup ERRORED on the two rows → ownerId=null → a FALSE "owner-less
  // workspace reconciled" warn every push. Now: select ALL owner rows, pick the
  // self-row deterministically, and NEVER false-warn owner-less when owners exist.
  const WS = "754ee124-706a-4f21-a4f4-e828257b0380"; // self-owner: user_id == ws.id
  const CO_OWNER = "52af49c2-d68e-477b-ba76-129e41807c7c";

  it("two legitimate owners → NO false owner-less warn; attribution to the self-row owner", async () => {
    WORKSPACE_ROWS = [{ id: WS }];
    // Co-owner created BEFORE the self-row — proves self-row preference is by
    // identity, not by created_at ordering.
    OWNER_ROWS.set(WS, [
      { user_id: CO_OWNER, created_at: "2026-06-02T07:47:27.126Z" },
      { user_id: WS, created_at: "2026-05-21T18:00:35.683Z" },
    ]);
    EXISTING_DIRS.add(wsPath(WS));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: true, synced: 1 });
    // The FALSE owner-less warn must NOT fire (the #5733 "28×" regression).
    expect(mirrorWarnWithDebounceSpy).not.toHaveBeenCalled();
    // Owner-keyed audit attributed to the SELF-row owner (ws.id), not the co-owner.
    expect(appendKbSyncRowSpy).toHaveBeenCalledTimes(1);
    expect(appendKbSyncRowSpy.mock.calls[0]![0]).toBe(WS);
    expect(appendKbSyncRowForWorkspaceSpy).not.toHaveBeenCalled();
    // A distinct, non-paging info breadcrumb records the by-design multi-owner state.
    expect(addBreadcrumbSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        message: "multiple-owners-reconcile",
        level: "info",
        data: expect.objectContaining({ workspaceId: WS, ownerCount: 2 }),
      }),
    );
  });

  it("no self-row among multiple owners → earliest-created owner wins (deterministic)", async () => {
    const TEAM = "33333333-3333-4333-8333-333333333333";
    const OWNER_EARLY = "11111111-1111-4111-8111-111111111111";
    const OWNER_LATE = "22222222-2222-4222-8222-222222222222";
    WORKSPACE_ROWS = [{ id: TEAM }];
    OWNER_ROWS.set(TEAM, [
      { user_id: OWNER_EARLY, created_at: "2026-01-01T00:00:00.000Z" },
      { user_id: OWNER_LATE, created_at: "2026-02-01T00:00:00.000Z" },
    ]);
    EXISTING_DIRS.add(wsPath(TEAM));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(mirrorWarnWithDebounceSpy).not.toHaveBeenCalled();
    expect(appendKbSyncRowSpy.mock.calls[0]![0]).toBe(OWNER_EARLY);
  });

  it("genuinely ZERO owner rows still emits exactly one owner-less drift warn", async () => {
    const WS_NONE = "99999999-9999-4999-8999-999999999999";
    WORKSPACE_ROWS = [{ id: WS_NONE }];
    // No OWNERS / OWNER_ROWS entry → owners == [] → genuine drift.
    EXISTING_DIRS.add(wsPath(WS_NONE));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(mirrorWarnWithDebounceSpy).toHaveBeenCalledTimes(1);
    expect(mirrorWarnWithDebounceSpy.mock.calls[0]![1]).toEqual(
      expect.objectContaining({ op: "ownerless-reconcile" }),
    );
    // The multiple-owners breadcrumb must NOT fire for a zero-owner workspace.
    expect(addBreadcrumbSpy).not.toHaveBeenCalledWith(
      expect.objectContaining({ message: "multiple-owners-reconcile" }),
    );
  });
});

describe("reconcile — validity-aware readiness gate + re-clone (the fix)", () => {
  const WS = "77777777-7777-4777-8777-777777777777";
  const OWNER = "55555555-5555-4555-8555-555555555555";
  const TARGET_REPO = normalizeRepoUrl("https://github.com/acme-co/widget");

  function reclonedBreadcrumb(recovered: boolean) {
    return expect.objectContaining({
      category: "workspace-reconcile-push",
      data: expect.objectContaining({ op: "corrupt-worktree-reclone", recovered, workspaceId: WS }),
    });
  }

  it("case 1 — VALID .git takes the existing sync path; NO reclone, NO reclone breadcrumb", async () => {
    WORKSPACE_ROWS = [{ id: WS }];
    OWNERS.set(WS, OWNER);
    EXISTING_DIRS.add(wsPath(WS)); // default mock ⇒ isValidGitWorkTree true
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: true, synced: 1 });
    expect(ensureWorkspaceRepoClonedSpy).not.toHaveBeenCalled();
    expect(syncWorkspaceSpy).toHaveBeenCalledTimes(1);
    expect(APPENDS.get(OWNER)!.at(-1)).toEqual(expect.objectContaining({ ok: true }));
    // The reclone breadcrumb fires ONLY on the invalid/absent branch.
    expect(addBreadcrumbSpy).not.toHaveBeenCalled();
  });

  it("case 2 — invalid/absent .git is re-cloned (also covers the concurrent-racer re-probe); audit ok+recovered, breadcrumb recovered:true", async () => {
    // false on the OUTER gate, true on the post-ensure re-probe. The false→true
    // pair ALSO exercises the concurrent-racer path: ensureWorkspaceRepoCloned
    // early-returns "ok" when a racer grafted a valid .git between the gate and
    // the function entry; the re-probe sees "ok" && valid ⇒ recovered:true,
    // the correct result regardless of which caller grafted (data-integrity).
    WORKSPACE_ROWS = [{ id: WS }];
    OWNERS.set(WS, OWNER);
    isReadyGitWorkTreeSpy.mockReturnValueOnce(false).mockReturnValueOnce(true);
    ensureWorkspaceRepoClonedSpy.mockResolvedValue("ok");

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: true, synced: 1 });
    expect(ensureWorkspaceRepoClonedSpy).toHaveBeenCalledTimes(1);
    expect(ensureWorkspaceRepoClonedSpy).toHaveBeenCalledWith({
      userId: OWNER,
      workspacePath: wsPath(WS),
      installationId: 42,
      repoUrl: TARGET_REPO,
    });
    expect(syncWorkspaceSpy).not.toHaveBeenCalled();
    expect(APPENDS.get(OWNER)!.at(-1)).toEqual(
      expect.objectContaining({ trigger: "webhook_push", ok: true, recovered: true, workspace_id: WS }),
    );
    expect(addBreadcrumbSpy).toHaveBeenCalledWith(reclonedBreadcrumb(true));
  });

  it("case 3 — populated-but-broken honest-block ('failed') is NOT claimed as recovered; audit workspace_not_ready, breadcrumb recovered:false", async () => {
    WORKSPACE_ROWS = [{ id: WS }];
    OWNERS.set(WS, OWNER);
    isReadyGitWorkTreeSpy.mockReturnValue(false); // false on both probes
    ensureWorkspaceRepoClonedSpy.mockResolvedValue("failed");

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: false, reason: "no-workspace-synced" });
    expect(syncWorkspaceSpy).not.toHaveBeenCalled();
    expect(APPENDS.get(OWNER)!.at(-1)).toEqual(
      expect.objectContaining({ ok: false, error_class: "workspace_not_ready", workspace_id: WS }),
    );
    expect(addBreadcrumbSpy).toHaveBeenCalledWith(reclonedBreadcrumb(false));
    // No double-page at the reconcile call site (the inner mirror already paged).
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("case 4 — benign 'ok' that did NOT heal (proxy guard): re-probe still false ⇒ recovered:false, workspace_not_ready", async () => {
    WORKSPACE_ROWS = [{ id: WS }];
    OWNERS.set(WS, OWNER);
    isReadyGitWorkTreeSpy.mockReturnValue(false); // re-probe stays false
    ensureWorkspaceRepoClonedSpy.mockResolvedValue("ok"); // benign skip, healed nothing

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: false, reason: "no-workspace-synced" });
    expect(APPENDS.get(OWNER)!.at(-1)).toEqual(
      expect.objectContaining({ ok: false, error_class: "workspace_not_ready", workspace_id: WS }),
    );
    // Proves we assert the validity INVARIANT, not the "ok" proxy.
    expect(addBreadcrumbSpy).toHaveBeenCalledWith(reclonedBreadcrumb(false));
  });

  it("case 5 — owner-less workspace: ensureWorkspaceRepoCloned userId falls back to ws.id; audit via workspace-keyed path", async () => {
    const WL = "99999999-9999-4999-8999-999999999999"; // no OWNERS entry ⇒ ownerId null
    WORKSPACE_ROWS = [{ id: WL }];
    isReadyGitWorkTreeSpy.mockReturnValueOnce(false).mockReturnValueOnce(true);
    ensureWorkspaceRepoClonedSpy.mockResolvedValue("ok");

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: true, synced: 1 });
    expect(ensureWorkspaceRepoClonedSpy).toHaveBeenCalledWith(
      expect.objectContaining({ userId: WL, workspacePath: wsPath(WL), installationId: 42, repoUrl: TARGET_REPO }),
    );
    // Owner-keyed path must NOT fire; the recovery lands on the workspace-keyed path.
    expect(appendKbSyncRowSpy).not.toHaveBeenCalled();
    expect(WS_APPENDS.get(WL)!.at(-1)).toEqual(
      expect.objectContaining({ ok: true, recovered: true, workspace_id: WL }),
    );
  });
});

describe("reconcile — cross-tenant isolation (fan-out per workspace)", () => {
  it("each workspace syncs ONLY its own derived path", async () => {
    WORKSPACE_ROWS = [{ id: "77777777-7777-4777-8777-777777777777" }, { id: "88888888-8888-4888-8888-888888888888" }];
    OWNERS.set("77777777-7777-4777-8777-777777777777", "55555555-5555-4555-8555-555555555555");
    OWNERS.set("88888888-8888-4888-8888-888888888888", "66666666-6666-4666-8666-666666666666");
    EXISTING_DIRS.add(wsPath("77777777-7777-4777-8777-777777777777"));
    EXISTING_DIRS.add(wsPath("88888888-8888-4888-8888-888888888888"));
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    await handler({ event: makeEvent(), step: makeStep(), logger });

    const aCall = syncWorkspaceSpy.mock.calls.find((c) => c[3].userId === "55555555-5555-4555-8555-555555555555")!;
    const bCall = syncWorkspaceSpy.mock.calls.find((c) => c[3].userId === "66666666-6666-4666-8666-666666666666")!;
    expect(aCall[1]).toBe(wsPath("77777777-7777-4777-8777-777777777777"));
    expect(bCall[1]).toBe(wsPath("88888888-8888-4888-8888-888888888888"));
    expect(aCall[1]).not.toBe(bCall[1]);
  });
});
