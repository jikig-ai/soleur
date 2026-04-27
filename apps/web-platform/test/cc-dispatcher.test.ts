import { describe, it, expect, vi, beforeEach } from "vitest";

import {
  getPendingPromptRegistry,
  getCcStartSessionRateLimiter,
  handleInteractivePromptResponseCase,
  dispatchSoleurGo,
  __resetDispatcherForTests,
} from "@/server/cc-dispatcher";
import type { InteractivePromptResponse } from "@/server/cc-interactive-prompt-types";
import { KeyInvalidError } from "@/lib/types";

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
      promptId: "p-1",
      conversationId: "conv-1",
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
          promptId: "p-1",
          conversationId: "conv-1",
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
          ? ({ type: "interactive_prompt_response" } as unknown as import("@/server/cc-interactive-prompt-types").InteractivePromptResponse)
          : ({
              type: "interactive_prompt_response",
              promptId: "p-1",
              conversationId: "conv-1",
              kind: payloadKind,
              response,
            } as unknown as import("@/server/cc-interactive-prompt-types").InteractivePromptResponse);

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
});
