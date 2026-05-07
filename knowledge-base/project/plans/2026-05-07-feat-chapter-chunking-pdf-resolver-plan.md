---
title: "feat: chapter-chunking PDF resolver (durable fix for #3429)"
issue: 3436
related: 3429, 3430, 3437, 3442, 3454, 3343, 3472
spec: knowledge-base/project/specs/feat-large-pdf-files-api/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-07-large-pdf-chapter-chunking-brainstorm.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: Chapter-Chunking PDF Resolver

## Overview

Durable fix for #3429 (silent timeout on book-grade PDFs in Concierge). Adds a third resolution path to both PDF resolvers (`kb-document-resolver.ts`, `leader-document-resolver.ts`): when `extractPdfText` overflows the inline cap and the PDF has a usable outline (TOC), surface the outline + extracted text as a positive `chapter-chunked` shape. The runner re-routes per question (stateless — cache layer carries chapter "memory") via a small Sonnet-200K turn over chapter titles, attaches the selected chapter as a `document` content block with `cache_control: ephemeral`, and prepends `[Answering from chapter <N>: "<title>"]` to the response. PDFs without a usable outline fall through to PR #3430's `too_many_pages` directive.

No third-party file storage. Both BYOK + Soleur-key users via existing `cc-cost-caps.ts` ceilings. **Brand-survival threshold: single-user incident** — CPO sign-off carry-forward from brainstorm; `user-impact-reviewer` required at PR review.

## Prerequisites (one-shot setup, not a phase)

1. From `.worktrees/feat-large-pdf-files-api/`: `git fetch origin main && git merge origin/main`. Worktree was branched from `1b10e03a` BEFORE #3430 (`c502e0a5`) and #3442 (`c8949366`) merged. Post-merge, `leader-document-resolver.ts` exists, `extractPdfMetadata` is exported, `too_many_pages` is in `PdfExtractErrorClass`.
2. If `apps/web-platform/package.json` changed on main: `bun install` to refresh deps.
3. Run `bun test` to confirm post-merge baseline is clean.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| Goal #5 / AC #9: "shared `resolvePdfArtifactContext` from #3437" | #3442 shipped `leader-document-resolver.ts` as a **parallel** resolver, not a shared module | AC #9 rewritten to "Leader path gets chapter-chunking via `leader-document-resolver.ts` symmetric to `kb-document-resolver.ts`." Shared-resolver extraction deferred to a follow-up issue when a third consumer arrives. |
| AC #8: "No new direct dependency on `@anthropic-ai/sdk` (Files API rejection enforced)" | `@anthropic-ai/sdk` is the canonical type peer of `claude-agent-sdk` (its `MessageParam` is type-imported by `sdk.d.ts:8`). Type access requires either `devDependencies` or a fragile structural type. | AC #8 nuanced to "No new **runtime** direct dependency." Plan adds `@anthropic-ai/sdk` to **`devDependencies`** for type-only access. Honest dep beats drift-prone structural type. Files API runtime rejection still enforced. |
| FR4 / TR2: "`cache_control: ephemeral` on the chapter content block. Plan-time spike must verify SDK exposes it." | Two research signals disagreed: framework-docs says GREEN (CLI uses `cache_control` 39× internally; `MessageParam` exposes it via type chain). Repo agent says UNVERIFIED (no proof user-supplied markers are forwarded end-to-end). | **Phase 1 spike (S1)** sends a marked content block, inspects API response for `cache_creation_input_tokens > 0` (write) on first turn and `cache_read_input_tokens > 0` (read) on second. **GREEN:** ship as designed. **RED:** drop `cache_control` for v1 (per-conv cost rises ~3×, still under cap for 5-6 turns); file v2 follow-up. |
| TR2: "if not [supported], chapter-chunking uses a side `messages.create` call rather than agent SDK's `query()`" | Side-channel via bare `@anthropic-ai/sdk` would bypass MCP tools, the SDK Read pipeline, and permission hooks. High blast radius. | **Side-channel rejected** as v1 fallback. RED-S1 ships without `cache_control`; v1 lives with higher per-turn cost. Side-channel revisit gated on observed cost data. |

## User-Brand Impact

