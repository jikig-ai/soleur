// Server-side PDF text extraction for KB Concierge document context (#3338).
//
// The Concierge can't reliably ask the model to call the SDK Read tool on a
// PDF the user is viewing — even with the gated capability + named-binary
// exclusion directives (PRs #3253/#3263/#3278/#3287/#3288/#3294), the model's
// training prior on `pdftotext` / `pdfplumber` / `pdf-parse` / `apt-get` still
// occasionally wins and pops a Bash modal at the end user (or a `find` modal
// when it tries to discover the file). The durable fix is to extract the PDF's
// text on the server at cold-Query construction so the agent sees an inline
// `<document>...</document>` body and never has to call Read.
//
// Implementation mirrors `kb-preview-metadata.ts`: lazy-import
// `pdfjs-dist/legacy/build/pdf.mjs`, `isEvalSupported: false`,
// `doc.destroy()`-in-finally. The legacy entry ships with a Node fake worker
// so `GlobalWorkerOptions` does not need to be set; metadata-only callers
// (`readPdfMetadata`) prove this works at cold-start. Encrypted PDFs reject
// cleanly because no `onPassword` callback is registered.
//
// Cap shape:
//   - Input buffer cap = 15 MB (mirrors `PREVIEW_MAX_BYTES`). Larger PDFs
//     return null; the caller falls through to the Read directive (with the
//     existing 32 MB Anthropic API ceiling — separate scope-out at #3332).
//   - Output text cap = `capChars` (caller-provided). Page iteration halts
//     once the running length exceeds the cap; the last page is sliced at a
//     code-unit boundary. Reports `truncated: true` when the cap fired.
//
// Errors are silent-fallbacks: corrupted, encrypted, or unparseable PDFs
// return null. The CALLER is responsible for mirroring to Sentry via
// `reportSilentFallback` (per `cq-silent-fallback-must-mirror-to-sentry`)
// because feature/op tags are call-site specific.

const INPUT_BUFFER_CAP_BYTES = 15 * 1024 * 1024;

export interface PdfTextExtractResult {
  text: string;
  truncated: boolean;
  pageCount: number;
}

/**
 * Extract text from a PDF buffer using the in-process `pdfjs-dist` parser.
 * Returns `null` on parse failure (corrupted, encrypted, oversized input);
 * the caller decides whether to mirror to Sentry.
 */
export async function extractPdfText(
  buffer: Buffer | Uint8Array,
  capChars: number,
): Promise<PdfTextExtractResult | null> {
  if (buffer.length > INPUT_BUFFER_CAP_BYTES) {
    return null;
  }

  // Lazy import — paid once per process (shared with `readPdfMetadata`).
  let pdfjs: typeof import("pdfjs-dist/legacy/build/pdf.mjs");
  try {
    pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  } catch {
    return null;
  }

  // pdfjs-dist@5.4.296 explicitly REJECTS Buffer ("Please provide binary data
  // as Uint8Array, rather than Buffer."), even though Buffer is a Uint8Array
  // subclass — the check is `instanceof Buffer === false`. Wrap to a plain
  // Uint8Array view (no copy) so the legacy parser entry accepts it.
  const isNodeBuffer =
    typeof Buffer !== "undefined" && Buffer.isBuffer(buffer);
  const data = isNodeBuffer
    ? new Uint8Array(
        (buffer as Buffer).buffer,
        (buffer as Buffer).byteOffset,
        (buffer as Buffer).byteLength,
      )
    : (buffer as Uint8Array);

  let doc: Awaited<ReturnType<typeof pdfjs.getDocument>["promise"]> | null =
    null;
  try {
    doc = await pdfjs.getDocument({
      data,
      isEvalSupported: false,
      // No `onPassword` callback — encrypted PDFs reject with PasswordException
      // and we return null. The Read-directive fallback path also can't read
      // encrypted PDFs (the SDK Read tool's Files API path fails on them too),
      // so users get a content-grounded error message either way.
    }).promise;

    const pageCount = doc.numPages;
    let text = "";
    let truncated = false;

    for (let pageNum = 1; pageNum <= pageCount; pageNum++) {
      const page = await doc.getPage(pageNum);
      try {
        const content = await page.getTextContent();
        const items = content.items as Array<{ str?: string }>;
        let pageText = "";
        for (const item of items) {
          if (typeof item.str === "string" && item.str.length > 0) {
            pageText += item.str + " ";
          }
        }
        // Insert a newline between pages so the model sees page boundaries.
        const piece = pageNum === 1 ? pageText : "\n" + pageText;
        if (text.length + piece.length > capChars) {
          // Halt — slice the partial page at the cap and stop iterating.
          text += piece.slice(0, capChars - text.length);
          truncated = true;
          break;
        }
        text += piece;
      } finally {
        // Free per-page resources promptly on big PDFs.
        page.cleanup();
      }
    }

    return { text, truncated, pageCount };
  } catch {
    return null;
  } finally {
    if (doc) {
      await doc.destroy().catch(() => {});
    }
  }
}
