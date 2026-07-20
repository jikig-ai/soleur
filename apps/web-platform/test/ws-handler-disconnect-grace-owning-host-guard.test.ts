/**
 * TR2 host-local owning-host guard — multi-host /workspaces epic #5274 Phase 1.
 *
 * Plan: knowledge-base/project/plans/2026-06-30-feat-multi-host-workspaces-phase-1-host-local-correctness-plan.md
 * ADR-068 §5.
 *
 * `runDisconnectGraceAbort(uid, convId)` must NOT abort when a live local OPEN
 * socket for the user is registered — that is the state of a reconnect that has
 * run `sessions.set` (in the auth/connect handler) but not yet its
 * `pendingDisconnects`-cancel loop (which sits behind three awaited
 * workspace-bind DB calls). Without the guard, a 30s grace timer expiring inside
 * that await window aborts a just-reconnected live turn (the #5240 "my work
 * vanished" regression) AT replicas=1. The guard only ever SUPPRESSES an abort
 * when a live OPEN socket exists; a missing or non-OPEN (CLOSED/CLOSING) socket
 * still aborts.
 *
 * Mirrors the harness in `ws-handler-grace-abort-cc-parity.test.ts` (which
 * drives `runDisconnectGraceAbort` directly, bypassing the timer) and adds
 * control over the real module-level `sessions` map. RED before GREEN per
 * AGENTS.md `cq-write-failing-tests-before`.
 */
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { WebSocket } from "ws";

const { mockAbortSession, mockCloseCcConversation } = vi.hoisted(() => ({
  mockAbortSession: vi.fn(),
  mockCloseCcConversation: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ from: vi.fn(), auth: { getUser: vi.fn() } }),
  serverUrl: "https://test.supabase.co",
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: vi.fn() })),
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
  abortSession: mockAbortSession,
}));
vi.mock("../server/concurrency", () => ({
  // ws-handler/agent-runner import these liveness consts from ./concurrency;
  // a wholesale mock must re-export them or accessing the binding throws.
  SLOT_STALENESS_THRESHOLD_SECONDS: 240,
  SLOT_HEARTBEAT_INTERVAL_MS: 60_000,
  releaseSlot: vi.fn(),
  acquireSlot: vi.fn(),
  touchSlot: vi.fn(),
  emitConcurrencyCapHit: vi.fn(),
}));
vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));
vi.mock("../server/cc-dispatcher", () => ({
  dispatchSoleurGo: vi.fn(),
  getCcStartSessionRateLimiter: vi.fn(),
  handleInteractivePromptResponseCase: vi.fn(),
  hasActiveCcQuery: vi.fn(),
  resolveCcBashGate: vi.fn(),
  drainAutonomousDisclosureGates: vi.fn(),
  markConversationAcked: vi.fn(),
  resolveConciergeDocumentContext: vi.fn(),
  closeCcConversation: mockCloseCcConversation,
}));

import { runDisconnectGraceAbort } from "../server/ws-handler";
import { streamReplayBuffer } from "../server/stream-replay-buffer";
import { sessions } from "../server/session-registry";

const UID = "u-guard-1";
const CONV = "conv-guard-1";

/** Seed the real module-level `sessions` map with a fake ClientSession whose
 *  socket has the given readyState (only `ws.readyState` is read by the guard). */
function seedSession(readyState: number): void {
  sessions.set(UID, { ws: { readyState } } as never);
}

describe("ws-handler runDisconnectGraceAbort — host-local owning-host guard (#5274 Phase 1)", () => {
  let clearSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.clearAllMocks();
    clearSpy = vi
      .spyOn(streamReplayBuffer, "clear")
      .mockImplementation(() => {});
  });

  afterEach(() => {
    // Intra-file hygiene: clear the seeded entry so the next test here (the
    // "no local session" case) sees `sessions.get(UID)` undefined. vitest
    // `isolate: true` already prevents cross-file bleed; this only matters
    // between the three tests in this file.
    sessions.delete(UID);
    clearSpy.mockRestore();
  });

  it("guard FIRES: a live OPEN local socket (race-window state) suppresses the abort", () => {
    seedSession(WebSocket.OPEN);

    runDisconnectGraceAbort(UID, CONV);

    expect(mockAbortSession).not.toHaveBeenCalled();
    expect(mockCloseCcConversation).not.toHaveBeenCalled();
    expect(clearSpy).not.toHaveBeenCalled();
  });

  it("guard PASSES: no local session → abort fires (no reconnect happened)", () => {
    runDisconnectGraceAbort(UID, CONV);

    expect(mockAbortSession).toHaveBeenCalledWith(UID, CONV);
    expect(mockCloseCcConversation).toHaveBeenCalledWith(CONV, "disconnected");
    expect(clearSpy).toHaveBeenCalledWith(CONV);
  });

  it("guard PASSES: a non-OPEN (CLOSED) socket → abort fires (pins the readyState===OPEN check)", () => {
    seedSession(WebSocket.CLOSED);

    runDisconnectGraceAbort(UID, CONV);

    expect(mockAbortSession).toHaveBeenCalledWith(UID, CONV);
    expect(mockCloseCcConversation).toHaveBeenCalledWith(CONV, "disconnected");
    expect(clearSpy).toHaveBeenCalledWith(CONV);
  });
});
