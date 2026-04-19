import { vi, describe, test, expect, beforeEach } from "vitest";

// Env var needed by serverUrl() guard — set before agent-runner is loaded
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// ---------------------------------------------------------------------------
// Mock all heavy dependencies so agent-runner loads without side effects.
// vi.hoisted() because vi.mock() factories run before let/const execute.
// Mirrors agent-runner-tools.test.ts preamble (vitest hoists vi.mock per-file,
// so each test file needs its own declarations).
// ---------------------------------------------------------------------------

const { mockFrom, mockQuery, mockReadFileSync, mockReportSilentFallback } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
  mockReportSilentFallback: vi.fn(),
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
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
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
  extractReviewGateInput: vi.fn(),
  buildReviewGateResponse: vi.fn(),
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => {
  const leaders = [
    { id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" },
  ];
  return { DOMAIN_LEADERS: leaders, ROUTABLE_DOMAIN_LEADERS: leaders };
});
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({ syncPull: vi.fn(), syncPush: vi.fn() }));
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
  reportSilentFallback: mockReportSilentFallback,
  reportSilentFallbackWarning: vi.fn(),
}));

import { startAgentSession } from "../server/agent-runner";
import { createSupabaseMockImpl, createQueryMock } from "./helpers/agent-runner-mocks";

describe("agent-runner sandbox hardening (#2634)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation(() => JSON.stringify({ mcpServers: {} }));
    createSupabaseMockImpl(mockFrom, {
      userData: {
        workspace_path: "/tmp/test-workspace",
        repo_status: null,
        github_installation_id: null,
        repo_url: null,
      },
    });
    createQueryMock(mockQuery);
  });

  test("passes hardened sandbox config (incl. failIfUnavailable=true) to SDK query()", async () => {
    await startAgentSession("user-1", "conv-1", "cpo");

    expect(mockQuery).toHaveBeenCalledOnce();
    const options = mockQuery.mock.calls[0][0].options;
    expect(options.sandbox).toBeDefined();
    // Core invariant: failIfUnavailable=true. If it silently flips to
    // false/undefined, the SDK falls back to unsandboxed execution under
    // bwrap-dep drift (#2634). Use .toBe(true) per
    // cq-mutation-assertions-pin-exact-post-state so a silent flip to
    // undefined fails deterministically (toBeTruthy would not).
    expect(options.sandbox.failIfUnavailable).toBe(true);
    // Pin sibling defense-in-depth flags so a future "fix" that flips one of
    // them (e.g., enabling unsandboxed Bash for a network-dep tool) breaks
    // this test. Removing the entire `sandbox:` block also fails the
    // toBeDefined check above.
    expect(options.sandbox.enabled).toBe(true);
    expect(options.sandbox.allowUnsandboxedCommands).toBe(false);
    expect(options.sandbox.autoAllowBashIfSandboxed).toBe(true);
    expect(options.sandbox.network.allowManagedDomainsOnly).toBe(true);
  });

  test("tags Sentry with feature=agent-sandbox when SDK throws sandbox-unavailable", async () => {
    // Simulate the SDK subprocess process.exit(1) propagating as a thrown
    // Error in the parent's async iterator. The substring matches what the
    // SDK writes to stderr (verified against
    // @anthropic-ai/claude-agent-sdk cli.js — see #2634).
    const sandboxErr = new Error(
      "Error: sandbox required but unavailable: missing socat",
    );
    mockQuery.mockImplementation(() => ({
      // eslint-disable-next-line @typescript-eslint/require-await
      async *[Symbol.asyncIterator]() {
        throw sandboxErr;
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    }));

    await startAgentSession("user-1", "conv-1", "cpo");

    // Filter to the agent-sandbox call — other features (e.g. kb-share
    // baseUrl warning) may also fire reportSilentFallback during init.
    const sandboxCalls = mockReportSilentFallback.mock.calls.filter(
      ([, opts]) => opts?.feature === "agent-sandbox",
    );
    expect(sandboxCalls).toHaveLength(1);
    const [errArg, optsArg] = sandboxCalls[0];
    expect(errArg).toBe(sandboxErr);
    expect(optsArg.op).toBe("sdk-startup");
    expect(optsArg.extra).toMatchObject({
      userId: "user-1",
      conversationId: "conv-1",
      leaderId: "cpo",
    });
  });

  test("does NOT tag agent-sandbox for unrelated SDK errors", async () => {
    const otherErr = new Error("Some other unrelated SDK failure");
    mockQuery.mockImplementation(() => ({
      // eslint-disable-next-line @typescript-eslint/require-await
      async *[Symbol.asyncIterator]() {
        throw otherErr;
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    }));

    await startAgentSession("user-1", "conv-1", "cpo");

    const sandboxCalls = mockReportSilentFallback.mock.calls.filter(
      ([, opts]) => opts?.feature === "agent-sandbox",
    );
    expect(sandboxCalls).toHaveLength(0);
  });
});
