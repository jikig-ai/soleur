// Leader-path symmetric coverage for the chapter-chunking soft-route
// (#3436). Mirrors `kb-document-resolver-chapter-chunked.test.ts` but
// targets `resolveLeaderDocumentContext` (no `knowledge-base/` prefix
// gate, `feature: "leader-context"` Sentry tag).

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
  extractPdfOutlineSpy,
  reportSilentFallbackSpy,
} = vi.hoisted(() => ({
  fetchUserWorkspacePathSpy: vi.fn(),
  extractPdfTextSpy: vi.fn(),
  extractPdfMetadataSpy: vi.fn(),
  extractPdfOutlineSpy: vi.fn(),
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

// PR-C §2.7 (#3244).
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: async () => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          single: async () => fetchUserWorkspacePathSpy(),
        }),
      }),
    }),
  }),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
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
    extractPdfOutline: extractPdfOutlineSpy,
  };
});

import { resolveLeaderDocumentContext } from "@/server/leader-document-resolver";
import { _resetWorkspacePathCacheForTests } from "@/server/kb-document-resolver";

let tmpRoot: string;

beforeEach(() => {
  tmpRoot = realpathSync(
    mkdtempSync(path.join(tmpdir(), "leader-document-resolver-chapter-chunked-")),
  );
  fetchUserWorkspacePathSpy.mockResolvedValue({
    data: { workspace_path: tmpRoot },
    error: null,
  });
  extractPdfTextSpy.mockReset();
  extractPdfMetadataSpy.mockReset();
  extractPdfOutlineSpy.mockReset();
  reportSilentFallbackSpy.mockReset();
  _resetWorkspacePathCacheForTests();
});

afterEach(() => {
  rmSync(tmpRoot, { recursive: true, force: true });
  vi.clearAllMocks();
});

describe("resolveLeaderDocumentContext chapter-chunked branch (#3436)", () => {
  function seedPdf(rel: string, contents = "%PDF-1.4\nfake") {
    mkdirSync(path.join(tmpRoot, path.dirname(rel)), { recursive: true });
    writeFileSync(path.join(tmpRoot, rel), Buffer.from(contents));
  }

  const sampleOutline = [
    { title: "Chapter 1", startPage: 1, endPage: 33, depth: 0 },
    { title: "Chapter 2", startPage: 34, endPage: 66, depth: 0 },
    { title: "Chapter 3", startPage: 67, endPage: 100, depth: 0 },
  ];

  it("returns chapter-chunked shape when outline is usable (no kb prefix gate)", async () => {
    // Leader resolver does NOT enforce a knowledge-base/ prefix; this
    // fixture sits at workspace root.
    seedPdf("attachments/manning-with-outline.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 403 });
    extractPdfOutlineSpy.mockResolvedValueOnce({
      ok: true,
      outline: sampleOutline,
    });
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "<full chapter text>",
      truncated: false,
      pageCount: 403,
    });

    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "attachments/manning-with-outline.pdf",
    });

    expect(result.documentKind).toBe("pdf");
    expect(result.documentExtractError).toBeUndefined();
    expect(result.documentExtractMeta?.chapters).toEqual(sampleOutline);
    expect(result.documentExtractMeta?.fullExtractedText).toBe(
      "<full chapter text>",
    );
    expect(result.documentExtractMeta?.numPages).toBe(403);
    expect(extractPdfOutlineSpy).toHaveBeenCalledTimes(1);
  });

  it("falls through to too_many_pages when outline is not usable", async () => {
    seedPdf("attachments/scanned.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 403 });
    extractPdfOutlineSpy.mockResolvedValueOnce({
      ok: false,
      reason: "no_outline",
    });

    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "attachments/scanned.pdf",
    });

    expect(result.documentExtractError).toBe("too_many_pages");
    expect(result.documentExtractMeta?.chapters).toBeUndefined();
  });

  it("does NOT call extractPdfOutline when numPages <= LARGE_PDF_PAGE_THRESHOLD", async () => {
    seedPdf("attachments/small.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 50 });

    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "attachments/small.pdf",
    });

    expect(result.documentExtractError).toBe("oversized_buffer");
    expect(extractPdfOutlineSpy).not.toHaveBeenCalled();
  });

  it("falls through to too_many_pages when outline is usable but full-text extract fails", async () => {
    seedPdf("attachments/outline-but-broken.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 403 });
    extractPdfOutlineSpy.mockResolvedValueOnce({
      ok: true,
      outline: sampleOutline,
    });
    extractPdfTextSpy.mockResolvedValueOnce({ error: "parse_error" });

    const result = await resolveLeaderDocumentContext({
      userId: "u1",
      contextPath: "attachments/outline-but-broken.pdf",
    });

    expect(result.documentExtractError).toBe("too_many_pages");
    expect(result.documentExtractMeta?.chapters).toBeUndefined();
  });
});
