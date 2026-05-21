import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// #4224 — Inngest function on `platform/workspace.reconcile.requested`.
//
// Drives `workspaceReconcileOnPushHandler` directly with a mock `step` (each
// step.run runs eagerly) so the Inngest runtime is not required for unit
// coverage. Mirrors cfo-on-payment-failed.test.ts.
//
// Load-bearing TOMs (Phase 2 write-scope + cross-tenant concurrent isolation)
// are validated here — the cross-tenant concurrent test is the canonical
// regression guard for the "syncWorkspace touched wrong workspace_path"
// failure class flagged in §User-Brand Impact.

const ORIGINAL_ENV = {
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_DEV: process.env.INNGEST_DEV,
};

function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) delete process.env[key];
  else process.env[key] = ORIGINAL_ENV[key];
}

// --- Module mocks (hoisted) -------------------------------------------------

interface UserRow {
  id: string;
  workspace_path: string;
  workspace_status: string;
  github_installation_id: number | null;
  kb_sync_history: unknown[];
}

const USER_ROWS = new Map<string, UserRow>();
const UPDATES = new Map<string, { kb_sync_history: unknown[] }>();

const tenantSelectSpy = vi.fn();
const tenantUpdateSpy = vi.fn();

const getFreshTenantClientSpy = vi.fn(async (userId: string) => {
  return {
    from: (table: string) => {
      if (table !== "users") throw new Error(`unexpected table ${table}`);
      return {
        select: (cols: string) => {
          tenantSelectSpy(userId, cols);
          return {
            eq: () => ({
              single: async () => {
                const row = USER_ROWS.get(userId);
                if (!row) return { data: null, error: { code: "PGRST116" } };
                return { data: row, error: null };
              },
              maybeSingle: async () => {
                const row = USER_ROWS.get(userId);
                return { data: row ?? null, error: null };
              },
            }),
          };
        },
        update: (patch: { kb_sync_history?: unknown[] }) => {
          tenantUpdateSpy(userId, patch);
          return {
            eq: async () => {
              const existing = USER_ROWS.get(userId);
              if (existing && patch.kb_sync_history) {
                existing.kb_sync_history = patch.kb_sync_history;
              }
              UPDATES.set(userId, {
                kb_sync_history: patch.kb_sync_history ?? [],
              });
              return { error: null };
            },
          };
        },
      };
    },
  };
});

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: getFreshTenantClientSpy,
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

const syncWorkspaceSpy = vi.fn();
vi.mock("@/server/kb-route-helpers", () => ({
  syncWorkspace: syncWorkspaceSpy,
}));

// session-sync exports `appendKbSyncRow` for the heterogeneous JSONB
// write (#4224). The mock walks the same shape as the tenant-client
// fetch/update pair below so the test asserts on UPDATES the same way.
const appendKbSyncRowSpy = vi.fn(async (userId: string, row: unknown) => {
  const existing = USER_ROWS.get(userId);
  const list = existing?.kb_sync_history ?? [];
  const updated = [...list, row];
  if (existing) existing.kb_sync_history = updated;
  UPDATES.set(userId, { kb_sync_history: updated });
});
vi.mock("@/server/session-sync", () => ({
  appendKbSyncRow: appendKbSyncRowSpy,
}));

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  hashUserId: (s: string) => `hash-${s}`,
}));

const logger = { warn: vi.fn(), info: vi.fn(), error: vi.fn() };

// --- Helpers ----------------------------------------------------------------

interface MockStep {
  calls: { name: string; result: unknown }[];
  run<T>(name: string, cb: () => Promise<T>): Promise<T>;
}

function makeStep(): MockStep {
  const calls: { name: string; result: unknown }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      const result = await cb();
      calls.push({ name, result });
      return result;
    },
  };
}

function seedUser(row: Partial<UserRow> & { id: string }) {
  const full: UserRow = {
    workspace_path: `/tmp/ws-${row.id}`,
    workspace_status: "ready",
    github_installation_id: 42,
    kb_sync_history: [],
    ...row,
  };
  USER_ROWS.set(row.id, full);
}

