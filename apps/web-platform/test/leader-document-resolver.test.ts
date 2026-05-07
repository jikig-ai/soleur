// Resolver-level coverage for the leader-path PDF document context (#3437).
//
// Mirrors `kb-document-resolver-pdf-page-gate.test.ts` but covers the leader
// path's resolver, which differs from Concierge in:
//   1. NO `knowledge-base/` prefix gate — leaders read across the whole
//      workspace.
//   2. Sentry feature tag `"leader-context"` (Concierge uses
//      `"kb-concierge-context"`) so operators can filter leader-side fires
//      from Concierge fires when both share `category: "cc-pdf-extractor"`.
//
// Mocks `pdf-text-extract` so the test drives both legs of the partition +
// gate without synthesizing real PDFs.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  mkdtempSync,
  realpathSync,
  rmSync,
  mkdirSync,
  writeFileSync,
} from "fs";
import { tmpdir } from "os";
import path from "path";

const {
  fetchUserWorkspacePathSpy,
  extractPdfTextSpy,
  extractPdfMetadataSpy,
  reportSilentFallbackSpy,
} = vi.hoisted(() => ({
  fetchUserWorkspacePathSpy: vi.fn(),
  extractPdfTextSpy: vi.fn(),
  extractPdfMetadataSpy: vi.fn(),
  reportSilentFallbackSpy: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          single: async () => fetchUserWorkspacePathSpy(),
        }),
      }),
    }),
  }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/server/pdf-text-extract", async () => {
  const actual = await vi.importActual<typeof import("@/server/pdf-text-extract")>(
    "@/server/pdf-text-extract",
  );
  return {
    ...actual,
    extractPdfText: extractPdfTextSpy,
    extractPdfMetadata: extractPdfMetadataSpy,
  };
});

import { resolveLeaderDocumentContext } from "@/server/leader-document-resolver";
import { _resetWorkspacePathCacheForTests } from "@/server/kb-document-resolver";

let tmpRoot: string;

beforeEach(() => {
  tmpRoot = realpathSync(
    mkdtempSync(path.join(tmpdir(), "leader-document-resolver-")),
  );
  fetchUserWorkspacePathSpy.mockResolvedValue({
    data: { workspace_path: tmpRoot },
    error: null,
  });
  extractPdfTextSpy.mockReset();
  extractPdfMetadataSpy.mockReset();
  reportSilentFallbackSpy.mockReset();
  _resetWorkspacePathCacheForTests();
});

afterEach(() => {
  rmSync(tmpRoot, { recursive: true, force: true });
  vi.clearAllMocks();
});

function seedFile(rel: string, contents = "%PDF-1.4\nfake") {
  mkdirSync(path.join(tmpRoot, path.dirname(rel)), { recursive: true });
  writeFileSync(path.join(tmpRoot, rel), Buffer.from(contents));
}

