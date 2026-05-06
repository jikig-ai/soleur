/**
 * Phase 4 (#stuck-active fix) — self-healing cap_hit ledger-divergence recovery.
 *
 * Plan: knowledge-base/project/plans/2026-05-05-fix-cc-chat-stuck-conversation-blocks-concurrency-slot-plan.md
 *
 * When `acquireSlot` returns `cap_hit` and the user's *visible* active
 * conversations (status in active/waiting_for_user, archived_at IS NULL)
 * are FEWER than slots in `user_concurrency_slots`, the ledger has at
 * least one orphan slot — its conversation row is missing or no longer
 * visible. `tryLedgerDivergenceRecovery` releases the orphans, mirrors
 * the divergence to Sentry via `reportSilentFallback`, and lets the
 * caller retry `acquireSlot` once. If the second attempt also returns
 * `cap_hit`, the existing close path runs unchanged (genuine cap).
 *
 * AC4/AC7 requires:
 *   - Orphan-slot scenario: divergence detected, orphan released,
 *     `didRecover: true`.
 *   - All-visible-real scenario: no recovery, `didRecover: false`,
 *     genuine cap_hit proceeds.
 *   - Sentry mirror tagged `feature: "concurrency-ledger-divergence"`,
 *     `op: "start_session-recovery"`.
 *
 * RED before GREEN per AGENTS.md `cq-write-failing-tests-before`.
 */
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, it, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Hoisted mocks
// ---------------------------------------------------------------------------

const {
  mockReleaseSlot,
  mockReportSilentFallback,
  mockServiceFrom,
} = vi.hoisted(() => ({
  mockReleaseSlot: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockServiceFrom: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: mockServiceFrom,
    auth: { getUser: vi.fn() },
  }),
  serverUrl: "https://test.supabase.co",
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
  addBreadcrumb: vi.fn(),
  captureMessage: vi.fn(),
}));

vi.mock("../server/agent-runner", () => ({
  startAgentSession: vi.fn(),
  sendUserMessage: vi.fn(),
  resolveReviewGate: vi.fn(),
  abortSession: vi.fn(),
}));

vi.mock("../server/concurrency", () => ({
  releaseSlot: mockReleaseSlot,
  acquireSlot: vi.fn(),
  touchSlot: vi.fn(),
  emitConcurrencyCapHit: vi.fn(),
}));

vi.mock("../server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

import { tryLedgerDivergenceRecovery } from "../server/ws-handler";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Captures runtime values the mock observes so tests can assert on the
 * production code's filter arguments (e.g. the stale-heartbeat cutoff
 * timestamp). Without this, the mock would silently accept any cutoff
 * value and a constant-value regression (e.g. `120` instead of
 * `120_000`) would not fail the test.
 */
interface MockCapture {
  /** Last `last_heartbeat_at` cutoff passed to `.lt(...)` on the
   *  `user_concurrency_slots` chain. */
  staleCutoff?: string;
}

