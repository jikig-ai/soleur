import { vi, describe, test, expect, beforeEach } from "vitest";

// Task 11.3b (#12714, rulings D29(4), D29(6), D32): the legacy runner appends the held-files line from `syncPull`'s fresh
// `{ heldFiles, onRecovered, checkedAt }` and the merge-blocked line from its `pullReason`, in the assembled system prompt
// the SDK receives. The route is "registered" exactly when this runner registered `github_push_branch` for the session
// (D32: "legacy always" survives here, in the runner's own line).

// Env vars needed by serverUrl() guard — set before agent-runner is loaded
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

// ---------------------------------------------------------------------------
// Mock all heavy dependencies (same harness as agent-runner-system-prompt.test.ts)
// ---------------------------------------------------------------------------

const {
  mockFrom,
  mockRpc,
  mockQuery,
  mockReadFileSync,
  resolveLeaderDocumentContextSpy,
  mockMessagesInsert,
  mockSyncPull,
  mockGithubApiGet,
} = vi.hoisted(() => ({
  mockSyncPull: vi.fn(),
  mockGithubApiGet: vi.fn(),
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
  resolveLeaderDocumentContextSpy: vi.fn(),
  mockMessagesInsert: vi.fn((_row: Record<string, unknown>) => ({ error: null })),
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
vi.mock("../server/agent-env", async () => {
  // feat-open-web-egress (#9534): agent-runner-sandbox-config derives the
  // web-egress deny census from the REAL ALLOWED_SERVICE_ENV_VARS export —
  // keep it (and every other export) while stubbing only buildAgentEnv.
  const actual =
    await vi.importActual<typeof import("../server/agent-env")>(
      "../server/agent-env",
    );
  return { ...actual, buildAgentEnv: vi.fn(() => ({})) };
});
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
  const leaders = [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }];
  return {
    DOMAIN_LEADERS: leaders,
    ROUTABLE_DOMAIN_LEADERS: leaders,
  };
});
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({
  syncPull: mockSyncPull,
  syncPush: vi.fn(),
}));
vi.mock("../server/github-api", () => ({
  githubApiGet: mockGithubApiGet,
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

// 2026-05-07 (#3437): the leader artifact-frame branch now resolves
// PDF/text contexts through `leader-document-resolver`. Mock it so these
// system-prompt tests drive expected partition shapes without paying real
// FS I/O. Per-test `mockResolvedValueOnce` calls supply the resolver
// output that produces each expected directive.
vi.mock("../server/leader-document-resolver", () => ({
  resolveLeaderDocumentContext: resolveLeaderDocumentContextSpy,
}));

// agent-runner now resolves the leader cwd from the ACTIVE workspace via
// `resolveActiveWorkspacePath` (ADR-044 convergence) instead of the legacy
// `users.workspace_path` column. Pin the seam to the seeded workspace_path so
// the absolute-path assertions below stay deterministic (mirrors #4910's
// Concierge test repoint). `importActual` keeps the other real exports that
// byok-resolver depends on.
vi.mock("../server/workspace-resolver", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("../server/workspace-resolver")>();
  return {
    ...actual,
    resolveActiveWorkspacePath: vi.fn(async () => "/tmp/test-workspace"),
  };
});

import { startAgentSession } from "../server/agent-runner";
import { buildKbSyncHeldAgentLine, buildKbSyncMergeBlockedAgentLine } from "../server/kb-sync-held-agent-line";
import { createSupabaseMockImpl, createQueryMock } from "./helpers/agent-runner-mocks";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function setupSupabaseMock(userData: Record<string, unknown>) {
  createSupabaseMockImpl(mockFrom, { userData, mockRpc, mockMessagesInsert });
}

const CONNECTED = {
  workspace_path: "/tmp/test-workspace",
  repo_status: "ready",
  github_installation_id: 12345,
  repo_url: "https://github.com/alice/my-repo",
};
const UNCONNECTED = { workspace_path: "/tmp/test-workspace", repo_status: null, github_installation_id: null, repo_url: null };
const CHECKED_AT = "2026-11-17T09:30:00.000Z";

const pullResult = (over: Record<string, unknown> = {}) => ({
  heldFiles: null,
  onRecovered: null,
  pullReason: "up_to_date",
  checkedAt: null,
  ...over,
});

async function promptFor(userData: Record<string, unknown>): Promise<string> {
  setupSupabaseMock(userData);
  createQueryMock(mockQuery);
  await startAgentSession("user-1", "conv-1", "cpo");
  expect(mockQuery).toHaveBeenCalledTimes(1);
  return mockQuery.mock.calls[0][0].options.systemPrompt as string;
}

const HELD_HEADING = "## Code changes not on the main branch yet";
const MERGE_HEADING = "## Unfinished merge in this workspace";

describe("legacy runner: held-files and merge-blocked agent lines (task 11.3b)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) return JSON.stringify({ mcpServers: {} });
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
    resolveLeaderDocumentContextSpy.mockResolvedValue({ artifactPath: "knowledge-base/product/roadmap.md", documentKind: "text" });
    mockGithubApiGet.mockResolvedValue({ default_branch: "main" });
    mockSyncPull.mockResolvedValue(pullResult());
  });

  test("count 2, tool registered: the registered line with the count, the time and the default branch", async () => {
    mockSyncPull.mockResolvedValue(pullResult({ heldFiles: 2, onRecovered: 0, checkedAt: CHECKED_AT }));
    const prompt = await promptFor(CONNECTED);
    const expected = buildKbSyncHeldAgentLine({
      heldFiles: 2,
      checkedAt: CHECKED_AT,
      route: "registered",
      onRecovered: 0,
      defaultBranch: "main",
    });
    expect(expected).not.toBeNull();
    expect(prompt).toContain(expected!);
    expect(prompt).toContain("2 changed code files in this workspace are not on the repository's main branch yet");
    expect(prompt).toContain("As of 2026-11-17 09:30 UTC");
    expect(prompt).toContain("git diff --name-only origin/main...HEAD");
    expect(prompt).toContain("`github_push_branch`");
    expect(prompt).not.toContain("soleur/recovered-kb-sync-<time>");
    expect(prompt).not.toContain(MERGE_HEADING);
    // The line goes in once, and it agrees with the Settings card's words, never "not on GitHub".
    expect(prompt.split(HELD_HEADING)).toHaveLength(2);
    expect(prompt).not.toMatch(/not on GitHub/i);
  });

  test("onRecovered > 0 names the recovered branches", async () => {
    mockSyncPull.mockResolvedValue(pullResult({ heldFiles: 3, onRecovered: 1, checkedAt: CHECKED_AT }));
    const prompt = await promptFor(CONNECTED);
    expect(prompt).toContain("Some of these changes are only on a local branch named `soleur/recovered-kb-sync-<time>`");
  });

  test("the default branch is unknown (lookup failed): origin/HEAD, still registered", async () => {
    mockGithubApiGet.mockRejectedValue(new Error("401"));
    mockSyncPull.mockResolvedValue(pullResult({ heldFiles: 2, onRecovered: 0, checkedAt: CHECKED_AT }));
    const prompt = await promptFor(CONNECTED);
    expect(prompt).toContain(
      buildKbSyncHeldAgentLine({ heldFiles: 2, checkedAt: CHECKED_AT, route: "registered", onRecovered: 0, defaultBranch: null })!,
    );
    expect(prompt).toContain("git diff --name-only origin/HEAD...HEAD");
  });

  test("tool absent (no installation): the not-registered line", async () => {
    mockSyncPull.mockResolvedValue(pullResult({ heldFiles: 2, onRecovered: 0, checkedAt: CHECKED_AT }));
    const prompt = await promptFor(UNCONNECTED);
    expect(prompt).toContain(
      buildKbSyncHeldAgentLine({ heldFiles: 2, checkedAt: CHECKED_AT, route: "not-registered", onRecovered: 0, defaultBranch: null })!,
    );
    expect(prompt).toContain("This session has no tool to push a branch");
  });

  test.each([
    ["null", pullResult({ heldFiles: null, checkedAt: null })],
    ["0", pullResult({ heldFiles: 0, onRecovered: 0, checkedAt: CHECKED_AT })],
    ["a count without a time", pullResult({ heldFiles: 2, onRecovered: 0, checkedAt: null })],
    ["a void syncPull (mocked or older shape)", undefined],
  ])("heldFiles %s: no held line", async (_label, result) => {
    mockSyncPull.mockResolvedValue(result);
    const prompt = await promptFor(CONNECTED);
    expect(prompt).not.toContain(HELD_HEADING);
    expect(prompt).not.toContain(MERGE_HEADING);
  });

  test.each(["merge_conflict", "unresolved_merge"] as const)("pullReason %s: the merge-blocked line", async (reason) => {
    mockSyncPull.mockResolvedValue(pullResult({ pullReason: reason }));
    const prompt = await promptFor(CONNECTED);
    expect(prompt).toContain(buildKbSyncMergeBlockedAgentLine(reason)!);
    expect(prompt).not.toContain(HELD_HEADING);
  });

  test("merge_conflict with a held count: both lines", async () => {
    mockSyncPull.mockResolvedValue(pullResult({ pullReason: "merge_conflict", heldFiles: 1, onRecovered: 0, checkedAt: CHECKED_AT }));
    const prompt = await promptFor(CONNECTED);
    expect(prompt).toContain("1 changed code file in this workspace is not on the repository's main branch yet");
    expect(prompt).toContain(MERGE_HEADING);
  });

  test("the session's syncPull is keyed on the active workspace and runs before the prompt is assembled", async () => {
    mockSyncPull.mockResolvedValue(pullResult({ heldFiles: 2, onRecovered: 0, checkedAt: CHECKED_AT }));
    await promptFor(CONNECTED);
    expect(mockSyncPull).toHaveBeenCalledTimes(1);
    expect(mockSyncPull.mock.invocationCallOrder[0]).toBeLessThan(mockQuery.mock.invocationCallOrder[0]);
  });
});
