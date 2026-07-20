// Integration coverage for the cc-soleur-go path's invocation of the
// shared prefill-guard helper. The helper's semantic contract
// (positive-match polarity, three observability ops, error
// sanitization) is pinned in `agent-prefill-guard.test.ts`. This file
// only verifies the integration: `realSdkQueryFactory` calls the
// helper with the correct args and threads the result into
// `buildAgentQueryOptions({ resumeSessionId })`.

import { describe, it, expect, vi, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const {
  mockQuery,
  mockApplyPrefillGuard,
  mockGetUserApiKey,
  mockGetUserServiceTokens,
  mockPatchWorkspacePermissions,
  mockReportSilentFallback,
  mockSendToClient,
  mockBuildAgentEnv,
  mockBuildAgentSandboxConfig,
  mockSupabaseFrom,
  mockResolveActiveWorkspacePath,
} = vi.hoisted(() => ({
  mockQuery: vi.fn(),
  mockApplyPrefillGuard: vi.fn(),
  mockGetUserApiKey: vi.fn(),
  mockGetUserServiceTokens: vi.fn(),
  mockPatchWorkspacePermissions: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockSendToClient: vi.fn(),
  mockBuildAgentEnv: vi.fn(),
  mockBuildAgentSandboxConfig: vi.fn(),
  mockSupabaseFrom: vi.fn(),
  mockResolveActiveWorkspacePath: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  // The factory imports `applyPrefillGuard` directly — this stub is
  // present only because some indirect transient imports may resolve
  // through the SDK module.
  getSessionMessages: vi.fn().mockResolvedValue([]),
  tool: vi.fn(),
  createSdkMcpServer: vi.fn(),
}));

vi.mock("@/server/agent-prefill-guard", () => ({
  applyPrefillGuard: mockApplyPrefillGuard,
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

// Issue A / Issue B part 2 — these dispatcher deps key off args.userId and are
// resolved in the cold-start Promise.all. Default to no-connected-repo / off so
// the prefill-guard behavior under test is unaffected.
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: vi.fn(async () => null),
}));
vi.mock("@/server/github-app", () => ({
  generateInstallationToken: vi.fn(async () => "ghs_test"),
}));
// Plan item 1 — cc-dispatcher imports the in-sandbox askpass writer from
// git-auth. Mock here too (Phase 0.4 sweep: any new cold-path import must be
// mocked in BOTH cc-dispatcher test files or the suite throws on import).
// Default no-repo path never calls it, but the module must resolve.
vi.mock("@/server/git-auth", () => ({
  writeAskpassScriptTo: vi.fn(() => "/tmp/ws/.askpass-test.sh"),
  cleanupAskpassScript: vi.fn(),
}));
vi.mock("@/server/resolve-bash-autonomous", () => ({
  resolveBashAutonomous: vi.fn(async () => false),
}));
// feat-bash-autonomous-default-on — soft-gate inputs default to un-acked /
// non-owner so the prefill-guard factory-shape tests dispatch unaffected.
vi.mock("@/server/resolve-autonomous-ack", () => ({
  resolveAutonomousAck: vi.fn(async () => null),
}));
vi.mock("@/server/resolve-workspace-owner", () => ({
  resolveIsWorkspaceOwner: vi.fn(async () => false),
}));

// Session-start ensure-repo self-heal (cold-path deps) — default no-op.
vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: vi.fn(async () => null),
  // #5394 — gate reads repo readiness; default ready so dispatch is not blocked.
  getCurrentRepoStatus: vi.fn(async () => ({
    repoStatus: "ready",
    repoError: null,
  })),
}));
vi.mock("@/server/ensure-workspace-repo", () => ({
  ensureWorkspaceRepoCloned: vi.fn(async () => undefined),
  ensureWorkspaceDirExists: vi.fn(async () => undefined),
}));

