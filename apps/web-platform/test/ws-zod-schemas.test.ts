import { describe, test, expect } from "vitest";
import {
  parseWSMessage,
  wsMessageSchema,
  interactivePromptPayloadSchema,
  interactivePromptResponseSchema,
} from "@/lib/ws-zod-schemas";

// Schema-level tests for the Stage 3 WS protocol (#2885). These tests run
// independently of the WS plumbing so a schema/union drift surfaces before
// `ws-client.ts:onmessage` is wired up.
//
// The bidirectional `_SchemaCovers` compile-time assertion in
// `lib/ws-zod-schemas.ts` is the load-bearing drift gate; these runtime tests
// pin a representative round-trip per variant and a representative rejection
// per failure shape.

describe("wsMessageSchema: existing variants round-trip", () => {
  test("session_started succeeds", () => {
    const r = parseWSMessage({ type: "session_started", conversationId: "c-1" });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.msg.type).toBe("session_started");
  });

  test("stream succeeds", () => {
    const r = parseWSMessage({
      type: "stream",
      content: "hi",
      partial: true,
      leaderId: "cmo",
    });
    expect(r.ok).toBe(true);
  });

  test("auth_ok succeeds (no payload fields)", () => {
    const r = parseWSMessage({ type: "auth_ok" });
    expect(r.ok).toBe(true);
  });
});

describe("wsMessageSchema: new Stage 3 variants round-trip", () => {
  test("subagent_spawn succeeds", () => {
    const r = parseWSMessage({
      type: "subagent_spawn",
      parentId: "p-1",
      leaderId: "cmo",
      spawnId: "s-1",
    });
    expect(r.ok).toBe(true);
  });

  test("subagent_complete succeeds", () => {
    const r = parseWSMessage({
      type: "subagent_complete",
      spawnId: "s-1",
      status: "success",
    });
    expect(r.ok).toBe(true);
  });

  test("workflow_started succeeds", () => {
    const r = parseWSMessage({
      type: "workflow_started",
      workflow: "brainstorm",
      conversationId: "c-1",
    });
    expect(r.ok).toBe(true);
  });

  test("workflow_ended succeeds with summary", () => {
    const r = parseWSMessage({
      type: "workflow_ended",
      workflow: "plan",
      status: "completed",
      summary: "Plan ready.",
    });
    expect(r.ok).toBe(true);
  });

  test("workflow_ended succeeds without summary", () => {
    const r = parseWSMessage({
      type: "workflow_ended",
      workflow: "plan",
      status: "user_aborted",
    });
    expect(r.ok).toBe(true);
  });

  test("interactive_prompt: ask_user kind succeeds", () => {
    const r = parseWSMessage({
      type: "interactive_prompt",
      promptId: "pr-1",
      conversationId: "c-1",
      kind: "ask_user",
      payload: { question: "Q?", options: ["a", "b"], multiSelect: false },
    });
    expect(r.ok).toBe(true);
  });

  test("interactive_prompt: diff kind succeeds", () => {
    const r = parseWSMessage({
      type: "interactive_prompt",
      promptId: "pr-2",
      conversationId: "c-1",
      kind: "diff",
      payload: { path: "/foo", additions: 3, deletions: 1 },
    });
    expect(r.ok).toBe(true);
  });

  test("interactive_prompt: todo_write kind succeeds", () => {
    const r = parseWSMessage({
      type: "interactive_prompt",
      promptId: "pr-3",
      conversationId: "c-1",
      kind: "todo_write",
      payload: {
        items: [
          { id: "1", content: "do thing", status: "pending" },
          { id: "2", content: "next", status: "in_progress" },
        ],
      },
    });
    expect(r.ok).toBe(true);
  });

  test("interactive_prompt_response: ask_user with string succeeds", () => {
    const r = parseWSMessage({
      type: "interactive_prompt_response",
      promptId: "pr-1",
      conversationId: "c-1",
      kind: "ask_user",
      response: "a",
    });
    expect(r.ok).toBe(true);
  });

  test("interactive_prompt_response: ask_user with array succeeds", () => {
    const r = parseWSMessage({
      type: "interactive_prompt_response",
      promptId: "pr-1",
      conversationId: "c-1",
      kind: "ask_user",
      response: ["a", "b"],
    });
    expect(r.ok).toBe(true);
  });

  test("interactive_prompt_response: plan_preview accept succeeds", () => {
    const r = parseWSMessage({
      type: "interactive_prompt_response",
      promptId: "pr-1",
      conversationId: "c-1",
      kind: "plan_preview",
      response: "accept",
    });
    expect(r.ok).toBe(true);
  });

  test("interactive_prompt_response: bash_approval deny succeeds", () => {
    const r = parseWSMessage({
      type: "interactive_prompt_response",
      promptId: "pr-1",
      conversationId: "c-1",
      kind: "bash_approval",
      response: "deny",
    });
    expect(r.ok).toBe(true);
  });

  test("interactive_prompt_response: diff ack succeeds", () => {
    const r = parseWSMessage({
      type: "interactive_prompt_response",
      promptId: "pr-1",
      conversationId: "c-1",
      kind: "diff",
      response: "ack",
    });
    expect(r.ok).toBe(true);
  });
});

