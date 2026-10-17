import { describe, expect, it } from "vitest";
import { createCodexWebEventMapper, mapCodexEngineEventToWsMessage } from "@/server/codex-ws-events";
import type { EngineEvent } from "@/server/agent-engine-contract";
import { translateCodexAppServerStream, createCodexReplayEvent, translateCodexPersistedItem } from "@/server/codex-code-message-translator";
import { applyStreamEvent } from "@/lib/chat-state-machine";

describe("Codex Web cumulative text", () => {
  const options = { leaderId: "cc_router" as const, conversationId: "synthetic-conversation" };
  const text = (eventId: string, value: string): EngineEvent => ({
    runId: "synthetic-run", eventId, sequence: 1, payload: { type: "text", text: value },
  });

  function render(chunks: Array<[string, string]>) {
    const map = createCodexWebEventMapper(options);
    let result = applyStreamEvent([], new Map(), { type: "stream_start", leaderId: "cc_router" });
    for (const [eventId, value] of chunks) {
      const frame = map(text(eventId, value));
      if (frame.type !== "stream") throw new Error("unexpected synthetic text frame");
      result = applyStreamEvent(result.messages, result.activeStreams, frame);
    }
    return result.messages.at(-1);
  }

  it("renders complete interleaved answers without inventing reasoning steps", () => {
    const answer = render([
      ["codex:item:synthetic:a:delta:1", "One "],
      ["codex:item:synthetic:b:delta:2", "Two "],
      ["codex:item:synthetic:a:delta:3", "answer"],
    ]);
    expect(answer?.content).toBe("One answer\n\nTwo ");
    expect(answer?.activity ?? []).toEqual([]);
  });

  it("retains a long second answer when an earlier item continues", () => {
    const second = "Synthetic detail ".repeat(24) + "\nRetained second paragraph.";
    const answer = render([
      ["codex:item:synthetic:a:delta:1", "First "],
      ["codex:item:synthetic:b:delta:2", second],
      ["codex:item:synthetic:a:delta:3", "answer"],
    ]);
    expect(answer?.content).toBe("First answer\n\n" + second);
    expect(answer?.activity ?? []).toEqual([]);
  });

  it("replays each answer item without losing its neighbors or creating narration", () => {
    const answer = render([
      ["codex:item:synthetic:a:delta:1", "Old first"],
      ["codex:item:synthetic:b:delta:2", "Old second"],
      ["codex:item:synthetic:a:message", "Complete first"],
      ["codex:item:synthetic:b:message", "Complete second"],
      ["codex:item:synthetic:a:message", "Complete first"],
      ["codex:item:synthetic:a:delta:3", "!"],
    ]);
    expect(answer?.content).toBe("Complete first!\n\nComplete second");
    expect(answer?.activity ?? []).toEqual([]);
  });

  it("converts translated deltas to snapshots without false reasoning steps", async () => {
    const map = createCodexWebEventMapper(options);
    const native = (async function* () {
      yield { method: "turn/started", params: { turnId: "synthetic-turn" } };
      for (const delta of ["Hello ", "world"]) {
        yield { method: "item/agentMessage/delta", params: { itemId: "synthetic-item", delta } };
      }
    })();
    let result = applyStreamEvent([], new Map(), { type: "stream_start", leaderId: "cc_router" });
    for await (const event of translateCodexAppServerStream(native, "synthetic-run")) {
      const frame = map(event);
      if (frame.type === "stream") result = applyStreamEvent(result.messages, result.activeStreams, frame);
    }
    expect(result.messages.at(-1)).toMatchObject({ content: "Hello world" });
    expect(result.messages.at(-1)?.activity ?? []).toEqual([]);
  });

  it("keeps interleaved items separate, including identities containing colons", () => {
    const map = createCodexWebEventMapper(options);
    map(text("codex:item:synthetic:a:delta:1", "One "));
    expect(map(text("codex:item:synthetic:b:delta:2", "Two "))).toMatchObject({ content: "One \n\nTwo " });
    expect(map(text("codex:item:synthetic:a:delta:3", "answer"))).toMatchObject({ content: "One answer\n\nTwo " });
  });

  it("replaces replay snapshots and seeds subsequent fragments without duplication", async () => {
    const map = createCodexWebEventMapper(options);
    map(text("codex:item:synthetic-item:delta:1", "Old "));
    const replay = createCodexReplayEvent(translateCodexPersistedItem({
      type: "agentMessage", id: "synthetic-item", text: "Full answer",
    })[0]);
    for await (const event of translateCodexAppServerStream((async function* () { yield replay; })(), "synthetic-run")) {
      expect(map(event)).toMatchObject({ content: "Full answer" });
      expect(map(event)).toMatchObject({ content: "Full answer" });
    }
    expect(map(text("codex:item:synthetic-item:delta:3", "!"))).toMatchObject({ content: "Full answer!" });
  });

  it("preserves snapshot semantics for injected neutral events and isolates mapper instances", () => {
    const first = createCodexWebEventMapper(options);
    first(text("codex:item:synthetic-item:delta:1", "First"));
    expect(first(text("synthetic-neutral-event", "Snapshot"))).toMatchObject({ content: "Snapshot" });
    expect(createCodexWebEventMapper(options)(text("codex:item:synthetic-item:delta:1", "Next"))).toMatchObject({ content: "Next" });
  });

  it("clears retained fragments after terminal lifecycle events", () => {
    const map = createCodexWebEventMapper(options);
    map(text("codex:item:synthetic-item:delta:1", "Prior"));
    map({ runId: "synthetic-run", eventId: "synthetic-end", sequence: 2, payload: { type: "status", status: "completed" } });
    expect(map(text("codex:item:synthetic-item:delta:3", "Next"))).toMatchObject({ content: "Next" });
  });

  it("bounds aggregate UTF-8 bytes across items and allows an exact-boundary replacement", () => {
    const map = createCodexWebEventMapper(options);
    expect(map(text("codex:item:synthetic-item:message", "é".repeat(128 * 1024)))).toMatchObject({ content: "é".repeat(128 * 1024) });
    expect(() => map(text("codex:item:synthetic-other:delta:2", "a"))).toThrow("codex_web_text_limit");
    map(text("codex:item:synthetic-item:message", "short"));
    expect(map(text("codex:item:synthetic-other:delta:3", "a"))).toMatchObject({ content: "short\n\na" });
  });

  it("bounds item count without evicting earlier answer fragments", () => {
    const map = createCodexWebEventMapper(options);
    for (let i = 0; i < 32; i++) map(text(`codex:item:synthetic-${i}:delta:${i + 1}`, "a"));
    expect(() => map(text("codex:item:synthetic-overflow:delta:33", "b"))).toThrow("codex_web_text_limit");
    expect(map(text("codex:item:synthetic-0:delta:34", "b"))).toMatchObject({ content: ["ab", ...Array<string>(31).fill("a")].join("\n\n") });
  });
});

