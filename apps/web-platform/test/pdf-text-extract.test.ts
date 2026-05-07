// Unit tests for `extractPdfText` (#3338 plan §Phase 1, follow-up plan
// 2026-05-06-fix-extract-pdf-text-null-in-production-plan.md §Phase 1).
//
// PDF fixtures are synthesized inline (per `cq-test-fixtures-synthesized-only`):
// `makeMinimalPdf(pages)` builds a minimal but spec-conforming PDF byte buffer
// with one Type1 Helvetica font reference and one text-showing operator per
// page. xref offsets are computed at append time.
//
// As of the 2026-05-06 follow-up, `extractPdfText` returns a discriminated
// union: a successful `PdfTextExtractResult` OR `{ error: PdfExtractErrorClass }`
// where the class names the failure shape. The previous null-returns are
// gone — tests that asserted `toBeNull()` now assert `result.error === <class>`
// so the next Sentry event diagnoses itself.

import { describe, it, expect, vi } from "vitest";

import {
  extractPdfText,
  extractPdfMetadata,
  extractPdfOutline,
  LARGE_PDF_PAGE_THRESHOLD,
  METADATA_READ_BYTE_CEILING_BYTES,
  METADATA_READ_TIMEOUT_MS,
  MIN_OUTLINE_ENTRIES,
  OUTLINE_PAGE_COVERAGE_MIN,
  OUTLINE_READ_TIMEOUT_MS,
} from "@/server/pdf-text-extract";
import { MAX_AGENT_READABLE_PDF_SIZE } from "@/lib/attachment-constants";
import {
  BELOW_PDFJS_ENGINES_FLOOR,
  emitPdfjsEngineFloorDiagnostic,
} from "./helpers/engines-floor";

// Engine-floor guard for #3439 (follow-up to #3424). See
// `test/helpers/engines-floor.ts` for the rationale (pdfjs-dist@5 calls
// `process.getBuiltinModule`, added in Node 22.3 / 20.16). Dev path:
// describe.skipIf + single stderr diagnostic. CI path: throw at module init
// so a misconfigured runner can't ship vacuous green. The lazy_import_failed
// test below sits OUTSIDE the skipIf because it mocks the real import — the
// engine floor is irrelevant to it.
emitPdfjsEngineFloorDiagnostic("pdf-text-extract.test");

/**
 * Build a minimal PDF byte buffer with one text-showing operator per page.
 * Returns a Buffer suitable for `extractPdfText`. No real PDF binaries land
 * in the repo (per `cq-test-fixtures-synthesized-only`).
 */
function makeMinimalPdf(pageTexts: string[]): Buffer {
  const chunks: Buffer[] = [];
  let totalBytes = 0;
  const offsets: number[] = [];

  function append(s: string): number {
    const b = Buffer.from(s, "binary");
    chunks.push(b);
    const before = totalBytes;
    totalBytes += b.length;
    return before;
  }

  append("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n");

  const numPages = pageTexts.length;
  const fontId = 3;
  const pageStartId = 4;
  const contentStartId = 4 + numPages;

  offsets.push(append(`1 0 obj\n<</Type /Catalog /Pages 2 0 R>>\nendobj\n`));

  const kidsStr =
    numPages > 0
      ? Array.from({ length: numPages }, (_, i) => `${pageStartId + i} 0 R`).join(
          " ",
        )
      : "";
  offsets.push(
    append(
      `2 0 obj\n<</Type /Pages /Kids [${kidsStr}] /Count ${numPages}>>\nendobj\n`,
    ),
  );

  offsets.push(
    append(
      `3 0 obj\n<</Type /Font /Subtype /Type1 /BaseFont /Helvetica>>\nendobj\n`,
    ),
  );

  for (let i = 0; i < numPages; i++) {
    offsets.push(
      append(
        `${pageStartId + i} 0 obj\n<</Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents ${contentStartId + i} 0 R /Resources <</Font <</F1 ${fontId} 0 R>>>>>>\nendobj\n`,
      ),
    );
  }

  for (let i = 0; i < numPages; i++) {
    const escaped = pageTexts[i]
      .replace(/\\/g, "\\\\")
      .replace(/\(/g, "\\(")
      .replace(/\)/g, "\\)");
    const stream = `BT\n/F1 12 Tf\n50 700 Td\n(${escaped}) Tj\nET\n`;
    const len = Buffer.byteLength(stream, "binary");
    offsets.push(
      append(
        `${contentStartId + i} 0 obj\n<</Length ${len}>>\nstream\n${stream}endstream\nendobj\n`,
      ),
    );
  }

  const totalObjs = 3 + 2 * numPages;
  const xrefOffset = totalBytes;
  let xref = `xref\n0 ${totalObjs + 1}\n0000000000 65535 f \n`;
  for (const off of offsets) {
    xref += `${String(off).padStart(10, "0")} 00000 n \n`;
  }
  append(xref);

  append(
    `trailer\n<</Size ${totalObjs + 1} /Root 1 0 R>>\nstartxref\n${xrefOffset}\n%%EOF\n`,
  );

  return Buffer.concat(chunks);
}

