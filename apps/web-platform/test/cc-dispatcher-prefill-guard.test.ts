// RED/GREEN tests for the cc-soleur-go prefill-guard at the SDK call
// boundary in `realSdkQueryFactory`. Issue #3250 — Concierge default
// `claude-sonnet-4-6` rejects assistant-terminated threads with HTTP 400
// "model does not support assistant message prefill" when the persisted
// session at `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` ends
// on `type: "assistant"` (idle-reaper, wall-clock runaway, cost-ceiling
// abort, container restart mid-turn).
//
// Guard contract (positive-match polarity per plan §Sharp Edges):
//   1. Probe the persisted session via `getSessionMessages(resumeSessionId,
//      { dir: workspacePath })` BEFORE calling sdkQuery.
//   2. If trailing `SessionMessage.type === "assistant"`: drop `resume:`,
//      emit one `warnSilentFallback({ feature: "cc-concierge",
//      op: "prefill-guard" })`.
//   3. If history is `[]`: pass `resume:` through, emit one
//      `warnSilentFallback({ ..., op: "prefill-guard-empty-history" })` —
//      observability hook for `dir`-arg drift detection.
//   4. If probe throws: pass `resume:` through, emit one
//      `warnSilentFallback({ ..., op: "prefill-guard-probe-failed" })`.
//   5. No `resumeSessionId`: no probe.
//   6. Probe MUST be called with `(resumeSessionId, { dir: workspacePath })`
//      — wrong dir returns `[]` silently and produces a false negative.
//
// Mocks reuse the harness pattern from `cc-dispatcher-real-factory.test.ts`
// — same vi.hoisted shape, same supabase fixture, same fake Query stub.
// Adds two captured spies the sibling file does NOT capture:
// `mockGetSessionMessages` and `mockWarnSilentFallback`.

import { describe, it, expect, vi, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const {
  mockQuery,
  mockGetSessionMessages,
  mockGetUserApiKey,
  mockGetUserServiceTokens,
  mockPatchWorkspacePermissions,
  mockReportSilentFallback,
  mockWarnSilentFallback,
  mockSendToClient,
  mockBuildAgentEnv,
  mockBuildAgentSandboxConfig,
  mockSupabaseFrom,
} = vi.hoisted(() => ({
  mockQuery: vi.fn(),
  mockGetSessionMessages: vi.fn(),
  mockGetUserApiKey: vi.fn(),
  mockGetUserServiceTokens: vi.fn(),
  mockPatchWorkspacePermissions: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
  mockSendToClient: vi.fn(),
  mockBuildAgentEnv: vi.fn(),
  mockBuildAgentSandboxConfig: vi.fn(),
  mockSupabaseFrom: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  getSessionMessages: mockGetSessionMessages,
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
  createCanUseTool: vi.fn(() => async () => ({ behavior: "allow" })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: mockWarnSilentFallback,
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

function warnCallsForGuard() {
  // Filter to only `cc-concierge` warns so an unrelated module-init
  // warn (rare but possible during the lazy supabase client init) cannot
  // false-positive these assertions.
  return mockWarnSilentFallback.mock.calls.filter(
    ([, opts]) => opts?.feature === "cc-concierge",
  );
}

describe("realSdkQueryFactory — prefill-guard (#3250)", () => {
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

  // Scenario 1 — guard fires on assistant-terminated history.
  it("drops resume when persisted session ends with assistant message", async () => {
    mockGetSessionMessages.mockResolvedValueOnce([
      {
        type: "user",
        uuid: "u1",
        session_id: "s",
        message: {},
        parent_tool_use_id: null,
      },
      {
        type: "assistant",
        uuid: "a1",
        session_id: "s",
        message: {},
        parent_tool_use_id: null,
      },
    ]);

    await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

    // Drift-guard portion of scenario 6 — probe must use workspace cwd.
    expect(mockGetSessionMessages).toHaveBeenCalledWith("s", {
      dir: WORKSPACE_PATH,
    });

    // Resume was dropped before reaching the SDK.
    expect(mockQuery).toHaveBeenCalledOnce();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBeUndefined();

    // One Sentry warn under the canonical feature/op.
    const calls = warnCallsForGuard();
    expect(calls).toHaveLength(1);
    const [errArg, optsArg] = calls[0];
    expect(errArg).toBeNull();
    expect(optsArg.feature).toBe("cc-concierge");
    expect(optsArg.op).toBe("prefill-guard");
    expect(optsArg.extra).toMatchObject({
      resumeSessionId: "s",
      lastType: "assistant",
      historyLength: 2,
    });
  });

  // Scenario 2 — user-terminated history passes through unchanged.
  it("preserves resume when persisted session ends with user message", async () => {
    mockGetSessionMessages.mockResolvedValueOnce([
      {
        type: "user",
        uuid: "u1",
        session_id: "s",
        message: {},
        parent_tool_use_id: null,
      },
      {
        type: "assistant",
        uuid: "a1",
        session_id: "s",
        message: {},
        parent_tool_use_id: null,
      },
      {
        type: "user",
        uuid: "u2",
        session_id: "s",
        message: {},
        parent_tool_use_id: null,
      },
    ]);

    await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

    expect(mockQuery).toHaveBeenCalledOnce();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBe("s");

    expect(warnCallsForGuard()).toHaveLength(0);
  });

  // Scenario 3 — empty history emits distinct op AND preserves resume.
  it("emits prefill-guard-empty-history and preserves resume when history is empty", async () => {
    mockGetSessionMessages.mockResolvedValueOnce([]);

    await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

    expect(mockQuery).toHaveBeenCalledOnce();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBe("s");

    const calls = warnCallsForGuard();
    expect(calls).toHaveLength(1);
    expect(calls[0][1].op).toBe("prefill-guard-empty-history");
  });

  // Scenario 4 — probe failure does NOT block the SDK call.
  it("preserves resume and logs probe-failed when getSessionMessages throws", async () => {
    const probeErr = new Error("synthetic probe failure");
    mockGetSessionMessages.mockRejectedValueOnce(probeErr);

    await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

    expect(mockQuery).toHaveBeenCalledOnce();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBe("s");

    const calls = warnCallsForGuard();
    expect(calls).toHaveLength(1);
    expect(calls[0][0]).toBe(probeErr);
    expect(calls[0][1].op).toBe("prefill-guard-probe-failed");
  });

  // Scenario 5 — no resumeSessionId means no probe.
  it("does not probe when resumeSessionId is undefined", async () => {
    await realSdkQueryFactory(makeArgs());

    expect(mockGetSessionMessages).not.toHaveBeenCalled();
    expect(warnCallsForGuard()).toHaveLength(0);
    expect(mockQuery).toHaveBeenCalledOnce();
    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.resume).toBeUndefined();
  });

  // Scenario 6 — drift-guard: probe MUST receive workspace cwd as `dir`.
  // Without `dir`, the SDK's default lookup returns [] silently and the
  // guard sees a "user-terminated" thread (false negative — the bug 400
  // would still fire in prod).
  it("invokes getSessionMessages with { dir: workspacePath } (drift-guard)", async () => {
    mockGetSessionMessages.mockResolvedValueOnce([
      {
        type: "user",
        uuid: "u1",
        session_id: "s",
        message: {},
        parent_tool_use_id: null,
      },
    ]);

    await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

    expect(mockGetSessionMessages).toHaveBeenCalledOnce();
    const [sid, probeOpts] = mockGetSessionMessages.mock.calls[0];
    expect(sid).toBe("s");
    expect(probeOpts).toEqual({ dir: WORKSPACE_PATH });
  });
});
