import { describe, expect, it } from "vitest";
import { assertLegacyEngineBinding } from "@/server/agent-engine-route-guard";

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
