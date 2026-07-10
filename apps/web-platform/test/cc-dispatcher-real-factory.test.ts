// RED/GREEN tests for the cc-soleur-go `realSdkQueryFactory` closure
// (replaces the prior `realSdkQueryFactoryStub`). Covers T1–T7
// (factory option shape) + T15 (leaderId attribution) + T16 (sandbox
// substring → agent-sandbox tag) + T18 (env shape) + T19 (KeyInvalidError
// sanitization).
//
// Mocks the SDK's `query` per the same pattern used in
// `agent-runner-kb-share-preview.test.ts` so the factory can be invoked
// with a fully-typed `QueryFactoryArgs` and the captured `options`
// asserted against the canonical shape.
//
// See plan §"Test Scenarios" — T1–T19. The Bash review-gate E2E (T12–T14)
// lives in a sibling file (`cc-dispatcher-bash-gate.test.ts`).

import { describe, it, expect, vi, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const {
  mockLogInfo,
  mockQuery,
  mockGetUserApiKey,
  mockGetUserServiceTokens,
  mockPatchWorkspacePermissions,
  mockReportSilentFallback,
  mockSendToClient,
  mockBuildAgentEnv,
  mockBuildAgentSandboxConfig,
  mockSupabaseFrom,
  mockResolveInstallationId,
  mockGenerateInstallationToken,
  mockResolveBashAutonomous,
  mockResolveAutonomousAck,
  mockResolveIsWorkspaceOwner,
  mockWriteAskpassScriptTo,
  mockCleanupAskpassScript,
  mockResolveActiveWorkspacePath,
  mockResolveActiveWorkspace,
  mockGetCurrentRepoUrl,
  mockGetCurrentRepoStatus,
  mockGetInstallationAccount,
  mockFindRepoOwnerInstallationForUser,
  mockEnsureWorkspaceRepoCloned,
} = vi.hoisted(() => ({
  mockLogInfo: vi.fn(),
  mockQuery: vi.fn(),
  mockGetUserApiKey: vi.fn(),
  mockGetUserServiceTokens: vi.fn(),
  mockPatchWorkspacePermissions: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockSendToClient: vi.fn(),
  mockBuildAgentEnv: vi.fn(),
  mockBuildAgentSandboxConfig: vi.fn(),
  mockSupabaseFrom: vi.fn(),
  mockResolveInstallationId: vi.fn(),
  mockGenerateInstallationToken: vi.fn(),
  mockResolveBashAutonomous: vi.fn(),
  mockResolveAutonomousAck: vi.fn(),
  mockResolveIsWorkspaceOwner: vi.fn(),
  mockWriteAskpassScriptTo: vi.fn(),
  mockCleanupAskpassScript: vi.fn(),
  mockResolveActiveWorkspacePath: vi.fn(),
  mockResolveActiveWorkspace: vi.fn(),
  mockGetCurrentRepoUrl: vi.fn(),
  mockGetCurrentRepoStatus: vi.fn(),
  mockGetInstallationAccount: vi.fn(),
  mockFindRepoOwnerInstallationForUser: vi.fn(),
  // Hoisted to a named spy (was an inline anonymous vi.fn) so the
  // installation-id the clone receives is inspectable — the load-bearing
  // assertion for the clone-consumes-self-healed-install fix.
  mockEnsureWorkspaceRepoCloned: vi.fn(async () => undefined),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  // Drift-guard for #3250: `realSdkQueryFactory` calls `getSessionMessages`
  // when `args.resumeSessionId` is set. Returning `[]` keeps the guard's
  // empty-history branch from blocking these tests and matches the
  // behavior asserted by the prefill-guard test file's empty-history
  // scenario.
  getSessionMessages: vi.fn().mockResolvedValue([]),
  // Return inspectable shapes so the soleur_platform always-build assertion
  // (#5370 T2) can read tool names off the registered server. `tool(name,…)`
  // → `{ name }`; `createSdkMcpServer(cfg)` → cfg (passthrough).
  tool: vi.fn((name: string) => ({ name })),
  createSdkMcpServer: vi.fn((cfg: unknown) => cfg),
}));

vi.mock("@/server/agent-runner", () => ({
  getUserApiKey: mockGetUserApiKey,
  getUserServiceTokens: mockGetUserServiceTokens,
  patchWorkspacePermissions: mockPatchWorkspacePermissions,
}));

vi.mock("@/server/agent-runner-sandbox-config", () => ({
  buildAgentSandboxConfig: mockBuildAgentSandboxConfig,
}));

vi.mock("@/server/agent-env", () => ({
  buildAgentEnv: mockBuildAgentEnv,
}));

vi.mock("@/server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => async () => ({})),
}));

// Issue A — Concierge gh-auth. Default to "no connected repo" (null) so the
// pre-existing factory-shape tests dispatch with no GH_TOKEN; the dedicated
// describe block below drives the connected + mint-failure paths.
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: mockResolveInstallationId,
}));

// feat-one-shot-concierge-gh-403 self-heal: the heal is driven entirely by the
// GitHub App JWT path (getInstallationAccount + findRepoOwnerInstallationForUser)
// — NO Supabase service-role. Pre-existing factory-shape tests run with
// getCurrentRepoUrl=null so the self-heal branch never fires; the dedicated
// describe block drives it.
vi.mock("@/server/github-app", () => ({
  generateInstallationToken: mockGenerateInstallationToken,
  getInstallationAccount: mockGetInstallationAccount,
  findRepoOwnerInstallationForUser: mockFindRepoOwnerInstallationForUser,
}));

// Plan item 1 — cc-dispatcher now imports the in-sandbox askpass writer from
// git-auth. MUST be mocked here AND in cc-dispatcher-prefill-guard.test.ts or
// the cold-start suite throws on import (Phase 0.4 sweep).
// #5394 — keep the pure sanitizers real (repo-readiness.ts consumes
// parseErrorPayload + sanitizeGitStderr for the error-branch gate); override
// only the askpass writers (the in-sandbox FS side effects).
vi.mock("@/server/git-auth", async () => {
  const actual =
    await vi.importActual<typeof import("@/server/git-auth")>(
      "@/server/git-auth",
    );
  return {
    ...actual,
    writeAskpassScriptTo: mockWriteAskpassScriptTo,
    cleanupAskpassScript: mockCleanupAskpassScript,
  };
});

// Issue B part 2 — autonomous toggle. Default off (false) so factory-shape
// tests dispatch with the review-gate intact.
vi.mock("@/server/resolve-bash-autonomous", () => ({
  resolveBashAutonomous: mockResolveBashAutonomous,
}));

// feat-bash-autonomous-default-on — first-run consent soft-gate inputs. Default
// ack=null + owner=false so factory-shape tests dispatch with the review-gate
// intact (un-acked non-owner ⇒ not the soft-gate path).
vi.mock("@/server/resolve-autonomous-ack", () => ({
  resolveAutonomousAck: mockResolveAutonomousAck,
}));
vi.mock("@/server/resolve-workspace-owner", () => ({
  resolveIsWorkspaceOwner: mockResolveIsWorkspaceOwner,
}));

// Session-start ensure-repo self-heal (cold-path deps). Default no-op so the
// factory-shape tests are unaffected.
// ADR-044: fetchUserWorkspacePath now resolves the ACTIVE workspace via
// resolveActiveWorkspacePath. Override only that export (importActual keeps the
// rest of workspace-resolver real for any other consumer cc-dispatcher pulls).
vi.mock("@/server/workspace-resolver", async () => {
  const actual = await vi.importActual<typeof import("@/server/workspace-resolver")>(
    "@/server/workspace-resolver",
  );
  return {
    ...actual,
    resolveActiveWorkspacePath: mockResolveActiveWorkspacePath,
    // ADR-044 PR-1: the factory resolves this directly before the Promise.all.
    resolveActiveWorkspace: mockResolveActiveWorkspace,
  };
});

vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: mockGetCurrentRepoUrl,
  getCurrentRepoStatus: mockGetCurrentRepoStatus,
}));
vi.mock("@/server/ensure-workspace-repo", () => ({
  ensureWorkspaceRepoCloned: mockEnsureWorkspaceRepoCloned,
  // Unconditional pre-sandbox dir guarantee — no-op here (these tests assert
  // option shape, not real dir existence). The dedicated invariant coverage
  // lives in cc-dispatcher-warm-presandbox-mkdir.test.ts (real mkdir).
  ensureWorkspaceDirExists: vi.fn(async () => undefined),
}));
// #5733 D2 — these tests assert SDK-binding / mint / egress shape on a fixture
// workspace path (`/tmp/cc-test-workspace`) that has no on-disk `.git`. D2 now
// honest-blocks an absent `.git` at the cold dispatch gate, so force the
// git-shape readiness to a ready dir-valid here (these tests do NOT exercise the
// readiness gate — that is owned by cc-dispatcher-repo-gate.test.ts +
// agent-ready-git-worktree.test.ts).
vi.mock("@/server/git-worktree-validity", async (orig) => {
  const actual = (await orig()) as Record<string, unknown>;
  return {
    ...actual,
    probeGitWorktreeShape: () => ({ kind: "dir-valid" }),
    isReadyGitWorkTree: () => true,
    isValidGitWorkTree: () => true,
    evaluateAgentReadiness: async () => "ready",
  };
});

vi.mock("@/server/permission-callback", () => ({
  // The factory composes a canUseTool from this — we capture the ctx
  // passed in via the spy returned here.
  createCanUseTool: vi.fn(() => async () => ({ behavior: "allow" })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
  // #5733 — reportAgentReadinessSelfStop pre-hashes the workspace id via hashUserId.
  hashUserId: (s: string) => `hash-${s}`,
  // #3369: mirrorWithDebounce extracted to observability.
  // These dispatcher tests do not exercise the debounce TTL, so
  // the stub forwards every call straight through to the spy.
  mirrorWithDebounce: mockReportSilentFallback,
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockSupabaseFrom })),
}));

// PR-C §2.4 / §2.10 / §2.11 (#3244): tenant migration of conversation-
// writer + agent-runner + cc-dispatcher (BYOK lease wrap). Mock so the
// test does not pull `mintFounderJwt` or the lease's `fetchAndDecrypt`
// chain.
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockSupabaseFrom })),
  mintFounderJwt: vi.fn(),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/server/byok-lease", async () => {
  const actual = await vi.importActual<typeof import("@/server/byok-lease")>(
    "@/server/byok-lease",
  );
  return {
    ...actual,
    // Bridge legacy `mockGetUserApiKey` setups (which used to mock the
    // direct `getUserApiKey()` call in cc-dispatcher pre-PR-C) to the
    // new `lease.getApiKey()` surface. Tests that
    // `mockResolvedValue("sk-test")` / `mockRejectedValueOnce(KeyInvalidError)`
    // continue to drive the same code path.
    runWithByokLease: vi.fn(
      async <T>(
        args: { workspaceContextUserId: string; keyOwnerUserId: string },
        body: (lease: {
          workspaceContextUserId: string;
          keyOwnerUserId: string;
          getRestApiKey: () => string | Promise<string>;
          getAgentCredential: () => Promise<{ value: string; scheme: "api_key" | "oauth_token" }>;
        }) => Promise<T>,
      ) =>
        body({
          workspaceContextUserId: args.workspaceContextUserId,
          keyOwnerUserId: args.keyOwnerUserId,
          // cc-dispatcher is an Agent-SDK consumer → getAgentCredential.
          // Bridge the legacy mockGetUserApiKey value/rejection into the
          // new { value, scheme } shape (scheme=api_key for these tests).
          getRestApiKey: () => mockGetUserApiKey(),
          getAgentCredential: async () => ({
            value: await mockGetUserApiKey(),
            scheme: "api_key" as const,
          }),
        }),
    ),
  };
});

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

vi.mock("@/server/ws-handler", () => ({
  sendToClient: mockSendToClient,
}));

