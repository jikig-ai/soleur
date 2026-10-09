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

import { existsSync, mkdirSync, mkdtempSync, rmSync } from "fs";
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
import { resolveWorkspaceMode } from "@/server/workspace-mode";

// The filesystem `denyRead` is a CONSTANT list — the broad parent deny
// `[WORKSPACES_ROOT, c4StagingRoot, "/proc", "/sys"]` (#5862, ADR-075 exit
// criterion; `/sys` joined the constant set under #1285):
// the vendored CLI 2.1.284 bwrap builder emits `--tmpfs <deny landing>` FIRST
// and then re-binds every covered `allowWrite`/`allowRead` path after it
// (deny-then-restore), so the parent tmpfs masks present AND future siblings
// while the agent's own workspace keeps read+write via the post-tmpfs
// `allowWrite` restore. No dispatch-time `readdirSync`, no per-sibling
// enumeration — a sibling created after the namespace build is never listed
// yet stays covered. Focused constant-deny tests live in
// `agent-sandbox-tenant-deny.test.ts`. These tests stub `WORKSPACES_ROOT` to a
// real temp fixture (own + two siblings) to prove the set is invariant under
// sibling creation.
describe("buildAgentSandboxConfig drift guard", () => {
  let root: string;
  let wtRoot: string;
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
    // #9725: the raw worktree root joins the deny set unconditionally — stub
    // it to a deterministic absent path so the verbatim denyRead assertions
    // can't drift with host env or a realpath alias.
    wtRoot = `${root}-worktrees`;
    vi.stubEnv("WORKTREE_ROOT", wtRoot);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
    // The C4 staging root sits BESIDE the workspaces root, never inside it
    // (inside, it would sit under the covering workspace deny — still denied,
    // but the dedicated staging tmpfs would be shadowed by the ws restore bind).
    rmSync(`${root}-c4-staging`, { recursive: true, force: true });
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
    // filesystem: write own; CONSTANT parent deny; NO allowRead key.
    expect(result.filesystem.allowWrite).toEqual([own]);
    expect(result.filesystem).not.toHaveProperty("allowRead");
    // EXACT list, order-pinned (#5862): the workspaces PARENT root + the C4
    // re-render staging root (#8623) + /proc + /sys (#1285) — the vendored
    // builder's deny-then-restore ordering re-binds `allowWrite` paths after
    // the covering `--tmpfs`, so own stays writable while the parent mask
    // hides every sibling (present or future). Order matters because the
    // emitted deny sequence maps to the builder's `--tmpfs` emission order; a
    // per-sibling entry here means enumeration crept back in — fail on either
    // drift.
    expect(result.filesystem.denyRead).toEqual([
      root,
      wtRoot,
      `${root}-c4-staging`,
      "/proc",
      "/sys",
    ]);
  });

  // #8623 Phase 0: the C4 re-render's staging root must be outside the agent's
  // write set AND denied for read, and it must EXIST before the sandbox starts
  // (the SDK silently skips a non-existent deny path).
  it("denies the C4 staging root, creates it, and never grants write to it or to os.tmpdir()", () => {
    const staging = `${root}-c4-staging`;
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.denyRead).toContain(staging);
    expect(existsSync(staging)).toBe(true);
    for (const w of result.filesystem.allowWrite) {
      expect(staging === w || staging.startsWith(`${w}/`)).toBe(false);
      expect(tmpdir() === w || tmpdir().startsWith(`${w}/`)).toBe(false);
    }
  });

  it("threads the workspacePath into filesystem.allowWrite (per-user write isolation)", () => {
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.allowWrite).toEqual([own]);
  });

  // #5733/#5862: the agent's OWN workspace sits UNDER the denied parent root —
  // that is correct, not a regression. The vendored CLI 2.1.284 builder emits
  // `--tmpfs <root>` FIRST and then re-binds every covered `allowWrite` path
  // read-write after it ("Re-bound write path wiped by denyRead tmpfs"), so the
  // parent mask cannot strand own the way PR #5848's read-only `allowRead`
  // re-bind did. What the config must NOT do is list `own` as its own denyRead
  // entry (a deny landing equal to own would leave nothing to restore into).
  it("covers the agent's own workspace via the parent deny (own restored rw by the vendor builder)", () => {
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.denyRead).toContain(root);
    // own is never an individual deny entry — the parent covers it.
    expect(result.filesystem.denyRead).not.toContain(own);
    expect(result.filesystem.allowWrite).toEqual([own]);
    // No allowRead re-bind on the default path — under deny-then-restore the
    // read-only restore is reserved for the support persona (below).
    expect(result.filesystem).not.toHaveProperty("allowRead");
  });

  // Security invariant: every OTHER tenant workspace is denied. Under the
  // constant parent deny the sibling paths are NOT individual entries — the
  // `--tmpfs <root>` covers the whole tree at namespace build (the runtime
  // `createSandboxHook` containment covers file-tools, NOT Bash — so bwrap
  // denyRead is the sole guard for that vector).
  it("denies every sibling workspace via the parent root + /proc (cross-tenant isolation)", () => {
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.denyRead).toContain(root);
    expect(result.filesystem.denyRead).toContain("/proc");
    // No per-sibling entries — enumeration is gone.
    expect(result.filesystem.denyRead).not.toContain(sibA);
    expect(result.filesystem.denyRead).not.toContain(sibB);
  });

  // The ADR-075 residual TOCTOU: under per-sibling enumeration a sibling
  // created between namespace builds stayed visible. With the constant parent
  // deny the emitted set cannot drift — and the parent tmpfs masks the new
  // sibling anyway, so coverage no longer depends on listing it.
  it("denyRead is CONSTANT — a sibling created between dispatches changes nothing (TOCTOU close)", () => {
    const a = buildAgentSandboxConfig(own);
    const sibC = join(root, "00000000-0000-0000-0000-0000000000c3");
    mkdirSync(sibC);
    const b = buildAgentSandboxConfig(own);
    expect(b.filesystem.denyRead).toEqual(a.filesystem.denyRead);
    // sibC is covered by the parent deny, never enumerated.
    expect(b.filesystem.denyRead).not.toContain(sibC);
    expect(b.filesystem.denyRead).toContain(root);
  });

  it("readOnly (support persona): allowWrite empties and allowRead restores the workspace read-only", () => {
    const result = buildAgentSandboxConfig(own, { readOnly: true });
    expect(result.filesystem.allowWrite).toEqual([]);
    // Under the covering parent deny the support session would lose its
    // workspace entirely without this restore — the vendor builder re-binds
    // `allowWithinDeny` paths `--ro-bind` after the tmpfs.
    expect(result.filesystem.allowRead).toEqual([own]);
    expect(result.filesystem.denyRead).toEqual([
      root,
      wtRoot,
      `${root}-c4-staging`,
      "/proc",
      "/sys",
    ]);
  });

  it("denyReadExtra entries append after the constant base, deduped", () => {
    const extra = join(root, "kb-internal");
    const result = buildAgentSandboxConfig(own, {
      denyReadExtra: [extra, "/proc"], // "/proc" duplicate must collapse
    });
    expect(result.filesystem.denyRead).toEqual([
      root,
      wtRoot,
      `${root}-c4-staging`,
      "/proc",
      "/sys",
      extra,
    ]);
  });

  it("network is locked down — no allowed domains, managed-only", () => {
    const result = buildAgentSandboxConfig(own);
    expect(result.network.allowedDomains).toEqual([]);
    expect(result.network.allowManagedDomainsOnly).toBe(true);
  });
});