vi.mock("@/server/permission-callback", () => ({
  createCanUseTool: vi.fn(() => async () => ({ behavior: "allow" })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
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

// PR-C §2.4 / §2.10 / §2.11 (#3244): conversation-writer + agent-runner
// + cc-dispatcher (BYOK lease wrap) now import from
// `@/lib/supabase/tenant`. Mock so the test does not pull the real
// `mintFounderJwt` chain.
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockSupabaseFrom })),
  mintFounderJwt: vi.fn(),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

// ADR-044: fetchUserWorkspacePath resolves the ACTIVE workspace via
// resolveActiveWorkspacePath. Override only that export; importActual keeps the
// rest of workspace-resolver real.
vi.mock("@/server/workspace-resolver", async () => {
  const actual = await vi.importActual<typeof import("@/server/workspace-resolver")>(
    "@/server/workspace-resolver",
  );
  return {
    ...actual,
    resolveActiveWorkspacePath: mockResolveActiveWorkspacePath,
    // ADR-044 PR-1: factory resolves this directly before the Promise.all.
    resolveActiveWorkspace: async (userId: string) => ({
      ok: true as const,
      workspaceId: userId,
    }),
  };
});

// PR-C §2.11 (#3244): cc-dispatcher.ts now wraps `realSdkQueryFactory`
// body in `runWithByokLease(args.userId, body)`. Short-circuit the lease
// so the test does not pull the real `fetchAndDecryptIntoSlot` chain
// (which would need a fully-shaped `api_keys.select.eq.eq.eq.limit.single`
// terminal); `body` is invoked with a fake `lease.getAgentCredential()`.
vi.mock("@/server/byok-lease", async () => {
  const actual = await vi.importActual<typeof import("@/server/byok-lease")>(
    "@/server/byok-lease",
  );
  return {
    ...actual,
    runWithByokLease: vi.fn(
      async <T>(
        args: { workspaceContextUserId: string; keyOwnerUserId: string },
        body: (lease: {
          workspaceContextUserId: string;
          keyOwnerUserId: string;
          getRestApiKey: () => string;
          getAgentCredential: () => Promise<{ value: string; scheme: "api_key" | "oauth_token" }>;
        }) => Promise<T>,
      ) =>
        body({
          workspaceContextUserId: args.workspaceContextUserId,
          keyOwnerUserId: args.keyOwnerUserId,
          // cc-dispatcher is an Agent-SDK consumer → getAgentCredential.
          getRestApiKey: () => "fake-byok-key",
          getAgentCredential: async () => ({ value: "fake-byok-key", scheme: "api_key" as const }),
        }),
    ),
  };
});

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

vi.mock("@/server/ws-handler", () => ({
  sendToClient: mockSendToClient,
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

vi.mock("@/server/notifications", () => ({ notifyOfflineUser: vi.fn() }));

import { realSdkQueryFactory } from "@/server/cc-dispatcher";

function makeFakeQuery() {
  return {
    async *[Symbol.asyncIterator]() {},
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

const WORKSPACE_PATH = "/tmp/cc-test-workspace";

function setupSupabaseMockReturning(workspacePath: string = WORKSPACE_PATH) {
  // ADR-044: workspace path comes from resolveActiveWorkspacePath now.
  mockResolveActiveWorkspacePath.mockResolvedValue(workspacePath);
  mockSupabaseFrom.mockImplementation((table: string) => {
    if (table === "users") {
      return {
        select: () => ({
          eq: () => ({
            single: () => ({
              data: { workspace_path: workspacePath },
              error: null,
            }),
            maybeSingle: () => ({
              data: { workspace_path: workspacePath },
              error: null,
            }),
          }),
        }),
      };
    }
    return {
      select: () => ({
        eq: () => ({ single: () => ({ data: null, error: null }) }),
      }),
      insert: () => ({ error: null }),
      update: () => ({ eq: () => ({ error: null }) }),
    };
  });
}

function makeArgs(
  overrides: Partial<Parameters<typeof realSdkQueryFactory>[0]> = {},
) {
  // biome-ignore lint/suspicious/noExplicitAny: minimal AsyncIterable stub
  const promptStream = {
    async *[Symbol.asyncIterator]() {},
  } as any;
  return {
    prompt: promptStream,
    systemPrompt: "system",
    pluginPath: "/ignored",
    cwd: "/ignored",
    userId: "user-1",
    conversationId: "conv-1",
    persona: "command_center" as const,
    ...overrides,
  };
}

describe("realSdkQueryFactory — prefill-guard integration (#3250)", () => {
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
    setupSupabaseMockReturning(WORKSPACE_PATH);
    // Default: helper passes resume through unchanged.
    mockApplyPrefillGuard.mockImplementation(async ({ resumeSessionId }) => ({
      safeResumeSessionId: resumeSessionId,
    }));
  });

  it("invokes applyPrefillGuard with the cc-concierge feature tag and CC_ROUTER_LEADER_ID", async () => {
    await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

    expect(mockApplyPrefillGuard).toHaveBeenCalledOnce();
    const call = mockApplyPrefillGuard.mock.calls[0][0];
    expect(call).toMatchObject({
      resumeSessionId: "s",
      workspacePath: WORKSPACE_PATH,
      userId: "user-1",
      conversationId: "conv-1",
      feature: "cc-concierge",
      leaderId: "cc_router",
    });
  });

  it("threads the helper's safeResumeSessionId into options.resume (drop case)", async () => {
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: undefined,
    });

    await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBeUndefined();
  });

  it("threads the helper's safeResumeSessionId into options.resume (preserve case)", async () => {
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: "s",
    });

    await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBe("s");
  });

  it("invokes the helper even when resumeSessionId is undefined (helper short-circuits)", async () => {
    await realSdkQueryFactory(makeArgs());

    expect(mockApplyPrefillGuard).toHaveBeenCalledOnce();
    expect(mockApplyPrefillGuard.mock.calls[0][0].resumeSessionId).toBeUndefined();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBeUndefined();
  });
});

