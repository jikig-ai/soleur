// Integration tests for the kb_share_preview tool wiring in agent-runner.ts.
// Mirrors the harness shape of agent-runner-kb-share-tools.test.ts (#2497) —
// same vi.mock set, same setupSupabaseMock / setupQueryMockImmediate helpers.

import { vi, describe, test, expect, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const { mockFrom, mockRpc, mockQuery, mockReadFileSync } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
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

// PR-B (#3244 §1.5.1): tenant-client factory; route through the same
// mockFrom chain so existing assertions still apply.
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
  // PR-B (#3244 §1.4.2): decryptKey* now return Buffer (zeroize-on-finally).
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
  createSupabaseMockImpl(mockFrom, { userData, mockRpc });
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

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

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

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toMatch(/kb_share_preview/);
  });

  test("canUseTool routes kb_share_preview as auto-approve (no review gate)", async () => {
    setupSupabaseMock(USER_WITH_WORKSPACE);
    setupQueryMockImmediate();

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    const result = await canUseTool(
      "mcp__soleur_platform__kb_share_preview",
      { token: "tok-abc" },
      { signal: new AbortController().signal },
    );
    expect(result.behavior).toBe("allow");
  });

  test("wires kb_share_preview even when the legacy users.workspace_path is null (ADR-044 active-workspace convergence, test 33)", async () => {
    // Convergence regression guard (#4910 leader half). Pre-fix, a null
    // `users.workspace_path` threw ERR_WORKSPACE_NOT_PROVISIONED and the leader
    // session never wired its tools — the exact founder-class break for invited
    // members / post-relocation users whose legacy column is empty but whose
    // ACTIVE workspace is healthy. The leader now resolves the workspace via
    // `resolveActiveWorkspacePath` (fail-closed to solo, never throws on an empty
    // column), so the session wires normally against the active workspace's
    // kbRoot.
    setupSupabaseMock(USER_WITHOUT_WORKSPACE);
    setupQueryMockImmediate();

    // Must NOT throw — the empty legacy column is no longer a provisioning gate.
    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.allowedTools).toContain(
      "mcp__soleur_platform__kb_share_preview",
    );
  });
});
