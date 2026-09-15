import { describe, expect, it, vi } from "vitest";
import { createEngineObservability } from "@/server/agent-engine-observability";

describe("engine observability", () => {
  it("emits lifecycle names with safe binding metadata only", () => {
    const sink = vi.fn();
    const observability = createEngineObservability(sink);
    observability.emit("engine_dispatch_started", {
      engineId: "codex",
      workspaceId: "workspace-1",
      conversationId: "conversation-1",
      adapterVersion: "codex-v1",
    });
    expect(sink).toHaveBeenCalledWith("engine_dispatch_started", {
      engineId: "codex",
      workspaceId: "workspace-1",
      conversationId: "conversation-1",
      adapterVersion: "codex-v1",
    });
    expect(sink.mock.calls[0][1]).not.toHaveProperty("text");
    expect(sink.mock.calls[0][1]).not.toHaveProperty("accessToken");
  });

  it("never lets a logging failure break dispatch", () => {
    const observability = createEngineObservability(() => { throw new Error("sink unavailable"); });
    expect(() => observability.emit("engine_dispatch_failed", { engineId: "codex" })).not.toThrow();
  });

  it("accepts replay-drop telemetry without provider payload metadata", () => {
    const sink = vi.fn();
    const observability = createEngineObservability(sink);
    observability.emit("engine_replay_item_dropped", {
      engineId: "codex",
      itemType: "reasoning",
      reason: "unsupported_item",
    });
    expect(sink).toHaveBeenCalledWith("engine_replay_item_dropped", {
      engineId: "codex",
      itemType: "reasoning",
      reason: "unsupported_item",
    });
    expect(sink.mock.calls[0][1]).not.toHaveProperty("content");
    expect(sink.mock.calls[0][1]).not.toHaveProperty("output");
  });

  it("accepts replay-failure telemetry with a stable failure class", () => {
    const sink = vi.fn();
    const observability = createEngineObservability(sink);
    observability.emit("engine_replay_failed", {
      engineId: "codex",
      failureClass: "page_invalid",
    });
    expect(sink).toHaveBeenCalledWith("engine_replay_failed", {
      engineId: "codex",
      failureClass: "page_invalid",
    });
  });
});
