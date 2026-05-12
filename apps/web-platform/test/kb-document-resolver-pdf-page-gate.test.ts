// Resolver-level coverage for the page-count gate (#3429).
//
// When `extractPdfText` returns `{ error: "oversized_buffer" }` (the >24MB
// extractor cap), the resolver runs `extractPdfMetadata` to obtain numPages
// cheaply and surfaces the new HARD class `too_many_pages` if numPages
// exceeds `LARGE_PDF_PAGE_THRESHOLD` (150). PDFs at or under the threshold
// continue to route via `oversized_buffer` (soft) — recovery preserved on
// small-page-count + large-byte-size PDFs.
//
// Mocks `pdf-text-extract` so the resolver test can drive both legs of the
// gate (oversized_buffer + numPages above/below threshold + metadata-read
// failures) without synthesizing real PDFs.

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
  // #3369: mirrorWithDebounce extracted to observability.ts.
  // kb-document-resolver routes extractPdfText failure mirrors
  // through it; forward straight through so the existing spy
  // assertions keep working.
  mirrorWithDebounce: reportSilentFallbackSpy,
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));

vi.mock("@/server/pdf-text-extract", async () => {
  // Import the real module so the threshold constants stay in lockstep
  // with the source — hardcoded test-side values silently desync if the
  // production threshold ever shifts. Spread `actual` then override the
  // two functions whose behavior the test drives via spies.
  const actual = await vi.importActual<typeof import("@/server/pdf-text-extract")>(
    "@/server/pdf-text-extract",
  );
  return {
    ...actual,
    extractPdfText: extractPdfTextSpy,
    extractPdfMetadata: extractPdfMetadataSpy,
  };
});

import { resolveConciergeDocumentContext } from "@/server/cc-dispatcher";
import { _resetWorkspacePathCacheForTests } from "@/server/kb-document-resolver";

let tmpRoot: string;

beforeEach(() => {
  tmpRoot = realpathSync(
    mkdtempSync(path.join(tmpdir(), "kb-document-resolver-pdf-page-gate-")),
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

describe("kb-document-resolver PDF page-count gate (#3429)", () => {
  function seedPdf(rel: string, contents = "%PDF-1.4\nfake") {
    mkdirSync(path.join(tmpRoot, path.dirname(rel)), { recursive: true });
    writeFileSync(path.join(tmpRoot, rel), Buffer.from(contents));
  }

  it("surfaces too_many_pages when oversized_buffer + numPages > 150", async () => {
    seedPdf("knowledge-base/manning.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 403 });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/manning.pdf",
    });

    expect(result.documentExtractError).toBe("too_many_pages");
    expect(result.documentExtractMeta).toEqual({ numPages: 403 });
    expect(result.documentKind).toBe("pdf");
    expect(extractPdfMetadataSpy).toHaveBeenCalledTimes(1);
  });

  it("falls through to oversized_buffer (soft) when numPages = 50", async () => {
    seedPdf("knowledge-base/image-heavy.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 50 });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/image-heavy.pdf",
    });

    expect(result.documentExtractError).toBe("oversized_buffer");
    expect(result.documentExtractMeta).toBeUndefined();
  });

  it("falls through to oversized_buffer (soft) at exactly the threshold (numPages = 150)", async () => {
    // Threshold is `> LARGE_PDF_PAGE_THRESHOLD` — equal-to stays soft.
    seedPdf("knowledge-base/edge.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({ ok: true, numPages: 150 });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/edge.pdf",
    });

    expect(result.documentExtractError).toBe("oversized_buffer");
  });

  it("fails closed to oversized_buffer when metadata read returns oversized", async () => {
    seedPdf("knowledge-base/huge.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({
      ok: false,
      reason: "oversized",
    });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/huge.pdf",
    });

    expect(result.documentExtractError).toBe("oversized_buffer");
    expect(result.documentExtractMeta).toBeUndefined();
  });

  it("fails closed to oversized_buffer on metadata-read timeout", async () => {
    seedPdf("knowledge-base/slow.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({
      ok: false,
      reason: "timeout",
    });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/slow.pdf",
    });

    expect(result.documentExtractError).toBe("oversized_buffer");
  });

  it("fails closed to oversized_buffer on metadata-read parse_error", async () => {
    seedPdf("knowledge-base/garbage.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });
    extractPdfMetadataSpy.mockResolvedValueOnce({
      ok: false,
      reason: "parse_error",
    });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/garbage.pdf",
    });

    expect(result.documentExtractError).toBe("oversized_buffer");
  });

  it("does NOT call extractPdfMetadata for non-oversized_buffer extractor failures", async () => {
    // The gate is keyed off oversized_buffer specifically — other soft/hard
    // classes route on their existing partition without paying a metadata
    // read.
    seedPdf("knowledge-base/encrypted.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({ error: "encrypted" });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/encrypted.pdf",
    });

    expect(result.documentExtractError).toBe("encrypted");
    expect(extractPdfMetadataSpy).not.toHaveBeenCalled();
  });

  it("does NOT call extractPdfMetadata when extraction succeeds", async () => {
    seedPdf("knowledge-base/normal.pdf");
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "Chapter 1\nIntro",
      truncated: false,
      pageCount: 12,
    });

    const result = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/normal.pdf",
    });

    expect(result.documentContent).toContain("Chapter 1");
    expect(extractPdfMetadataSpy).not.toHaveBeenCalled();
  });
});
