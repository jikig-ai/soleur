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

  it("wraps events with the bound run and contiguous sequences", async () => {
    const messages = (async function* () {
      yield { method: "item/agentMessage/delta", params: { itemId: "item-3", delta: "hi" } };
      yield { method: "turn/completed", params: { turnId: "turn-2", status: "completed" } };
    })();
    const events = [];
    for await (const event of translateCodexAppServerStream(messages, "run-1")) events.push(event);
    expect(events).toEqual([
      { runId: "run-1", eventId: "codex:item:item-3:delta", sequence: 1, payload: { type: "text", text: "hi" } },
      { runId: "run-1", eventId: "codex:turn:turn-2:status", sequence: 2, payload: { type: "status", status: "completed" } },
    ]);
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
    expect(translateCodexPersistedItem({ type: "commandExecution", id: "item-6", command: "git status", status: "completed" })).toEqual([]);
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
