/**
 * canUseTool Tiered Gating Integration Tests (Phase 1, #1926)
 *
 * Tests the end-to-end tiered gating behavior in agent-runner's canUseTool:
 * - Gated tier: MCP tool triggers review gate via sendToClient + abortableReviewGate
 * - Audit logging: structured JSON emitted for platform tool invocations
 *
 * Auto-approve tier tests are added in Phase 2 when read tools are registered.
 * Blocked tier tests are added when blocked tools are defined.
 *
 * Follows the agent-runner-tools.test.ts mock pattern: boot a session,
 * extract canUseTool from the mockQuery call, and test it directly.
 */
import { vi, describe, test, expect, beforeEach } from "vitest";

// Env vars needed by serverUrl() guard
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// ---------------------------------------------------------------------------
// vi.hoisted — variables referenced inside vi.mock() factories
// ---------------------------------------------------------------------------
const {
  mockFrom,
  mockQuery,
  mockSendToClient,
  mockAbortableReviewGate,
  mockLogInfo,
  mockReadFileSync,
} = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockQuery: vi.fn(),
  mockSendToClient: vi.fn(),
  mockAbortableReviewGate: vi.fn(),
  mockLogInfo: vi.fn(),
  mockReadFileSync: vi.fn(),
}));

// ---------------------------------------------------------------------------
// Mock heavy dependencies (same pattern as agent-runner-tools.test.ts)
// ---------------------------------------------------------------------------
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
  createClient: vi.fn(() => ({ from: mockFrom })),
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("../server/ws-handler", () => ({ sendToClient: mockSendToClient }));
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: mockLogInfo,
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
  abortableReviewGate: mockAbortableReviewGate,
  validateSelection: vi.fn(),
  extractReviewGateInput: vi.fn(),
  buildReviewGateResponse: vi.fn(),
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => {
  const leaders = [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }];
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
}));

import { startAgentSession } from "../server/agent-runner";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const DEFAULT_API_KEY_ROW = {
  id: "key-1",
  provider: "anthropic",
  encrypted_key: Buffer.from("test").toString("base64"),
  iv: Buffer.from("test-iv-1234").toString("base64"),
  auth_tag: Buffer.from("test-tag-1234567").toString("base64"),
  key_version: 2,
};

// Creates a chainable mock that supports both:
// - getUserApiKey: select().eq().eq().eq().limit().single() -> { data, error }
// - getUserServiceTokens: await select().eq().eq() -> { data, error }
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

