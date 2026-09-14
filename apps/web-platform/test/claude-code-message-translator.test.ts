import { describe, expect, it } from "vitest";
import { translateClaudeSdkMessage, translateClaudeSdkStream } from "@/server/claude-code-message-translator";

describe("Claude SDK message translator", () => {
  it("translates assistant text blocks into stable neutral text events", () => {
    expect(translateClaudeSdkMessage({
      type: "assistant",
      uuid: "msg-1",
      message: {
        content: [
          { type: "text", text: "hello" },
          { type: "tool_use", id: "tool-1", name: "Bash", input: {} },
          { type: "text", text: "world" },
        ],
      },
    })).toEqual([
      { sourceId: "msg-1:text:0", payload: { type: "text", text: "hello" } },
      { sourceId: "msg-1:text:2", payload: { type: "text", text: "world" } },
    ]);
  });

  it("preserves assistant-level provider failures as sanitized retryable errors", () => {
    expect(translateClaudeSdkMessage({
      type: "assistant",
      uuid: "msg-auth",
      error: "rate_limit",
      message: { content: [] },
    })).toEqual([
      {
        sourceId: "msg-auth:error",
        payload: { type: "error", code: "rate_limit", retryable: true },
      },
    ]);
    expect(translateClaudeSdkMessage({
      type: "assistant",
      uuid: "msg-unknown",
      error: "token=secret",
      message: { content: [] },
    })).toEqual([
      {
        sourceId: "msg-unknown:error",
        payload: { type: "error", code: "claude_provider_error", retryable: false },
      },
    ]);
  });

  it("translates tool progress without exposing raw provider fields", () => {
    expect(translateClaudeSdkMessage({
      type: "tool_progress",
      uuid: "msg-2",
      tool_use_id: "tool-1",
      tool_name: "Read",
      elapsed_time_seconds: 4,
    })).toEqual([
      { sourceId: "msg-2:progress", payload: { type: "progress", message: "Read (4s)" } },
    ]);
  });

  it("translates successful results into usage then completed status", () => {
    expect(translateClaudeSdkMessage({
      type: "result",
      subtype: "success",
      uuid: "msg-3",
      is_error: false,
      total_cost_usd: 0.12,
      usage: {
        input_tokens: 10,
        output_tokens: 5,
        cache_read_input_tokens: 2,
        cache_creation_input_tokens: 1,
      },
    })).toEqual([
      {
        sourceId: "msg-3:usage",
        payload: {
          type: "usage",
          usage: {
            native: [
              { unit: "input_tokens", value: 10 },
              { unit: "output_tokens", value: 5 },
              { unit: "cache_read_input_tokens", value: 2 },
              { unit: "cache_creation_input_tokens", value: 1 },
            ],
            cost: { provenance: "reported", amount: 0.12, currency: "USD" },
          },
        },
      },
      { sourceId: "msg-3:status", payload: { type: "status", status: "completed" } },
    ]);
  });

  it("translates error results into a sanitized error and failed status", () => {
    expect(translateClaudeSdkMessage({
      type: "result",
      subtype: "error_during_execution",
      uuid: "msg-4",
      is_error: true,
      total_cost_usd: 0,
      usage: {},
      errors: ["token=secret"],
    })).toEqual([
      {
        sourceId: "msg-4:usage",
        payload: {
          type: "usage",
          usage: { native: [], cost: { provenance: "reported", amount: 0, currency: "USD" } },
        },
      },
      {
        sourceId: "msg-4:error",
        payload: { type: "error", code: "error_during_execution", retryable: false },
      },
      { sourceId: "msg-4:status", payload: { type: "status", status: "failed" } },
    ]);
  });

  it("drops malformed and unsupported messages", () => {
    expect(translateClaudeSdkMessage({ type: "assistant", uuid: "msg-5", message: {} })).toEqual([]);
    expect(translateClaudeSdkMessage({ type: "tool_progress", uuid: "msg-6", tool_name: "Read" })).toEqual([]);
    expect(translateClaudeSdkMessage({ type: "status", uuid: "msg-7" })).toEqual([]);
    expect(translateClaudeSdkMessage({ type: "result", subtype: "success", uuid: "" })).toEqual([]);
    expect(translateClaudeSdkMessage(null)).toEqual([]);
    expect(translateClaudeSdkMessage({
      type: "assistant",
      uuid: "x".repeat(129),
      message: { content: [{ type: "text", text: "hidden" }] },
    })).toEqual([]);
    expect(translateClaudeSdkMessage({
      type: "assistant",
      uuid: "msg-\n-injection",
      message: { content: [{ type: "text", text: "hidden" }] },
    })).toEqual([]);
    expect(translateClaudeSdkMessage({
      type: "assistant",
      uuid: "msg-\u2028-injection",
      message: { content: [{ type: "text", text: "hidden" }] },
    })).toEqual([]);
  });

  it("wraps translated messages with run identity and contiguous sequences", async () => {
    const messages = (async function* () {
      yield { type: "assistant", uuid: "msg-8", message: { content: [{ type: "text", text: "hello" }] } };
      yield { type: "result", subtype: "success", uuid: "msg-9", is_error: false, usage: {} };
    })();
    const events = [];
    for await (const event of translateClaudeSdkStream(messages, "run-1")) events.push(event);
    expect(events).toEqual([
      { runId: "run-1", eventId: "claude:msg-8:text:0", sequence: 1, payload: { type: "text", text: "hello" } },
      { runId: "run-1", eventId: "claude:msg-9:usage", sequence: 2, payload: { type: "usage", usage: { native: [], cost: { provenance: "unavailable" } } } },
      { runId: "run-1", eventId: "claude:msg-9:status", sequence: 3, payload: { type: "status", status: "completed" } },
    ]);
  });

  it("rejects an invalid run identity before consuming provider messages", async () => {
    const messages = (async function* () {
      yield* [];
      throw new Error("provider stream should not be consumed");
    })();
    await expect((async () => {
      for await (const _event of translateClaudeSdkStream(messages, "bad\nrun")) { /* no-op */ }
    })()).rejects.toThrowError("claude_run_id_invalid");
  });
});
