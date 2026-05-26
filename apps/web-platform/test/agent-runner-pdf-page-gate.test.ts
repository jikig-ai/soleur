// Leader-path PDF partition + page-gate test (#3437).
//
// Mirrors `kb-document-resolver-pdf-page-gate.test.ts` but exercises the
// leader's `startAgentSession` artifact-directive branch. The leader-path
// resolver is mocked so the test drives the full PdfExtractErrorClass
// partition without synthesizing real PDFs:
//
//   too_many_pages              → buildPdfTooLongDirective lead
//   encrypted, empty_text       → buildPdfUnreadableDirective lead
//   oversized_buffer, lazy_*,
//     parse_error, corrupted,
//     read_failed               → buildPdfGatedDirective lead
//
// The inline-content branch (caller passed `context.content`) bypasses the
// resolver entirely and continues to wrap the body in `<document>`.

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

// Mock the new leader resolver so this test drives the partition without
// touching the disk or pdfjs.
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
import {
  DEFAULT_API_KEY_ROW,
  createSupabaseMockImpl,
  createQueryMock,
} from "./helpers/agent-runner-mocks";

const BASE_USER_DATA = {
  workspace_path: "/tmp/test-workspace",
  repo_status: "ready",
  github_installation_id: 12345,
  repo_url: "https://github.com/alice/my-repo",
};

function setupSupabaseMock() {
  createSupabaseMockImpl(mockFrom, { userData: BASE_USER_DATA });
}

function setupQueryMock() {
  createQueryMock(mockQuery);
}

const PDF_PATH = "knowledge-base/test-fixtures/book.pdf";
const PDF_CONTEXT: ConversationContext = { path: PDF_PATH, type: "kb-viewer" };

beforeEach(() => {
  vi.clearAllMocks();
  mockReadFileSync.mockImplementation((filePath: string) => {
    if (String(filePath).includes("plugin.json")) {
      return JSON.stringify({ mcpServers: {} });
    }
    throw new Error(`ENOENT: no such file ${filePath}`);
  });
  resolveLeaderDocumentContextSpy.mockReset();
});

