import { describe, expect, it, vi } from "vitest";
import { composeReviewedEngineFactories } from "@/server/agent-engine-adapter-composition";

describe("reviewed adapter composition", () => {
  it("composes Claude and Codex factories without selecting an engine", () => {
    const claude = {} as never;
    const codex = {} as never;
    const factories = composeReviewedEngineFactories({
      claudeTransport: {} as never,
      codexTransport: {} as never,
      codexAuth: {} as never,
      createClaude: () => claude,
      createCodex: () => codex,
    });
    expect(factories["claude-code"]!()).toBe(claude);
    expect(factories.codex!()).toBe(codex);
  });

  it("omits Codex when its auth/transport dependencies are unavailable", () => {
    const factories = composeReviewedEngineFactories({ claudeTransport: {} as never, createClaude: vi.fn(() => ({} as never)) });
    expect(factories.codex).toBeUndefined();
  });

  it("registers a future engine through an additive factory map", () => {
    const grok = {} as never;
    const factories = composeReviewedEngineFactories({
      additionalFactories: { "grok-build": () => grok },
    });
    expect(factories["grok-build"]!()).toBe(grok);
  });
});
