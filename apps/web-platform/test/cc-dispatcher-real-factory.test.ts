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
  mockQuery,
  mockGetUserApiKey,
  mockGetUserServiceTokens,
  mockPatchWorkspacePermissions,
  mockReportSilentFallback,
  mockSendToClient,
  mockBuildAgentEnv,
  mockBuildAgentSandboxConfig,
  mockSupabaseFrom,
} = vi.hoisted(() => ({
  mockQuery: vi.fn(),
  mockGetUserApiKey: vi.fn(),
  mockGetUserServiceTokens: vi.fn(),
  mockPatchWorkspacePermissions: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockSendToClient: vi.fn(),
  mockBuildAgentEnv: vi.fn(),
  mockBuildAgentSandboxConfig: vi.fn(),
  mockSupabaseFrom: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn(),
  createSdkMcpServer: vi.fn(),
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

vi.mock("@/server/permission-callback", () => ({
  // The factory composes a canUseTool from this — we capture the ctx
  // passed in via the spy returned here.
  createCanUseTool: vi.fn(() => async () => ({ behavior: "allow" })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockSupabaseFrom })),
}));

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
 * Drive the deferred-build factory: invoke + flush the inner build.
 * The proxy starts async work in `void ensureInner()`; we await a
 * macrotask + a few microtasks so all chained `.then()` resolve before
 * we assert against `mockQuery`. Using `setImmediate` (Node) covers
 * the worst case where the inner promise chain spans multiple awaits.
 */
async function flushFactoryBuild(): Promise<void> {
  // Three queueMicrotask cycles cover: workspace fetch → Promise.all
  // (apiKey + tokens) → patchWorkspacePermissions → sdkQuery.
  for (let i = 0; i < 5; i++) {
    await Promise.resolve();
  }
  // Guarantee one event-loop tick so any setImmediate-deferred chain
  // also drains.
  await new Promise<void>((resolve) => setImmediate(resolve));
}

const WORKSPACE_PATH = "/tmp/cc-test-workspace";

function setupSupabaseMockReturning(
  workspacePath: string | null = WORKSPACE_PATH,
) {
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
    setupSupabaseMockReturning(WORKSPACE_PATH);
  });

  // -------------------------------------------------------------------------
  // T1: factory called with valid user → returns Query
  // -------------------------------------------------------------------------
  it("T1: invokes SDK query() once with cwd=workspacePath and the canonical model", async () => {
    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();

    expect(mockQuery).toHaveBeenCalledOnce();
    const callArg = mockQuery.mock.calls[0][0];
    expect(callArg.options.cwd).toBe(WORKSPACE_PATH);
    expect(callArg.options.model).toBe("claude-sonnet-4-6");
  });

  // -------------------------------------------------------------------------
  // T2: factory options omit / empty mcpServers (V1; V2-13 widens)
  // -------------------------------------------------------------------------
  it("T2: mcpServers is empty for V1 (V2-13 will widen)", async () => {
    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();
    const opts = mockQuery.mock.calls[0][0].options;
    // Either undefined or {} is acceptable. Assert no servers registered.
    expect(opts.mcpServers === undefined || Object.keys(opts.mcpServers).length === 0).toBe(true);
  });

  // -------------------------------------------------------------------------
  // T3: plugins: [{ type: "local", path: <workspace>/plugins/soleur }]
  // -------------------------------------------------------------------------
  it("T3: plugins points at the per-user workspace plugin copy", async () => {
    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.plugins).toEqual([
      { type: "local", path: `${WORKSPACE_PATH}/plugins/soleur` },
    ]);
  });

  // -------------------------------------------------------------------------
  // T4: sandbox includes failIfUnavailable=true and allowUnsandboxedCommands=false
  // -------------------------------------------------------------------------
  it("T4: sandbox is the canonical buildAgentSandboxConfig output", async () => {
    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.sandbox.failIfUnavailable).toBe(true);
    expect(opts.sandbox.allowUnsandboxedCommands).toBe(false);
    // Helper was called with the workspace path.
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH);
  });

  // -------------------------------------------------------------------------
  // T5: hooks include PreToolUse + SubagentStart
  // -------------------------------------------------------------------------
  it("T5: hooks include PreToolUse matcher AND SubagentStart audit hook", async () => {
    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();
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
    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.disallowedTools).toEqual(
      expect.arrayContaining(["WebSearch", "WebFetch"]),
    );
  });

  // -------------------------------------------------------------------------
  // T7: settingSources: [] (defense-in-depth)
  // -------------------------------------------------------------------------
  it("T7: settingSources is the empty array (no project settings.json pre-approvals)", async () => {
    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.settingSources).toEqual([]);
  });

  // -------------------------------------------------------------------------
  // T15: leaderId: "cc_router" passed to createCanUseTool
  // -------------------------------------------------------------------------
  it('T15: createCanUseTool receives leaderId: "cc_router" (audit-log attribution)', async () => {
    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();
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
  // T8: KeyInvalidError from getUserApiKey throws → reportSilentFallback fires
  // (asserted via the runner's catch in soleur-go-runner.ts; for the factory
  // alone, we assert that the throw propagates with the SAME class.)
  // -------------------------------------------------------------------------
  it("T8: KeyInvalidError from getUserApiKey propagates verbatim through the iterator (runner mirrors)", async () => {
    const { KeyInvalidError } = await import("@/lib/types");
    mockGetUserApiKey.mockRejectedValueOnce(new KeyInvalidError());

    // Factory returns a Query proxy synchronously; the inner build is
    // async and surfaces the KeyInvalidError on the iterator's first
    // .next() call (per the deferred-build contract — see
    // realSdkQueryFactory body).
    const q = realSdkQueryFactory(makeArgs());
    const iter = q[Symbol.asyncIterator]();
    await expect(iter.next()).rejects.toBeInstanceOf(KeyInvalidError);
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

    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();

    expect(mockBuildAgentEnv).toHaveBeenCalledWith("sk-test", {
      PLAUSIBLE_API_KEY: "plk-1",
    });
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.env.ANTHROPIC_API_KEY).toBe("sk-test");
    // CWE-526: no service-role key in env.
    expect(opts.env.SUPABASE_SERVICE_ROLE_KEY).toBeUndefined();
    expect(opts.env.BYOK_ENCRYPTION_KEY).toBeUndefined();
  });

  // -------------------------------------------------------------------------
  // T10: patchWorkspacePermissions runs once per cold factory call
  // -------------------------------------------------------------------------
  it("T10: patchWorkspacePermissions fires once per factory invocation", async () => {
    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();
    expect(mockPatchWorkspacePermissions).toHaveBeenCalledOnce();
    expect(mockPatchWorkspacePermissions).toHaveBeenCalledWith(WORKSPACE_PATH);
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

    const q = realSdkQueryFactory(makeArgs());
    const iter = q[Symbol.asyncIterator]();
    await expect(iter.next()).rejects.toBe(sandboxErr);

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
    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledOnce();
    expect(mockBuildAgentSandboxConfig).toHaveBeenCalledWith(WORKSPACE_PATH);
  });

  // -------------------------------------------------------------------------
  // Resume key: when resumeSessionId provided, options.resume is set.
  // -------------------------------------------------------------------------
  it("threads resumeSessionId into options.resume when present", async () => {
    realSdkQueryFactory(makeArgs({ resumeSessionId: "sess-abc" }));
    await flushFactoryBuild();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBe("sess-abc");
  });

  it("omits options.resume when no resumeSessionId provided", async () => {
    realSdkQueryFactory(makeArgs());
    await flushFactoryBuild();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBeUndefined();
  });
});
