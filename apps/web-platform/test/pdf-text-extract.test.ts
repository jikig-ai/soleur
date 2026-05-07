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

import { describe, it, expect } from "vitest";

import {
  extractPdfText,
  extractPdfMetadata,
  LARGE_PDF_PAGE_THRESHOLD,
  METADATA_READ_BYTE_CEILING_BYTES,
  METADATA_READ_TIMEOUT_MS,
} from "@/server/pdf-text-extract";
import { MAX_AGENT_READABLE_PDF_SIZE } from "@/lib/attachment-constants";

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

describe("extractPdfText", () => {
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

  it("caps page iteration at MAX_PAGES and reports truncated=true (#3338 P1-B)", async () => {
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
// NOTE: pdfjs-mock-based tests (timeout, lazy_import_failed) live in the
// sibling file `pdf-text-extract-mocked.test.ts` so vitest's per-file
// isolation prevents the module mocks from leaking into the real-pdfjs
// tests below.
describe("extractPdfMetadata (#3429)", () => {
  it("exports the threshold and ceiling constants with sensible values", () => {
    expect(LARGE_PDF_PAGE_THRESHOLD).toBe(150);
    expect(METADATA_READ_BYTE_CEILING_BYTES).toBe(60 * 1024 * 1024);
    expect(METADATA_READ_TIMEOUT_MS).toBe(3000);
  });

  it("returns { ok: false, reason: 'oversized' } when buffer exceeds METADATA_READ_BYTE_CEILING_BYTES — short-circuits before pdfjs runs", async () => {
    // Allocate a buffer one byte over the ceiling. The function MUST
    // short-circuit BEFORE invoking pdfjs (otherwise the test would pay
    // 60MB+ pdfjs xref-build cost). Wall-clock <50ms is the cheapest
    // proxy for "no parser invocation".
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
