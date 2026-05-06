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
// Cap shape (2026-05-06 follow-up to #3337/#3338):
//   - Input buffer cap is the SHARED constant `MAX_AGENT_READABLE_PDF_SIZE`
//     from `@/lib/attachment-constants` (24 MB). Aligning the extractor with
//     the upload validator closes Hypothesis A from
//     `2026-05-06-fix-extract-pdf-text-null-in-production-plan.md`: a PDF in
//     the [15 MB, 24 MB] band would pass upload but trip an unaligned 15 MB
//     extractor cap, returning null → the apt-get cascade.
//   - Output text cap = `capChars` (caller-provided). Page iteration halts
//     once the running length exceeds the cap; the last page is sliced at a
//     code-unit boundary. Reports `truncated: true` when the cap fired.
//
// Failure shape: the extractor returns a discriminated union — either a
// successful `PdfTextExtractResult` OR `{ error: <PdfExtractErrorClass> }`.
// The CALLER mirrors the failure to Sentry (per
// `cq-silent-fallback-must-mirror-to-sentry`) and uses `errorClass` to drive
// the user-facing fallback prompt (`buildPdfUnreadableDirective` —
// soleur-go-runner.ts) instead of the apt-get-prone gated Read directive.

import { MAX_AGENT_READABLE_PDF_SIZE } from "@/lib/attachment-constants";
import { reportSilentFallback } from "./observability";

/**
 * Hard cap on page iteration count. PDFs declare /Pages /Count independently
 * of byte size — a 1 MB attacker-crafted PDF can claim 1,000,000 empty pages
 * and pin the event loop calling getPage()+getTextContent() in a loop the
 * cap-at-capChars break never escapes (each page produces 0 chars). Bound
 * the loop independently. Real-world books rarely exceed a few hundred
 * pages; KB documents are typically &lt;200.
 */
const MAX_PAGES = 500;

/**
 * Distinguishable failure shapes surfaced to the caller. The caller mirrors
 * to Sentry with `extra.errorClass = <one of these>` so operators can read
 * the failure class directly off the event without parsing breadcrumbs, and
 * the runner picks an appropriate user-facing message in
 * `buildPdfUnreadableDirective`.
 */
export type PdfExtractErrorClass =
  | "oversized_buffer"
  | "lazy_import_failed"
  | "encrypted"
  | "corrupted"
  | "parse_error"
  | "empty_text"
  // 2026-05-06 follow-up to #3353: `readFile` failed in
  // `kb-document-resolver` BEFORE the buffer ever reached the extractor.
  // Surfaced through the same typed-error path so the runner picks
  // `buildPdfUnreadableDirective` instead of falling back to the gated
  // Read directive (which lands the agent in the sandbox-deny path that
  // produced the "outside my workspace boundary" reply in #3376).
  | "read_failed";

export interface PdfTextExtractResult {
  text: string;
  truncated: boolean;
  pageCount: number;
}

export interface PdfTextExtractError {
  error: PdfExtractErrorClass;
  /** Optional hint — populated for `empty_text` so operators see how many
   *  pages the parser saw before producing zero text (scanned PDF signal). */
  pageCount?: number;
}

/**
 * Extract text from a PDF buffer using the in-process `pdfjs-dist` parser.
 * On parse failure (corrupted, encrypted, oversized input, lazy-import
 * failure), returns `{ error: <class> }` instead of null — the caller drives
 * a content-grounded fallback prompt off the class so the model never falls
 * back to the apt-get / find Bash cascade.
 */
export async function extractPdfText(
  buffer: Buffer | Uint8Array,
  capChars: number,
): Promise<PdfTextExtractResult | PdfTextExtractError> {
  if (buffer.length > MAX_AGENT_READABLE_PDF_SIZE) {
    return { error: "oversized_buffer" };
  }

  // Lazy import — paid once per process (shared with `readPdfMetadata`).
  // Mirror to Sentry so a future runtime regression diagnoses itself
  // (e.g., a base-image refresh that drops Node below the engines.node
  // floor). `process.getBuiltinModule` was added in Node 22.3 / 20.16;
  // pdfjs-dist@5 calls it during module init.
  let pdfjs: typeof import("pdfjs-dist/legacy/build/pdf.mjs");
  try {
    pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  } catch (importErr) {
    reportSilentFallback(importErr, {
      feature: "kb-concierge-context",
      op: "extractPdfText.import",
      extra: {
        nodeVersion: process.versions.node,
        message: (importErr as Error)?.message ?? "",
      },
    });
    return { error: "lazy_import_failed" };
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
      // and we surface the class. The runner translates "encrypted" into a
      // content-grounded fallback prompt; the agent does NOT attempt to Read
      // the file (which would also fail for the same reason).
    }).promise;

    const pageCount = doc.numPages;
    // Independent cap: even if total text stays under capChars (e.g., empty
    // pages), the page-iteration loop has a cost per page (getPage +
    // getTextContent + cleanup). Bound it so attacker-declared numPages
    // can't pin the cold-Query event loop.
    const effectivePageLimit = Math.min(pageCount, MAX_PAGES);
    let text = "";
    let truncated = false;

    for (let pageNum = 1; pageNum <= effectivePageLimit; pageNum++) {
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

    // Surface the page-cap as a truncation signal so observability can
    // distinguish "huge book, body fit" from "page-cap kicked in".
    if (pageCount > effectivePageLimit) {
      truncated = true;
    }

    // Hypothesis B fold-in: a parsed-but-text-empty PDF (scanned image-only
    // document) is its own failure class. Returning success with
    // `text: ""` would let the resolver mirror nothing to Sentry and fall
    // through to a directive the agent can't satisfy. Promote to a typed
    // error so the caller picks the scanned-PDF user-facing message.
    if (text.length === 0) {
      return { error: "empty_text", pageCount };
    }

    return { text, truncated, pageCount };
  } catch (err) {
    // pdfjs's PasswordException / InvalidPDFException are NOT both re-exported
    // from the legacy entry (`pdfjs-dist/legacy/build/pdf.mjs`). InvalidPDFException
    // is in the export block; PasswordException is not. Both inherit from
    // BaseException which sets `this.name = "PasswordException"` /
    // `"InvalidPDFException"` in the constructor — so name-based dispatch is
    // the most portable check. instanceof `pdfjs.InvalidPDFException` would
    // also work for one of them; using `.name` for both keeps the branch
    // symmetric and survives any future re-export reshuffle.
    const name = (err as { name?: unknown } | null)?.name;
    if (name === "PasswordException") return { error: "encrypted" };
    if (name === "InvalidPDFException") return { error: "corrupted" };
    return { error: "parse_error" };
  } finally {
    if (doc) {
      await doc.destroy().catch(() => {});
    }
  }
}
