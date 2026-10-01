import { describe, expect, it, vi } from "vitest";
import { createReviewedEngineAdapter } from "@/server/agent-engine-adapter-factory";
import { createEngineRegistry } from "@/server/agent-engine-registry";
import type { EngineSelection } from "@/server/agent-engine-contract";

const qualifiedSelection: EngineSelection = {
  engineId: "grok-build",
  authMode: "managed",
  operation: "new-run",
  workflow: "interactive",
  dataClass: "synthetic",
  requiredCapabilities: ["streaming"],
  now: 1_800_000_000_000,
};

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

  it("can resolve an enabled future engine from an injected reviewed registry", () => {
    const future = {} as never;
    const registry = createEngineRegistry([{
      id: "grok-build",
      version: "grok-build-v1",
      transport: "remote",
      enabledForNewRuns: true,
      enabledForExistingRuns: true,
      authModes: ["managed"],
      qualifications: [],
    }]);

    expect(createReviewedEngineAdapter(
      "grok-build",
      { "grok-build": () => future },
      "new-run",
      registry,
    )).toBe(future);
  });

  it("requires a qualified selection when one is supplied", () => {
    const future = {} as never;
    const registry = createEngineRegistry([{
      id: "grok-build",
      version: "grok-build-v1",
      transport: "remote",
      enabledForNewRuns: true,
      enabledForExistingRuns: true,
      authModes: ["managed"],
      qualifications: [{
        authMode: "managed",
        adapterVersion: "grok-build-v1",
        workflow: "interactive",
        dataClass: "synthetic",
        expiresAt: qualifiedSelection.now + 60_000,
        evidenceRef: "qualification/grok-synthetic",
        capabilities: { streaming: "verified" },
      }],
    }]);
    expect(createReviewedEngineAdapter(
      "grok-build",
      { "grok-build": () => future },
      "new-run",
      registry,
      qualifiedSelection,
    )).toBe(future);

    expect(() => createReviewedEngineAdapter(
      "grok-build",
      { "grok-build": () => future },
      "new-run",
      registry,
      { ...qualifiedSelection, dataClass: "customer" },
    )).toThrowError("engine_unqualified");
  });

  it("fails closed when qualification is requested from a get-only registry", () => {
    const registry = { get: createEngineRegistry([{
      id: "grok-build",
      version: "grok-build-v1",
      transport: "remote",
      enabledForNewRuns: true,
      enabledForExistingRuns: true,
      authModes: ["managed"],
      qualifications: [],
    }]).get };
    expect(() => createReviewedEngineAdapter(
      "grok-build",
      { "grok-build": () => ({} as never) },
      "new-run",
      registry,
      qualifiedSelection,
    )).toThrowError("engine_qualification_unavailable");
  });

  it("rejects a selection whose operation differs from the factory operation", () => {
    const registry = createEngineRegistry([{
      id: "grok-build",
      version: "grok-build-v1",
      transport: "remote",
      enabledForNewRuns: true,
      enabledForExistingRuns: true,
      authModes: ["managed"],
      qualifications: [],
    }]);
    expect(() => createReviewedEngineAdapter(
      "grok-build",
      { "grok-build": () => ({} as never) },
      "existing-run",
      registry,
      qualifiedSelection,
    )).toThrowError("engine_selection_operation_mismatch");
  });
});
