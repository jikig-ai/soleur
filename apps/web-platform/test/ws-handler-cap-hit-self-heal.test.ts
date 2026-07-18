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
  mockForEachSession,
  mockHasActiveCcQuery,
} = vi.hoisted(() => ({
  mockReleaseSlot: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockServiceFrom: vi.fn(),
  // AC14: controls the LEGACY agent-loop registry probe. Default no-op = no
  // live legacy loop for any conversation. A test can override it to simulate a
  // live backgrounded loop that must be PROTECTED from the dead-socket reap.
  mockForEachSession: vi.fn(),
  // AC14: controls the cc-soleur-go (DOMINANT) loop probe. Default false = no
  // live cc query. A test overrides it to true to simulate a live cc loop that
  // must be PROTECTED from the dead-socket reap. The `_conversationId` param
  // makes the mock's type accept a 1-arg mockImplementation (TS2345 otherwise).
  mockHasActiveCcQuery: vi.fn((_conversationId: string): boolean => false),
}));

// Partial mock: preserve every real export (ws-handler imports setUserWorkspace,
// getActiveTurnConversation, etc.) and override ONLY forEachSessionForConversation
// so the AC14 hasLiveAgentLoop legacy-registry branch is controllable.
vi.mock("../server/agent-session-registry", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../server/agent-session-registry")>()),
  forEachSessionForConversation: mockForEachSession,
}));

// Partial mock of the cc-dispatcher: override ONLY hasActiveCcQuery so the AC14
// hasLiveAgentLoop cc-registry branch (the DOMINANT loop path) is controllable —
// without this the branch is only ever exercised returning false and a
// regression neutering it would ship green (test-design P1).
vi.mock("../server/cc-dispatcher", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../server/cc-dispatcher")>()),
  hasActiveCcQuery: mockHasActiveCcQuery,
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: mockServiceFrom,
    auth: { getUser: vi.fn() },
  }),
  serverUrl: "https://test.supabase.co",
}));

// PR-C §2.10 (#3244): ws-handler tenant migration. Reuse the same
// from-mock so existing predicate-aware setups continue to drive the
// new tenant-client code paths without per-test duplication.
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockServiceFrom })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
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
  // ws-handler.ts imports these liveness constants from ./concurrency; the
  // wholesale mock MUST re-export them or ws-handler reads `undefined` and the
  // staleCutoff computation becomes NaN (wholesale-mock-drops-named-exports).
  SLOT_STALENESS_THRESHOLD_SECONDS: 240,
  SLOT_HEARTBEAT_INTERVAL_MS: 60_000,
}));

