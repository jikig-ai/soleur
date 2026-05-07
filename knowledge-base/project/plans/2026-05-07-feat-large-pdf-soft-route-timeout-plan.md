---
title: Page-Count Gate on Concierge PDF Soft-Route
issue: "#3429"
spec: knowledge-base/project/specs/feat-large-pdf-soft-route-timeout/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-07-large-pdf-soft-route-timeout-brainstorm.md
branch: feat-large-pdf-soft-route-timeout
worktree: .worktrees/feat-large-pdf-soft-route-timeout/
pr: "#3430"
date: 2026-05-07
type: feat
classification: bridge-fix
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
follow_ups: ["#3436", "#3437"]
---

# Plan: Page-Count Gate on Concierge PDF Soft-Route (Bridge Fix for Issue #3429)

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** Research Reconciliation, TR1 (extractPdfMetadata body), Sharp Edges, Acceptance Criteria
**Verification artifacts collected:**

- `apps/web-platform/node_modules/pdfjs-dist/types/src/display/api.d.ts` — confirmed `getDocument()` returns `PDFDocumentLoadingTask` with `destroy(): Promise<void>` (line 824/872) — corrects the original Sharp Edge that claimed "no AbortController surface". The cancel pattern is `loadingTask.destroy()`.
- `apps/web-platform/server/kb-preview-metadata.ts:75-104` — sibling metadata-only-read precedent. Validates the import + `isEvalSupported: false` + `doc.destroy()-in-finally` pattern.
- `apps/web-platform/server/pdf-text-extract.ts:120-132` — Buffer→Uint8Array wrap is the authoritative pattern (cites the exact rejection error). Reused verbatim in `extractPdfMetadata`.
- `apps/web-platform/test/pdf-text-extract.test.ts:25-100` — `makeMinimalPdf(pageTexts)` synthesis pattern. Reused for the `numPages: 200` test fixture.
- `apps/web-platform/test/read-tool-pdf-capability.test.ts:9-10, 302-333` — partition-mirror test pattern. Confirms adding `"too_many_pages"` to `PDF_HARD_FAILURE_LITERALS` automatically extends iteration; targeted assertion still required for HARD-membership directive shape.
- `gh issue view 3429/3436/3437 --json state` — all three OPEN, titles match plan claims.
- `gh issue list --label code-review --state open` — 70 open issues; 4 touch the planned files (#3438 fold-in, #3343 / #3369 / #2955 acknowledged).

### Key Improvements over the spec

1. **Cancel-on-timeout fixed.** Original Sharp Edge claimed pdfjs has no cancel surface; type-defs prove `loadingTask.destroy()` is the right cancel API. `extractPdfMetadata` now uses `Promise.race([loadingTask.promise, timeout])` and `loadingTask.destroy()` on timeout — RSS leak window collapses to the time pdfjs needs to honor `destroy()`.
2. **Reconciliation table added.** Spec's TR2 second trigger ("text > 50KB inline cap") is dead under current code (`extractPdfText` truncates at the cap). Plan drops the second trigger and gates only on `oversized_buffer`. Two other reconciliation rows (24MB extractor cap, 60MB metadata ceiling justification).
3. **Folded in #3438** (lazy_import_failed direct test) — natural sibling of the new `extractPdfMetadata` tests in the same file.
4. **Concrete `extractPdfMetadata` body** with the cancel-on-timeout pattern is now in the plan, not deferred to /work.

### New Considerations Discovered

- pdfjs-dist 5.4.296 has `PDFDocumentLoadingTask.destroy()` for cancel — use it on timeout instead of leaking the in-flight promise.
- `numPages` access on the resolved doc is synchronous (not awaited) — no second `await` is needed inside the `Promise.race` winner branch.
- Test mock pattern: `vi.mock("pdfjs-dist/legacy/build/pdf.mjs", () => ({ getDocument: vi.fn(...) }))` is the supported shape per existing test scaffolding (no current uses in `pdf-text-extract.test.ts` — would be the first mock in the file; `kb-share` tests use the same module-mock pattern).

## Overview

After PR #3405 partitioned `PdfExtractErrorClass` into soft-failure (route to `buildPdfGatedDirective`) vs hard-failure (route to `buildPdfUnreadableDirective`), 400+ page PDFs that hit `oversized_buffer` (>24MB extractor cap) route to soft → gated `Read`. The Concierge agent then issues ~21 sequential `Read({pages: "1-20"})` calls. Each call materializes a base64 PDF chunk + model ingestion (many seconds each). The 90-second `DEFAULT_WALL_CLOCK_TRIGGER_MS` idle-reaper in `soleur-go-runner.ts` fires before the chain finishes, surfacing `"Agent stopped responding"` to the user.

This plan implements the **bridge fix**: a page-count-aware gate on the Concierge PDF soft-failure route. When the resolver detects a PDF that has hit `oversized_buffer`, it does a metadata-only pdfjs read (with a 60MB byte ceiling and 3s `Promise.race` timeout) to obtain `numPages`. PDFs with `numPages > 150` route to a new `too_many_pages` HARD class with a specific, actionable refusal directive ("I see {N} pages — that's too long for me to read in one go. Share a chapter, or paste the table of contents…"). PDFs at or under the threshold continue to route via the existing soft-failure path (recovery preserved on small-page-count + large-byte-size PDFs).

The durable destination — Anthropic Files API pre-upload that eliminates the Read fanout structurally — is filed as #3436 with its own architecture cycle. Leader-path symmetry (`agent-runner.ts`) is filed as #3437. Both deferrals are tracked.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| TR2: "extraction succeeds but text exceeds the 50KB inline cap" → call `extractPdfMetadata` | `extractPdfText(buffer, CONCIERGE_INLINE_CAP_BYTES)` truncates output text at 50KB and returns `{ truncated: true, ... }` (success). The resolver inlines the truncated body via `documentContent`. There is no current code path where the extractor returns text >50KB and reaches the soft-route. | **Drop the second trigger.** Page count, not text length, is the right signal — and a truncated 50KB inline body usually fits the Concierge in one turn (the cascade fires only on `oversized_buffer`). FR1 / TR2 are amended in §"Functional Requirements (Amended)" to gate ONLY on `oversized_buffer`. If a future change makes >50KB success bodies surface upstream, the gate can be extended without partition churn. |
| TR1: `INPUT_BUFFER_CAP_BYTES = 15 MB` (referenced in brainstorm) | Extractor cap is `MAX_AGENT_READABLE_PDF_SIZE` from `@/lib/attachment-constants` (24MB after #3337/#3338). Brainstorm prose says ">15MB" but the actual cap is 24MB. | Plan uses 24MB consistently. Empirical reproduction (Manning 403-page book) is described as ">15MB" in the issue body; the actual buffer at `oversized_buffer` time exceeds 24MB. |
| TR1: `METADATA_READ_BYTE_CEILING_BYTES = 60MB` | No precedent at 60MB — current codebase pdfjs ceilings are 15MB (extractor) and 24MB (upload + extractor post-#3337). 60MB is a new ceiling. | **Keep 60MB** — the metadata-only call has a different RSS profile (xref + numPages, no full text iteration). 60MB still leaves plenty of headroom over the 24MB extractor cap so that a Manning-shaped PDF (15-30MB) is in scope. Document the constant as "not the same as the extractor cap" inline. |
| Soft/Hard partition has compile-time rail | Confirmed: `PDF_SOFT_FAILURE_LITERALS` + `PDF_HARD_FAILURE_LITERALS` + `_AssertPartitionTotal` rail in `soleur-go-runner.ts:282-317`. Test mirror in `read-tool-pdf-capability.test.ts:302-333`. | New class `too_many_pages` MUST be added to `PDF_HARD_FAILURE_LITERALS` AND the test mirror import. |
| pdfjs-dist version 5.4.296 (already imported via legacy entry) | Confirmed installed; `apps/web-platform/server/pdf-text-extract.ts` imports `pdfjs-dist/legacy/build/pdf.mjs`. | TR5 satisfied — no new dep. |
| Leader path (`agent-runner.ts:842-858`) symmetry deferred | Confirmed: leader directly calls `buildPdfGatedDirective(safeContextPath, safeFullPath, CONTEXT_NO_ASK)` with no extractor and no `documentExtractError` plumbing. Same bug applies but a separate, larger refactor. | Defer to #3437 per NG2. |

## Files to Edit

- `apps/web-platform/server/pdf-text-extract.ts` (extend exports + add `extractPdfMetadata`)
- `apps/web-platform/server/kb-document-resolver.ts` (PDF branch — call `extractPdfMetadata` on `oversized_buffer`)
- `apps/web-platform/server/soleur-go-runner.ts` (partition update + new `buildPdfTooLongDirective` factory + routing)
- `apps/web-platform/test/pdf-text-extract.test.ts` (extend with `extractPdfMetadata` cases AND fold-in #3438 — see "Open Code-Review Overlap")
- `apps/web-platform/test/pdf-unreadable-directive.test.ts` (add `buildPdfTooLongDirective` cases)
- `apps/web-platform/test/read-tool-pdf-capability.test.ts` (extend partition mirror with `too_many_pages` in HARD)
- `apps/web-platform/test/cc-concierge-pdf-summarize-e2e.test.ts` (add many-pages PDF case asserting new directive lead)

## Files to Create

- `apps/web-platform/test/kb-document-resolver-pdf-page-gate.test.ts` (resolver-level test for the gate; new file because the existing resolver test surface is in `cc-concierge-pdf-summarize-e2e.test.ts` at the integration tier and the unit shape is distinct enough to warrant its own file)

## Open Code-Review Overlap

4 open scope-outs touch these files:

- **#3438 — review: add direct lazy_import_failed test for extractPdfText (PR #3431)** — touches `pdf-text-extract.ts` AND `pdf-text-extract.test.ts`. **Fold in.** This plan extends `pdf-text-extract.test.ts` with the new `extractPdfMetadata` tests; adding the missing direct `lazy_import_failed` case in the same file is a natural sibling. PR body MUST include `Closes #3438`.
- **#3343 — review: case-insensitive `</document>` escape across cc + leader prompt builders** — touches `soleur-go-runner.ts`. **Acknowledge.** Different concern (security hardening of the escape regex, applies to both the Concierge and leader prompt builders). Folding in would expand the diff into prompt-builder territory unrelated to the page-count gate. Leave open for its own cycle.
- **#3369 — review: Extract mirrorWithDebounce from cc-dispatcher to observability (PR #3353 follow-up)** — touches `kb-document-resolver.ts`. **Acknowledge.** Different concern (observability refactor). Folding in would mix architectural refactor with bug-fix scope. Leave open.
- **#2955 — arch: process-local state assumption needs ADR + startup guard** — touches `soleur-go-runner.ts`. **Acknowledge.** Strategic ADR concern, much larger scope. Leave open for its own architecture-track cycle.

## User-Brand Impact

**If this lands broken, the user experiences:** Either (a) a regression on the small-page-count case (60-page image-heavy PDF refuses where it used to recover via gated Read fanout), OR (b) the existing silent timeout continues to fire — Concierge looks unreliable on the very flagship-shaped use case (founder uploads a Manning book and asks for a summary).

**If this leaks, the user's data is exposed via:** No new exposure vector — the metadata-only read uses the already-isolated pdfjs-dist parser; the new directive copy contains only the page count (already known to the user). RSS spike on a malformed PDF is the only new resource-side risk and is bounded by the 60MB pre-pdfjs cap and 3s `Promise.race` timeout.

**Brand-survival threshold:** `single-user incident` — one founder reproducing this on a Manning book is enough to break the Concierge brand promise. The bridge fix MUST (a) not silently misfire, (b) not regress small-PDF success, (c) provide a clear next step in the refusal copy. Per `hr-weigh-every-decision-against-target-user-impact`, `requires_cpo_signoff: true` is set in the YAML frontmatter and `user-impact-reviewer` will be invoked at review time per `plugins/soleur/skills/review/SKILL.md`.

## Functional Requirements (Amended from Spec)

- **FR1 (amended).** When the resolver's `extractPdfText` call returns `{ error: "oversized_buffer" }`, the resolver MUST attempt a metadata-only pdfjs read on the same buffer to obtain `numPages` BEFORE setting `documentExtractError`.
- **FR2.** If the metadata read returns `{ ok: true, numPages }` with `numPages > LARGE_PDF_PAGE_THRESHOLD` (initial value 150), the resolver MUST surface `documentExtractError: "too_many_pages"` and pass `numPages` through a new `documentExtractMeta` channel (typed structured object — see TR2 below).
- **FR3.** The runner MUST partition `too_many_pages` into the HARD set, routing to a new `buildPdfTooLongDirective(artifactPath, numPages, NO_ASK)` factory.
- **FR4.** The directive copy MUST follow this exact form (test surface):
  > `"I see {N} pages — that's too long for me to read in one go. Share a chapter, or paste the table of contents and I'll point you at the right section."`
- **FR5.** PDFs with `numPages ≤ LARGE_PDF_PAGE_THRESHOLD` MUST continue to route via the existing soft-failure path (`buildPdfGatedDirective`).
- **FR6.** If the metadata read errors (timeout, parse failure, oversized buffer beyond the metadata ceiling) the resolver MUST fall through to the existing soft-failure routing — fail closed.
- **FR7.** A Sentry breadcrumb MUST be emitted on every metadata-read attempt (`category: "cc-pdf-extractor"`, `data: { ok, op: "metadataRead", numPages?, reason?, pathBasename }`). Existing breadcrumb shape is preserved (additive `op` field).

## Technical Requirements

### TR1 — `pdf-text-extract.ts` (extend)

Add the following exports:

```ts
// Threshold: floor(90s reaper / ~10s per Read call) * 20 pages/call - safety
// margin = 160 → 150 for headroom. Single exported constant; trivially
// reversible if real-world per-Read latency proves higher.
export const LARGE_PDF_PAGE_THRESHOLD = 150;

// Upper bound at which we'll attempt a metadata-only pdfjs read. Distinct
// from MAX_AGENT_READABLE_PDF_SIZE (24MB extractor cap) — metadata-only
// reads have a different RSS profile (xref + numPages, no per-page text
// iteration). 60MB still bounds RSS for a malformed PDF while leaving
// headroom over 24MB so a Manning-shaped PDF (15-30MB) is in scope.
export const METADATA_READ_BYTE_CEILING_BYTES = 60 * 1024 * 1024;

// `Promise.race` timeout on the pdfjs metadata-only call.
export const METADATA_READ_TIMEOUT_MS = 3000;

export type PdfMetadataReadResult =
  | { ok: true; numPages: number }
  | { ok: false; reason: "oversized" | "timeout" | "parse_error" };

export async function extractPdfMetadata(
  buffer: Buffer | Uint8Array,
): Promise<PdfMetadataReadResult>;
```

`extractPdfMetadata` body — concrete implementation pattern:

```ts
export async function extractPdfMetadata(
  buffer: Buffer | Uint8Array,
): Promise<PdfMetadataReadResult> {
  // 1. Pre-pdfjs byte ceiling — bound RSS without invoking the parser.
  if (buffer.length > METADATA_READ_BYTE_CEILING_BYTES) {
    return { ok: false, reason: "oversized" };
  }

  // 2. Lazy-import (paid once per process; shared with extractPdfText).
  let pdfjs: typeof import("pdfjs-dist/legacy/build/pdf.mjs");
  try {
    pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  } catch {
    // Lazy_import_failed is dominated by Node-engine drift; bounded by
    // three-layer enforcement (PR #3383). Surface as parse_error here —
    // we don't have a separate union member and the gate's behavior is
    // identical (fail-closed to existing soft-route).
    return { ok: false, reason: "parse_error" };
  }

  // 3. Buffer → Uint8Array view (zero-copy) — pdfjs-dist@5.4.296 rejects
  //    Buffer via `instanceof Buffer === false`. Authoritative pattern from
  //    pdf-text-extract.ts:120-132.
  const isNodeBuffer =
    typeof Buffer !== "undefined" && Buffer.isBuffer(buffer);
  const data = isNodeBuffer
    ? new Uint8Array(
        (buffer as Buffer).buffer,
        (buffer as Buffer).byteOffset,
        (buffer as Buffer).byteLength,
      )
    : (buffer as Uint8Array);

  // 4. Race the loadingTask.promise against a timeout. pdfjs-dist 5.4.296
  //    `getDocument()` returns PDFDocumentLoadingTask with destroy(): Promise<void>
  //    ("Abort all network requests and destroy the worker" — types/src/display/api.d.ts:872).
  //    On timeout we call loadingTask.destroy() to abort the in-flight task.
  const loadingTask = pdfjs.getDocument({ data, isEvalSupported: false });

  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<"__timeout__">((resolve) => {
    timer = setTimeout(() => resolve("__timeout__"), METADATA_READ_TIMEOUT_MS);
  });

  try {
    const winner = await Promise.race([loadingTask.promise, timeout]);
    if (winner === "__timeout__") {
      // Cancel the in-flight task — releases the worker + xref allocation.
      // Fire-and-forget; destroy() returns a Promise we don't await (we've
      // already decided to fail-closed).
      void loadingTask.destroy().catch(() => {});
      return { ok: false, reason: "timeout" };
    }
    // winner is the resolved doc. numPages is synchronous on the doc.
    const doc = winner;
    const numPages = doc.numPages;
    void doc.destroy().catch(() => {});
    return { ok: true, numPages };
  } catch {
    // getDocument() rejection (corrupted, encrypted, malformed). The doc
    // never resolved so loadingTask.destroy() is the cleanup path.
    void loadingTask.destroy().catch(() => {});
    return { ok: false, reason: "parse_error" };
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
```

Add `"too_many_pages"` to the `PdfExtractErrorClass` union (declaration only — runtime-side handled by TR3).

**Why `loadingTask.destroy()` not `doc.destroy()` on timeout:** the `doc` doesn't exist yet at timeout (the promise hasn't resolved). The `PDFDocumentLoadingTask` is the long-lived handle returned synchronously by `getDocument()` and owns the abort capability per the type def docstring.

### TR2 — `kb-document-resolver.ts` (PDF branch gate)

Where `extractPdfText` returns `{ error: "oversized_buffer" }` (line 166-206 in the current file), insert the gate:

```ts
if (result.error === "oversized_buffer") {
  const meta = await extractPdfMetadata(buffer);
  Sentry.addBreadcrumb({
    category: "cc-pdf-extractor",
    message: "extractPdfMetadata completed",
    level: "info",
    data: {
      ok: meta.ok,
      op: "metadataRead",
      numPages: meta.ok ? meta.numPages : null,
      reason: meta.ok ? null : meta.reason,
      pathBasename: path.basename(contextPath),
    },
  });
  if (meta.ok && meta.numPages > LARGE_PDF_PAGE_THRESHOLD) {
    return {
      artifactPath: contextPath,
      documentKind: "pdf",
      documentExtractError: "too_many_pages",
      documentExtractMeta: { numPages: meta.numPages },
    };
  }
  // meta.ok && numPages <= threshold → fall through to existing soft-route
  // meta.ok === false → fail-closed to existing soft-route
  // (mirror result.error to Sentry as today; existing breadcrumb already
  //  emitted at the parent scope.)
}
```

Wire `documentExtractMeta` through the resolver's return type and through `DispatchArgs` in `soleur-go-runner.ts` (typed channel — see TR3).

### TR3 — `soleur-go-runner.ts` (partition + factory + routing)

1. Add `"too_many_pages"` to `PDF_HARD_FAILURE_LITERALS` (line 289-292):

   ```ts
   export const PDF_HARD_FAILURE_LITERALS = [
     "encrypted",
     "empty_text",
     "too_many_pages",
   ] as const satisfies readonly PdfExtractErrorClass[];
   ```

   The `_AssertPartitionTotal` rail at line 312-317 picks this up automatically (driven off the literal arrays).

2. Add `buildPdfTooLongDirective` factory in the prompt-builder block (sibling to `buildPdfGatedDirective` / `buildPdfUnreadableDirective`):

   ```ts
   export function buildPdfTooLongDirective(
     artifactPath: string,
     numPages: number,
     noAsk: string,
   ): string {
     // Bound numPages display: clamp to a non-negative integer, sanity cap
     // at 99999 to keep the prompt bytes bounded against an attacker-shaped
     // numPages from a malformed PDF.
     const safeN = Math.max(0, Math.min(Math.floor(Number(numPages) || 0), 99999));
     return `The user is currently viewing: ${artifactPath}\n\nI see ${safeN} pages — that's too long for me to read in one go. Share a chapter, or paste the table of contents and I'll point you at the right section. ${noAsk}`;
   }
   ```

3. Wire `documentExtractMeta` through `DispatchArgs` and `BuildSoleurGoSystemPromptArgs`. Type:

   ```ts
   export interface DocumentExtractMeta {
     numPages?: number;
   }
   // DispatchArgs:
   documentExtractMeta?: DocumentExtractMeta;
   // BuildSoleurGoSystemPromptArgs:
   documentExtractMeta?: DocumentExtractMeta;
   ```

4. In `buildSoleurGoSystemPrompt` PDF branch (around line 887-913), when `documentExtractError === "too_many_pages"`, route to `buildPdfTooLongDirective`:

   ```ts
   if (args.documentExtractError) {
     const safeErrorClass = sanitizePromptString(args.documentExtractError);
     if (isPdfSoftFailure(safeErrorClass)) {
       artifactDirective = buildPdfGatedDirective(safeArtifactPath, absoluteReadPath, NO_ASK);
     } else if (safeErrorClass === "too_many_pages") {
       const safeNumPages = args.documentExtractMeta?.numPages ?? 0;
       artifactDirective = buildPdfTooLongDirective(safeArtifactPath, safeNumPages, NO_ASK);
     } else {
       artifactDirective = buildPdfUnreadableDirective(safeArtifactPath, NO_ASK, safeErrorClass);
     }
   } else if (...) // existing inline-or-fallback path unchanged
   ```

   Branch order matters: `isPdfSoftFailure` returns false for `"too_many_pages"` (it's HARD) so the `else if` is reachable; the `else` continues to default to `buildPdfUnreadableDirective` for any other HARD class.

### TR4 — Tests (RED-first)

- **`pdf-text-extract.test.ts`** (extend; folds in #3438):
  - `describe("extractPdfMetadata")`:
    - `it("returns { ok: false, reason: 'oversized' } when buffer exceeds METADATA_READ_BYTE_CEILING_BYTES")` — synthesize a 65MB buffer (header + zero-padded body); assert no pdfjs invocation occurred (cheapest: assert wall-clock <50ms).
    - `it("returns { ok: true, numPages } for a valid 3-page PDF")` — reuse `makePdfBuffer({ pages: ["p1", "p2", "p3"] })`; assert `numPages === 3`.
    - `it("returns { ok: false, reason: 'parse_error' } on a buffer with no PDF header")` — garbage buffer.
    - `it("returns { ok: false, reason: 'timeout' } when getDocument exceeds METADATA_READ_TIMEOUT_MS")` — use `vi.useFakeTimers()` + `vi.advanceTimersByTimeAsync(METADATA_READ_TIMEOUT_MS + 100)` so the test does NOT pay 3s wall-clock per run. Mock `pdfjs.getDocument` to return a `PDFDocumentLoadingTask`-shaped object with a never-resolving `promise` and a `destroy: vi.fn(() => Promise.resolve())` so the test can also assert `destroy` was called once after the timeout fired.
  - `describe("extractPdfText lazy_import_failed")` (folds in #3438):
    - `it("returns { error: 'lazy_import_failed' } when the dynamic import throws")` — mock `import("pdfjs-dist/legacy/build/pdf.mjs")` to reject; assert error class. Use `vi.mock("pdfjs-dist/legacy/build/pdf.mjs", () => { throw new Error("synthetic-import-failure"); })` at module top — module-mocks are hoisted and run before the lazy import inside `extractPdfText`. (No prior `vi.mock` use in this test file; this would be the first.)

- **`pdf-unreadable-directive.test.ts`** (extend):
  - `describe("buildPdfTooLongDirective")`:
    - `it("produces FR4 exact copy with the page count interpolated")` — assert exact string match including the page count.
    - `it("clamps a negative or NaN numPages to 0")` — assert no crash and clamp behavior.
    - `it("expectNoCascade still holds")` — assert no `pdftotext` / `apt-get` / `pdfplumber` substrings present.

- **`read-tool-pdf-capability.test.ts`** (extend partition mirror):
  - The existing partition test (line 315-333) iterates over `PDF_SOFT_FAILURE_LITERALS` and `PDF_HARD_FAILURE_LITERALS`. Adding `"too_many_pages"` to `PDF_HARD_FAILURE_LITERALS` automatically extends the iteration. Add a targeted assertion:
    - `it("'too_many_pages' is HARD (routes to buildPdfTooLongDirective, NOT buildPdfGatedDirective)")` — assert `isPdfSoftFailure("too_many_pages") === false` AND that buildSoleurGoSystemPrompt with `documentExtractError: "too_many_pages"` produces output containing the FR4 lead string and NOT containing `PDF_GATED_DIRECTIVE_LEAD`.

- **`kb-document-resolver-pdf-page-gate.test.ts`** (new):
  - `describe("kb-document-resolver PDF page-count gate")`:
    - `it("surfaces too_many_pages when oversized_buffer + numPages > 150")` — mock `extractPdfText → { error: "oversized_buffer" }` and `extractPdfMetadata → { ok: true, numPages: 200 }`; assert resolver returns `documentExtractError: "too_many_pages"` and `documentExtractMeta.numPages === 200`.
    - `it("falls through to oversized_buffer (soft) when numPages = 50")` — same mocks, `numPages: 50`; assert returns `documentExtractError: "oversized_buffer"`.
    - `it("fails closed to oversized_buffer when metadata read returns { ok: false, reason: 'oversized' }")` — synthesize an 80MB buffer; assert returns `documentExtractError: "oversized_buffer"`.
    - `it("fails closed to oversized_buffer on metadata-read timeout")` — mock metadata to resolve with `{ ok: false, reason: "timeout" }`; assert resolver returns `documentExtractError: "oversized_buffer"`.

- **`cc-concierge-pdf-summarize-e2e.test.ts`** (extend):
  - `it("emits buildPdfTooLongDirective lead for a synthesized many-pages PDF")` — feed a `documentExtractError: "too_many_pages"` + `documentExtractMeta: { numPages: 250 }` through the e2e setup; assert system prompt contains `"I see 250 pages"` and does NOT contain `PDF_GATED_DIRECTIVE_LEAD`.

### TR5 — No new dependencies

`pdfjs-dist@5.4.296` already imported via `pdfjs-dist/legacy/build/pdf.mjs` in `pdf-text-extract.ts`. No new npm deps. Confirmed in `apps/web-platform/node_modules/pdfjs-dist/package.json`.

### TR6 — No leader-path changes

`apps/web-platform/server/agent-runner.ts:842-858` calls `buildPdfGatedDirective` directly with no extractor and no `documentExtractError` plumbing. Same bug applies but a separate, larger refactor. Deferred to #3437 per NG2.

### TR7 — No reaper-window changes

`DEFAULT_WALL_CLOCK_TRIGGER_MS = 90_000` and `DEFAULT_MAX_TURN_DURATION_MS = 600_000` unchanged. Reaper window is intentionally unchanged — bumping it papers over the symptom and increases "agent appears stuck" surface for unrelated cases (per brainstorm Decision #2-rejected).

## Implementation Phases

### Phase 0 — Pre-flight (no code changes)

- [x] Re-read `apps/web-platform/server/pdf-text-extract.ts`, `kb-document-resolver.ts`, `soleur-go-runner.ts` (post-compaction safety per `hr-always-read-a-file-before-editing-it`).
- [x] Verify pdfjs-dist install: `test -d apps/web-platform/node_modules/pdfjs-dist && cat apps/web-platform/node_modules/pdfjs-dist/package.json | jq .version` returns `"5.4.296"`.
- [x] Confirm `bun run typecheck` is clean before the first edit.

### Phase 1 — RED: failing tests first (per `cq-write-failing-tests-before`)

- [x] **Task 1.1.** Extend `apps/web-platform/test/pdf-text-extract.test.ts` with `describe("extractPdfMetadata")` block (4 cases per TR4) — RED, asserts against not-yet-imported `extractPdfMetadata` symbol.
- [x] **Task 1.2.** Extend same file with the `lazy_import_failed` direct test (folds in #3438) — RED.
- [x] **Task 1.3.** Add `describe("buildPdfTooLongDirective")` block to `pdf-unreadable-directive.test.ts` (3 cases per TR4) — RED.
- [x] **Task 1.4.** Extend `read-tool-pdf-capability.test.ts` with the `too_many_pages` HARD-membership assertion — RED (the partition rail will fail at compile-time; that IS the test).
- [x] **Task 1.5.** Create `kb-document-resolver-pdf-page-gate.test.ts` (4 cases per TR4) — RED.
- [x] **Task 1.6.** Extend `cc-concierge-pdf-summarize-e2e.test.ts` with the many-pages case — RED.
- [x] **Task 1.7.** Run `bun run test apps/web-platform/test/pdf-text-extract.test.ts apps/web-platform/test/pdf-unreadable-directive.test.ts apps/web-platform/test/read-tool-pdf-capability.test.ts apps/web-platform/test/kb-document-resolver-pdf-page-gate.test.ts apps/web-platform/test/cc-concierge-pdf-summarize-e2e.test.ts` — confirm all new tests RED (existing tests remain green).
- [x] **Task 1.8.** Commit RED state with message `test(cc-concierge): RED — page-count gate + tooLong directive (#3429)`.

### Phase 2 — GREEN: implementation

- [x] **Task 2.1.** Implement `extractPdfMetadata` + the 3 new constants + add `"too_many_pages"` to `PdfExtractErrorClass` in `pdf-text-extract.ts`.
- [x] **Task 2.2.** Wire `documentExtractMeta` channel through `kb-document-resolver.ts`'s return type (`KbDocumentContext` or equivalent) and add the gate per TR2.
- [x] **Task 2.3.** Add `"too_many_pages"` to `PDF_HARD_FAILURE_LITERALS` in `soleur-go-runner.ts`. Confirm `_AssertPartitionTotal` rail compiles.
- [x] **Task 2.4.** Implement `buildPdfTooLongDirective` factory and add `documentExtractMeta` to `DispatchArgs` and `BuildSoleurGoSystemPromptArgs`.
- [x] **Task 2.5.** Update PDF branch in `buildSoleurGoSystemPrompt` to route `"too_many_pages"` to `buildPdfTooLongDirective` per TR3 step 4.
- [x] **Task 2.6.** Run full test suite: `cd apps/web-platform && bun run test`. Confirm all tests GREEN. Run `bun run typecheck`. Confirm zero new errors.
- [x] **Task 2.7.** Commit GREEN state with message `feat(cc-concierge): page-count gate on PDF soft-route — bridge fix for #3429`.

### Phase 3 — Threshold calibration verification (open question Q1)

- [x] **Task 3.1.** Document the threshold-derivation math inline at the constant declaration in `pdf-text-extract.ts`: `floor(90s / ~10s per Read call) * 20 pages/call - safety margin = 160 → 150`.
- [x] **Task 3.2.** Note in plan/PR body: empirical re-calibration (measure per-Read wall-clock on Manning + synthetic test PDFs) is deferred to QA / post-merge observability via Sentry breadcrumbs. The threshold is a single exported constant — trivially adjustable downward if real-world latency proves higher. No implementation code change.

### Phase 4 — Push, review, QA

- [ ] **Task 4.1.** Push branch (per `rf-before-spawning-review-agents-push-the`): `git push origin feat-large-pdf-soft-route-timeout`.
- [ ] **Task 4.2.** Update PR #3430 body with: closes #3429 references, `Closes #3438` (folded-in scope-out), `Ref #3436 #3437` (deferred symmetry/durable-fix), the User-Brand Impact section verbatim from this plan, and the empirical reproduction note (Manning vs Au Chat).
- [ ] **Task 4.3.** Mark PR ready for review: `gh pr ready 3430`.
- [ ] **Task 4.4.** Invoke `skill: soleur:review` with multi-agent set — required: `architecture-strategist`, `agent-native-reviewer`, `user-impact-reviewer` (mandatory per `requires_cpo_signoff: true` + threshold `single-user incident`), `code-simplicity-reviewer`. Apply review findings inline per `rf-review-finding-default-fix-inline`.
- [ ] **Task 4.5.** Manual QA reproduction:
  - `Au Chat Pôtan` (57-page, <15MB) — verify inline-content success path (no directive, body inlined).
  - `Manning Effective Platform Engineering` (403-page, >24MB) — verify new `buildPdfTooLongDirective` output with `"I see 403 pages"`.
  - Synthesized 60-page image-heavy >24MB PDF — verify `buildPdfGatedDirective` (existing copy preserved, recovery intact).
- [ ] **Task 4.6.** Verify Sentry breadcrumbs in dev: trigger the gate, confirm `cc-pdf-extractor` breadcrumb with `op: "metadataRead"` and `class: "too_many_pages"`.

### Phase 5 — Ship

- [ ] **Task 5.1.** Confirm CPO sign-off recorded (per `requires_cpo_signoff: true`). Brainstorm Phase 0.5 carry-forward already covers CPO assessment; review-time `user-impact-reviewer` provides the per-PR check.
- [ ] **Task 5.2.** Run `skill: soleur:compound` to capture session learnings.
- [ ] **Task 5.3.** Run `skill: soleur:ship` to drive preflight + auto-merge.
- [ ] **Task 5.4.** Post-merge: verify release/deploy workflows succeed per `wg-after-a-pr-merges-to-main-verify-all`. Spot-check Sentry for the new breadcrumb shape.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** A 403-page PDF (>24MB, hits `oversized_buffer`) routed through Concierge produces the new `buildPdfTooLongDirective` output with the page count named, in <3s of metadata-read latency. Manual repro on Manning Book succeeds (Phase 4.5).
- [ ] **AC2.** A 57-page PDF (<15MB) routed through Concierge continues to produce the inline-content success path (no directive, body inlined via `<document>` wrapper). Manual repro on Au Chat Pôtan succeeds (Phase 4.5).
- [ ] **AC3.** A synthesized 60-page image-heavy PDF (>24MB, hits `oversized_buffer`, but page count below threshold) continues to route to `buildPdfGatedDirective` with the existing copy.
- [ ] **AC4.** A synthesized 80MB PDF (exceeds the 60MB metadata ceiling) falls through to the existing soft-failure routing — fails closed.
- [ ] **AC5.** A synthesized PDF whose metadata-read times out (mocked) falls through to the existing soft-failure routing — fails closed.
- [ ] **AC6.** Sentry shows `cc-pdf-extractor` breadcrumbs with `op: "metadataRead"` and (when threshold trips) `class: "too_many_pages"`. Verified in dev (Phase 4.6).
- [ ] **AC7.** `bun run typecheck` passes with zero new errors.
- [ ] **AC8.** Project test suite passes: existing PR #3405 partition tests unchanged in passage; new tests for the gate added per TR4.
- [ ] **AC9.** Multi-agent review (`architecture-strategist`, `agent-native-reviewer`, `user-impact-reviewer`, `code-simplicity-reviewer`) completed per `rf-review-finding-default-fix-inline`.
- [ ] **AC10.** CPO sign-off recorded per `requires_cpo_signoff: true` and the `single-user incident` brand-survival threshold.
- [ ] **AC11.** PR body uses `Closes #3429` and `Closes #3438` ON THEIR OWN LINES; `Ref #3436` and `Ref #3437` for deferred follow-ups (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] **AC12.** All four ALARM classes ALWAYS show in the Risks section of the PR body: threshold mis-calibration, metadata-read RSS spike, false-negative on text-heavy success path, pdfjs-dist Node engine drift.

### Post-merge (operator)

- [ ] **AC13.** Verify production Sentry shows the new `op: "metadataRead"` breadcrumb shape on a real Concierge PDF cold-Query (no synthetic event needed; the next real cc-concierge dispatch on a PDF will emit it).
- [ ] **AC14.** Confirm #3438 closed automatically by the merge (auto-close via `Closes #3438`).
- [ ] **AC15.** Confirm #3436 (Files API durable fix) and #3437 (leader-path symmetry) remain open and milestoned (`Post-MVP / Later` is acceptable; CPO should milestone-bump #3436 to next phase per brainstorm risk R5).

## Risks

- **R1.** **Threshold mis-calibration.** 150 pages is math-derived (90s reaper / ~10s per Read call × 20 pages/call - safety margin). If real-world per-Read latency is significantly higher, the threshold may still allow timeouts. **Mitigation:** Phase 3 documents the math; Sentry breadcrumbs enable post-merge calibration; threshold is a single exported constant (trivially reversible).
- **R2.** **Metadata-read RSS spike on a malformed PDF.** pdfjs builds the xref table during `getDocument`; a pathologically-structured PDF might still spike RSS. **Mitigation:** TR1 hard-caps the input at 60MB before pdfjs is invoked; `Promise.race` 3s timeout caps wall-clock; `doc.destroy()` in `finally` releases the doc on success; fire-and-forget cleanup on timeout.
- **R3.** **False negative on text-heavy success path.** If a 200-page PDF extracts text under 50KB (heavily compressed / mostly images), the gate fires unnecessarily on the `oversized_buffer` branch only — small-byte-cap text-heavy 200-page PDFs continue to route via the inline-content success path (the gate triggers on `oversized_buffer`, not on text-length). **Mitigation:** the gate is keyed off `oversized_buffer` only per the reconciliation finding; under-cap success is unaffected.
- **R4.** **pdfjs-dist Node engine drift.** Per learning `2026-04-18-pdfjs-metadata-on-node-without-canvas.md`, pdfjs-dist 5.x requires Node 22.3+. **Mitigation:** already covered by the repo's three-layer enforcement (`engines` + `.nvmrc` + CI `setup-node`) per #3383; no new requirement here.
- **R5.** **Trust-breach if #3436 doesn't ship next phase.** Per CPO assessment, A is a bridge; if Files API (B) isn't milestoned within the same phase, the trust-breach risk re-surfaces the first time a user expects whole-book summarization. **Mitigation:** #3436 is filed; CPO milestone-bumps it per AC15.
- **R6.** **Defense-relaxation analog (per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`).** This plan does NOT relax any existing defense — `oversized_buffer` still routes to `buildPdfGatedDirective` for small-page-count cases (FR5); the `too_many_pages` gate is additive. The new 60MB metadata ceiling is a new ceiling, not a relaxation; it explicitly bounds RSS for the new code path.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled per spec carry-forward.)
- The `_AssertPartitionTotal` rail in `soleur-go-runner.ts:312-317` is a compile-time check — adding `"too_many_pages"` to the union without also adding it to `PDF_HARD_FAILURE_LITERALS` will fail `tsc --noEmit`. Tests in Phase 1 will RED via the same rail; this is intentional.
- The test mirror in `read-tool-pdf-capability.test.ts:9-10` imports `PDF_SOFT_FAILURE_LITERALS` and `PDF_HARD_FAILURE_LITERALS` from the runtime source (single source of truth). Adding the literal to the runtime arrays automatically extends the test iteration.
- `extractPdfMetadata`'s timeout path uses `loadingTask.destroy()` (not the doc — the doc doesn't exist yet at timeout). Per `pdfjs-dist@5.4.296` types (`types/src/display/api.d.ts:872`), `PDFDocumentLoadingTask.destroy()` "abort[s] all network requests and destroy[s] the worker". The cancel is fire-and-forget (we've already returned the timeout result); `clearTimeout(timer)` in `finally` prevents a leaked timer when `getDocument` resolves before the deadline.
- pdfjs-dist@5.4.296 explicitly REJECTS Buffer (`instanceof Buffer === false` check); `extractPdfMetadata` MUST wrap to a plain Uint8Array view per the same pattern as `extractPdfText`. Without the wrap, every metadata-read returns `{ ok: false, reason: "parse_error" }` and the gate degrades to fail-closed in production.
- Per `cq-regex-unicode-separators-escape-only`: any regex this plan introduces must use `\uXXXX` escape notation, not literal U+2028/U+2029. (No new regex introduced; existing sanitizers in `soleur-go-runner.ts` already follow the rule.)
- The `buildPdfTooLongDirective` copy is a test surface (FR4 exact match). Any future copy revision MUST update both the factory AND the test in the same commit.
- `pdf-text-extract.test.ts` currently has zero `vi.mock` calls. Two new tests in this plan introduce mocks: (1) the lazy_import_failed test mocks the legacy pdf.mjs module; (2) the metadata timeout test mocks `pdfjs.getDocument`. Mocks are NOT visible across `it` blocks unless declared at top-of-file or inside `beforeEach`. Per learning `2026-04-18-pdfjs-metadata-on-node-without-canvas.md` Session Errors §"openBinaryStream spy", be explicit about the mock factory shape (don't call-through inside the wrapper) and use `vi.useFakeTimers()` + `vi.advanceTimersByTimeAsync()` for the timeout test — wall-clock-based timeout assertions add 3s per test run.
- pdfjs-dist 5.4.296 `getDocument()` returns the `PDFDocumentLoadingTask` synchronously; `.promise` is the resolved doc. The mock shape MUST mirror this two-field structure (`{ promise: Promise<PDFDocument>, destroy: () => Promise<void> }`) — using a bare promise breaks the `loadingTask.destroy()` call site.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO) — carried forward from brainstorm Phase 0.5

### Engineering (CTO) — carry-forward

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** Recommends Option A+ (page-count gate with 60MB metadata ceiling, 3s `Promise.race` timeout, fail-closed). Files API (B) is correct destination but warrants its own architecture cycle (#3436). Concierge fix is load-bearing for the user-reported regression; leader-path symmetry filed as #3437. Critical-path risk bounded by fail-closed pattern. Capability gaps: none.

### Product (CPO) — carry-forward, sign-off required

**Status:** reviewed (carry-forward from brainstorm) + per-PR sign-off required at review time
**Assessment:** A as bridge, B as destination, NOT D. Target user (founder uploading a Manning book) is in exploratory mode — clean refusal is acceptable IF the directive teaches them how to extract value now. Reject auto-summarize-first-N-pages (NG5; useless preface summary reinforces "Concierge is shallow"). Threshold calibration must be against actual failure mode (token budget × per-page tokens), not page count alone — addressed by Phase 3 inline math + Sentry breadcrumbs for post-merge calibration. If A ships and B isn't milestoned within the same phase, trust-breach risk re-surfaces — addressed by AC15.

**Brainstorm-recommended specialists:** none (no copywriter, no ux-design-lead — no new UI surface; the directive copy is text-only and was authored by CPO in the brainstorm).

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no new user-facing pages, no new components, no modals/dialogs. The change is entirely server-side: a routing decision in the agent's system prompt that produces a different text response in the existing chat surface. Per Phase 2.5 mechanical escalation: no new files match `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`.

## References

- Issue #3429 — empirical reproduction + three candidate directions
- Issue #3436 — Anthropic Files API durable fix (deferred per NG1)
- Issue #3437 — leader-path symmetry (deferred per NG2)
- Issue #3438 — folded-in lazy_import_failed test
- Issue #3343 — open scope-out, acknowledged
- Issue #3369 — open scope-out, acknowledged
- Issue #2955 — open scope-out, acknowledged
- PR #3405 — partition that exposed this cost
- PR #3430 — this PR (draft)
- Spec: `knowledge-base/project/specs/feat-large-pdf-soft-route-timeout/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-07-large-pdf-soft-route-timeout-brainstorm.md`
- Learning: `knowledge-base/project/learnings/2026-05-06-cc-concierge-pdf-summary-cascade-structural-fix.md`
- Learning: `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md`
- Learning: `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md`
- Learning: `knowledge-base/project/learnings/2026-05-06-cap-coupling-between-adjacent-prs.md`
- Code: `apps/web-platform/server/pdf-text-extract.ts`
- Code: `apps/web-platform/server/kb-document-resolver.ts`
- Code: `apps/web-platform/server/soleur-go-runner.ts`
- Code (deferred): `apps/web-platform/server/agent-runner.ts:842-858`
