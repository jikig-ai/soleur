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
import { toPdfjsData } from "./pdfjs-input";

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

/**
 * Sentry feature-tag dictionary for both PDF resolvers. The Concierge
 * resolver passes the implicit default (or the explicit `CONCIERGE` tag);
 * the leader resolver passes the `LEADER` tag. Hoisted to a single shared
 * record so a future rename is one edit, not five.
 */
export const PDF_FEATURE_TAGS = {
  CONCIERGE: "kb-concierge-context",
  LEADER: "leader-context",
} as const;

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

// 2026-05-07 plan §Phase 2 (#3436) — outline coverage tunables.
// Walk-cost ceiling for `pdfjs.getDocument` + `getOutline` + per-entry
// `getDestination`/`getPageIndex`. 5s is loose enough for 500+ entries on
// real-world publisher TOCs (Manning/O'Reilly) while still bounding the
// resolver's hot-path cost.
export const OUTLINE_READ_TIMEOUT_MS = 5000;
// Below this entry count an outline is assumed to be "front-matter only"
// (cover / TOC / index entries from a scanned PDF) — fall through to the
// `too_many_pages` bridge instead of routing per-chapter.
export const MIN_OUTLINE_ENTRIES = 3;
// Outline coverage = (last entry's endPage - first entry's startPage + 1) /
// numPages. Below 0.8 we assume the outline only references front matter
// — the body of the book has no chapter anchors and per-chapter slicing
// would mis-route most user questions.
export const OUTLINE_PAGE_COVERAGE_MIN = 0.8;

export interface ChapterIndex {
  title: string;
  startPage: number;
  endPage: number;
  depth: number;
}

