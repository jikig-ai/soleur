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

vi.mock("@/server/permission-callback", () => ({
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
