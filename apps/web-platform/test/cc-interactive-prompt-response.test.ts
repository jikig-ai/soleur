import { describe, it, expect, vi, beforeEach } from "vitest";

import {
  PendingPromptRegistry,
  makePendingPromptKey,
  type PendingPromptRecord,
} from "@/server/pending-prompt-registry";
import { handleInteractivePromptResponse } from "@/server/cc-interactive-prompt-response";

// RED test for Stage 2.14 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md.
//
// `handleInteractivePromptResponse` is the pure decision function behind
// the `interactive_prompt_response` WS case. Responsibilities:
//   - Zod-validate response shape per `kind` (rejects malformed at boundary).
//   - Ownership check: reject unless the record's userId === ws.session.userId
//     AND record.conversationId === payload.conversationId.
//   - Idempotency via `registry.consume()` — a replay after success is
//     reported as "already_consumed", not silently dropped.
//   - On success, calls `deliverToolResult(toolUseId, content)` to forward
//     the normalized response back to the runner's Query.streamInput.
//
// The function returns a discriminated result the caller maps to a WS
// error code or 2xx-equivalent silence. The function itself does NOT
// emit WS frames (that's ws-handler's concern).

type ResponsePayload = Parameters<typeof handleInteractivePromptResponse>[0]["payload"];

function seedPrompt(
  registry: PendingPromptRegistry,
  overrides: Partial<PendingPromptRecord> = {},
): PendingPromptRecord {
  const record: PendingPromptRecord = {
    promptId: "p-1",
    conversationId: "conv-1",
    userId: "user-1",
    kind: "ask_user",
    toolUseId: "toolu_1",
    createdAt: 0,
    payload: {},
    ...overrides,
  };
  registry.register(record);
  return record;
}

