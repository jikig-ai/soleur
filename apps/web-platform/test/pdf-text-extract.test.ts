// Unit tests for `extractPdfText` (#3338 plan §Phase 1).
//
// PDF fixtures are synthesized inline (per `cq-test-fixtures-synthesized-only`):
// `makeMinimalPdf(pages)` builds a minimal but spec-conforming PDF byte buffer
// with one Type1 Helvetica font reference and one text-showing operator per
// page. xref offsets are computed at append time.

import { describe, it, expect } from "vitest";

import { extractPdfText } from "@/server/pdf-text-extract";

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
    // Use binary encoding so high-byte chars in the PDF binary marker
    // pass through verbatim.
    const b = Buffer.from(s, "binary");
    chunks.push(b);
    const before = totalBytes;
    totalBytes += b.length;
    return before;
  }

  // PDF header + binary marker.
  append("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n");

  const numPages = pageTexts.length;
  // Object IDs: 1 Catalog, 2 Pages, 3 Font, 4..3+N Pages, 4+N..3+2N Contents.
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

describe("extractPdfText", () => {
  it("extracts text from a single-page PDF", async () => {
    const buf = makeMinimalPdf(["Hello World"]);
    const result = await extractPdfText(buf, 50_000);
    expect(result).not.toBeNull();
    expect(result!.pageCount).toBe(1);
    expect(result!.truncated).toBe(false);
    expect(result!.text).toContain("Hello World");
  });

  it("extracts text from a multi-page PDF and reports pageCount", async () => {
    const buf = makeMinimalPdf(["Page One Body", "Page Two Body"]);
    const result = await extractPdfText(buf, 50_000);
    expect(result).not.toBeNull();
    expect(result!.pageCount).toBe(2);
    expect(result!.text).toContain("Page One Body");
    expect(result!.text).toContain("Page Two Body");
    expect(result!.truncated).toBe(false);
  });

  it("truncates output and reports truncated=true when capChars is small", async () => {
    const buf = makeMinimalPdf([
      "AAAAAAAAAA BBBBBBBBBB CCCCCCCCCC",
      "DDDDDDDDDD EEEEEEEEEE FFFFFFFFFF",
    ]);
    const result = await extractPdfText(buf, 20);
    expect(result).not.toBeNull();
    expect(result!.truncated).toBe(true);
    expect(result!.text.length).toBeLessThanOrEqual(20);
  });

  it("returns null on a corrupted buffer (no PDF header)", async () => {
    const garbage = Buffer.from("this is definitely not a PDF file");
    const result = await extractPdfText(garbage, 50_000);
    expect(result).toBeNull();
  });

  it("returns null when buffer exceeds 15 MB input cap", async () => {
    // Input cap mirrors PREVIEW_MAX_BYTES at kb-preview-metadata.ts:25.
    // Refuse without invoking the parser to avoid a 200-300 MB RSS spike.
    const oversized = Buffer.alloc(15 * 1024 * 1024 + 1);
    const result = await extractPdfText(oversized, 50_000);
    expect(result).toBeNull();
  });

  it("handles an empty (zero-page) PDF without throwing", async () => {
    // Synthesized 0-page PDF — `pdfjs-dist` typically rejects an empty Pages
    // tree as malformed; either { text: "", pageCount: 0 } or null is an
    // acceptable terminal state. Asserts no throw and a sane shape.
    const buf = makeMinimalPdf([]);
    const result = await extractPdfText(buf, 50_000);
    if (result !== null) {
      expect(result.pageCount).toBeGreaterThanOrEqual(0);
      expect(typeof result.text).toBe("string");
      expect(result.truncated).toBe(false);
    }
  });

  it("returns null on a PDF with truncated body (graceful reject — covers password/encrypted class)", async () => {
    // Behaviorally identical to T3 per plan §"Test Scenarios" T4: any
    // unparseable PDF (corrupted body, password-protected without callback,
    // unsupported filter) returns null and the caller falls through to the
    // Read directive. Synthesizing a spec-correct encrypted PDF in pure JS
    // requires implementing PDF encryption (RC4/AES-128/256 + key derivation)
    // — disproportionate to the assertion. A truncated PDF body covers the
    // same code path: pdfjs throws on missing root catalog → catch → null.
    const buf = makeMinimalPdf(["Secret content"]);
    // Truncate mid-stream so the xref offsets point past EOF.
    const truncated = buf.subarray(0, Math.floor(buf.length / 2));
    const result = await extractPdfText(truncated, 50_000);
    expect(result).toBeNull();
  });
});
