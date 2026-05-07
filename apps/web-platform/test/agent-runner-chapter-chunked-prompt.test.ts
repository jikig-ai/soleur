// Leader-path system-prompt coverage for the chapter-chunked branch
// (#3436 Phase 3.A foundations). Symmetric to
// `soleur-go-runner-chapter-chunked-prompt.test.ts`.
//
// Phase 3.A intentionally DEFERS the dispatch-time per-turn chapter
// routing + content-block attachment to #3472 (Phase 3.B). Until #3472
// ships, when the leader resolver populates
// `documentExtractMeta.chapters`, the runner system prompt MUST fall
// through to the existing PR #3430 `too_many_pages` bridge directive.

import { vi, describe, test, expect, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const { mockFrom, mockQuery, mockReadFileSync, resolveLeaderDocumentContextSpy } = vi.hoisted(
  () => ({
    mockFrom: vi.fn(),
    mockQuery: vi.fn(),
    mockReadFileSync: vi.fn(),
    resolveLeaderDocumentContextSpy: vi.fn(),
  }),
);

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn(
    (_name: string, _desc: string, _schema: unknown, handler: Function) => ({
      name: _name,
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

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockFrom, rpc: vi.fn() })),
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
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));
vi.mock("../server/byok", () => ({
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
  reportSilentFallback: vi.fn(),
  reportSilentFallbackWarning: vi.fn(),
}));

vi.mock("../server/leader-document-resolver", () => ({
  resolveLeaderDocumentContext: resolveLeaderDocumentContextSpy,
}));

import { startAgentSession } from "../server/agent-runner";
import type { ConversationContext } from "../lib/types";
import {
  PDF_GATED_DIRECTIVE_LEAD,
  PDF_UNREADABLE_DIRECTIVE_LEAD,
  PDF_TOO_LONG_DIRECTIVE_LEAD,
} from "../server/soleur-go-runner";
import type { ChapterIndex } from "../server/pdf-text-extract";
import {
  createSupabaseMockImpl,
  createQueryMock,
} from "./helpers/agent-runner-mocks";

const BASE_USER_DATA = {
  workspace_path: "/tmp/test-workspace",
  repo_status: "ready",
  github_installation_id: 12345,
  repo_url: "https://github.com/alice/my-repo",
};

const PDF_PATH = "knowledge-base/test-fixtures/big-book.pdf";
const PDF_CONTEXT: ConversationContext = { path: PDF_PATH, type: "kb-viewer" };

const SAMPLE_CHAPTERS: ChapterIndex[] = [
  { title: "Introduction", startPage: 1, endPage: 12, depth: 0 },
  { title: "Architecture overview", startPage: 13, endPage: 47, depth: 0 },
  { title: "Authentication", startPage: 48, endPage: 102, depth: 0 },
];

beforeEach(() => {
  vi.clearAllMocks();
  mockReadFileSync.mockImplementation((filePath: string) => {
    if (String(filePath).includes("plugin.json")) {
      return JSON.stringify({ mcpServers: {} });
    }
    throw new Error(`ENOENT: no such file ${filePath}`);
  });
  resolveLeaderDocumentContextSpy.mockReset();
  createSupabaseMockImpl(mockFrom, { userData: BASE_USER_DATA });
  createQueryMock(mockQuery);
});

describe("agent-runner leader chapter-chunked branch (#3436 Phase 3.A fall-through)", () => {
  test("falls through to PDF_TOO_LONG bridge when resolver returns chapters (Phase 3.B not yet wired)", async () => {
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: PDF_PATH,
      documentKind: "pdf",
      documentExtractMeta: {
        numPages: 403,
        chapters: SAMPLE_CHAPTERS,
        fullExtractedText: "(extracted body)",
      },
    });

    await startAgentSession(
      "user-1",
      "conv-1",
      "cpo",
      undefined,
      undefined,
      PDF_CONTEXT,
    );

    const prompt: string = mockQuery.mock.calls[0][0].options.systemPrompt;

    // Bridge directive carries the page count.
    expect(prompt).toContain(PDF_TOO_LONG_DIRECTIVE_LEAD);
    expect(prompt).toContain("403");

    // CRITICAL: chapter-content-block contract must NOT leak into the
    // prompt until #3472 actually attaches the content block.
    expect(prompt).not.toContain("Table of contents:");
    expect(prompt).not.toContain("Do NOT invoke the Read tool");
    expect(prompt).not.toMatch(/Prefix every reply with `\[Answering/);
    expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    expect(prompt).not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
  });

  test("falls through to too_many_pages directive when chapters is unset (existing behavior)", async () => {
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: PDF_PATH,
      documentKind: "pdf",
      documentExtractError: "too_many_pages",
      documentExtractMeta: { numPages: 403 },
    });

    await startAgentSession(
      "user-1",
      "conv-2",
      "cpo",
      undefined,
      undefined,
      PDF_CONTEXT,
    );

    const prompt: string = mockQuery.mock.calls[0][0].options.systemPrompt;
    expect(prompt).not.toContain("Table of contents:");
    expect(prompt).toContain(PDF_TOO_LONG_DIRECTIVE_LEAD);
    expect(prompt).toContain("403");
  });
});
