---
date: 2026-05-07
topic: large-pdf-soft-route-timeout
issue: "#3429"
related_issues: ["#3405", "#3425"]
domain: engineering
status: complete
worktree: feat-large-pdf-soft-route-timeout
pr: "#3430"
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# Brainstorm: Large-PDF Soft-Route Timeout (Concierge)

## What We're Building

A page-count-aware gate on the cc-concierge PDF soft-failure route that turns a silent-timeout into a specific, actionable refusal directive ("share a chapter or paste the TOC") for PDFs too long for the SDK `Read` tool's 20-page-per-request cap.

This is the **bridge fix** to issue #3429. The durable destination — Anthropic Files API pre-upload that eliminates the Read fanout structurally — is filed as a separate architecture-track issue and brainstorm (referenced below).

## Why This Approach

After PR #3405 partitioned `PdfExtractErrorClass` into soft-failure (route to gated `Read` directive) vs hard-failure (route to unreadable directive), 400+ page PDFs that hit `oversized_buffer` (>15MB extractor cap) route to soft → gated `Read`. The agent then issues ~21 sequential `Read({pages: "1-20"})` calls. Each call's response materializes a chunk of base64 PDF + model ingestion, taking many seconds. The 90-second `DEFAULT_WALL_CLOCK_TRIGGER_MS` idle-reaper in `soleur-go-runner.ts` fires before the chain finishes, surfacing "Agent stopped responding" to the user.

The structural fix is to detect "too long for Read" upstream — by reading `numPages` cheaply via pdfjs metadata-only — and route to a new hard directive that teaches the user how to extract value (share a chapter, paste the TOC) instead of letting the agent silently fail.

**Why not Files API (Option B) now:** Anthropic's Files API is the durable answer (eliminates the Read fanout entirely; lets the model summarize whole books) but has unverified constraints (size cap, BYOK token-cost surprise on 200K-token whole-book ingest, leader-path symmetry plumbing). Files API gets its own architecture cycle. Meanwhile, users hitting the bug today need an immediate fix that turns a confusing timeout into a clear next step.

**Why not Option D (re-partition `oversized_buffer` to hard with no page-count check):** CPO + CTO both reject. D regresses 80-page image-heavy PDFs (>15MB byte size, but small enough page count to succeed via Read fanout) into refusal. The page-count gate keeps recovery on those cases.

**Why not Option C (reaper bump):** Issue author rejected. A 1000-page PDF won't fit even at 600s reaper. Bumping the reaper increases "agent appears stuck" surface for unrelated cases. Wrong shape.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Bridge fix scope: Concierge path only (`soleur-go-runner.ts`, `kb-document-resolver.ts`, `pdf-text-extract.ts`) | CTO: leader path doesn't extract text (no `documentExtractError` plumbing); applying gate there is a separate, larger change |
| 2 | Page-count threshold: **150 pages** (initial value; empirically calibrated in plan phase) | Math: `floor(90s reaper / ~10s per Read call) * 20 pages/call - safety margin = 160 pages`. Round to 150 for headroom. |
| 3 | Page-count source: pdfjs metadata-only call via `pdfjs-dist/legacy/build/pdf.mjs` (proven cheap on Node 22 per `2026-04-18-pdfjs-metadata-on-node-without-canvas.md`) | Reuses existing dep + pattern; no new infrastructure |
| 4 | Metadata-read safety envelope: re-cap at 60MB before invoking metadata-only `getDocument`; `Promise.race` 3s timeout; try/catch fail-closed to current soft-route behavior on any error | CTO: metadata pdfjs call shouldn't itself become a new failure mode; worst case we regress to today's behavior, not worse |
| 5 | Two gate trigger points | (a) `oversized_buffer` extractor refusal (>15MB); (b) extractor success but inline text >50KB (would otherwise fall through to Read) |
| 6 | Directive copy: `"I see {N} pages — that's too long for me to read in one go. Share a chapter, or paste the table of contents and I'll point you at the right section."` | CPO: specific (page count named), preserves concierge identity, teaches next step |
| 7 | Reject auto-summarize-first-N-pages | CPO: produces useless preface summary; reinforces "Concierge is shallow" perception |
| 8 | Reject Option D (repartition `oversized_buffer` to hard with no page-count check) | CPO + CTO: capability regression on small-page-count + large-byte-size PDFs |
| 9 | New `PdfExtractErrorClass` member: `too_many_pages` (joins HARD partition) | Routes to the new directive; preserves the existing partition pattern from PR #3405 |
| 10 | Files API (Option B) deferred to separate architecture-track issue with its own brainstorm | Multi-day scope; needs WebFetch verification of Files API limits + token-budget guard + leader-path symmetry plan |
| 11 | Leader-path symmetry deferred to separate issue | `wg-when-an-audit-identifies-pre-existing` — the leader hits the same bug; separate fix because leader doesn't go through `kb-document-resolver.ts` |

