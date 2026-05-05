import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockReportSilentFallback, mockFetchUserWorkspacePath } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockFetchUserWorkspacePath: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
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

import {
  getPendingPromptRegistry,
  getCcStartSessionRateLimiter,
  handleInteractivePromptResponseCase,
  dispatchSoleurGo,
  __resetDispatcherForTests,
} from "@/server/cc-dispatcher";
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
    mockReportSilentFallback.mockClear();
    mockFetchUserWorkspacePath.mockReset();
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
    expect(errMsg.message).toContain("Command Center router is unavailable");
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
  // dispatchSoleurGo onToolUse label routing
  //
  // Bug: cc-dispatcher emitted `label: block.name` (raw SDK tool name like
  // `Read`) on the `tool_use` WS event, while the legacy agent-runner path
  // routes the same event through `buildToolLabel(name, input, workspacePath)`
  // which produces verbose, scrubbed labels (`Reading <relative>.pdf...`).
  // After fix, both server-side `tool_use` emitters share identical
  // label-building semantics and the chip beneath "Soleur Concierge / Working"
  // shows the verbose label end-to-end.
  // ---------------------------------------------------------------------------
  it("KB Concierge: routes onToolUse label through buildToolLabel (verbose, scrubbed)", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    const stubWorkspace = "/tmp/claude-XXXX/workspace";
    mockFetchUserWorkspacePath.mockResolvedValue(stubWorkspace);

    const stubRunner = {
      dispatch: vi.fn(
        async (args: {
          events: {
            onToolUse: (block: {
              name: string;
              input: Record<string, unknown>;
              toolUseId: string;
            }) => void;
          };
        }) => {
          args.events.onToolUse({
            name: "Read",
            input: { file_path: `${stubWorkspace}/Au Chat Potan.pdf` },
            toolUseId: "tool_use_1",
          });
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
    __setCcRunnerForTests(stubRunner);

    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    await dispatchSoleurGo({
      userId: "u-tool-label",
      conversationId: "conv-tool-label",
      userMessage: "summarize this PDF",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
      artifactPath: "Au Chat Potan.pdf",
      documentKind: "pdf",
    });

    const toolUseCalls = sendToClient.mock.calls.filter(
      ([, msg]) =>
        msg && typeof msg === "object" && (msg as { type?: string }).type === "tool_use",
    );
    expect(toolUseCalls.length).toBe(1);
    const frame = toolUseCalls[0][1] as {
      type: string;
      label: string;
      leaderId?: string;
    };
    // Must NOT be the bare SDK tool name.
    expect(frame.label).not.toBe("Read");
    // Must be the buildToolLabel output, with workspace prefix scrubbed.
    expect(frame.label).toBe("Reading Au Chat Potan.pdf...");
    // Must not contain the workspace prefix anywhere — proves the scrub fired.
    expect(frame.label).not.toContain(stubWorkspace);
    // Leader id pinned to cc_router for the Concierge surface.
    expect(frame.leaderId).toBe("cc_router");
  });

  it("KB Concierge: emits verbose label and mirrors to Sentry when fetchUserWorkspacePath throws", async () => {
    const { __setCcRunnerForTests } = await import("@/server/cc-dispatcher");

    mockFetchUserWorkspacePath.mockRejectedValue(
      new Error("Workspace not provisioned"),
    );

    const stubRunner = {
      dispatch: vi.fn(
        async (args: {
          events: {
            onToolUse: (block: {
              name: string;
              input: Record<string, unknown>;
              toolUseId: string;
            }) => void;
          };
        }) => {
          args.events.onToolUse({
            name: "Read",
            input: { file_path: "/home/agent/repo/foo.pdf" },
            toolUseId: "tool_use_1",
          });
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
    __setCcRunnerForTests(stubRunner);

    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    await dispatchSoleurGo({
      userId: "u-fallback",
      conversationId: "conv-fallback",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
    });

    // Sentry mirror fired exactly once for the workspace-resolve fallback.
    const workspaceResolveMirrors = mockReportSilentFallback.mock.calls.filter(
      ([, ctx]) =>
        ctx?.feature === "command-center" &&
        ctx?.op === "cc-dispatcher-workspace-resolve",
    );
    expect(workspaceResolveMirrors).toHaveLength(1);

    // The tool_use frame still carries a verbose label (NOT the bare "Read").
    // Workspace was unavailable, so the absolute path stays in the label —
    // verbose-but-unscrubbed is acceptable per the deepened plan §Risks.
    const toolUseCalls = sendToClient.mock.calls.filter(
      ([, msg]) =>
        msg && typeof msg === "object" && (msg as { type?: string }).type === "tool_use",
    );
    expect(toolUseCalls.length).toBe(1);
    const frame = toolUseCalls[0][1] as { label: string };
    expect(frame.label).not.toBe("Read");
    expect(frame.label).toBe("Reading /home/agent/repo/foo.pdf...");
  });
});