vi.mock("../server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

import { tryLedgerDivergenceRecovery, sessions } from "../server/ws-handler";

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
    // clearAllMocks clears call history but NOT implementations — reset the
    // AC14 loop probes to their defaults so a prior test's live-loop override
    // does not leak. mockHasActiveCcQuery defaults to false (no cc loop).
    mockForEachSession.mockReset();
    mockHasActiveCcQuery.mockReset();
    mockHasActiveCcQuery.mockReturnValue(false);
    // The module `sessions` map is real + shared across tests in this file;
    // clear it so a prior test's focused-session injection cannot leak into a
    // dead-socket test that assumes no focused conversation.
    sessions.clear();
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

  it("all slots reference visible conversations WITH a live loop → no recovery, didRecover: false", async () => {
    // Genuine cap_hit: every slot maps to a visible-active conversation that is
    // genuinely LIVE (has an agent loop). Post-AC14, "healthy" requires a live
    // loop (or focus) — so mark conv-real-1 live. No divergence — recovery is a
    // no-op and the caller should fall through to the existing close path.
    mockForEachSession.mockImplementation(
      (_u: string, convId: string, fn: (k: string, s: unknown) => unknown) => {
        if (convId === "conv-real-1") fn("user-1:conv-real-1", {});
      },
    );
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
    // Two orphan slots + one real-visible slot with a live loop. Recovery must
    // release BOTH orphans and leave the real (live-loop-protected) slot alone.
    mockForEachSession.mockImplementation(
      (_u: string, convId: string, fn: (k: string, s: unknown) => unknown) => {
        if (convId === "conv-real-1") fn("user-1:conv-real-1", {});
      },
    );
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
    // clearAllMocks clears call history but NOT implementations — reset the
    // AC14 loop probes to their defaults so a prior test's live-loop override
    // does not leak. mockHasActiveCcQuery defaults to false (no cc loop).
    mockForEachSession.mockReset();
    mockHasActiveCcQuery.mockReset();
    mockHasActiveCcQuery.mockReturnValue(false);
    // The module `sessions` map is real + shared across tests in this file;
    // clear it so a prior test's focused-session injection cannot leak into a
    // dead-socket test that assumes no focused conversation.
    sessions.clear();
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

    // Anchor the production-side shared SLOT_STALENESS_THRESHOLD_SECONDS (240s
    // as of the 2026-07-18 Disk-IO backoff). A regression that ships `240`
    // (treated as ms) or a typo'd magnitude would miss this window.
    expect(capture.staleCutoff).toBeDefined();
    const cutoffMs = new Date(capture.staleCutoff!).getTime();
    const expected = before - 240_000;
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

  it("AC14: fresh-heartbeat visible slot with NO live agent loop → dead-socket reap (immediate cap-hit reclaim)", async () => {
    // AC14 dead-socket branch: a conversation whose slot is visible-active and
    // fresh-heartbeat (<240 s, so NEITHER orphan NOR stale), not the focused
    // socket conversation, and with no live agent loop on this instance — the
    // classic crash+reconnect+new-conversation lockout. Must be reaped
    // immediately, THRESHOLD-INDEPENDENT, so the cap-hit user is not locked out
    // for up to 240 s. mockForEachSession default no-op = no legacy loop; real
    // hasActiveCcQuery = false (no runner) → hasLiveAgentLoop = false → reaped.
    setupSupabaseMock({
      visibleConversations: [{ id: "conv-real-1" }],
      slotRows: [{ conversation_id: "conv-real-1" }],
      staleSlotRows: [],
    });

    const result = await tryLedgerDivergenceRecovery("user-1");

    expect(result.didRecover).toBe(true);
    expect(mockReleaseSlot).toHaveBeenCalledTimes(1);
    expect(mockReleaseSlot).toHaveBeenCalledWith("user-1", "conv-real-1");
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.extra).toMatchObject({
      orphanCount: 0,
      staleHeartbeatCount: 0,
      deadSocketCount: 1,
      recoveryCause: "dead-socket",
    });
  });

  it("AC14: fresh-heartbeat visible slot WITH a live agent loop → NOT reaped (backgrounded loop protected)", async () => {
    // The load-bearing safety property (CTO ruling): a backgrounded-but-live
    // loop (e.g. after crash+reconnect, or paused on a review gate) has a live
    // registry entry and MUST NOT be reaped even though it is not the focused
    // socket conversation. Simulate a live legacy loop for conv-live-1.
    mockForEachSession.mockImplementation(
      (_userId: string, _convId: string, fn: (k: string, s: unknown) => unknown) => {
        fn("user-1:conv-live-1", {}); // one live session entry → hasLiveAgentLoop true
      },
    );
    setupSupabaseMock({
      visibleConversations: [{ id: "conv-live-1" }],
      slotRows: [{ conversation_id: "conv-live-1" }],
      staleSlotRows: [],
    });

    const result = await tryLedgerDivergenceRecovery("user-1");

    expect(result.didRecover).toBe(false);
    expect(mockReleaseSlot).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("AC14: fresh-heartbeat visible slot WITH a live cc-soleur-go query → NOT reaped (dominant loop path protected)", async () => {
    // test-design P1: the cc-dispatcher lineage is the DOMINANT loop-protection
    // path and was previously exercised only returning false. Simulate a live cc
    // query for conv-cc-live; the dead-socket reap must NOT fire (killing a live
    // cc loop is the single-user incident this branch exists to avoid). Neutering
    // `if (hasActiveCcQuery(...)) return true` in hasLiveAgentLoop reddens this.
    mockHasActiveCcQuery.mockImplementation(
      (convId: string) => convId === "conv-cc-live",
    );
    setupSupabaseMock({
      visibleConversations: [{ id: "conv-cc-live" }],
      slotRows: [{ conversation_id: "conv-cc-live" }],
      staleSlotRows: [],
    });

    const result = await tryLedgerDivergenceRecovery("user-1");

    expect(result.didRecover).toBe(false);
    expect(mockReleaseSlot).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("AC14: focused-but-idle conversation (in sessions map, no live loop) → NOT reaped (focus-exclusion guard)", async () => {
    // test-design P2: the focus-exclusion guard (!focusedConvIds.has(cid)) was
    // dead code under test because no test populated the module `sessions` map.
    // A user's currently-focused conversation has a fresh heartbeat (the socket
    // is touching it) but between turns has no live agent loop — it must NOT be
    // dead-socket-reaped. Deleting `!focusedConvIds.has(cid) &&` from the filter
    // reddens this.
    sessions.set("user-1", {
      conversationId: "conv-focused",
    } as unknown as Parameters<typeof sessions.set>[1]);
    setupSupabaseMock({
      visibleConversations: [{ id: "conv-focused" }],
      slotRows: [{ conversation_id: "conv-focused" }],
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
      recoveryCause: "orphan+stale-heartbeat",
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
