// Drift-guard for `buildAgentSandboxConfig` — the helper extracted from
// the prior inline `sandbox: {...}` block at the `agent-runner.ts`
// `query({ options })` call site. Two consumers (legacy domain-leader
// runner + cc-soleur-go `realSdkQueryFactory`) MUST receive an
// identical shape, except for the token-derived `network.allowedDomains`
// (#5041 follow-up — the cc path widens egress iff an entitled GH token
// was minted). If a field is silently dropped here, both consumers
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
        allowRead: [workspacePath],
      },
    });
  });

  it("threads the workspacePath into filesystem.allowWrite (per-user write isolation)", () => {
    const result = buildAgentSandboxConfig("/workspaces/alice");
    expect(result.filesystem.allowWrite).toEqual(["/workspaces/alice"]);
  });

  // #5733 — the agent bwrap sandbox tmpfs-obscures the whole `/workspaces`
  // tree via `denyRead`, and `allowWrite` grants WRITE only (SDK semantics:
  // reading within a denyRead region requires `allowRead`, which "takes
  // precedence over denyRead"). Without an explicit read carve-out the agent
  // cannot `git rev-parse`/`ls` its OWN repo → the "not a git repository"
  // strand (Sentry WEB-PLATFORM-46, gitKind=dir-valid, gitRevParseValid=false).
  // The re-allow must be the agent's own workspacePath so it survives the
  // `/workspaces` parent-deny.
  it("re-allows READ of the agent's own workspace within the /workspaces denyRead region (#5733)", () => {
    const result = buildAgentSandboxConfig("/workspaces/alice");
    expect(result.filesystem.allowRead).toEqual(["/workspaces/alice"]);
  });

  // Security invariant: the read carve-out must be EXACTLY the agent's own
  // workspace — never the whole `/workspaces` tree — so sibling tenants'
  // `/workspaces/<other>` stay tmpfs-hidden. `allowRead` re-binds only the
  // listed path; a broader entry would breach cross-tenant isolation.
  it("allowRead re-allows ONLY the caller's workspace, not the /workspaces root (cross-tenant isolation)", () => {
    const result = buildAgentSandboxConfig("/workspaces/alice");
    expect(result.filesystem.allowRead).not.toContain("/workspaces");
    expect(result.filesystem.allowRead).toEqual(["/workspaces/alice"]);
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

describe("buildAgentSandboxConfig — GitHub egress variant (#5041 follow-up)", () => {
  it("allowGithubEgress: true → exact-host GitHub allowlist, all other fields canonical", () => {
    const workspacePath = "/tmp/test-workspace";
    const result = buildAgentSandboxConfig(workspacePath, {
      allowGithubEgress: true,
    });

    // Canonical-literal style (same as T17): every non-network field must
    // stay byte-identical to the locked-down profile — egress widens the
    // domain allowlist and NOTHING else.
    expect(result).toEqual({
      enabled: true,
      failIfUnavailable: true,
      autoAllowBashIfSandboxed: true,
      allowUnsandboxedCommands: false,
      enableWeakerNestedSandbox: true,
      network: {
        allowedDomains: ["github.com", "api.github.com"],
        allowManagedDomainsOnly: true,
      },
      filesystem: {
        allowWrite: [workspacePath],
        denyRead: ["/workspaces", "/proc"],
        allowRead: [workspacePath],
      },
    });
  });

  it("allowGithubEgress: false → locked down, identical to the default call", () => {
    const explicit = buildAgentSandboxConfig("/tmp/x", {
      allowGithubEgress: false,
    });
    expect(explicit.network.allowedDomains).toEqual([]);
    expect(explicit).toEqual(buildAgentSandboxConfig("/tmp/x"));
  });

  it("returns a fresh allowedDomains array per call (frozen const must not leak)", () => {
    const a = buildAgentSandboxConfig("/tmp/x", { allowGithubEgress: true });
    const b = buildAgentSandboxConfig("/tmp/x", { allowGithubEgress: true });
    expect(a.network.allowedDomains).not.toBe(b.network.allowedDomains);
  });
});

describe("buildAgentQueryOptions drift guard (legacy ↔ cc — #2922)", () => {
  const baseArgs = {
    workspacePath: "/tmp/test-workspace",
    pluginPath: "/tmp/test-workspace/plugins/soleur",
    credential: { value: "sk-test", scheme: "api_key" as const },
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