function setupSupabaseMock(args: {
  visibleConversations: Array<{ id: string }>;
  slotRows: Array<{ conversation_id: string }>;
  /**
   * Slots whose `last_heartbeat_at < now() - STALE_HEARTBEAT_THRESHOLD_SECONDS`.
   * A separate SELECT on `user_concurrency_slots` with an `.lt(...)` clause
   * must resolve to these rows. The first SELECT (orphan path, no `.lt()`)
   * resolves to `slotRows`. Defaults to `[]` so existing tests are
   * unchanged.
   */
  staleSlotRows?: Array<{ conversation_id: string }>;
}): MockCapture {
  const staleRows = args.staleSlotRows ?? [];
  const capture: MockCapture = {};
  mockServiceFrom.mockImplementation((table: string) => {
    if (table === "conversations") {
      // .select("id").eq("user_id", uid).is("archived_at", null).in("status", [...])
      const chain: Record<string, unknown> = {
        data: args.visibleConversations,
        error: null,
        eq: vi.fn(() => chain),
        is: vi.fn(() => chain),
        in: vi.fn(() => chain),
        then: (resolve: (v: unknown) => void) =>
          resolve({ data: args.visibleConversations, error: null }),
      };
      return { select: vi.fn(() => chain) };
    }
    if (table === "user_concurrency_slots") {
      // Per-from() chain: `.lt()` flips the chain into stale-heartbeat
      // mode AND captures the cutoff value so tests can assert the
      // production-side constant. Production calls `.from()` twice
      // (once without `.lt()` for the orphan path, once with `.lt()`
      // for the stale path) — each gets a fresh chain, so the
      // `isStaleQuery` flag does not leak across queries.
      let isStaleQuery = false;
      const chain: Record<string, unknown> = {
        error: null,
        eq: vi.fn(() => chain),
        lt: vi.fn((_col: string, val: string) => {
          isStaleQuery = true;
          capture.staleCutoff = val;
          return chain;
        }),
        then: (resolve: (v: unknown) => void) =>
          resolve({
            data: isStaleQuery ? staleRows : args.slotRows,
            error: null,
          }),
      };
      return { select: vi.fn(() => chain) };
    }
    return {
      select: vi.fn(() => ({
        eq: vi.fn(),
        is: vi.fn(),
        in: vi.fn(),
        lt: vi.fn(),
      })),
    };
  });
  return capture;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("tryLedgerDivergenceRecovery (AC4/AC7)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("orphan slot present → releases orphan, mirrors to Sentry, returns didRecover: true", async () => {
    // Slot references a conversation that is NOT in the user's visible
    // active set (archived, hard-deleted, or never existed). Recovery
    // must release the orphan.
    setupSupabaseMock({
      visibleConversations: [], // user perceives zero active conversations
      slotRows: [{ conversation_id: "conv-orphan-1" }],
    });

    const result = await tryLedgerDivergenceRecovery("user-1");

    expect(result.didRecover).toBe(true);
    expect(mockReleaseSlot).toHaveBeenCalledTimes(1);
    expect(mockReleaseSlot).toHaveBeenCalledWith("user-1", "conv-orphan-1");

    // Sentry mirror — tagged per AC4.
    expect(mockReportSilentFallback).toHaveBeenCalled();
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts).toMatchObject({
      feature: "concurrency-ledger-divergence",
      op: "start_session-recovery",
    });
    expect(opts.extra).toMatchObject({
      userId: "user-1",
      visibleCount: 0,
      slotCount: 1,
      orphanCount: 1,
    });
  });

  it("all slots reference visible conversations → no recovery, didRecover: false", async () => {
    // Genuine cap_hit: every slot maps to a visible-active conversation.
    // No divergence — recovery is a no-op and the caller should fall
    // through to the existing close path.
    setupSupabaseMock({
      visibleConversations: [{ id: "conv-real-1" }],
      slotRows: [{ conversation_id: "conv-real-1" }],
    });

    const result = await tryLedgerDivergenceRecovery("user-1");

    expect(result.didRecover).toBe(false);
    expect(mockReleaseSlot).not.toHaveBeenCalled();
    // No Sentry mirror on the success/no-divergence path (AC4 explicitly
    // excludes the recovered case from telemetry to avoid noise).
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("multiple orphan slots → releases each, reports orphanCount", async () => {
    // Two orphan slots + one real-visible slot. Recovery must release
    // BOTH orphans and leave the real slot alone.
    setupSupabaseMock({
      visibleConversations: [{ id: "conv-real-1" }],
      slotRows: [
        { conversation_id: "conv-real-1" },
        { conversation_id: "conv-orphan-A" },
        { conversation_id: "conv-orphan-B" },
      ],
    });

    const result = await tryLedgerDivergenceRecovery("user-1");

    expect(result.didRecover).toBe(true);
    expect(mockReleaseSlot).toHaveBeenCalledTimes(2);
    expect(mockReleaseSlot).toHaveBeenCalledWith("user-1", "conv-orphan-A");
    expect(mockReleaseSlot).toHaveBeenCalledWith("user-1", "conv-orphan-B");
    // The real slot must NOT be released.
    expect(mockReleaseSlot).not.toHaveBeenCalledWith("user-1", "conv-real-1");

    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.extra).toMatchObject({
      userId: "user-1",
      visibleCount: 1,
      slotCount: 3,
      orphanCount: 2,
    });
  });

  it("zero slots → no recovery, no Sentry, didRecover: false", async () => {
    // Edge case: cap_hit with zero slot rows shouldn't happen, but if
    // it does the helper must return cleanly without divergence noise.
    setupSupabaseMock({
      visibleConversations: [],
      slotRows: [],
    });

    const result = await tryLedgerDivergenceRecovery("user-1");

    expect(result.didRecover).toBe(false);
    expect(mockReleaseSlot).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// stale-heartbeat reap (May-6 extension — see plan
// 2026-05-06-fix-one-shot-conversation-limit-stuck-executing-plan.md)
//
// `tryLedgerDivergenceRecovery` widened to also reap slots whose
// `last_heartbeat_at` lapsed past STUCK_ACTIVE_THRESHOLD_SECONDS even when
// the conversation row IS still visible (status='active', archived_at IS
// NULL). This closes the 0-180s dead-end window between an old WS
// supersession and the next reaper tick.
// ---------------------------------------------------------------------------

describe("tryLedgerDivergenceRecovery — stale-heartbeat reap (May-6)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("stale-heartbeat slot whose conversation IS visible → reaps slot, mirrors with staleHeartbeatCount, didRecover: true", async () => {
    // Reproduction of the May-6 dead-end: dashboard's stuck-Executing
    // conversation IS visible (status='active', archived_at NULL), so the
    // orphan check returns []. The widened helper must additionally
    // detect that the slot's heartbeat is stale (>120s) and reap it.
    const before = Date.now();
    const capture = setupSupabaseMock({
      visibleConversations: [{ id: "conv-stuck-active" }],
      slotRows: [{ conversation_id: "conv-stuck-active" }],
      staleSlotRows: [{ conversation_id: "conv-stuck-active" }],
    });

    const result = await tryLedgerDivergenceRecovery("user-1");

    expect(result.didRecover).toBe(true);
    expect(mockReleaseSlot).toHaveBeenCalledTimes(1);
    expect(mockReleaseSlot).toHaveBeenCalledWith("user-1", "conv-stuck-active");

    // Anchor the production-side STALE_HEARTBEAT_THRESHOLD_SECONDS constant.
    // A regression that ships `120` (treated as ms) or `1_200_000` (typo)
    // would miss this; this assertion catches it.
    expect(capture.staleCutoff).toBeDefined();
    const cutoffMs = new Date(capture.staleCutoff!).getTime();
    const expected = before - 120_000;
    expect(Math.abs(cutoffMs - expected)).toBeLessThan(5_000);

    expect(mockReportSilentFallback).toHaveBeenCalled();
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts).toMatchObject({
      feature: "concurrency-ledger-divergence",
      op: "start_session-recovery",
    });
    expect(opts.extra).toMatchObject({
      userId: "user-1",
      visibleCount: 1,
      slotCount: 1,
      orphanCount: 0,
      staleHeartbeatCount: 1,
      recoveryCause: "stale-heartbeat",
    });
  });

  it("fresh-heartbeat slot whose conversation IS visible → no reap, no Sentry, didRecover: false", async () => {
    // Negative gate: a slot whose heartbeat is fresh (returned as []
    // by the stale SELECT) and whose conversation is visible is a
    // genuine cap_hit. The widened helper must NOT over-fire.
    setupSupabaseMock({
      visibleConversations: [{ id: "conv-real-1" }],
      slotRows: [{ conversation_id: "conv-real-1" }],
      staleSlotRows: [],
    });

    const result = await tryLedgerDivergenceRecovery("user-1");

    expect(result.didRecover).toBe(false);
    expect(mockReleaseSlot).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("orphan slot AND separate stale-heartbeat slot → reaps both, Sentry shows both counts", async () => {
    // convA: orphan (slot present, conversation NOT visible).
    // convB: stale-heartbeat (slot present, conversation visible, heartbeat lapsed).
    // Both must be reaped in a single recovery pass.
    setupSupabaseMock({
      visibleConversations: [{ id: "conv-B" }],
      slotRows: [{ conversation_id: "conv-A" }, { conversation_id: "conv-B" }],
      staleSlotRows: [{ conversation_id: "conv-B" }],
    });

    const result = await tryLedgerDivergenceRecovery("user-1");

    expect(result.didRecover).toBe(true);
    expect(mockReleaseSlot).toHaveBeenCalledTimes(2);
    expect(mockReleaseSlot).toHaveBeenCalledWith("user-1", "conv-A");
    expect(mockReleaseSlot).toHaveBeenCalledWith("user-1", "conv-B");

    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.extra).toMatchObject({
      userId: "user-1",
      visibleCount: 1,
      slotCount: 2,
      orphanCount: 1,
      staleHeartbeatCount: 1,
      recoveryCause: "orphan-and-stale",
    });
  });

  it("same conversation appears in BOTH orphan and stale-heartbeat sets → releaseSlot called once (deduped)", async () => {
    // A slot whose conversation is hard-deleted AND whose heartbeat
    // lapsed appears in both detection branches. The recovery pass must
    // dedup by conversation_id so we don't issue two releaseSlot calls
    // for the same row (idempotent at the DB but breadcrumb noise).
    setupSupabaseMock({
      visibleConversations: [],
      slotRows: [{ conversation_id: "conv-A" }],
      staleSlotRows: [{ conversation_id: "conv-A" }],
    });

    const result = await tryLedgerDivergenceRecovery("user-1");

    expect(result.didRecover).toBe(true);
    expect(mockReleaseSlot).toHaveBeenCalledTimes(1);
    expect(mockReleaseSlot).toHaveBeenCalledWith("user-1", "conv-A");

    // Single Sentry mirror per recovery invocation (Sharp Edge in plan).
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.extra).toMatchObject({
      userId: "user-1",
      orphanCount: 1,
      staleHeartbeatCount: 1,
    });
  });
});