describe("Codex websocket event mapping", () => {
  it("maps lifecycle and text events without exposing provider data", () => {
    const options = { leaderId: "cc_router" as const, conversationId: "conv-1" };
    expect(mapCodexEngineEventToWsMessage({ runId: "run-1", eventId: "e-1", sequence: 1, payload: { type: "status", status: "running" } }, options)).toEqual({ type: "stream_start", leaderId: "cc_router", conversationId: "conv-1" });
    expect(mapCodexEngineEventToWsMessage({ runId: "run-1", eventId: "e-2", sequence: 2, payload: { type: "text", text: "hello" } }, options)).toEqual({ type: "stream", content: "hello", partial: true, answerSnapshot: true, leaderId: "cc_router", conversationId: "conv-1" });
    expect(mapCodexEngineEventToWsMessage({ runId: "run-1", eventId: "e-3", sequence: 3, payload: { type: "status", status: "completed" } }, options)).toEqual({ type: "stream_end", leaderId: "cc_router", conversationId: "conv-1" });
  });

  it("maps approvals and failures to existing safe WS shapes", () => {
    const options = { leaderId: "cc_router" as const, conversationId: "conv-1" };
    expect(mapCodexEngineEventToWsMessage({ runId: "run-1", eventId: "e-4", sequence: 4, payload: { type: "approval", requestId: "req-1", tool: "shell", description: "run command" } }, options)).toEqual({ type: "tool_use", leaderId: "cc_router", label: "Approval required", conversationId: "conv-1" });
    expect(mapCodexEngineEventToWsMessage({ runId: "run-1", eventId: "e-5", sequence: 5, payload: { type: "error", code: "codex_provider_error", retryable: false } }, options)).toEqual({ type: "error", message: "Codex execution failed", conversationId: "conv-1" });
  });

  it("maps reported USD usage into the existing usage frame", () => {
    expect(mapCodexEngineEventToWsMessage({
      runId: "run-1", eventId: "e-6", sequence: 6,
      payload: { type: "usage", usage: { native: [{ unit: "input_tokens", value: 10 }, { unit: "output_tokens", value: 4 }], cost: { provenance: "reported", amount: 0.12, currency: "USD" } } },
    }, { leaderId: "cc_router", conversationId: "conv-1", workspaceId: "ws-1" })).toEqual({
      type: "usage_update", conversationId: "conv-1", workspaceId: "ws-1", totalCostUsd: 0.12, inputTokens: 10, outputTokens: 4,
    });
  });
});