describe("agent-runner leader PDF partition (#3437)", () => {
  test("too_many_pages routes to buildPdfTooLongDirective with page count", async () => {
    setupSupabaseMock();
    setupQueryMock();
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: PDF_PATH,
      documentKind: "pdf",
      documentExtractError: "too_many_pages",
      documentExtractMeta: { numPages: 403 },
    });

    await startAgentSession("user-1", "conv-1", "cpo", undefined, undefined, PDF_CONTEXT);

    const prompt: string = mockQuery.mock.calls[0][0].options.systemPrompt;
    expect(prompt).toContain(PDF_TOO_LONG_DIRECTIVE_LEAD);
    expect(prompt).toContain("403");
    // Cannot ALSO contain the gated/unreadable leads — partition is exclusive.
    expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    expect(prompt).not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
  });

  test.each([
    ["encrypted"],
    ["empty_text"],
  ] as const)(
    "%s (HARD) routes to buildPdfUnreadableDirective",
    async (errorClass) => {
      setupSupabaseMock();
      setupQueryMock();
      resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
        artifactPath: PDF_PATH,
        documentKind: "pdf",
        documentExtractError: errorClass,
      });

      await startAgentSession("user-1", "conv-1", "cpo", undefined, undefined, PDF_CONTEXT);

      const prompt: string = mockQuery.mock.calls[0][0].options.systemPrompt;
      expect(prompt).toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
      expect(prompt).not.toContain(PDF_TOO_LONG_DIRECTIVE_LEAD);
      expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    },
  );

  test.each([
    ["oversized_buffer"],
    ["lazy_import_failed"],
    ["corrupted"],
    ["parse_error"],
    ["read_failed"],
  ] as const)(
    "%s (SOFT) routes to buildPdfGatedDirective",
    async (errorClass) => {
      setupSupabaseMock();
      setupQueryMock();
      resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
        artifactPath: PDF_PATH,
        documentKind: "pdf",
        documentExtractError: errorClass,
      });

      await startAgentSession("user-1", "conv-1", "cpo", undefined, undefined, PDF_CONTEXT);

      const prompt: string = mockQuery.mock.calls[0][0].options.systemPrompt;
      expect(prompt).toContain(PDF_GATED_DIRECTIVE_LEAD);
      expect(prompt).not.toContain(PDF_TOO_LONG_DIRECTIVE_LEAD);
      expect(prompt).not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
    },
  );

  test("PDF success with extracted text inlines body via <document> wrapper", async () => {
    setupSupabaseMock();
    setupQueryMock();
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: PDF_PATH,
      documentKind: "pdf",
      documentContent: "Chapter 1\nContents extracted from PDF",
    });

    await startAgentSession("user-1", "conv-1", "cpo", undefined, undefined, PDF_CONTEXT);

    const prompt: string = mockQuery.mock.calls[0][0].options.systemPrompt;
    expect(prompt).toContain("<document>");
    expect(prompt).toContain("Chapter 1");
    expect(prompt).toContain("</document>");
    expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    expect(prompt).not.toContain(PDF_TOO_LONG_DIRECTIVE_LEAD);
  });

  test("inline-content branch (caller-provided content) skips the resolver", async () => {
    setupSupabaseMock();
    setupQueryMock();
    const ctx: ConversationContext = {
      path: "knowledge-base/notes/draft.md",
      type: "kb-viewer",
      content: "Hello body content",
    };

    await startAgentSession("user-1", "conv-1", "cpo", undefined, undefined, ctx);

    expect(resolveLeaderDocumentContextSpy).not.toHaveBeenCalled();
    const prompt: string = mockQuery.mock.calls[0][0].options.systemPrompt;
    expect(prompt).toContain("<document>");
    expect(prompt).toContain("Hello body content");
  });

  test("too_many_pages directive does NOT name pdftotext/pdfplumber/PyPDF2/apt-get/pip3 (apt-get cascade defense — AC14)", async () => {
    setupSupabaseMock();
    setupQueryMock();
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: PDF_PATH,
      documentKind: "pdf",
      documentExtractError: "too_many_pages",
      documentExtractMeta: { numPages: 403 },
    });

    await startAgentSession("user-1", "conv-1", "cpo", undefined, undefined, PDF_CONTEXT);

    const prompt: string = mockQuery.mock.calls[0][0].options.systemPrompt;
    // AC14: the leader-path too-long directive MUST NOT mention any of the
    // measured cascade-binary names. Mirrors the Concierge AC the apt-get
    // cascade learning enshrined.
    const forbidden = [
      "pdftotext",
      "pdfplumber",
      "pdf-parse",
      "PyPDF2",
      "PyMuPDF",
      "fitz",
      "apt-get",
      "pip3 install",
    ];
    // The leader baseline emits `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` and the
    // gated directive's exclusion clause names these tokens deliberately —
    // so we scope the check to the artifact frame between the identity
    // opener and the baseline-rest.
    const tooLongIdx = prompt.indexOf(PDF_TOO_LONG_DIRECTIVE_LEAD);
    expect(tooLongIdx).toBeGreaterThan(0);
    // Take a window around the too-long directive that excludes the
    // baseline (which legitimately names these tokens for capability
    // discovery on the Read tool).
    const tooLongFrame = prompt.slice(tooLongIdx, tooLongIdx + 4000);
    for (const token of forbidden) {
      expect(tooLongFrame).not.toContain(token);
    }
  });

  test("no documentExtractError + kind=pdf with no body falls through to gated directive", async () => {
    // Resolver returned a path-only result (e.g. read fully failed without
    // surfacing a typed error class). The runner falls through to the
    // assertive Read directive, preserving pre-#3437 leader behavior on
    // path-only PDF contexts.
    setupSupabaseMock();
    setupQueryMock();
    resolveLeaderDocumentContextSpy.mockResolvedValueOnce({
      artifactPath: PDF_PATH,
      documentKind: "pdf",
    });

    await startAgentSession("user-1", "conv-1", "cpo", undefined, undefined, PDF_CONTEXT);

    const prompt: string = mockQuery.mock.calls[0][0].options.systemPrompt;
    expect(prompt).toContain(PDF_GATED_DIRECTIVE_LEAD);
  });
});
