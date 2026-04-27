// Drift-guard for `buildAgentSandboxConfig` — the helper extracted from
// the prior inline `sandbox: {...}` block at the `agent-runner.ts`
// `query({ options })` call site. Two consumers (legacy domain-leader
// runner + cc-soleur-go `realSdkQueryFactory`) MUST receive an
// identical shape. If a field is silently dropped here, both consumers
// regress to a wider sandbox profile in prod.
//
// Per plan T17 / AC3: assert verbatim deep-equality vs the canonical
// literal. Test uses `toEqual` (not `toBe`) — readonly-object identity
// differs across calls.
//
// See learning `2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md`
// for the helper-extraction risk class addressed by this test.
//
// Sibling drift-guard for `buildAgentQueryOptions` (#2922): asserts
// shared fields between legacy + cc args produce identical canonical
// shape, ignoring divergent per-call overrides (mcpServers,
// allowedTools, maxTurns, maxBudgetUsd).

import { describe, it, expect, vi } from "vitest";

import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";

vi.mock("@/server/agent-env", () => ({
  buildAgentEnv: vi.fn(() => ({ ANTHROPIC_API_KEY: "sk-test" })),
}));
vi.mock("@/server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => async () => ({})),
}));

import { buildAgentQueryOptions } from "@/server/agent-runner-query-options";

describe("buildAgentSandboxConfig drift guard", () => {
  it("matches the canonical inline shape verbatim (T17)", () => {
    const workspacePath = "/tmp/test-workspace";
    const result = buildAgentSandboxConfig(workspacePath);

    // Verbatim copy of the literal that lived at the prior
    // `agent-runner.ts` `query({ options: { sandbox: ... } })` call site.
    // A field drop in the helper trips this assertion.
    expect(result).toEqual({
      enabled: true,
      failIfUnavailable: true,
      autoAllowBashIfSandboxed: true,
      allowUnsandboxedCommands: false,
      enableWeakerNestedSandbox: true,
      network: {
        allowedDomains: [],
        allowManagedDomainsOnly: true,
      },
      filesystem: {
        allowWrite: [workspacePath],
        denyRead: ["/workspaces", "/proc"],
      },
    });
  });

  it("threads the workspacePath into filesystem.allowWrite (per-user write isolation)", () => {
    const result = buildAgentSandboxConfig("/workspaces/alice");
    expect(result.filesystem.allowWrite).toEqual(["/workspaces/alice"]);
  });

  it("filesystem.denyRead is constant across workspaces", () => {
    const a = buildAgentSandboxConfig("/workspaces/alice");
    const b = buildAgentSandboxConfig("/workspaces/bob");
    expect(a.filesystem.denyRead).toEqual(b.filesystem.denyRead);
    expect(a.filesystem.denyRead).toEqual(["/workspaces", "/proc"]);
  });

  it("network is locked down — no allowed domains, managed-only", () => {
    const result = buildAgentSandboxConfig("/tmp/x");
    expect(result.network.allowedDomains).toEqual([]);
    expect(result.network.allowManagedDomainsOnly).toBe(true);
  });
});

describe("buildAgentQueryOptions drift guard (legacy ↔ cc — #2922)", () => {
  const baseArgs = {
    workspacePath: "/tmp/test-workspace",
    pluginPath: "/tmp/test-workspace/plugins/soleur",
    apiKey: "sk-test",
    serviceTokens: {} as Record<string, string>,
    systemPrompt: "you are a router",
    canUseTool: (async () => ({
      behavior: "allow" as const,
      updatedInput: {},
    })) as never,
  };

  // Stable serialization across Node versions per plan Enhancement #2.
  function serializeShared(opts: Record<string, unknown>): string {
    const SHARED = [
      "cwd",
      "model",
      "permissionMode",
      "settingSources",
      "includePartialMessages",
      "disallowedTools",
    ] as const;
    const subset: Record<string, unknown> = {};
    for (const k of SHARED) subset[k] = opts[k];
    return JSON.stringify(subset, Object.keys(subset).sort());
  }

  it("legacy + cc produce identical shared-field shape", () => {
    const legacy = buildAgentQueryOptions({
      ...baseArgs,
      maxTurns: 50,
      maxBudgetUsd: 5.0,
      allowedTools: ["mcp__soleur_platform__kb_share_create"],
    });
    const cc = buildAgentQueryOptions({
      ...baseArgs,
      mcpServers: {},
    });
    expect(
      serializeShared(legacy as unknown as Record<string, unknown>),
    ).toBe(serializeShared(cc as unknown as Record<string, unknown>));
  });

  it("plugins, sandbox, hooks.PreToolUse keep identical shape across paths", () => {
    const legacy = buildAgentQueryOptions(baseArgs);
    const cc = buildAgentQueryOptions({ ...baseArgs, mcpServers: {} });
    expect(legacy.plugins).toEqual(cc.plugins);
    expect(legacy.sandbox).toEqual(cc.sandbox);
    // biome-ignore lint/style/noNonNullAssertion: shape verified by other tests
    expect(legacy.hooks!.PreToolUse![0].matcher).toBe(
      // biome-ignore lint/style/noNonNullAssertion: shape verified by other tests
      cc.hooks!.PreToolUse![0].matcher,
    );
  });
});