export type PdfOutlineReadResult =
  | { ok: true; outline: ChapterIndex[] }
  | {
      ok: false;
      reason: "no_outline" | "outline_too_shallow" | "timeout" | "parse_error";
    };

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
  options?: { featureTag?: string; startPage?: number; endPage?: number },
): Promise<PdfTextExtractResult | PdfTextExtractError> {
  // featureTag disambiguates Sentry mirrors between callers (Concierge vs
  // leader). Default preserves the legacy behavior so existing call sites
  // remain wire-compatible. The leader-document resolver passes
  // `featureTag: "leader-context"` so operators can filter leader-side
  // lazy-import failures from Concierge fires.
  const featureTag = options?.featureTag ?? PDF_FEATURE_TAGS.CONCIERGE;
  if (buffer.length > MAX_AGENT_READABLE_PDF_SIZE) {
    return { error: "oversized_buffer" };
  }
  // Validate page-range request shape BEFORE invoking pdfjs (#3436 §Phase 2).
  // `endPage <= numPages` is checked after pdfjs returns numPages; here we
  // only validate intra-arg consistency.
  const startPage = options?.startPage;
  const endPage = options?.endPage;
  if (startPage !== undefined || endPage !== undefined) {
    if (
      startPage === undefined ||
      endPage === undefined ||
      !Number.isInteger(startPage) ||
      !Number.isInteger(endPage) ||
      startPage < 1 ||
      endPage < startPage
    ) {
      return { error: "parse_error" };
    }
  }

  // Lazy import — paid once per process (shared with `readPdfMetadata`).
  // Mirror to Sentry so a future runtime regression diagnoses itself
  // (e.g., a base-image refresh that drops Node below the engines.node
  // floor). `process.getBuiltinModule` was added in Node 22.3 / 20.16;
  // pdfjs-dist@5 calls it during module init.
  let pdfjs: typeof import("pdfjs-dist/legacy/build/pdf.mjs");
  try {
    // If you add or rename a bare-specifier `await import()` here, mirror it
    // in the build-time `require.resolve` assertion in apps/web-platform/Dockerfile
    // (see #3422) — otherwise a missing dep silently routes through the catch
    // below and surfaces only as a WARN Sentry breadcrumb.
    pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  } catch (importErr) {
    reportSilentFallback(importErr, {
      feature: featureTag,
      op: "extractPdfText.import",
      extra: {
        nodeVersion: process.versions.node,
        message: (importErr as Error)?.message ?? "",
      },
    });
    return { error: "lazy_import_failed" };
  }

  // pdfjs-dist@5+ rejects Buffer; convert via the shared no-copy helper so
  // this and `kb-preview-metadata.ts` stay in lockstep.
  const data = toPdfjsData(buffer);

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
    // Validate page-range against the actual page count (#3436 §Phase 2).
    // `endPage > numPages` is treated as caller-side bug → parse_error
    // (existing class — no new union member per plan).
    if (endPage !== undefined && endPage > pageCount) {
      return { error: "parse_error" };
    }
    // Resolve the iteration window. Range-mode iterates [startPage, endPage]
    // (1-based, inclusive). Whole-doc mode preserves the legacy contract.
    const rangeStart = startPage ?? 1;
    const rangeEnd = endPage ?? pageCount;
    // Independent cap: even if total text stays under capChars (e.g., empty
    // pages), the page-iteration loop has a cost per page (getPage +
    // getTextContent + cleanup). Bound it so attacker-declared numPages
    // can't pin the cold-Query event loop. Range-mode applies the cap to
    // the slice width — a single-chapter request still gets MAX_PAGES of
    // headroom so a 500-page chapter (improbable but valid) is iterable.
    const requestedSpan = rangeEnd - rangeStart + 1;
    const effectiveSpan = Math.min(requestedSpan, MAX_PAGES);
    const effectivePageLimit = rangeStart + effectiveSpan - 1;
    let text = "";
    let truncated = false;
    // Range-mode `oversized_buffer` (#3436 §Phase 2): if the FIRST page in
    // the requested slice would already overflow capChars, the chapter is
    // genuinely too large for inline injection. Surface as oversized_buffer
    // so the runner can emit "I have the TOC but chapter X failed to extract"
    // (plan AC #7). Whole-doc mode keeps the legacy truncation behavior.
    const isRangeMode = startPage !== undefined && endPage !== undefined;

    for (let pageNum = rangeStart; pageNum <= effectivePageLimit; pageNum++) {
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
        const piece = pageNum === rangeStart ? pageText : "\n" + pageText;
        if (text.length + piece.length > capChars) {
          if (isRangeMode) {
            // Chapter slice would overflow — surface as oversized_buffer so
            // the runner can emit a chapter-specific failure prompt.
            return { error: "oversized_buffer" };
          }
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
    // distinguish "huge book, body fit" from "page-cap kicked in". In
    // range-mode the cap applies to the slice (rangeEnd vs effectivePageLimit).
    if (isRangeMode ? rangeEnd > effectivePageLimit : pageCount > effectivePageLimit) {
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

  // 3. Buffer → Uint8Array view (zero-copy) — shared helper from `pdfjs-input.ts`
  //    keeps `extractPdfText` and `extractPdfMetadata` byte-equivalent on the
  //    pdfjs-dist@5+ "Buffer is not Uint8Array" rejection.
  const data = toPdfjsData(buffer);

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

/**
 * Outline (TOC) walk for the chapter-chunking soft-route (#3436).
 *
 * The Concierge / leader resolvers call this AFTER `extractPdfMetadata`
 * confirms `numPages > LARGE_PDF_PAGE_THRESHOLD`. If the PDF carries a
 * publisher-grade outline (Manning/O'Reilly), we surface it as a
 * `ChapterIndex[]` so the runner can route per-question to a single
 * chapter instead of falling through to the bridge `too_many_pages`
 * directive (#3430).
 *
 * Heuristic gates (plan §Sharp Edges):
 * - `MIN_OUTLINE_ENTRIES = 3`: filters scanned-PDF "Cover / Index" stubs.
 * - `OUTLINE_PAGE_COVERAGE_MIN = 0.8`: filters front-matter-only outlines
 *   where chapters reference only the first 20% of the book.
 * - Whole-outline-fail on any unresolved `dest`: better to fall through
 *   to the bridge than to mis-bound a chapter and answer from the wrong
 *   pages.
 *
 * Top-level outline only — nested sub-chapters (`item.items`) are flattened
 * away. Routing-turn cost grows linearly with chapter count, and 3-30
 * top-level chapters is the sweet spot for Sonnet's per-turn token budget.
 *
 * Three independent safety bounds (mirrors `extractPdfMetadata`):
 *   1. Lazy import — surface as `parse_error` on failure.
 *   2. Timeout: `Promise.race` against `OUTLINE_READ_TIMEOUT_MS` (5s).
 *   3. Cancel-on-timeout: `loadingTask.destroy()` aborts the in-flight worker.
 *
 * Page indices are 1-based per plan TR1 (consistent with how
 * `LARGE_PDF_PAGE_THRESHOLD` is interpreted across the codebase).
 */
export async function extractPdfOutline(
  buffer: Buffer | Uint8Array,
): Promise<PdfOutlineReadResult> {
  // Re-use the metadata-read byte ceiling. Outline walk has a similar RSS
  // profile (xref + outline tree, no per-page text iteration).
  if (buffer.length > METADATA_READ_BYTE_CEILING_BYTES) {
    return { ok: false, reason: "parse_error" };
  }

  let pdfjs: typeof import("pdfjs-dist/legacy/build/pdf.mjs");
  try {
    pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  } catch {
    return { ok: false, reason: "parse_error" };
  }

  const data = toPdfjsData(buffer);
  const loadingTask = pdfjs.getDocument({ data, isEvalSupported: false });

  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<"__timeout__">((resolve) => {
    timer = setTimeout(() => resolve("__timeout__"), OUTLINE_READ_TIMEOUT_MS);
  });

  let doc:
    | Awaited<ReturnType<typeof pdfjs.getDocument>["promise"]>
    | null = null;
  try {
    const winner = await Promise.race([loadingTask.promise, timeout]);
    if (winner === "__timeout__") {
      void loadingTask.destroy().catch(() => {});
      return { ok: false, reason: "timeout" };
    }
    doc = winner;
    const numPages = doc.numPages;

    // pdfjs returns `null` when the PDF has no /Outlines tree.
    type OutlineItem = {
      title: string;
      dest?: unknown;
      items?: OutlineItem[];
    };
    const rawOutline = (await doc.getOutline()) as OutlineItem[] | null;
    if (!rawOutline || rawOutline.length === 0) {
      return { ok: false, reason: "no_outline" };
    }

    // Resolve the start page for each top-level entry. `dest` may be:
    //   - a string: named destination → getDestination(name) → [ref, view]
    //   - an array: explicit destination → first element is a page ref
    //   - null/missing: skip (whole-outline-fail signal)
    async function resolveStartPage0(dest: unknown): Promise<number | null> {
      if (!dest) return null;
      let resolved: unknown = dest;
      if (typeof dest === "string") {
        try {
          resolved = await doc!.getDestination(dest);
        } catch {
          return null;
        }
        if (!resolved) return null;
      }
      if (!Array.isArray(resolved) || resolved.length === 0) return null;
      const ref = resolved[0];
      if (ref === null || ref === undefined) return null;
      try {
        const idx = await doc!.getPageIndex(ref);
        if (typeof idx !== "number" || idx < 0) return null;
        return idx; // 0-based
      } catch {
        return null;
      }
    }

    const starts: Array<{ title: string; startPage0: number; depth: number }> = [];
    for (const item of rawOutline) {
      const startPage0 = await resolveStartPage0(item.dest);
      if (startPage0 === null) {
        // Plan: any unresolved dest → treat WHOLE outline as unusable.
        return { ok: false, reason: "outline_too_shallow" };
      }
      starts.push({
        title: typeof item.title === "string" ? item.title : "",
        startPage0,
        depth: 0,
      });
    }

    if (starts.length < MIN_OUTLINE_ENTRIES) {
      return { ok: false, reason: "outline_too_shallow" };
    }

    // Sort by start page (defensive — well-formed PDFs already arrive
    // sorted, but trust the bytes only as far as we can verify them).
    starts.sort((a, b) => a.startPage0 - b.startPage0);

    // Build endPage from the next entry's startPage; last entry ends at
    // numPages. ChapterIndex page indices are 1-based.
    const outline: ChapterIndex[] = starts.map((entry, i) => {
      const next = starts[i + 1];
      const endPage = next ? next.startPage0 : numPages;
      return {
        title: entry.title,
        startPage: entry.startPage0 + 1,
        endPage,
        depth: entry.depth,
      };
    });

    // Coverage check: if the outline only references the front matter of
    // the book (cover / preface / TOC / first few sample chapters), per-
    // chapter routing would mis-route most user questions to the synthetic
    // last chapter that extends to numPages. The signal is "where does the
    // deepest top-level entry START?" — measured as a fraction of total
    // pages. A publisher-grade Manning/O'Reilly outline has its last top-
    // level chapter start ≥ 80% into the book; a scanned PDF whose only
    // outline entries are front-matter has its last entry within the first
    // 20%. Fall through to the bridge below the threshold.
    const lastStart = outline[outline.length - 1].startPage;
    const coverage = lastStart / numPages;
    if (coverage < OUTLINE_PAGE_COVERAGE_MIN) {
      return { ok: false, reason: "outline_too_shallow" };
    }

    return { ok: true, outline };
  } catch {
    void loadingTask.destroy().catch(() => {});
    return { ok: false, reason: "parse_error" };
  } finally {
    if (timer !== undefined) clearTimeout(timer);
    if (doc) {
      await doc.destroy().catch(() => {});
    }
  }
}
