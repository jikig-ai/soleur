---
title: Page-Count Gate on Concierge PDF Soft-Route
status: specified
issue: 3429
brainstorm: knowledge-base/project/brainstorms/2026-05-07-large-pdf-soft-route-timeout-brainstorm.md
branch: feat-large-pdf-soft-route-timeout
date: 2026-05-07
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# Spec: Page-Count Gate on Concierge PDF Soft-Route

## Problem Statement

After PR #3405 partitioned `PdfExtractErrorClass` into soft-failure (route to gated `Read` directive) vs hard-failure (route to unreadable directive), 400+ page PDFs that hit `oversized_buffer` (the >15MB extractor cap) route to soft → gated `Read`. The Concierge agent then issues ~21 sequential `Read({pages: "1-20"})` calls. Each call's response materialization (base64 PDF chunk + model ingestion) takes many seconds. The 90-second `DEFAULT_WALL_CLOCK_TRIGGER_MS` idle-reaper in `soleur-go-runner.ts` fires before the chain finishes, surfacing `"Agent stopped responding"` to the user.

**Empirical reproduction (#3429):** Manning Book - Effective Platform Engineering (403 pages, >15MB) consistently times out; Au Chat Pôtan presentation (57 pages, <15MB) consistently succeeds via the inline-content success path. Page count, not prompt wording, is the differentiator.

## Goals

- **G1.** PDFs with too many pages for the SDK `Read` tool's per-request cap (default >150 pages) MUST produce a specific, actionable refusal directive instead of a silent timeout.
- **G2.** PDFs that succeed today on the inline-content success path (e.g., the 57-page Au Chat case) MUST continue to succeed unchanged.
- **G3.** PDFs in the recovery window (small enough for Read fanout, e.g., a 60-page image-heavy >15MB PDF) MUST continue to route to the gated `Read` directive — no capability regression.
- **G4.** The page-count gate itself MUST NOT introduce a new failure mode: any error in the metadata-only pdfjs read MUST fail closed to the current soft-route behavior.
- **G5.** The new directive MUST name the page count and offer a concrete next step (share a chapter, paste the table of contents).
- **G6.** Sentry observability MUST distinguish the new gate fires from existing extractor failures.

## Non-Goals

- **NG1.** Anthropic Files API integration (Option B) — durable destination, separate architecture-track issue.
- **NG2.** Leader path (`agent-runner.ts:842-858`) symmetry — same bug affects the leader, separate issue.
- **NG3.** Re-partition of `oversized_buffer` from SOFT to HARD without a page-count check (Option D) — capability regression on small-page-count + large-byte-size PDFs.
- **NG4.** Reaper-window bump (Option C) — papers over symptom; rejected by issue author.
- **NG5.** Auto-summarize-first-N-pages partial-recovery pattern — produces useless preface summary; rejected by CPO.
- **NG6.** Automatic chapter-range parsing of follow-up turns — copy alone is sufficient (verified in QA); follow-up is a separate UX project if needed.
- **NG7.** Retroactive sweep of historical Concierge sessions — gate fires forward only.

## Functional Requirements

- **FR1.** When a PDF document is being resolved for Concierge AND the extractor cannot inline the body (either `oversized_buffer` was raised OR the extracted text exceeds the 50KB inline cap), the resolver MUST attempt a metadata-only pdfjs read to obtain `numPages`.
- **FR2.** If the metadata read returns `numPages > LARGE_PDF_PAGE_THRESHOLD` (initial value 150), the resolver MUST surface a new `PdfExtractErrorClass` value `too_many_pages` with the page count carried in the resolver's error metadata.
- **FR3.** The runner (`soleur-go-runner.ts`) MUST partition `too_many_pages` into the HARD set, routing to a new `buildPdfTooLongDirective(artifactPath, numPages, NO_ASK)` factory.
- **FR4.** The directive copy MUST follow the form: `"I see {N} pages — that's too long for me to read in one go. Share a chapter, or paste the table of contents and I'll point you at the right section."` (exact wording is part of the test surface).
- **FR5.** PDFs with `numPages ≤ LARGE_PDF_PAGE_THRESHOLD` MUST continue to route via the existing soft-failure path (`buildPdfGatedDirective`), preserving today's recovery on small-byte-cap PDFs.
- **FR6.** If the metadata read errors (timeout, parse failure, oversized buffer beyond the metadata ceiling) the resolver MUST fall through to the existing soft-failure routing — fail closed to today's behavior.
- **FR7.** A Sentry breadcrumb MUST be emitted on every metadata-read attempt (`category: "cc-pdf-extractor"`, `data: { op: "metadataRead", ok, numPages?, reason? }`).

## Technical Requirements

- **TR1.** Extend `apps/web-platform/server/pdf-text-extract.ts`:
  - Add `LARGE_PDF_PAGE_THRESHOLD = 150` exported constant.
  - Add `METADATA_READ_BYTE_CEILING_BYTES = 60 * 1024 * 1024` (60MB) exported constant — the upper bound at which we'll attempt a metadata-only pdfjs read.
  - Add `METADATA_READ_TIMEOUT_MS = 3000` exported constant.
  - Add `extractPdfMetadata(buffer: Buffer): Promise<{ ok: true; numPages: number } | { ok: false; reason: "oversized" | "timeout" | "parse_error" }>`:
    - If `buffer.length > METADATA_READ_BYTE_CEILING_BYTES`, return `{ ok: false, reason: "oversized" }` without invoking pdfjs.
    - Otherwise, invoke `pdfjs.getDocument({ data: buffer, isEvalSupported: false }).promise` wrapped in `Promise.race` against `METADATA_READ_TIMEOUT_MS`.
    - Read `doc.numPages`; call `doc.destroy()` in a `finally` block.
    - Catch all errors; return structured `{ ok: false, reason: "timeout" | "parse_error" }`.
  - Add `"too_many_pages"` to the `PdfExtractErrorClass` union.
- **TR2.** Update `apps/web-platform/server/kb-document-resolver.ts` PDF branch:
  - When `extractPdfText` returns null with class `oversized_buffer`, OR when extraction succeeds but text exceeds the 50KB inline cap, call `extractPdfMetadata(buffer)`.
  - On `{ ok: true, numPages }` with `numPages > LARGE_PDF_PAGE_THRESHOLD`: surface `documentExtractError = "too_many_pages"` and pass `numPages` through the resolver's error metadata channel.
  - On `{ ok: true, numPages }` with `numPages <= LARGE_PDF_PAGE_THRESHOLD`: continue with the existing soft-failure routing.
  - On `{ ok: false, ... }`: fall through to existing soft-failure routing (fail-closed).
  - Emit Sentry breadcrumb per FR7.
- **TR3.** Update `apps/web-platform/server/soleur-go-runner.ts`:
  - Move `too_many_pages` into `PDF_HARD_FAILURE_CLASSES`.
  - Update `_AssertPartitionTotal` compile-time rail to include the new class.
  - Add factory `buildPdfTooLongDirective(artifactPath, numPages, NO_ASK)` that produces the FR4 copy.
  - In the PDF branch (around line 771 per partition spec), when `documentExtractError === "too_many_pages"` route to the new factory passing `safeArtifactPath`, `safeNumPages`, and `NO_ASK`. All other hard classes continue to route to `buildPdfUnreadableDirective`.
- **TR4.** Tests (RED-first per `cq-write-failing-tests-before`):
  - Unit: `pdf-text-extract.test.ts` — add tests for `extractPdfMetadata` covering oversized-input refusal, parse-failure, timeout (mocked), and success returning expected `numPages`.
  - Unit: `pdf-unreadable-directive.test.ts` (or sibling) — assert `buildPdfTooLongDirective` produces FR4 exact copy with the page count interpolated, and that `expectNoCascade` still holds.
  - Routing: `read-tool-pdf-capability.test.ts` (or sibling) — extend the soft/hard partition walk to cover `too_many_pages` in HARD.
  - Resolver: a test in `kb-document-resolver` test surface that asserts the gate fires for a stub PDF with `numPages = 200` and falls through for `numPages = 50`.
  - E2E (`cc-concierge-pdf-summarize-e2e.test.ts`): add a case for a synthesized many-pages PDF asserting the new directive lead is present and `PDF_GATED_DIRECTIVE_LEAD` is absent.
- **TR5.** No new npm dependencies. The metadata read uses the existing `pdfjs-dist@5.4.296/legacy/build/pdf.mjs` import (already present in `pdf-text-extract.ts`).
- **TR6.** No changes to `apps/web-platform/server/agent-runner.ts` (leader path symmetry deferred per NG2).
- **TR7.** No changes to `DEFAULT_WALL_CLOCK_TRIGGER_MS`. The reaper window is unchanged.

## Acceptance Criteria

- **AC1.** A 403-page PDF (>15MB, hits `oversized_buffer`) routed through Concierge produces the new `buildPdfTooLongDirective` output with the page count named, in <3s of metadata-read latency. Manual repro on Manning Book succeeds.
- **AC2.** A 57-page PDF (<15MB) routed through Concierge continues to produce the inline-content success path (no directive, body inlined via `<document>` wrapper). Manual repro on Au Chat Pôtan succeeds.
- **AC3.** A synthesized 60-page image-heavy PDF (>15MB, hits `oversized_buffer`, but page count below threshold) continues to route to `buildPdfGatedDirective` with the existing copy.
- **AC4.** A synthesized 80MB PDF (exceeds the 60MB metadata ceiling) falls through to the existing soft-failure routing — fails closed.
- **AC5.** A synthesized PDF whose metadata-read times out (mocked) falls through to the existing soft-failure routing — fails closed.
- **AC6.** Sentry shows `cc-pdf-extractor` breadcrumbs with `op: "metadataRead"` and the new `class: "too_many_pages"` value when the gate fires.
- **AC7.** `bun run typecheck` passes with zero new errors.
- **AC8.** Project test suite passes: existing PR #3405 tests unchanged in passage; new tests for the gate added per TR4.
- **AC9.** Multi-agent review (`architecture-strategist`, `agent-native-reviewer`, `user-impact-reviewer`, `code-simplicity-reviewer`) completed per `rf-review-finding-default-fix-inline`.
- **AC10.** CPO sign-off recorded per `requires_cpo_signoff: true` and the `single-user incident` brand-survival threshold.

## Risks

- **R1.** **Threshold mis-calibration.** 150 pages is math-derived (90s reaper / ~10s per Read call × 20 pages/call - safety margin). If real-world per-Read latency is significantly higher, the threshold may still allow timeouts. **Mitigation:** plan-phase empirical measurement on Manning + synthetic 100/200/300-page PDFs; adjust threshold downward if needed. Threshold is a single exported constant — trivially reversible.
- **R2.** **Metadata-read RSS spike on a malformed PDF.** pdfjs builds the xref table during `getDocument`; a pathologically-structured PDF might still spike RSS. **Mitigation:** TR1 hard-caps the input at 60MB before pdfjs is invoked; `Promise.race` 3s timeout caps wall-clock; `doc.destroy()` in `finally` releases the doc.
- **R3.** **False negative on text-heavy success path.** If a 200-page PDF extracts text under 50KB (heavily compressed / mostly images), the gate fires unnecessarily — user gets a refusal even though the inline-content path could have served them. **Mitigation:** the gate only fires on the >50KB-text or oversized_buffer paths; the under-50KB success path bypasses the gate entirely. Verify in QA on a known text-light long PDF.
- **R4.** **pdfjs-dist Node engine drift.** Per learning `2026-04-18-pdfjs-metadata-on-node-without-canvas.md`, pdfjs-dist 5.x requires Node 22.3+. Local dev on Node 21 will crash at metadata read. **Mitigation:** already covered by repo's three-layer enforcement (`engines` + `.nvmrc` + CI `setup-node`); no new requirement here.
- **R5.** **Trust-breach if B doesn't ship next phase.** Per CPO assessment, A is a bridge; if Files API (B) isn't milestoned within the same phase, the trust-breach risk re-surfaces the first time a user expects whole-book summarization. **Mitigation:** file the B issue and milestone it before this PR merges. Track in handoff.

## Implementation Outline (for planning)

- Files modified:
  - `apps/web-platform/server/pdf-text-extract.ts` (extend exports + add `extractPdfMetadata`)
  - `apps/web-platform/server/kb-document-resolver.ts` (PDF branch gate)
  - `apps/web-platform/server/soleur-go-runner.ts` (partition update + new factory)
- Files added: none (all changes extend existing modules)
- Tests: extend `pdf-text-extract.test.ts`, `pdf-unreadable-directive.test.ts`, `read-tool-pdf-capability.test.ts`, `cc-concierge-pdf-summarize-e2e.test.ts`, plus a resolver test
- Follow-up issues to file before this PR merges:
  - Anthropic Files API for large-PDF Concierge ingest (Option B; durable fix)
  - Leader-path symmetry: extend `agent-runner.ts` PDF handling to use the same partition + page-count gate
- Architecture record (optional): `/soleur:architecture create 'Anthropic Files API for large-PDF Concierge ingest'` per CTO assessment

## References

- Issue #3429 — empirical reproduction + three candidate directions
- PR #3405 — partition that exposed this cost
- Issue #3425 — manual reproduction follow-through
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-07-large-pdf-soft-route-timeout-brainstorm.md`
- Learning: `knowledge-base/project/learnings/2026-05-06-cc-concierge-pdf-summary-cascade-structural-fix.md`
- Learning: `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md`