function isOk(
  result: Awaited<ReturnType<typeof extractPdfText>>,
): result is { text: string; truncated: boolean; pageCount: number } {
  return result !== null && !("error" in result);
}

describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)("extractPdfText", () => {
  it("extracts text from a single-page PDF", async () => {
    const buf = makeMinimalPdf(["Hello World"]);
    const result = await extractPdfText(buf, 50_000);
    expect(isOk(result)).toBe(true);
    if (!isOk(result)) return;
    expect(result.pageCount).toBe(1);
    expect(result.truncated).toBe(false);
    expect(result.text).toContain("Hello World");
  });

  it("extracts text from a multi-page PDF and reports pageCount", async () => {
    const buf = makeMinimalPdf(["Page One Body", "Page Two Body"]);
    const result = await extractPdfText(buf, 50_000);
    expect(isOk(result)).toBe(true);
    if (!isOk(result)) return;
    expect(result.pageCount).toBe(2);
    expect(result.text).toContain("Page One Body");
    expect(result.text).toContain("Page Two Body");
    expect(result.truncated).toBe(false);
  });

  it("truncates output and reports truncated=true when capChars is small", async () => {
    const buf = makeMinimalPdf([
      "AAAAAAAAAA BBBBBBBBBB CCCCCCCCCC",
      "DDDDDDDDDD EEEEEEEEEE FFFFFFFFFF",
    ]);
    const result = await extractPdfText(buf, 20);
    expect(isOk(result)).toBe(true);
    if (!isOk(result)) return;
    expect(result.truncated).toBe(true);
    expect(result.text.length).toBeLessThanOrEqual(20);
  });

  it("returns { error: 'corrupted' | 'parse_error' } on a buffer with no PDF header", async () => {
    // pdfjs throws InvalidPDFException for a missing/invalid header → "corrupted".
    // Some pdfjs builds bubble the parse failure as a generic Error → "parse_error".
    // Either is acceptable; both are non-null so the caller's null-check no
    // longer fires the apt-get cascade.
    const garbage = Buffer.from("this is definitely not a PDF file");
    const result = await extractPdfText(garbage, 50_000);
    expect(result).not.toBeNull();
    expect(result && "error" in result).toBe(true);
    if (!result || !("error" in result)) return;
    expect(["corrupted", "parse_error"]).toContain(result.error);
  });

  it("returns { error: 'oversized_buffer' } when buffer exceeds the upload cap", async () => {
    // Hypothesis A: pre-fix the local INPUT_BUFFER_CAP_BYTES = 15 MB silently
    // gated PDFs in the [15 MB, 24 MB] band uploaded after #3337 raised the
    // upload cap to 24 MB. The fix aligns the extractor to the same constant.
    // The size guard fires only when buffer.length > MAX_AGENT_READABLE_PDF_SIZE.
    const oversized = Buffer.alloc(MAX_AGENT_READABLE_PDF_SIZE + 1);
    const result = await extractPdfText(oversized, 50_000);
    expect(result).not.toBeNull();
    expect(result && "error" in result).toBe(true);
    if (!result || !("error" in result)) return;
    expect(result.error).toBe("oversized_buffer");
  });

  it("does NOT trip oversized_buffer for buffers in the [old-15MB, new-24MB] band (Hypothesis A regression)", { timeout: 15_000 }, async () => {
    // Synthesize a 16 MB buffer of zero bytes. pdfjs will fail to parse
    // (InvalidPDFException → "corrupted"), but the critical assertion is
    // that we did NOT short-circuit on the input cap. Pre-fix this returned
    // null (oversized_buffer) silently, hitting the apt-get cascade.
    const sixteenMb = Buffer.alloc(16 * 1024 * 1024);
    // Stamp a PDF header so this isn't an obviously invalid header path.
    sixteenMb.write("%PDF-1.4\n");
    const result = await extractPdfText(sixteenMb, 50_000);
    expect(result).not.toBeNull();
    expect(result && "error" in result).toBe(true);
    if (!result || !("error" in result)) return;
    // Critical invariant: the cap-aligned extractor MUST classify this
    // buffer as a parse-failure shape — NOT as oversized_buffer (which
    // would re-introduce Hypothesis A) and NOT as a class outside the
    // expected pdfjs failure modes (which would hint at silent contract
    // drift in the library or our outer catch). Pin the actual observed
    // class on the current pdfjs-dist version so future drift surfaces as
    // an actionable failure message ("expected 'parse_error' to be
    // 'corrupted'") rather than a vacuous pass.
    expect(["corrupted", "parse_error"]).toContain(result.error);
  });

  it("handles an empty (zero-page) PDF without throwing — empty_text or terminal shape", async () => {
    // Synthesized 0-page PDF — pdfjs typically rejects an empty Pages tree as
    // malformed. Acceptable terminal states: { text: "", pageCount: 0,
    // truncated: false } OR { error: "empty_text" } OR { error: "corrupted" |
    // "parse_error" }. All non-null shapes are fine.
    const buf = makeMinimalPdf([]);
    const result = await extractPdfText(buf, 50_000);
    expect(result).not.toBeNull();
    if (!result) return;
    if (isOk(result)) {
      expect(result.pageCount).toBeGreaterThanOrEqual(0);
      expect(typeof result.text).toBe("string");
    } else {
      expect(["empty_text", "corrupted", "parse_error"]).toContain(result.error);
    }
  });

  it("returns { error: 'corrupted' | 'parse_error' } on a mid-stream-truncated body", async () => {
    // Mid-stream truncation makes xref offsets point past EOF; pdfjs throws
    // a parser exception → "corrupted" (InvalidPDFException) or
    // "parse_error" (generic). Note: this test does NOT exercise the
    // password-protected / encrypted PDF path — synthesizing spec-correct
    // RC4/AES-128 encryption in pure JS is disproportionate to the
    // assertion. The encrypted-PDF graceful-reject path is reached via the
    // same `try/catch` in extractPdfText (PasswordException is mapped to
    // "encrypted" via its `.name` property; coverage for the branch is in
    // the cc-dispatcher-concierge-context.test.ts mock-driven scenarios).
    const buf = makeMinimalPdf(["Secret content"]);
    const truncated = buf.subarray(0, Math.floor(buf.length / 2));
    const result = await extractPdfText(truncated, 50_000);
    expect(result).not.toBeNull();
    expect(result && "error" in result).toBe(true);
    if (!result || !("error" in result)) return;
    expect(["corrupted", "parse_error"]).toContain(result.error);
  });

  // 30s ceiling: the extractor caps iteration at MAX_PAGES=500 (server/pdf-text-extract.ts);
  // 500 pdfjs getPage+getTextContent calls run ~3-8s locally, so 30s gives ~4x headroom
  // for cold-cache CI variance without tolerating real regressions (default vitest 5s
  // would fail on slow runners).
  it("caps page iteration at MAX_PAGES and reports truncated=true (#3338 P1-B)", { timeout: 30_000 }, async () => {
    const pages = Array.from({ length: 600 }, (_, i) => `p${i}`);
    const buf = makeMinimalPdf(pages);
    const result = await extractPdfText(buf, 50_000);
    expect(isOk(result)).toBe(true);
    if (!isOk(result)) return;
    expect(result.pageCount).toBe(600);
    expect(result.truncated).toBe(true);
  });
});

