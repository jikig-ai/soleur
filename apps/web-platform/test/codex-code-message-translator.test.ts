import { describe, expect, it } from "vitest";
import {
  translateCodexAppServerEvent,
  translateCodexAppServerStream,
  translateCodexPersistedItem,
  translateCodexPersistedTurn,
  createCodexReplayEvent,
} from "@/server/codex-code-message-translator";

describe("Codex App Server event translator", () => {
  it("translates agent message deltas into neutral text events", () => {
    expect(translateCodexAppServerEvent({
      method: "item/agentMessage/delta",
      params: { itemId: "item-1", delta: "hello" },
    })).toEqual([
      { sourceId: "item:item-1:delta", payload: { type: "text", text: "hello" } },
    ]);
  });

  it("translates command approval requests without exposing protocol fields", () => {
    expect(translateCodexAppServerEvent({
      method: "item/commandExecution/requestApproval",
      params: { itemId: "item-2", reason: "Needs review", command: "git status" },
    })).toEqual([
      {
        sourceId: "approval:item-2",
        payload: { type: "approval", requestId: "item-2", tool: "command", description: "Needs review" },
      },
    ]);
  });

  it("preserves token usage and terminal status separately", () => {
    expect(translateCodexAppServerEvent({
      method: "turn/completed",
      params: {
        turnId: "turn-1",
        status: "completed",
        usage: { inputTokens: 10, outputTokens: 5, totalCostUsd: 0.04 },
      },
    })).toEqual([
      {
        sourceId: "turn:turn-1:usage",
        payload: {
          type: "usage",
          usage: {
            native: [{ unit: "input_tokens", value: 10 }, { unit: "output_tokens", value: 5 }],
            cost: { provenance: "reported", amount: 0.04, currency: "USD" },
          },
        },
      },
      { sourceId: "turn:turn-1:status", payload: { type: "status", status: "completed" } },
    ]);
  });

  it("accepts the v2 App Server turn envelope observed in live qualification", () => {
    expect(translateCodexAppServerEvent({
      method: "turn/completed",
      params: { threadId: "thread-1", turn: { id: "turn-1", status: "completed", items: [] } },
    })).toEqual([
      { sourceId: "turn:turn-1:status", payload: { type: "status", status: "completed" } },
    ]);
  });

  it("emits the final per-turn usage snapshot once before terminal status", async () => {
    const messages = (async function* () {
      yield { method: "turn/started", params: { threadId: "thread-1", turn: { id: "turn-1", status: "inProgress", items: [] } } };
      yield { method: "thread/tokenUsage/updated", params: { threadId: "thread-1", turnId: "turn-1", tokenUsage: { last: { inputTokens: 4, outputTokens: 1 }, total: { inputTokens: 4, outputTokens: 1 } } } };
      yield { method: "thread/tokenUsage/updated", params: { threadId: "thread-1", turnId: "turn-1", tokenUsage: { last: { inputTokens: 8, outputTokens: 3 }, total: { inputTokens: 8, outputTokens: 3 } } } };
      yield { method: "turn/completed", params: { threadId: "thread-1", turn: { id: "turn-1", status: "completed", items: [] } } };
    })();
    const events = [];
    for await (const event of translateCodexAppServerStream(messages, "run-live")) events.push(event);
    expect(events).toEqual([
      { runId: "run-live", eventId: "codex:turn:turn-1:status:1", sequence: 1, payload: { type: "status", status: "running" } },
      { runId: "run-live", eventId: "codex:turn:turn-1:usage:2", sequence: 2, payload: { type: "usage", usage: { native: [{ unit: "input_tokens", value: 8 }, { unit: "output_tokens", value: 3 }], cost: { provenance: "unavailable" } } } },
      { runId: "run-live", eventId: "codex:turn:turn-1:status:3", sequence: 3, payload: { type: "status", status: "completed" } },
    ]);
  });

  it("rejects an unsafe v2 turn identity", async () => {
    const messages = (async function* () {
      yield { method: "turn/completed", params: { threadId: "thread-1", turn: { id: "bad\nturn", status: "completed", items: [] } } };
    })();
    await expect((async () => {
      for await (const _event of translateCodexAppServerStream(messages, "run-live")) { /* no-op */ }
    })()).rejects.toThrowError("codex_message_invalid");
  });

  it("fails closed on malformed token usage instead of sending misleading totals", async () => {
    const messages = (async function* () {
      yield { method: "thread/tokenUsage/updated", params: { threadId: "thread-1", turnId: "turn-1", tokenUsage: { last: { inputTokens: -1, outputTokens: 2 } } } };
    })();
    await expect((async () => {
      for await (const _event of translateCodexAppServerStream(messages, "run-live")) { /* no-op */ }
    })()).rejects.toThrowError("codex_usage_invalid");
  });

  it("wraps events with the bound run and contiguous sequences", async () => {
    const messages = (async function* () {
      yield { method: "item/agentMessage/delta", params: { itemId: "item-3", delta: "hi" } };
      yield { method: "turn/completed", params: { turnId: "turn-2", status: "completed" } };
    })();
    const events = [];
    for await (const event of translateCodexAppServerStream(messages, "run-1")) events.push(event);
    expect(events).toEqual([
      { runId: "run-1", eventId: "codex:item:item-3:delta:1", sequence: 1, payload: { type: "text", text: "hi" } },
      { runId: "run-1", eventId: "codex:turn:turn-2:status:2", sequence: 2, payload: { type: "status", status: "completed" } },
    ]);
  });

  it("assigns unique live event IDs across repeated deltas and turn status changes", async () => {
    const messages = (async function* () {
      yield { method: "turn/started", params: { threadId: "thread-1", turn: { id: "turn-1", status: "inProgress" } } };
      yield { method: "item/agentMessage/delta", params: { itemId: "item-1", delta: "A" } };
      yield { method: "item/agentMessage/delta", params: { itemId: "item-1", delta: "B" } };
      yield { method: "turn/completed", params: { threadId: "thread-1", turn: { id: "turn-1", status: "completed" } } };
    })();
    const events = [];
    for await (const event of translateCodexAppServerStream(messages, "run-live")) events.push(event);
    expect(events).toHaveLength(4);
    expect(new Set(events.map((event) => event.eventId)).size).toBe(events.length);
  });

  it("fails closed when a recognized event has no safe identity", async () => {
    const messages = (async function* () {
      yield { method: "item/agentMessage/delta", params: { itemId: "bad\nitem", delta: "hidden" } };
    })();
    await expect((async () => {
      for await (const _event of translateCodexAppServerStream(messages, "run-2")) { /* no-op */ }
    })()).rejects.toThrowError("codex_message_invalid");
  });

  it("translates persisted agent messages without leaking provider item fields", () => {
    expect(translateCodexPersistedItem({
      type: "agentMessage",
      id: "item-4",
      text: "Persisted answer",
      phase: "final_answer",
      secret: "must-not-cross",
    })).toEqual([
      { sourceId: "item:item-4:message", payload: { type: "text", text: "Persisted answer" } },
    ]);
  });

  it("translates only approval-waiting persisted commands", () => {
    expect(translateCodexPersistedItem({
      type: "commandExecution",
      id: "item-5",
      command: "git status",
      status: "awaitingApproval",
      cwd: "/workspace",
    })).toEqual([
      {
        sourceId: "approval:item-5",
        payload: { type: "approval", requestId: "item-5", tool: "command", description: "git status" },
      },
    ]);
    expect(translateCodexPersistedItem({ type: "commandExecution", id: "item-6", command: "git status", status: "completed" })).toEqual([
      { sourceId: "command:item-6:status", payload: { type: "progress", message: "Command completed" } },
    ]);
  });

  it("translates persisted plan text into bounded progress", () => {
    expect(translateCodexPersistedItem({
      type: "plan",
      id: "plan-1",
      text: "1. Inspect the repository\\n2. Run focused tests",
      review: "must-not-cross",
    })).toEqual([
      {
        sourceId: "plan:plan-1",
        payload: { type: "progress", message: "1. Inspect the repository\\n2. Run focused tests" },
      },
    ]);
    expect(translateCodexPersistedItem({ type: "plan", id: "plan-2" })).toEqual([]);
  });

  it("reduces persisted file changes to metadata progress without exposing paths or diffs", () => {
    expect(translateCodexPersistedItem({
      type: "fileChange",
      id: "change-1",
      status: "completed",
      changes: [{ path: "/workspace/secret.ts", kind: "update", diff: "private" }],
    })).toEqual([
      {
        sourceId: "file-change:change-1",
        payload: { type: "progress", message: "File changes recorded (1)" },
      },
    ]);
    expect(translateCodexPersistedItem({ type: "fileChange", id: "change-2", changes: "malformed" })).toEqual([]);
  });

  it("replays command outcomes as status metadata without stdout or stderr", () => {
    expect(translateCodexPersistedItem({
      type: "commandExecution",
      id: "command-1",
      status: "completed",
      command: "cat secret.txt",
      aggregatedOutput: "private output",
    })).toEqual([
      {
        sourceId: "command:command-1:status",
        payload: { type: "progress", message: "Command completed" },
      },
    ]);
    expect(translateCodexPersistedItem({
      type: "commandExecution",
      id: "command-2",
      status: "failed",
      exitCode: 1,
    })).toEqual([
      {
        sourceId: "command:command-2:status",
        payload: { type: "progress", message: "Command failed" },
      },
    ]);
  });

  it("replays MCP tool outcomes as status metadata without connector data", () => {
    expect(translateCodexPersistedItem({
      type: "mcpToolCall",
      id: "mcp-1",
      server: "private-server",
      tool: "lookup",
      status: "completed",
      arguments: { email: "person@example.com" },
      result: { secret: "private" },
    })).toEqual([
      {
        sourceId: "mcp:mcp-1:status",
        payload: { type: "progress", message: "MCP tool completed" },
      },
    ]);
    expect(translateCodexPersistedItem({ type: "mcpToolCall", id: "mcp-2", status: "failed", error: "private" })).toEqual([
      {
        sourceId: "mcp:mcp-2:status",
        payload: { type: "progress", message: "MCP tool failed" },
      },
    ]);
  });

  it("replays dynamic tool outcomes as status metadata without tool payloads", () => {
    expect(translateCodexPersistedItem({
      type: "dynamicToolCall",
      id: "dynamic-1",
      tool: "private_tool",
      status: "completed",
      arguments: { token: "private" },
      contentItems: [{ text: "private result" }],
    })).toEqual([
      {
        sourceId: "dynamic:dynamic-1:status",
        payload: { type: "progress", message: "Dynamic tool completed" },
      },
    ]);
    expect(translateCodexPersistedItem({ type: "dynamicToolCall", id: "dynamic-2", status: "failed" })).toEqual([
      {
        sourceId: "dynamic:dynamic-2:status",
        payload: { type: "progress", message: "Dynamic tool failed" },
      },
    ]);
  });

  it("replays collaboration tool outcomes without cross-thread payloads", () => {
    expect(translateCodexPersistedItem({
      type: "collabToolCall",
      id: "collab-1",
      tool: "delegate",
      status: "completed",
      senderThreadId: "thread-private",
      prompt: "private prompt",
    })).toEqual([
      {
        sourceId: "collab:collab-1:status",
        payload: { type: "progress", message: "Collaboration tool completed" },
      },
    ]);
    expect(translateCodexPersistedItem({ type: "collabToolCall", id: "collab-2", status: "failed", receiverThreadId: "private" })).toEqual([
      {
        sourceId: "collab:collab-2:status",
        payload: { type: "progress", message: "Collaboration tool failed" },
      },
    ]);
  });

  it("replays review-mode lifecycle without review instructions or findings", () => {
    expect(translateCodexPersistedItem({
      type: "enteredReviewMode",
      id: "review-1",
      review: "private review target",
    })).toEqual([
      {
        sourceId: "review:review-1:started",
        payload: { type: "progress", message: "Review started" },
      },
    ]);
    expect(translateCodexPersistedItem({
      type: "exitedReviewMode",
      id: "review-1",
      review: "private findings",
    })).toEqual([
      {
        sourceId: "review:review-1:completed",
        payload: { type: "progress", message: "Review completed" },
      },
    ]);
  });

  it("replays context compaction as bounded metadata without reasoning content", () => {
    expect(translateCodexPersistedItem({
      type: "contextCompaction",
      id: "compact-1",
      summary: "private reasoning summary",
      input: "private context",
    })).toEqual([
      {
        sourceId: "compaction:compact-1",
        payload: { type: "progress", message: "Context compacted" },
      },
    ]);
    expect(translateCodexPersistedItem({ type: "contextCompaction", id: "bad\ncompaction" })).toEqual([]);
  });

  it("replays web-search activity without queries or action details", () => {
    expect(translateCodexPersistedItem({
      type: "webSearch",
      id: "search-1",
      query: "private customer lookup",
      action: { type: "openPage", url: "https://private.example.test" },
    })).toEqual([
      {
        sourceId: "web-search:search-1",
        payload: { type: "progress", message: "Web search recorded" },
      },
    ]);
    expect(translateCodexPersistedItem({ type: "webSearch", id: "bad\nsearch" })).toEqual([]);
  });

  it("replays image-view activity without filesystem paths or image content", () => {
    expect(translateCodexPersistedItem({
      type: "imageView",
      id: "image-1",
      path: "/workspace/private/customer.png",
      content: "private pixels",
    })).toEqual([
      {
        sourceId: "image-view:image-1",
        payload: { type: "progress", message: "Image view recorded" },
      },
    ]);
    expect(translateCodexPersistedItem({ type: "imageView", id: "bad\nimage", path: "/private.png" })).toEqual([]);
  });

  it("replays function-call output activity without tool identity or output", () => {
    expect(translateCodexPersistedItem({
      type: "functionCallOutput",
      id: "output-1",
      name: "private_tool",
      namespace: "private_namespace",
      output: "private result",
    })).toEqual([
      {
        sourceId: "function-output:output-1",
        payload: { type: "progress", message: "Function output recorded" },
      },
    ]);
    expect(translateCodexPersistedItem({ type: "functionCallOutput", id: "bad\noutput", output: "must fail" })).toEqual([]);
  });

  it("replays user-message activity without content or attachments", () => {
    expect(translateCodexPersistedItem({
      type: "userMessage",
      id: "user-1",
      content: [{ type: "text", text: "private customer request" }, { type: "image", imageUrl: "private" }],
      attachments: [{ id: "attachment-private" }],
    })).toEqual([
      {
        sourceId: "user-message:user-1",
        payload: { type: "progress", message: "User input recorded" },
      },
    ]);
    expect(translateCodexPersistedItem({ type: "userMessage", id: "bad\nuser", content: [] })).toEqual([]);
  });

  it("translates persisted turn status and usage with bounded identities", () => {
    expect(translateCodexPersistedTurn({
      id: "turn-3",
      status: "completed",
      usage: { inputTokens: 3, outputTokens: 2, totalCostUsd: 0.01 },
    })).toEqual([
      {
        sourceId: "turn:turn-3:usage",
        payload: {
          type: "usage",
          usage: {
            native: [{ unit: "input_tokens", value: 3 }, { unit: "output_tokens", value: 2 }],
            cost: { provenance: "reported", amount: 0.01, currency: "USD" },
          },
        },
      },
      { sourceId: "turn:turn-3:status", payload: { type: "status", status: "completed" } },
    ]);
    expect(translateCodexPersistedTurn({ id: "turn\n3", status: "completed" })).toEqual([]);
  });

  it("wraps already-translated replay events with the same neutral stream contract", async () => {
    const messages = (async function* () {
      yield createCodexReplayEvent({
        sourceId: "item:item-7:message",
        payload: { type: "text", text: "replayed" },
      });
    })();
    const events = [];
    for await (const event of translateCodexAppServerStream(messages, "run-3")) events.push(event);
    expect(events).toEqual([
      { runId: "run-3", eventId: "codex:item:item-7:message", sequence: 1, payload: { type: "text", text: "replayed" } },
    ]);
  });
});