function makeEvent(overrides: Partial<{
  founderId: string;
  installationId: number;
  deliveryId: string;
  defaultBranch: string;
  headSha: string;
  beforeSha: string;
  pushReceivedAt: number;
}> = {}) {
  return {
    name: "platform/workspace.reconcile.requested" as const,
    v: "1",
    data: {
      founderId: "founder-A",
      installationId: 42,
      deliveryId: "delivery-1",
      defaultBranch: "main",
      headSha: "abc1234567890abcdef1234567890abcdef12345",
      beforeSha: "def4567890abcdef1234567890abcdef12345678",
      pushReceivedAt: 1_700_000_000_000,
      ...overrides,
    },
  };
}

beforeEach(() => {
  USER_ROWS.clear();
  UPDATES.clear();
  tenantSelectSpy.mockReset();
  tenantUpdateSpy.mockReset();
  syncWorkspaceSpy.mockReset();
  appendKbSyncRowSpy.mockClear();
  reportSilentFallbackSpy.mockReset();
  logger.warn.mockReset();
  logger.info.mockReset();
  logger.error.mockReset();
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
  const mod = await import(
    "@/server/inngest/functions/workspace-reconcile-on-push"
  );
  return mod.workspaceReconcileOnPushHandler;
}

describe("workspace-reconcile-on-push — happy path", () => {
  it("calls syncWorkspace + appends rich kb_sync_history row {ok:true, trigger:webhook_push}", async () => {
    seedUser({ id: "founder-A", workspace_path: "/ws/A", github_installation_id: 42 });
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    const step = makeStep();
    const result = await handler({ event: makeEvent(), step, logger });

    expect(syncWorkspaceSpy).toHaveBeenCalledTimes(1);
    expect(syncWorkspaceSpy).toHaveBeenCalledWith(
      42,
      "/ws/A",
      expect.anything(),
      expect.objectContaining({ userId: "founder-A", op: "push" }),
    );
    expect(result).toEqual(expect.objectContaining({ ok: true }));

    const update = UPDATES.get("founder-A");
    expect(update).toBeDefined();
    const row = (update!.kb_sync_history as Array<Record<string, unknown>>).slice(-1)[0];
    expect(row).toEqual(
      expect.objectContaining({
        trigger: "webhook_push",
        ok: true,
        sha_before: "def4567890abcdef1234567890abcdef12345678",
        sha_after: "abc1234567890abcdef1234567890abcdef12345",
        push_received_at: 1_700_000_000_000,
      }),
    );
    expect(typeof (row as { at: unknown }).at).toBe("string");
    expect(typeof (row as { sync_completed_at: unknown }).sync_completed_at).toBe("number");
  });
});

describe("workspace-reconcile-on-push — ff-only failure", () => {
  it("appends row {ok:false, error_class:non_fast_forward} and mirrors to Sentry", async () => {
    seedUser({ id: "founder-A", workspace_path: "/ws/A", github_installation_id: 42 });
    syncWorkspaceSpy.mockResolvedValue({
      ok: false,
      error: new Error("non-fast-forward"),
    });

    const handler = await importHandler();
    const step = makeStep();
    await handler({ event: makeEvent(), step, logger });

    const row = (UPDATES.get("founder-A")!.kb_sync_history as Array<Record<string, unknown>>).slice(-1)[0];
    expect(row).toEqual(
      expect.objectContaining({ ok: false, error_class: "non_fast_forward" }),
    );

    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const ctx = reportSilentFallbackSpy.mock.calls[0][1] as {
      feature: string;
      op?: string;
      message?: string;
    };
    expect(ctx.feature).toBe("workspace-reconcile-push");
    expect(ctx.op).toBe("sync");
    expect(ctx.message).toMatch(/workspace sync failed/i);
  });
});

describe("workspace-reconcile-on-push — workspace not ready", () => {
  it("skips syncWorkspace + appends row {ok:false, error_class:workspace_not_ready} + Sentry mirror op=skip-not-ready", async () => {
    seedUser({
      id: "founder-A",
      workspace_path: "/ws/A",
      workspace_status: "cloning",
      github_installation_id: 42,
    });

    const handler = await importHandler();
    const step = makeStep();
    await handler({ event: makeEvent(), step, logger });

    expect(syncWorkspaceSpy).not.toHaveBeenCalled();
    const row = (UPDATES.get("founder-A")!.kb_sync_history as Array<Record<string, unknown>>).slice(-1)[0];
    expect(row).toEqual(
      expect.objectContaining({ ok: false, error_class: "workspace_not_ready" }),
    );
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1]).toEqual(
      expect.objectContaining({ feature: "workspace-reconcile-push", op: "skip-not-ready" }),
    );
  });
});