// -------------------------------------------------------------------------
// #3269 — context-reset notice + WS event integration. The helper's
// semantic contract is pinned in `agent-prefill-guard.test.ts`. This block
// verifies the dispatcher wiring: notice appended to systemPrompt iff
// guard fires; WS `context_reset` emitted exactly once per fire; both
// reason variants thread through; non-firing branches do not emit/mutate.
// -------------------------------------------------------------------------

describe("realSdkQueryFactory — context_reset signal (#3269)", () => {
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
    setupSupabaseMockReturning(WORKSPACE_PATH);
    mockApplyPrefillGuard.mockImplementation(async ({ resumeSessionId }) => ({
      safeResumeSessionId: resumeSessionId,
    }));
  });

  it("appends contextResetNotice to systemPrompt exactly when guard fires", async () => {
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: undefined,
      contextResetNotice: "RESET-NOTICE-MARKER",
      reason: "prefill-guard",
    });

    await realSdkQueryFactory(
      makeArgs({ resumeSessionId: "s", systemPrompt: "BASE" }),
    );

    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.systemPrompt).toContain("BASE");
    expect(opts.systemPrompt).toContain("RESET-NOTICE-MARKER");
  });

  it("does NOT mutate systemPrompt when guard does not fire", async () => {
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: "s",
    });

    await realSdkQueryFactory(
      makeArgs({ resumeSessionId: "s", systemPrompt: "BASE" }),
    );

    const opts = mockQuery.mock.calls[0][0].options;
    // The context-reset NOTICE must not be added when the guard does not fire.
    // (The static gh-403 honesty directive is appended unconditionally — see
    // feat-one-shot-concierge-gh-403 — so assert BASE is preserved and the
    // reset notice is absent, rather than exact equality.)
    expect(opts.systemPrompt).toContain("BASE");
    expect(opts.systemPrompt).not.toContain("RESET-NOTICE-MARKER");
    // AC5 (behavioral): the gh-403 honesty directive IS present in the
    // assembled prompt — not just the source text. Forbids scope speculation
    // and re-consent advice on a `gh` 403.
    expect(opts.systemPrompt).toMatch(/Do NOT\s+speculate/i);
    expect(opts.systemPrompt).toMatch(/re-consent/i);
  });

  it("emits one context_reset WS event per guard fire with reason 'prefill-guard'", async () => {
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: undefined,
      contextResetNotice: "notice text",
      reason: "prefill-guard",
    });

    await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

    const contextResetCalls = mockSendToClient.mock.calls.filter(
      (call) => call[1]?.type === "context_reset",
    );
    expect(contextResetCalls).toHaveLength(1);
    expect(contextResetCalls[0][0]).toBe("user-1");
    expect(contextResetCalls[0][1]).toEqual({
      type: "context_reset",
      reason: "prefill-guard",
      conversationId: "conv-1",
    });
  });

  it("emits reason 'tool_use_orphan' when trailing message had a tool_use content block", async () => {
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: undefined,
      contextResetNotice: "tool-aware",
      reason: "tool_use_orphan",
    });

    await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

    const contextResetCalls = mockSendToClient.mock.calls.filter(
      (call) => call[1]?.type === "context_reset",
    );
    expect(contextResetCalls).toHaveLength(1);
    expect(contextResetCalls[0][1].reason).toBe("tool_use_orphan");
  });

  it("does NOT emit context_reset when guard returns no notice (probe failure / empty history / user-final)", async () => {
    // probe-failed pass-through (helper returns safeResumeSessionId unchanged
    // and does not populate notice fields)
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: "s",
    });
    await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

    const contextResetCalls = mockSendToClient.mock.calls.filter(
      (call) => call[1]?.type === "context_reset",
    );
    expect(contextResetCalls).toHaveLength(0);
  });

  it("does NOT carry the notice forward across calls when the guard does not fire on the second call (multi-turn non-accumulation, AC6b)", async () => {
    // First call: guard fires
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: undefined,
      contextResetNotice: "FIRST-CALL-NOTICE",
      reason: "prefill-guard",
    });
    await realSdkQueryFactory(
      makeArgs({ resumeSessionId: "s", systemPrompt: "BASE" }),
    );

    const firstOpts = mockQuery.mock.calls[0][0].options;
    expect(firstOpts.systemPrompt).toContain("FIRST-CALL-NOTICE");

    // Second call: guard does not fire (e.g., user-final history)
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: "s",
    });
    await realSdkQueryFactory(
      makeArgs({ resumeSessionId: "s", systemPrompt: "BASE" }),
    );

    const secondOpts = mockQuery.mock.calls[1][0].options;
    // The first call's reset notice must not carry forward (multi-turn
    // non-accumulation). BASE is preserved; the static gh-403 directive is
    // appended every call but never accumulates across calls.
    expect(secondOpts.systemPrompt).toContain("BASE");
    expect(secondOpts.systemPrompt).not.toContain("FIRST-CALL-NOTICE");
  });
});