## Open Questions

1. **Threshold calibration.** Initial value of 150 pages is math-derived. Plan phase should add an empirical calibration step: measure per-Read-call wall-clock on the Manning book (or a synthetic 200/300/400-page test PDF) and adjust threshold so the 9-call ceiling holds with margin. This is a measurement task, not a design question.
2. **Should the directive include partial recovery via TOC paste?** CPO suggested "paste the TOC and I'll point you at the right section." Concierge currently treats the next user turn as free-form text; if the user pastes a TOC, the agent will respond against it as document context. This works without code changes — copy alone is sufficient. Verify in QA.
3. **Sentry breadcrumb for the new gate.** Should the breadcrumb category be `cc-pdf-extractor` (existing) with `class: too_many_pages`, or a new `cc-pdf-page-gate` category? Existing category preferred for observability continuity.

## User-Brand Impact

**Artifact:** Concierge response to a user who uploaded a long PDF and asked for a summary.

**Vector:** Silent timeout — user sees "Agent stopped responding" with no recovery path. Trust breach (Concierge looks unreliable). Secondary: silent BYOK / Anthropic credit burn on ~21 doomed Read calls per attempt.

**Threshold:** `single-user incident` — one founder reproducing this on a Manning book is enough to break the concierge brand promise. The fix must (a) not silently misfire, (b) not regress small-PDF success, (c) provide a clear next step in the refusal copy.

**Mitigation in this brainstorm:**
- Decision #4 (metadata-read safety envelope) prevents the gate itself from becoming a new failure mode.
- Decision #6 (specific copy with page count) prevents the "broken concierge" perception by naming the constraint and offering a path forward.
- Decision #2 (threshold = 150) deliberately conservative; small PDFs (Au Chat 57-page case) stay on the inline-content success path unchanged.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Recommends Option A+ (page-count gate with 60MB metadata ceiling, 3s `Promise.race` timeout, fail-closed). Files API (B) is correct destination but warrants its own architecture cycle. Concierge fix is load-bearing for the user-reported regression; leader-path symmetry should be filed as a separate `wg-when-an-audit-identifies-pre-existing` issue. Critical-path risk bounded by fail-closed pattern. Capability gaps: none.

### Product (CPO)

**Summary:** A as bridge, B as destination, NOT D. Target user (founder uploading a Manning book) is in exploratory mode — clean refusal is acceptable IF the directive teaches them how to extract value now. Reject auto-summarize-first-N-pages (useless preface summary reinforces "Concierge is shallow"). Threshold calibration must be against actual failure mode (token budget × per-page tokens), not page count alone. If A ships and B isn't milestoned within the same phase, trust-breach risk re-surfaces.

## References

- PR #3405 — partition that exposed this cost (merged 2026-05-07)
- Issue #3425 — manual reproduction follow-through that surfaced the timeout
- Performance-oracle review on PR #3405 F3 — flagged exactly this risk pre-merge
- Learning `2026-05-06-cc-concierge-pdf-summary-cascade-structural-fix.md` — partition design + structural-fix pattern
- Learning `2026-04-18-pdfjs-metadata-on-node-without-canvas.md` — metadata-only pdfjs pattern, Node 22 engine note
- `apps/web-platform/server/soleur-go-runner.ts` — `DEFAULT_WALL_CLOCK_TRIGGER_MS`, `buildPdfGatedDirective`, `PDF_SOFT_FAILURE_CLASSES`, `PDF_HARD_FAILURE_CLASSES`
- `apps/web-platform/server/pdf-text-extract.ts` — `PdfExtractErrorClass` definition, `INPUT_BUFFER_CAP_BYTES`, `MAX_PAGES`
- `apps/web-platform/server/kb-document-resolver.ts` — PDF branch, `documentExtractError` surface
- `apps/web-platform/server/agent-runner.ts:842-858` — leader-path PDF handling (deferred symmetry)
