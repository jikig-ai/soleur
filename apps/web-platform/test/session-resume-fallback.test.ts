import { vi, describe, test, expect, beforeEach } from "vitest";

// Env vars needed by serverUrl() guard — set before agent-runner is loaded
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// ---------------------------------------------------------------------------
// Mock all heavy dependencies so agent-runner loads without side effects.
// Use vi.hoisted() for variables referenced inside vi.mock() factories.
// ---------------------------------------------------------------------------

const { mockFrom, mockQuery, mockSendToClient, mockCaptureException, mockReadFileSync } =
  vi.hoisted(() => ({
    mockFrom: vi.fn(),
    mockQuery: vi.fn(),
    mockSendToClient: vi.fn(),
    mockCaptureException: vi.fn(),
    mockReadFileSync: vi.fn(),
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
  return {
    ...actual,
    readFileSync: mockReadFileSync,
  };
});

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockFrom })),
}));
vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
}));
vi.mock("../server/ws-handler", () => ({
  sendToClient: mockSendToClient,
}));
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
  sanitizeErrorForClient: vi.fn(() => "sanitized error"),
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
    { id: "cto", name: "CTO", title: "Chief Technology Officer", description: "Technology" },
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const STALE_SESSION_ID = "544e6cdb-461b-40f6-bd78-498893569a6e";
const RESUME_ERROR_MSG = `Claude Code returned an error result: No conversation found with session ID: ${STALE_SESSION_ID}`;

const DEFAULT_API_KEY_ROW = {
  id: "key-1",
  provider: "anthropic",
  encrypted_key: Buffer.from("test").toString("base64"),
  iv: Buffer.from("test-iv-1234").toString("base64"),
  auth_tag: Buffer.from("test-tag-1234567").toString("base64"),
  key_version: 2,
};

function createApiKeysMock(rows: Record<string, unknown>[] = [DEFAULT_API_KEY_ROW]) {
  const createChain = (): Record<string, unknown> => ({
    data: rows,
    error: null,
    eq: () => createChain(),
    limit: () => ({ single: () => ({ data: rows[0] ?? null, error: null }) }),
    then: (resolve: (v: unknown) => void) => resolve({ data: rows, error: null }),
  });
  return { select: () => createChain() };
}

const mockConversationUpdate = vi.fn(() => ({
  eq: vi.fn(() => ({ error: null })),
}));

function setupSupabaseMock() {
  mockFrom.mockImplementation((table: string) => {
    if (table === "api_keys") {
      return createApiKeysMock();
    }
    if (table === "users") {
      return {
        select: () => ({
          eq: () => ({
            single: () => ({
              data: {
                workspace_path: "/tmp/test-workspace",
                repo_status: "ready",
                github_installation_id: null,
                repo_url: null,
              },
              error: null,
            }),
          }),
        }),
      };
    }
    if (table === "conversations") {
      return {
        update: mockConversationUpdate,
      };
    }
    if (table === "messages") {
      return { insert: () => ({ error: null }) };
    }
    return {
      select: () => ({ eq: () => ({ single: () => ({ data: null, error: null }) }) }),
      update: () => ({ eq: () => ({ error: null }) }),
      insert: () => ({ error: null }),
    };
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("session resume fallback", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) {
        return JSON.stringify({ mcpServers: {} });
      }
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
  });

  test("startAgentSession rejects when SDK throws stale session error on resume", async () => {
    setupSupabaseMock();
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        throw new Error(RESUME_ERROR_MSG);
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as any);

    await expect(
      startAgentSession("user-1", "conv-1", "cto", STALE_SESSION_ID, "test message"),
    ).rejects.toThrow("No conversation found with session ID");
  });

  test("sends stream_end before re-throwing on stale resume", async () => {
    setupSupabaseMock();
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        throw new Error(RESUME_ERROR_MSG);
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as any);

    await startAgentSession("user-1", "conv-1", "cto", STALE_SESSION_ID, "test message").catch(
      () => {},
    );

    // stream_start is sent at line 1020 before iterating, then stream_end on resume failure
    const streamEndCalls = mockSendToClient.mock.calls.filter(
      (call: unknown[]) => (call[1] as Record<string, unknown>).type === "stream_end",
    );
    expect(streamEndCalls.length).toBeGreaterThanOrEqual(1);
  });

  test("does NOT call Sentry.captureException on stale resume re-throw", async () => {
    setupSupabaseMock();
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        throw new Error(RESUME_ERROR_MSG);
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as any);

    await startAgentSession("user-1", "conv-1", "cto", STALE_SESSION_ID, "test message").catch(
      () => {},
    );

    expect(mockCaptureException).not.toHaveBeenCalled();
  });

  test("does NOT send error message to client on stale resume re-throw", async () => {
    setupSupabaseMock();
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        throw new Error(RESUME_ERROR_MSG);
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as any);

    await startAgentSession("user-1", "conv-1", "cto", STALE_SESSION_ID, "test message").catch(
      () => {},
    );

    const errorCalls = mockSendToClient.mock.calls.filter(
      (call: unknown[]) => (call[1] as Record<string, unknown>).type === "error",
    );
    expect(errorCalls).toHaveLength(0);
  });

  test("does NOT mark conversation as failed on stale resume re-throw", async () => {
    setupSupabaseMock();
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        throw new Error(RESUME_ERROR_MSG);
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as any);

    await startAgentSession("user-1", "conv-1", "cto", STALE_SESSION_ID, "test message").catch(
      () => {},
    );

    // The conversations.update mock should NOT have been called with "failed" status
    // (it may have been called for other reasons like status updates, but not from the error path)
    const updateCalls = mockConversationUpdate.mock.calls as unknown[][];
    for (const call of updateCalls) {
      const arg = call[0] as Record<string, unknown> | undefined;
      if (arg && "status" in arg) {
        expect(arg.status).not.toBe("failed");
      }
    }
  });

  test("non-resume errors still follow normal error path (Sentry + client error)", async () => {
    setupSupabaseMock();
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        throw new Error("Some other SDK error");
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as any);

    // Non-resume errors should NOT reject (internal catch resolves the promise)
    await startAgentSession("user-1", "conv-1", "cto", undefined, "test message");

    // Sentry should be called for non-resume errors
    expect(mockCaptureException).toHaveBeenCalledOnce();

    // Error should be sent to client
    const errorCalls = mockSendToClient.mock.calls.filter(
      (call: unknown[]) => (call[1] as Record<string, unknown>).type === "error",
    );
    expect(errorCalls).toHaveLength(1);
  });
});
