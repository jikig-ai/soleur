import {
  describe,
  it,
  expect,
  vi,
  beforeEach,
  afterEach,
} from "vitest";
import {
  createMockQueryScripted as createMockQuery,
  makeRecordingEvents as makeEvents,
  flushMicrotasks,
} from "./helpers/soleur-go-fixtures";

// #4440 follow-up to #4418 — `session_revoked` WorkflowEnd propagation.
//
// Pins the contract: when the SDK iterator inside `consumeStream` throws
// a `RuntimeAuthError` with `cause === "denied_jti"` (the mid-stream
// JWT-deny race), the runner emits a `WorkflowEnd{status:"session_revoked", reason, deniedAt}`
// rather than the generic `internal_error`. The reason / deniedAt
// fields come from a best-effort `getMyRevocationStatus(userId)` RPC
// (mocked here via the helper module).
//
// Non-`denied_jti` RuntimeAuthError causes (jwt_mint, rotation) still
// route through `internal_error` — only the deny-list cause warrants
// the dedicated terminal status, because the session is recoverable
// from a transient mint failure.

const { mockReportSilentFallback, mockMirrorWithDebounce } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockMirrorWithDebounce: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
  mirrorWithDebounce: mockMirrorWithDebounce,
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));

const { mockGetMyRevocationStatus } = vi.hoisted(() => ({
  mockGetMyRevocationStatus: vi.fn(),
}));
vi.mock("@/lib/supabase/tenant", async () => {
  // Re-export the real `RuntimeAuthError` class so `instanceof` checks
  // inside the runner match the test-instantiated error. Substitute
  // `getMyRevocationStatus` + the rest of the module surface area the
  // runner imports (none of which we need to mock for this test).
  const actual = await vi.importActual<typeof import("@/lib/supabase/tenant")>(
    "@/lib/supabase/tenant",
  );
  return {
    ...actual,
    getMyRevocationStatus: (...args: unknown[]) =>
      mockGetMyRevocationStatus(...args),
  };
});

import { RuntimeAuthError } from "@/lib/supabase/tenant";
import { createSoleurGoRunner } from "@/server/soleur-go-runner";

describe("consumeStream — RuntimeAuthError JWT-deny propagation (#4440)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("denied_jti RuntimeAuthError → WorkflowEnd { status: 'session_revoked', reason, deniedAt }", async () => {
    mockGetMyRevocationStatus.mockResolvedValue({
      revoked: true,
      deniedAt: "2026-05-25T10:00:00.000Z",
      reason: "operator-revoked-stolen-jwt",
    });

    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-jwt-deny",
      userId: "user-A",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // SDK iterator rejects with RuntimeAuthError mid-stream — same
    // surface as a tenant-RPC inside a tool call discovering the JWT
    // landed on the deny-list between mint and use.
    mock.emitError(
      new RuntimeAuthError("denied_jti", "JWT jti denied at runtime"),
    );
    await flushMicrotasks(20);

    const ends = events._ended;
    expect(ends).toHaveLength(1);
    expect(ends[0]).toEqual({
      status: "session_revoked",
      reason: "operator-revoked-stolen-jwt",
      deniedAt: "2026-05-25T10:00:00.000Z",
    });
    expect(mockGetMyRevocationStatus).toHaveBeenCalledWith("user-A");
  });

  it("denied_jti with null status (legacy deny row / RPC failure) → reason+deniedAt null", async () => {
    mockGetMyRevocationStatus.mockResolvedValue(null);

    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-jwt-deny-null",
      userId: "user-B",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });
    mock.emitError(
      new RuntimeAuthError("denied_jti", "JWT jti denied at runtime"),
    );
    await flushMicrotasks(20);

    expect(events._ended).toEqual([
      { status: "session_revoked", reason: null, deniedAt: null },
    ]);
  });

  it("non-denied_jti RuntimeAuthError (jwt_mint) → still routes through internal_error", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-mint-fail",
      userId: "user-C",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });
    mock.emitError(new RuntimeAuthError("jwt_mint", "mint rate-limited"));
    await flushMicrotasks(20);

    expect(events._ended).toHaveLength(1);
    expect(events._ended[0]?.status).toBe("internal_error");
    // No revocation status lookup performed — we only fire that RPC on
    // the deny-list branch (avoid the ~750ms p95 cost on transient
    // mint failures that retry on the next turn).
    expect(mockGetMyRevocationStatus).not.toHaveBeenCalled();
  });

  it("generic Error (non-RuntimeAuthError) → still routes through internal_error", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-generic",
      userId: "user-D",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });
    mock.emitError(new Error("SDK connection reset"));
    await flushMicrotasks(20);

    expect(events._ended).toHaveLength(1);
    expect(events._ended[0]?.status).toBe("internal_error");
    expect(mockGetMyRevocationStatus).not.toHaveBeenCalled();
  });
});
