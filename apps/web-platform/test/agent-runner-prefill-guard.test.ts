// #3269 — legacy agent-runner path's wiring of the shared prefill-guard
// helper. The helper's semantic contract is pinned in
// `agent-prefill-guard.test.ts`. This file verifies the legacy path
// integration: notice appended to systemPrompt iff guard fires; WS
// `context_reset` emitted exactly once per fire; both `reason` variants
// thread through; non-firing branches do not emit/mutate.
//
// Mirrors `cc-dispatcher-prefill-guard.test.ts` for the legacy
// `startAgentSession` entry point.

import { describe, test, expect, vi, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const {
  mockFrom,
  mockRpc,
  mockQuery,
  mockReadFileSync,
  mockApplyPrefillGuard,
  mockSendToClient,
} = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
  mockApplyPrefillGuard: vi.fn(),
  mockSendToClient: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn(
    (_name: string, _desc: string, _schema: unknown, handler: Function) => ({
      name: _name,
      handler,
    }),
  ),
  createSdkMcpServer: vi.fn((opts: { name: string; tools: unknown[] }) => ({
    type: "sdk",
    name: opts.name,
    instance: { tools: opts.tools },
  })),
}));

vi.mock("fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("fs")>();
  return { ...actual, readFileSync: mockReadFileSync };
});

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockFrom })),
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockFrom, rpc: mockRpc })),
  mintFounderJwt: vi.fn(),
  RuntimeAuthError: class RuntimeAuthError extends Error {
    cause: string;
    constructor(cause: string, msg: string) {
      super(msg);
      this.name = "RuntimeAuthError";
      this.cause = cause;
    }
  },
}));

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("../server/ws-handler", () => ({ sendToClient: mockSendToClient }));
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));
vi.mock("../server/byok", () => ({
  decryptKey: vi.fn(() => Buffer.from("sk-test-key", "utf8")),
  decryptKeyLegacy: vi.fn(() => Buffer.from("sk-test-key", "utf8")),
  zeroize: vi.fn(),
  encryptKey: vi.fn(),
}));
vi.mock("../server/error-sanitizer", () => ({
  sanitizeErrorForClient: vi.fn(() => "error"),
}));
vi.mock("../server/sandbox", () => ({ isPathInWorkspace: vi.fn(() => true) }));
vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [],
  extractToolPath: vi.fn(),
  isFileTool: vi.fn(() => false),
  isSafeTool: vi.fn(() => false),
}));
vi.mock("../server/agent-env", () => ({ buildAgentEnv: vi.fn(() => ({})) }));
vi.mock("../server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => vi.fn()),
}));
vi.mock("../server/review-gate", () => ({
  abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
  validateSelection: vi.fn(),
  extractReviewGateInput: vi.fn(),
  buildReviewGateResponse: vi.fn(),
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => {
  const leaders = [
    {
      id: "cpo",
      name: "CPO",
      title: "Chief Product Officer",
      description: "Product",
    },
  ];
  return { DOMAIN_LEADERS: leaders, ROUTABLE_DOMAIN_LEADERS: leaders };
});
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({
  syncPull: vi.fn(),
  syncPush: vi.fn(),
}));
vi.mock("../server/github-api", () => ({
  githubApiGet: vi.fn().mockResolvedValue({ default_branch: "main" }),
  githubApiGetText: vi.fn().mockResolvedValue(""),
  githubApiPost: vi.fn().mockResolvedValue(null),
}));
vi.mock("../server/service-tools", () => ({
  plausibleCreateSite: vi.fn(),
  plausibleAddGoal: vi.fn(),
  plausibleGetStats: vi.fn(),
}));
vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  reportSilentFallbackWarning: vi.fn(),
  warnSilentFallback: vi.fn(),
}));
vi.mock("../server/agent-prefill-guard", () => ({
  applyPrefillGuard: mockApplyPrefillGuard,
}));

import { startAgentSession } from "../server/agent-runner";
import {
  createSupabaseMockImpl,
  createQueryMock,
} from "./helpers/agent-runner-mocks";

const BASE_USER_DATA = {
  workspace_path: "/tmp/test-workspace",
  repo_status: null,
  github_installation_id: null,
  repo_url: null,
};

function setupSupabaseMock() {
  createSupabaseMockImpl(mockFrom, { userData: BASE_USER_DATA, mockRpc });
}

function setupQueryMockImmediate() {
  createQueryMock(mockQuery);
}

describe("startAgentSession — context_reset signal (#3269)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) {
        return JSON.stringify({ mcpServers: {} });
      }
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
    // Default: helper passes resume through unchanged.
    mockApplyPrefillGuard.mockImplementation(async ({ resumeSessionId }) => ({
      safeResumeSessionId: resumeSessionId,
    }));
    setupSupabaseMock();
    setupQueryMockImmediate();
  });

  test("appends contextResetNotice to systemPrompt exactly when guard fires", async () => {
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: undefined,
      contextResetNotice: "RUNNER-RESET-NOTICE",
      reason: "prefill-guard",
    });

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", "session-s");

    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.systemPrompt).toContain("RUNNER-RESET-NOTICE");
  });

  test("does NOT mutate systemPrompt when guard does not fire", async () => {
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: "session-s",
    });

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", "session-s");

    const opts = mockQuery.mock.calls[0][0].options;
    expect(opts.systemPrompt).not.toContain("Prior conversation context was reset");
  });

  test("emits one context_reset WS event per guard fire with reason 'prefill-guard'", async () => {
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: undefined,
      contextResetNotice: "notice",
      reason: "prefill-guard",
    });

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", "session-s");

    const contextResetCalls = mockSendToClient.mock.calls.filter(
      (call) => call[1]?.type === "context_reset",
    );
    expect(contextResetCalls).toHaveLength(1);
    expect(contextResetCalls[0][0]).toBe("11111111-1111-4111-8111-111111111111");
    expect(contextResetCalls[0][1]).toEqual({
      type: "context_reset",
      reason: "prefill-guard",
      conversationId: "conv-1",
    });
  });

  test("emits reason 'tool_use_orphan' when trailing message had a tool_use content block", async () => {
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: undefined,
      contextResetNotice: "tool-aware",
      reason: "tool_use_orphan",
    });

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", "session-s");

    const contextResetCalls = mockSendToClient.mock.calls.filter(
      (call) => call[1]?.type === "context_reset",
    );
    expect(contextResetCalls).toHaveLength(1);
    expect(contextResetCalls[0][1].reason).toBe("tool_use_orphan");
  });

  test("does NOT emit context_reset when guard returns no notice (probe-fail / empty / user-final)", async () => {
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: "session-s",
    });

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", "session-s");

    const contextResetCalls = mockSendToClient.mock.calls.filter(
      (call) => call[1]?.type === "context_reset",
    );
    expect(contextResetCalls).toHaveLength(0);
  });

  test("does NOT carry the notice forward across calls when the guard does not fire on the second call (AC6b)", async () => {
    // First call: guard fires
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: undefined,
      contextResetNotice: "FIRST-CALL-NOTICE",
      reason: "prefill-guard",
    });
    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", "session-s");

    const firstOpts = mockQuery.mock.calls[0][0].options;
    expect(firstOpts.systemPrompt).toContain("FIRST-CALL-NOTICE");

    // Second call: guard does not fire
    mockApplyPrefillGuard.mockResolvedValueOnce({
      safeResumeSessionId: "session-s",
    });
    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", "session-s");

    const secondOpts = mockQuery.mock.calls[1][0].options;
    expect(secondOpts.systemPrompt).not.toContain("FIRST-CALL-NOTICE");
  });
});