describe("workspace-reconcile-on-push — unmapped founderId (defense-in-depth)", () => {
  it("does NOT call syncWorkspace and mirrors to Sentry when user row is missing", async () => {
    // Deliberately do not seed the user row.
    const handler = await importHandler();
    const step = makeStep();
    await handler({ event: makeEvent({ founderId: "ghost-founder" }), step, logger });

    expect(syncWorkspaceSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1]).toEqual(
      expect.objectContaining({
        feature: "workspace-reconcile-push",
        op: "skip-unmapped",
      }),
    );
  });
});

describe("workspace-reconcile-on-push — write-scope (single tenant)", () => {
  it("syncWorkspace receives ONLY founder A's workspace_path when event is for A", async () => {
    seedUser({ id: "founder-A", workspace_path: "/ws/A", github_installation_id: 42 });
    seedUser({ id: "founder-B", workspace_path: "/ws/B", github_installation_id: 99 });
    syncWorkspaceSpy.mockResolvedValue({ ok: true });

    const handler = await importHandler();
    const step = makeStep();
    await handler({ event: makeEvent({ founderId: "founder-A", installationId: 42 }), step, logger });

    expect(syncWorkspaceSpy).toHaveBeenCalledTimes(1);
    const [calledInstallationId, calledWorkspacePath] = syncWorkspaceSpy.mock.calls[0];
    expect(calledInstallationId).toBe(42);
    expect(calledWorkspacePath).toBe("/ws/A");
    expect(calledWorkspacePath).not.toBe("/ws/B");

    // B's row must NOT be touched.
    expect(UPDATES.get("founder-B")).toBeUndefined();
  });
});

describe("workspace-reconcile-on-push — cross-tenant concurrent (Kieran #8)", () => {
  it("two concurrent invocations isolate to their own workspace_paths (no cross-coalescing)", async () => {
    seedUser({ id: "founder-A", workspace_path: "/ws/A", github_installation_id: 42 });
    seedUser({ id: "founder-B", workspace_path: "/ws/B", github_installation_id: 99 });

    // Resolve both calls concurrently; assert both got their own params.
    syncWorkspaceSpy.mockImplementation(async (_installId, wsPath) => {
      // Simulate a small async hop so the two awaits overlap.
      await new Promise((r) => setImmediate(r));
      return { ok: true, calledWith: wsPath };
    });

    const handler = await importHandler();
    const stepA = makeStep();
    const stepB = makeStep();
    await Promise.all([
      handler({
        event: makeEvent({ founderId: "founder-A", installationId: 42, deliveryId: "delivery-A" }),
        step: stepA,
        logger,
      }),
      handler({
        event: makeEvent({ founderId: "founder-B", installationId: 99, deliveryId: "delivery-B" }),
        step: stepB,
        logger,
      }),
    ]);

    expect(syncWorkspaceSpy).toHaveBeenCalledTimes(2);
    const aCall = syncWorkspaceSpy.mock.calls.find((c) => c[0] === 42)!;
    const bCall = syncWorkspaceSpy.mock.calls.find((c) => c[0] === 99)!;
    expect(aCall[1]).toBe("/ws/A");
    expect(bCall[1]).toBe("/ws/B");

    // Each user's row records exactly one append.
    expect(
      (UPDATES.get("founder-A")!.kb_sync_history as unknown[]).length,
    ).toBe(1);
    expect(
      (UPDATES.get("founder-B")!.kb_sync_history as unknown[]).length,
    ).toBe(1);
  });
});