// 2026-05-07 follow-up to #3429: extractPdfMetadata bridge fix.
// Metadata-only pdfjs read on the soft-route path. When extractPdfText
// raises `oversized_buffer` for a >24MB PDF, the resolver calls this
// function to obtain numPages cheaply (xref-only, no per-page text
// iteration). PDFs with `numPages > LARGE_PDF_PAGE_THRESHOLD` route to the
// new HARD class `too_many_pages` to avoid the Read-fanout idle-reaper
// timeout described in #3429.
//
// `skipIf(BELOW_PDFJS_ENGINES_FLOOR)` because the "valid 3-page PDF" test
// calls real pdfjs which needs Node ≥22.3 / 20.16 per the engines field.
// The mock-based timeout test lives in `pdf-text-extract-mocked.test.ts`.
describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)("extractPdfMetadata (#3429)", () => {
  it("exports the threshold and ceiling constants with sensible values", () => {
    expect(LARGE_PDF_PAGE_THRESHOLD).toBe(150);
    expect(METADATA_READ_BYTE_CEILING_BYTES).toBe(40 * 1024 * 1024);
    expect(METADATA_READ_TIMEOUT_MS).toBe(3000);
  });

  it("returns { ok: false, reason: 'oversized' } when buffer exceeds METADATA_READ_BYTE_CEILING_BYTES — short-circuits before pdfjs runs", async () => {
    // Allocate a buffer one byte over the ceiling. The function MUST
    // short-circuit BEFORE invoking pdfjs (otherwise the test would pay
    // pdfjs xref-build cost). Wall-clock <50ms is the cheapest proxy
    // for "no parser invocation".
    const oversized = Buffer.alloc(METADATA_READ_BYTE_CEILING_BYTES + 1);
    const start = Date.now();
    const result = await extractPdfMetadata(oversized);
    const elapsed = Date.now() - start;
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.reason).toBe("oversized");
    expect(elapsed).toBeLessThan(50);
  });

  it("returns { ok: true, numPages } for a valid 3-page PDF", async () => {
    const buf = makeMinimalPdf(["p1", "p2", "p3"]);
    const result = await extractPdfMetadata(buf);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.numPages).toBe(3);
  });

  it("returns { ok: false, reason: 'parse_error' } on a buffer with no PDF header", async () => {
    const garbage = Buffer.from("this is definitely not a PDF file");
    const result = await extractPdfMetadata(garbage);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.reason).toBe("parse_error");
  });
});

