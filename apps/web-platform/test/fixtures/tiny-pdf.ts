// Synthesized single-page PDF buffer for bundled-server regression tests.
//
// Per `cq-test-fixtures-synthesized-only`: no real PDF files in the repo.
// Constructed at module load with a minimal Type1/Helvetica text-showing
// operator so pdfjs's `getTextContent()` returns the embedded literal.
//
// Imported by:
//   - test/fixtures/extract-entry.ts (esbuild bundles → node execs)
//   - test/fixtures/metadata-entry.ts (same)
//   - test/pdf-text-extract.bundled-server.test.ts
//   - test/kb-preview-metadata.bundled-server.test.ts

function buildTinyPdf(text: string): Buffer {
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

  const fontId = 3;
  const pageId = 4;
  const contentId = 5;

  offsets.push(append(`1 0 obj\n<</Type /Catalog /Pages 2 0 R>>\nendobj\n`));
  offsets.push(
    append(
      `2 0 obj\n<</Type /Pages /Kids [${pageId} 0 R] /Count 1>>\nendobj\n`,
    ),
  );
  offsets.push(
    append(
      `3 0 obj\n<</Type /Font /Subtype /Type1 /BaseFont /Helvetica>>\nendobj\n`,
    ),
  );
  offsets.push(
    append(
      `${pageId} 0 obj\n<</Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents ${contentId} 0 R /Resources <</Font <</F1 ${fontId} 0 R>>>>>>\nendobj\n`,
    ),
  );

  const escaped = text
    .replace(/\\/g, "\\\\")
    .replace(/\(/g, "\\(")
    .replace(/\)/g, "\\)");
  const stream = `BT\n/F1 12 Tf\n50 700 Td\n(${escaped}) Tj\nET\n`;
  const len = Buffer.byteLength(stream, "binary");
  offsets.push(
    append(
      `${contentId} 0 obj\n<</Length ${len}>>\nstream\n${stream}endstream\nendobj\n`,
    ),
  );

  const totalObjs = 5;
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

export const TINY_PDF_TEXT = "Hello PDF";
export const TINY_PDF_BUFFER: Buffer = buildTinyPdf(TINY_PDF_TEXT);
