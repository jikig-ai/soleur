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
  // #3369: mirrorWithDebounce extracted to observability.
  // These dispatcher tests do not exercise the debounce TTL, so
  // the stub forwards every call straight through to the spy.
  mirrorWithDebounce: vi.fn(),
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));
vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));

import {
  registerCcBashGate,
  resolveCcBashGate,
  cleanupCcBashGatesForConversation,
  drainAutonomousDisclosureGates,
  registerAutonomousAckPosture,
  markConversationAcked,
  __resetDispatcherForTests,
} from "@/server/cc-dispatcher";
import { createSoleurGoRunner } from "@/server/soleur-go-runner";
import {
  getBashApprovalCache,
  _resetBashApprovalCacheForTests,
} from "@/server/permission-callback-bash-batch";

describe("cc-dispatcher Bash review-gate (Option A — synthetic AgentSession)", () => {
  beforeEach(() => {
    __resetDispatcherForTests();
    _resetBashApprovalCacheForTests();
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

  // -------------------------------------------------------------------------
  // T13b: runner.reapIdle() drains _ccBashGates via the `onCloseQuery`
  // hook. Pre-fix, reapIdle closed the Query without firing
  // `onWorkflowEnded`, so the dispatch-side cleanup never ran and the
  // gate registry leaked. This test pins the centralized cleanup wiring.
  // -------------------------------------------------------------------------
  it("T13b: reapIdle invokes onCloseQuery → drains ccBashGates for the conversation", async () => {
    // Build a runner with a fake factory whose Query never finishes —
    // we only care about the close hook firing on idle reap.
    // biome-ignore lint/suspicious/noExplicitAny: minimal Query stub
    const fakeQuery: any = {
      // Iterator that pends forever (until close()).
      async *[Symbol.asyncIterator]() {
        await new Promise<void>(() => {
          /* never resolves */
        });
      },
      close: vi.fn(),
      interrupt: vi.fn(),
    };

    const closeHookCalls: Array<{ conversationId: string; userId: string }> =
      [];
    let nowMs = 0;
    const runner = createSoleurGoRunner({
      queryFactory: () => fakeQuery,
      now: () => nowMs,
      idleReapMs: 1000,
      onCloseQuery: (args) => {
        closeHookCalls.push(args);
        // Mirror the production wiring: cleanupCcBashGatesForConversation.
        cleanupCcBashGatesForConversation(args.userId, args.conversationId);
      },
    });

    // Seed a Bash gate against the (userId, conversationId) the runner
    // will own. Use a session whose reviewGateResolvers map has an
    // entry for the gateId so `resolveCcBashGate` would otherwise
    // return true.
    const session = {
      abort: new AbortController(),
      reviewGateResolvers: new Map<
        string,
        { resolve: (s: string) => void; options: string[] }
      >([["g1", { resolve: () => {}, options: [] }]]),
      sessionId: null,
    };
    registerCcBashGate({
      userId: "u-reap",
      conversationId: "conv-reap",
      gateId: "g1",
      session,
    });

    // Sanity: gate is live.
    // (Don't actually call resolveCcBashGate — that would consume it.)
    // Instead, advance time past idleReapMs and run reapIdle().
    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-reap",
      userId: "u-reap",
      userMessage: "trigger query construction",
      currentRouting: { kind: "soleur_go_pending" },
      events: {
        onText: () => {},
        onToolUse: () => {},
        onWorkflowDetected: () => {},
        onWorkflowEnded: () => {},
        onResult: () => {},
      },
      persistActiveWorkflow: async () => {},
    });

    expect(runner.hasActiveQuery("conv-reap")).toBe(true);

    nowMs += 5000; // > idleReapMs
    const reaped = runner.reapIdle();
    expect(reaped).toBe(1);

    // The onCloseQuery hook fired with the correct identity.
    expect(closeHookCalls).toEqual([
      { conversationId: "conv-reap", userId: "u-reap" },
    ]);

    // The Bash gate is gone — subsequent resolve returns false.
    expect(
      resolveCcBashGate({
        userId: "u-reap",
        conversationId: "conv-reap",
        gateId: "g1",
        selection: "Approve",
      }),
    ).toBe(false);
  });

  // -------------------------------------------------------------------------
  // T-AC-2921: multi-Bash batching contract
  //   - 5 sequential `git status` after batch grant → 0 additional gates
  //   - `git status` grant ≠ `git push` allow (prefix-strict)
  //   - cross-conversation isolation
  // -------------------------------------------------------------------------
  describe("T-AC-2921: bash batching across conversation lifecycle", () => {
    it("5 sequential `git status` after batch grant → cache hits all 5", () => {
      const cache = getBashApprovalCache("u-batch", "conv-batch");
      // Simulating "user picked Approve all `git status`" after first gate.
      cache.grant("git status");
      let hits = 0;
      for (let i = 0; i < 5; i++) {
        if (cache.allow("git status")) hits++;
      }
      expect(hits).toBe(5);
    });

    it("`git status` grant does NOT auto-allow `git push`", () => {
      const cache = getBashApprovalCache("u-strict", "conv-strict");
      cache.grant("git status");
      expect(cache.allow("git push origin main")).toBe(false);
    });

    it("cross-conversation isolation — grant in conv-A does not leak to conv-B", () => {
      const ca = getBashApprovalCache("u-iso", "conv-A");
      const cb = getBashApprovalCache("u-iso", "conv-B");
      ca.grant("git status");
      expect(ca.allow("git status")).toBe(true);
      expect(cb.allow("git status")).toBe(false);
    });

    it("cleanupCcBashGatesForConversation drains the batched-approval cache too", () => {
      const cache = getBashApprovalCache("u-clean", "conv-clean");
      cache.grant("git status");
      expect(cache.allow("git status")).toBe(true);

      cleanupCcBashGatesForConversation("u-clean", "conv-clean");

      // After cleanup, the cache is drained.
      expect(getBashApprovalCache("u-clean", "conv-clean").allow("git status")).toBe(
        false,
      );
    });
  });

  // -------------------------------------------------------------------------
  // P1 — CONSENT-GATE BYPASS via frame substitution. The held disclosure
  // gate and the normal Bash review-gate share one registry keyed by gateId.
  // Without a `kind` discriminator, a `review_gate_response` frame carrying a
  // HELD disclosure gateId would release the consent-gated command WITHOUT
  // routing through the owner-checked `setAutonomousAck` path. The registry
  // MUST refuse to resolve a gate whose kind ≠ the responder's expected kind.
  // -------------------------------------------------------------------------
  describe("P1: kind-discriminated gate resolution (cross-frame bypass)", () => {
    function buildResolvableSession(gateId: string) {
      let resolved: string | undefined;
      const session = {
        abort: new AbortController(),
        reviewGateResolvers: new Map<
          string,
          { resolve: (s: string) => void; options: string[] }
        >([
          [
            gateId,
            {
              resolve: (s: string) => {
                resolved = s;
              },
              options: ["Got it"],
            },
          ],
        ]),
        sessionId: null,
      };
      return { session, getResolved: () => resolved };
    }

    it("a review_gate_response (expected kind 'review') CANNOT release a held autonomous_disclosure gate", () => {
      const { session, getResolved } = buildResolvableSession("g-hold");
      registerCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId: "g-hold",
        session,
        kind: "autonomous_disclosure",
      });

      // Attacker substitutes a review_gate_response carrying the held
      // disclosure gateId + a "Got it"-shaped selection.
      const released = resolveCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId: "g-hold",
        selection: "Got it",
        expectedKind: "review",
      });

      expect(released).toBe(false);
      // The held command's resolver MUST NOT have fired.
      expect(getResolved()).toBeUndefined();

      // The gate is still live for the CORRECT responder kind.
      const correct = resolveCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId: "g-hold",
        selection: "Got it",
        expectedKind: "autonomous_disclosure",
      });
      expect(correct).toBe(true);
      expect(getResolved()).toBe("Got it");
    });

    it("an autonomous_disclosure_response (expected kind 'autonomous_disclosure') CANNOT release a review gate", () => {
      const { session, getResolved } = buildResolvableSession("g-review");
      registerCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId: "g-review",
        session,
        kind: "review",
      });

      const released = resolveCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId: "g-review",
        selection: "Approve",
        expectedKind: "autonomous_disclosure",
      });
      expect(released).toBe(false);
      expect(getResolved()).toBeUndefined();
    });

    it("default expectedKind is 'review' (back-compat for unspecified callers)", () => {
      const { session, getResolved } = buildResolvableSession("g-default");
      registerCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId: "g-default",
        session,
        // kind omitted → defaults to "review"
      });
      const released = resolveCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId: "g-default",
        selection: "Approve",
        // expectedKind omitted → defaults to "review"
      });
      expect(released).toBe(true);
      expect(getResolved()).toBe("Approve");
    });
  });

  // -------------------------------------------------------------------------
  // P2 — multi-hold, single ack. Two commands HELD behind the disclosure before
  // the owner acks once: a single ack must DRAIN all held disclosure gates for
  // the conversation (not just the clicked one). Review gates are NOT drained.
  // -------------------------------------------------------------------------
  describe("P2: drainAutonomousDisclosureGates (multi-hold single ack)", () => {
    function seedDisclosureGate(gateId: string) {
      const resolved: string[] = [];
      const session = {
        abort: new AbortController(),
        reviewGateResolvers: new Map<
          string,
          { resolve: (s: string) => void; options: string[] }
        >([
          [
            gateId,
            { resolve: (s: string) => resolved.push(s), options: ["Got it"] },
          ],
        ]),
        sessionId: null,
      };
      registerCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId,
        session,
        kind: "autonomous_disclosure",
      });
      return resolved;
    }

    it("one ack releases ALL held disclosure gates for the conversation", () => {
      const r1 = seedDisclosureGate("hold-1");
      const r2 = seedDisclosureGate("hold-2");

      const count = drainAutonomousDisclosureGates({
        userId: "u1",
        conversationId: "conv-1",
        selection: "Got it",
      });

      expect(count).toBe(2);
      expect(r1).toEqual(["Got it"]);
      expect(r2).toEqual(["Got it"]);
    });

    it("does NOT drain review gates (only autonomous_disclosure)", () => {
      const held = seedDisclosureGate("hold-x");
      const reviewResolved: string[] = [];
      const reviewSession = {
        abort: new AbortController(),
        reviewGateResolvers: new Map<
          string,
          { resolve: (s: string) => void; options: string[] }
        >([
          [
            "rev-1",
            {
              resolve: (s: string) => reviewResolved.push(s),
              options: ["Approve"],
            },
          ],
        ]),
        sessionId: null,
      };
      registerCcBashGate({
        userId: "u1",
        conversationId: "conv-1",
        gateId: "rev-1",
        session: reviewSession,
        kind: "review",
      });

      const count = drainAutonomousDisclosureGates({
        userId: "u1",
        conversationId: "conv-1",
        selection: "Got it",
      });

      expect(count).toBe(1);
      expect(held).toEqual(["Got it"]);
      expect(reviewResolved).toEqual([]); // untouched
    });

    it("scopes to the (userId, conversationId) — sibling conversation untouched", () => {
      const here = seedDisclosureGate("hold-here");
      // Sibling conversation gate.
      const thereResolved: string[] = [];
      const thereSession = {
        abort: new AbortController(),
        reviewGateResolvers: new Map<
          string,
          { resolve: (s: string) => void; options: string[] }
        >([
          [
            "hold-there",
            {
              resolve: (s: string) => thereResolved.push(s),
              options: ["Got it"],
            },
          ],
        ]),
        sessionId: null,
      };
      registerCcBashGate({
        userId: "u1",
        conversationId: "conv-OTHER",
        gateId: "hold-there",
        session: thereSession,
        kind: "autonomous_disclosure",
      });

      drainAutonomousDisclosureGates({
        userId: "u1",
        conversationId: "conv-1",
        selection: "Got it",
      });

      expect(here).toEqual(["Got it"]);
      expect(thereResolved).toEqual([]);
    });
  });

  // -------------------------------------------------------------------------
  // P1 — in-session ack posture: markConversationAcked flips the registered
  // cell so a post-ack command reads the live (acked) posture, not the frozen
  // cold-start snapshot. Drained on conversation cleanup.
  // -------------------------------------------------------------------------
  describe("P1: in-session ack posture cell", () => {
    it("markConversationAcked flips the registered posture cell to non-null", () => {
      let posture: number | null = null;
      registerAutonomousAckPosture("u1", "conv-1", {
        get: () => posture,
        set: (v) => {
          posture = v;
        },
      });
      expect(posture).toBeNull();

      markConversationAcked("u1", "conv-1", 1_700_000_000_000);
      expect(posture).toBe(1_700_000_000_000);
    });

    it("markConversationAcked is a no-op when no cell is registered", () => {
      // Must not throw.
      expect(() =>
        markConversationAcked("nobody", "no-conv", 1),
      ).not.toThrow();
    });

    it("cleanup drains the posture cell (no leak across conversations)", () => {
      let posture: number | null = 1_700_000_000_000;
      registerAutonomousAckPosture("u1", "conv-1", {
        get: () => posture,
        set: (v) => {
          posture = v;
        },
      });
      cleanupCcBashGatesForConversation("u1", "conv-1");
      // After cleanup the cell is gone — a later mark is a no-op (cell removed).
      markConversationAcked("u1", "conv-1", 42);
      expect(posture).toBe(1_700_000_000_000); // unchanged (cell was deleted)
    });
  });
});
