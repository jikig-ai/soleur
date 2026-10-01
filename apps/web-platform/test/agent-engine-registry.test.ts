import { describe, expect, it } from "vitest";
import {
  createEngineRegistry,
  EngineEligibilityError,
} from "@/server/agent-engine-registry";
import type { EngineDefinition, EngineSelection } from "@/server/agent-engine-contract";

const now = 1_800_000_000_000;

function definition(overrides: Partial<EngineDefinition> = {}): EngineDefinition {
  return {
    id: "codex",
    version: "test-version",
    transport: "local",
    enabledForNewRuns: true,
    enabledForExistingRuns: true,
    authModes: ["api-key", "chatgpt"],
    qualifications: ["api-key", "chatgpt"].map((authMode) => ({
      authMode,
      adapterVersion: "test-version",
      workflow: "interactive",
      dataClass: "synthetic",
      expiresAt: now + 60_000,
      evidenceRef: "qualification/synthetic-test",
      capabilities: { "platform-tools": "verified", approvals: "verified" },
    })),
    ...overrides,
  };
}

function selection(overrides: Partial<EngineSelection> = {}): EngineSelection {
  return {
    engineId: "codex",
    authMode: "api-key",
    operation: "new-run",
    workflow: "interactive",
    dataClass: "synthetic",
    requiredCapabilities: ["platform-tools", "approvals"],
    now,
    ...overrides,
  };
}

describe("reviewed engine registry", () => {
  it("exposes a cloned definition for settings validation without authorizing execution", () => {
    const registry = createEngineRegistry([definition({ id: "claude-code" })]);
    const first = registry.get("claude-code");
    expect(first.id).toBe("claude-code");
    expect(first).not.toBe(registry.get("claude-code"));
    expect(() => registry.get("missing-engine")).toThrow("engine_unknown");
  });

  it.each(["api-key", "chatgpt"])("selects the requested Codex auth mode: %s", (authMode) => {
    const registry = createEngineRegistry([definition()]);
    expect(registry.resolve(selection({ authMode })).id).toBe("codex");
  });

  it("supports a fourth engine through registration alone", () => {
    const registry = createEngineRegistry([definition({ id: "future-engine", transport: "remote" })]);
    expect(registry.resolve(selection({ engineId: "future-engine" })).transport).toBe("remote");
  });

  it("refuses an unknown engine even when another qualified engine is available", () => {
    const registry = createEngineRegistry([definition({ id: "claude-code" })]);
    expect(() => registry.resolve(selection())).toThrow(EngineEligibilityError);
    expect(() => registry.resolve(selection())).toThrow("engine_unknown");
  });

  it.each(["", "../codex", "Codex", "codex\n", "constructor", "__proto__"])(
    "rejects malformed or reserved registry IDs: %s", (id) => {
      expect(() => createEngineRegistry([definition({ id })])).toThrow();
    },
  );

  it("rejects duplicate registration instead of replacing the first adapter", () => {
    expect(() => createEngineRegistry([definition(), definition()])).toThrow("engine_duplicate");
  });

  it("distinguishes stopping new runs from disabling existing runs", () => {
    const registry = createEngineRegistry([definition({ enabledForNewRuns: false })]);
    expect(() => registry.resolve(selection())).toThrow("engine_disabled");
    expect(registry.resolve(selection({ operation: "existing-run" })).id).toBe("codex");
    const disabled = createEngineRegistry([definition({ enabledForExistingRuns: false })]);
    expect(() => disabled.resolve(selection({ operation: "existing-run" }))).toThrow("engine_disabled");
  });

  it("does not reuse API-key qualification for ChatGPT sign-in", () => {
    const d = definition();
    const registry = createEngineRegistry([definition({ qualifications: d.qualifications.slice(0, 1) })]);
    expect(() => registry.resolve(selection({ authMode: "chatgpt" }))).toThrow("engine_unqualified");
  });

  it("does not switch auth mode when the selected mode is unavailable", () => {
    const registry = createEngineRegistry([definition({ authModes: ["chatgpt"] })]);
    expect(() => registry.resolve(selection())).toThrow("engine_auth_unsupported");
  });

  it("synthetic approval does not authorize customer content", () => {
    const registry = createEngineRegistry([definition()]);
    expect(() => registry.resolve(selection({ dataClass: "customer" }))).toThrow("engine_unqualified");
  });

  it("rejects stale evidence and evidence for another adapter version", () => {
    const registry = createEngineRegistry([definition()]);
    expect(() => registry.resolve(selection({ now: now + 60_000 }))).toThrow("engine_unqualified");
    const upgraded = createEngineRegistry([definition({ version: "new-version" })]);
    expect(() => upgraded.resolve(selection())).toThrow("engine_unqualified");
  });

  it("restricts a remote engine to the qualified workflow and verified capabilities", () => {
    const d = definition();
    const registry = createEngineRegistry([definition({ transport: "remote", qualifications: d.qualifications.map((q) => ({
      ...q, workflow: "repository-summary", capabilities: { artifacts: "verified", approvals: "supported" },
    })) })]);
    expect(registry.resolve(selection({ workflow: "repository-summary", requiredCapabilities: ["artifacts"] })).id).toBe("codex");
    expect(() => registry.resolve(selection())).toThrow("engine_unqualified");
    expect(() => registry.resolve(selection({ workflow: "repository-summary", requiredCapabilities: ["approvals"] }))).toThrow("engine_capability_missing");
  });

  it("does not combine capability evidence from incompatible qualification records", () => {
    const d = definition();
    const base = d.qualifications[0];
    const registry = createEngineRegistry([definition({ qualifications: [
      { ...base, capabilities: { approvals: "verified" } },
      { ...base, capabilities: { "platform-tools": "verified" } },
    ] })]);
    expect(() => registry.resolve(selection())).toThrow("engine_capability_missing");
  });

  it("copies registration so caller mutation cannot change eligibility", () => {
    const d = definition();
    const registry = createEngineRegistry([d]);
    d.enabledForNewRuns = false;
    d.qualifications[0].capabilities.approvals = "unsupported";
    expect(registry.resolve(selection()).id).toBe("codex");
  });
});
