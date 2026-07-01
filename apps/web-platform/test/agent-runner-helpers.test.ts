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

import { mkdirSync, mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";

vi.mock("@/server/agent-env", () => ({
  buildAgentEnv: vi.fn(() => ({ ANTHROPIC_API_KEY: "sk-test" })),
}));
vi.mock("@/server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => async () => ({})),
}));

import { buildAgentQueryOptions } from "@/server/agent-runner-query-options";

// The filesystem `denyRead` is now computed per-dispatch from a live
// `readdirSync(WORKSPACES_ROOT)` (per-sibling deny — #5733 follow-up, PR
// #5848's `allowRead` re-bind made the workspace read-only). These tests
// stub `WORKSPACES_ROOT` to a real temp fixture (own + two siblings) so the
// enumeration is deterministic. Focused enumerator unit + fail-closed tests
// live in `agent-sandbox-sibling-deny.test.ts`.
describe("buildAgentSandboxConfig drift guard", () => {
  let root: string;
  let own: string;
  let sibA: string;
  let sibB: string;

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "sbx-drift-"));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    sibA = join(root, "00000000-0000-0000-0000-0000000000a1");
    sibB = join(root, "00000000-0000-0000-0000-0000000000b2");
    mkdirSync(own);
    mkdirSync(sibA);
    mkdirSync(sibB);
    vi.stubEnv("WORKSPACES_ROOT", root);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
  });

  it("matches the canonical non-filesystem shape verbatim (T17)", () => {
    const result = buildAgentSandboxConfig(own);
    // Non-filesystem fields are static and must stay byte-identical.
    expect(result.enabled).toBe(true);
    expect(result.failIfUnavailable).toBe(true);
    expect(result.autoAllowBashIfSandboxed).toBe(true);
    expect(result.allowUnsandboxedCommands).toBe(false);
    expect(result.enableWeakerNestedSandbox).toBe(true);
    expect(result.network).toEqual({
      allowedDomains: [],
      allowManagedDomainsOnly: true,
    });
    // filesystem: write own; deny every sibling + /proc; NO allowRead key.
    expect(result.filesystem.allowWrite).toEqual([own]);
    expect(result.filesystem).not.toHaveProperty("allowRead");
    expect(result.filesystem.denyRead).toEqual(
      expect.arrayContaining([sibA, sibB, "/proc"]),
    );
  });

  it("threads the workspacePath into filesystem.allowWrite (per-user write isolation)", () => {
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.allowWrite).toEqual([own]);
  });

  // #5733 core fix: the agent's OWN workspace must be READ+WRITE, so it must
  // NOT appear in denyRead (a broad `/workspaces` deny `--tmpfs`-obscures it,
  // and the SDK's only post-tmpfs re-allow — `allowRead` — is read-only and
  // shadows the write bind; PR #5848 shipped exactly that read-only regression).
  it("does NOT deny the agent's own workspace (own stays read+write)", () => {
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.denyRead).not.toContain(own);
    expect(result.filesystem.allowWrite).toContain(own);
    // No allowRead re-bind — it is the read-only shadow that broke writes.
    expect(result.filesystem).not.toHaveProperty("allowRead");
  });

  // Security invariant: every OTHER tenant workspace is denied. A broad-only
  // deny (or a missing sibling) would let the agent `cat` a sibling's repo via
  // Bash (the runtime `createSandboxHook` containment covers file-tools, NOT
  // Bash — so bwrap denyRead is the sole guard for that vector).
  it("denies every sibling workspace + /proc (cross-tenant isolation)", () => {
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.denyRead).toContain(sibA);
    expect(result.filesystem.denyRead).toContain(sibB);
    expect(result.filesystem.denyRead).toContain("/proc");
  });

  it("denyRead tracks the live sibling set (per-dispatch, not constant)", () => {
    const a = buildAgentSandboxConfig(own);
    // A new tenant appears before the next dispatch → it must be denied too.
    const sibC = join(root, "00000000-0000-0000-0000-0000000000c3");
    mkdirSync(sibC);
    const b = buildAgentSandboxConfig(own);
    expect(a.filesystem.denyRead).not.toContain(sibC);
    expect(b.filesystem.denyRead).toContain(sibC);
  });

  it("network is locked down — no allowed domains, managed-only", () => {
    const result = buildAgentSandboxConfig(own);
    expect(result.network.allowedDomains).toEqual([]);
    expect(result.network.allowManagedDomainsOnly).toBe(true);
  });
});

describe("buildAgentSandboxConfig — GitHub egress variant (#5041 follow-up)", () => {
  let root: string;
  let own: string;
  let sibA: string;

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "sbx-egress-"));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    sibA = join(root, "00000000-0000-0000-0000-0000000000a1");
    mkdirSync(own);
    mkdirSync(sibA);
    vi.stubEnv("WORKSPACES_ROOT", root);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
  });

  it("allowGithubEgress: true → exact-host GitHub allowlist; egress widens NOTHING else", () => {
    const result = buildAgentSandboxConfig(own, { allowGithubEgress: true });
    expect(result.network).toEqual({
      allowedDomains: ["github.com", "api.github.com"],
      allowManagedDomainsOnly: true,
    });
    // Filesystem is unchanged by the egress flag.
    expect(result.filesystem.allowWrite).toEqual([own]);
    expect(result.filesystem).not.toHaveProperty("allowRead");
    expect(result.filesystem.denyRead).toEqual(
      expect.arrayContaining([sibA, "/proc"]),
    );
  });

  it("allowGithubEgress: false → locked down, identical to the default call", () => {
    const explicit = buildAgentSandboxConfig(own, { allowGithubEgress: false });
    expect(explicit.network.allowedDomains).toEqual([]);
    expect(explicit).toEqual(buildAgentSandboxConfig(own));
  });

  it("returns a fresh allowedDomains array per call (frozen const must not leak)", () => {
    const a = buildAgentSandboxConfig(own, { allowGithubEgress: true });
    const b = buildAgentSandboxConfig(own, { allowGithubEgress: true });
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
