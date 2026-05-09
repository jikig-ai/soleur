// Resolver-level coverage for the chapter-chunking soft-route (#3436).
//
// When `extractPdfText` returns `oversized_buffer` AND the metadata read
// reports `numPages > LARGE_PDF_PAGE_THRESHOLD`, the resolver ALSO calls
// `extractPdfOutline`. If the outline is usable, the resolver runs a full-
// text extract (loose cap) and returns `{ chapters, fullExtractedText }`
// with NO `documentExtractError` — chapter-chunked is success-with-structure,
// not an error. PDFs without a usable outline fall through to the existing
// `too_many_pages` bridge (#3430).

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

import { resolveConciergeDocumentContext } from "@/server/cc-dispatcher";
import { _resetWorkspacePathCacheForTests } from "@/server/kb-document-resolver";

let tmpRoot: string;

beforeEach(() => {
  tmpRoot = realpathSync(
    mkdtempSync(path.join(tmpdir(), "kb-document-resolver-chapter-chunked-")),
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

describe("kb-document-resolver chapter-chunked branch (#3436)", () => {
  function seedPdf(rel: string, contents = "%PDF-1.4\nfake") {
    mkdirSync(path.join(tmpRoot, path.dirname(rel)), { recursive: true });
    writeFileSync(path.join(tmpRoot, rel), Buffer.from(contents));
  }

  const sampleOutline = [
    { title: "Chapter 1", startPage: 1, endPage: 33, depth: 0 },
    { title: "Chapter 2", startPage: 34, endPage: 66, depth: 0 },
    { title: "Chapter 3", startPage: 67, endPage: 100, depth: 0 },
  ];

  it("returns chapter-chunked shape (chapters + fullExtractedText, no error) when outline is usable", async () => {
    seedPdf("knowledge-base/manning-with-outline.pdf");
    // First call (concierge inline cap) overflows → oversized_buffer.
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 403 });
    extractPdfOutlineSpy.mockResolvedValueOnce({
      ok: true,
      outline: sampleOutline,
    });
    // Second extractPdfText call (full-text loose cap) succeeds.
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "<full chapter text>",
      truncated: false,
      pageCount: 403,
    });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/manning-with-outline.pdf",
    });

    expect(result.documentKind).toBe("pdf");
    expect(result.documentExtractError).toBeUndefined();
    expect(result.documentExtractMeta).toBeDefined();
    expect(result.documentExtractMeta?.chapters).toEqual(sampleOutline);
    expect(result.documentExtractMeta?.fullExtractedText).toBe(
      "<full chapter text>",
    );
    expect(result.documentExtractMeta?.numPages).toBe(403);
    // Outline call was attempted.
    expect(extractPdfOutlineSpy).toHaveBeenCalledTimes(1);
    // The second extractPdfText call carried a different (loose) cap than
    // the first.
    expect(extractPdfTextSpy).toHaveBeenCalledTimes(2);
  });

  it("falls through to too_many_pages when outline is not usable (no_outline)", async () => {
    seedPdf("knowledge-base/scanned.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 403 });
    extractPdfOutlineSpy.mockResolvedValueOnce({
      ok: false,
      reason: "no_outline",
    });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/scanned.pdf",
    });

    expect(result.documentExtractError).toBe("too_many_pages");
    expect(result.documentExtractMeta?.chapters).toBeUndefined();
    expect(result.documentExtractMeta?.fullExtractedText).toBeUndefined();
    expect(result.documentExtractMeta?.numPages).toBe(403);
  });

  it("falls through to too_many_pages when outline is too shallow", async () => {
    seedPdf("knowledge-base/front-matter-only.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 403 });
    extractPdfOutlineSpy.mockResolvedValueOnce({
      ok: false,
      reason: "outline_too_shallow",
    });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/front-matter-only.pdf",
    });

    expect(result.documentExtractError).toBe("too_many_pages");
    expect(result.documentExtractMeta?.chapters).toBeUndefined();
  });

  it("falls through to too_many_pages when outline read times out", async () => {
    seedPdf("knowledge-base/slow-outline.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 403 });
    extractPdfOutlineSpy.mockResolvedValueOnce({
      ok: false,
      reason: "timeout",
    });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/slow-outline.pdf",
    });

    expect(result.documentExtractError).toBe("too_many_pages");
  });

  it("does NOT call extractPdfOutline when numPages <= LARGE_PDF_PAGE_THRESHOLD", async () => {
    // The chapter-chunking branch is gated on the same threshold as the
    // too_many_pages bridge — small-page-count PDFs route via the existing
    // soft-route without paying the outline cost.
    seedPdf("knowledge-base/small.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 50 });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/small.pdf",
    });

    expect(result.documentExtractError).toBe("oversized_buffer");
    expect(extractPdfOutlineSpy).not.toHaveBeenCalled();
  });

  it("falls through to too_many_pages when outline is usable but full-text extract fails", async () => {
    // Defensive: if the loose-cap full-text extract trips an unexpected
    // failure (lazy_import_failed, parse_error post-hoc), surface
    // too_many_pages instead of a half-built chapter-chunked shape with
    // no body. Worst case the user gets the bridge — never worse.
    seedPdf("knowledge-base/outline-but-broken.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 403 });
    extractPdfOutlineSpy.mockResolvedValueOnce({
      ok: true,
      outline: sampleOutline,
    });
    extractPdfTextSpy.mockResolvedValueOnce({ error: "parse_error" });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/outline-but-broken.pdf",
    });

    expect(result.documentExtractError).toBe("too_many_pages");
    expect(result.documentExtractMeta?.chapters).toBeUndefined();
  });
});
