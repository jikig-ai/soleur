import { describe, expect, it } from "vitest";
import { mapCodexEngineEventToWsMessage } from "@/server/codex-ws-events";

describe("Codex websocket event mapping", () => {
  it("maps lifecycle and text events without exposing provider data", () => {
    const options = { leaderId: "cc_router" as const, conversationId: "conv-1" };
    expect(mapCodexEngineEventToWsMessage({ runId: "run-1", eventId: "e-1", sequence: 1, payload: { type: "status", status: "running" } }, options)).toEqual({ type: "stream_start", leaderId: "cc_router" });
    expect(mapCodexEngineEventToWsMessage({ runId: "run-1", eventId: "e-2", sequence: 2, payload: { type: "text", text: "hello" } }, options)).toEqual({ type: "stream", content: "hello", partial: true, leaderId: "cc_router" });
    expect(mapCodexEngineEventToWsMessage({ runId: "run-1", eventId: "e-3", sequence: 3, payload: { type: "status", status: "completed" } }, options)).toEqual({ type: "stream_end", leaderId: "cc_router" });
  });

  it("maps approvals and failures to existing safe WS shapes", () => {
    const options = { leaderId: "cc_router" as const, conversationId: "conv-1" };
    expect(mapCodexEngineEventToWsMessage({ runId: "run-1", eventId: "e-4", sequence: 4, payload: { type: "approval", requestId: "req-1", tool: "shell", description: "run command" } }, options)).toEqual({ type: "tool_use", leaderId: "cc_router", label: "Approval required" });
    expect(mapCodexEngineEventToWsMessage({ runId: "run-1", eventId: "e-5", sequence: 5, payload: { type: "error", code: "codex_provider_error", retryable: false } }, options)).toEqual({ type: "error", message: "Codex execution failed" });
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
