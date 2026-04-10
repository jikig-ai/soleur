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
} = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockQuery: vi.fn(),
  mockSendToClient: vi.fn(),
  mockAbortableReviewGate: vi.fn(),
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

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockFrom })),
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
  abortableReviewGate: mockAbortableReviewGate,
  validateSelection: vi.fn(),
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => ({
  DOMAIN_LEADERS: [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }],
}));
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({
  syncPull: vi.fn(),
  syncPush: vi.fn(),
}));

import { startAgentSession } from "../server/agent-runner";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function setupSupabaseMock(userData: Record<string, unknown>) {
  mockFrom.mockImplementation((table: string) => {
    if (table === "api_keys") {
      return {
        select: () => ({
          eq: () => ({
            eq: () => ({
              eq: () => ({
                limit: () => ({
                  single: () => ({
                    data: {
                      id: "key-1",
                      encrypted_key: Buffer.from("test").toString("base64"),
                      iv: Buffer.from("test-iv-1234").toString("base64"),
                      auth_tag: Buffer.from("test-tag-1234567").toString("base64"),
                      key_version: 2,
                    },
                    error: null,
                  }),
                }),
              }),
            }),
          }),
        }),
      };
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("canUseTool tiered gating (#1926)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
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

      const logSpy = vi.fn();
      const originalLog = console.log;
      console.log = logSpy;

      try {
        const canUseTool = await getCanUseTool();

        await canUseTool(
          "mcp__soleur_platform__create_pull_request",
          { head: "feat-branch", base: "main", title: "test" },
          { signal: new AbortController().signal },
        );

        // At least one call should contain structured audit data
        const auditCalls = logSpy.mock.calls.filter((args: unknown[]) => {
          const msg = typeof args[0] === "string" ? args[0] : "";
          try {
            const parsed = JSON.parse(msg);
            return parsed.tool && parsed.tier && parsed.decision;
          } catch {
            return false;
          }
        });
        expect(auditCalls.length).toBeGreaterThan(0);

        // Verify audit log contains expected fields
        const firstAudit = JSON.parse(auditCalls[0][0] as string);
        expect(firstAudit.tool).toBe("mcp__soleur_platform__create_pull_request");
        expect(firstAudit.tier).toBe("gated");
        expect(firstAudit.repo).toBe("alice/my-repo");
        expect(firstAudit.ts).toBeTypeOf("number");
      } finally {
        console.log = originalLog;
      }
    });

    test("audit log records rejection decision", async () => {
      mockAbortableReviewGate.mockResolvedValue("Reject");

      const logSpy = vi.fn();
      const originalLog = console.log;
      console.log = logSpy;

      try {
        const canUseTool = await getCanUseTool();

        await canUseTool(
          "mcp__soleur_platform__create_pull_request",
          { head: "feat-branch", base: "main", title: "test" },
          { signal: new AbortController().signal },
        );

        const auditCalls = logSpy.mock.calls
          .filter((args: unknown[]) => {
            try {
              const parsed = JSON.parse(args[0] as string);
              return parsed.tool && parsed.decision;
            } catch {
              return false;
            }
          })
          .map((args: unknown[]) => JSON.parse(args[0] as string));

        // Should have a "rejected" decision log
        const rejectedLog = auditCalls.find(
          (log: Record<string, unknown>) => log.decision === "rejected",
        );
        expect(rejectedLog).toBeDefined();
      } finally {
        console.log = originalLog;
      }
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
