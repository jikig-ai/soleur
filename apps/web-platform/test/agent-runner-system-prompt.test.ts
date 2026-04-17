import { vi, describe, test, expect, beforeEach } from "vitest";

// Env vars needed by serverUrl() guard — set before agent-runner is loaded
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

// ---------------------------------------------------------------------------
// Mock all heavy dependencies (same pattern as agent-runner-tools.test.ts)
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
  return { ...actual, readFileSync: mockReadFileSync };
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
  abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
  validateSelection: vi.fn(),
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
import type { ConversationContext } from "../lib/types";
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

const BASE_USER_DATA = {
  workspace_path: "/tmp/test-workspace",
  repo_status: "ready",
  github_installation_id: 12345,
  repo_url: "https://github.com/alice/my-repo",
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("agent-runner system prompt context injection", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) {
        return JSON.stringify({ mcpServers: {} });
      }
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
  });

  test("system prompt never contains absolute workspace paths", async () => {
    setupSupabaseMock(BASE_USER_DATA);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).not.toContain("/tmp/test-workspace");
    expect(options.systemPrompt).not.toContain("The user's workspace is at");
  });

  test("system prompt includes 'Never mention file system paths' instruction", async () => {
    setupSupabaseMock(BASE_USER_DATA);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("Never mention file system paths");
  });

  test("when context has path and content, system prompt includes artifact content", async () => {
    setupSupabaseMock(BASE_USER_DATA);
    setupQueryMockImmediate();

    const context: ConversationContext = {
      path: "knowledge-base/product/roadmap.md",
      type: "kb-viewer",
      content: "# Product Roadmap\n\nPhase 1...",
    };

    await startAgentSession("user-1", "conv-1", "cpo", undefined, undefined, context);

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("Artifact content:");
    expect(options.systemPrompt).toContain("# Product Roadmap");
  });

  test("when context has path but no content, system prompt instructs to read the file", async () => {
    setupSupabaseMock(BASE_USER_DATA);
    setupQueryMockImmediate();

    const context: ConversationContext = {
      path: "knowledge-base/product/roadmap.md",
      type: "kb-viewer",
    };

    await startAgentSession("user-1", "conv-1", "cpo", undefined, undefined, context);

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("Read this file first");
    expect(options.systemPrompt).toContain("knowledge-base/product/roadmap.md");
    expect(options.systemPrompt).not.toContain("Artifact content:");
  });

  test("system prompt says files are relative to cwd, not an absolute path", async () => {
    setupSupabaseMock(BASE_USER_DATA);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("relative to the current working directory");
  });

  // Closes #2315: agent cannot discover KB share tools without advertisement
  // in the system prompt. Block must appear whenever share tools are
  // registered (i.e., whenever the workspace is ready).
  test("system prompt contains Knowledge-base sharing block", async () => {
    setupSupabaseMock(BASE_USER_DATA);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("Knowledge-base sharing");
    expect(options.systemPrompt).toContain("kb_share_create");
    expect(options.systemPrompt).toContain("kb_share_list");
    expect(options.systemPrompt).toContain("kb_share_revoke");
  });

  test("system prompt warns about sensitive-path guardrail in KB sharing block", async () => {
    setupSupabaseMock(BASE_USER_DATA);
    setupQueryMockImmediate();

    await startAgentSession("user-1", "conv-1", "cpo");

    const options = mockQuery.mock.calls[0][0].options;
    // The capability block must instruct the agent to confirm before
    // creating a link on sensitive-looking paths. Tests the section inside
    // the KB-sharing block, not just the base prompt.
    const sharingBlock =
      options.systemPrompt.split("Knowledge-base sharing")[1] ?? "";
    expect(sharingBlock.toLowerCase()).toMatch(/sensitive|credentials/);
  });
});
