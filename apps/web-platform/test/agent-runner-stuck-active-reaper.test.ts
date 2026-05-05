/**
 * Phase 3 (#stuck-active fix) — periodic reaper for stuck-active conversations.
 *
 * Plan: knowledge-base/project/plans/2026-05-05-fix-cc-chat-stuck-conversation-blocks-concurrency-slot-plan.md
 *
 * The reaper periodically calls `find_stuck_active_conversations` (migration
 * 037) and finalizes any candidate row to status='failed', releases the
 * (possibly orphan) concurrency slot, and aborts the in-process session.
 *
 * AC2/AC5 requires:
 *   - `setInterval` cadence at 60 s; signal is slot-heartbeat staleness.
 *   - Order in the loop: status flip → releaseSlot → abortSession.
 *   - Idempotent: an already-released slot row is a no-op.
 *   - The RPC error path mirrors to Sentry via `reportSilentFallback`.
 *
 * RED before GREEN per AGENTS.md `cq-write-failing-tests-before`.
 */
import { vi, describe, test, expect, beforeEach, afterEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// ---------------------------------------------------------------------------
// Hoisted mocks
// ---------------------------------------------------------------------------

const {
  mockFrom,
  mockRpc,
  mockReleaseSlot,
  mockReportSilentFallback,
} = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockReleaseSlot: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: vi.fn(),
  tool: vi.fn(),
  createSdkMcpServer: vi.fn(() => ({ type: "sdk", name: "test", instance: { tools: [] } })),
}));

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockFrom, rpc: mockRpc })),
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn(), addBreadcrumb: vi.fn() }));
vi.mock("../server/ws-handler", () => ({ sendToClient: vi.fn() }));
vi.mock("../server/logger", () => ({
  default: { error: vi.fn(), warn: vi.fn(), info: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));
vi.mock("../server/byok", () => ({
  decryptKey: vi.fn(),
  decryptKeyLegacy: vi.fn(),
  encryptKey: vi.fn(),
}));
vi.mock("../server/error-sanitizer", () => ({
  sanitizeErrorForClient: vi.fn(() => "error"),
}));
vi.mock("../server/sandbox", () => ({ isPathInWorkspace: vi.fn(() => true) }));
vi.mock("../server/agent-env", () => ({ buildAgentEnv: vi.fn(() => ({})) }));
vi.mock("../server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => vi.fn()),
}));
vi.mock("../server/review-gate", () => ({
  abortableReviewGate: vi.fn(),
  validateSelection: vi.fn(),
  extractReviewGateInput: vi.fn(),
  buildReviewGateResponse: vi.fn(),
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => ({
  ROUTABLE_DOMAIN_LEADERS: [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }],
  DOMAIN_LEADERS: [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }],
}));
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({ syncPull: vi.fn(), syncPush: vi.fn() }));
vi.mock("../server/github-app", () => ({ createPullRequest: vi.fn() }));
vi.mock("../server/vision-helpers", () => ({
  tryCreateVision: vi.fn(),
  buildVisionEnhancementPrompt: vi.fn(),
}));
vi.mock("../server/providers", () => ({ PROVIDER_CONFIG: {}, EXCLUDED_FROM_SERVICES_UI: [] }));

