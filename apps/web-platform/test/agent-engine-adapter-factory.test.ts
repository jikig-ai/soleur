import { describe, expect, it, vi } from "vitest";
import { createReviewedEngineAdapter } from "@/server/agent-engine-adapter-factory";

describe("reviewed engine adapter factory", () => {
  it("creates only enabled reviewed engines", () => {
    const claude = {} as never;
    expect(createReviewedEngineAdapter("claude-code", { "claude-code": () => claude })).toBe(claude);
    expect(() => createReviewedEngineAdapter("codex", { codex: vi.fn() })).toThrowError("engine_disabled");
  });

  it("fails closed for unknown engines and missing factories", () => {
    expect(() => createReviewedEngineAdapter("grok-build", {})).toThrowError("engine_unknown");
    expect(() => createReviewedEngineAdapter("claude-code", {})).toThrowError("adapter_unavailable");
  });
});