// Expected signed-URL account fleet, generated locally (NOT imported from the
// source const) so a typo in the source list cannot self-verify: sa0..sa99
// minus sa22 (NXDOMAIN — see the docblock on GITHUB_ACTIONS_LOG_ACCOUNTS).
const EXPECTED_SA_ACCOUNTS = Array.from(
  { length: 100 },
  (_, i) => `productionresultssa${i}.blob.core.windows.net`,
).filter((h) => h !== "productionresultssa22.blob.core.windows.net");

describe("buildAgentSandboxConfig — GitHub egress variant (#5041 follow-up)", () => {
  let root: string;
  let own: string;
  let sibA: string;
  let wtRoot: string;

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "sbx-egress-"));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    sibA = join(root, "00000000-0000-0000-0000-0000000000a1");
    mkdirSync(own);
    mkdirSync(sibA);
    vi.stubEnv("WORKSPACES_ROOT", root);
    wtRoot = `${root}-worktrees`;
    vi.stubEnv("WORKTREE_ROOT", wtRoot);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
    // The C4 staging root sits BESIDE the workspaces root, never inside it
    // (inside, it would sit under the covering workspace deny — still denied,
    // but the dedicated staging tmpfs would be shadowed by the ws restore bind).
    rmSync(`${root}-c4-staging`, { recursive: true, force: true });
  });

  it("allowGithubEgress: true → GitHub + npm + Actions-blob allowlist; egress widens NOTHING else", () => {
    const result = buildAgentSandboxConfig(own, { allowGithubEgress: true });
    expect(result.network).toEqual({
      allowedDomains: [
        "github.com",
        "api.github.com",
        "registry.npmjs.org",
        ...EXPECTED_SA_ACCOUNTS,
      ],
      allowManagedDomainsOnly: true,
    });
    // Filesystem is unchanged by the egress flag.
    expect(result.filesystem.allowWrite).toEqual([own]);
    expect(result.filesystem).not.toHaveProperty("allowRead");
    // EXACT constant list — see the T17 guard rationale above.
    expect(result.filesystem.denyRead).toEqual([
      root,
      wtRoot,
      `${root}-c4-staging`,
      "/proc",
      "/sys",
    ]);
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
    mode: resolveWorkspaceMode("command_center"),
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