describe("handleInteractivePromptResponse (Stage 2.14)", () => {
  let registry: PendingPromptRegistry;
  let deliverToolResult: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    registry = new PendingPromptRegistry({ nowFn: () => 0 });
    deliverToolResult = vi.fn();
  });

  it("delivers to runner on ownership match + valid payload", () => {
    seedPrompt(registry);
    const result = handleInteractivePromptResponse({
      registry,
      userId: "user-1",
      payload: {
        type: "interactive_prompt_response",
        promptId: "p-1",
        conversationId: "conv-1",
        kind: "ask_user",
        response: "A",
      },
      deliverToolResult,
    });
    expect(result.ok).toBe(true);
    expect(deliverToolResult).toHaveBeenCalledTimes(1);
    const call = deliverToolResult.mock.calls[0]!;
    expect(call[0]).toEqual({
      conversationId: "conv-1",
      toolUseId: "toolu_1",
      content: "A",
    });
  });

  it("rejects when the prompt owner is a different user (no such prompt)", () => {
    seedPrompt(registry, { userId: "other-user" });
    const result = handleInteractivePromptResponse({
      registry,
      userId: "user-1", // imposter
      payload: {
        type: "interactive_prompt_response",
        promptId: "p-1",
        conversationId: "conv-1",
        kind: "ask_user",
        response: "A",
      },
      deliverToolResult,
    });
    expect(result).toEqual({ ok: false, error: "not_found" });
    expect(deliverToolResult).not.toHaveBeenCalled();
  });

  it("rejects cross-conversation probe as not_found (composite key silent-denies)", () => {
    // The registry's composite key includes conversationId, so a crafted
    // payload with a known promptId but a DIFFERENT conversationId does
    // NOT reach the record — registry.get returns undefined, which the
    // handler reports as not_found. This IS the security invariant
    // (silent denial per pending-prompt-registry.ts §(b)): the attacker
    // cannot probe for the existence of someone else's promptId across
    // conversations. The record owned by its real conversation stays
    // untouched.
    seedPrompt(registry, { conversationId: "conv-1" });
    const result = handleInteractivePromptResponse({
      registry,
      userId: "user-1",
      payload: {
        type: "interactive_prompt_response",
        promptId: "p-1",
        conversationId: "conv-OTHER",
        kind: "ask_user",
        response: "A",
      },
      deliverToolResult,
    });
    expect(result).toEqual({ ok: false, error: "not_found" });
    // The real record must NOT be consumed (a subsequent correct reply must work).
    expect(registry.size()).toBe(1);
    expect(deliverToolResult).not.toHaveBeenCalled();
  });

  it("rejects when payload.kind does not match the record's kind", () => {
    seedPrompt(registry, { kind: "plan_preview" });
    const result = handleInteractivePromptResponse({
      registry,
      userId: "user-1",
      payload: {
        type: "interactive_prompt_response",
        promptId: "p-1",
        conversationId: "conv-1",
        kind: "bash_approval",
        response: "approve",
      },
      deliverToolResult,
    });
    expect(result).toEqual({ ok: false, error: "kind_mismatch" });
    expect(registry.size()).toBe(1);
    expect(deliverToolResult).not.toHaveBeenCalled();
  });

  it("returns already_consumed on a replay after success", () => {
    seedPrompt(registry);
    const first = handleInteractivePromptResponse({
      registry,
      userId: "user-1",
      payload: {
        type: "interactive_prompt_response",
        promptId: "p-1",
        conversationId: "conv-1",
        kind: "ask_user",
        response: "A",
      },
      deliverToolResult,
    });
    expect(first.ok).toBe(true);

    const replay = handleInteractivePromptResponse({
      registry,
      userId: "user-1",
      payload: {
        type: "interactive_prompt_response",
        promptId: "p-1",
        conversationId: "conv-1",
        kind: "ask_user",
        response: "A",
      },
      deliverToolResult,
    });
    expect(replay).toEqual({ ok: false, error: "already_consumed" });
    expect(deliverToolResult).toHaveBeenCalledTimes(1); // only the first
  });

  it("rejects ask_user with non-string / non-array response as invalid_response", () => {
    seedPrompt(registry, { kind: "ask_user" });
    const result = handleInteractivePromptResponse({
      registry,
      userId: "user-1",
      payload: {
        type: "interactive_prompt_response",
        promptId: "p-1",
        conversationId: "conv-1",
        kind: "ask_user",
        // biome-ignore lint/suspicious/noExplicitAny: intentionally malformed
        response: 42 as any,
      } as unknown as ResponsePayload,
      deliverToolResult,
    });
    expect(result).toEqual({ ok: false, error: "invalid_response" });
    expect(registry.size()).toBe(1); // not consumed on malformed
    expect(deliverToolResult).not.toHaveBeenCalled();
  });

  it("accepts plan_preview response of 'accept' or 'iterate' only", () => {
    seedPrompt(registry, { kind: "plan_preview" });
    const good = handleInteractivePromptResponse({
      registry,
      userId: "user-1",
      payload: {
        type: "interactive_prompt_response",
        promptId: "p-1",
        conversationId: "conv-1",
        kind: "plan_preview",
        response: "accept",
      },
      deliverToolResult,
    });
    expect(good.ok).toBe(true);
    expect(deliverToolResult.mock.calls[0]![0].content).toBe("accept");

    seedPrompt(registry, { promptId: "p-2", kind: "plan_preview" });
    const bad = handleInteractivePromptResponse({
      registry,
      userId: "user-1",
      payload: {
        type: "interactive_prompt_response",
        promptId: "p-2",
        conversationId: "conv-1",
        kind: "plan_preview",
        // biome-ignore lint/suspicious/noExplicitAny: intentionally malformed
        response: "reject" as any,
      } as unknown as ResponsePayload,
      deliverToolResult,
    });
    expect(bad).toEqual({ ok: false, error: "invalid_response" });
  });

  it("accepts bash_approval response of 'approve' or 'deny' only", () => {
    seedPrompt(registry, { kind: "bash_approval" });
    const good = handleInteractivePromptResponse({
      registry,
      userId: "user-1",
      payload: {
        type: "interactive_prompt_response",
        promptId: "p-1",
        conversationId: "conv-1",
        kind: "bash_approval",
        response: "deny",
      },
      deliverToolResult,
    });
    expect(good.ok).toBe(true);
  });

  it("accepts diff / todo_write / notebook_edit 'ack'", () => {
    for (const kind of ["diff", "todo_write", "notebook_edit"] as const) {
      const reg = new PendingPromptRegistry({ nowFn: () => 0 });
      const cb = vi.fn();
      reg.register({
        promptId: "p-x",
        conversationId: "conv-1",
        userId: "user-1",
        kind,
        toolUseId: `tu-${kind}`,
        createdAt: 0,
        payload: {},
      });
      const result = handleInteractivePromptResponse({
        registry: reg,
        userId: "user-1",
        payload: {
          type: "interactive_prompt_response",
          promptId: "p-x",
          conversationId: "conv-1",
          kind,
          response: "ack",
        },
        deliverToolResult: cb,
      });
      expect(result.ok).toBe(true);
      expect(cb).toHaveBeenCalledWith({
        conversationId: "conv-1",
        toolUseId: `tu-${kind}`,
        content: "ack",
      });
    }
  });

  it("returns invalid_payload when the payload shape is malformed (missing promptId)", () => {
    seedPrompt(registry);
    const result = handleInteractivePromptResponse({
      registry,
      userId: "user-1",
      // biome-ignore lint/suspicious/noExplicitAny: intentionally malformed
      payload: { type: "interactive_prompt_response" } as any,
      deliverToolResult,
    });
    expect(result).toEqual({ ok: false, error: "invalid_payload" });
    expect(deliverToolResult).not.toHaveBeenCalled();
  });
});
