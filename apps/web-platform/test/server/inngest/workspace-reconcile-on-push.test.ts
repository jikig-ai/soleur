import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

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
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  hashUserId: (s: string) => `hash-${s}`,
}));

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
    fullName: "jikig-ai/soleur",
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
      event: makeEvent({ fullName: "Jikig-AI/Soleur" }),
      step: makeStep(),
      logger,
    });

    // The match key is the composed + normalized URL (host lowercased,
    // path case preserved) — never the bare slug.
    expect(repoUrlFilterSpy).toHaveBeenCalledWith("https://github.com/Jikig-AI/Soleur");
    expect(repoUrlFilterSpy).not.toHaveBeenCalledWith("Jikig-AI/Soleur");
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
  });
});

describe("reconcile — no workspace match", () => {
  it("skips + Sentry-mirrors when no workspace is connected to the repo", async () => {
    WORKSPACE_ROWS = [];
    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: false, reason: "no-workspace-match" });
    expect(syncWorkspaceSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "workspace-reconcile-push",
        op: "skip-no-workspace-match",
      }),
    );
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
      expect.objectContaining({ ok: false, error_class: "workspace_not_ready" }),
    );
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "skip-not-ready" }),
    );
  });
});

describe("reconcile — sync failure", () => {
  it("appends {sync_failed} + Sentry mirror op=sync", async () => {
    WORKSPACE_ROWS = [{ id: "ws-A" }];
    OWNERS.set("ws-A", "owner-A");
    EXISTING_DIRS.add(wsPath("ws-A"));
    syncWorkspaceSpy.mockResolvedValue({ ok: false, error: new Error("non-fast-forward") });

    const handler = await importHandler();
    const result = await handler({ event: makeEvent(), step: makeStep(), logger });

    expect(result).toEqual({ ok: false, reason: "no-workspace-synced" });
    expect(APPENDS.get("owner-A")!.at(-1)).toEqual(
      expect.objectContaining({ ok: false, error_class: "sync_failed" }),
    );
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "workspace-reconcile-push", op: "sync" }),
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
