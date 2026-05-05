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

function setupSupabaseMock(args: {
  visibleConversations: Array<{ id: string }>;
  slotRows: Array<{ conversation_id: string }>;
}) {
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
      const chain: Record<string, unknown> = {
        data: args.slotRows,
        error: null,
        eq: vi.fn(() => chain),
        then: (resolve: (v: unknown) => void) =>
          resolve({ data: args.slotRows, error: null }),
      };
      return { select: vi.fn(() => chain) };
    }
    return {
      select: vi.fn(() => ({
        eq: vi.fn(),
        is: vi.fn(),
        in: vi.fn(),
      })),
    };
  });
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
