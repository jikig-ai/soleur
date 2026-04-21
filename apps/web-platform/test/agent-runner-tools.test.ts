import { vi, describe, test, expect, beforeEach } from "vitest";

// Env vars needed by serverUrl() guard — set before agent-runner is loaded
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// ---------------------------------------------------------------------------
// Mock all heavy dependencies so agent-runner loads without side effects.
// Use vi.hoisted() for variables referenced inside vi.mock() factories
// (vitest hoists vi.mock to the top of the file before let/const execute).
// ---------------------------------------------------------------------------

const { mockFrom, mockQuery, mockReadFileSync } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockQuery: vi.fn(),
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
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("../server/ws-handler", () => ({ sendToClient: vi.fn() }));
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
  // Default to "Approve" so gated tools pass through in wiring tests.
  // Tiered gating behavior is tested in canusertool-tiered-gating.test.ts.
  abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
  validateSelection: vi.fn(),
  extractReviewGateInput: vi.fn(),
  buildReviewGateResponse: vi.fn(),
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => {
  const leaders = [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }];
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
  DEFAULT_API_KEY_ROW,
  createSupabaseMockImpl,
  createQueryMock,
} from "./helpers/agent-runner-mocks";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function setupSupabaseMock(
  userData: Record<string, unknown>,
  serviceTokenRows?: Record<string, unknown>[],
) {
  createSupabaseMockImpl(mockFrom, { userData, apiKeyRows: serviceTokenRows });
}