describe("resolveLeaderDocumentContext (#3437)", () => {
  it("returns {} when contextPath is null/empty", async () => {
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: null,
    });
    expect(result).toEqual({});
  });

  it("uses caller-provided text content (skips read)", async () => {
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "notes/draft.md",
      providedContent: "Hello body",
    });
    expect(result.documentKind).toBe("text");
    expect(result.documentContent).toBe("Hello body");
    expect(result.artifactPath).toBe("notes/draft.md");
    expect(extractPdfTextSpy).not.toHaveBeenCalled();
  });

  it("returns kind=pdf with no body when caller provides PDF content", async () => {
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "uploads/manual.pdf",
      providedContent: "ignored",
    });
    expect(result.documentKind).toBe("pdf");
    expect(result.documentContent).toBeUndefined();
    expect(extractPdfTextSpy).not.toHaveBeenCalled();
  });

  it("does NOT enforce a knowledge-base/ prefix gate (leader scope is the whole workspace)", async () => {
    // Concierge resolver returns {} for paths outside knowledge-base/.
    // The leader resolver MUST resolve files anywhere in the workspace.
    seedFile("attachments/conv-1/diagram.txt", "Diagram body");
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "attachments/conv-1/diagram.txt",
    });
    expect(result.documentKind).toBe("text");
    expect(result.documentContent).toBe("Diagram body");
  });

  it("inlines successful PDF extraction body", async () => {
    seedFile("books/manning.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "Chapter 1 intro",
      truncated: false,
      pageCount: 8,
    });
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "books/manning.pdf",
    });
    expect(result.documentKind).toBe("pdf");
    expect(result.documentContent).toContain("Chapter 1");
    expect(extractPdfMetadataSpy).not.toHaveBeenCalled();
  });

  it("surfaces too_many_pages when oversized_buffer + numPages > 150", async () => {
    seedFile("books/manning-big.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 403 });
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "books/manning-big.pdf",
    });
    expect(result.documentExtractError).toBe("too_many_pages");
    expect(result.documentExtractMeta).toEqual({ numPages: 403 });
    expect(result.documentKind).toBe("pdf");
  });

  it("falls through to oversized_buffer (soft) when numPages <= 150", async () => {
    seedFile("books/image-heavy.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 50 });
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "books/image-heavy.pdf",
    });
    expect(result.documentExtractError).toBe("oversized_buffer");
    expect(result.documentExtractMeta).toBeUndefined();
  });

  it("fails closed to oversized_buffer when metadata read fails (oversized/timeout/parse_error)", async () => {
    for (const reason of ["oversized", "timeout", "parse_error"] as const) {
      seedFile(`books/fail-${reason}.pdf`);
      extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
      extractPdfMetadataSpy.mockResolvedValueOnce({ ok: false, reason });
      const result = await resolveLeaderDocumentContext({
        userId: "u1",
        contextPath: `books/fail-${reason}.pdf`,
      });
      expect(result.documentExtractError).toBe("oversized_buffer");
      expect(result.documentExtractMeta).toBeUndefined();
    }
  });

  it("does NOT call extractPdfMetadata for non-oversized_buffer extractor failures (e.g. encrypted)", async () => {
    seedFile("books/encrypted.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "encrypted" });
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "books/encrypted.pdf",
    });
    expect(result.documentExtractError).toBe("encrypted");
    expect(extractPdfMetadataSpy).not.toHaveBeenCalled();
  });

  it("returns read_failed without paging Sentry on ENOENT", async () => {
    // File does NOT exist; readFile throws ENOENT. Per
    // cq-silent-fallback-must-mirror-to-sentry's "first-time 404"
    // exemption, the resolver suppresses the Sentry mirror but still
    // surfaces the typed read_failed class so the runner picks the
    // unreadable directive.
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "missing/ghost.pdf",
    });
    expect(result.documentExtractError).toBe("read_failed");
    expect(result.documentKind).toBe("pdf");
    // ENOENT MUST NOT page Sentry (file deletion is expected drift).
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("blocks path-traversal via isPathInWorkspace", async () => {
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "../../../etc/passwd",
    });
    expect(result).toEqual({});
    expect(extractPdfTextSpy).not.toHaveBeenCalled();
  });

  it("inlines text content under the cap", async () => {
    seedFile("notes/short.md", "Short body");
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "notes/short.md",
    });
    expect(result.documentKind).toBe("text");
    expect(result.documentContent).toBe("Short body");
  });

  it("returns kind=text with no body when text file exceeds the inline cap", async () => {
    const huge = "x".repeat(60_000);
    seedFile("notes/huge.md", huge);
    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "notes/huge.md",
    });
    expect(result.documentKind).toBe("text");
    expect(result.documentContent).toBeUndefined();
  });

  it("passes featureTag: 'leader-context' to extractPdfText", async () => {
    seedFile("books/some.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "body",
      truncated: false,
      pageCount: 3,
    });
    await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "books/some.pdf",
    });
    expect(extractPdfTextSpy).toHaveBeenCalledTimes(1);
    const lastCall = extractPdfTextSpy.mock.calls[0];
    // Signature: (buffer, capChars, options?)
    expect(lastCall[2]).toMatchObject({ featureTag: "leader-context" });
  });
});
