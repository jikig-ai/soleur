import { describe, it, expect, vi, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const { mockReportSilentFallback, mockSupabaseFrom, FakeRuntimeAuthError } =
  vi.hoisted(() => ({
    mockReportSilentFallback: vi.fn(),
    mockSupabaseFrom: vi.fn(),
    FakeRuntimeAuthError: class FakeRuntimeAuthError extends Error {},
  }));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

// PR-C §2.4 (#3244): conversation-writer.ts now imports from
// `@/lib/supabase/tenant` instead of using `@supabase/supabase-js`
// + `createServiceClient`. Mock the tenant module directly.
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockSupabaseFrom })),
  RuntimeAuthError: FakeRuntimeAuthError,
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

import {
  updateConversationFor,
  __resetSentryDedupForTests,
} from "@/server/conversation-writer";

type UpdateCall = {
  payload: Record<string, unknown>;
  eqs: Array<[string, unknown]>;
  ins: Array<[string, unknown[]]>;
};

function captureUpdateChain(
  opts: {
    errorOnUpdate?: Error | null;
    selectData?: { id: string }[] | null;
    /** When provided, the update chain resolves with 0 rows IF the
     *  caller appended an `.in("status", values)` predicate that does
     *  NOT include `simulatedStatus`. Lets a single test scenario
     *  exercise both the "row matches the guard" and "row excluded by
     *  the guard" outcomes without per-test mock branching. */
    simulatedStatus?: string;
  } = {},
): UpdateCall[] {
  const errorOnUpdate = opts.errorOnUpdate ?? null;
  const updateCalls: UpdateCall[] = [];

  mockSupabaseFrom.mockImplementation((table: string) => {
    if (table === "users") {
      // PR-C §2.4 (#3244): auth probe `tenant.from("users")...maybeSingle()`.
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: { id: "user-1" },
              error: null,
            }),
          }),
        }),
      };
    }
    if (table !== "conversations") {
      throw new Error(`unexpected table: ${table}`);
    }
    return {
      update: (payload: Record<string, unknown>) => {
        const entry: UpdateCall = { payload, eqs: [], ins: [] };
        updateCalls.push(entry);
        const chain: Record<string, unknown> = {
          error: errorOnUpdate,
          eq: (col: string, val: unknown) => {
            entry.eqs.push([col, val]);
            return chain;
          },
          in: (col: string, vals: unknown[]) => {
            entry.ins.push([col, vals]);
            return chain;
          },
          select: () => ({
            // expectMatch path resolves the chain via .select("id").
            then: (resolve: (v: unknown) => void) => {
              const guard = entry.ins.find(([c]) => c === "status");
              const guardExcluded =
                guard !== undefined &&
                opts.simulatedStatus !== undefined &&
                !(guard[1] as string[]).includes(opts.simulatedStatus);
              return resolve({
                data: guardExcluded ? [] : (opts.selectData ?? [{ id: "conv-1" }]),
                error: errorOnUpdate,
              });
            },
          }),
          then: (resolve: (v: unknown) => void) =>
            resolve({ error: errorOnUpdate }),
        };
        return chain;
      },
    };
  });

  return updateCalls;
}