function setupQueryMockImmediate() {
  createQueryMock(mockQuery);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("agent-runner MCP tool wiring", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Return plugin.json with MCP server entries when readFileSync is called
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) {
        return JSON.stringify({
          mcpServers: {
            context7: { type: "http", url: "https://mcp.context7.com/mcp" },
            cloudflare: { type: "http", url: "https://mcp.cloudflare.com/mcp" },
            vercel: { type: "http", url: "https://mcp.vercel.com" },
            stripe: { type: "http", url: "https://mcp.stripe.com" },
          },
        });
      }
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
  });

  test("passes mcpServers to query() when user has installationId and repo_url", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/alice/my-repo",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    expect(mockQuery).toHaveBeenCalledOnce();
    const options = mockQuery.mock.calls[0][0].options;

    // mcpServers should contain soleur_platform
    expect(options.mcpServers).toBeDefined();
    expect(options.mcpServers.soleur_platform).toBeDefined();

    // allowedTools should include the MCP tool
    expect(options.allowedTools).toContain("mcp__soleur_platform__create_pull_request");
  });

  test("omits GitHub platform tools when user has no installationId", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: null,
      github_installation_id: null,
      repo_url: null,
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    expect(mockQuery).toHaveBeenCalledOnce();
    const options = mockQuery.mock.calls[0][0].options;

    // KB share tools register unconditionally (#2309) so mcpServers is
    // defined — but the GitHub-specific tool names must not appear.
    expect(options.allowedTools).not.toContain(
      "mcp__soleur_platform__create_pull_request",
    );
    expect(options.allowedTools).not.toContain(
      "mcp__soleur_platform__github_read_ci_status",
    );
  });

  test("canUseTool allows registered platform MCP tools", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/alice/my-repo",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    // Registered platform tool should be allowed
    const result = await canUseTool(
      "mcp__soleur_platform__create_pull_request",
      { head: "feat-branch", base: "main", title: "test" },
      { signal: new AbortController().signal },
    );
    expect(result.behavior).toBe("allow");
  });

  test("canUseTool denies unregistered mcp__ tools", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/alice/my-repo",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    // Unregistered MCP tool should be denied (not blanket mcp__ allow)
    const result = await canUseTool(
      "mcp__other_server__dangerous_tool",
      {},
      { signal: new AbortController().signal },
    );
    expect(result.behavior).toBe("deny");
  });

  test("omits GitHub platform tools when repo_url owner contains URL-encoded traversal", async () => {
    // %2F decodes to '/' inside a segment — the regex rejects '%'
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/..%2F..%2Fetc/passwd",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    expect(mockQuery).toHaveBeenCalledOnce();
    const options = mockQuery.mock.calls[0][0].options;
    expect(options.allowedTools).not.toContain(
      "mcp__soleur_platform__create_pull_request",
    );
  });

  test("omits GitHub platform tools when repo_url has missing segments", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/owner-only",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    expect(mockQuery).toHaveBeenCalledOnce();
    const options = mockQuery.mock.calls[0][0].options;
    expect(options.allowedTools).not.toContain(
      "mcp__soleur_platform__create_pull_request",
    );
  });

  test("omits GitHub platform tools when repo_url is not a valid URL", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "not-a-url",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    expect(mockQuery).toHaveBeenCalledOnce();
    const options = mockQuery.mock.calls[0][0].options;
    expect(options.allowedTools).not.toContain(
      "mcp__soleur_platform__create_pull_request",
    );
  });

  test("omits GitHub platform tools when repo_url owner contains special characters", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/owner%2F..%2F/repo",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    expect(mockQuery).toHaveBeenCalledOnce();
    const options = mockQuery.mock.calls[0][0].options;
    expect(options.allowedTools).not.toContain(
      "mcp__soleur_platform__create_pull_request",
    );
  });

  test("canUseTool allows plugin MCP tools from registered servers", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/alice/my-repo",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    // Plugin MCP tool from a server registered in plugin.json should be allowed
    const result = await canUseTool(
      "mcp__plugin_soleur_cloudflare__zones_list",
      {},
      { signal: new AbortController().signal },
    );
    expect(result.behavior).toBe("allow");
  });

  test("canUseTool denies plugin MCP tools from unregistered servers", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/alice/my-repo",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    // Plugin MCP tool from an unregistered server should be denied
    const result = await canUseTool(
      "mcp__plugin_soleur_unknown__hack",
      {},
      { signal: new AbortController().signal },
    );
    expect(result.behavior).toBe("deny");
  });

  test("canUseTool denies non-plugin mcp__ tools", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/alice/my-repo",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    // Non-plugin MCP tool should still be denied
    const result = await canUseTool(
      "mcp__random_server__dangerous_tool",
      {},
      { signal: new AbortController().signal },
    );
    expect(result.behavior).toBe("deny");
  });

  test("allowedTools includes plugin MCP wildcard patterns", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/alice/my-repo",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;

    // allowedTools should include wildcard patterns for plugin MCP servers
    expect(options.allowedTools).toContain("mcp__plugin_soleur_cloudflare__*");
    expect(options.allowedTools).toContain("mcp__plugin_soleur_context7__*");
    expect(options.allowedTools).toContain("mcp__plugin_soleur_vercel__*");
    expect(options.allowedTools).toContain("mcp__plugin_soleur_stripe__*");
  });

  test("canUseTool still denies non-mcp unrecognized tools", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: null,
      github_installation_id: null,
      repo_url: null,
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    // Unknown non-mcp tools should still be denied
    const result = await canUseTool(
      "SomeUnknownTool",
      {},
      { signal: new AbortController().signal },
    );
    expect(result.behavior).toBe("deny");
  });

  test("platformToolNames includes Plausible tools when user has PLAUSIBLE_API_KEY", async () => {
    const plausibleRow = {
      ...DEFAULT_API_KEY_ROW,
      id: "key-plausible",
      provider: "plausible",
    };
    setupSupabaseMock(
      {
        workspace_path: "/tmp/test-workspace",
        repo_status: "ready",
        github_installation_id: 12345,
        repo_url: "https://github.com/alice/my-repo",
      },
      [DEFAULT_API_KEY_ROW, plausibleRow],
    );
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.allowedTools).toContain("mcp__soleur_platform__plausible_create_site");
    expect(options.allowedTools).toContain("mcp__soleur_platform__plausible_add_goal");
    expect(options.allowedTools).toContain("mcp__soleur_platform__plausible_get_stats");
  });

  test("Plausible tools registered even without GitHub installation", async () => {
    const plausibleRow = {
      ...DEFAULT_API_KEY_ROW,
      id: "key-plausible",
      provider: "plausible",
    };
    setupSupabaseMock(
      {
        workspace_path: "/tmp/test-workspace",
        repo_status: null,
        github_installation_id: null,
        repo_url: null,
      },
      [DEFAULT_API_KEY_ROW, plausibleRow],
    );
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.allowedTools).toContain("mcp__soleur_platform__plausible_create_site");
    // PR tool should NOT be present (no GitHub installation)
    expect(options.allowedTools).not.toContain("mcp__soleur_platform__create_pull_request");
  });

  test("Plausible tools not registered when user has no PLAUSIBLE_API_KEY", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/alice/my-repo",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const allowed = options.allowedTools ?? [];
    expect(allowed).not.toContain("mcp__soleur_platform__plausible_create_site");
  });

  test("canUseTool allows Plausible MCP tools when registered", async () => {
    const plausibleRow = {
      ...DEFAULT_API_KEY_ROW,
      id: "key-plausible",
      provider: "plausible",
    };
    setupSupabaseMock(
      {
        workspace_path: "/tmp/test-workspace",
        repo_status: "ready",
        github_installation_id: 12345,
        repo_url: "https://github.com/alice/my-repo",
      },
      [DEFAULT_API_KEY_ROW, plausibleRow],
    );
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    const canUseTool = options.canUseTool!;

    const result = await canUseTool(
      "mcp__soleur_platform__plausible_create_site",
      { domain: "example.com" },
      { signal: new AbortController().signal },
    );
    expect(result.behavior).toBe("allow");
  });

  test("system prompt includes Connected Services with Plausible when user has PLAUSIBLE_API_KEY", async () => {
    const plausibleRow = {
      ...DEFAULT_API_KEY_ROW,
      id: "key-plausible",
      provider: "plausible",
    };
    setupSupabaseMock(
      {
        workspace_path: "/tmp/test-workspace",
        repo_status: "ready",
        github_installation_id: 12345,
        repo_url: "https://github.com/alice/my-repo",
      },
      [DEFAULT_API_KEY_ROW, plausibleRow],
    );
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("## Connected Services");
    expect(options.systemPrompt).toContain("- Plausible: connected");
  });

  test("system prompt does NOT include Connected Services when user has no service tokens", async () => {
    setupSupabaseMock({
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/alice/my-repo",
    });
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    // Only anthropic row exists (skipped by getUserServiceTokens) → no Connected Services
    expect(options.systemPrompt).not.toContain("## Connected Services");
  });

  test("system prompt omits Plausible from Connected Services when no Plausible token", async () => {
    const cloudflareRow = {
      ...DEFAULT_API_KEY_ROW,
      id: "key-cloudflare",
      provider: "cloudflare",
    };
    setupSupabaseMock(
      {
        workspace_path: "/tmp/test-workspace",
        repo_status: "ready",
        github_installation_id: 12345,
        repo_url: "https://github.com/alice/my-repo",
      },
      [DEFAULT_API_KEY_ROW, cloudflareRow],
    );
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("## Connected Services");
    expect(options.systemPrompt).toContain("- Cloudflare: connected");
    expect(options.systemPrompt).not.toContain("- Plausible: connected");
  });
});