describe("wsMessageSchema: rejection cases", () => {
  test("missing type rejects", () => {
    const r = parseWSMessage({ conversationId: "c-1" });
    expect(r.ok).toBe(false);
  });

  test("unknown type rejects", () => {
    const r = parseWSMessage({ type: "made_up", whatever: 1 });
    expect(r.ok).toBe(false);
  });

  test("interactive_prompt without kind rejects", () => {
    const r = parseWSMessage({
      type: "interactive_prompt",
      promptId: "pr-1",
      conversationId: "c-1",
      payload: { foo: "bar" },
    });
    expect(r.ok).toBe(false);
  });

  test("interactive_prompt with malformed payload rejects (diff: additions wrong type)", () => {
    const r = parseWSMessage({
      type: "interactive_prompt",
      promptId: "pr-1",
      conversationId: "c-1",
      kind: "diff",
      payload: { path: "/foo", additions: "not-a-number", deletions: 1 },
    });
    expect(r.ok).toBe(false);
  });

  test("workflow_ended with unknown status rejects", () => {
    const r = parseWSMessage({
      type: "workflow_ended",
      workflow: "plan",
      status: "made_up_status",
    });
    expect(r.ok).toBe(false);
  });

  test("workflow_started with unknown workflow name rejects", () => {
    const r = parseWSMessage({
      type: "workflow_started",
      workflow: "made_up",
      conversationId: "c-1",
    });
    expect(r.ok).toBe(false);
  });

  test("subagent_complete with unknown status rejects", () => {
    const r = parseWSMessage({
      type: "subagent_complete",
      spawnId: "s-1",
      status: "rotated",
    });
    expect(r.ok).toBe(false);
  });
});

describe("interactivePromptPayloadSchema (standalone)", () => {
  test("rejects unknown kind", () => {
    const r = interactivePromptPayloadSchema.safeParse({
      kind: "totally_new",
      payload: {},
    });
    expect(r.success).toBe(false);
  });

  test("ask_user payload requires multiSelect", () => {
    const r = interactivePromptPayloadSchema.safeParse({
      kind: "ask_user",
      payload: { question: "Q?", options: ["a"] },
    });
    expect(r.success).toBe(false);
  });
});

describe("interactivePromptResponseSchema (standalone)", () => {
  test("ack-only kinds reject string responses", () => {
    const r = interactivePromptResponseSchema.safeParse({
      promptId: "pr-1",
      conversationId: "c-1",
      kind: "todo_write",
      response: "accept",
    });
    expect(r.success).toBe(false);
  });

  test("plan_preview rejects ack", () => {
    const r = interactivePromptResponseSchema.safeParse({
      promptId: "pr-1",
      conversationId: "c-1",
      kind: "plan_preview",
      response: "ack",
    });
    expect(r.success).toBe(false);
  });
});

describe("wsMessageSchema: schema export shape", () => {
  test("wsMessageSchema is a Zod schema", () => {
    expect(wsMessageSchema).toBeDefined();
    expect(typeof wsMessageSchema.safeParse).toBe("function");
  });
});
