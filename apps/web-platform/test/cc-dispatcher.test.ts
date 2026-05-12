import { describe, it, expect, vi, beforeEach } from "vitest";

const {
  mockReportSilentFallback,
  mockFetchUserWorkspacePath,
  mockMessagesInsert,
  mockUpdateConversationFor,
  mockMirrorP0Deduped,
} = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockFetchUserWorkspacePath: vi.fn(),
  mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }),
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
  mockMirrorP0Deduped: vi.fn(),
}));

vi.mock("@/server/conversation-writer", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/conversation-writer")
  >("@/server/conversation-writer");
  return {
    ...actual,
    updateConversationFor: mockUpdateConversationFor,
  };
});

vi.mock("@/server/observability", async () => {
  // Pull the real `mirrorWithDebounce` + `__resetMirrorDebounceForTests`
  // so the existing per-(userId, errorClass) coalescing assertion (3 calls
  // in <5min → 1 mirror) still holds against the spy reportSilentFallback.
  // Stub `reportSilentFallback` so individual call-site mirrors are
  // observable; `mirrorWithDebounce` internally delegates to whatever the
  // module's exported `reportSilentFallback` is, but since the module is
  // mocked the delegation pulls our spy.
  const actual = await vi.importActual<
    typeof import("@/server/observability")
  >("@/server/observability");
  return {
    ...actual,
    reportSilentFallback: mockReportSilentFallback,
    warnSilentFallback: vi.fn(),
    // Override mirrorWithDebounce with a TTL-honoring wrapper that uses
    // the spy as its sink. We can't reuse `actual.mirrorWithDebounce`
    // directly because that one captured the real reportSilentFallback
    // at module-init time (before this mock swap). Pulling the TTL from
    // `actual.MIRROR_DEBOUNCE_MS` keeps the wrapper in lockstep with the
    // production constant — if `MIRROR_DEBOUNCE_MS` ever changes, the
    // 3-call-→-1-mirror assertion in this file will not silently drift.
    mirrorWithDebounce: (() => {
      const lastReportedAt = new Map<string, number>();
      return (err: unknown, ctx: unknown, userId: string, errorClass: string) => {
        const key = `${userId}:${errorClass}`;
        const now = Date.now();
        const last = lastReportedAt.get(key);
        if (last !== undefined && now - last < actual.MIRROR_DEBOUNCE_MS) return;
        lastReportedAt.set(key, now);
        mockReportSilentFallback(err, ctx);
      };
    })(),
    // #3603 W1 — `mirrorP0Deduped` is the cross-tenant / W4-orphan
    // P0 mirror with 1h `(userId, op, conversationId)` dedup. Spying
    // it directly lets W4-orphan tests assert the op slug + ctx shape
    // without exercising the real Sentry path; the real helper's
    // dedup behavior is covered separately in observability tests.
    mirrorP0Deduped: mockMirrorP0Deduped,
  };
});

// Module-scoped: every test in this file gets a mocked
// `fetchUserWorkspacePath`. Existing dispatchSoleurGo tests pre-#3235 do not
// assert on workspace-resolve or tool labels, so the swap is behavior-neutral
// for them. Future tests in this file MUST be aware that a real Supabase
// SELECT is bypassed here — re-add `vi.importActual` if you need the real
// memo / Supabase round-trip semantics.
// #3626 — `onResult` now also calls `persistTurnCost` (cost-writer.ts).
// In test env the helper would attempt a real Supabase write and throw
// synchronously, breaking subsequent SDK callbacks. Stub to a no-op so
// the W4 messages.usage path remains the unit-under-test here. The cost-
// writer aggregation surface has its own dedicated test coverage.
vi.mock("@/server/cost-writer", () => ({
  persistTurnCost: vi.fn(),
}));

vi.mock("@/server/kb-document-resolver", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/kb-document-resolver")
  >("@/server/kb-document-resolver");
  return {
    ...actual,
    fetchUserWorkspacePath: mockFetchUserWorkspacePath,
  };
});

// #3254 — `dispatchSoleurGo` now persists a `messages` row per turn
// (so `message_attachments.message_id` FK can be satisfied for cc-path
// attachments). Stub the service-role client so existing tests that
// don't care about the new insert keep passing without spinning a real
// Supabase up.
vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://test.supabase.co",
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "messages") {
        return { insert: mockMessagesInsert };
      }
      // `conversations` writes go through `updateConversationFor` which is
      // mocked above; service-client should never see a direct .from("conversations").
      throw new Error(`unexpected table in cc-dispatcher.test.ts: ${table}`);
    },
    storage: {
      from: () => ({ download: vi.fn() }),
    },
  }),
}));

import {
  getPendingPromptRegistry,
  getCcStartSessionRateLimiter,
  handleInteractivePromptResponseCase,
  dispatchSoleurGo,
  __resetDispatcherForTests,
  __resetCcPersistUsageObservationForTests,
} from "@/server/cc-dispatcher";
// #3603 W1 plan §2.2.3 — hook P0 dedup reset into the test reset chain so a
// future test that exercises the real `mirrorP0Deduped` (vs. this file's spy
// override) doesn't see state leak from a prior test. No-op against the spy
// override below, but pins the contract.
import { __resetP0DedupForTests } from "@/server/observability";
import type { WSMessage } from "@/lib/types";
import { KeyInvalidError } from "@/lib/types";
import { mintPromptId, mintConversationId } from "@/lib/branded-ids";
type InteractivePromptResponse = Extract<WSMessage, { type: "interactive_prompt_response" }>;

// Unit tests for the per-process singleton + orchestration module. The
// real-SDK queryFactory path is stubbed (throws — runner's own
// reportSilentFallback fires); full E2E dispatch is exercised in
// soleur-go-runner.test.ts + soleur-go-runner-interactive-prompt.test.ts
// against a mock factory. These tests pin the glue: idempotent
// singleton init, rate-limit config, and interactive_prompt_response
// WS-error mapping.

