// Integration tests for the kb_share_preview tool wiring in agent-runner.ts.
// Mirrors the harness shape of agent-runner-kb-share-tools.test.ts (#2497) —
// same vi.mock set, same setupSupabaseMock / setupQueryMockImmediate helpers.

import { vi, describe, test, expect, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const { mockFrom, mockQuery, mockReadFileSync } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn(
    (name: string, _desc: string, _schema: unknown, handler: Function) => ({
      name,
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
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("../server/ws-handler", () => ({ sendToClient: vi.fn() }));
vi.mock("../server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
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
    { id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" },
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
  warnSilentFallback: vi.fn(),
}));

import { startAgentSession } from "../server/agent-runner";
import { getToolTier, TOOL_TIER_MAP } from "../server/tool-tiers";
import {
  createSupabaseMockImpl,
  createQueryMock,
} from "./helpers/agent-runner-mocks";

function setupSupabaseMock(userData: Record<string, unknown>) {
  createSupabaseMockImpl(mockFrom, { userData });
}

function setupQueryMockImmediate() {
  createQueryMock(mockQuery);
}

const USER_WITH_WORKSPACE = {
  workspace_path: "/tmp/test-workspace",
  repo_status: "ready",
  github_installation_id: 12345,
  repo_url: "https://github.com/alice/my-repo",
};

const USER_WITHOUT_WORKSPACE = {
  workspace_path: null,
  repo_status: null,
  github_installation_id: null,
  repo_url: null,
};

describe("agent-runner kb_share_preview tool wiring", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) {
        return JSON.stringify({ mcpServers: {} });
      }
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
  });

  test("registers kb_share_preview when workspace ready (tests 29, 30)", async () => {
    setupSupabaseMock(USER_WITH_WORKSPACE);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.allowedTools).toContain(
      "mcp__soleur_platform__kb_share_preview",
    );
  });

  test("kb_share_preview is explicitly mapped to auto-approve (test 31)", () => {
    expect(TOOL_TIER_MAP).toHaveProperty(
      "mcp__soleur_platform__kb_share_preview",
      "auto-approve",
    );
    expect(getToolTier("mcp__soleur_platform__kb_share_preview")).toBe(
      "auto-approve",
    );
  });

  test("system prompt advertises kb_share_preview capability (test 32)", async () => {
    setupSupabaseMock(USER_WITH_WORKSPACE);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toMatch(/kb_share_preview/);
  });

  test("canUseTool routes kb_share_preview as auto-approve (no review gate)", async () => {
    setupSupabaseMock(USER_WITH_WORKSPACE);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    const result = await canUseTool(
      "mcp__soleur_platform__kb_share_preview",
      { token: "tok-abc" },
      { signal: new AbortController().signal },
    );
    expect(result.behavior).toBe("allow");
  });

  test("does not register kb_share_preview when workspace unavailable (test 33)", async () => {
    setupSupabaseMock(USER_WITHOUT_WORKSPACE);
    setupQueryMockImmediate();

    // Workspace path is null — startAgentSession is expected to reject
    // via ERR_WORKSPACE_NOT_PROVISIONED before tool registration runs.
    // The invariant: either the session rejects, or allowedTools does NOT
    // include kb_share_preview. Defense in depth against registering the
    // preview tool against an undefined kbRoot.
    let threw = false;
    try {
      await startAgentSession("user-1", "conv-1", "cpo");
    } catch {
      threw = true;
    }

    if (!threw && mockQuery.mock.calls.length > 0) {
      const options = mockQuery.mock.calls[0][0].options;
      expect(options.allowedTools ?? []).not.toContain(
        "mcp__soleur_platform__kb_share_preview",
      );
    }
  });
});
