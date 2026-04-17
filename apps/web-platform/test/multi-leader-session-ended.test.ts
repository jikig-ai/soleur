import { vi, describe, test, expect, beforeEach } from "vitest";

// Env vars needed by serverUrl() guard
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// ---------------------------------------------------------------------------
// Mock dependencies (same pattern as agent-runner-system-prompt.test.ts)
// ---------------------------------------------------------------------------

const { mockFrom, mockQuery, mockReadFileSync, mockSendToClient } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
  mockSendToClient: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn((_name: string, _desc: string, _schema: unknown, handler: Function) => ({
    name: _name,
    handler,
  })),
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
  createClient: vi.fn(() => ({
    from: mockFrom,
    rpc: vi.fn().mockResolvedValue({ error: null }),
  })),
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
  decryptKey: vi.fn(() => "sk-test-key"),
  decryptKeyLegacy: vi.fn(),
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
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => {
  const leaders = [
    { id: "cpo", name: "Desi", title: "Chief Product Officer", description: "Product" },
    { id: "coo", name: "Kelsey", title: "Chief Operations Officer", description: "Operations" },
    { id: "cmo", name: "Veena", title: "Chief Marketing Officer", description: "Marketing" },
  ];
  return {
    DOMAIN_LEADERS: leaders,
    ROUTABLE_DOMAIN_LEADERS: leaders,
  };
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
}));

import { startAgentSession } from "../server/agent-runner";
import {
  createSupabaseMockImpl,
} from "./helpers/agent-runner-mocks";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const BASE_USER_DATA = {
  workspace_path: "/tmp/test-workspace",
  repo_status: "ready",
  github_installation_id: 12345,
  repo_url: "https://github.com/alice/my-repo",
};

function setupMocks() {
  createSupabaseMockImpl(mockFrom, { userData: BASE_USER_DATA });
}

/**
 * Create a query mock that emits a result event — simulating a leader that
 * finishes normally and sends stream_end + session_ended.
 */
function setupQueryMockWithResult() {
  mockQuery.mockReturnValue({
    async *[Symbol.asyncIterator]() {
      yield { type: "result", session_id: "sess-1" };
    },
    next: vi.fn(),
    return: vi.fn(),
    throw: vi.fn(),
  } as any);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("multi-leader session_ended (#2428)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) {
        return JSON.stringify({ mcpServers: {} });
      }
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
  });

  test("startAgentSession with skipSessionEnded=true does NOT send session_ended", async () => {
    setupMocks();
    setupQueryMockWithResult();

    await startAgentSession(
      "user-1", "conv-1", "cpo", undefined, "test message", undefined, undefined,
      true, // skipSessionEnded
    );

    const sessionEndedCalls = mockSendToClient.mock.calls.filter(
      (call) => (call[1] as { type: string }).type === "session_ended",
    );
    expect(sessionEndedCalls).toHaveLength(0);
  });

  test("startAgentSession without skipSessionEnded sends session_ended (single-leader backward compat)", async () => {
    setupMocks();
    setupQueryMockWithResult();

    await startAgentSession("user-1", "conv-1", "cpo");

    const sessionEndedCalls = mockSendToClient.mock.calls.filter(
      (call) => (call[1] as { type: string }).type === "session_ended",
    );
    expect(sessionEndedCalls).toHaveLength(1);
    expect(sessionEndedCalls[0][1]).toEqual({
      type: "session_ended",
      reason: "turn_complete",
    });
  });

  test("stream_end is still sent per-leader even when skipSessionEnded=true", async () => {
    setupMocks();
    setupQueryMockWithResult();

    await startAgentSession(
      "user-1", "conv-1", "cpo", undefined, "test", undefined, undefined,
      true,
    );

    const streamEndCalls = mockSendToClient.mock.calls.filter(
      (call) => (call[1] as { type: string }).type === "stream_end",
    );
    expect(streamEndCalls).toHaveLength(1);
    expect(streamEndCalls[0][1].leaderId).toBe("cpo");
  });
});
