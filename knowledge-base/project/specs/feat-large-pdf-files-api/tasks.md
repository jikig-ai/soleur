---
title: Chapter-Chunking PDF Resolver — Tasks
issue: 3436
plan: knowledge-base/project/plans/2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md
spec: knowledge-base/project/specs/feat-large-pdf-files-api/spec.md
brand_survival_threshold: single-user incident
---

# Tasks: Chapter-Chunking PDF Resolver

Derived from `2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md` (post-review). Three implementation phases preceded by one-shot prerequisites.

## 0. Prerequisites (one-shot)

- 0.1 `git fetch origin main && git merge origin/main` from the worktree. Resolve conflicts (none expected — worktree's only edits are docs).
- 0.2 If `apps/web-platform/package.json` changed on main: `bun install`.
- 0.3 `bun test` baseline; confirm clean.
- 0.4 Verify post-merge state: `leader-document-resolver.ts` exists, `extractPdfMetadata` is exported, `too_many_pages` is in `PdfExtractErrorClass`.
- 0.5 Add `@anthropic-ai/sdk` to `apps/web-platform/package.json` `devDependencies` (latest matching the version pinned by `claude-agent-sdk`'s peer). Regenerate `bun.lock`.

## 1. Phase 1 — Empirical spikes (gates Phase 2)

### 1.1 S1: cache_control end-to-end forwarding

- 1.1.1 Create `apps/web-platform/scripts/spike/cache-control-forwarding.ts` (script, not test).
- 1.1.2 Construct an `SDKUserMessage` with a `document` content block carrying `cache_control: { type: "ephemeral" }` and a >2KB body.
- 1.1.3 Send via `query()` with a real Anthropic key (BYOK or test key from local Doppler `dev` config).
- 1.1.4 Inspect first-run `SDKResultMessage.usage` → record `cache_creation_input_tokens`.
- 1.1.5 Send identical content within 5min TTL → record `cache_read_input_tokens` on second run.
- 1.1.6 Document outcome: GREEN (write > 0 AND read > 0) or RED (cache fields always 0). Save to `apps/web-platform/scripts/spike/s1-result.json` (committed).
- 1.1.7 If RED: edit AC #4 in the plan to keep only the RED branch (5-turn cap); file v2 follow-up issue for bare-SDK side-channel revisit; remove the GREEN-only test from Phase 3.

### 1.2 S2: pdfjs getOutline() coverage on 2 fixtures

- 1.2.1 Acquire 2 fixture PDFs (binaries `.gitignore`d): 1 outline-bearing technical book (Manning/O'Reilly-class, 200-500pg), 1 scanned book (no outline).
- 1.2.2 Create `apps/web-platform/scripts/spike/pdf-outline-fixtures.json` with SHA + source URL for each (manifest only; binaries not committed).
- 1.2.3 Create `apps/web-platform/scripts/spike/pdf-outline-coverage.ts`. For each fixture: call `extractPdfOutline(buffer)`; record outline length, top-level entry count, page coverage, classification (usable / unusable).
- 1.2.4 Document outcome in `apps/web-platform/scripts/spike/s2-result.md` (committed). PR body cites this verbatim.
- 1.2.5 If either fixture fails its expected classification: PAUSE; revisit brainstorm. Likely outcome: defer to embedding-based retrieval (#3450).

## 2. Phase 2 — Outline extraction + resolver wiring

### 2.1 Extend `pdf-text-extract.ts`

- 2.1.1 Add constants: `OUTLINE_READ_TIMEOUT_MS = 5000`, `MIN_OUTLINE_ENTRIES = 3`, `OUTLINE_PAGE_COVERAGE_MIN = 0.8`.
- 2.1.2 Add type: `PdfOutlineReadResult = { ok: true; outline: ChapterIndex[] } | { ok: false; reason: "no_outline" | "outline_too_shallow" | "timeout" | "parse_error" }` where `ChapterIndex = { title: string; startPage: number; endPage: number; depth: number }` (1-based pages).
- 2.1.3 Implement `extractPdfOutline(buffer): Promise<PdfOutlineReadResult>` mirroring `extractPdfMetadata` shape (lazy import, race-with-timeout, `void loadingTask.destroy()` on timeout, `void doc.destroy()` finally, never throw).
- 2.1.4 Walk `pdf.getOutline()` items recursively; resolve `dest` via `pdf.getDestination(name)` → `pdf.getPageIndex(ref)`. Compute end page from sibling start (or `numPages` for last).
- 2.1.5 If any chapter dest fails to resolve → return `{ ok: false, reason: "parse_error" }` for the WHOLE outline. Don't emit partial chapter list.
- 2.1.6 Apply heuristic: outline unusable if entries < `MIN_OUTLINE_ENTRIES` OR top-level coverage < `OUTLINE_PAGE_COVERAGE_MIN`.
- 2.1.7 Mirror the `Dockerfile require.resolve` assertion comment block (existing pattern at line ~174-177) so build-time guards cover the new code path.
- 2.1.8 Extend `extractPdfText` signature: `extractPdfText(buffer, capChars, options?: { featureTag?: string; startPage?: number; endPage?: number })`.
  - Validate `startPage >= 1`, `endPage <= numPages`, `endPage >= startPage`. Invalid → `{ ok: false, error: "parse_error" }`.
  - `MAX_PAGES = 500` applies: if `endPage - startPage + 1 > MAX_PAGES`, truncate from `startPage`.
  - `INPUT_BUFFER_CAP_BYTES` applies to SLICED output. Single-chapter overflow → `{ ok: false, error: "oversized_buffer" }`.
- 2.1.9 Tests in `apps/web-platform/test/pdf-text-extract.test.ts` (extend existing): outline happy / no-outline / too-shallow / timeout / dest-resolution-failure paths; page-range valid / invalid / over-MAX_PAGES / oversized-slice paths.

### 2.2 Resolver wiring (parallel — both files)

- 2.2.1 Extend `DocumentExtractMeta` (declared in `kb-document-resolver.ts`, imported by leader): add `chapters?: ChapterIndex[]` and `fullExtractedText?: string`.
- 2.2.2 In `kb-document-resolver.ts`, after the `oversized_buffer` + `extractPdfMetadata` block: if `meta.ok && meta.numPages > LARGE_PDF_PAGE_THRESHOLD`, ALSO call `extractPdfOutline(buffer)`. Branch:
  - `outlineResult.ok === true` → also call `extractPdfText(buffer, FULL_TEXT_CAP_BYTES)` (loose cap, e.g., 5MB chars). Return `{ documentExtractMeta: { numPages, chapters: outlineResult.outline, fullExtractedText } }` with NO `documentExtractError`.
  - `outlineResult.ok === false` → existing `too_many_pages` return.
- 2.2.3 In `leader-document-resolver.ts`, symmetric branch with same logic.
- 2.2.4 Tests: `apps/web-platform/test/kb-document-resolver-chapter-chunked.test.ts` (new) and `apps/web-platform/test/leader-document-resolver-chapter-chunked.test.ts` (new). Cover: oversized + outline-bearing → chapter-chunked shape; oversized + no outline → bridge directive; under-cap → existing inline path unchanged.

## 3. Phase 3 — Chapter routing + runner integration + tests

### 3.1 Chapter routing module

- 3.1.1 Create `apps/web-platform/server/pdf-chapter-router.ts` with single export `selectChapter`.
- 3.1.2 Type: `SelectChapterResult = { kind: "selected"; chapterIndex: number; alternates: number[] } | { kind: "ambiguous"; candidates: number[] } | { kind: "cost-cap-hit"; cap: number; totalCostUsd: number }`.
- 3.1.3 System prompt: "Pick the chapter most likely to contain the answer. Reply with just the chapter number (1-N), or AMBIGUOUS if multiple chapters apply." Numeric-index, NOT title-match (avoids LLM paraphrase trap).
- 3.1.4 Fallback: if numeric parse fails, fuzzy-match returned text against `outline[i].title` (Levenshtein < 0.3 of length); if no fuzzy match, return `{ kind: "ambiguous", candidates: [] }`.
- 3.1.5 Pin model to Sonnet 4.6 / 200K via constant in this module — do NOT inherit runner's model.
- 3.1.6 Routing-turn cost handling: add the routing turn's `total_cost_usd` to `state.totalCostUsd` BEFORE returning. If post-routing total >= cap, return `{ kind: "cost-cap-hit" }`.
- 3.1.7 BYOK key resolution via `runWithByokLease` ALS path.
- 3.1.8 Tests: `apps/web-platform/test/pdf-chapter-router.test.ts` (new). Cover: numeric-index happy path, AMBIGUOUS path, fuzzy-match-fallback path, cost-cap-hit path. Mock `query()` with deterministic responses.

### 3.2 Runner integration — Concierge (`soleur-go-runner.ts`)

- 3.2.1 Add constant `PDF_CHAPTER_CHUNKED_DIRECTIVE_LEAD = "This PDF is large but I have the table of contents."`
- 3.2.2 Add directive-consumer branch: when resolver returns `documentExtractMeta?.chapters?.length > 0` AND no `documentExtractError`, build inline directive (template string, no factory): "[Chapter list inline]. Use the loaded chapter (passed as content block) to answer the user's question."
- 3.2.3 First chapter-chunked turn (TOC overview): emit directive only; model produces "this book has chapters X, Y, Z."
- 3.2.4 Subsequent user-question turns within a chapter-chunked context (stateless — re-route every turn):
  - Call `selectChapter({ question, outline, userId, conversationCostState })`.
  - On `kind: "cost-cap-hit"` → emit existing `cost_ceiling` via `WorkflowEnded`. Done.
  - On `kind: "ambiguous"` → response = "I can answer from chapter [X] or chapter [Y] — which would you like?" Don't fire answer turn.
  - On `kind: "selected"`:
    - Slice via `extractPdfText(buffer, capChars, { startPage: outline[chapterIndex].startPage, endPage: outline[chapterIndex].endPage })`.
    - **If slice fails** (oversized_buffer / parse_error): response = "I have the TOC but chapter [X] failed to extract — try a different chapter or re-attach the PDF." **Refund the routing turn's cost from `state.totalCostUsd`** — do NOT charge for unsuccessful routing→extraction.
    - **If slice succeeds:** attach as `document` content block on user message with `cache_control: { type: "ephemeral" }` (gated on S1 GREEN; RED-S1 omits `cache_control`).
  - Fire answer turn.
  - Prepend `[Answering from chapter <chapterIndex>: "<title>"]` to response text before persisting + streaming.
- 3.2.5 **No `loadedChapter` server-side state.** Cache layer is the memory.
- 3.2.6 **System prompt byte-stability assertion:** capture system-prompt hash at first within-chapter turn; assert byte-identical on every subsequent within-chapter turn in the integration test. Fail-loud on drift.

### 3.3 Runner integration — Leader (`agent-runner.ts`)

- 3.3.1 Symmetric implementation to 3.2 in the leader PDF branch (post-#3442 lines 909-996).
- 3.3.2 Leader-specific: directive includes NO-ASK clause telling model "do not invoke Read on this PDF; the chapter content is provided in the user message."

### 3.4 Integration tests

- 3.4.1 `apps/web-platform/test/soleur-go-runner-chapter-chunked.test.ts`: full flow — TOC overview → routed answer (assert chapter prefix appears) → chapter switch (assert cache key changes, prefix updates) → ambiguous turn (assert no answer turn fires, no charge) → chapter-extraction failure (assert refund + recovery copy) → cap-hit mid-routing (assert `cost_ceiling` fires instead of answer).
- 3.4.2 `apps/web-platform/test/agent-runner-chapter-chunked.test.ts`: same scenarios for leader runner.
- 3.4.3 **GREEN-S1 only:** assertion that `cache_creation_input_tokens > 0` on first within-chapter turn and `cache_read_input_tokens > 0` on second. RED-S1 omits.
- 3.4.4 System-prompt byte-stability assertion in same-chapter turn sequence (3.2.6).

## 4. Pre-merge verification

- 4.1 Run full `bun test` suite — all pass.
- 4.2 Run S1 + S2 spike scripts; commit results to PR body verbatim.
- 4.3 Verify AC #4 has been edited to keep only the matching S1 branch (GREEN or RED).
- 4.4 Manual smoke test against an outline-bearing fixture PDF (S2's first fixture) end-to-end through Concierge: upload to KB, ask "summarize chapter 3" — verify content-grounded answer + chapter prefix + < 8s p95 round-trip.
- 4.5 Run multi-agent code review (`/soleur:review`).
- 4.6 Resolve all review findings inline (default fix-inline per `rf-review-finding-default-fix-inline`).
- 4.7 PR body includes:
  - `## User-Brand Impact` section (carry-forward from plan + brainstorm)
  - Link to brainstorm `## User-Brand Impact` for CPO sign-off carry-forward
  - S1 + S2 spike outcomes verbatim
  - Open Code-Review Overlap dispositions table
  - "Closes #3436" on its own body line (auto-close)
- 4.8 `user-impact-reviewer` agent invoked at PR review and signs off (pre-merge gate per `hr-weigh-every-decision-against-target-user-impact`).
- 4.9 Set semver label: `semver:minor` (new functional capability — chapter-chunked resolution path).

## 5. Post-merge

- 5.1 Monitor `cost_ceiling` event rate for 1 week; flag any single chapter-Q&A conversation hitting cap.
- 5.2 Monitor outline-unusable rate for `LARGE_PDF_PAGE_THRESHOLD`+ PDFs; > 30% → file tuning issue.
- 5.3 **GREEN-S1 only:** log cache hit rate over 1 week; < 50% → file follow-up.
- 5.4 Update #3454 body to note chapter-chunking widened the agent-native gap (outline now a server-internal fact); link to merged PR.