// `info` routes to the shared hoisted spy so the egress-posture log payload
// is assertable (AC6-class: boolean only, never the token). Filter by
// message string in assertions — every module's child logger shares it.
vi.mock("@/server/logger", () => ({
  default: { info: mockLogInfo, error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: mockLogInfo,
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

vi.mock("@/server/notifications", () => ({ notifyOfflineUser: vi.fn() }));

import { realSdkQueryFactory } from "@/server/cc-dispatcher";
import { createCanUseTool } from "@/server/permission-callback";

// Helper: build a fake Query that the SDK mock returns.
function makeFakeQuery() {
  return {
    async *[Symbol.asyncIterator]() {
      // No messages — factory tests only assert the options shape.
    },
    close: vi.fn().mockResolvedValue(undefined),
    interrupt: vi.fn().mockResolvedValue(undefined),
    setPermissionMode: vi.fn().mockResolvedValue(undefined),
    setModel: vi.fn().mockResolvedValue(undefined),
    supportedCommands: vi.fn().mockResolvedValue([]),
    supportedModels: vi.fn().mockResolvedValue([]),
    mcpServerStatus: vi.fn().mockResolvedValue([]),
    next: vi.fn(),
    return: vi.fn(),
    throw: vi.fn(),
    // biome-ignore lint/suspicious/noExplicitAny: SDK Query stub
  } as any;
}

/**
 * The factory is now a real `async (args) => Promise<Query>`. Tests
 * await it directly — no proxy/deferred-build flush needed.
 */

const WORKSPACE_PATH = "/tmp/cc-test-workspace";

function setupSupabaseMockReturning(
  workspacePath: string | null = WORKSPACE_PATH,
) {
  // ADR-044: the workspace path is resolved via resolveActiveWorkspacePath
  // (active workspace), not the users.workspace_path read. A null workspacePath
  // models the legacy "not provisioned" throw the factory's error path expects.
  if (workspacePath) {
    mockResolveActiveWorkspacePath.mockResolvedValue(workspacePath);
  } else {
    mockResolveActiveWorkspacePath.mockRejectedValue(
      new Error("Workspace not provisioned"),
    );
  }
  mockSupabaseFrom.mockImplementation((table: string) => {
    if (table === "users") {
      return {
        select: () => ({
          eq: () => ({
            single: () => ({
              data: workspacePath ? { workspace_path: workspacePath } : null,
              error: workspacePath ? null : new Error("not found"),
            }),
            maybeSingle: () => ({
              data: workspacePath ? { workspace_path: workspacePath } : null,
              error: workspacePath ? null : new Error("not found"),
            }),
          }),
        }),
      };
    }
    return {
      select: () => ({ eq: () => ({ single: () => ({ data: null, error: null }) }) }),
      insert: () => ({ error: null }),
      update: () => ({ eq: () => ({ error: null }) }),
    };
  });
}

function makeArgs(overrides: Partial<Parameters<typeof realSdkQueryFactory>[0]> = {}) {
  // biome-ignore lint/suspicious/noExplicitAny: minimal AsyncIterable stub
  const promptStream = {
    async *[Symbol.asyncIterator]() {},
  } as any;
  return {
    prompt: promptStream,
    systemPrompt: "system",
    pluginPath: "/ignored", // factory recomputes from workspacePath
    cwd: "/ignored", // factory uses workspacePath
    userId: "user-1",
    conversationId: "conv-1",
    persona: "command_center" as const,
    ...overrides,
  };
}

describe("realSdkQueryFactory — cc-soleur-go SDK binding", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUserApiKey.mockResolvedValue("sk-test");
    mockGetUserServiceTokens.mockResolvedValue({});
    mockBuildAgentEnv.mockReturnValue({ ANTHROPIC_API_KEY: "sk-test" });
    mockBuildAgentSandboxConfig.mockReturnValue({
      enabled: true,
      failIfUnavailable: true,
      autoAllowBashIfSandboxed: true,
      allowUnsandboxedCommands: false,
      enableWeakerNestedSandbox: true,
      network: { allowedDomains: [], allowManagedDomainsOnly: true },
      filesystem: {
        allowWrite: [WORKSPACE_PATH],
        denyRead: ["/workspaces", "/proc"],
      },
    });
    mockQuery.mockReturnValue(makeFakeQuery());
    // Issue A defaults: no connected repo (null) → no mint, no GH_TOKEN.
    mockResolveInstallationId.mockResolvedValue(null);
    mockGenerateInstallationToken.mockResolvedValue("ghs_default_test_token");
    mockResolveBashAutonomous.mockResolvedValue(false);
    mockResolveAutonomousAck.mockResolvedValue(null);
    mockResolveIsWorkspaceOwner.mockResolvedValue(false);
    // ADR-044 PR-1: default to the solo workspace (= userId). Dispatch-path
    // tests that need a team/reset id override per-case.
    mockResolveActiveWorkspace.mockImplementation(async (userId: string) => ({
      ok: true,
      workspaceId: userId,
    }));
    // feat-one-shot-concierge-gh-403 self-heal defaults: no connected repo so
    // the self-heal branch is skipped for every pre-existing test. The
    // dedicated describe block overrides these per-test.
    mockGetCurrentRepoUrl.mockResolvedValue(null);
    // #5394 — default repo readiness is `ready` so the gate never blocks the
    // pre-existing factory-shape tests; the dedicated gate describe overrides it.
    mockGetCurrentRepoStatus.mockResolvedValue({
      repoStatus: "ready",
      repoError: null,
    });
    mockGetInstallationAccount.mockResolvedValue({ login: "owner", id: 1, type: "Organization" });
    mockFindRepoOwnerInstallationForUser.mockResolvedValue({ installationId: null, outcome: "not-member" });
    // Item 1 — in-sandbox askpass writer returns a deterministic path under
    // the workspace (the real writer uses a randomUUID suffix).
    mockWriteAskpassScriptTo.mockReturnValue(
      `${WORKSPACE_PATH}/.askpass-fixed-test.sh`,
    );
    setupSupabaseMockReturning(WORKSPACE_PATH);
  });

  // -------------------------------------------------------------------------
  // T1: factory called with valid user → returns Query
  // -------------------------------------------------------------------------
  it("T1: invokes SDK query() once with cwd=workspacePath and the canonical model", async () => {
    await realSdkQueryFactory(makeArgs());

    expect(mockQuery).toHaveBeenCalledOnce();
    const callArg = mockQuery.mock.calls[0][0];
    expect(callArg.options.cwd).toBe(WORKSPACE_PATH);
    expect(callArg.options.model).toBe("claude-sonnet-5");
  });

  // -------------------------------------------------------------------------
  // T2: factory options omit / empty mcpServers (V1; V2-13 widens)
  // -------------------------------------------------------------------------
  it("T2: soleur_platform server is ALWAYS built with narrate/summarize (#5370)", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    // feat-reasoning-chat-boxes (#5370): the soleur_platform server is now
    // built unconditionally so the always-on narrate/summarize tools are
    // reachable on every cc dispatch (was empty for V1; the C4 write tool is
    // still flag+repo-gated and merged into the SAME server when eligible).
    // makeArgs() has no connected repo / c4 flag, so ONLY narrate/summarize
    // are present — edit_c4_diagram is absent.
    expect(opts.mcpServers).toBeDefined();
    expect(Object.keys(opts.mcpServers)).toEqual(["soleur_platform"]);
    const toolNames = (opts.mcpServers.soleur_platform.tools ?? []).map(
      (t: { name: string }) => t.name,
    );
    expect(toolNames).toEqual(
      expect.arrayContaining(["narrate", "summarize"]),
    );
    expect(toolNames).not.toContain("edit_c4_diagram");
  });

  // -------------------------------------------------------------------------
  // T3: plugins: [{ type: "local", path: <DEPLOYED plugin root> }]  (security fix)
  // -------------------------------------------------------------------------
  it("T3: plugins points at the DEPLOYED plugin root, not the workspace copy", async () => {
    // getPluginPath() default (no SOLEUR_PLUGIN_PATH set in test). A workspace whose
    // connected repo ships its own plugins/soleur/ must NOT shadow the deployed plugin
    // (security: loading the workspace copy would run its hooks.json in-process).
    // See knowledge-base/.../2026-07-06-connected-repo-shadows-deployed-plugin-*.md.
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.plugins).toEqual([
      { type: "local", path: "/app/shared/plugins/soleur" },
    ]);
  });

  // -------------------------------------------------------------------------
  // T4: sandbox includes failIfUnavailable=true and allowUnsandboxedCommands=false
  // -------------------------------------------------------------------------
  it("T4: sandbox is the canonical buildAgentSandboxConfig output", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.sandbox.failIfUnavailable).toBe(true);
    expect(opts.sandbox.allowUnsandboxedCommands).toBe(false);
    // Helper was called with the workspace path AND fail-closed egress —
    // this dispatch has no connected repo, so no GitHub egress (#5041
    // follow-up).
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH, {
      allowGithubEgress: false,
      readOnly: false,
    });
  });

  // -------------------------------------------------------------------------
  // T5: hooks include PreToolUse + SubagentStart
  // -------------------------------------------------------------------------
  it("T5: hooks include PreToolUse matcher AND SubagentStart audit hook", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.hooks?.PreToolUse).toBeDefined();
    expect(Array.isArray(opts.hooks.PreToolUse)).toBe(true);
    expect(opts.hooks.PreToolUse[0].matcher).toContain("Bash");
    expect(opts.hooks?.SubagentStart).toBeDefined();
    expect(Array.isArray(opts.hooks.SubagentStart)).toBe(true);
  });

  // -------------------------------------------------------------------------
  // T6: disallowedTools mirrors WebSearch + WebFetch from agent-runner
  // -------------------------------------------------------------------------
  it("T6: disallowedTools includes WebSearch and WebFetch (parity with agent-runner)", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.disallowedTools).toEqual(
      expect.arrayContaining(["WebSearch", "WebFetch"]),
    );
  });

  // -------------------------------------------------------------------------
  // T6b (#3338 + #3344): cc path HARD-BLOCKS Edit/Write via disallowedTools.
  //
  // Bash was originally hard-blocked alongside Edit/Write (#3338) to prevent
  // a `find . -name "*.pdf"` / `apt-get install poppler-utils` modal cascade.
  // Two structural mitigations (#3338 PDF Read 24 MB ceiling + #3430
  // page-count gate) eliminated those triggers, so #3344 removed Bash from
  // the hard-block list. Bash now routes through canUseTool + the legacy
  // path's safe-bash allowlist (auto-approve for read-only KB-exploration
  // verbs; review-gate fallback for everything else).
  //
  // The auto-approve `allowedTools` list pins read-only tools
  // (Read/Glob/Grep/LS/NotebookRead/TodoWrite/ExitPlanMode) so they bypass
  // canUseTool. SDK semantics per sdk.d.ts:855-892:
  //   - allowedTools = auto-approve (NOT restriction)
  //   - disallowedTools = hard-block (removes from model's context)
  // Pin BOTH invariants. Bash MUST NOT appear in disallowedTools (post-#3344)
  // so the cc-path can route Bash through safe-bash. Edit/Write MUST remain
  // in disallowedTools so the cc-router still cannot mutate files.
  // -------------------------------------------------------------------------
  it("T6b: disallowedTools HARD-BLOCKS Edit/Write on the cc path; Bash routes via canUseTool (#3338 + #3344)", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(Array.isArray(opts.disallowedTools)).toBe(true);
    expect(opts.disallowedTools).toEqual(
      expect.arrayContaining(["Edit", "Write", "WebSearch", "WebFetch"]),
    );
    // #3344: Bash MUST NOT be in disallowedTools — the model needs to emit
    // it so it routes through canUseTool → safe-bash auto-approve for
    // read-only verbs. Pinning the negative-space invariant.
    expect(opts.disallowedTools).not.toContain("Bash");
    // Auto-approve list narrows to read-only safe tools + the always-on
    // narrate/summarize emit tools (feat-reasoning-chat-boxes #5370 — pure
    // emit tools auto-approved so a narration never pays a canUseTool
    // round-trip / surfaces a review modal). Order-tolerant closed-set match
    // so widening the list requires an explicit test edit.
    expect(Array.isArray(opts.allowedTools)).toBe(true);
    const sorted = [...opts.allowedTools].sort();
    expect(sorted).toEqual(
      [
        "ExitPlanMode",
        "Glob",
        "Grep",
        "LS",
        "NotebookRead",
        "Read",
        "TodoWrite",
        "mcp__soleur_platform__narrate",
        "mcp__soleur_platform__summarize",
      ],
    );
  });

  // -------------------------------------------------------------------------
  // T7: settingSources: [] (defense-in-depth)
  // -------------------------------------------------------------------------
  it("T7: settingSources is the empty array (no project settings.json pre-approvals)", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.settingSources).toEqual([]);
  });

  // -------------------------------------------------------------------------
  // T15: leaderId: "cc_router" passed to createCanUseTool
  // -------------------------------------------------------------------------
  it('T15: createCanUseTool receives leaderId: "cc_router" (audit-log attribution)', async () => {
    await realSdkQueryFactory(makeArgs());
    expect(createCanUseTool).toHaveBeenCalledOnce();
    const ctx = (createCanUseTool as unknown as { mock: { calls: unknown[][] } }).mock.calls[0][0] as {
      leaderId: string;
      userId: string;
      conversationId: string;
    };
    expect(ctx.leaderId).toBe("cc_router");
    expect(ctx.userId).toBe("user-1");
    expect(ctx.conversationId).toBe("conv-1");
  });

  // -------------------------------------------------------------------------
  // T8: KeyInvalidError from getUserApiKey rejects the factory promise.
  // The factory is now a real async function — KeyInvalidError surfaces
  // synchronously to the runner's `await deps.queryFactory(...)` catch
  // (tagged `op: "queryFactory"`), then `dispatchSoleurGo` maps it to
  // `errorCode: "key_invalid"`. T19 in cc-dispatcher.test.ts covers the
  // dispatcher-level mapping; here we pin the factory-level throw shape.
  // -------------------------------------------------------------------------
  it("T8: KeyInvalidError from getUserApiKey rejects the awaited factory call (runner catch tags op=queryFactory)", async () => {
    const { KeyInvalidError } = await import("@/lib/types");
    mockGetUserApiKey.mockRejectedValueOnce(new KeyInvalidError());

    await expect(realSdkQueryFactory(makeArgs())).rejects.toBeInstanceOf(
      KeyInvalidError,
    );
    // Inner sdkQuery never called because BYOK fetch threw upstream.
    expect(mockQuery).not.toHaveBeenCalled();
  });

  // -------------------------------------------------------------------------
  // T9 / T18: env shape — buildAgentEnv called with apiKey + serviceTokens;
  // resulting env contains only the allowlisted vars.
  // -------------------------------------------------------------------------
  it("T9/T18: buildAgentEnv is invoked with BYOK key + service tokens (no SUPABASE_SERVICE_ROLE_KEY leak)", async () => {
    mockGetUserServiceTokens.mockResolvedValueOnce({
      PLAUSIBLE_API_KEY: "plk-1",
    });
    mockBuildAgentEnv.mockReturnValueOnce({
      ANTHROPIC_API_KEY: "sk-test",
      PLAUSIBLE_API_KEY: "plk-1",
    });

    await realSdkQueryFactory(makeArgs());

    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      { PLAUSIBLE_API_KEY: "plk-1" },
      // Issue A: third opts arg always present; ghToken undefined here
      // because the default mock resolves no installation (null). Slice B:
      // pluginPath (getPluginPath() = deployed root) is always threaded.
      { ghToken: undefined, pluginPath: "/app/shared/plugins/soleur" },
    );
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.env.ANTHROPIC_API_KEY).toBe("sk-test");
    // CWE-526: no service-role key in env.
    expect(opts.env.SUPABASE_SERVICE_ROLE_KEY).toBeUndefined();
    expect(opts.env.BYOK_ENCRYPTION_KEY).toBeUndefined();
  });

  // -------------------------------------------------------------------------
  // Issue A — Concierge gh-auth: mint + inject GH_TOKEN (AC1/AC4)
  // -------------------------------------------------------------------------
  it("AC1: connected repo → mints installation token and threads it as ghToken", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockResolvedValueOnce("ghs_minted_xyz");

    await realSdkQueryFactory(makeArgs());

    // ADR-044 PR-1: the factory threads the membership-verified activeWorkspaceId
    // (= "user-1" solo here) into resolveInstallationId as the 2nd arg, so the
    // install resolves to the SAME workspace as the agent CWD / repo (no second
    // divergent resolve).
    expect(mockResolveInstallationId).toHaveBeenCalledWith("user-1", "user-1");
    expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
      987654,
      expect.objectContaining({ minRemainingMs: expect.any(Number) }),
    );
    // buildAgentEnv receives the minted token via the opts param — plus the
    // in-sandbox askpass wiring (item 1): the helper path + the same token as
    // gitInstallationToken.
    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      {},
      {
        ghToken: "ghs_minted_xyz",
        gitAskpassScriptPath: `${WORKSPACE_PATH}/.askpass-fixed-test.sh`,
        gitInstallationToken: "ghs_minted_xyz",
        pluginPath: "/app/shared/plugins/soleur",
      },
    );
  });

  // -------------------------------------------------------------------------
  // ADR-044 PR-1 (FR1/TR1) — unified-resolve threading. The membership-verified
  // activeWorkspaceId must reach ALL workspace-keyed consumers (path/install/
  // repo/status), so the agent CWD, repo, install, and self-heal key to ONE id.
  // -------------------------------------------------------------------------
  it("threads the resolved TEAM id into install + repo + status consumers (no second divergent resolve)", async () => {
    const teamWs = "team-ws-99";
    mockResolveActiveWorkspace.mockResolvedValueOnce({
      ok: true,
      workspaceId: teamWs,
    });
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockResolvedValueOnce("ghs_team");

    await realSdkQueryFactory(makeArgs());

    expect(mockResolveInstallationId).toHaveBeenCalledWith("user-1", teamWs);
    expect(mockGetCurrentRepoUrl).toHaveBeenCalledWith("user-1", teamWs);
    expect(mockGetCurrentRepoStatus).toHaveBeenCalledWith("user-1", teamWs);
  });

  it("db-error from resolveActiveWorkspace blocks dispatch (WorkspaceNotReadyError, no SDK query)", async () => {
    mockResolveActiveWorkspace.mockResolvedValueOnce({
      ok: false,
      reason: "db-error",
    });

    await expect(realSdkQueryFactory(makeArgs())).rejects.toMatchObject({
      name: "WorkspaceNotReadyError",
    });
    expect(mockQuery).not.toHaveBeenCalled();
  });

  // -------------------------------------------------------------------------
  // Item 1d/1e — in-sandbox git GIT_ASKPASS wiring (plan §Phase 1)
  // -------------------------------------------------------------------------
  it("item1d: connected repo → writes a fixed-name askpass helper under the workspace exactly once", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockResolvedValueOnce("ghs_minted_xyz");

    await realSdkQueryFactory(makeArgs());

    // The helper is written under the user's OWN workspace (the only verified
    // sandbox-readable allowWrite dir) — NOT $HOME/$TMPDIR — with a FIXED name
    // so it is reused per workspace (no accumulation, no cleanup lifecycle).
    // WORKSPACE_PATH/.git does not exist in the test, so the dir is the
    // workspace root; in prod with a cloned repo it is `<workspace>/.git`.
    expect(mockWriteAskpassScriptTo).toHaveBeenCalledTimes(1);
    expect(mockWriteAskpassScriptTo).toHaveBeenCalledWith(
      WORKSPACE_PATH,
      ".soleur-askpass.sh",
    );
    // And the writer's resolved path is threaded into buildAgentEnv (not a
    // vacuous "env exists" check — assert the askpass path actually flows).
    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      expect.anything(),
      expect.anything(),
      expect.objectContaining({
        gitAskpassScriptPath: `${WORKSPACE_PATH}/.askpass-fixed-test.sh`,
        gitInstallationToken: "ghs_minted_xyz",
      }),
    );
  });

  it("item1d: no connected repo (null installation) → NO askpass write, gitAskpassScriptPath undefined", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(null);

    await realSdkQueryFactory(makeArgs());

    expect(mockWriteAskpassScriptTo).not.toHaveBeenCalled();
    // buildAgentEnv receives undefined askpass inputs (both-or-nothing → the
    // GIT_* set is never injected for a no-repo dispatch).
    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      {},
      {
        ghToken: undefined,
        gitAskpassScriptPath: undefined,
        gitInstallationToken: undefined,
        pluginPath: "/app/shared/plugins/soleur",
      },
    );
  });

  it("item1d: mint failure → NO askpass write (no token to ride GIT_INSTALLATION_TOKEN)", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockRejectedValueOnce(new Error("mint boom"));

    await realSdkQueryFactory(makeArgs());

    expect(mockWriteAskpassScriptTo).not.toHaveBeenCalled();
  });

  it("item1e: the askpass-helper path is the ONLY place the credential is wired — token never embedded in a remote URL or argv", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockResolvedValueOnce("ghs_minted_xyz");

    await realSdkQueryFactory(makeArgs());

    // The minted token must NOT appear in the askpass-writer arguments (it
    // takes only the dir); it rides GIT_INSTALLATION_TOKEN env, set by
    // buildAgentEnv. Synthesized-fixture invariant per cq-test-fixtures-synthesized-only.
    for (const call of mockWriteAskpassScriptTo.mock.calls) {
      expect(JSON.stringify(call)).not.toContain("ghs_minted_xyz");
    }
    // The clone/remote URL path lives in ensure-workspace-repo (mocked here);
    // git-auth's own suite pins "token NEVER appears in execFile args". This
    // assertion pins that the cc wiring passes only the workspace dir + the
    // fixed helper name — never the token.
    expect(mockWriteAskpassScriptTo).toHaveBeenCalledWith(
      WORKSPACE_PATH,
      ".soleur-askpass.sh",
    );
  });

  it("AC1: no connected repo (null installation) → no mint, ghToken undefined, dispatch proceeds", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(null);

    await realSdkQueryFactory(makeArgs());

    expect(mockGenerateInstallationToken).not.toHaveBeenCalled();
    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      {},
      { ghToken: undefined, pluginPath: "/app/shared/plugins/soleur" },
    );
    expect(mockQuery).toHaveBeenCalledOnce();
  });

  it("AC4: mint failure mirrors to Sentry (op:mint-gh-token) and dispatch continues without GH_TOKEN", async () => {
    mockResolveInstallationId.mockResolvedValueOnce(987654);
    mockGenerateInstallationToken.mockRejectedValueOnce(new Error("mint boom"));

    await realSdkQueryFactory(makeArgs());

    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "cc-dispatcher", op: "mint-gh-token" }),
    );
    // Non-fatal: dispatch still happens, ghToken undefined.
    expect(mockQuery).toHaveBeenCalledOnce();
    expect(mockBuildAgentEnv).toHaveBeenCalledWith(
      { value: "sk-test", scheme: "api_key" },
      {},
      { ghToken: undefined, pluginPath: "/app/shared/plugins/soleur" },
    );
  });

  // -------------------------------------------------------------------------
  // feat-one-shot-concierge-gh-403 — installation self-heal (the load-bearing
  // fix). Stored install is a cross-account personal install; the dispatch
  // mints for the ENTITLED repo-owner install via the GitHub-App-JWT path only
  // (NO service-role). The user's login is derived from the stored personal
  // install's account; no persist (in-memory override per dispatch).
  // -------------------------------------------------------------------------
  describe("installation self-heal", () => {
    const REPO = "https://github.com/jikig-ai/soleur";
    const STORED = 130018654; // personal install (issues:read)
    const OWNER = 122213433; // org install (issues:write)

    it("mismatch (personal stored install) → mints the entitled owner install for this dispatch", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      // Stored is the user's PERSONAL install — its login IS the user's GH login.
      mockGetInstallationAccount.mockResolvedValueOnce({ login: "Elvalio", id: STORED, type: "User" });
      mockFindRepoOwnerInstallationForUser.mockResolvedValueOnce({ installationId: OWNER, outcome: "member" });

      await realSdkQueryFactory(makeArgs());

      // The user's login passed to the entitlement gate is derived from the
      // stored install's account (no service-role admin lookup).
      expect(mockFindRepoOwnerInstallationForUser).toHaveBeenCalledWith(
        "jikig-ai",
        "Elvalio",
      );
      // Load-bearing: GH_TOKEN minted for the OWNER install, not the stored one.
      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        OWNER,
        expect.anything(),
      );
      expect(mockGenerateInstallationToken).not.toHaveBeenCalledWith(
        STORED,
        expect.anything(),
      );
      // AC1 (regression): the workspace CLONE must also receive the self-healed
      // OWNER install — not the stored one. Before the fix the clone ran with
      // STORED, 403'd on the org repo, and left the workspace `.git`-less
      // ("No Git Repository in Workspace"). This is the load-bearing assertion.
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: OWNER }),
      );
      expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalledWith(
        expect.objectContaining({ installationId: STORED }),
      );
    });

    it("negative control: stored install already owns the repo → NO owner probe, mints stored", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(OWNER);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      // Stored account already matches the owner → cheap guard short-circuits.
      mockGetInstallationAccount.mockResolvedValueOnce({ login: "jikig-ai", id: OWNER, type: "Organization" });

      await realSdkQueryFactory(makeArgs());

      expect(mockFindRepoOwnerInstallationForUser).not.toHaveBeenCalled();
      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        OWNER,
        expect.anything(),
      );
      // AC3 + AC5: the no-op (already-owning) path is unaffected — here the
      // stored install IS the owner (resolveInstallationId → OWNER), so clone +
      // mint both use OWNER and no promotion probe runs.
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: OWNER }),
      );
    });

    it("entitlement denied (findRepoOwnerInstallationForUser → null) → keeps stored install + mirrors the skip (Bug B)", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      mockGetInstallationAccount.mockResolvedValueOnce({ login: "outside-user", id: STORED, type: "User" });
      mockFindRepoOwnerInstallationForUser.mockResolvedValueOnce({ installationId: null, outcome: "not-member" }); // not an org member

      await realSdkQueryFactory(makeArgs());

      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        STORED,
        expect.anything(),
      );
      // The deny is a QUERYABLE Sentry event (null err → captureMessage), with
      // the 4-field payload (Bug B, AC4).
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({
          feature: "cc-dispatcher",
          op: "self-heal-skip",
          extra: expect.objectContaining({
            storedInstallationId: STORED,
            owner: "jikig-ai",
            membershipProbeOutcome: "not-member",
            effectiveInstallationId: STORED,
          }),
        }),
      );
      // AC2 (fail-closed proof): promotion was DENIED, so the clone gets the
      // STORED install — exactly what it used before the fix. The hoist can
      // never widen the clone's access beyond the existing entitlement gate.
      // The mint (asserted above) gets STORED too — clone + mint in lockstep.
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: STORED }),
      );
    });

    it("org-type stored install (login != owner) → keeps stored (fail-safe, no probe) + mirrors the skip", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      // Stored is an ORG install for a DIFFERENT org → user login not derivable
      // without a service-role admin lookup → keep stored, never probe.
      mockGetInstallationAccount.mockResolvedValueOnce({ login: "some-other-org", id: STORED, type: "Organization" });

      await realSdkQueryFactory(makeArgs());

      expect(mockFindRepoOwnerInstallationForUser).not.toHaveBeenCalled();
      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        STORED,
        expect.anything(),
      );
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({
          feature: "cc-dispatcher",
          op: "self-heal-skip",
          extra: expect.objectContaining({
            membershipProbeOutcome: "org-type-stored-install",
            effectiveInstallationId: STORED,
          }),
        }),
      );
      // Fail-safe org-type path keeps the clone on the stored install too.
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: STORED }),
      );
    });

    it("probe failure (getInstallationAccount throws) → keeps stored install, mirrors to Sentry, dispatch proceeds", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      mockGetInstallationAccount.mockRejectedValueOnce(new Error("probe boom"));

      await realSdkQueryFactory(makeArgs());

      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          feature: "cc-dispatcher",
          op: "installation-self-heal-probe",
        }),
      );
      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        STORED,
        expect.anything(),
      );
      expect(mockQuery).toHaveBeenCalledOnce();
      // AC4: a self-heal probe failure now PRECEDES the clone (the hoist moved
      // the probe above ensureWorkspaceRepoCloned). The probe's try/catch keeps
      // effectiveInstallationId === STORED, so the clone STILL runs — the probe
      // is not a new clone-blocking dependency.
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: STORED }),
      );
    });

    it("AC6: self-heal deny path never serializes a GitHub token into Sentry or clone args", async () => {
      // The hoist relocates existing log.* / reportSilentFallback calls verbatim.
      // Guard that the move did not inline a minted token into a payload
      // (hr-github-app-auth-not-pat). Drive the deny path so the skip mirror fires.
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      mockGetInstallationAccount.mockResolvedValueOnce({ login: "outside-user", id: STORED, type: "User" });
      mockFindRepoOwnerInstallationForUser.mockResolvedValueOnce({ installationId: null, outcome: "not-member" });
      mockGenerateInstallationToken.mockResolvedValueOnce("ghs_secret_minted_token_value");

      await realSdkQueryFactory(makeArgs());

      // Positive control: the mint actually ran and produced a ghs_-shaped token
      // in this dispatch, so the negative scan below is meaningful — the payloads
      // are clean because the token was redacted/never-logged, NOT vacuously clean
      // because no token ever materialized.
      expect(mockGenerateInstallationToken).toHaveBeenCalled();

      const serialized = JSON.stringify([
        ...mockReportSilentFallback.mock.calls,
        ...mockEnsureWorkspaceRepoCloned.mock.calls,
      ]);
      expect(serialized).not.toMatch(/ghs_|gho_|ghp_/);
    });
  });

  // -------------------------------------------------------------------------
  // Sandbox GitHub egress lockstep (#5041 follow-up) — egress and the
  // entitled token move together. The sandbox-config mock delegates to the
  // REAL implementation in this block so the assertions reach the actual
  // allowedDomains the SDK receives (call-arg pinning alone cannot prove
  // the flag maps to the GitHub hosts).
  // -------------------------------------------------------------------------
  describe("sandbox GitHub egress lockstep (#5041 follow-up)", () => {
    const REPO = "https://github.com/jikig-ai/soleur";
    const STORED = 130018654; // personal install
    const OWNER = 122213433; // org install

    beforeEach(async () => {
      const actual = await vi.importActual<
        typeof import("@/server/agent-runner-sandbox-config")
      >("@/server/agent-runner-sandbox-config");
      mockBuildAgentSandboxConfig.mockImplementation(
        actual.buildAgentSandboxConfig,
      );
    });

    it("mismatch promotion → OWNER-install mint AND GitHub egress, in one test (lockstep)", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(STORED);
      mockGetCurrentRepoUrl.mockResolvedValueOnce(REPO);
      mockGetInstallationAccount.mockResolvedValueOnce({
        login: "Elvalio",
        id: STORED,
        type: "User",
      });
      mockFindRepoOwnerInstallationForUser.mockResolvedValueOnce({
        installationId: OWNER,
        outcome: "member",
      });

      await realSdkQueryFactory(makeArgs());

      // (a) token minted for the entitled OWNER install (existing :727 style)
      expect(mockGenerateInstallationToken).toHaveBeenCalledWith(
        OWNER,
        expect.anything(),
      );
      // (b) the SAME dispatch opens GitHub egress — the two move in lockstep.
      expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH, {
        allowGithubEgress: true,
        readOnly: false,
      });
      const opts = mockQuery.mock.calls[0][0].options;
      // Literal on purpose (canonical-literal style, do not import the
      // const) — an import would make a typo in the const self-verify.
      expect(opts.sandbox.network.allowedDomains).toEqual([
        "github.com",
        "api.github.com",
      ]);
    });

    it("fail-closed: no connected repo → no token AND sandbox fully closed", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(null);

      await realSdkQueryFactory(makeArgs());

      expect(mockGenerateInstallationToken).not.toHaveBeenCalled();
      expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH, {
        allowGithubEgress: false,
        readOnly: false,
      });
      const opts = mockQuery.mock.calls[0][0].options;
      expect(opts.sandbox.network.allowedDomains).toEqual([]);
    });

    it("fail-closed: mint failure → dispatch continues, egress collapses with the token", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(987654);
      mockGenerateInstallationToken.mockRejectedValueOnce(
        new Error("mint boom"),
      );

      await realSdkQueryFactory(makeArgs());

      expect(mockQuery).toHaveBeenCalledOnce();
      expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH, {
        allowGithubEgress: false,
        readOnly: false,
      });
      const opts = mockQuery.mock.calls[0][0].options;
      expect(opts.sandbox.network.allowedDomains).toEqual([]);
      // The token half of the lockstep: env got no ghToken either.
      expect(mockBuildAgentEnv).toHaveBeenCalledWith(
        expect.anything(),
        expect.anything(),
        expect.objectContaining({ ghToken: undefined }),
      );
    });

    it("posture log emits boolean-only payload — never the token value", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(987654);
      // beforeEach default mint resolves "ghs_default_test_token".

      await realSdkQueryFactory(makeArgs());

      const postureCalls = mockLogInfo.mock.calls.filter(
        ([, msg]) => msg === "Concierge sandbox GitHub egress posture",
      );
      expect(postureCalls).toHaveLength(1);
      const payload = postureCalls[0][0];
      expect(payload).toEqual({ userId: "user-1", githubEgress: true });
      expect(typeof payload.githubEgress).toBe("boolean");
      expect(JSON.stringify(payload)).not.toContain("ghs_default_test_token");
    });

    it("no-token dispatch appends the GitHub-access-unavailable prompt addendum", async () => {
      // beforeEach default: no connected repo → no mint, no token.
      await realSdkQueryFactory(makeArgs());

      const opts = mockQuery.mock.calls[0][0].options;
      expect(opts.systemPrompt).toContain(
        "GitHub access unavailable in this session",
      );
      // Posture log mirrors the closed state.
      const postureCalls = mockLogInfo.mock.calls.filter(
        ([, msg]) => msg === "Concierge sandbox GitHub egress posture",
      );
      expect(postureCalls).toHaveLength(1);
      expect(postureCalls[0][0]).toEqual({
        userId: "user-1",
        githubEgress: false,
      });
    });

    it("token dispatch does NOT carry the GitHub-access-unavailable addendum", async () => {
      mockResolveInstallationId.mockResolvedValueOnce(987654);

      await realSdkQueryFactory(makeArgs());

      const opts = mockQuery.mock.calls[0][0].options;
      expect(opts.systemPrompt).not.toContain(
        "GitHub access unavailable in this session",
      );
    });
  });

  // -------------------------------------------------------------------------
  // #5394 — repo-readiness gate (Layer A). The factory throws RepoNotReadyError
  // for a cloning/error workspace BEFORE ensureWorkspaceRepoCloned and before
  // the SDK query() spawn (AC1 no-spawn); a `ready` workspace flows UNCHANGED
  // into the self-heal (AC6 — proves the reclaim path is not short-circuited).
  // The gate keys on repo_status, never `.git` presence.
  // -------------------------------------------------------------------------
  describe("repo-readiness gate (#5394)", () => {
    it("AC1: cloning → throws RepoNotReadyError BEFORE ensureWorkspaceRepoCloned and BEFORE query() (no spawn)", async () => {
      const { RepoNotReadyError } = await import("@/server/repo-readiness");
      mockGetCurrentRepoStatus.mockResolvedValueOnce({
        repoStatus: "cloning",
        repoError: null,
      });

      await expect(realSdkQueryFactory(makeArgs())).rejects.toBeInstanceOf(
        RepoNotReadyError,
      );

      // The load-bearing AC1 assertion — the agent is never spawned and the
      // self-heal clone is never attempted against a not-ready workspace.
      expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
      expect(mockQuery).not.toHaveBeenCalled();
    });

    it("AC1: the thrown cloning error carries code=cloning and NO errorCode", async () => {
      const { RepoNotReadyError } = await import("@/server/repo-readiness");
      mockGetCurrentRepoStatus.mockResolvedValueOnce({
        repoStatus: "cloning",
        repoError: null,
      });

      let err: unknown;
      try {
        await realSdkQueryFactory(makeArgs());
      } catch (e) {
        err = e;
      }
      expect(err).toBeInstanceOf(RepoNotReadyError);
      const cloningErr = err as InstanceType<typeof RepoNotReadyError>;
      expect(cloningErr.code).toBe("cloning");
      expect(cloningErr.errorCode).toBeUndefined();
      expect(cloningErr.message).toContain("still being set up");
    });

    it("AC2: error → throws with code=error + errorCode=repo_setup_failed (reason from users.repo_error)", async () => {
      const { RepoNotReadyError } = await import("@/server/repo-readiness");
      mockGetCurrentRepoStatus.mockResolvedValueOnce({
        repoStatus: "error",
        repoError: JSON.stringify({
          code: "AUTH_FAILED",
          message: "Authentication failed",
        }),
      });

      let err: unknown;
      try {
        await realSdkQueryFactory(makeArgs());
      } catch (e) {
        err = e;
      }
      expect(err).toBeInstanceOf(RepoNotReadyError);
      const errorErr = err as InstanceType<typeof RepoNotReadyError>;
      expect(errorErr.code).toBe("error");
      expect(errorErr.errorCode).toBe("repo_setup_failed");
      expect(errorErr.message).toContain("Authentication failed");
      expect(errorErr.message).toContain("Reconnect in Settings → Repository");
      expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
      expect(mockQuery).not.toHaveBeenCalled();
    });

    it("AC6: ready → gate does NOT throw; ensureWorkspaceRepoCloned IS reached (reclaim/self-heal not short-circuited)", async () => {
      // beforeEach default is `ready`; assert it flows into the self-heal.
      await realSdkQueryFactory(makeArgs());
      expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledOnce();
      expect(mockQuery).toHaveBeenCalledOnce();
    });

    it("fail-open: a not_connected workspace is NOT blocked (flows to the existing repo-less path)", async () => {
      mockGetCurrentRepoStatus.mockResolvedValueOnce({
        repoStatus: "not_connected",
        repoError: null,
      });
      await realSdkQueryFactory(makeArgs());
      expect(mockQuery).toHaveBeenCalledOnce();
    });
  });

  // -------------------------------------------------------------------------
  // T10: patchWorkspacePermissions runs once per cold factory call
  // -------------------------------------------------------------------------
  it("T10: patchWorkspacePermissions fires once per factory invocation", async () => {
    await realSdkQueryFactory(makeArgs());
    expect(mockPatchWorkspacePermissions).toHaveBeenCalledOnce();
    expect(mockPatchWorkspacePermissions).toHaveBeenCalledWith(WORKSPACE_PATH);
  });

  // -------------------------------------------------------------------------
  // T2 (ADR-109): support persona bypasses the repo-lifecycle and runs read-only
  // at the plugin docs root. The mirror of T10 — patchWorkspacePermissions must
  // NOT run — plus cwd + read-only sandbox + kb-search-only skills.
  // -------------------------------------------------------------------------
  it("T2: support persona skips patchWorkspacePermissions and runs read-only at the plugin root", async () => {
    await realSdkQueryFactory(makeArgs({ persona: "support" }));

    // Repo-lifecycle write op is NOT invoked for support (contrast T10).
    expect(mockPatchWorkspacePermissions).not.toHaveBeenCalled();

    const opts = mockQuery.mock.calls[0][0].options;
    // cwd is the boot-validated plugin docs root, not the user's workspace.
    expect(opts.cwd).toBe("/app/shared/plugins/soleur");
    // SDK skills scoped to kb-search only (support surface).
    expect(opts.skills).toEqual(["kb-search"]);

    // Sandbox built read-only, at the plugin root — allowWrite:[] is enforced
    // inside buildAgentSandboxConfig (unit-tested T3 in agent-runner-query-options).
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(
      "/app/shared/plugins/soleur",
      { allowGithubEgress: false, readOnly: true },
    );
  });

  // -------------------------------------------------------------------------
  // T16: sandbox-required-but-unavailable substring → feature: "agent-sandbox"
  // (filtered by feature tag per learning
  // 2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md)
  // -------------------------------------------------------------------------
  it("T16: sandbox-unavailable error tags Sentry with feature=agent-sandbox (filtered by tag)", async () => {
    const sandboxErr = new Error(
      "Error: sandbox required but unavailable: missing socat",
    );
    mockQuery.mockImplementationOnce(() => {
      throw sandboxErr;
    });

    await expect(realSdkQueryFactory(makeArgs())).rejects.toBe(sandboxErr);

    // Filter by feature tag per learning
    // 2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md
    // — module init can fire other features (e.g. kb-share baseUrl).
    const sandboxCalls = mockReportSilentFallback.mock.calls.filter(
      ([, opts]) => opts?.feature === "agent-sandbox",
    );
    expect(sandboxCalls).toHaveLength(1);
    expect(sandboxCalls[0][1].op).toBe("sdk-startup");
    expect(sandboxCalls[0][1].extra).toMatchObject({
      userId: "user-1",
      conversationId: "conv-1",
      leaderId: "cc_router",
    });
  });

  // -------------------------------------------------------------------------
  // T17 (negative): factory uses buildAgentSandboxConfig (no inline literal)
  // -------------------------------------------------------------------------
  it("T17: factory delegates sandbox shape to buildAgentSandboxConfig (no inline drift)", async () => {
    await realSdkQueryFactory(makeArgs());
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledOnce();
    // No-token dispatch → fail-closed egress (#5041 follow-up).
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH, {
      allowGithubEgress: false,
      readOnly: false,
    });
  });

  // -------------------------------------------------------------------------
  // Resume key: when resumeSessionId provided, options.resume is set.
  // -------------------------------------------------------------------------
  it("threads resumeSessionId into options.resume when present", async () => {
    await realSdkQueryFactory(makeArgs({ resumeSessionId: "sess-abc" }));
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBe("sess-abc");
  });

  it("omits options.resume when no resumeSessionId provided", async () => {
    await realSdkQueryFactory(makeArgs());
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBeUndefined();
  });

  // -------------------------------------------------------------------------
  // T-AC4 (#2920): cc dispatcher writes real conversation status updates.
  // Replaces the prior no-op `ccDeps.updateConversationStatus`. Mirrors
  // `agent-runner.ts:303` shape (status + last_active) and includes the
  // R8 composite-key gate (`.eq("user_id", args.userId)`).
  // -------------------------------------------------------------------------
  describe("T-AC4: ccDeps.updateConversationStatus writes (#2920)", () => {
    function captureUpdateChain() {
      const updateCalls: Array<{
        payload: Record<string, unknown>;
        eqs: Array<[string, unknown]>;
      }> = [];

      mockSupabaseFrom.mockImplementation((table: string) => {
        if (table === "users") {
          return {
            select: () => ({
              eq: () => ({
                single: () => ({
                  data: { workspace_path: WORKSPACE_PATH },
                  error: null,
                }),
                maybeSingle: () => ({
                  data: { workspace_path: WORKSPACE_PATH },
                  error: null,
                }),
              }),
            }),
          };
        }
        if (table === "conversations") {
          return {
            update: (payload: Record<string, unknown>) => {
              const entry = { payload, eqs: [] as Array<[string, unknown]> };
              updateCalls.push(entry);
              const chain: Record<string, unknown> = {
                error: null,
                eq: (col: string, val: unknown) => {
                  entry.eqs.push([col, val]);
                  return chain;
                },
                select: () =>
                  Promise.resolve({ data: [{ id: "conv-1" }], error: null }),
                then: (resolve: (v: unknown) => void) =>
                  resolve({ error: null }),
              };
              return chain;
            },
          };
        }
        return {
          select: () => ({
            eq: () => ({ single: () => ({ data: null, error: null }) }),
          }),
          insert: () => ({ error: null }),
        };
      });
      return updateCalls;
    }

    async function getCcDepsFromFactory() {
      // The factory passes ccDeps via createCanUseTool(ctx). Capture the
      // ctx.deps so we can drive updateConversationStatus directly.
      await realSdkQueryFactory(makeArgs());
      const ctx = (
        createCanUseTool as unknown as { mock: { calls: unknown[][] } }
      ).mock.calls[0][0] as {
        deps: {
          updateConversationStatus: (
            convId: string,
            status: string,
          ) => Promise<void>;
        };
      };
      return ctx.deps;
    }

    it("T-AC4a: writes waiting_for_user with composite-key (.eq id + user_id)", async () => {
      const updateCalls = captureUpdateChain();
      const deps = await getCcDepsFromFactory();

      await deps.updateConversationStatus("conv-1", "waiting_for_user");

      expect(updateCalls).toHaveLength(1);
      expect(updateCalls[0].payload.status).toBe("waiting_for_user");
      // last_active is also written (parity with legacy agent-runner.ts:303)
      expect(typeof updateCalls[0].payload.last_active).toBe("string");
      // R8 composite-key invariant: BOTH id AND user_id must be present
      const cols = updateCalls[0].eqs.map(([c]) => c).sort();
      expect(cols).toEqual(["id", "user_id"]);
      const userIdEq = updateCalls[0].eqs.find(([c]) => c === "user_id");
      expect(userIdEq?.[1]).toBe("user-1");
      const idEq = updateCalls[0].eqs.find(([c]) => c === "id");
      expect(idEq?.[1]).toBe("conv-1");
    });

    it("T-AC4b: writes active on gate resolve (separate update)", async () => {
      const updateCalls = captureUpdateChain();
      const deps = await getCcDepsFromFactory();

      await deps.updateConversationStatus("conv-1", "active");

      expect(updateCalls).toHaveLength(1);
      expect(updateCalls[0].payload.status).toBe("active");
    });

    it("T-AC4c: every status update carries the user_id .eq gate (R8)", async () => {
      const updateCalls = captureUpdateChain();
      const deps = await getCcDepsFromFactory();

      await deps.updateConversationStatus("conv-1", "waiting_for_user");
      await deps.updateConversationStatus("conv-1", "active");

      expect(updateCalls).toHaveLength(2);
      for (const call of updateCalls) {
        const userIdEq = call.eqs.find(([c]) => c === "user_id");
        expect(userIdEq?.[1]).toBe("user-1");
      }
    });

    it("T-AC4d: error from supabase mirrors to reportSilentFallback", async () => {
      mockSupabaseFrom.mockImplementation((table: string) => {
        if (table === "users") {
          return {
            select: () => ({
              eq: () => ({
                single: () => ({
                  data: { workspace_path: WORKSPACE_PATH },
                  error: null,
                }),
                maybeSingle: () => ({
                  data: { workspace_path: WORKSPACE_PATH },
                  error: null,
                }),
              }),
            }),
          };
        }
        if (table === "conversations") {
          return {
            update: () => {
              const chain: Record<string, unknown> = {
                error: new Error("db unavailable"),
                eq: () => chain,
                select: () =>
                  Promise.resolve({
                    data: null,
                    error: new Error("db unavailable"),
                  }),
                then: (resolve: (v: unknown) => void) =>
                  resolve({ error: new Error("db unavailable") }),
              };
              return chain;
            },
          };
        }
        return {
          select: () => ({
            eq: () => ({ single: () => ({ data: null, error: null }) }),
          }),
          insert: () => ({ error: null }),
        };
      });
      const deps = await getCcDepsFromFactory();
      mockReportSilentFallback.mockClear();

      await deps.updateConversationStatus("conv-1", "waiting_for_user");

      const calls = mockReportSilentFallback.mock.calls.filter(
        ([, opts]) => opts?.feature === "cc-dispatcher",
      );
      expect(calls.length).toBeGreaterThanOrEqual(1);
      expect(calls[0][1].op).toBe("updateConversationStatus");
      expect(calls[0][1].extra).toMatchObject({
        userId: "user-1",
        conversationId: "conv-1",
        status: "waiting_for_user",
      });
    });
  });
});
