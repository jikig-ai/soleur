import { describe, expect, it } from "vitest";
import { assertLegacyConversationEngineBinding, assertLegacyEngineBinding } from "@/server/agent-engine-route-guard";

describe("legacy engine route guard", () => {
  it("accepts only the default Claude binding", () => {
    expect(() => assertLegacyEngineBinding({ engineId: "claude-code" })).not.toThrow();
    expect(() => assertLegacyEngineBinding({ engine_id: "claude-code" })).not.toThrow();
  });

  it("fails closed for a persisted Codex binding instead of falling back", () => {
    expect(() => assertLegacyEngineBinding({ engineId: "codex" })).toThrowError(
      expect.objectContaining({ code: "engine_dispatch_required" }),
    );
  });

  it("fails closed for malformed persisted state", () => {
    expect(() => assertLegacyEngineBinding(null)).toThrowError(
      expect.objectContaining({ code: "engine_binding_invalid" }),
    );
  });
});

describe("existing conversation engine route guard", () => {
  it("rejects a Codex-bound resumed conversation before legacy dispatch", async () => {
    const repository = {
      getConversationRun: async () => ({ binding: { engineId: "codex" } }),
      getConversationBindingState: async () => "bound",
    };
    await expect(assertLegacyConversationEngineBinding(repository, "conv-1")).rejects.toMatchObject({
      code: "engine_dispatch_required",
    });
  });

  it("does not read the marker when a binding row is present", async () => {
    let markerReads = 0;
    await expect(assertLegacyConversationEngineBinding({
      getConversationRun: async () => ({ binding: { engineId: "claude-code" } }),
      getConversationBindingState: async () => { markerReads += 1; return "bound"; },
    }, "conv-bound")).resolves.toBeUndefined();
    expect(markerReads).toBe(0);
  });

  it("allows a persisted Claude binding and a conversation predating engine bindings", async () => {
    await expect(assertLegacyConversationEngineBinding(
      {
        getConversationRun: async () => ({ binding: { engineId: "claude-code" } }),
        getConversationBindingState: async () => "bound",
      }, "conv-1",
    )).resolves.toBeUndefined();
    await expect(assertLegacyConversationEngineBinding(
      { getConversationRun: async () => null, getConversationBindingState: async () => "legacy" }, "old-conv",
    )).resolves.toBeUndefined();
  });

  it("propagates binding lookup failures", async () => {
    await expect(assertLegacyConversationEngineBinding(
      {
        getConversationRun: async () => { throw new Error("db_down"); },
        getConversationBindingState: async () => "legacy",
      }, "conv-1",
    )).rejects.toThrow("db_down");
  });

  it("fails closed when a modern conversation has no binding yet", async () => {
    await expect(assertLegacyConversationEngineBinding({
      getConversationRun: async () => null,
      getConversationBindingState: async () => "pending",
    }, "conv-pending")).rejects.toMatchObject({ code: "engine_binding_invalid" });
  });
});