// 2026-05-07 plan §Phase 2 (#3436): page-range slicing on extractPdfText.
// Chapter-chunked resolver branch slices a chapter via
// `extractPdfText(buffer, capChars, { startPage, endPage })`. Validation:
// 1-based pages, endPage <= numPages, endPage >= startPage. Invalid range
// returns { error: "parse_error" } (existing class; no new union member).
describe.skipIf(BELOW_PDFJS_ENGINES_FLOOR)("extractPdfText page-range option (#3436)", () => {
  it("slices a single chapter when given startPage/endPage", async () => {
    const buf = makeMinimalPdf([
      "Page One Body",
      "Page Two Body",
      "Page Three Body",
      "Page Four Body",
    ]);
    const result = await extractPdfText(buf, 50_000, {
      startPage: 2,
      endPage: 3,
    });
    expect(isOk(result)).toBe(true);
    if (!isOk(result)) return;
    expect(result.text).toContain("Page Two Body");
    expect(result.text).toContain("Page Three Body");
    expect(result.text).not.toContain("Page One Body");
    expect(result.text).not.toContain("Page Four Body");
  });

  it("returns { error: 'parse_error' } when startPage < 1", async () => {
    const buf = makeMinimalPdf(["a", "b", "c"]);
    const result = await extractPdfText(buf, 50_000, { startPage: 0, endPage: 2 });
    expect(result && "error" in result).toBe(true);
    if (!result || !("error" in result)) return;
    expect(result.error).toBe("parse_error");
  });

  it("returns { error: 'parse_error' } when endPage > numPages", async () => {
    const buf = makeMinimalPdf(["a", "b", "c"]);
    const result = await extractPdfText(buf, 50_000, { startPage: 1, endPage: 99 });
    expect(result && "error" in result).toBe(true);
    if (!result || !("error" in result)) return;
    expect(result.error).toBe("parse_error");
  });

  it("returns { error: 'parse_error' } when endPage < startPage", async () => {
    const buf = makeMinimalPdf(["a", "b", "c"]);
    const result = await extractPdfText(buf, 50_000, { startPage: 3, endPage: 2 });
    expect(result && "error" in result).toBe(true);
    if (!result || !("error" in result)) return;
    expect(result.error).toBe("parse_error");
  });

  it("returns { error: 'oversized_buffer' } when slice would exceed cap (synthetic ceiling)", async () => {
    // Drive `oversized_buffer` for a chapter slice using a tiny capChars on
    // a real range. The plan reserves `oversized_buffer` for "chapter X is
    // too large" — distinguishable from the per-PDF input cap because the
    // resolver narrows the range BEFORE invoking the extractor.
    const buf = makeMinimalPdf([
      "AAAAAAAAAAAAAAAAAAAAAAAA",
      "BBBBBBBBBBBBBBBBBBBBBBBB",
    ]);
    // capChars=1 forces the slice output to overflow on the very first
    // page text. Currently extractPdfText would return truncated output;
    // the new contract returns an explicit oversized_buffer when the
    // SLICE output would exceed cap. (RED until impl wires this.)
    const result = await extractPdfText(buf, 1, { startPage: 1, endPage: 2 });
    expect(result && "error" in result).toBe(true);
    if (!result || !("error" in result)) return;
    expect(result.error).toBe("oversized_buffer");
  });
});