function setupSupabaseMock(userData: Record<string, unknown>) {
  mockFrom.mockImplementation((table: string) => {
    if (table === "api_keys") {
      return createApiKeysMock();
    }
    if (table === "users") {
      return {
        select: () => ({
          eq: () => ({
            single: () => ({
              data: userData,
              error: null,
            }),
          }),
        }),
      };
    }
    if (table === "conversations") {
      return {
        update: vi.fn(() => ({
          eq: vi.fn(() => ({ error: null })),
        })),
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

function setupQueryMockImmediate() {
  mockQuery.mockReturnValue({
    async *[Symbol.asyncIterator]() {
      yield { type: "result", session_id: "sess-1" };
    },
    next: vi.fn(),
    return: vi.fn(),
    throw: vi.fn(),
  } as any);
}

async function getCanUseTool() {
  setupSupabaseMock({
    workspace_path: "/tmp/test-workspace",
    repo_status: "ready",
    github_installation_id: 12345,
    repo_url: "https://github.com/alice/my-repo",
  });
  setupQueryMockImmediate();

  await startAgentSession("user-1", "conv-1", "cpo");

  const options = mockQuery.mock.calls[0][0].options;
  return options.canUseTool! as (
    toolName: string,
    toolInput: Record<string, unknown>,
    options: { signal: AbortSignal; agentID?: string },
  ) => Promise<{ behavior: string; message?: string; updatedInput?: Record<string, unknown> }>;
}

/**
 * Find a structured audit log call matching the given filter.
 * Throws a descriptive error listing all actual audit calls if no match found.
 */
function findAuditLog(
  mock: ReturnType<typeof vi.fn>,
  filter: (obj: Record<string, unknown>) => boolean,
): Record<string, unknown> {
  const allAuditCalls = mock.mock.calls.filter(
    (args: unknown[]) => {
      const obj = args[0] as Record<string, unknown>;
      return obj?.tool && obj?.tier;
    },
  );
  const match = allAuditCalls.find((args: unknown[]) =>
    filter(args[0] as Record<string, unknown>),
  );
  if (!match) {
    const summaries = allAuditCalls.map(
      (args: unknown[]) => JSON.stringify(args[0]),
    );
    throw new Error(
      `No audit log matched filter. Actual audit calls (${allAuditCalls.length}):\n${summaries.join("\n")}`,
    );
  }
  return match[0] as Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("canUseTool tiered gating (#1926)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) {
        return JSON.stringify({ mcpServers: {} });
      }
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
  });

  describe("gated tier", () => {
    test("create_pull_request triggers review gate (not auto-allowed)", async () => {
      mockAbortableReviewGate.mockResolvedValue("Approve");
      const canUseTool = await getCanUseTool();

      const result = await canUseTool(
        "mcp__soleur_platform__create_pull_request",
        { head: "feat-branch", base: "main", title: "test PR" },
        { signal: new AbortController().signal },
      );

      expect(result.behavior).toBe("allow");
      // The gate must fire — create_pull_request is now gated, not auto-approved
      expect(mockSendToClient).toHaveBeenCalledWith(
        "user-1",
        expect.objectContaining({ type: "review_gate" }),
      );
      expect(mockAbortableReviewGate).toHaveBeenCalled();
    });

    test("create_pull_request denied when user rejects gate", async () => {
      mockAbortableReviewGate.mockResolvedValue("Reject");
      const canUseTool = await getCanUseTool();

      const result = await canUseTool(
        "mcp__soleur_platform__create_pull_request",
        { head: "feat-branch", base: "main", title: "test PR" },
        { signal: new AbortController().signal },
      );

      expect(result.behavior).toBe("deny");
      expect(result.message).toMatch(/rejected|denied/i);
    });

    test("review gate message is human-readable for create_pull_request", async () => {
      mockAbortableReviewGate.mockResolvedValue("Approve");
      const canUseTool = await getCanUseTool();

      await canUseTool(
        "mcp__soleur_platform__create_pull_request",
        { head: "feat-branch", base: "main", title: "My PR Title" },
        { signal: new AbortController().signal },
      );

      const gateCall = mockSendToClient.mock.calls.find(
        (call: unknown[]) =>
          (call[1] as Record<string, unknown>).type === "review_gate",
      );
      expect(gateCall).toBeDefined();
      const gatePayload = gateCall![1] as {
        type: string;
        question: string;
        options: string[];
      };
      // Message should describe what the agent wants to do
      expect(gatePayload.question).toMatch(/open PR/i);
      expect(gatePayload.question).toContain("My PR Title");
      expect(gatePayload.options).toEqual(["Approve", "Reject"]);
    });
  });

  describe("audit logging", () => {
    test("structured audit log emitted for gated tool", async () => {
      mockAbortableReviewGate.mockResolvedValue("Approve");
      const canUseTool = await getCanUseTool();

      await canUseTool(
        "mcp__soleur_platform__create_pull_request",
        { head: "feat-branch", base: "main", title: "test" },
        { signal: new AbortController().signal },
      );

      // Logger.info should have been called with audit data
      const auditData = findAuditLog(mockLogInfo, (obj) =>
        obj.tool === "mcp__soleur_platform__create_pull_request" && obj.decision === "approved",
      );
      expect(auditData.tool).toBe("mcp__soleur_platform__create_pull_request");
      expect(auditData.tier).toBe("gated");
      expect(auditData.decision).toBe("approved");
      expect(auditData.repo).toBe("alice/my-repo");
    });

    test("audit log records rejection decision", async () => {
      mockAbortableReviewGate.mockResolvedValue("Reject");
      const canUseTool = await getCanUseTool();

      await canUseTool(
        "mcp__soleur_platform__create_pull_request",
        { head: "feat-branch", base: "main", title: "test" },
        { signal: new AbortController().signal },
      );

      const auditData = findAuditLog(mockLogInfo, (obj) =>
        obj.decision === "rejected",
      );
      expect(auditData.decision).toBe("rejected");
    });
  });

  describe("auto-approve tier", () => {
    test("structured audit log emitted for auto-approved tool", async () => {
      const canUseTool = await getCanUseTool();

      await canUseTool(
        "mcp__soleur_platform__github_read_ci_status",
        { owner: "alice", repo: "my-repo", ref: "main" },
        { signal: new AbortController().signal },
      );

      const auditData = findAuditLog(mockLogInfo, (obj) =>
        obj.tool === "mcp__soleur_platform__github_read_ci_status" && obj.tier === "auto-approve",
      );
      expect(auditData.tool).toBe("mcp__soleur_platform__github_read_ci_status");
      expect(auditData.tier).toBe("auto-approve");
      expect(auditData.decision).toBe("auto-approved");
      // Review gate should NOT have been called for auto-approve tools
      expect(mockAbortableReviewGate).not.toHaveBeenCalled();
    });
  });

  describe("auto-approve tier (#1927)", () => {
    test("github_read_ci_status auto-approved without review gate", async () => {
      const canUseTool = await getCanUseTool();

      const result = await canUseTool(
        "mcp__soleur_platform__github_read_ci_status",
        { branch: "main", per_page: 10 },
        { signal: new AbortController().signal },
      );

      expect(result.behavior).toBe("allow");
      // No review gate should fire for auto-approve tools
      expect(mockSendToClient).not.toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ type: "review_gate" }),
      );
      expect(mockAbortableReviewGate).not.toHaveBeenCalled();
    });

    test("github_read_workflow_logs auto-approved without review gate", async () => {
      const canUseTool = await getCanUseTool();

      const result = await canUseTool(
        "mcp__soleur_platform__github_read_workflow_logs",
        { run_id: 12345 },
        { signal: new AbortController().signal },
      );

      expect(result.behavior).toBe("allow");
      expect(mockSendToClient).not.toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ type: "review_gate" }),
      );
      expect(mockAbortableReviewGate).not.toHaveBeenCalled();
    });

    test("auto-approve audit log emitted with correct tier", async () => {
      const canUseTool = await getCanUseTool();

      await canUseTool(
        "mcp__soleur_platform__github_read_ci_status",
        { branch: "main" },
        { signal: new AbortController().signal },
      );

      const auditCall = mockLogInfo.mock.calls.find(
        (args: unknown[]) => {
          const obj = args[0] as Record<string, unknown>;
          return obj?.tool === "mcp__soleur_platform__github_read_ci_status"
            && obj?.tier === "auto-approve";
        },
      );
      expect(auditCall).toBeDefined();
      const auditData = auditCall![0] as Record<string, unknown>;
      expect(auditData.decision).toBe("auto-approved");
      expect(auditData.repo).toBe("alice/my-repo");
    });
  });

  describe("unregistered tools still denied", () => {
    test("non-platform MCP tools are denied by default", async () => {
      const canUseTool = await getCanUseTool();

      const result = await canUseTool(
        "mcp__other_server__some_tool",
        {},
        { signal: new AbortController().signal },
      );

      expect(result.behavior).toBe("deny");
    });

    test("unknown tools are denied by default", async () => {
      const canUseTool = await getCanUseTool();

      const result = await canUseTool(
        "SomeRandomTool",
        {},
        { signal: new AbortController().signal },
      );

      expect(result.behavior).toBe("deny");
    });
  });
});
