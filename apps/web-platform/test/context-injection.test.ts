import { vi, describe, test, expect, beforeEach } from "vitest";

// Env vars needed by serverUrl() guard
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// ---------------------------------------------------------------------------
// Mock dependencies (same pattern as agent-runner-system-prompt.test.ts)
// ---------------------------------------------------------------------------

const {
  mockFrom,
  mockRpc,
  mockQuery,
  mockReadFileSync,
  mockReadFile,
  resolveLeaderDocumentContextSpy,
} = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
  mockReadFile: vi.fn(),
  resolveLeaderDocumentContextSpy: vi.fn(),
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

vi.mock("fs/promises", async (importOriginal) => {
  const actual = await importOriginal<typeof import("fs/promises")>();
  return { ...actual, readFile: mockReadFile };
});

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockFrom })),
}));

// PR-B (#3244 §1.5.1): tenant-client factory; route through the same
// mock chain so existing assertions still apply.
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

// 2026-05-07 (#3437): the leader artifact-frame branch routes PDF/text
// contexts through `leader-document-resolver`. Mock it so these tests
// drive the partition shapes deterministically without exercising real
// FS reads through the resolver wrapper.
vi.mock("../server/leader-document-resolver", () => ({
  resolveLeaderDocumentContext: resolveLeaderDocumentContextSpy,
}));

import { startAgentSession } from "../server/agent-runner";
import type { ConversationContext } from "../lib/types";
import {
  createSupabaseMockImpl,
  createQueryMock,
} from "./helpers/agent-runner-mocks";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const BASE_USER_DATA = {
  workspace_path: "/tmp/test-workspace",
  repo_status: "ready",
  github_installation_id: 12345,
  repo_url: "https://github.com/alice/my-repo",
};

function setupMocks() {
  createSupabaseMockImpl(mockFrom, { userData: BASE_USER_DATA, mockRpc });
  createQueryMock(mockQuery);
}

// ---------------------------------------------------------------------------
// Tests: server-side document content injection (#2428 Bug 3)
// ---------------------------------------------------------------------------

describe("document context injection (#2428)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) {
        return JSON.stringify({ mcpServers: {} });
      }
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
  });

  test("text file under 100KB: content injected into system prompt", async () => {
    setupMocks();

    const fileContent = "# Vision du projet\n\nCréer un lieu hybride...";
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: "overview/pitch-projet.md",
      documentKind: "text",
      documentContent: fileContent,
    });

    const context: ConversationContext = {
      path: "overview/pitch-projet.md",
      type: "kb-viewer",
      // no content — resolver reads it
    };

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", undefined, "test", context);

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("Vision du projet");
    expect(options.systemPrompt).toContain("Créer un lieu hybride");
    expect(options.systemPrompt).toContain("Do not ask which document");
  });

  test("PDF file: assertive Read instruction with filename", async () => {
    setupMocks();
    // Path-only PDF (no extracted body, no typed error) → runner falls
    // through to the gated Read directive (legacy behavior on path-only
    // PDF contexts).
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: "overview/Au Chat Pôtan - Pitch Projet.pdf",
      documentKind: "pdf",
    });

    const context: ConversationContext = {
      path: "overview/Au Chat Pôtan - Pitch Projet.pdf",
      type: "kb-viewer",
    };

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", undefined, "test", context);

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("Au Chat Pôtan - Pitch Projet.pdf");
    expect(options.systemPrompt).toContain("Do not ask which document");
    // Should NOT try to inject raw PDF content as text
    expect(options.systemPrompt).not.toContain("Artifact content:");
  });

  test("text file over 50KB: assertive Read instruction with size info", async () => {
    setupMocks();
    // Resolver caps at MAX_INLINE_BYTES (50KB) and surfaces kind=text
    // without content for over-cap files; runner emits the Read directive.
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: "overview/large-file.md",
      documentKind: "text",
    });

    const context: ConversationContext = {
      path: "overview/large-file.md",
      type: "kb-viewer",
    };

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", undefined, "test", context);

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("large-file.md");
    expect(options.systemPrompt).toContain("Do not ask which document");
    expect(options.systemPrompt).not.toContain("x".repeat(100));
  });

  test("all context injection branches include 'do not ask which document' language", async () => {
    setupMocks();
    // Read failure surfaces as kind=text without content (Bug A1 #3376
    // legacy leader behavior — Read directive on text read failure).
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: "overview/missing-file.md",
      documentKind: "text",
    });

    const context: ConversationContext = {
      path: "overview/missing-file.md",
      type: "kb-viewer",
    };

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", undefined, "test", context);

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("Do not ask which document");
  });

  test("system prompt never contains absolute workspace paths in context injection", async () => {
    setupMocks();
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: "overview/vision.md",
      documentKind: "text",
      documentContent: "some content",
    });

    const context: ConversationContext = {
      path: "overview/vision.md",
      type: "kb-viewer",
    };

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", undefined, "test", context);

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).not.toContain("/tmp/test-workspace");
  });

  test("path traversal attempt rejected by isPathInWorkspace", async () => {
    setupMocks();

    // Mock isPathInWorkspace to return false for traversal paths
    const { isPathInWorkspace } = await import("../server/sandbox");
    (isPathInWorkspace as ReturnType<typeof vi.fn>).mockReturnValueOnce(false);

    const context: ConversationContext = {
      path: "../../etc/passwd",
      type: "kb-viewer",
    };

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", undefined, "test", context);

    const options = mockQuery.mock.calls[0][0].options;
    // Should NOT inject any file content or Read instruction for traversal path
    expect(options.systemPrompt).not.toContain("etc/passwd");
    expect(mockReadFile).not.toHaveBeenCalled();
  });

  test("when context has content already, no server-side read occurs", async () => {
    setupMocks();

    const context: ConversationContext = {
      path: "overview/vision.md",
      type: "kb-viewer",
      content: "Already provided content",
    };

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo", undefined, "test", context);

    // readFile should NOT be called — content was provided by the client
    expect(mockReadFile).not.toHaveBeenCalled();

    const options = mockQuery.mock.calls[0][0].options;
    expect(options.systemPrompt).toContain("Already provided content");
  });
});