// 2026-05-07 plan §Phase 2 (#3436): extractPdfOutline shape contract.
// Tests run against a mocked pdfjs module so we can exercise the
// outline-walking logic without synthesizing a fully-spec'd /Outlines tree
// in raw PDF bytes (consistent with the lazy_import_failed pattern below).
describe("extractPdfOutline (#3436)", () => {
  function makeMockPdfjs(opts: {
    numPages: number;
    outline: Array<{
      title: string;
      // pdfjs's getOutline returns `dest` (string for named destinations,
      // array for explicit). Use `destName` in fixture spec for ergonomics
      // and rewrite to the wire shape below.
      destName?: string | null;
    }> | null;
    pageIndexByName?: Record<string, number>;
    timeoutMs?: number;
  }) {
    const doc = {
      numPages: opts.numPages,
      // Wire shape: `dest: <name>` (a string named destination), matching pdfjs.
      getOutline: async () =>
        opts.outline === null
          ? null
          : opts.outline.map((entry) => ({
              title: entry.title,
              dest: entry.destName ?? null,
              items: [],
            })),
      getDestination: async (name: string) => {
        const idx = opts.pageIndexByName?.[name];
        if (idx === undefined) return null;
        return [{ __pageRef: idx }, { name: "XYZ" }];
      },
      getPageIndex: async (ref: { __pageRef?: number } | unknown) => {
        if (typeof ref === "object" && ref !== null && "__pageRef" in ref) {
          return (ref as { __pageRef: number }).__pageRef;
        }
        return -1;
      },
      destroy: async () => {},
    };
    return {
      getDocument: () => {
        const promise =
          opts.timeoutMs !== undefined
            ? new Promise((resolve) => setTimeout(() => resolve(doc), opts.timeoutMs))
            : Promise.resolve(doc);
        return { promise, destroy: async () => {} };
      },
    };
  }

  async function importIsolated() {
    vi.resetModules();
    return await import("@/server/pdf-text-extract");
  }

  it("exports outline tunables with sensible values", async () => {
    expect(MIN_OUTLINE_ENTRIES).toBe(3);
    expect(OUTLINE_PAGE_COVERAGE_MIN).toBeCloseTo(0.8);
    expect(OUTLINE_READ_TIMEOUT_MS).toBe(5000);
  });

  it("returns { ok: true, outline } for a usable outline meeting MIN_OUTLINE_ENTRIES + coverage", async () => {
    try {
      // 3 chapters at pages 1, 50, 90 of 100 pages — last chapter starts
      // at page 90 = 0.9 coverage, ≥ OUTLINE_PAGE_COVERAGE_MIN (0.8).
      const mockPdfjs = makeMockPdfjs({
        numPages: 100,
        outline: [
          { title: "Chapter 1", destName: "ch1" },
          { title: "Chapter 2", destName: "ch2" },
          { title: "Chapter 3", destName: "ch3" },
        ],
        pageIndexByName: { ch1: 0, ch2: 49, ch3: 89 },
      });
      vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", () => mockPdfjs);
      const mod = await importIsolated();
      const buf = Buffer.from("%PDF-1.4\n");
      const result = await mod.extractPdfOutline(buf);
      expect(result.ok).toBe(true);
      if (!result.ok) return;
      expect(result.outline).toHaveLength(3);
      // Page indices in ChapterIndex are 1-based per plan TR1.
      expect(result.outline[0].title).toBe("Chapter 1");
      expect(result.outline[0].startPage).toBe(1);
      expect(result.outline[0].endPage).toBe(49);
      expect(result.outline[1].startPage).toBe(50);
      expect(result.outline[1].endPage).toBe(89);
      expect(result.outline[2].startPage).toBe(90);
      expect(result.outline[2].endPage).toBe(100);
    } finally {
      vi.doUnmock("pdfjs-dist/legacy/build/pdf.mjs");
      vi.resetModules();
    }
  });

  it("returns { ok: false, reason: 'no_outline' } when getOutline returns null", async () => {
    try {
      vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", () =>
        makeMockPdfjs({ numPages: 100, outline: null }),
      );
      const mod = await importIsolated();
      const buf = Buffer.from("%PDF-1.4\n");
      const result = await mod.extractPdfOutline(buf);
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.reason).toBe("no_outline");
    } finally {
      vi.doUnmock("pdfjs-dist/legacy/build/pdf.mjs");
      vi.resetModules();
    }
  });

  it("returns { ok: false, reason: 'outline_too_shallow' } when fewer than MIN_OUTLINE_ENTRIES", async () => {
    try {
      vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", () =>
        makeMockPdfjs({
          numPages: 100,
          outline: [
            { title: "Cover", destName: "cover" },
            { title: "Index", destName: "idx" },
          ],
          pageIndexByName: { cover: 0, idx: 50 },
        }),
      );
      const mod = await importIsolated();
      const buf = Buffer.from("%PDF-1.4\n");
      const result = await mod.extractPdfOutline(buf);
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.reason).toBe("outline_too_shallow");
    } finally {
      vi.doUnmock("pdfjs-dist/legacy/build/pdf.mjs");
      vi.resetModules();
    }
  });

  it("returns { ok: false, reason: 'outline_too_shallow' } when page coverage < OUTLINE_PAGE_COVERAGE_MIN", async () => {
    // 3 entries covering pages 1..30 of a 200-page PDF — coverage 0.15.
    try {
      vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", () =>
        makeMockPdfjs({
          numPages: 200,
          outline: [
            { title: "Front 1", destName: "f1" },
            { title: "Front 2", destName: "f2" },
            { title: "Front 3", destName: "f3" },
          ],
          pageIndexByName: { f1: 0, f2: 10, f3: 20 },
        }),
      );
      const mod = await importIsolated();
      const buf = Buffer.from("%PDF-1.4\n");
      const result = await mod.extractPdfOutline(buf);
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.reason).toBe("outline_too_shallow");
    } finally {
      vi.doUnmock("pdfjs-dist/legacy/build/pdf.mjs");
      vi.resetModules();
    }
  });

  it("returns { ok: false, reason: 'outline_too_shallow' } when ANY chapter dest cannot resolve (whole-outline fail)", async () => {
    // Plan: "If any chapter dest cannot resolve → treat WHOLE outline as
    // unusable (don't emit partial chapter list — better to fall through
    // to bridge than mis-bound chapters)."
    try {
      vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", () =>
        makeMockPdfjs({
          numPages: 100,
          outline: [
            { title: "Chapter 1", destName: "ch1" },
            { title: "Chapter 2", destName: "missing" },
            { title: "Chapter 3", destName: "ch3" },
          ],
          // Note: "missing" is intentionally absent from the resolution map.
          pageIndexByName: { ch1: 0, ch3: 66 },
        }),
      );
      const mod = await importIsolated();
      const buf = Buffer.from("%PDF-1.4\n");
      const result = await mod.extractPdfOutline(buf);
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.reason).toBe("outline_too_shallow");
    } finally {
      vi.doUnmock("pdfjs-dist/legacy/build/pdf.mjs");
      vi.resetModules();
    }
  });

  it("returns { ok: false, reason: 'timeout' } when getDocument exceeds OUTLINE_READ_TIMEOUT_MS", async () => {
    try {
      vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", () =>
        makeMockPdfjs({
          numPages: 100,
          outline: [],
          // Timeout is 5000ms; mocked load takes 6000ms.
          timeoutMs: 6000,
        }),
      );
      const mod = await importIsolated();
      const buf = Buffer.from("%PDF-1.4\n");
      const result = await mod.extractPdfOutline(buf);
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.reason).toBe("timeout");
    } finally {
      vi.doUnmock("pdfjs-dist/legacy/build/pdf.mjs");
      vi.resetModules();
    }
  }, 10_000);

  it.skipIf(BELOW_PDFJS_ENGINES_FLOOR)(
    "returns { ok: false, reason: 'parse_error' } on garbage input",
    async () => {
      // No mock — exercise the real parse failure path. Skipped below the
      // pdfjs engine floor (Node 22.3 / 20.16) per `engines-floor.ts`.
      const garbage = Buffer.from("definitely not a PDF");
      const result = await extractPdfOutline(garbage);
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.reason).toBe("parse_error");
    },
  );
});

