import { vi, describe, test, expect, beforeEach } from "vitest";

// Env vars needed by serverUrl() guard — set before agent-runner is loaded
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

import { startAgentSession } from "../server/agent-runner";
import {
  getToolTier,
  buildGateMessage,
  TOOL_TIER_MAP,
} from "../server/tool-tiers";
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

const USER_WITH_GITHUB = {
  workspace_path: "/tmp/test-workspace",
  repo_status: "ready",
  github_installation_id: 12345,
  repo_url: "https://github.com/alice/my-repo",
};

const USER_WITHOUT_GITHUB = {
  workspace_path: "/tmp/test-workspace",
  repo_status: null,
  github_installation_id: null,
  repo_url: null,
};

describe("agent-runner kb_share_* tool wiring", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) {
        return JSON.stringify({ mcpServers: {} });
      }
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
  });

  test("registers kb_share_create, kb_share_list, kb_share_revoke when workspace ready", async () => {
    setupSupabaseMock(USER_WITH_GITHUB);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.allowedTools).toContain("mcp__soleur_platform__kb_share_create");
    expect(options.allowedTools).toContain("mcp__soleur_platform__kb_share_list");
    expect(options.allowedTools).toContain("mcp__soleur_platform__kb_share_revoke");
  });

  // Applies learning 2026-04-10-service-tool-registration-scope-guard:
  // kb_share_* tools must register INDEPENDENTLY of the GitHub installation
  // guard. Prevents a future refactor from silently gating KB tools behind
  // an unrelated prerequisite.
  test("registers kb_share_* tools for users without GitHub installation", async () => {
    setupSupabaseMock(USER_WITHOUT_GITHUB);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    // GitHub tools absent — but KB share tools present.
    expect(options.allowedTools).not.toContain(
      "mcp__soleur_platform__create_pull_request",
    );
    expect(options.allowedTools).toContain("mcp__soleur_platform__kb_share_create");
    expect(options.allowedTools).toContain("mcp__soleur_platform__kb_share_list");
    expect(options.allowedTools).toContain("mcp__soleur_platform__kb_share_revoke");
    // mcpServers built even without GitHub because KB share tools exist.
    expect(options.mcpServers?.soleur_platform).toBeDefined();
  });

  test("canUseTool routes kb_share_list as auto-approve (read-only)", async () => {
    setupSupabaseMock(USER_WITH_GITHUB);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    const result = await canUseTool(
      "mcp__soleur_platform__kb_share_list",
      {},
      { signal: new AbortController().signal },
    );
    expect(result.behavior).toBe("allow");
  });

  test("canUseTool routes kb_share_create through review gate (gated)", async () => {
    setupSupabaseMock(USER_WITH_GITHUB);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    const result = await canUseTool(
      "mcp__soleur_platform__kb_share_create",
      { documentPath: "readme.md" },
      { signal: new AbortController().signal },
    );
    // Review-gate mock returns "Approve" — so the call allows.
    expect(result.behavior).toBe("allow");
  });

  test("canUseTool routes kb_share_revoke through review gate (gated)", async () => {
    setupSupabaseMock(USER_WITH_GITHUB);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    const result = await canUseTool(
      "mcp__soleur_platform__kb_share_revoke",
      { token: "tok-1234567890" },
      { signal: new AbortController().signal },
    );
    expect(result.behavior).toBe("allow");
  });
});

describe("tool tier map entries for kb_share tools", () => {
  // Explicit TOOL_TIER_MAP entries required — default fail-closed ("gated")
  // would mask a missing kb_share_list entry otherwise.
  test("kb_share_list is explicitly mapped to auto-approve", () => {
    expect(TOOL_TIER_MAP).toHaveProperty(
      "mcp__soleur_platform__kb_share_list",
      "auto-approve",
    );
    expect(getToolTier("mcp__soleur_platform__kb_share_list")).toBe("auto-approve");
  });

  test("kb_share_create is explicitly mapped to gated", () => {
    expect(TOOL_TIER_MAP).toHaveProperty(
      "mcp__soleur_platform__kb_share_create",
      "gated",
    );
  });

  test("kb_share_revoke is explicitly mapped to gated", () => {
    expect(TOOL_TIER_MAP).toHaveProperty(
      "mcp__soleur_platform__kb_share_revoke",
      "gated",
    );
  });
});

describe("buildGateMessage for kb_share tools", () => {
  test("kb_share_create message references the document path", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__kb_share_create",
      { documentPath: "product/roadmap.md" },
    );
    expect(msg).toContain("product/roadmap.md");
    expect(msg.toLowerCase()).toContain("share");
  });

  test("kb_share_revoke message references the token preview", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__kb_share_revoke",
      { token: "abcdef1234567890-long-token" },
    );
    expect(msg).toMatch(/abcdef1234/);
    expect(msg.toLowerCase()).toContain("revoke");
  });
});
