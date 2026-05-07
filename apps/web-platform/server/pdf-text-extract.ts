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
  | "read_failed"
  // 2026-05-07 follow-up to #3429: bridge fix for the large-PDF
  // soft-route timeout. When `oversized_buffer` fires (>24MB) AND the
  // resolver's metadata-only pdfjs read reports `numPages >
  // LARGE_PDF_PAGE_THRESHOLD`, surface this HARD class so the runner
  // routes to `buildPdfTooLongDirective` instead of `buildPdfGatedDirective`.
  // Avoids the ~21-call SDK Read fanout that exceeds the 90s idle-reaper
  // window on 400+ page PDFs.
  | "too_many_pages";

// Threshold derivation (#3429): floor(90s reaper / ~10s per Read call) *
// 20 pages-per-call - safety margin = 160 pages → 150 for headroom.
// Single exported constant — trivially adjustable downward if real-world
// per-Read latency proves higher (post-merge calibration via Sentry
// breadcrumbs). Reversible via one-line edit; no architectural commitment.
export const LARGE_PDF_PAGE_THRESHOLD = 150;

// Upper bound at which we'll attempt a metadata-only pdfjs read (#3429).
// DISTINCT from MAX_AGENT_READABLE_PDF_SIZE (24MB extractor cap) —
// metadata-only reads have a different RSS profile (xref + numPages, no
// per-page text iteration). 40 MiB bounds RSS for a malformed PDF
// (pdfjs can spike ~3-5x the buffer size during xref-build per the
// 2026-04-18 learning) while leaving headroom over the 24MB extractor
// cap so a Manning-shaped PDF (15-30MB) is in scope. Above this ceiling
// we fail closed — the resolver falls through to the existing soft-route.
//
// Sized down from the originally-proposed 60 MiB per perf-oracle review
// of PR #3430: a 60 MiB malformed PDF could allocate >300 MB RSS during
// xref-build, partially defeating the bound; 40 MiB caps the worst-case
// RSS spike at ~200 MB while preserving the Manning use case.
//
// Bit-shift form (`40 << 20`) by design — the `kb-pdf-cap-alignment`
// drift guard forbids `<n> * 1024 * 1024` shadow constants in this file
// to prevent re-introducing a competing extractor cap; the metadata
// ceiling is a SEPARATE concern (different lifecycle, different RSS
// profile) so we use the equivalent `40 << 20 = 41_943_040` shape.
export const METADATA_READ_BYTE_CEILING_BYTES = 40 << 20;

// `Promise.race` timeout on the pdfjs metadata-only `getDocument` call
// (#3429). 3s caps the wall-clock cost in the resolver's hot path. On
// timeout we call `loadingTask.destroy()` (per pdfjs-dist@5.4.296
// `types/src/display/api.d.ts:872`: "Abort all network requests and
// destroy the worker") and return the timeout shape; the resolver
// fail-closes to existing soft-route behavior.
export const METADATA_READ_TIMEOUT_MS = 3000;

export type PdfMetadataReadResult =
  | { ok: true; numPages: number }
  | { ok: false; reason: "oversized" | "timeout" | "parse_error" };

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

/**
 * Metadata-only pdfjs read for the page-count gate (#3429).
 *
 * The resolver invokes this when `extractPdfText` raised `oversized_buffer`
 * (>24MB) to obtain `numPages` cheaply WITHOUT paying the per-page text
 * iteration cost. Wrapped in three independent safety bounds:
 *
 *   1. Byte ceiling: refuse buffers >60MB BEFORE invoking pdfjs (bounds RSS).
 *   2. Timeout: `Promise.race` against `METADATA_READ_TIMEOUT_MS` (3s).
 *   3. Cancel-on-timeout: `loadingTask.destroy()` aborts the in-flight
 *      worker per pdfjs-dist@5.4.296 `types/src/display/api.d.ts:872`.
 *
 * The function never throws — every error path returns the typed
 * `PdfMetadataReadResult` failure shape so the resolver can drive
 * fail-closed routing without a try/catch at the call site.
 */
export async function extractPdfMetadata(
  buffer: Buffer | Uint8Array,
): Promise<PdfMetadataReadResult> {
  // 1. Pre-pdfjs byte ceiling. Bounds RSS without invoking the parser.
  if (buffer.length > METADATA_READ_BYTE_CEILING_BYTES) {
    return { ok: false, reason: "oversized" };
  }

  // 2. Lazy import — paid once per process (shared with `extractPdfText`).
  let pdfjs: typeof import("pdfjs-dist/legacy/build/pdf.mjs");
  try {
    pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  } catch {
    // Lazy_import_failed is dominated by Node-engine drift and bounded
    // by the repo's three-layer enforcement (engines + .nvmrc + CI). We
    // surface as `parse_error` here because the gate's behavior is
    // identical (fail-closed to existing soft-route routing) and there
    // is no caller-actionable distinction.
    return { ok: false, reason: "parse_error" };
  }

  // 3. Buffer → Uint8Array view (zero-copy) — pdfjs-dist@5.4.296 rejects
  //    Node Buffer (`instanceof Buffer === false` check). Authoritative
  //    pattern from `extractPdfText` above.
  const isNodeBuffer =
    typeof Buffer !== "undefined" && Buffer.isBuffer(buffer);
  const data = isNodeBuffer
    ? new Uint8Array(
        (buffer as Buffer).buffer,
        (buffer as Buffer).byteOffset,
        (buffer as Buffer).byteLength,
      )
    : (buffer as Uint8Array);

  // 4. Race the loadingTask.promise against a timeout. On timeout we call
  //    `loadingTask.destroy()` (the synchronous handle owns the cancel API
  //    — `doc` may not have resolved yet).
  const loadingTask = pdfjs.getDocument({ data, isEvalSupported: false });

  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<"__timeout__">((resolve) => {
    timer = setTimeout(() => resolve("__timeout__"), METADATA_READ_TIMEOUT_MS);
  });

  try {
    const winner = await Promise.race([loadingTask.promise, timeout]);
    if (winner === "__timeout__") {
      // Cancel the in-flight task — releases the worker + xref allocation.
      // Fire-and-forget; the resolver has already decided to fail-closed.
      void loadingTask.destroy().catch(() => {});
      return { ok: false, reason: "timeout" };
    }
    // winner is the resolved doc. numPages is synchronous on the doc.
    const doc = winner;
    const numPages = doc.numPages;
    void doc.destroy().catch(() => {});
    return { ok: true, numPages };
  } catch {
    // getDocument rejection (corrupted, encrypted, malformed). The doc
    // never resolved so loadingTask.destroy() is the cleanup path.
    void loadingTask.destroy().catch(() => {});
    return { ok: false, reason: "parse_error" };
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