describe("updateConversationFor", () => {
  beforeEach(() => {
    mockReportSilentFallback.mockClear();
    mockSupabaseFrom.mockReset();
    __resetSentryDedupForTests();
  });

  // T1 — happy path
  it("writes the patch and pins both .eq(id, user_id) (R8 invariant)", async () => {
    const updateCalls = captureUpdateChain();

    const result = await updateConversationFor("user-1", "conv-1", {
      status: "completed",
      last_active: "2026-04-27T00:00:00.000Z",
    });

    expect(result.ok).toBe(true);
    expect(updateCalls).toHaveLength(1);
    expect(updateCalls[0].payload).toEqual({
      status: "completed",
      last_active: "2026-04-27T00:00:00.000Z",
    });

    const cols = updateCalls[0].eqs.map(([c]) => c).sort();
    expect(cols).toEqual(["id", "user_id"]);

    const idEq = updateCalls[0].eqs.find(([c]) => c === "id");
    expect(idEq?.[1]).toBe("conv-1");

    const userIdEq = updateCalls[0].eqs.find(([c]) => c === "user_id");
    expect(userIdEq?.[1]).toBe("user-1");

    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  // T2 — error path mirrors to Sentry via reportSilentFallback
  it("mirrors errors to reportSilentFallback and returns ok: false", async () => {
    captureUpdateChain({ errorOnUpdate: new Error("db unavailable") });

    const result = await updateConversationFor("user-1", "conv-1", {
      status: "failed",
    });

    expect(result.ok).toBe(false);
    expect(result.error?.message).toBe("db unavailable");

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [errArg, opts] = mockReportSilentFallback.mock.calls[0];
    expect(errArg).toBeInstanceOf(Error);
    expect((errArg as Error).message).toBe("db unavailable");
    expect(opts).toMatchObject({
      feature: "conversation-writer",
      op: "update",
      extra: {
        userId: "user-1",
        conversationId: "conv-1",
        patchKeys: ["status"],
      },
    });
  });

  // T3 — feature/op overrides flow into the Sentry tag
  it("propagates caller-provided feature, op, and extra into the Sentry tag", async () => {
    captureUpdateChain({ errorOnUpdate: new Error("boom") });

    await updateConversationFor(
      "user-1",
      "conv-1",
      { status: "completed" },
      {
        feature: "ws-handler",
        op: "supersede-on-reconnect",
        extra: { sessionId: "sess-1" },
      },
    );

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const opts = mockReportSilentFallback.mock.calls[0][1];
    expect(opts.feature).toBe("ws-handler");
    expect(opts.op).toBe("supersede-on-reconnect");
    expect(opts.extra).toMatchObject({
      userId: "user-1",
      conversationId: "conv-1",
      patchKeys: ["status"],
      sessionId: "sess-1",
    });
  });

  // T4 — 0-rows-affected is silent success (Supabase returns no error for
  // composite-key misses; documented contract)
  it("returns ok: true when no rows match the composite key (no error from supabase)", async () => {
    const updateCalls = captureUpdateChain();

    const result = await updateConversationFor("wrong-user", "conv-1", {
      status: "completed",
    });

    expect(result.ok).toBe(true);
    expect(updateCalls).toHaveLength(1);
    const userIdEq = updateCalls[0].eqs.find(([c]) => c === "user_id");
    expect(userIdEq?.[1]).toBe("wrong-user");
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  // T5 — expectMatch: 0-rows-affected surfaces as failure
  it("returns ok: false and mirrors to Sentry when expectMatch is set and 0 rows match", async () => {
    captureUpdateChain({ selectData: [] });

    const result = await updateConversationFor(
      "user-1",
      "conv-1",
      { status: "completed" },
      { feature: "ws-handler", op: "close-conversation", expectMatch: true },
    );

    expect(result.ok).toBe(false);
    expect(result.error?.message).toBe("conversation update affected 0 rows");

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [errArg, opts] = mockReportSilentFallback.mock.calls[0];
    expect(errArg).toBeNull();
    expect(opts).toMatchObject({
      feature: "ws-handler",
      op: "close-conversation",
      message: "conversation update affected 0 rows (expectMatch)",
    });
  });

  // T6 — expectMatch: success path returns ok: true and does not page Sentry
  it("returns ok: true when expectMatch is set and >=1 row matches", async () => {
    captureUpdateChain({ selectData: [{ id: "conv-1" }] });

    const result = await updateConversationFor(
      "user-1",
      "conv-1",
      { status: "completed" },
      { feature: "ws-handler", op: "close-conversation", expectMatch: true },
    );

    expect(result.ok).toBe(true);
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  // T7 — error preserves cause chain (caller can introspect Postgres error)
  it("preserves the underlying Supabase error as Error.cause", async () => {
    const dbErr = Object.assign(new Error("db unavailable"), {
      code: "PGRST301",
    });
    captureUpdateChain({ errorOnUpdate: dbErr });

    const result = await updateConversationFor("user-1", "conv-1", {
      status: "completed",
    });

    expect(result.ok).toBe(false);
    expect(result.error?.cause).toBe(dbErr);
  });

  // T8 — Sentry dedup caps blast radius during error storms (one mirror
  // per feature/op/kind per dedup window). Required so a Supabase outage
  // doesn't blow through the Sentry quota with hundreds of duplicate
  // events per second.
  it("dedups Sentry mirrors to one per (feature, op, kind) per window", async () => {
    captureUpdateChain({ errorOnUpdate: new Error("db unavailable") });

    for (let i = 0; i < 5; i++) {
      await updateConversationFor("user-1", `conv-${i}`, {
        status: "failed",
      });
    }

    // 5 calls, all errored, but only one Sentry mirror within the dedup
    // window for the same (feature, op, "error") tuple.
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });

  // T9 — different (feature, op) pairs do NOT share a dedup slot
  it("does not share a dedup slot across feature/op pairs", async () => {
    captureUpdateChain({ errorOnUpdate: new Error("boom") });

    await updateConversationFor(
      "user-1",
      "conv-1",
      { status: "failed" },
      { feature: "ws-handler", op: "close-conversation" },
    );
    await updateConversationFor(
      "user-1",
      "conv-2",
      { status: "failed" },
      { feature: "ws-handler", op: "supersede-on-reconnect" },
    );
    await updateConversationFor(
      "user-1",
      "conv-3",
      { status: "failed" },
      { feature: "agent-runner", op: "updateConversationStatus" },
    );

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(3);
  });

  // T10 — onlyIfStatusIn appends `.in("status", [...])` to the base query
  // (#3463: narrows the abort-branch's UPDATE so it cannot stomp a row
  // that already reached a terminal state).
  it("appends .in(status, [...]) when onlyIfStatusIn is provided", async () => {
    const updateCalls = captureUpdateChain();

    const result = await updateConversationFor(
      "user-1",
      "conv-1",
      { status: "failed" },
      { onlyIfStatusIn: ["active"] },
    );

    expect(result.ok).toBe(true);
    expect(updateCalls).toHaveLength(1);
    expect(updateCalls[0].ins).toEqual([["status", ["active"]]]);

    // Composite key is still pinned alongside the status guard.
    const cols = updateCalls[0].eqs.map(([c]) => c).sort();
    expect(cols).toEqual(["id", "user_id"]);
  });

  // T11 — onlyIfStatusIn omitted: no .in() chained, behavior identical to today
  it("does not call .in() when onlyIfStatusIn is omitted", async () => {
    const updateCalls = captureUpdateChain();

    await updateConversationFor("user-1", "conv-1", { status: "failed" });

    expect(updateCalls).toHaveLength(1);
    expect(updateCalls[0].ins).toEqual([]);
  });

  // T12 — onlyIfStatusIn + expectMatch=false: 0-rows-affected (row excluded
  // by the guard) is silent success, no Sentry mirror. This is the
  // load-bearing race-window contract for the new agent-runner helper.
  it("returns ok: true silently when onlyIfStatusIn excludes the row and expectMatch is false", async () => {
    captureUpdateChain({ simulatedStatus: "waiting_for_user" });

    const result = await updateConversationFor(
      "user-1",
      "conv-1",
      { status: "failed" },
      { onlyIfStatusIn: ["active"] },
    );

    expect(result.ok).toBe(true);
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  // T13 — onlyIfStatusIn + expectMatch=true: 0-rows-affected still surfaces
  // as failure (expectMatch's contract is unchanged by the new guard).
  it("returns ok: false when onlyIfStatusIn excludes the row and expectMatch is true", async () => {
    captureUpdateChain({ simulatedStatus: "waiting_for_user" });

    const result = await updateConversationFor(
      "user-1",
      "conv-1",
      { status: "failed" },
      {
        onlyIfStatusIn: ["active"],
        expectMatch: true,
        feature: "test",
        op: "guarded-write",
      },
    );

    expect(result.ok).toBe(false);
    expect(result.error?.message).toBe("conversation update affected 0 rows");
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });
});
