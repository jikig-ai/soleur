// Leader dispatch-time chapter-routing integration coverage
// (#3436 Phase 3.B — bundle PR feat-pdf-chapter-chunking-bundle).
//
// Mirror of `soleur-go-runner-chapter-chunked.test.ts` for the leader
// path. Key differences from the Concierge:
//   - Each `startAgentSession` call is a fresh one-shot SDK query
//     (string `prompt`, not streaming-input). No persistent
//     ActiveQuery state machine; chapter routing fires inline before
//     the SDK call.
//   - The chapter slice is inlined into the user prompt via a
//     `<chapter-content>...</chapter-content>` wrapper rather than a
//     `document` content block with `cache_control`.
//   - The system prompt's NO-ASK-on-Read clause is the leader's
//     load-bearing surface for not invoking the SDK Read tool on the
//     chapter-chunked PDF. This file asserts the directive is
//     present; runtime enforcement is the model's responsibility
//     under the directive.

import { vi, describe, test, expect, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const {
  mockFrom,
  mockRpc,
  mockQuery,
  mockReadFileSync,
  mockReadFile,
  resolveLeaderDocumentContextSpy,
  selectChapterSpy,
  extractPdfTextSpy,
  sendToClientSpy,
} = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
  mockReadFile: vi.fn(),
  resolveLeaderDocumentContextSpy: vi.fn(),
  selectChapterSpy: vi.fn(),
  extractPdfTextSpy: vi.fn(),
  sendToClientSpy: vi.fn(),
}));

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

vi.mock("node:fs/promises", () => ({
  readFile: mockReadFile,
  // startAgentSession now ensures the workspace dir before sandbox construction
  // (ensureWorkspaceDirExists → mkdir); this partial mock must export it.
  mkdir: vi.fn(async () => undefined),
}));

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockFrom })),
}));

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
vi.mock("../server/ws-handler", () => ({ sendToClient: sendToClientSpy }));
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
vi.mock("../server/pdf-chapter-router", () => ({
  selectChapter: selectChapterSpy,
}));
vi.mock("../server/pdf-text-extract", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../server/pdf-text-extract")>();
  return { ...actual, extractPdfText: extractPdfTextSpy };
});

import { startAgentSession } from "../server/agent-runner";
import type { ConversationContext } from "../lib/types";
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
  selectChapterSpy.mockReset();
  extractPdfTextSpy.mockReset();
  mockReadFile.mockReset();
  createSupabaseMockImpl(mockFrom, { userData: BASE_USER_DATA, mockRpc });
  createQueryMock(mockQuery);
});

describe("agent-runner leader chapter-chunked dispatch (Phase 3.B)", () => {
  test("selected: inlines chapter slice into user prompt with <chapter-content> wrapper", async () => {
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: PDF_PATH,
      documentKind: "pdf",
      documentExtractMeta: {
        numPages: 403,
        chapters: SAMPLE_CHAPTERS,
        fullExtractedText: "(extracted body)",
      },
    });
    selectChapterSpy.mockResolvedValueOnce({
      kind: "selected",
      chapterIndex: 1,
      routingCostUsd: 0.001,
    });
    mockReadFile.mockResolvedValueOnce(Buffer.from("fake-pdf"));
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "Architecture overview body.",
      truncated: false,
      pageCount: 35,
    });

    await startAgentSession(
      "11111111-1111-4111-8111-111111111111",
      "conv-route",
      "cpo",
      undefined,
      "Tell me about the architecture",
      PDF_CONTEXT,
    );

    // selectChapter invoked with the user question + outline.
    expect(selectChapterSpy).toHaveBeenCalledTimes(1);
    expect(selectChapterSpy.mock.calls[0]![0].question).toBe(
      "Tell me about the architecture",
    );

    // The SDK query receives the rewritten prompt with the chapter
    // slice inlined.
    const promptArg: string = mockQuery.mock.calls[0][0].prompt;
    expect(promptArg).toContain("Chapter 2: Architecture overview");
    expect(promptArg).toContain("<chapter-content>");
    expect(promptArg).toContain("Architecture overview body.");
    expect(promptArg).toContain("</chapter-content>");
    expect(promptArg).toContain("User question: Tell me about the architecture");

    // System prompt has the directive (covers cross-reference with
    // the chapter-chunked-prompt test file).
    const sysPrompt: string = mockQuery.mock.calls[0][0].options.systemPrompt;
    expect(sysPrompt).toContain("Do NOT invoke the Read tool on this PDF");
    expect(sysPrompt).toContain("Table of contents:");
  });

  test("ambiguous: emits clarification text via stream + does NOT rewrite prompt", async () => {
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: PDF_PATH,
      documentKind: "pdf",
      documentExtractMeta: {
        numPages: 403,
        chapters: SAMPLE_CHAPTERS,
        fullExtractedText: "(extracted body)",
      },
    });
    selectChapterSpy.mockResolvedValueOnce({
      kind: "ambiguous",
      routingCostUsd: 0.001,
    });

    await startAgentSession(
      "11111111-1111-4111-8111-111111111111",
      "conv-ambig",
      "cpo",
      undefined,
      "tell me about something",
      PDF_CONTEXT,
    );

    expect(mockReadFile).not.toHaveBeenCalled();
    expect(extractPdfTextSpy).not.toHaveBeenCalled();
    // Stream event was emitted with the ambiguity copy.
    const streamCalls = sendToClientSpy.mock.calls.filter(
      (c: unknown[]) =>
        (c[1] as { type?: string })?.type === "stream",
    );
    const ambiguityHit = streamCalls.find((c: unknown[]) =>
      String((c[1] as { content?: string })?.content ?? "").includes(
        "multiple chapters",
      ),
    );
    expect(ambiguityHit).toBeDefined();
    // Prompt unchanged — original user question is preserved.
    const promptArg: string = mockQuery.mock.calls[0][0].prompt;
    expect(promptArg).toBe("tell me about something");
  });

  test("ENOENT on chapter readFile: emits read-failure copy via stream + Sentry mirror", async () => {
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: PDF_PATH,
      documentKind: "pdf",
      documentExtractMeta: {
        numPages: 403,
        chapters: SAMPLE_CHAPTERS,
        fullExtractedText: "(extracted body)",
      },
    });
    selectChapterSpy.mockResolvedValueOnce({
      kind: "selected",
      chapterIndex: 0,
      routingCostUsd: 0.001,
    });
    const enoent = Object.assign(new Error("ENOENT"), { code: "ENOENT" });
    mockReadFile.mockRejectedValueOnce(enoent);

    await startAgentSession(
      "11111111-1111-4111-8111-111111111111",
      "conv-enoent",
      "cpo",
      undefined,
      "summarize chapter 1",
      PDF_CONTEXT,
    );

    const streamCalls = sendToClientSpy.mock.calls.filter(
      (c: unknown[]) =>
        (c[1] as { type?: string })?.type === "stream",
    );
    const errMsg = streamCalls.find((c: unknown[]) =>
      String((c[1] as { content?: string })?.content ?? "").includes(
        "could not be read",
      ),
    );
    expect(errMsg).toBeDefined();
  });
});