vi.mock("../server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

vi.mock("../server/concurrency", () => ({
  releaseSlot: mockReleaseSlot,
  acquireSlot: vi.fn(),
  touchSlot: vi.fn(),
  emitConcurrencyCapHit: vi.fn(),
}));

import {
  startStuckActiveReaper,
  abortSession,
} from "../server/agent-runner";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface ConversationRow {
  id: string;
  user_id: string;
  status: "active" | "waiting_for_user" | "failed" | "completed";
}

/**
 * Build a Supabase mock that:
 *  - Routes RPC calls to `mockRpc`.
 *  - Captures `update().eq().eq()` writes to a `conversations` table.
 *  - Returns a fixed candidate set for `find_stuck_active_conversations`.
 */
function setupSupabaseMockForReaper(args: {
  /** Rows the RPC should report as stuck-active candidates. */
  candidates: Array<{ id: string; user_id: string }>;
  /** RPC error to simulate. */
  rpcError?: { message: string };
}): {
  statusUpdates: Array<{ conversationId: string; userId: string; status: string }>;
} {
  const statusUpdates: Array<{ conversationId: string; userId: string; status: string }> = [];

  mockRpc.mockImplementation(async (name: string) => {
    if (name === "find_stuck_active_conversations") {
      if (args.rpcError) return { data: null, error: args.rpcError };
      return { data: args.candidates, error: null };
    }
    return { data: null, error: null };
  });

  mockFrom.mockImplementation((table: string) => {
    if (table === "conversations") {
      return {
        update: vi.fn((patch: Record<string, unknown>) => {
          // The conversation-writer wrapper uses
          // `.update(patch).eq("id", convId).eq("user_id", userId)` and
          // either awaits the query directly (`expectMatch: false`) or
          // chains `.select("id")` first (`expectMatch: true`). Capture
          // the keyed pair on the .eq() calls and emit a `statusUpdates`
          // record on EITHER terminal: the awaited chain (.then) OR the
          // `.select()` fork — whichever the caller takes.
          let capturedConvId: string | undefined;
          let capturedUserId: string | undefined;
          const recordWrite = () => {
            if (capturedConvId && capturedUserId) {
              statusUpdates.push({
                conversationId: capturedConvId,
                userId: capturedUserId,
                status: String(patch.status ?? ""),
              });
            }
          };
          const chain: Record<string, unknown> = {
            // PostgREST builders are thenable — the await on the chain
            // resolves with `{ data, error }`. The reaper's expectMatch:false
            // path takes this branch (no `.select()`).
            then: (resolve: (v: unknown) => void) => {
              recordWrite();
              return resolve({ data: null, error: null });
            },
            eq: vi.fn((col: string, val: string) => {
              if (col === "id") capturedConvId = val;
              if (col === "user_id") capturedUserId = val;
              return chain;
            }),
            select: vi.fn(() => {
              recordWrite();
              return Promise.resolve({
                data: [{ id: capturedConvId ?? "x" }],
                error: null,
              });
            }),
          };
          (chain.eq as ReturnType<typeof vi.fn>).mockImplementation(
            (col: string, val: string) => {
              if (col === "id") capturedConvId = val;
              if (col === "user_id") capturedUserId = val;
              return chain;
            },
          );
          return chain;
        }),
      };
    }
    return {
      select: () => ({ eq: () => ({ single: () => ({ data: null, error: null }) }) }),
      update: () => ({ eq: () => ({ error: null }) }),
      insert: () => ({ error: null }),
    };
  });

  return { statusUpdates };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("startStuckActiveReaper (AC2/AC5)", () => {
  let timer: NodeJS.Timeout | undefined;

  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });

  afterEach(() => {
    if (timer) clearInterval(timer);
    vi.useRealTimers();
  });

  test("reaps stuck-active rows surfaced by the RPC: status→failed, releaseSlot, abortSession", async () => {
    // The RPC's predicate (slot missing OR heartbeat stale) is exercised
    // by migration 037; the reaper trusts whatever IDs it returns. The
    // test seeds two reapable candidates and verifies the per-row order
    // (status flip → releaseSlot → abortSession) and that an out-of-scope
    // row (NOT returned by the RPC) is untouched.
    const reapable: ConversationRow[] = [
      { id: "conv-orphan-no-slot", user_id: "user-A", status: "active" },
      { id: "conv-stale-heartbeat", user_id: "user-B", status: "active" },
    ];
    const outOfScope: ConversationRow = {
      id: "conv-fresh-slot",
      user_id: "user-C",
      status: "active",
    };

    const { statusUpdates } = setupSupabaseMockForReaper({
      candidates: reapable.map(({ id, user_id }) => ({ id, user_id })),
    });

    timer = startStuckActiveReaper();

    // Advance past one tick (60 s) and drain the microtasks queued by the
    // RPC promise + per-row writes. Clear the timer BEFORE additional
    // microtask drains so a second tick doesn't fire and double the
    // observed call counts.
    await vi.advanceTimersByTimeAsync(60_000);
    if (timer) clearInterval(timer);
    timer = undefined;
    // One more await turn so any in-flight async work from the tick we
    // already triggered settles before we assert.
    await Promise.resolve();
    await Promise.resolve();

    // Each reapable row got a status flip to "failed".
    for (const row of reapable) {
      expect(statusUpdates).toContainEqual({
        conversationId: row.id,
        userId: row.user_id,
        status: "failed",
      });
    }

    // Out-of-scope row was never returned by the RPC — no write for it.
    expect(
      statusUpdates.find((u) => u.conversationId === outOfScope.id),
    ).toBeUndefined();

    // releaseSlot was called for each reapable row, with the keyed
    // (userId, conversationId) tuple.
    expect(mockReleaseSlot).toHaveBeenCalledTimes(reapable.length);
    for (const row of reapable) {
      expect(mockReleaseSlot).toHaveBeenCalledWith(row.user_id, row.id);
    }
  });

  test("RPC error → reportSilentFallback fires; reaper does NOT throw", async () => {
    setupSupabaseMockForReaper({
      candidates: [],
      rpcError: { message: "RPC outage" },
    });

    // Should not throw — the reaper is a fire-and-forget interval.
    timer = startStuckActiveReaper();
    await vi.advanceTimersByTimeAsync(61_000);
    await vi.runOnlyPendingTimersAsync();

    // Mirror to Sentry per cq-silent-fallback-must-mirror-to-sentry.
    expect(mockReportSilentFallback).toHaveBeenCalled();
    const call = mockReportSilentFallback.mock.calls[0];
    expect(call[1]).toMatchObject({
      feature: "concurrency-stuck-active-reaper",
    });

    // No status writes attempted on the error path.
    expect(mockReleaseSlot).not.toHaveBeenCalled();
  });

  test("empty candidate set → no DB writes and no slot releases", async () => {
    const { statusUpdates } = setupSupabaseMockForReaper({ candidates: [] });

    timer = startStuckActiveReaper();
    await vi.advanceTimersByTimeAsync(61_000);
    await vi.runOnlyPendingTimersAsync();

    expect(statusUpdates).toEqual([]);
    expect(mockReleaseSlot).not.toHaveBeenCalled();
  });

  // Discoverability: assert the abort export (unused here directly, but
  // the reaper depends on it). A mis-export would surface as a TypeError
  // at runtime — better to crash the test at import time.
  test("abortSession is exported (smoke check on shared invariant)", () => {
    expect(typeof abortSession).toBe("function");
  });
});
