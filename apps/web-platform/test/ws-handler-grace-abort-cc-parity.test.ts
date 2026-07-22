/**
 * #5356 — ws-handler disconnect grace abort signals BOTH lineages (RED).
 *
 * Plan: knowledge-base/project/plans/2026-06-15-feat-cc-soleur-go-checkpoint-parity-plan.md
 *
 * AC6/T6: the disconnect grace timer must signal the LEGACY path
 * (`abortSession`) AND the cc-soleur-go path
 * (`closeCcConversation(convId, "disconnected")`). The grace-timer body is
 * extracted into the exported `runDisconnectGraceAbort(uid, convId)` so the
 * dual-signal wiring is unit-testable without a live WebSocket. Both calls are
 * idempotent no-ops for the path that does not own the conversation; the
 * registries are mutually exclusive so this never double-checkpoints.
 *
 * RED before GREEN per AGENTS.md `cq-write-failing-tests-before`.
 */
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, it, expect, vi, beforeEach } from "vitest";

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
// Full-mock cc-dispatcher: enumerate the exact names ws-handler imports so the
// binding `closeCcConversation` resolves to our spy (a direct-binding call
// cannot be intercepted by vi.spyOn on the real module).
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

describe("#5356 ws-handler grace abort — dual-path terminal", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("T6: signals BOTH abortSession (legacy) and closeCcConversation (cc) with disconnected", () => {
    const clearSpy = vi
      .spyOn(streamReplayBuffer, "clear")
      .mockImplementation(() => {});

    runDisconnectGraceAbort("u-1", "conv-1");

    expect(mockAbortSession).toHaveBeenCalledWith("u-1", "conv-1");
    expect(mockCloseCcConversation).toHaveBeenCalledWith("conv-1", "disconnected");
    // Existing #5273 behavior preserved: replay buffer is cleared.
    expect(clearSpy).toHaveBeenCalledWith("conv-1");

    clearSpy.mockRestore();
  });
});
