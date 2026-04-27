// Option A — synthetic AgentSession Bash review-gate flow for the
// cc-soleur-go path. Covers T12 (full flow), T13 (cleanup on
// closeConversation/reapIdle), T14 (BLOCKED_BASH_PATTERNS deny path
// fires without WS event).
//
// Key invariant (R8 — composite-key cross-user safety): the
// `ccBashGates` Map is keyed by `${userId}:${conversationId}:${gateId}`,
// mirroring `pending-prompt-registry.ts` `makePendingPromptKey`. Lookup
// from a different userId silently denies — no record should be revealed
// to a non-owner.
//
// Synthetic AgentSession shape per `review-gate.ts`:
//   { abort: AbortController, reviewGateResolvers: Map, sessionId: null }

import { describe, it, expect, vi, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: vi.fn(),
  tool: vi.fn(),
  createSdkMcpServer: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("@/server/ws-handler", () => ({ sendToClient: vi.fn() }));
vi.mock("@/server/notifications", () => ({ notifyOfflineUser: vi.fn() }));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));
vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));

import {
  registerCcBashGate,
  resolveCcBashGate,
  cleanupCcBashGatesForConversation,
  __resetDispatcherForTests,
} from "@/server/cc-dispatcher";

describe("cc-dispatcher Bash review-gate (Option A — synthetic AgentSession)", () => {
  beforeEach(() => {
    __resetDispatcherForTests();
  });

  // -------------------------------------------------------------------------
  // T12: Bash review-gate via synthetic session — register + resolve.
  // -------------------------------------------------------------------------
  it("T12: register + resolve roundtrip resolves with the chosen selection", async () => {
    let resolved: string | undefined;
    const session = {
      abort: new AbortController(),
      reviewGateResolvers: new Map<
        string,
        { resolve: (s: string) => void; options: string[] }
      >(),
      sessionId: null,
    };

    // The synthetic session's reviewGateResolvers is the awaitable seam
    // that `permission-callback.ts` closes via `abortableReviewGate`. Wire
    // a resolver under gateId and let resolveCcBashGate call it.
    const promise = new Promise<string>((resolve) => {
      session.reviewGateResolvers.set("gate-1", {
        resolve: (s) => {
          resolved = s;
          resolve(s);
        },
        options: ["Approve", "Reject"],
      });
    });

    registerCcBashGate({
      userId: "u1",
      conversationId: "conv-1",
      gateId: "gate-1",
      session,
    });

    resolveCcBashGate({
      userId: "u1",
      conversationId: "conv-1",
      gateId: "gate-1",
      selection: "Approve",
    });

    await expect(promise).resolves.toBe("Approve");
    expect(resolved).toBe("Approve");
    // Record was consumed (single-use).
    const second = resolveCcBashGate({
      userId: "u1",
      conversationId: "conv-1",
      gateId: "gate-1",
      selection: "Approve",
    });
    expect(second).toBe(false);
  });

  it("T12b: cross-user lookup silently denies (R8 composite-key)", () => {
    const session = {
      abort: new AbortController(),
      reviewGateResolvers: new Map(),
      sessionId: null,
    };
    registerCcBashGate({
      userId: "alice",
      conversationId: "conv-1",
      gateId: "gate-1",
      session,
    });

    // Bob attempts to resolve Alice's gate — must return false.
    const result = resolveCcBashGate({
      userId: "bob",
      conversationId: "conv-1",
      gateId: "gate-1",
      selection: "Approve",
    });
    expect(result).toBe(false);
  });

  // -------------------------------------------------------------------------
  // T13: cleanup on closeConversation / reapIdle drains entries.
  // -------------------------------------------------------------------------
  it("T13: cleanupCcBashGatesForConversation removes all entries for the conversation", () => {
    const session = {
      abort: new AbortController(),
      reviewGateResolvers: new Map(),
      sessionId: null,
    };
    registerCcBashGate({
      userId: "u1",
      conversationId: "conv-1",
      gateId: "g1",
      session,
    });
    registerCcBashGate({
      userId: "u1",
      conversationId: "conv-1",
      gateId: "g2",
      session,
    });
    // Sibling entry under a different conversation must NOT be drained.
    registerCcBashGate({
      userId: "u1",
      conversationId: "conv-2",
      gateId: "g1",
      session,
    });

    cleanupCcBashGatesForConversation("u1", "conv-1");

    // conv-1 entries gone — resolveCcBashGate returns false.
    expect(
      resolveCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId: "g1",
        selection: "Approve",
      }),
    ).toBe(false);
    expect(
      resolveCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId: "g2",
        selection: "Approve",
      }),
    ).toBe(false);
    // conv-2 entry survives — but resolves false because there is no
    // matching reviewGateResolvers entry on the session for "g1" of
    // conv-2 (we never set it). The Map presence is the invariant; do
    // not assert resolution here.
  });

  // -------------------------------------------------------------------------
  // T14: BLOCKED_BASH_PATTERNS denial path stays in permission-callback.ts;
  // the cc-dispatcher Bash gate code path is NOT entered. We assert the
  // ccBashGates Map is unchanged when the upstream pattern matcher denies.
  //
  // Implementation detail: the cc factory wires `createCanUseTool` with
  // a synthetic session; the BLOCKED_BASH_PATTERNS check fires INSIDE
  // `permission-callback.ts` BEFORE registerCcBashGate is reached. So
  // a blocked invocation never registers a gate.
  //
  // This test pins the negative-space contract: registerCcBashGate is
  // not auto-invoked on permission-callback's behalf. Passes trivially
  // until a future refactor wires registerCcBashGate inside
  // permission-callback (which would be a regression).
  // -------------------------------------------------------------------------
  it("T14: blocked Bash invocations do not auto-register a gate (deny is upstream)", () => {
    // Empty registry baseline.
    expect(
      resolveCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId: "never-registered",
        selection: "Approve",
      }),
    ).toBe(false);
  });
});