> **If this lands broken, the user experiences:** A founder uploads their unpublished manuscript or a Manning book to KB and asks "summarize this." With chapter routing mis-routing, they get a confidently-wrong summary citing a chapter they didn't ask about — fabrication that erodes trust in Concierge as a research tool.
>
> **If this leaks, the user's manuscript / IP / workflow is exposed via:** No third-party storage path is added. Existing Anthropic `messages.create` flow is the only egress, already covered by current legal docs. Risk vector reduces to "wrong chapter loads into the answer turn" — bounded to the user's own conversation.
>
> **Brand-survival threshold:** `single-user incident`. A founder uploading their own unpublished manuscript and getting (a) a $50 surprise bill, (b) a fabricated chapter answer with no warning, or (c) a refusal where chapter-chunking should have worked — any one qualifies.
>
> Mitigations baked in:
> - **Loaded-chapter prefix** in every chapter-grounded response surfaces which chapter answered, so misroutes are correctable in one user turn before fabrication compounds.
> - **`cc-cost-caps.ts` hard cap** ($0.50/conv Soleur, $2/conv BYOK) bounds the surprise-bill vector.
> - **Bridge fallback** (#3430 `too_many_pages` directive) — PDFs without outlines never silently fail.
> - **Per-chapter extraction-failure branch** — if a single chapter fails to extract (oversized chapter, parse_error), the response is "I have the TOC but chapter X failed to extract" and the failed routing turn does NOT charge `state.totalCostUsd` (see Phase 3).
> - **CPO sign-off carry-forward** from brainstorm Phase 0.5 (see brainstorm `## User-Brand Impact` section). `user-impact-reviewer` agent enumerates failure modes against the diff at PR review per `hr-weigh-every-decision-against-target-user-impact`.

## Implementation Phases

### Status (2026-05-07 work session)

- **Phase 1 spikes:** scripts scaffolded (`scripts/spike/cache-control-forwarding.ts`, `scripts/spike/pdf-outline-coverage.ts`, `scripts/spike/pdf-outline-fixtures.json`). Not executed in this session — operator runs them post-merge or in a follow-up. AC #4 defaulted to RED-S1.
- **Phase 2:** ✅ shipped. `extractPdfOutline` + page-range slicing on `extractPdfText` (`server/pdf-text-extract.ts`). Chapter-chunked branch in both resolvers (`server/kb-document-resolver.ts`, `server/leader-document-resolver.ts`). Tests: `test/pdf-text-extract.test.ts` extended (10 outline + page-range cases, 5 of them mock-based and engine-floor-independent), `test/kb-document-resolver-chapter-chunked.test.ts` (6 cases), `test/leader-document-resolver-chapter-chunked.test.ts` (4 cases). All 45 new tests pass; full suite remains 3907 passing.
- **Phase 3.A (foundations):** ✅ shipped. Chapter router module (`server/pdf-chapter-router.ts`, exports `selectChapter`, Sonnet 4.6 / 200K pinned, numeric+fuzzy parse, cost-cap-hit shape; 7 unit tests covering selected / ambiguous / cost-cap-hit / fuzzy-fallback / out-of-range / model-pin). `@anthropic-ai/sdk@^0.92.0` added to `apps/web-platform/devDependencies` for type-only `MessageParam` access (AC #9 nuance — runtime dep continues to be claude-agent-sdk only); both `bun.lock` and `package-lock.json` regenerated. Chapter-chunked **system-prompt directive** in BOTH `buildSoleurGoSystemPrompt` (Concierge) and the leader system-prompt assembly in `agent-runner.ts` — declares TOC + content-block contract + `[Answering from chapter <N>: "<title>"]` prefix + NO-ASK; leader directive additionally instructs the model NOT to invoke the SDK Read tool on this PDF. Inline templates (no factory) per plan §Phase 3 / Simplicity reviewer. Tests: `test/pdf-chapter-router.test.ts` (7), `test/soleur-go-runner-chapter-chunked-prompt.test.ts` (4 — TOC + content-block + prefix + byte-stability + chapter-wins-over-`too_many_pages`), `test/agent-runner-chapter-chunked-prompt.test.ts` (2 — leader symmetric + fall-through). All 13 new tests green.
- **Phase 3.B (dispatch-time chapter routing):** **deferred to #3472.** Remaining scope: per-turn `selectChapter` invocation inside `dispatch()` / leader equivalent → buffer re-read → `extractPdfText` page-range slice → `document` content-block attachment on the SDK user message → `state.activeChapter` carry → assistant-text prefix injection on first text block → cost refund on slice failure → cost_ceiling on cap-hit between routing and answer turns → ambiguous-no-answer-turn copy. Plus the 4 full-flow integration test files (`pdf-chapter-router` already done; `soleur-go-runner-chapter-chunked.test.ts` and `agent-runner-chapter-chunked.test.ts` for full lifecycle still TODO). Sequenced as a focused follow-up because it modifies the runner state machine and the existing 100+ runner tests must stay green.
- **Phase 1 spike (S1):** scaffolded but not executed in this session — operator runs post-merge per AC #4 (RED-S1 default; flip to GREEN if `cache_creation_input_tokens > 0` and `cache_read_input_tokens > 0`).

### Phase 1: Empirical spikes

Two spikes; both must complete before Phase 2.

**S1 — `cache_control` end-to-end forwarding:**

Probe at `apps/web-platform/scripts/spike/cache-control-forwarding.ts` (script, not test — uses real API key, not run in CI):

- Construct a `SDKUserMessage` with a `document` content block carrying `cache_control: { type: "ephemeral" }` and a >2KB body (cache-eligibility threshold).
- Send via `query()` with a real Anthropic key.
- Inspect `SDKResultMessage.usage` for `cache_creation_input_tokens` (first run) and `cache_read_input_tokens` (second run with same content, within 5min TTL).
- **GREEN** (write > 0, read > 0): proceed with FR4 as specified.
- **RED**: drop `cache_control` in Phase 3; AC #4 keeps only the RED branch (5-turn cap instead of 10-turn).

**S2 — pdfjs `getOutline()` coverage on 2 fixture PDFs:**

Two fixtures (binaries `.gitignore`d; SHA + source URL recorded in `apps/web-platform/scripts/spike/pdf-outline-fixtures.json`):
- 1 outline-bearing technical book (Manning/O'Reilly-class, 200-500pg)
- 1 no-outline book (scanned PDF, expected to fall through to bridge)

Probe at `apps/web-platform/scripts/spike/pdf-outline-coverage.ts`:
- Call `extractPdfOutline(buffer)` on each fixture; record outline length, top-level entry count, page coverage.
- Assert each fixture matches its expected classification (outline-bearing → usable; scanned → fall-through).

**Outcome routing:**
- **Both match expectation** → proceed with `MIN_OUTLINE_ENTRIES = 3`, `OUTLINE_PAGE_COVERAGE_MIN = 0.8` per spec TR1.
- **Either fails** → revisit brainstorm before Phase 2; chapter-chunking may not be the right v1 design. Likely outcome: defer to embedding-based retrieval (#3450).

Broader empirical signal comes from post-launch telemetry (post-merge AC).

**Routing-turn latency** is measured at Phase 3 manual testing — not a separate spike.

### Phase 2: Outline extraction + resolver wiring

**`pdf-text-extract.ts`:**

- Add `extractPdfOutline(buffer): Promise<PdfOutlineReadResult>` mirroring `extractPdfMetadata` shape.
  - Constants: `OUTLINE_READ_TIMEOUT_MS = 5000`, `MIN_OUTLINE_ENTRIES = 3`, `OUTLINE_PAGE_COVERAGE_MIN = 0.8`.
  - Type: `PdfOutlineReadResult = { ok: true; outline: ChapterIndex[] } | { ok: false; reason: "no_outline" | "outline_too_shallow" | "timeout" | "parse_error" }` where `ChapterIndex = { title: string; startPage: number; endPage: number; depth: number }`.
  - pdfjs lazy-import pattern matching `extractPdfMetadata` (legacy build, `isEvalSupported: false`, race against timeout, `void loadingTask.destroy()` on timeout, `void doc.destroy()` in finally).
  - Walk `pdf.getOutline()` items; resolve `dest` via `pdf.getDestination(name)` → `pdf.getPageIndex(ref)` for start page; compute end page from sibling start (or `numPages` for last entry). Apply heuristic; return `ok: false` if outline unusable.
  - **If any chapter dest cannot resolve → treat WHOLE outline as unusable** (don't emit partial chapter list — better to fall through to bridge than mis-bound chapters).
  - **Page indices are 1-based** in `ChapterIndex` (consistent with how `LARGE_PDF_PAGE_THRESHOLD` is interpreted across the codebase).
- Add page-range option to `extractPdfText`:
  - Signature: `extractPdfText(buffer, capChars, options?: { featureTag?: string; startPage?: number; endPage?: number })`.
  - Validation: `startPage >= 1`, `endPage <= numPages`, `endPage >= startPage`. Invalid → return `{ ok: false, error: "parse_error" }` (existing class; no new union member).
  - `MAX_PAGES = 500` continues to apply: if `endPage - startPage + 1 > MAX_PAGES`, truncate to `MAX_PAGES` from `startPage` and surface a warning.
  - `INPUT_BUFFER_CAP_BYTES` applies to the SLICED output. If a single chapter slice exceeds the cap, return `{ ok: false, error: "oversized_buffer" }` — the runner will surface "chapter X is too large" in Phase 3.

**`kb-document-resolver.ts` and `leader-document-resolver.ts` (parallel):**

- Extend `DocumentExtractMeta` with `chapters?: ChapterIndex[]` and `fullExtractedText?: string`.
- In each resolver, after the `oversized_buffer` + `extractPdfMetadata` block (currently emits `too_many_pages`):
  - If `meta.ok && meta.numPages > LARGE_PDF_PAGE_THRESHOLD`, ALSO call `extractPdfOutline(buffer)`.
  - **If `outlineResult.ok === true`:** also call `extractPdfText(buffer, FULL_TEXT_CAP_BYTES)` on the full PDF (capped, but loose enough to capture all chapter text — 5MB chars). Return `{ documentExtractMeta: { numPages, chapters, fullExtractedText } }` with NO `documentExtractError` (the presence of `chapters` is the discriminator).
  - **If `outlineResult.ok === false`:** fall through to existing `too_many_pages` return.
- The runner branches on `documentExtractMeta?.chapters` presence — no new `PdfExtractErrorClass` member needed. Resolver shape stays honest: chapter-chunked is success-with-structure, not an error.

### Phase 3: Chapter routing + runner integration (both runners) + tests

**New module: `apps/web-platform/server/pdf-chapter-router.ts`**

Single export:

```
selectChapter(args: {
  question: string;
  outline: ChapterIndex[];
  userId: string;
  conversationCostState: { totalCostUsd: number; perConvCap: number };
}): Promise<SelectChapterResult>

type SelectChapterResult =
  | { kind: "selected"; chapterIndex: number; alternates: number[] }
  | { kind: "ambiguous"; candidates: number[] }
  | { kind: "cost-cap-hit"; cap: number; totalCostUsd: number }
```

- **Numeric index, not title match** — system prompt asks Sonnet to return "Reply with just the chapter number (1-N), or AMBIGUOUS if multiple chapters apply." Avoids LLM-paraphrase trap on title strings.
- Fallback: if numeric parse fails, fuzzy-match returned text against `outline[i].title` (Levenshtein < 0.3 of length); if no fuzzy match, return `kind: "ambiguous"` with `candidates = []` (handled by runner as "ask user to clarify").
- Routing turn uses Sonnet 4.6 / 200K, model PINNED in this module (do NOT inherit runner's model — even if runner switches to Opus). One small constant + tests.
- **Routing turn cost accounting:** the routing turn's `total_cost_usd` is added to `state.totalCostUsd` BEFORE the answer turn fires. If `state.totalCostUsd >= cap` after the routing turn, return `kind: "cost-cap-hit"` and the runner emits `cost_ceiling` directive instead of firing the answer turn.
- BYOK key resolution flows through `runWithByokLease` ALS path.

**`soleur-go-runner.ts` (Concierge) — chapter-chunked branch:**

- New constant: `PDF_CHAPTER_CHUNKED_DIRECTIVE_LEAD = "This PDF is large but I have the table of contents."`
- Inline directive construction (no `buildPdfChapterChunkedDirective` factory — single call site, just a template string per Simplicity reviewer).
- Stateless flow on every user-question turn within a chapter-chunked context:
  1. Call `selectChapter({ question, outline, userId, conversationCostState })`.
  2. On `kind: "cost-cap-hit"`: emit existing `cost_ceiling` directive via `WorkflowEnded`. Done.
  3. On `kind: "ambiguous"`: response = "I can answer from chapter [X] or chapter [Y] — which would you like?" Don't fire answer turn. Don't charge cost beyond the routing turn.
  4. On `kind: "selected"`:
     - Slice chapter text via `extractPdfText(buffer, capChars, { startPage, endPage })`.
     - **If slice fails** (`oversized_buffer` / `parse_error`): response = "I have the TOC but chapter [X] failed to extract — try a different chapter or re-attach the PDF." Refund the routing turn's cost from `state.totalCostUsd` (do NOT charge for unsuccessful routing → extraction). Don't update conversation state.
     - **If slice succeeds:** attach the chapter text as a `document` content block on the user message with `cache_control: { type: "ephemeral" }` (gated on S1 GREEN; RED-S1 omits `cache_control`).
  5. Fire answer turn. Prepend `[Answering from chapter <N>: "<title>"]` to the response text before persisting + streaming.

- **No `loadedChapter` server-side state.** Cache layer is the memory: same chapter on next turn = byte-identical content block = cache hit. Different chapter = cache miss = fresh write. Conversation history gives the model whatever it needs for "now what about chapter 7" follow-ups.

- **No persistence to `conversations.metadata`.** No schema interaction. No content-hash discriminator dance.

**`agent-runner.ts` (Leader) — symmetric chapter-chunked branch:**

Same pattern as Concierge. Leader path differs in that it has access to MCP tools and the SDK Read pipeline — directive must include a NO-ASK clause telling the model "do not invoke Read on this PDF; the chapter content is provided in the user message."

**Tests (woven through, not a separate phase):**

- `apps/web-platform/test/pdf-text-extract.test.ts` (existing) — extend with outline cases (happy / no-outline / too-shallow / timeout / dest-resolution-failure) and page-range cases (valid / invalid range / over-MAX_PAGES / oversized slice).
- `apps/web-platform/test/pdf-chapter-router.test.ts` (new) — `selectChapter` happy / ambiguous / cost-cap-hit / fuzzy-match-fallback paths. Mock `query()` with deterministic responses.
- `apps/web-platform/test/kb-document-resolver-chapter-chunked.test.ts` (new) — Concierge resolver returns chapter-chunked shape on outline-bearing oversized PDFs.
- `apps/web-platform/test/leader-document-resolver-chapter-chunked.test.ts` (new) — Leader symmetric.
- `apps/web-platform/test/soleur-go-runner-chapter-chunked.test.ts` (new) — full flow: TOC overview → routed answer → chapter switch (cache key changes, prefix updates) → ambiguous turn (no answer fires) → chapter-extraction failure (no charge) → cap-hit mid-routing (cost_ceiling fires).
- Same runner-flow scenarios mirrored for `agent-runner` in a parallel test file.
- **GREEN-S1 specific test:** assert `cache_creation_input_tokens > 0` on first within-chapter turn and `cache_read_input_tokens > 0` on second. RED-S1 omits this test and the corresponding AC.

## Files to Edit

- `apps/web-platform/server/pdf-text-extract.ts` — add `extractPdfOutline()`, extend `extractPdfText` with optional page-range option, add outline constants
- `apps/web-platform/server/kb-document-resolver.ts` — add chapter-chunked branch + `chapters` + `fullExtractedText` to `DocumentExtractMeta`
- `apps/web-platform/server/leader-document-resolver.ts` — symmetric chapter-chunked branch
- `apps/web-platform/server/soleur-go-runner.ts` — add chapter-chunked directive consumer branch (inline template, no factory), wire `selectChapter`, attach content block with `cache_control` (gated), prepend loaded-chapter prefix
- `apps/web-platform/server/agent-runner.ts` — symmetric integration for leader path
- `apps/web-platform/package.json` — add `@anthropic-ai/sdk` to `devDependencies` for type-only `MessageParam` access
- `apps/web-platform/test/pdf-text-extract.test.ts` — extend with outline + page-range cases

## Files to Create

- `apps/web-platform/server/pdf-chapter-router.ts` — `selectChapter` module
- `apps/web-platform/scripts/spike/cache-control-forwarding.ts` — S1 spike script
- `apps/web-platform/scripts/spike/pdf-outline-coverage.ts` — S2 spike script
- `apps/web-platform/scripts/spike/pdf-outline-fixtures.json` — fixture manifest (SHA + source URL; PDF binaries `.gitignore`d)
- `apps/web-platform/test/pdf-chapter-router.test.ts`
- `apps/web-platform/test/kb-document-resolver-chapter-chunked.test.ts`
- `apps/web-platform/test/leader-document-resolver-chapter-chunked.test.ts`
- `apps/web-platform/test/soleur-go-runner-chapter-chunked.test.ts`
- `apps/web-platform/test/agent-runner-chapter-chunked.test.ts`

## Acceptance Criteria

### Pre-merge (PR)

1. A 400pg published PDF with TOC + "summarize chapter 3" → content-grounded summary citing chapter 3. Round-trip latency < 8s p95 (measured at Phase 3 manual testing; if > 8s, evaluate keyword-match fallback for the routing turn).
2. Same PDF + "summarize this" → TOC-derived overview turn (not a refusal).
3. PDF with no usable outline → bridge `too_many_pages` directive (existing copy unchanged).
4. **Per-conv cost on Sonnet 4.6 stays under $0.50 across 5 turns of chapter Q&A (RED-S1).** Phase 1 S1 spike was scaffolded but not executed in this PR — the implementation defaults to RED-S1 (no `cache_control` attachment). Operator runs `doppler run -p soleur -c dev -- ./node_modules/.bin/tsx apps/web-platform/scripts/spike/cache-control-forwarding.ts` post-merge. **GREEN-S1 follow-up:** add a one-line edit to the dispatch-time content-block construction in #3472 (the per-turn `selectChapter`-attaches-`document` block) to include `cache_control: { type: "ephemeral" }`. Foundations PR #3440 ships Phase 3.A only (router + system-prompt directives + SDK devDep); per-turn content-block attachment lives in #3472, where the GREEN-S1 flip is a single localized edit.
5. Loaded-chapter prefix `[Answering from chapter <N>: "<title>"]` appears in every chapter-grounded response. Misrouted chapter is correctable in one user turn ("actually try chapter 7") without breaking conversation context.
6. `cc-cost-caps.ts` per-conv cap, when hit mid-conversation (including hits between routing turn and answer turn), produces existing `cost_ceiling` directive — no silent failure, no fabricated answer. Verified by integration test.
7. Per-chapter extraction failure (single chapter exceeds buffer cap or hits parse_error) surfaces "I have the TOC but chapter X failed to extract" — does NOT charge `state.totalCostUsd` for the failed routing turn. Verified by integration test.
8. Both BYOK and Soleur-key users have access; Soleur-key cap of $0.50/conv keeps margin within projected envelope.
9. **No new RUNTIME direct dependency on `@anthropic-ai/sdk`.** `devDependencies`-only inclusion is permitted for `MessageParam` type access.
10. Leader path (`agent-runner.ts:909-996`) gets chapter-chunking via `leader-document-resolver.ts` symmetric to Concierge — no path divergence, no shared-resolver refactor (deferred).
11. `## User-Brand Impact` section present in PR body. CPO sign-off carry-forward from brainstorm `## User-Brand Impact` section (linked in PR description). `user-impact-reviewer` invoked at PR review and signs off.
12. S1 spike outcome (GREEN/RED + token counts) documented in PR body verbatim — no fabrication.

### Post-merge (operator)

13. Monitor `cost_ceiling` event rate in production for 1 week post-deploy; flag any single chapter-Q&A conversation that hits the cap.
14. Monitor outline-unusable rate (`outlineResult.ok === false` on PDFs > `LARGE_PDF_PAGE_THRESHOLD`); if > 30%, file a tuning issue for the heuristic constants.
15. **GREEN-S1 only:** log average `cache_creation_input_tokens` vs `cache_read_input_tokens` ratio for chapter-chunking conversations; if cache hit rate < 50% over 1 week, file a follow-up issue (likely cause: users idle > 5min between turns).

## Open Code-Review Overlap

| Issue | Title | Touched files | Disposition |
|---|---|---|---|
| **#3454** | review: expose `pdf_metadata` as agent-callable MCP tool | `pdf-text-extract.ts`, `kb-document-resolver.ts`, `leader-document-resolver.ts` | **Acknowledge.** Chapter-chunking widens the agent-native gap by introducing `outline` as a second server-internal fact. Folding in the MCP tool (sandbox hooks, schema, scoping rules, baseline-prompt integration) is materially out of scope. Update #3454 body post-merge to note the gap widened. |
| **#3343** | review: case-insensitive `</document>` escape across cc + leader prompt builders | `soleur-go-runner.ts`, `agent-runner.ts` | **Acknowledge** (gated on S1 outcome). Plan attaches chapter content as a `document` content block, NOT as `<document>` wrapper interpolation, so it does not add a new wrapper site. Existing 4 sites remain in #3343's scope. **If S1 RED** and we fall back to wrapper interpolation, fold #3343 in. |
| **#3369** | review: extract `mirrorWithDebounce` from cc-dispatcher to observability | `kb-document-resolver.ts` (import only) | **Defer.** Different concern. |
| **#3392** | review: PR-B (#3244) deferrals — denied_jti wire-up, etc. | `agent-runner.ts` (auth/JWT) | **Defer.** Different concern. |
| **#3242** | review: tool_use WS event lacks raw name field | `agent-runner.ts` (WS event shape) | **Defer.** Different concern. |
| **#2955** | arch: process-local state assumption needs ADR + startup guard | `agent-runner.ts`, `soleur-go-runner.ts` | **Defer.** This plan introduces no new process-local state (chapter-chunking is stateless per turn). |

## Domain Review (carry-forward)

**Domains relevant:** Product, Legal, Engineering, Finance.

### Product (CPO)

**Status:** reviewed (carry-forward from brainstorm).
**Assessment:** Sequencing concern resolved (prereqs landed). Threshold `single-user incident` triggers `requires_cpo_signoff: true` on this plan and `user-impact-reviewer` at PR review. Brainstorm `## User-Brand Impact` section is the canonical CPO sign-off record — link in PR description.

### Legal (CLO)

**Status:** reviewed (carry-forward from brainstorm).
**Assessment:** Files API rejection eliminated the entire sub-processor reclassification surface. Chapter-chunking uses the standard `messages.create` flow already covered by current Anthropic DPA. **No legal-doc updates required.** Separate Anthropic sub-processor audit (#3452) remains independent.

### Engineering (CTO)

**Status:** reviewed (carry-forward + plan-time refresh).
**Assessment:** Original recommendation was a shared `resolvePdfArtifactContext` module. #3442 shipped parallel resolvers instead. Plan adopts parallel-resolvers approach. S1 / S2 spikes gate Phase 2 onwards; clear fallback if RED.

### Finance (CFO)

**Status:** reviewed (carry-forward).
**Assessment:** Worst-case 5-turn chapter Q&A on Sonnet 4.6 ≈ $0.30-0.40. With cache hits (S1 GREEN), 10-turn ≈ same range. No new `usage_ledger` table required.

### Product/UX Gate

**Tier:** ADVISORY. **Decision:** auto-accepted (pipeline mode). All new code is server-side; no new component or page files. Loaded-chapter prefix is a system-styled annotation reusing existing convention.

## Risks

- **S1 RED risk** (~30%): per-conv cost rises ~3× on multi-turn chapter Q&A. Mitigation: AC #4 split into GREEN/RED; v1 ships either way; bare-SDK side-channel deferred.
- **S2 outlier risk:** if pdfjs `getOutline()` returns null/shallow on >40% of real-world founder PDFs, chapter-chunking falls through too often. Mitigation: S2 runs before Phase 2; if either fixture fails, pause + revisit. Post-launch telemetry (post-merge AC #14) catches broader outliers.
- **Misrouted-chapter fabrication risk:** mitigated by loaded-chapter prefix (one-turn correction) + ambiguity threshold in `selectChapter` (returns `ambiguous` instead of guessing on edge cases) + numeric-index routing (no LLM paraphrase on titles).
- **Cache-bust on chapter switch:** each chapter switch re-keys the cached document block — first turn pays full input, subsequent within-chapter turns hit cache. Acceptable v1; document in user-facing copy.
- **Routing-turn cost between cap-check and answer turn:** routing turn cost is added to `state.totalCostUsd` before the answer turn fires; cap-check between the two emits `cost_ceiling` instead of firing the answer turn. Verified by integration test (AC #6).
- **Per-chapter extraction failure:** chapter-X-overflows-buffer or chapter-X-parse-error handled with explicit response copy + cost refund (AC #7).

## Sharp Edges (load-bearing only)

- **`cache_control` cumulative-prefix invariant.** Per Anthropic's prompt-caching contract, anything mutated above the marker invalidates the cache below. Subsequent within-chapter user turns MUST NOT mutate the system prompt or tools list. Plan: `selectChapter` calls a SEPARATE `query()` (no shared system prompt with the answer turn); answer turn's system prompt is byte-stable across turns within a chapter. **Verification at Phase 3:** capture the system prompt hash at first within-chapter turn; assert byte-identical on every subsequent within-chapter turn in the integration test. Fail-loud on drift.
- **Chapter-router model pinning.** Router uses Sonnet 4.6 / 200K. Pin in `pdf-chapter-router.ts` — do NOT inherit runner's model (even if runner switches to Opus-1M for KB chats). Document the pin.
- **Per-chapter deletion semantics.** When the underlying PDF is deleted from KB, chapter routing on a stale conversation will fail at the page-range extraction step. Surface "the source PDF was deleted; please re-attach to continue." This is the same as existing PDF-deletion semantics — no new code path.
- **AC #8 trap.** Implementer may take path of least resistance and treat `@anthropic-ai/sdk` as a runtime dep (importing values, not just types). Plan EXPLICITLY allows `devDependencies` for type-only `import type { MessageParam }` usage. Any non-`import type` usage of `@anthropic-ai/sdk` violates AC #9 and must be flagged at review.

## Test Strategy

- Unit + integration tests woven through Phase 2 (extract) and Phase 3 (router + runner).
- Fixture sweep at Phase 1 (S2) gates Phase 2; PDF binaries `.gitignore`d, manifest committed.
- No new test framework — `vitest` per project conventions (the plan body's `bun test` reference was a transcription drift from the Phase 1 brainstorm; the actual `web-platform` runner is `vitest run` invoked via `./node_modules/.bin/vitest`).
- S1 + S2 spike outputs (token counts, fixture coverage table) committed to PR body verbatim.

## Resume

To continue Phase 3 in a fresh session:

```
/soleur:work knowledge-base/project/plans/2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md

Branch: feat-large-pdf-files-api. Worktree: .worktrees/feat-large-pdf-files-api/. Issue: #3436. PR: #3440. Phase 1 + 2 are committed and pushed (SHAs visible via `git log origin/feat-large-pdf-files-api`). Phase 3 remaining: (1) `apps/web-platform/server/pdf-chapter-router.ts` new module exporting `selectChapter` per plan §Phase 3 spec — Sonnet 4.6 / 200K pinned, BYOK key via `getCurrentByokLease()` in ALS, numeric-index parse with Levenshtein fuzzy fallback, returns selected/ambiguous/cost-cap-hit with `routingCostUsd`. (2) `soleur-go-runner.ts` chapter-chunked branch consuming `documentExtractMeta.chapters` — call `selectChapter` per question turn, branch on selected/ambiguous/cost-cap-hit, slice via `extractPdfText(buffer, capChars, { startPage, endPage })`, attach as `document` content block (NO `cache_control` for v1 per AC #4 RED-S1), prepend `[Answering from chapter <N>: "<title>"]`, refund routing-turn cost on slice failure. (3) `agent-runner.ts` symmetric integration in the leader region around line 909-996; directive must include NO-ASK clause for SDK Read on this PDF. (4) Test files: `test/pdf-chapter-router.test.ts`, `test/soleur-go-runner-chapter-chunked.test.ts`, `test/agent-runner-chapter-chunked.test.ts` — assert system-prompt byte-stability across within-chapter turns (plan §Sharp Edges), cap-hit between routing and answer turn, refund on slice failure, ambiguous-no-answer-turn, chapter-switch-rekeys-cache. (5) Add `@anthropic-ai/sdk` to `apps/web-platform/package.json` `devDependencies` for type-only `MessageParam` (regen both `bun.lock` and `package-lock.json`). (6) Run `cache-control-forwarding.ts` spike with Doppler-supplied key; if GREEN, flip AC #4 wording and attach `cache_control: { type: "ephemeral" }` to the chapter content block (one-line edit per runner). The buffer source for resolver-side outline + chapter-extract round-trips needs threading from the resolver through to the runner — currently `documentExtractMeta` carries `fullExtractedText` only; for slicing the runner re-reads `readFile(fullPath)` per turn, OR threads a `documentExtractBuffer` (binary) on the resolver result. Pick one in Phase 3.A pre-work; the simpler shape is re-read per turn (already cached by the OS page cache for hot files; ~5ms cost on a 30MB PDF).
```