describe("cc-dispatcher singletons + orchestration", () => {
  beforeEach(() => {
    __resetDispatcherForTests();
    __resetP0DedupForTests();
    __resetCcPersistUsageObservationForTests();
    mockReportSilentFallback.mockClear();
    mockFetchUserWorkspacePath.mockReset();
    mockMessagesInsert.mockClear();
    // Default: every messages-insert succeeds; tests that need a failure
    // can override per-call.
    mockMessagesInsert.mockResolvedValue({ error: null });
    mockUpdateConversationFor.mockClear();
    mockUpdateConversationFor.mockResolvedValue({ ok: true });
    mockMirrorP0Deduped.mockClear();
    // #3603 W4 — env state must be deterministic per test. `CC_PERSIST_USAGE`
    // defaults to off (unset) at merge per AC9/AC11; tests that need the
    // flag on stub it explicitly via `vi.stubEnv`.
    vi.unstubAllEnvs();
    // Default: a stable stub workspace path so existing tests that don't
    // care about the workspace-resolve path still get a deterministic value.
    mockFetchUserWorkspacePath.mockResolvedValue("/tmp/claude-XXXX/workspace");
  });

  it("getPendingPromptRegistry returns a stable singleton", () => {
    const a = getPendingPromptRegistry();
    const b = getPendingPromptRegistry();
    expect(a).toBe(b);
  });

  it("getCcStartSessionRateLimiter enforces defaults (10/user/hour)", () => {
    const limiter = getCcStartSessionRateLimiter();
    const decisions: boolean[] = [];
    for (let i = 0; i < 11; i++) {
      decisions.push(limiter.check({ userId: "u1", ip: `ip-${i}` }).allowed);
    }
    // 11th call is denied (cap=10).
    expect(decisions.slice(0, 10).every(Boolean)).toBe(true);
    expect(decisions[10]).toBe(false);
  });

  it("handleInteractivePromptResponseCase emits structured WS error on not_found", () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const payload: InteractivePromptResponse = {
      type: "interactive_prompt_response",
      promptId: "nope",
      conversationId: "conv",
      kind: "ask_user",
      response: "A",
    };
    const result = handleInteractivePromptResponseCase({
      userId: "u1",
      payload,
      sendToClient,
    });
    expect(result.ok).toBe(false);
    // The ws-handler must have been instructed to emit a structured error.
    // It may also be invoked with emitInteractivePrompt on other paths;
    // check that at least one call carries the error shape.
    const errorCalls = sendToClient.mock.calls.filter(
      ([, msg]) => msg && typeof msg === "object" && (msg as { type?: string }).type === "error",
    );
    expect(errorCalls.length).toBeGreaterThan(0);
    expect((errorCalls[0]![1] as { message: string }).message).toContain("not_found");
  });

  it("handleInteractivePromptResponseCase delivers on success (registers + consumes + invokes runner.respondToToolUse)", () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const registry = getPendingPromptRegistry();
    registry.register({
      promptId: mintPromptId("p-1"),
      conversationId: mintConversationId("conv-1"),
      userId: "u1",
      kind: "plan_preview",
      toolUseId: "toolu_1",
      createdAt: Date.now(),
      payload: {},
    });

    const result = handleInteractivePromptResponseCase({
      userId: "u1",
      payload: {
        type: "interactive_prompt_response",
        promptId: "p-1",
        conversationId: "conv-1",
        kind: "plan_preview",
        response: "accept",
      },
      sendToClient,
    });

    expect(result.ok).toBe(true);
    // Record consumed.
    expect(registry.size()).toBe(0);
    // No error emission on success.
    const errorCalls = sendToClient.mock.calls.filter(
      ([, msg]) => msg && typeof msg === "object" && (msg as { type?: string }).type === "error",
    );
    expect(errorCalls).toHaveLength(0);
  });

  it.each([
    ["already_consumed", "plan_preview", "accept"],
    ["kind_mismatch", "bash_approval", "approve"],
    ["invalid_response", "plan_preview", "something-not-accept"],
    ["invalid_payload", "plan_preview", "accept"],
  ] as const)(
    "handleInteractivePromptResponseCase emits errorCode on %s",
    (expectedError, payloadKind, response) => {
      const sendToClient = vi.fn().mockReturnValue(true);
      const registry = getPendingPromptRegistry();
      // Seed record for the cases that need a live prompt.
      if (expectedError !== "invalid_payload") {
        registry.register({
          promptId: mintPromptId("p-1"),
          conversationId: mintConversationId("conv-1"),
          userId: "u1",
          kind: "plan_preview", // record kind pinned
          toolUseId: "toolu_1",
          createdAt: Date.now(),
          payload: {},
        });
      }
      // For already_consumed, consume first.
      if (expectedError === "already_consumed") {
        handleInteractivePromptResponseCase({
          userId: "u1",
          payload: {
            type: "interactive_prompt_response",
            promptId: "p-1",
            conversationId: "conv-1",
            kind: "plan_preview",
            response: "accept",
          },
          sendToClient: vi.fn().mockReturnValue(true),
        });
      }

      const payload =
        expectedError === "invalid_payload"
          ? ({ type: "interactive_prompt_response" } as unknown as InteractivePromptResponse)
          : ({
              type: "interactive_prompt_response",
              promptId: "p-1",
              conversationId: "conv-1",
              kind: payloadKind,
              response,
            } as unknown as InteractivePromptResponse);

      const result = handleInteractivePromptResponseCase({
        userId: "u1",
        payload,
        sendToClient,
      });

      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error).toBe(expectedError);

      const errorCalls = sendToClient.mock.calls.filter(
        ([, m]) => m && typeof m === "object" && (m as { type?: string }).type === "error",
      );
      expect(errorCalls.length).toBeGreaterThan(0);
      expect((errorCalls[0]![1] as { errorCode?: string }).errorCode).toBe(
        "interactive_prompt_rejected",
      );
    },
  );

  // ---------------------------------------------------------------------------
  // T19: KeyInvalidError sanitization to client + errorCode propagation.
  // The dispatch catch path detects `KeyInvalidError` (BYOK fetch) and
  // surfaces `errorCode: "key_invalid"` so the client can prompt for a
  // fresh key. Generic errors fall back to the existing "router unavailable"
  // wording without an errorCode.
  // ---------------------------------------------------------------------------
  it("dispatchSoleurGo forwards runner_runaway diagnostics over WS error event (#3225)", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");
    const stubRunner = {
      dispatch: vi.fn(async (args: { events: { onWorkflowEnded: (end: unknown) => void } }) => {
        // Drive a runner_runaway WorkflowEnd through the dispatcher's
        // onWorkflowEnded handler so we can verify wire forwarding.
        args.events.onWorkflowEnded({
          status: "runner_runaway",
          elapsedMs: 92_500,
          lastBlockKind: "tool_use",
          lastBlockToolName: "Read",
          reason: "idle_window",
        });
      }),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo({
      userId: "u1",
      conversationId: "conv-runaway",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
    });

    const errorCalls = sendToClient.mock.calls.filter(
      ([, msg]) =>
        msg && typeof msg === "object" && (msg as { type?: string }).type === "error",
    );
    expect(errorCalls.length).toBeGreaterThan(0);
    const errMsg = errorCalls[0][1] as {
      type: string;
      message: string;
      runnerRunawayReason?: string;
      runnerRunawayLastBlockKind?: string | null;
      runnerRunawayLastBlockToolName?: string | null;
    };
    // Static user-facing copy preserved.
    expect(errMsg.message).toContain("agent went idle");
    // New diagnostic forwarding — agent-user observability parity.
    expect(errMsg.runnerRunawayReason).toBe("idle_window");
    expect(errMsg.runnerRunawayLastBlockKind).toBe("tool_use");
    expect(errMsg.runnerRunawayLastBlockToolName).toBe("Read");
  });

  it("T19: dispatchSoleurGo surfaces errorCode=key_invalid when runner throws KeyInvalidError", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    // The first dispatch will create a runner; we want the runner to throw
    // KeyInvalidError synchronously when calling queryFactory. The runner
    // captured the real factory at construction; we override by injecting
    // a known-throwing factory via __resetDispatcherForTests + a follow-up
    // stub. Since the real factory hits Supabase, the simplest seam is:
    // call dispatch with a malformed routing that triggers the catch.
    //
    // Practically, we simulate the failure by passing a routing that the
    // runner will eventually run through queryFactory — and rely on the
    // dispatch catch to detect KeyInvalidError. To do that, we mock the
    // factory thrown shape via the underlying runner singleton.
    //
    // Since cc-dispatcher.ts wires its own factory (real or stub), the
    // cleanest E2E here is: feed a KeyInvalidError into the catch path
    // by having the runner.dispatch reject. We achieve this by replacing
    // the runner with a stub that rejects.
    //
    // Use the test-only seam to swap in a stub runner.
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");
    const stubRunner = {
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
      dispatch: vi.fn(async () => {
        throw new KeyInvalidError();
      }),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo({
      userId: "u1",
      conversationId: "conv-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
    });

    const errorCalls = sendToClient.mock.calls.filter(
      ([, msg]) =>
        msg && typeof msg === "object" && (msg as { type?: string }).type === "error",
    );
    expect(errorCalls.length).toBeGreaterThan(0);
    const errMsg = errorCalls[0][1] as { errorCode?: string; message?: string };
    expect(errMsg.errorCode).toBe("key_invalid");
    // Message must not leak raw stack / class internals.
    expect(errMsg.message).not.toContain("KeyInvalidError");
    expect(errMsg.message).not.toContain("at ");
  });

  // ---------------------------------------------------------------------------
  // Sentry mirror debounce — second call within 5-min window does NOT
  // re-mirror the same (userId, errorClass) combo. Prevents the
  // misconfigured-prod scenario where 1 QPS = 86k Sentry events/day.
  // ---------------------------------------------------------------------------
  it("Sentry mirror is debounced per (userId, errorClass) within 5-minute window", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");
    const stubRunner = {
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
      dispatch: vi.fn(async () => {
        throw new KeyInvalidError();
      }),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    const baseArgs = {
      userId: "u-debounce",
      conversationId: "conv-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" } as const,
      sendToClient,
      persistActiveWorkflow,
    };

    await dispatchSoleurGo(baseArgs);
    await dispatchSoleurGo(baseArgs);
    await dispatchSoleurGo(baseArgs);

    // Mirror fires once for (u-debounce, KeyInvalidError); subsequent
    // calls within the 5-min window are dropped.
    const dispatchMirrors = mockReportSilentFallback.mock.calls.filter(
      ([, ctx]) =>
        ctx?.feature === "cc-dispatcher" && ctx?.op === "dispatch",
    );
    expect(dispatchMirrors).toHaveLength(1);

    // The client still sees an error EVERY time — only the Sentry write
    // is debounced.
    const errorCalls = sendToClient.mock.calls.filter(
      ([, msg]) =>
        msg && typeof msg === "object" && (msg as { type?: string }).type === "error",
    );
    expect(errorCalls).toHaveLength(3);
    for (const call of errorCalls) {
      expect((call[1] as { errorCode?: string }).errorCode).toBe("key_invalid");
    }
  });

  it("Sentry mirror debounces independently for distinct (userId, errorClass) keys", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    // First user fails with KeyInvalidError.
    __setCcRunnerForTests({
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
      dispatch: vi.fn(async () => {
        throw new KeyInvalidError();
      }),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any);

    await dispatchSoleurGo({
      userId: "u-A",
      conversationId: "conv-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
    });

    await dispatchSoleurGo({
      userId: "u-B",
      conversationId: "conv-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
    });

    // Both users got mirrored — debounce key is per-user.
    const dispatchMirrors = mockReportSilentFallback.mock.calls.filter(
      ([, ctx]) =>
        ctx?.feature === "cc-dispatcher" && ctx?.op === "dispatch",
    );
    expect(dispatchMirrors).toHaveLength(2);
  });

  // ---------------------------------------------------------------------------
  // KB Concierge bug fixes:
  //  - artifactPath / documentKind / documentContent are forwarded to
  //    `runner.dispatch` so the system prompt injects document context
  //    (regression: PR #2901 cutover dropped this on the soleur-go path).
  //  - dispatchSoleurGo wires `events.onTextTurnEnd` to emit a `stream_end`
  //    WS event for `cc_router` so the bubble transitions out of
  //    "streaming" and the MarkdownRenderer engages.
  // ---------------------------------------------------------------------------
  it("KB Concierge: forwards artifactPath + documentKind + documentContent to runner.dispatch", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");
    const dispatchSpy = vi.fn(async (_args: unknown) => ({ queryReused: false }));
    const stubRunner = {
      dispatch: dispatchSpy,
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    await dispatchSoleurGo({
      userId: "u-kb",
      conversationId: "conv-kb",
      userMessage: "summarize this document",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
      artifactPath: "knowledge-base/foo.pdf",
      documentKind: "pdf",
    });

    expect(dispatchSpy).toHaveBeenCalledTimes(1);
    const arg = dispatchSpy.mock.calls[0][0] as {
      artifactPath?: string;
      documentKind?: string;
      documentContent?: string;
    };
    expect(arg.artifactPath).toBe("knowledge-base/foo.pdf");
    expect(arg.documentKind).toBe("pdf");
  });

  it("KB Concierge: forwards documentExtractError to runner.dispatch (Hypothesis A regression — PR #3353)", async () => {
    // Pin the end-to-end thread: when ws-handler resolves
    // `{ documentExtractError: <class> }` and spreads it into
    // `dispatchSoleurGo`, the dispatcher MUST forward the field to
    // `runner.dispatch`. Without this pin a future refactor that
    // explicitly enumerates fields (instead of `...documentArgs`) would
    // silently drop the extractor failure class and re-introduce the
    // apt-get cascade — the bug PR #3353 closes.
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");
    const dispatchSpy = vi.fn(async (_args: unknown) => ({ queryReused: false }));
    const stubRunner = {
      dispatch: dispatchSpy,
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    await dispatchSoleurGo({
      userId: "u-extract-err",
      conversationId: "conv-extract-err",
      userMessage: "summarize this document",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
      artifactPath: "knowledge-base/scanned.pdf",
      documentKind: "pdf",
      documentExtractError: "empty_text",
    });

    expect(dispatchSpy).toHaveBeenCalledTimes(1);
    const arg = dispatchSpy.mock.calls[0][0] as {
      documentExtractError?: string;
    };
    expect(arg.documentExtractError).toBe("empty_text");
  });

  it("KB Concierge: forwards documentExtractMeta to runner.dispatch (#3429 wire-drop regression — caught by user-impact-reviewer on PR #3430)", async () => {
    // Pin the resolver→dispatcher→runner thread for the page-count gate's
    // numPages payload. Pre-fix, dispatchSoleurGo destructured fields
    // explicitly and forgot `documentExtractMeta`, so even though the
    // resolver populated `{ numPages: 403 }`, the runner saw `undefined`
    // and the user-facing copy fell back to "I see 0 pages". This test
    // pins the field's survival across the dispatcher hop so a future
    // field addition can't silently re-introduce the same defect class.
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");
    const dispatchSpy = vi.fn(async (_args: unknown) => ({ queryReused: false }));
    const stubRunner = {
      dispatch: dispatchSpy,
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    await dispatchSoleurGo({
      userId: "u-meta",
      conversationId: "conv-meta",
      userMessage: "summarize this document",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
      artifactPath: "knowledge-base/big-book.pdf",
      documentKind: "pdf",
      documentExtractError: "too_many_pages",
      documentExtractMeta: { numPages: 403 },
    });

    expect(dispatchSpy).toHaveBeenCalledTimes(1);
    const arg = dispatchSpy.mock.calls[0][0] as {
      documentExtractError?: string;
      documentExtractMeta?: { numPages?: number };
    };
    expect(arg.documentExtractError).toBe("too_many_pages");
    expect(arg.documentExtractMeta).toEqual({ numPages: 403 });
  });

  it("KB Concierge: emits stream_end{leaderId:cc_router} when runner fires events.onTextTurnEnd", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");
    const stubRunner = {
      dispatch: vi.fn(async (args: { events: { onTextTurnEnd?: () => void } }) => {
        // Simulate the runner emitting a turn-boundary signal.
        args.events.onTextTurnEnd?.();
        return { queryReused: false };
      }),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    await dispatchSoleurGo({
      userId: "u-streamend",
      conversationId: "conv-streamend",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
    });

    const streamEndCalls = sendToClient.mock.calls.filter(
      ([, msg]) =>
        msg && typeof msg === "object" && (msg as { type?: string }).type === "stream_end",
    );
    expect(streamEndCalls.length).toBe(1);
    const frame = streamEndCalls[0][1] as {
      type: string;
      leaderId?: string;
    };
    expect(frame.leaderId).toBe("cc_router");
  });

  it("T19b: dispatchSoleurGo surfaces generic message (no errorCode) for unrelated errors", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");
    const stubRunner = {
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
      dispatch: vi.fn(async () => {
        throw new Error("some generic upstream failure");
      }),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo({
      userId: "u1",
      conversationId: "conv-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
    });

    const errorCalls = sendToClient.mock.calls.filter(
      ([, msg]) =>
        msg && typeof msg === "object" && (msg as { type?: string }).type === "error",
    );
    expect(errorCalls.length).toBeGreaterThan(0);
    const errMsg = errorCalls[0][1] as { errorCode?: string; message?: string };
    expect(errMsg.errorCode).toBeUndefined();
    expect(errMsg.message).toContain("Dashboard router is unavailable");
  });

  // ---------------------------------------------------------------------------
  // WORKFLOW_END_USER_MESSAGES — typed exhaustive map replaces the prior
  // `Workflow ended (${status}) — retry to continue.` template that
  // leaked the internal status enum to users. Compile-time enforcement is
  // via `Record<WorkflowEndStatus, string>`; this test pins a runtime
  // snapshot + verifies every variant has an entry.
  // ---------------------------------------------------------------------------
  it("WORKFLOW_END_USER_MESSAGES has an entry for every WorkflowEndStatus variant", async () => {
    const { WORKFLOW_END_USER_MESSAGES } = await import(
      "@/server/cc-dispatcher"
    );
    // Variants from the runner's WorkflowEnd union.
    const expectedKeys: ReadonlyArray<string> = [
      "completed",
      "cost_ceiling",
      "runner_runaway",
      "user_aborted",
      "idle_timeout",
      "plugin_load_failure",
      "internal_error",
    ];
    const actualKeys = Object.keys(WORKFLOW_END_USER_MESSAGES).sort();
    expect(actualKeys).toEqual([...expectedKeys].sort());

    // `completed` is intentionally empty — that path is handled via the
    // terminal `session_ended` WS event and never produces a user-facing
    // error message.
    expect(WORKFLOW_END_USER_MESSAGES.completed).toBe("");

    // Recoverable branches must surface user-friendly copy without
    // leaking the internal enum.
    expect(WORKFLOW_END_USER_MESSAGES.runner_runaway).toContain(
      "agent went idle",
    );
    expect(WORKFLOW_END_USER_MESSAGES.cost_ceiling).toContain(
      "per-workflow cost cap",
    );
    expect(WORKFLOW_END_USER_MESSAGES.internal_error).toContain(
      "Something went wrong",
    );

    // Defense-in-depth: NO entry should leak the status token verbatim
    // in a `Workflow ended (...)` template.
    for (const [key, msg] of Object.entries(WORKFLOW_END_USER_MESSAGES)) {
      expect(msg, `key=${key}`).not.toContain("Workflow ended (");
    }
  });

  // ---------------------------------------------------------------------------
  // dispatchSoleurGo onToolUse label routing (#3235)
  //
  // Bug: cc-dispatcher emitted `label: block.name` (raw SDK tool name like
  // `Read`) on the `tool_use` WS event, while the legacy agent-runner path
  // routes the same event through `buildToolLabel(name, input, workspacePath)`
  // which produces verbose, scrubbed labels (`Reading <relative>.pdf...`).
  // After fix, both server-side `tool_use` emitters share identical
  // label-building semantics and the chip beneath "Soleur Concierge / Working"
  // shows the verbose label end-to-end.
  // ---------------------------------------------------------------------------
  type ToolUseBlock = {
    name: string;
    input: Record<string, unknown>;
    toolUseId: string;
  };

  function makeStubCcRunner(args: {
    onDispatch: (events: { onToolUse: (block: ToolUseBlock) => void }) => void;
  }) {
    return {
      dispatch: vi.fn(
        async (a: { events: { onToolUse: (b: ToolUseBlock) => void } }) => {
          // Yield one microtask so the dispatcher's parallel
          // workspace-resolve `.then` settles before the stub fires
          // onToolUse. In production, the SDK Query construction (which
          // awaits the same memo) provides this ordering implicitly; the
          // stub bypasses the runner internals so we simulate it explicitly.
          await Promise.resolve();
          args.onDispatch(a.events);
          return { queryReused: false };
        },
      ),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
  }

  function captureToolUseFrames(sendToClient: ReturnType<typeof vi.fn>) {
    return sendToClient.mock.calls
      .filter(
        ([, msg]) =>
          msg &&
          typeof msg === "object" &&
          (msg as { type?: string }).type === "tool_use",
      )
      .map(([, msg]) => msg as { type: string; label: string; leaderId?: string });
  }

  it("KB Concierge: routes onToolUse label through buildToolLabel and scrubs workspace prefix", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    const stubWorkspace = "/tmp/claude-XXXX/workspace";
    mockFetchUserWorkspacePath.mockResolvedValue(stubWorkspace);

    __setCcRunnerForTests(
      makeStubCcRunner({
        onDispatch: (events) =>
          events.onToolUse({
            name: "Read",
            input: { file_path: `${stubWorkspace}/Au Chat Potan.pdf` },
            toolUseId: "tool_use_1",
          }),
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-tool-label",
      conversationId: "conv-tool-label",
      userMessage: "summarize this PDF",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
      artifactPath: "Au Chat Potan.pdf",
      documentKind: "pdf",
    });

    const frames = captureToolUseFrames(sendToClient);
    expect(frames).toHaveLength(1);
    const frame = frames[0]!;

    // Must NOT be the bare SDK tool name (the bug).
    expect(frame.label).not.toBe("Read");
    // Must read like a Read-with-relative-path label. Use a regex so a
    // future buildToolLabel suffix tweak (`...` → `…`, etc.) does not
    // break this dispatcher-contract test — exact-format coverage lives
    // in `tool-labels.test.ts`.
    expect(frame.label).toMatch(/^Reading .*Au Chat Potan\.pdf/);
    // Must not contain the workspace prefix anywhere — proves the scrub fired.
    expect(frame.label).not.toContain(stubWorkspace);
    // Leader id pinned to cc_router for the Concierge surface.
    expect(frame.leaderId).toBe("cc_router");
  });

  it("KB Concierge: mirrors workspace-resolve failure to Sentry under feature: cc-dispatcher", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    mockFetchUserWorkspacePath.mockRejectedValue(
      new Error("Workspace not provisioned"),
    );

    __setCcRunnerForTests(
      makeStubCcRunner({
        onDispatch: (events) =>
          events.onToolUse({
            name: "Read",
            input: { file_path: "/home/agent/repo/foo.pdf" },
            toolUseId: "tool_use_1",
          }),
      }),
    );

    await dispatchSoleurGo({
      userId: "u-fallback-mirror",
      conversationId: "conv-fallback-mirror",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient: vi.fn().mockReturnValue(true),
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    const workspaceResolveMirrors = mockReportSilentFallback.mock.calls.filter(
      ([, ctx]) =>
        ctx?.feature === "cc-dispatcher" && ctx?.op === "workspace-resolve",
    );
    expect(workspaceResolveMirrors).toHaveLength(1);
    // The userId/conversationId must travel as `extra` so Sentry can group
    // by user + conversation when the resolve flakes.
    expect(workspaceResolveMirrors[0]![1]?.extra).toMatchObject({
      userId: "u-fallback-mirror",
      conversationId: "conv-fallback-mirror",
    });
  });

  it("KB Concierge: falls back to a safe label (no absolute path) when workspace path is unavailable", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    mockFetchUserWorkspacePath.mockRejectedValue(
      new Error("Workspace not provisioned"),
    );

    const absolutePath = "/home/agent/repo/foo.pdf";
    __setCcRunnerForTests(
      makeStubCcRunner({
        onDispatch: (events) =>
          events.onToolUse({
            name: "Read",
            input: { file_path: absolutePath },
            toolUseId: "tool_use_1",
          }),
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-fallback-label",
      conversationId: "conv-fallback-label",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    const frames = captureToolUseFrames(sendToClient);
    expect(frames).toHaveLength(1);
    const frame = frames[0]!;
    // Workspace was unavailable AND the path is absolute, so
    // `extractRelativePath` returns undefined and `buildToolLabel` falls
    // back to FALLBACK_LABELS.Read. Defense-in-depth against echoing
    // host-shaped paths to clients during a Supabase incident.
    expect(frame.label).not.toBe("Read");
    expect(frame.label).toBe("Reading file...");
    expect(frame.label).not.toContain(absolutePath);
  });

  // ---------------------------------------------------------------------------
  // dispatchSoleurGo assistant-message persistence (Continue Thread regression)
  //
  // Mirrors `agent-runner.ts:saveMessage(... "assistant" ...)`. The cc path
  // historically dropped the assistant write, so `api-messages.ts` returned
  // user-only history on resume → `chat-surface.tsx isClassifying === true` →
  // the routing chip rendered on every resumed thread (PR #3251 surfaced
  // the symptom by renaming the chip).
  // ---------------------------------------------------------------------------

  type AssistantPersistenceEvents = {
    onText: (text: string) => void;
    onTextTurnEnd?: () => void;
    // #3603 W2 — flush partial assistant text on non-completed workflow end.
    // Loosely typed to avoid pulling the full WorkflowEnd union into the
    // narrow test contract; tests pass minimally-shaped status payloads.
    onWorkflowEnded?: (end: { status: string } & Record<string, unknown>) => void;
    // #3603 W4 — per-turn cost telemetry captured pre-`onTextTurnEnd` so the
    // dispatcher can attach `{ cost_usd }` to the corresponding `messages` row
    // under the `CC_PERSIST_USAGE` flag.
    onResult?: (result: { totalCostUsd: number }) => void;
  };

  function makeAssistantPersistenceStubRunner(args: {
    onDispatch: (events: AssistantPersistenceEvents) => Promise<void> | void;
  }) {
    return {
      dispatch: vi.fn(
        async (a: { events: AssistantPersistenceEvents }) => {
          await Promise.resolve();
          await args.onDispatch(a.events);
          return { queryReused: false };
        },
      ),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
  }

  function assistantInsertCalls(
    insertMock: ReturnType<typeof vi.fn>,
  ): Array<Record<string, unknown>> {
    return insertMock.mock.calls
      .map((c) => c[0] as { role?: string } & Record<string, unknown>)
      .filter((row) => row && row.role === "assistant");
  }

  function mirrorCallsForOp(
    mirrorMock: ReturnType<typeof vi.fn>,
    op: string,
  ): Array<unknown[]> {
    return mirrorMock.mock.calls.filter(([, ctx]) => {
      const c = ctx as { feature?: string; op?: string } | undefined;
      return c?.feature === "cc-dispatcher" && c?.op === op;
    });
  }

  it("T1: persists assistant message via supabase().from('messages').insert when onTextTurnEnd fires", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          // #3603 W8 — single onText carries the complete SDK emission for
          // this turn. The multi-emission "last-wins" semantic is exercised
          // separately in T-W8 / T-W8-emission-order.
          events.onText("Hello world.");
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-persist-1",
      conversationId: "conv-persist-1",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // `void saveAssistantMessage()` is fire-and-forget; wait for the insert
    // to land rather than counting microtasks (which silently invalidates
    // the test if the helper's await chain grows).
    await vi.waitFor(() =>
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1),
    );

    const assistantRows = assistantInsertCalls(mockMessagesInsert);
    expect(assistantRows[0]).toEqual(
      expect.objectContaining({
        conversation_id: "conv-persist-1",
        role: "assistant",
        content: "Hello world.",
        leader_id: "cc_router",
      }),
    );
  });

  it("T2: does NOT insert assistant row when no text was emitted (tool-only turn)", async () => {
    // RED-cycle note: this test passed vacuously before T1's GREEN — the
    // pre-fix dispatcher never inserted assistant rows at all. Its load-bearing
    // role is forward: catches a future regression where the
    // `if (!fullText) return` empty-text guard is dropped.
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          // No onText calls — simulate a tool-only turn that ends in `result`.
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-empty-turn",
      conversationId: "conv-empty-turn",
      userMessage: "run a tool",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // No assistant row should ever be inserted — flush microtasks and assert
    // the count stays at 0.
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(0);
  });

  // ---------------------------------------------------------------------------
  // #3603 W8 — replace-not-append: align persisted content with UI render
  //
  // The chat-state-machine REPLACE semantic at `chat-state-machine.ts:477`
  // (`applyStreamEvent` case `"stream"`) shows only the LATEST SDK emission
  // within a turn. The server accumulator must mirror this so DB hydration
  // on tab reload matches what the user saw live (AC11 evidence
  // 2026-05-11 — conversation 36df3694: persisted content concatenated a
  // hidden routing preamble with the visible answer; user only saw the
  // answer).
  //
  // Invariant: the value of `accumulatedAssistantText` at the instant
  // `onTextTurnEnd` fires is what persists. No reordering, no merge.
  // ---------------------------------------------------------------------------

  it("T-W8: multi-emission within one turn persists ONLY the latest emission (replace, not append)", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          // Simulates the AC11 finding: SDK emits a routing preamble
          // (filtered/replaced by the UI's REPLACE semantic), then the
          // actual user-visible answer.
          events.onText("Routing to soleur:go — classifying this as a connectivity ping.");
          events.onText("AC11 verification confirmed.");
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w8-1",
      conversationId: "conv-w8-1",
      userMessage: "ping",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    await vi.waitFor(() =>
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1),
    );

    const [row] = assistantInsertCalls(mockMessagesInsert);
    // Only the LATEST emission persists — preamble is gone.
    expect(row).toEqual(
      expect.objectContaining({
        role: "assistant",
        content: "AC11 verification confirmed.",
        leader_id: "cc_router",
      }),
    );
    // Explicit negative assertion guards against future regression to `+=`.
    expect((row.content as string)).not.toContain("Routing to soleur:go");
  });

  it("T-W8-emission-order: persistence mirrors UI render regardless of SDK emission order (last wins, even when 'wrong')", async () => {
    // Falsifiable proof of the chosen W8 invariant (GDPR BLOCK 1 corollary).
    // If the SDK ever reverses order and emits the preamble LAST, persistence
    // will store the preamble — same as what the UI would render. Drift
    // between persistence and UI stays zero regardless of "meaning".
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          // Reversed order: answer first, then routing preamble.
          events.onText("AC11 verification confirmed.");
          events.onText("Routing to soleur:go — classifying this as a connectivity ping.");
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w8-2",
      conversationId: "conv-w8-2",
      userMessage: "ping",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    await vi.waitFor(() =>
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1),
    );

    const [row] = assistantInsertCalls(mockMessagesInsert);
    // LAST emission wins — preamble persists even though "wrong" from the
    // user's perspective. The UI would render the same; consistency is the
    // load-bearing invariant.
    expect(row.content).toBe(
      "Routing to soleur:go — classifying this as a connectivity ping.",
    );
  });

  // ---------------------------------------------------------------------------
  // #3603 W2 — flush partial assistant text on non-completed workflow end
  //
  // Mirrors the legacy abort contract at `agent-runner.ts:2044-2055` so the
  // user's partially-streamed text survives a runner abort. A closure-scoped
  // `workflowEnded` flag suppresses a late `onTextTurnEnd` so it cannot
  // double-write or overwrite the abort row.
  //
  // Scope: 6 non-`completed` `WorkflowEnd` statuses (cost_ceiling,
  // runner_runaway, user_aborted, idle_timeout, plugin_load_failure,
  // internal_error). User-Stop is `user_aborted` and IS covered.
  //
  // Accepted residuals: SIGKILL (no onWorkflowEnded fires) and
  // reaper/closeConversation paths (cc-dispatcher.ts:738).
  // ---------------------------------------------------------------------------

  for (const statusFixture of [
    { status: "runner_runaway", elapsedMs: 5000, lastBlockKind: "text", lastBlockToolName: null, reason: "idle_window" },
    { status: "idle_timeout" },
    { status: "internal_error", error: "boom" },
    { status: "user_aborted" },
    { status: "plugin_load_failure", error: "plugin missing" },
    { status: "cost_ceiling", totalCostUsd: 5, cap: 4, workflow: null },
  ]) {
    it(`T-W2-${statusFixture.status}: flushes accumulated text as status:"aborted" row on non-completed workflow end`, async () => {
      const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

      __setCcRunnerForTests(
        makeAssistantPersistenceStubRunner({
          onDispatch: (events) => {
            events.onText("partial reply before abort");
            // Note: onTextTurnEnd does NOT fire — runner aborts mid-turn.
            events.onWorkflowEnded?.(statusFixture);
          },
        }),
      );

      const sendToClient = vi.fn().mockReturnValue(true);
      await dispatchSoleurGo({
        userId: `u-w2-${statusFixture.status}`,
        conversationId: `conv-w2-${statusFixture.status}`,
        userMessage: "hi",
        currentRouting: { kind: "soleur_go_pending" },
        sendToClient,
        persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
      });

      await vi.waitFor(() =>
        expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1),
      );

      const [row] = assistantInsertCalls(mockMessagesInsert);
      expect(row).toEqual(
        expect.objectContaining({
          role: "assistant",
          content: "partial reply before abort",
          leader_id: "cc_router",
          status: "aborted",
        }),
      );
    });
  }

  it("T-W2-empty: does NOT write an aborted row when accumulator is empty (tool-only turn that aborts)", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          // No onText — model used a tool then aborted before emitting text.
          events.onWorkflowEnded?.({ status: "runner_runaway", elapsedMs: 5000, lastBlockKind: "tool_use", lastBlockToolName: "Read", reason: "idle_window" });
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w2-empty",
      conversationId: "conv-w2-empty",
      userMessage: "tool only",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Flush microtasks; no assistant insert should land.
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(0);
  });

  it("T-W2-completed: does NOT write an aborted row on status:'completed' (normal onTextTurnEnd path applies)", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          events.onText("normal reply");
          // onWorkflowEnded with completed fires AFTER onTextTurnEnd in the
          // normal flow; here we simulate the completed-only case for safety.
          events.onTextTurnEnd?.();
          events.onWorkflowEnded?.({ status: "completed" });
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w2-completed",
      conversationId: "conv-w2-completed",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    await vi.waitFor(() =>
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1),
    );

    const [row] = assistantInsertCalls(mockMessagesInsert);
    // Normal flow — no "aborted" status, just a regular assistant row.
    expect(row.status).not.toBe("aborted");
    expect(row.content).toBe("normal reply");
  });

  it("T-W2-late-text-async: workflowEnded flag survives a real microtask boundary between onWorkflowEnded and onTextTurnEnd", async () => {
    // Per GDPR work-phase-2-exit R2 (2026-05-12): T-W2-late-text fires both
    // callbacks synchronously; in production the SDK iterator may interleave
    // them across actual microtasks. The synchronous flag set is correct
    // either way, but this test exercises the realistic async interleave.
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: async (events) => {
          events.onText("partial before abort (async case)");
          events.onWorkflowEnded?.({
            status: "runner_runaway",
            elapsedMs: 5000,
            lastBlockKind: "text",
            lastBlockToolName: null,
            reason: "idle_window",
          });
          // Yield the event loop — real-world SDK iterator interleave.
          await Promise.resolve();
          await Promise.resolve();
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w2-async",
      conversationId: "conv-w2-async",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    await vi.waitFor(() =>
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1),
    );
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1);

    const [row] = assistantInsertCalls(mockMessagesInsert);
    expect(row.status).toBe("aborted");
    expect(row.content).toBe("partial before abort (async case)");
  });

  it("T-W2-late-text: a late onTextTurnEnd after onWorkflowEnded(aborted) is a silent no-op (no double-write, no overwrite)", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          events.onText("text before abort");
          events.onWorkflowEnded?.({ status: "runner_runaway", elapsedMs: 5000, lastBlockKind: "text", lastBlockToolName: null, reason: "idle_window" });
          // Simulate the in-flight SDK callback that arrives after the abort
          // has already flushed. The workflowEnded flag must suppress this.
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w2-late",
      conversationId: "conv-w2-late",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Settle: only the abort write should land; the late onTextTurnEnd
    // should not produce a second insert.
    await vi.waitFor(() =>
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1),
    );
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1);

    const [row] = assistantInsertCalls(mockMessagesInsert);
    expect(row.status).toBe("aborted");
    expect(row.content).toBe("text before abort");
  });

  it("T3: mirrors save-assistant-message-failed to Sentry on insert error and does NOT throw", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    // Role-aware mock — does not depend on insert ordering between user and
    // assistant rows. If the dispatcher is ever refactored to write the user
    // row in a different position, this test still drives the assistant
    // failure-path deterministically.
    mockMessagesInsert.mockImplementation(
      async (row: { role?: string }) =>
        row?.role === "assistant"
          ? { error: { message: "db down" } }
          : { error: null },
    );

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          events.onText("text");
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await expect(
      dispatchSoleurGo({
        userId: "u-mirror-fail",
        conversationId: "conv-mirror-fail",
        userMessage: "hi",
        currentRouting: { kind: "soleur_go_pending" },
        sendToClient,
        persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
      }),
    ).resolves.not.toThrow();

    await vi.waitFor(() =>
      expect(
        mirrorCallsForOp(mockReportSilentFallback, "save-assistant-message-failed"),
      ).toHaveLength(1),
    );

    // The mirrored error MUST be the underlying Supabase error, not undefined
    // — defends against a future refactor that drops the err arg.
    const mirrorCall = mirrorCallsForOp(
      mockReportSilentFallback,
      "save-assistant-message-failed",
    )[0]!;
    expect(mirrorCall[0]).toBeTruthy();
    expect(mirrorCall[0]).toMatchObject({ message: "db down" });
  });

  // ---------------------------------------------------------------------------
  // #3603 W4 — `messages.usage` parity behind `CC_PERSIST_USAGE` flag
  //
  // Default-off. When on, cc-path persists the cc-narrowed shape
  // `{ cost_usd: number }` per Art. 5(1)(c) data-minimization (cost only on
  // complete turns; full usage snapshot is the legacy agent-runner contract).
  // ---------------------------------------------------------------------------

  it("T-W4-basic-on: persists usage = { cost_usd } when CC_PERSIST_USAGE=true and onResult fired before onTextTurnEnd", async () => {
    vi.stubEnv("CC_PERSIST_USAGE", "true");
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          events.onText("turn N reply");
          // Runner fires onResult immediately before onTextTurnEnd (see
          // soleur-go-runner.ts handleResultMessage:1836+1848).
          events.onResult?.({ totalCostUsd: 0.0042 });
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w4-on",
      conversationId: "conv-w4-on",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    await vi.waitFor(() =>
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1),
    );

    const [row] = assistantInsertCalls(mockMessagesInsert);
    // cc-narrowed shape: `cost_usd` only — NO `input_tokens` / `output_tokens`
    // / `completed_actions` on complete turns (Art. 5(1)(c)).
    expect(row.usage).toEqual({ cost_usd: 0.0042 });
  });

  it("T-W4-basic-off: persists usage = null when CC_PERSIST_USAGE is unset (default)", async () => {
    // No vi.stubEnv — exercises the default-off path enforced by AC9/AC11.
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          events.onText("turn N reply");
          events.onResult?.({ totalCostUsd: 0.0042 });
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w4-off",
      conversationId: "conv-w4-off",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    await vi.waitFor(() =>
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1),
    );

    const [row] = assistantInsertCalls(mockMessagesInsert);
    // Flag off → explicit null, NOT `{ cost_usd: 0.0042 }`. Status defaults
    // to `'complete'` via migration 040 (omitted from the row payload).
    expect(row.usage).toBeNull();
    expect(row.status).toBeUndefined();
  });

  it("T-W4-race: per-turn `pendingTurnUsage` snapshot-clear-bump attaches each turn's cost to its own row + a LATE stale onResult attaches to the next turn (not bleeds back)", async () => {
    // Test-design review 2026-05-12 flagged the earlier variant as a vacuous
    // pass against the `turnIndex` tag — events fired sequentially per turn
    // would pass even without the tag. Revised below to ALSO exercise the
    // stale-onResult scenario:
    //   Turn 0: onText → onResult(c0) → onTextTurnEnd (saves with c0,
    //           snapshot-clear-bumps to turnIndex=1)
    //   Stale:  onResult(c_stale) — fires AFTER turn 0's bump but BEFORE
    //           turn 1's content. pendingTurnUsage gets tagged turnIndex=1
    //           with the wrong cost.
    //   Turn 1: onText → onResult(c1) overwrites pendingTurnUsage (still
    //           tagged 1) → onTextTurnEnd saves with c1 (correct).
    // Load-bearing assertion: row 0 carries c0 (NOT c_stale), row 1 carries
    // c1 (NOT c_stale). Catches a regression where pendingTurnUsage isn't
    // cleared per turn or where the snapshot bumps `currentTurnIndex`
    // BEFORE reading pendingTurnUsage (which would cause a turnIndex mismatch
    // and drop turn 0's usage).
    vi.stubEnv("CC_PERSIST_USAGE", "true");
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          // Turn 0
          events.onText("first reply");
          events.onResult?.({ totalCostUsd: 0.001 });
          events.onTextTurnEnd?.();
          // Late stale onResult — currentTurnIndex is now 1 (bumped by the
          // preceding onTextTurnEnd), so this captures with turnIndex=1.
          // Turn 1's onResult below overwrites it.
          events.onResult?.({ totalCostUsd: 0.999 });
          // Turn 1
          events.onText("second reply");
          events.onResult?.({ totalCostUsd: 0.002 });
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w4-race",
      conversationId: "conv-w4-race",
      userMessage: "two turns",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    await vi.waitFor(() =>
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(2),
    );

    const rows = assistantInsertCalls(mockMessagesInsert);
    expect(rows[0]).toEqual(
      expect.objectContaining({ content: "first reply", usage: { cost_usd: 0.001 } }),
    );
    expect(rows[1]).toEqual(
      expect.objectContaining({ content: "second reply", usage: { cost_usd: 0.002 } }),
    );
  });

  it("T-W4-orphan: usage captured + empty text aborted via runner_runaway drops the row AND fires mirrorP0Deduped(usage_orphan_dropped)", async () => {
    vi.stubEnv("CC_PERSIST_USAGE", "true");
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          // Cost emitted (turn cost-capped after a tool burst) but the model
          // produced zero text → empty-content drop per PR-A1 contract.
          events.onResult?.({ totalCostUsd: 0.0099 });
          events.onWorkflowEnded?.({
            status: "runner_runaway",
            elapsedMs: 5000,
            lastBlockKind: "tool_use",
            lastBlockToolName: "Bash",
            reason: "idle_window",
          });
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w4-orphan",
      conversationId: "conv-w4-orphan",
      userMessage: "tool-only orphan",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Settle: no assistant insert.
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(0);

    // Exactly ONE P0 mirror with the literal op slug.
    expect(mockMirrorP0Deduped).toHaveBeenCalledTimes(1);
    const [errArg, ctxArg] = mockMirrorP0Deduped.mock.calls[0]!;
    expect((errArg as Error)?.message).toBe("usage_orphan_dropped");
    expect(ctxArg).toEqual({
      op: "usage_orphan_dropped",
      userId: "u-w4-orphan",
      conversationId: "conv-w4-orphan",
    });
  });

  it("T-W4-flag-symmetry: CC_PERSIST_USAGE=true but onResult never fires → row writes usage = null (explicit, not undefined)", async () => {
    vi.stubEnv("CC_PERSIST_USAGE", "true");
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          events.onText("reply without onResult");
          // No onResult — simulates SDK callback drop / non-fire path.
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w4-symmetry",
      conversationId: "conv-w4-symmetry",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    await vi.waitFor(() =>
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1),
    );

    const [row] = assistantInsertCalls(mockMessagesInsert);
    // Flag on + no captured usage → explicit null write. Closes the
    // telemetry-join-format-mismatch class of bugs (learning
    // 2026-05-04-telemetry-join-format-mismatch-caught-by-orphan-counter.md).
    expect(row.usage).toBeNull();
  });

  it("T-W4-reset-symmetry: abort-with-text attaches captured usage AND clears pendingTurnUsage so a late onTextTurnEnd is a no-op", async () => {
    vi.stubEnv("CC_PERSIST_USAGE", "true");
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    __setCcRunnerForTests(
      makeAssistantPersistenceStubRunner({
        onDispatch: (events) => {
          events.onText("partial before abort");
          events.onResult?.({ totalCostUsd: 0.005 });
          // Abort while text is present → aborted row carries the captured
          // usage; pendingTurnUsage MUST be cleared so a late onTextTurnEnd
          // cannot re-attach the stale value.
          events.onWorkflowEnded?.({ status: "user_aborted" });
          events.onTextTurnEnd?.();
        },
      }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      userId: "u-w4-reset",
      conversationId: "conv-w4-reset",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    await vi.waitFor(() =>
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1),
    );
    // Settle further — confirm the late onTextTurnEnd does NOT produce a
    // second insert.
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(1);

    const [row] = assistantInsertCalls(mockMessagesInsert);
    expect(row).toEqual(
      expect.objectContaining({
        role: "assistant",
        content: "partial before abort",
        status: "aborted",
        usage: { cost_usd: 0.005 },
      }),
    );
    // No orphan mirror — the usage was consumed by the aborted row.
    expect(mockMirrorP0Deduped).not.toHaveBeenCalled();
  });

  // ---------------------------------------------------------------------------
  // #3603 W1 invariant-7 — `assertWriteScope` sentinel call-site smoke.
  //
  // Sentinel-only at HEAD (no payload source exists); the call site itself is
  // the load-bearing invariant. Any future refactor that drops the call must
  // be caught by this test. When a payload source IS wired in, this test is
  // extended with a mismatch scenario asserting `mirrorP0Deduped` fires.
  // ---------------------------------------------------------------------------

  it("T-W1-invariant-7: assertWriteScope is exercised at EVERY messages-write call site (user-INSERT + complete + aborted)", async () => {
    // Sentinel-only at HEAD: the production helper always returns `true`.
    // Forcing it to fail at SPECIFIC call sites proves the halt wiring is
    // present at each one. Call sequence (per `dispatchSoleurGo`):
    //   Call 1: user-row INSERT (pre-runner). Throws on false.
    //   Call 2: `onTextTurnEnd` → `saveAssistantMessage()` (complete path).
    //           Returns silently on false.
    //   Call 3: `onWorkflowEnded` abort branch → `saveAssistantMessage({status:"aborted"})`.
    //           Returns silently on false.
    // Call-counting spy: lets call 1 through (so dispatch reaches the runner),
    // then halts calls 2 + 3. Tests ALL THREE call sites in a single dispatch.
    const {
      __setCcRunnerForTests,
      __setAssertWriteScopeForTests,
      __resetAssertWriteScopeForTests,
    } = await import("@/server/cc-dispatcher");

    let scopeCallCount = 0;
    const scopeSpy = vi.fn(() => {
      scopeCallCount += 1;
      // First call (user-INSERT) succeeds so dispatch proceeds; subsequent
      // calls (assistant complete + abort) halt.
      return scopeCallCount === 1;
    });
    __setAssertWriteScopeForTests(scopeSpy);

    try {
      __setCcRunnerForTests(
        makeAssistantPersistenceStubRunner({
          onDispatch: (events) => {
            // Drive BOTH the complete-path and the abort-path call sites
            // through a single dispatch so the test pins them together.
            events.onText("would have been persisted");
            events.onTextTurnEnd?.();
            events.onText("partial before abort");
            events.onWorkflowEnded?.({
              status: "user_aborted",
            });
          },
        }),
      );

      const sendToClient = vi.fn().mockReturnValue(true);
      await dispatchSoleurGo({
        userId: "u-scope",
        conversationId: "conv-scope",
        userMessage: "hi",
        currentRouting: { kind: "soleur_go_pending" },
        sendToClient,
        persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
      });

      // Settle the assistant call sites' microtasks.
      await new Promise((resolve) => setTimeout(resolve, 10));

      // Exactly ONE user-INSERT (call 1 passed), ZERO assistant rows (calls
      // 2 + 3 halted by sentinel).
      const userRows = mockMessagesInsert.mock.calls
        .map((c) => c[0] as { role?: string })
        .filter((r) => r.role === "user");
      expect(userRows).toHaveLength(1);
      expect(assistantInsertCalls(mockMessagesInsert)).toHaveLength(0);

      // Exactly THREE scope-spy invocations — proves all three call sites
      // (user-INSERT, onTextTurnEnd→save, onWorkflowEnded→save({status:"aborted"}))
      // run through the helper. A future refactor that drops any call site
      // fails this assertion.
      expect(scopeSpy).toHaveBeenCalledTimes(3);
      for (const call of scopeSpy.mock.calls) {
        // Receives the dispatch-closure identity tuple — when a future SDK
        // payload source is wired in, this signature is the single edit point.
        expect(call).toEqual(["u-scope", "conv-scope"]);
      }
    } finally {
      __resetAssertWriteScopeForTests();
    }
  });
});