// Direct unit test of the lazy_import_failed branch (#3438). Sits OUTSIDE
// the engine-floor describe.skipIf because the `vi.doMock` short-circuits
// the real `await import("pdfjs-dist/legacy/build/pdf.mjs")` — the runtime
// never reaches `process.getBuiltinModule`, so the test runs identically on
// Node 21.7.3 and Node 22.x. Asserts both the discriminated-union contract
// (`result.error === "lazy_import_failed"`) and the Sentry mirror call from
// `pdf-text-extract.ts:113-122` (so the silent-fallback observability can't
// regress without flipping the test red).
//
// Worker-isolation: relies on vitest's default per-file isolation
// (`vitest.config.ts` does NOT set `pool: "threads"` with `isolate: false`
// for the unit project). The before-import `vi.resetModules()` and the
// finally-block `vi.doUnmock` + `vi.resetModules()` together prevent
// in-file mock leakage; if the project ever moves to `isolate: false`,
// move this `describe` to its own file (`pdf-text-extract.lazy-import.test.ts`).
describe("extractPdfText lazy_import_failed", () => {
  it("returns lazy_import_failed when pdfjs module init throws", async () => {
    const reportSilentFallback = vi.fn();
    try {
      vi.doMock("@/server/observability", async () => {
        const actual = await vi.importActual<
          typeof import("@/server/observability")
        >("@/server/observability");
        return { ...actual, reportSilentFallback };
      });
      vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", () => {
        throw new Error("simulated module-init failure");
      });
      vi.resetModules();
      const { extractPdfText: extractPdfTextIsolated } = await import(
        "@/server/pdf-text-extract"
      );
      const buf = Buffer.from("%PDF-1.4\n");
      const result = await extractPdfTextIsolated(buf, 50_000);
      expect(result).toMatchObject({ error: "lazy_import_failed" });
      expect(reportSilentFallback).toHaveBeenCalledTimes(1);
      const [errArg, ctxArg] = reportSilentFallback.mock.calls[0];
      // Vitest wraps factory throws with its own Error; we don't assert on
      // the inner message because vitest swallows it. The discriminated-union
      // contract above + the observability feature/op shape below are the
      // load-bearing invariants.
      expect(errArg).toBeInstanceOf(Error);
      expect(ctxArg).toMatchObject({
        feature: "kb-concierge-context",
        op: "extractPdfText.import",
      });
      expect(ctxArg.extra).toMatchObject({
        nodeVersion: process.versions.node,
      });
    } finally {
      vi.doUnmock("@/server/observability");
      vi.doUnmock("pdfjs-dist/legacy/build/pdf.mjs");
      vi.resetModules();
    }
  });

  // 2026-05-07 follow-up to #3437: when the leader-document resolver calls
  // extractPdfText, lazy-import failures must mirror to Sentry with
  // `feature: "leader-context"` so operators can filter leader-side fires
  // from Concierge fires (which mirror with `feature: "kb-concierge-context"`).
  // Pre-fix the feature tag was hardcoded; this test pins the per-call
  // override surface (`featureTag` arg) so a future refactor can't silently
  // collapse the two paths to one tag.
  it("mirrors with caller-provided featureTag when one is passed", async () => {
    const reportSilentFallback = vi.fn();
    try {
      vi.doMock("@/server/observability", async () => {
        const actual = await vi.importActual<
          typeof import("@/server/observability")
        >("@/server/observability");
        return { ...actual, reportSilentFallback };
      });
      vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", () => {
        throw new Error("simulated module-init failure");
      });
      vi.resetModules();
      const { extractPdfText: extractPdfTextIsolated } = await import(
        "@/server/pdf-text-extract"
      );
      const buf = Buffer.from("%PDF-1.4\n");
      const result = await extractPdfTextIsolated(buf, 50_000, {
        featureTag: "leader-context",
      });
      expect(result).toMatchObject({ error: "lazy_import_failed" });
      expect(reportSilentFallback).toHaveBeenCalledTimes(1);
      const [, ctxArg] = reportSilentFallback.mock.calls[0];
      expect(ctxArg).toMatchObject({
        feature: "leader-context",
        op: "extractPdfText.import",
      });
    } finally {
      vi.doUnmock("@/server/observability");
      vi.doUnmock("pdfjs-dist/legacy/build/pdf.mjs");
      vi.resetModules();
    }
  });

  it("defaults featureTag to 'kb-concierge-context' when omitted", async () => {
    const reportSilentFallback = vi.fn();
    try {
      vi.doMock("@/server/observability", async () => {
        const actual = await vi.importActual<
          typeof import("@/server/observability")
        >("@/server/observability");
        return { ...actual, reportSilentFallback };
      });
      vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", () => {
        throw new Error("simulated module-init failure");
      });
      vi.resetModules();
      const { extractPdfText: extractPdfTextIsolated } = await import(
        "@/server/pdf-text-extract"
      );
      const buf = Buffer.from("%PDF-1.4\n");
      await extractPdfTextIsolated(buf, 50_000);
      const [, ctxArg] = reportSilentFallback.mock.calls[0];
      expect(ctxArg.feature).toBe("kb-concierge-context");
    } finally {
      vi.doUnmock("@/server/observability");
      vi.doUnmock("pdfjs-dist/legacy/build/pdf.mjs");
      vi.resetModules();
    }
  });
});
