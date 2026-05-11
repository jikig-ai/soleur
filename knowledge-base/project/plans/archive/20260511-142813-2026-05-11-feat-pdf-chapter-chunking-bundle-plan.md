---
title: "feat: PDF chapter-chunking Phase 3.B + S1/S2 spikes bundle (#3472, #3473, #3474)"
issues:
  - 3472
  - 3473
  - 3474
related:
  - 3436   # CLOSED parent
  - 3440   # MERGED 2026-05-07 — Phase 3.A foundations
  - 3450   # embedding retrieval (S2 RED pivot target)
  - 3454   # pdf_metadata MCP tool (acknowledged)
  - 3343   # </document> escape (acknowledged, gated on S1)
parent_plan: knowledge-base/project/plans/2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-07-large-pdf-chapter-chunking-brainstorm.md
parent_spec: knowledge-base/project/specs/feat-large-pdf-files-api/spec.md
bundle_brainstorm: knowledge-base/project/brainstorms/2026-05-11-pdf-chapter-chunking-bundle-brainstorm.md
bundle_spec: knowledge-base/project/specs/feat-pdf-chapter-chunking-bundle/spec.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_user_impact_reviewer: true
branch: feat-pdf-chapter-chunking-bundle
worktree: .worktrees/feat-pdf-chapter-chunking-bundle/
draft_pr: 3550
type: feature
---

# Bundle Plan: PDF Chapter-Chunking Phase 3.B + S1/S2 Spikes

## Overview

Single PR (`feat-pdf-chapter-chunking-bundle`, draft #3550) that bundles three mutually-dependent issues:

- **#3472** — Phase 3.B dispatch-time chapter routing (re-introduce the chapter-chunked system-prompt directive in both runners, wire `selectChapter` per turn, attach the chapter as a `document` content block, prepend `[Answering from chapter N: "<title>"]`, refund on slice failure, mirror in Leader path).
- **#3473** — S1 spike (`cache_control` end-to-end forwarding probe). One-line dispatch gating.
- **#3474** — S2 spike (pdfjs `getOutline()` coverage on 2 fixture PDFs). Confirms the `MIN_OUTLINE_ENTRIES = 3` / `OUTLINE_PAGE_COVERAGE_MIN = 0.8` heuristic or forces a Phase 1 pivot to embedding retrieval (#3450).

**Why one PR, not three:** the spikes are scripts already shipped by Phase 3.A (PR #3440); their outputs gate exactly two lines of dispatch code. Bundling 30 minutes of operator script-running into the implementation PR collapses three operator-driven follow-throughs to one merge and removes the risk that S1 GREEN never propagates post-merge. Decision driver, alternatives considered, and dispositions are recorded in the bundle brainstorm §Why Bundle, Not Stage.

**Why this is brand-survival load-bearing:** Phase 3.A (PR #3440) deliberately **reverted** the chapter-chunked system-prompt directive in both runners after the multi-agent review classified the directive-without-delivery state as a `single-user incident` regression. Today, oversized PDFs with usable outlines silently fall through to PR #3430's `too_many_pages` bridge. This bundle revives the directive AND wires its dispatch counterpart in a single atomic commit (TR4 → AC #18). No intermediate commit on the branch carries the directive without the matching content-block attachment.

This plan is a focused extension of the parent plan (`2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md`). All Phase 3 implementation detail, model pinning, sanitization, error-class taxonomy, and ALS/BYOK plumbing carry forward verbatim per KD-8. The four refresh-surfaced deltas (KD-2/3/5/6) and three bundle-shape deltas (KD-1/7 + TR4) are the new content here.

## Research Reconciliation — Spec vs. Codebase

Carry-forward verbatim from parent plan §Research Reconciliation (4 rows: shared-resolver, devDep type-only, `cache_control` S1 gating, side-channel rejection). No new spec/codebase mismatches surfaced by the 2026-05-11 brainstorm refresh.

Bundle-time deltas (this plan):

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| Bundle spec FR2: fixture manifest `sourceUrl` points at Manning/O'Reilly | Current manifest `apps/web-platform/scripts/spike/pdf-outline-fixtures.json` carries `sourceUrl: "TODO: operator records source URL (e.g., a Manning/O'Reilly purchase ...)"` — copyrighted-material reference at rest. | KD-2 → AC #16. Switch to (a) `generate-outline-fixture.ts` for the outline-bearing fixture; (b) archive.org pre-1929 US public-domain or CC0 source for the no-outline fixture. Manifest example `sourceUrl` rewritten in the same PR. |
| Parent plan AC #5 covers single-PDF prefix | Two PDFs simultaneously in active KB context is not covered — `selectChapter` operates per active PDF, the prefix doesn't name which book answered. | KD-6 → AC #5-bis. Prefix carries `<book title>` OR routing returns `kind: "ambiguous-which-document"`. |
| Parent plan §Risks line 265 covers cap-check **between** routing and answer turns | Cap exceeded **during** answer-turn streaming is governed by `cc-cost-caps.ts` mid-stream behavior but the carry-over of `state.activeChapter` past the boundary is untested. | KD-3 → AC #14. Integration test asserts `state.activeChapter` persists across the mid-stream cap boundary. |
| Plan §Resume left buffer-source decision open | OS page cache makes hot-file re-reads ~5ms on a 30MB PDF; threading binary on `documentExtractMeta` serializes through the runner state machine. | KD-4 → TR1 (no AC line). Re-read per turn via `readFile(state.chapterChunkedContext.fullPath)`; do NOT thread `documentExtractBuffer`. Re-evaluate post-merge if telemetry shows >100ms re-read p95. |
| Plan implicitly assumes PDF stays attached for life of conversation | Active KB context can have a PDF replaced/rotated/deleted mid-conversation. With `state.chapterChunkedContext` cached, the next turn's `documentExtractMeta.chapters` may be empty. | KD-5 → AC #13. Dispatch clears `state.activeChapter`, forces re-route, surfaces "the source PDF changed — re-routing" copy. |
| Bundle assumes S1 outcome is stable across the review cycle | If S1 GREEN-flips after review agents have already analyzed a RED-default diff, the `cache_control` marker ships under stale review attention. | KD-7 → AC #17. Run S1 BEFORE marking PR ready; outcome change post-review triggers a new review round. |

## User-Brand Impact

> **If this lands broken, the user experiences:** A founder uploads their unpublished manuscript or a Manning book to KB and asks "summarize chapter 3" (or "what does chapter 3 say about X"). The most-likely broken outcomes are: (a) **fabricated chapter answer** — `selectChapter` picks chapter 7, but the directive ships without the dispatch wiring, so the model responds with confidently-wrong content under `[Answering from chapter 3]`; (b) **silent wrong-book answer** when KB has two chapter-chunkable PDFs and `selectChapter` picks one without disambiguation (KD-6); (c) **surprise $50+ bill** if mid-stream cap behavior fails to persist `activeChapter` and the user pays another routing turn (KD-3); (d) **stale-context confusion** when the PDF rotated mid-conversation and dispatch still routes against the old outline (KD-5); (e) **refusal** where chapter-chunking should have worked (S2 outline-extraction false-negative).
>
> **If this leaks, the user's manuscript / IP / workflow is exposed via:** No new third-party storage path. Existing Anthropic `messages.create` flow is the only egress, already covered by current Anthropic DPA. Risk vector reduces to "wrong chapter loads into the answer turn" — bounded to the user's own conversation. Sub-processor surface is unchanged (CLO refresh confirmed).
>
> **Brand-survival threshold:** `single-user incident`. A founder uploading their own unpublished manuscript and getting any of (a)–(e) above qualifies. Threshold is **inherited** from the parent plan §User-Brand Impact (lines 34-47) — no relaxation.
>
> **Mitigations baked into this bundle (carry-forward + new):**
> - Loaded-chapter prefix in every chapter-grounded response (parent plan; **extended for cross-document case** via KD-6 → AC #5-bis).
> - `cc-cost-caps.ts` per-conv cap ($0.50/conv Soleur, $2/conv BYOK) bounds the surprise-bill vector; **mid-stream cap persistence test** (KD-3 → AC #14) catches the corner the parent plan §Risks line 265 left underspecified.
> - Bridge fallback (#3430 `too_many_pages` directive) preserved as the fall-through; **stale-context invalidation** (KD-5 → AC #13) restores it as the recovery path when the PDF rotates.
> - Per-chapter extraction-failure branch with cost refund (parent AC #7).
> - **Single-commit invariant** (TR4 → AC #18): the system-prompt directive revival in both runners and the dispatch-time content-block attachment land in the same commit. Verified by `git log --oneline -- <runner files>` after the implementation phase.
> - **S1 outcome flip triggers re-review** (KD-7 → AC #17): if `cache_control` gating flips between draft and ready, the changed attachment line counts as a code change requiring a new review round per `rf-review-finding-default-fix-inline`.
> - CPO sign-off carry-forward from brainstorm Phase 0.5; `user-impact-reviewer` agent enumerates failure modes against the diff at PR review per `hr-weigh-every-decision-against-target-user-impact`.

`requires_cpo_signoff: true` and `requires_user_impact_reviewer: true` are set in frontmatter. CPO sign-off is the brainstorm refresh's CPO assessment (carry-forward, recorded under §Domain Review below). The `user-impact-reviewer` agent runs at PR review time via the review skill's conditional-agent block — not invoked at plan time.

## Implementation Phases

The bundle's phase order is load-bearing: spikes run **first inside the worktree** so the spike outputs anchor the dispatch-implementation decisions (S1 → `cache_control` attachment line; S2 → confirms heuristic or pivots to #3450). Tests for KD-3/5/6 are woven into the dispatch phase; the single-commit invariant (TR4) is enforced by combining directive revival + dispatch wiring into one commit per runner.

### Status (2026-05-11 worktree state)

- Branch `feat-pdf-chapter-chunking-bundle` cut from `main` at the Phase 3.A merge tip.
- Worktree at `.worktrees/feat-pdf-chapter-chunking-bundle/` — verified `git branch --show-current` = `feat-pdf-chapter-chunking-bundle`.
- Draft PR #3550 open.
- Existing artifacts from Phase 3.A (already on `main`, present in worktree):
  - `apps/web-platform/server/pdf-chapter-router.ts` (selectChapter, model-pinned, sanitized; 11 unit tests in `test/pdf-chapter-router.test.ts`).
  - `apps/web-platform/server/pdf-text-extract.ts` (extractPdfOutline + page-range extractPdfText).
  - `apps/web-platform/server/kb-document-resolver.ts` + `leader-document-resolver.ts` (chapter-chunked branch returning `chapters` + `fullExtractedText`).
  - `apps/web-platform/scripts/spike/cache-control-forwarding.ts` (S1 probe, scaffolded).
  - `apps/web-platform/scripts/spike/pdf-outline-coverage.ts` (S2 probe, scaffolded).
  - `apps/web-platform/scripts/spike/pdf-outline-fixtures.json` (manifest with Manning/O'Reilly-referencing `sourceUrl` placeholder — KD-2 target).
  - `test/soleur-go-runner-chapter-chunked-prompt.test.ts` + `test/agent-runner-chapter-chunked-prompt.test.ts` (pin the **directive REVERTED → fall-through to `too_many_pages`** invariant; this PR flips them).
- Directive state in `apps/web-platform/server/soleur-go-runner.ts` (verified): `buildSoleurGoSystemPrompt` lines 1000-1016 fall through to `buildPdfTooLongDirective` when `chapters` are present (Phase 3.A revert). Symmetric fall-through in `apps/web-platform/server/agent-runner.ts` lines 1011-1014.

### Phase 0 — Worktree preflight

Single-shot setup, not a workflow phase. Run from `.worktrees/feat-pdf-chapter-chunking-bundle/`:

1. `git fetch origin main` — confirm no drift since the worktree was cut.
2. `bun install` — refresh deps from current `package.json` + `bun.lock`.
3. `./node_modules/.bin/vitest run` (or the equivalent `package.json` script — verify via `jq '.scripts.test' apps/web-platform/package.json` before running) — confirm post-merge baseline is green; record passing count for AC reference.
4. Sanity-check: `doppler secrets get ANTHROPIC_API_KEY -p soleur -c dev --plain | wc -c` should return a non-zero count. Do NOT print the key.

### Phase 1 — Spike S1: `cache_control` end-to-end forwarding (#3473)

**Goal:** decide whether dispatch attaches `cache_control: { type: "ephemeral" }` to the chapter `document` content block (one-line gating in Phase 3 of this plan).

**Sequence:**

1. From the worktree root: `doppler run -p soleur -c dev -- ./node_modules/.bin/tsx apps/web-platform/scripts/spike/cache-control-forwarding.ts`.
2. Capture full stdout to `/tmp/spike-s1-output.txt`.
3. Parse the spike's output: extract `cache_creation_input_tokens` (first run) and `cache_read_input_tokens` (second run, within 5min TTL).
4. **GREEN-S1** if both > 0. **RED-S1** otherwise.
5. Paste the captured output verbatim into the PR body as a `## Spike S1 — cache_control forwarding` section, **above** the implementation diff narrative. Prefix the section with the explicit verdict (`GREEN-S1` or `RED-S1`).
6. Update local plan note: record the outcome so Phase 3 picks the matching dispatch attachment shape.
7. **Append a stable PR comment** for the AC #17 audit trail: `gh pr comment 3550 --body "## Spike S1 — cache_control forwarding\n\n**Verdict:** GREEN-S1 | RED-S1\n\n**Run at:** $(date -u +%Y-%m-%dT%H:%M:%SZ)\n\n<verbatim output>"`. This creates the immutable per-run record that AC #17 verifies against — one comment per S1 invocation; the count must match the number of review-requested events.

**Gating rule for downstream phases:**
- **GREEN-S1** → Phase 3 dispatch attaches `cache_control: { type: "ephemeral" }` on the `document` content block.
- **RED-S1** → Phase 3 omits `cache_control`; AC #4 keeps only the RED branch (5-turn cap instead of 10-turn); side-channel via bare `@anthropic-ai/sdk` is NOT introduced as v1 fallback (parent plan rejected).

**KD-7 (AC #17) enforcement:** S1 MUST run BEFORE the PR is marked ready for review. If a re-run between draft and ready flips the outcome, the changed `cache_control` line counts as a code change requiring a new review round.

### Phase 2 — Spike S2: pdfjs `getOutline()` coverage (#3474)

**Goal:** confirm `MIN_OUTLINE_ENTRIES = 3` / `OUTLINE_PAGE_COVERAGE_MIN = 0.8` heuristic on real fixtures or pivot Phase 1 of the parent plan to embedding retrieval (#3450).

**Step 2a — KD-2 fixture sourcing (do this BEFORE running the spike):**

Replace the `pdf-outline-fixtures.json` manifest's `sourceUrl` references and add a new generator script.

1. **New file `apps/web-platform/scripts/spike/generate-outline-fixture.ts`** — programmatic PDF generator using `pdfkit` (already in deps) OR `LaTeX \tableofcontents + 200 pages of lorem ipsum`. Constraints:
   - Outline includes ≥10 top-level entries with depth ≥1.
   - Each entry resolves via `getDestination` → `getPageIndex` (i.e., the outline uses named destinations, not raw page refs without resolution).
   - Total page count between 200 and 500 (parent plan §S2 spec).
   - Output file is `.gitignore`d (binary not committed).
   - Script records SHA-256 of the generated file and prints to stdout.

2. **No-outline fixture sourcing** — pre-1929 US public-domain scan from archive.org OR a CC0 source. Manifest records archive.org URL + SHA-256.

3. **Update `apps/web-platform/scripts/spike/pdf-outline-fixtures.json`** — remove Manning/O'Reilly references in any `sourceUrl` example or comment. Point outline-bearing entry at `scripts/spike/generate-outline-fixture.ts` (relative path); point no-outline entry at the archive.org URL + SHA.

4. **Run the generator:** `./node_modules/.bin/tsx apps/web-platform/scripts/spike/generate-outline-fixture.ts > /tmp/generated-fixture.pdf`. Verify SHA matches the manifest.

5. Download the no-outline fixture per the manifest's URL; verify SHA.

**Step 2b — Run the spike:**

1. From the worktree root: `doppler run -p soleur -c dev -- ./node_modules/.bin/tsx apps/web-platform/scripts/spike/pdf-outline-coverage.ts`.
2. Capture stdout. The spike prints a per-fixture table: outline length, top-level entry count, page coverage, verdict (`usable` / `fall-through`).
3. Paste the table verbatim into the PR body as `## Spike S2 — outline coverage`, with per-fixture explicit verdict.

**Outcome routing:**

- **Both fixtures match expectation** (outline-bearing → `usable`; no-outline → `fall-through`) → proceed to Phase 3.
- **Either fixture diverges** → STOP. Re-open parent plan §Phase 1 and revisit. Likely outcome: file an issue tagging #3450 with the failed-fixture coverage data and defer Phase 3.B of this bundle.

Bundle-time scope-out: this plan does NOT pre-implement embedding retrieval (#3450). Pivot is a separate cycle.

### Phase 3 — Dispatch wiring + directive revival (single commit, TR4 → AC #18)

**Load-bearing invariant:** The system-prompt directive revival in `buildSoleurGoSystemPrompt` AND the dispatch-time `document` content-block attachment in `dispatch()` MUST land in the same git commit. Symmetric in `agent-runner.ts`. Verify on the branch with `git log --oneline -- apps/web-platform/server/soleur-go-runner.ts apps/web-platform/server/agent-runner.ts` — no commit may carry the directive without the attachment, and no commit may carry the attachment without the directive.

Rationale: Phase 3.A's multi-agent review (PR #3440) classified the directive-without-delivery state as `single-user incident`. Two-commit landing reopens that window for any reviewer who checks out a mid-branch SHA.

#### 3.1 — Re-add `@anthropic-ai/sdk` devDep

`apps/web-platform/package.json`: re-add `@anthropic-ai/sdk@^0.92.0` to `devDependencies` for type-only `MessageParam` access on the structured user message construction. (Phase 3.A removed it as dead surface — see parent plan §Status Phase 3.A note.)

Regen both `bun.lock` and `package-lock.json` per `cq-before-pushing-package-json-changes` (Dockerfile uses `npm ci`).

Verify the import remains `import type { MessageParam } from "@anthropic-ai/sdk"` — any non-`import type` usage violates AC #9 (parent plan).

#### 3.2 — Concierge (`apps/web-platform/server/soleur-go-runner.ts`)

**Re-introduce the chapter-chunked system-prompt directive** in `buildSoleurGoSystemPrompt` (replace the current `too_many_pages` fall-through at lines 1000-1016, Phase 3.A revert site). Inline template per parent plan §Phase 3 / Simplicity reviewer (no `buildPdfChapterChunkedDirective` factory — single call site).

Directive content:
- `The user is currently viewing: ${sanitizedPath}`
- TOC list (sanitized title + 1-based page range per `ChapterIndex`)
- "The most-relevant chapter to the user's next question will be routed and attached on that user turn as a `document` content block."
- "Treat that block as the authoritative source for your answer."
- `Prefix every reply with [Answering from chapter <N>: "<title>"]`
- **KD-6 conditional** — when `documentExtractMeta.chapters` is populated for >1 PDF in active KB context, prefix template carries the document title: `[Answering from "<book title>", chapter <N>: "<title>"]`.

**Add to `ActiveQuery` state:**
- `chapterChunkedContext: { fullPath: string; outline: ChapterIndex[]; documentTitle: string } | null` — set on session creation when `args.documentExtractMeta?.chapters` is populated. `fullPath` is sourced from `args.contextPath` at session creation (the upstream dispatcher already knows the resolved absolute workspace path; do NOT widen `DocumentExtractMeta` for this — the resolver's view of the file path is internal). `documentTitle` is derived at session creation by parsing the basename of `args.contextPath` (with a PDF-metadata `Title` fallback if the parsed basename is opaque, e.g. `attachment-7f2e.pdf`). [Updated 2026-05-11 per Kieran P1-B / Architecture P1.3 — `DocumentExtractMeta.path` does not exist; threading via state from `args.contextPath` is cleaner than widening the resolver interface.]
- `activeChapter: { displayNumber: number; title: string; prefixEmitted: boolean; documentTitle: string | null } | null` — set per-turn before pushing user message; cleared by `handleResultMessage`. `documentTitle` populated only in multi-PDF case (KD-6).
- `multiPdfChapterChunked: boolean` — derived flag, set when the resolver returns chapter-chunked metadata for >1 active PDF (KD-6 disambiguation trigger). See §Risks "Cross-document confusion (KD-6)" for the architectural reachability concern flagged by the review panel.
- `chapterExtractionFailures: number` — per-conversation counter, default 0. Incremented on each chapter-slice failure (§3.2 step 3c). Bounds the infinite-refund-loop at 3 failures.

**In `dispatch()`, after `state` is acquired and BEFORE `pushUserMessage`:**

1. **KD-5 stale-context check (AC #13)** — if `state.chapterChunkedContext` is set but the current turn's `documentExtractMeta.chapters` is empty OR the current turn's `args.contextPath` differs from `state.chapterChunkedContext.fullPath`:
   - Clear `state.chapterChunkedContext` and `state.activeChapter`.
   - **If the new turn's `documentExtractMeta.chapters` is populated:** reconstruct `state.chapterChunkedContext` from the new `args.contextPath` + outline + parsed title, then **proceed with the normal chapter-routing path for THIS turn**. The user's question gets answered against the new PDF — no dropped input, no extra cost beyond the new turn's routing.
   - **If the new turn's `documentExtractMeta.chapters` is empty:** fall through to the `too_many_pages` bridge (or the resolver's other branch). The user's question gets answered through the existing fallback path on the SAME turn.
   - Prepend a one-line system-styled annotation to the assistant response: `"(Source PDF changed — answering against the new attachment.)"` Does NOT emit as a separate assistant message; rides on the response that does fire. Final copy is in Open Question 2; implementer proposes + user signs off pre-merge.
   - [Updated 2026-05-11 per Spec-flow F5 — original draft created an internal contradiction (§3.2 said "fall through to normal path"; AC #13 test 8 implied "no answer turn until next message"). Resolution: clear-and-proceed-same-turn, no dropped user input, no extra routing turn billed.]

2. If `state.chapterChunkedContext` is null: existing path (no chapter routing).

3. Else: call `selectChapter({ question: userMessage, outline: state.chapterChunkedContext.outline, conversationCostState: { totalCostUsd: state.totalCostUsd, perConvCap: capFor(state.costCaps, state.currentWorkflow) } })`.
   - **`kind: "router-error"`** — charge `routingCostUsd` to `state.totalCostUsd`; emit `WorkflowEnded` `internal_error` with the SDK error reason. Sentry already mirrored inside `selectChapter`.
   - **`kind: "cost-cap-hit"`** — charge `routingCostUsd`; `emitWorkflowEnded(state, { status: "cost_ceiling", ... })`; return.
   - **`kind: "ambiguous"`** — charge `routingCostUsd`; emit synthetic assistant text via `state.events.onText` ("I can answer from chapter [X] or chapter [Y] — which would you like?"); return without firing answer turn.
   - **`kind: "ambiguous-which-document"`** (KD-6 NEW — only emitted when `state.multiPdfChapterChunked === true` AND the router cannot disambiguate by title-mention in question) — charge `routingCostUsd`; emit synthetic assistant text listing the candidate PDFs by title; return without firing answer turn.
   - **`kind: "selected"`**:
     a. `readFile(state.chapterChunkedContext.fullPath)` (KD-4 — re-read per turn; do NOT thread a `documentExtractBuffer` on `documentExtractMeta`). **Wrap in try/catch.** On `ENOENT` (PDF deleted from KB mid-conversation while `chapterChunkedContext` is still cached): clear `state.chapterChunkedContext` + `state.activeChapter`, refund `routingCostUsd` from `state.totalCostUsd`, emit "The source PDF for this conversation was deleted; please re-attach it to continue." and return without firing an answer turn. Mirror the error to Sentry via `reportSilentFallback(err, { feature: "soleur-go-runner", op: "chapter-readfile-enoent" })` per `cq-silent-fallback-must-mirror-to-sentry`. On any other `readFile` exception, treat as `parse_error` and follow §3c below. [Added 2026-05-11 per Spec-flow F8 — original plan did not enumerate the file-deletion gap between KD-5's `documentExtractMeta`-empty trigger (which assumes the resolver knows the file is gone) and the slice-failure path (which assumes a buffer in hand).]
     b. `extractPdfText(buffer, capChars, { startPage, endPage })` per parent plan §Phase 2 page-range slicing.
     c. **Slice failure** (`oversized_buffer` / `parse_error`): emit "I have the TOC but chapter X failed to extract — try a different chapter or re-attach the PDF." Refund `routingCostUsd` from `state.totalCostUsd` (parent AC #7). Mirror the error to Sentry via `reportSilentFallback(err, { feature: "soleur-go-runner", op: "chapter-slice-failure", extra: { chapterIndex, errorClass } })` per `cq-silent-fallback-must-mirror-to-sentry`. **Increment `state.chapterExtractionFailures`** (new counter on `ActiveQuery`, default 0); if it reaches 3 in this conversation, surface the cap directly on this turn — "I can't extract chapters from this PDF — please re-attach or pick a different document." — and DO NOT refund the routing cost for the cap-trip turn (the failure is no longer transient — bounds the infinite-refund-loop). Return without firing answer turn. [Added 2026-05-11 per Spec-flow F7 + Architecture P2.1 — original plan had infinite-refund-loop risk + missing Sentry mirror on a degraded-condition fallback.]
     d. **Slice success**: set `state.activeChapter` (populate `documentTitle` only when `state.multiPdfChapterChunked === true`). Push structured user message via a new `pushStructuredUserMessage(state, content)` helper accepting `MessageParam`-shaped content array (`document` block + `text` block).
       - **S1-gated attachment shape:**
         - GREEN-S1: `document` block carries `cache_control: { type: "ephemeral" }`.
         - RED-S1: `document` block omits `cache_control`.
     e. Fire answer turn through the existing path.

**In `handleAssistantMessage`:** if `state.activeChapter` is set and `prefixEmitted === false`, prepend the chapter prefix to the first text block. Multi-PDF case (KD-6) uses the document-title-bearing template; single-PDF case uses the existing parent-plan-tested first-text-block prefix injection.

**In `handleResultMessage`:** clear `state.activeChapter`. **Do NOT clear `state.chapterChunkedContext`** — it persists across turns so the next user question reroutes off the same outline.

**KD-3 mid-stream cap behavior (AC #14):** the existing `cc-cost-caps.ts` mid-stream cap handling fires when the cap is exceeded during answer-turn streaming. **Invariant added by this bundle:** `state.activeChapter` MUST persist into the next user turn so the next turn does NOT pay another routing turn. Verified by integration test in §3.5 below; no code change is required to preserve the value (cap-hit emits `cost_ceiling` and returns; `handleResultMessage` is NOT called for the truncated turn). The test pins this against future regressions.

#### 3.3 — Leader (`apps/web-platform/server/agent-runner.ts`)

Symmetric pattern to §3.2, mirrored into the leader system-prompt assembly at lines 1002-1014 (current revert site) and the leader dispatch path around the existing region:

1. Re-introduce the leader chapter-chunked directive in the system-prompt assembly. Includes the leader-specific NO-ASK clause: `Do NOT invoke the Read tool on this PDF; the chapter content is provided in the user message.` (Concierge omits — has no SDK Read tool.)
2. Wire the same dispatch-time chapter routing using `pdf-chapter-router` and the same `pushStructuredUserMessage` shape (extracted as a shared helper if both runners diverge minimally; otherwise inline twice — single-callsite simplicity per parent plan).
3. Same KD-3 / KD-5 / KD-6 / KD-7 propagation.

#### 3.4 — Helper extraction: do not extract (decided)

Inline the dispatch block in both `soleur-go-runner.ts` and `agent-runner.ts`. **Do not** extract a shared `dispatchChapterChunked` helper. Runners diverge on Read-tool surface, NO-ASK semantics, system-prompt assembly, and resolver call paths — DRY here would create a multi-runner abstraction in front of two genuinely different state machines. Single-callsite simplicity preferred per parent plan, DHH P1, and Code-Simplicity #5.

`pushStructuredUserMessage` is the only new helper introduced — a local (non-exported) function in `soleur-go-runner.ts`, with a sibling in `agent-runner.ts` if the message-shape construction diverges. It does NOT live in `pdf-chapter-router.ts` — routing and message-shape construction are different concerns.

**No new shared `resolvePdfArtifactContext` module** — parent plan §Research Reconciliation row 1 deferred this; bundle preserves.

[Decided 2026-05-11 per DHH P1 + Code-Simplicity #5 + Architecture P3.3 — original draft deferred this to implementation; the 80% byte-overlap threshold is arbitrary and unmeasurable mid-implementation.]

#### 3.5 — Tests woven into Phase 3 (TDD per `cq-write-failing-tests-before`)

Write RED tests for each AC before the implementation lands.

**New file `apps/web-platform/test/soleur-go-runner-chapter-chunked.test.ts`:**

1. **Routed answer (AC #5)** — single-PDF case, `[Answering from chapter N: "title"]` prepended on first text block.
2. **Chapter switch — system-prompt byte-stability** (parent §Sharp Edges) — capture system-prompt hash on first within-chapter turn; assert byte-identical on subsequent within-chapter turns.
3. **Ambiguous turn (AC #5)** — no answer fires; cost limited to `routingCostUsd`.
4. **Chapter-extraction failure (AC #7)** — refund routing cost; failure-copy surfaces.
5. **Cap-hit between routing and answer turns (AC #6)** — `cost_ceiling` fires; no answer turn.
6. **Router-error path** — emits `internal_error` `WorkflowEnded`.
7. **KD-3 mid-stream cap (AC #14)** — simulate `cc-cost-caps.ts` mid-stream truncation; assert `state.activeChapter` is preserved across the cap boundary; next user turn does not pay another routing turn.
8. **KD-5 stale-context invalidation (AC #13)** — two sub-cases:
   - **8a (path mismatch, new PDF has chapters):** set up `state.chapterChunkedContext = { fullPath: "/ws/old.pdf", ... }`; next turn arrives with `args.contextPath = "/ws/new.pdf"` AND `documentExtractMeta.chapters` populated for the new PDF. Assert: old `chapterChunkedContext` cleared, new `chapterChunkedContext` reconstructed against `/ws/new.pdf`, chapter routing fires for THIS turn against the new outline, "(Source PDF changed — answering against the new attachment.)" prepended to assistant response.
   - **8b (path mismatch, new PDF has no chapters):** same setup but new PDF has empty `documentExtractMeta.chapters`. Assert: `chapterChunkedContext` cleared, fall-through to `too_many_pages` bridge fires for THIS turn, same prepended annotation.
   - Both sub-cases: no extra routing turn cost beyond the single new-context routing; user's question is answered on the same turn.
9. **KD-6 single-PDF prefix** — existing prefix shape (no document title); regression guard.

**New file `apps/web-platform/test/agent-runner-chapter-chunked.test.ts`:** mirror tests 1–9 for the leader path. Add a leader-specific test for the NO-ASK clause: assert the SDK Read tool is NOT invoked on the chapter-chunked PDF (mock `query()` and assert no `Read` tool_use with `path` equal to `state.chapterChunkedContext.fullPath`).

**New file `apps/web-platform/test/pdf-chapter-router-cross-document.test.ts`** (or extension of existing `pdf-chapter-router.test.ts`):

10. **KD-6 cross-document disambiguation (AC #5-bis)** — when `selectChapter` is called with a multi-PDF active context, asserts router returns `kind: "ambiguous-which-document"` for a question that doesn't mention either book title; returns `kind: "selected"` with `documentIndex` populated when the question DOES mention one book title.
11. **KD-6 prefix carries document title** (single-test variant): assert that the multi-PDF case prepends `[Answering from "<book title>", chapter <N>: "<title>"]`.

**Edits to existing files:**

- `apps/web-platform/test/soleur-go-runner-chapter-chunked-prompt.test.ts` — flip assertions from "directive REVERTED to fall-through" → "directive PRESENT" (the Phase 3.A pin is now the prior invariant). The 4 fall-through cases become 4 directive-present cases.
- `apps/web-platform/test/agent-runner-chapter-chunked-prompt.test.ts` — symmetric flip (the 2 leader cases).

**GREEN-S1 specific test** (only added if Phase 1 returns GREEN): assert `cache_creation_input_tokens > 0` on first within-chapter turn and `cache_read_input_tokens > 0` on second. RED-S1 omits this test.

#### 3.6 — Verify single-commit invariant (TR4 → AC #18)

After §3.1–§3.5 are staged, before pushing, run this per-commit walking script. **Do NOT use `git log --oneline -- A B`** — that command is a union filter (commits touching A OR B) and silently accepts a commit touching only one runner, which is the exact `single-user incident` failure mode TR4 is designed to catch.

```bash
#!/usr/bin/env bash
# Verify TR4 single-commit invariant: every commit on this branch that touches
# either runner's chapter-chunked region must touch BOTH the directive marker
# AND the dispatch marker in the SAME commit (or NEITHER — pure unrelated edits).
set -euo pipefail
FAIL=0
DIRECTIVE_MARKER='chapter-chunked'       # appears in both runners' directive blocks
DISPATCH_MARKER='pushStructuredUserMessage'  # new helper appears at dispatch sites in both runners
RUNNERS=(apps/web-platform/server/soleur-go-runner.ts apps/web-platform/server/agent-runner.ts)
for sha in $(git rev-list main..HEAD -- "${RUNNERS[@]}"); do
  diff=$(git show "$sha" -- "${RUNNERS[@]}")
  has_directive=0; has_dispatch=0
  echo "$diff" | grep -q "$DIRECTIVE_MARKER" && has_directive=1
  echo "$diff" | grep -q "$DISPATCH_MARKER" && has_dispatch=1
  if [[ $has_directive -ne $has_dispatch ]]; then
    echo "FAIL $sha — directive=$has_directive dispatch=$has_dispatch (must match)"
    FAIL=1
  fi
done
exit $FAIL
```

Wire this as a `pre-push` hook on the worktree for the duration of this branch's life (delete on merge). If a commit violates the invariant: `git rebase -i` to squash with the matching commit, or `git commit --amend` to fold the missing region into the offending commit. (Per AGENTS.md: prefer creating a new combined commit over rewriting already-pushed history — squash only this branch's local commits.)

[Updated 2026-05-11 per Kieran P1-A + Architecture P1.1 — the original `git log --oneline -- A B` verification is a union, not intersection, and does not detect single-runner commits.]

### Phase 4 — PR body composition

Compose the PR body with spike outputs **above** the implementation narrative (KD-1 → AC #15):

```
## Spike S1 — cache_control forwarding
<verbatim stdout from Phase 1>
**Verdict:** GREEN-S1 | RED-S1

## Spike S2 — outline coverage
<verbatim per-fixture table from Phase 2>
**Per-fixture verdict:** outline-bearing → usable | fall-through ; no-outline → usable | fall-through

## Implementation
<diff narrative referencing §3.1–§3.6 above>

## User-Brand Impact
<carry-forward from plan §User-Brand Impact, link to brainstorm + parent plan>

## Closes
Closes #3472
Closes #3473
Closes #3474

Ref #3436 #3440 #3450 #3454 #3343
```

**Caveat per `wg-use-closes-n-in-pr-body-not-title-to`:** Use `Closes #N` ONLY on its own body line; never put `Closes #N` in the PR title or inside a checkbox/code block. The auto-close scanner triggers anywhere in the PR title or body.

### Phase 5 — Operator handoff: post-merge ACs

Carry-forward verbatim from parent plan §Acceptance Criteria post-merge:

19. Monitor `cost_ceiling` event rate in production for 1 week post-deploy.
20. Monitor outline-unusable rate; file tuning issue if > 30%.
21. (GREEN-S1 only) Log `cache_creation` vs `cache_read` token ratio; file follow-up if cache hit rate < 50% over 1 week.

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts` — re-introduce chapter-chunked directive in `buildSoleurGoSystemPrompt` (lines 1000-1016 revert site); wire `selectChapter` per turn in `dispatch()`; add `chapterChunkedContext` / `activeChapter` / `multiPdfChapterChunked` to `ActiveQuery`; emit chapter prefix in `handleAssistantMessage`; clear `activeChapter` in `handleResultMessage`; handle stale-context invalidation (KD-5).
- `apps/web-platform/server/agent-runner.ts` — symmetric re-introduction (lines 1002-1014 revert site) + leader NO-ASK directive + symmetric dispatch wiring.
- `apps/web-platform/scripts/spike/pdf-outline-fixtures.json` — remove Manning/O'Reilly references; point outline-bearing entry at `generate-outline-fixture.ts`; point no-outline entry at archive.org URL + SHA-256.
- `apps/web-platform/package.json` — re-add `@anthropic-ai/sdk@^0.92.0` to `devDependencies`.
- `apps/web-platform/bun.lock` — regenerate.
- `apps/web-platform/package-lock.json` — regenerate (Dockerfile uses `npm ci`).
- `apps/web-platform/test/soleur-go-runner-chapter-chunked-prompt.test.ts` — flip assertions to "directive PRESENT".
- `apps/web-platform/test/agent-runner-chapter-chunked-prompt.test.ts` — flip assertions symmetrically.

## Files to Create

- `apps/web-platform/scripts/spike/generate-outline-fixture.ts` — KD-2 fixture generator. `pdfkit`-driven, ≥10 top-level outline entries, 200–500 pages, prints SHA-256 of output.
- `apps/web-platform/test/soleur-go-runner-chapter-chunked.test.ts` — full-flow integration tests (9 scenarios per §3.5).
- `apps/web-platform/test/agent-runner-chapter-chunked.test.ts` — leader mirror + NO-ASK assertion.
- `apps/web-platform/test/pdf-chapter-router-cross-document.test.ts` — KD-6 cross-document disambiguation (or extend existing `pdf-chapter-router.test.ts` — implementer's call).

**Pre-implementation glob verification (per `hr-when-a-plan-specifies-relative-paths-e-g`):**

```
git ls-files apps/web-platform/server/ | grep -E '^(soleur-go-runner|agent-runner|pdf-chapter-router|pdf-text-extract|kb-document-resolver|leader-document-resolver)\.ts$'
git ls-files apps/web-platform/scripts/spike/ | grep -E '^(cache-control-forwarding|pdf-outline-coverage|pdf-outline-fixtures)\.'
git ls-files apps/web-platform/test/ | grep -E 'chapter-chunked|chapter-router'
```

All paths above are verified present (or to be created in this PR). The third glob should include the existing `pdf-chapter-router.test.ts` + `soleur-go-runner-chapter-chunked-prompt.test.ts` + `agent-runner-chapter-chunked-prompt.test.ts` shipped by Phase 3.A — if it doesn't, the worktree drifted and Phase 0 should be re-run.

## Acceptance Criteria

### Pre-merge (PR)

**Carry-forward from parent plan (verbatim per KD-8):**

1. A 400pg published PDF with TOC + "summarize chapter 3" → content-grounded summary citing chapter 3, p95 < 8s.
2. Same PDF + "summarize this" → TOC-derived overview, not a refusal.
3. PDF with no usable outline → `too_many_pages` bridge unchanged.
4. Per-conv cost on Sonnet 4.6 under $0.50 across **5 turns RED-S1 / 10 turns GREEN-S1**.
5. Loaded-chapter prefix `[Answering from chapter <N>: "<title>"]` in every chapter-grounded response (single-PDF case). Misroute correctable in one turn.
6. `cc-cost-caps.ts` cap hit between routing and answer turn → `cost_ceiling` directive fires.
7. Per-chapter extraction failure → "I have the TOC but chapter X failed to extract" copy; routing cost refunded.
8. Both BYOK and Soleur-key users have access via `cc-cost-caps.ts`.
9. **No new RUNTIME direct dep on `@anthropic-ai/sdk`.** `devDependencies`-only inclusion is permitted for type-only `import type { MessageParam }`. Any non-`import type` usage violates this AC.
10. Leader path symmetric via `leader-document-resolver.ts`.
11. `## User-Brand Impact` section in PR body; CPO sign-off carry-forward from brainstorm; `user-impact-reviewer` invoked at PR review.
12. S1 spike outcome (GREEN/RED + token counts) documented verbatim in PR body.

**Bundle-specific ACs (KD-1..KD-8 deltas + TR4):**

- **AC #5-bis (KD-6) — Cross-document disambiguation.** When `documentExtractMeta.chapters` is populated for >1 PDF in the active KB context, the loaded-chapter prefix carries the document title (`[Answering from "<book title>", chapter <N>: "<title>"]`) OR the routing turn returns `kind: "ambiguous-which-document"` listing candidate PDFs and asking the user to choose. Single-PDF case keeps the existing prefix shape. **Verified by** `pdf-chapter-router-cross-document.test.ts` cases 10–11.
- **AC #13 (KD-5) — Stale-context invalidation.** When `state.chapterChunkedContext` is set but the next turn's `documentExtractMeta.chapters` is empty (PDF replaced / rotated / deleted), dispatch clears `state.activeChapter`, clears `state.chapterChunkedContext`, surfaces "source PDF changed — re-routing" copy, and does not fire an answer turn until the user's next message. **Verified by** `soleur-go-runner-chapter-chunked.test.ts` case 8.
- **AC #14 (KD-3) — Mid-stream cap behavior (regression guard).** When `cc-cost-caps.ts` cap is hit DURING answer-turn streaming, `state.activeChapter` is preserved across the cap boundary so the user's next turn does NOT pay another routing turn. **Pins existing `cc-cost-caps.ts` mid-stream behavior — no new production code; this AC is a regression guard via `soleur-go-runner-chapter-chunked.test.ts` case 7.** [Updated 2026-05-11 per Code-Simplicity #4 — plan §3.2 already notes "no code change is required to preserve the value"; this is pinning, not implementation.]
- **AC #15 (KD-1) — Spike outputs in PR body.** PR body contains `## Spike S1 — cache_control forwarding` and `## Spike S2 — outline coverage` sections, both above the implementation narrative, both with verbatim stdout/table and explicit verdict (`GREEN-S1` / `RED-S1`; per-fixture `usable` / `fall-through`).
- **AC #16 (KD-2) — Fixture licensing.** `pdf-outline-fixtures.json` contains no Manning/O'Reilly references. Outline-bearing fixture points at `generate-outline-fixture.ts` (committed in this PR). No-outline fixture points at archive.org pre-1929 US public-domain or CC0 source with SHA-256.
- **AC #17 (KD-7) — S1 outcome stability across review.** S1 ran BEFORE the PR was marked ready for review. Each S1 run appends a stable PR comment via `gh pr comment 3550 --body "..."` (Phase 1 step 7). **Verified at ship time** by `gh api repos/jikig-ai/soleur/issues/3550/comments | jq '[.[] | select(.body | startswith("## Spike S1"))] | length'` — the count must match the number of review-requested events in the PR timeline (one S1 run between each review round). If the S1 outcome flipped between draft and ready, the comment trail shows it and the reviewer-slate audit can verify a new review round was triggered. [Updated 2026-05-11 per Kieran P1-D — original "reviewer-slate audit" was not concrete; PR-comment trail gives a fingerprint.]
- **AC #18 (TR4) — Single-commit invariant.** Verified by the per-commit walking shell script in §3.6 (NOT by `git log --oneline -- A B` — that command is a union, not intersection, and silently misses the failure mode). The script runs `git show <sha> -- <runner files>` for each branch commit and asserts that the directive marker (`chapter-chunked`) and dispatch marker (`pushStructuredUserMessage`) are present together or absent together. Exits non-zero on any commit that touches one without the other. Recommended: wire as `pre-push` hook for the branch lifetime. [Updated 2026-05-11 per Kieran P1-A + Architecture P1.1 — original verification command did not work.]

### Post-merge (operator)

19. Monitor `cost_ceiling` event rate in production for 1 week post-deploy; flag any single chapter-Q&A conversation that hits the cap.
20. Monitor outline-unusable rate (`outlineResult.ok === false` on PDFs > `LARGE_PDF_PAGE_THRESHOLD`); if > 30%, file a tuning issue for the heuristic constants.
21. **GREEN-S1 only:** log average `cache_creation_input_tokens` vs `cache_read_input_tokens` ratio; if cache hit rate < 50% over 1 week, file a follow-up issue.
22. **(KD-4) Per-turn buffer re-read p95 latency.** Log p95 time-to-buffer for chapter-chunked answer turns; if p95 > 100ms over 1 week, file a follow-up issue to reconsider threading `documentExtractBuffer` on the resolver result (KD-4 fallback shape). [Added 2026-05-11 per Kieran P2-A — TR1's "re-evaluate if p95 > 100ms" had no AC anchor; post-merge telemetry closes the loop.]

**KD ↔ AC mapping summary** (per user brief):

| KD | AC | Where verified |
|---|---|---|
| KD-1 — Bundle shape (spike outputs in PR body) | AC #15 | PR body composition (Phase 4) |
| KD-2 — Fixture sourcing | AC #16 | Manifest diff + generator script (Phase 2a) |
| KD-3 — Mid-stream cap behavior | AC #14 | Integration test case 7 (Phase 3.5) |
| KD-4 — Buffer source: re-read per turn | TR1 + post-merge AC #22 | Implementation shape (Phase 3.2/3.3) + post-deploy p95 telemetry |
| KD-5 — Stale-context invalidation | AC #13 | Integration test case 8 (Phase 3.5) |
| KD-6 — Cross-document disambiguation | AC #5-bis | Router tests 10–11 (Phase 3.5) |
| KD-7 — S1 outcome flip → re-review | AC #17 | Ship-time reviewer-slate audit |
| KD-8 — Carry-forward verbatim | (carry-forward markers) | Parent-plan reference, no new AC |
| TR4 — Single-commit invariant | AC #18 | git log verification (Phase 3.6) |

## Open Code-Review Overlap

Grep run against `gh issue list --label code-review --state open --limit 200`. 71 open code-review issues; matches against bundle-touched files:

| Issue | Title | Touched files | Disposition |
|---|---|---|---|
| **#3343** | review: case-insensitive `</document>` escape across cc + leader prompt builders | `soleur-go-runner.ts`, `agent-runner.ts` | **Acknowledge** (carry-forward from parent plan). Bundle attaches chapter as a `document` content block, NOT a `<document>` wrapper interpolation, so it does not add a new wrapper site. Existing 4 sites remain in #3343's scope. **If S1 RED forces wrapper-interpolation fallback** → fold #3343 in. RED-default does NOT force wrapper interpolation (parent plan rejected the side-channel) so this acknowledgement stands either way. |
| **#3454** | review: expose `pdf_metadata` as agent-callable MCP tool | `pdf-text-extract.ts`, `kb-document-resolver.ts`, `leader-document-resolver.ts` | **Acknowledge** (carry-forward). Chapter-chunking widens the agent-native gap by introducing `outline` as a second server-internal fact. Folding in the MCP tool is materially out of scope (sandbox hooks, schema, scoping, baseline-prompt integration). Update #3454 body post-merge to note the gap widened. |
| **#3369** | review: extract `mirrorWithDebounce` from cc-dispatcher to observability | `kb-document-resolver.ts` (import only) | **Defer.** Different concern; bundle does not modify the import surface. |
| **#3392** | review: PR-B (#3244) deferrals — denied_jti wire-up, etc. | `agent-runner.ts` (auth/JWT region) | **Defer.** Different concern; bundle does not touch JWT auth surface. |
| **#3242** | review: tool_use WS event lacks raw name field for agent consumers | `agent-runner.ts` (WS event shape) | **Defer.** Different concern. |
| **#2955** | arch: process-local state assumption needs ADR + startup guard | `agent-runner.ts`, `soleur-go-runner.ts` | **Defer.** Bundle introduces no new process-local state — `chapterChunkedContext` and `activeChapter` live on `ActiveQuery` (per-session, already process-local but bounded to session lifetime). Same property as existing state shape. |

PR-body reminder: list these scope-outs explicitly under a `### Scope-outs acknowledged` section so reviewers can see they were considered.

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Finance. (Marketing, Operations, Sales, Support assessed in brainstorm Phase 0.5 as not relevant — bundle does not change customer-facing surface beyond what parent plan already covered.)

**Brainstorm carry-forward — Domain Assessments section of `2026-05-11-pdf-chapter-chunking-bundle-brainstorm.md`** records the 2026-05-11 refresh from CPO, CLO, CTO. CFO carries forward from parent plan §Domain Review (no per-bundle delta — cost envelope unchanged).

### Product (CPO)

**Status:** reviewed (carry-forward from brainstorm refresh 2026-05-11).
**Assessment:** Sign-off stands. One delta — cross-document disambiguation (KD-6) is a new AC item `user-impact-reviewer` would have flagged at PR review; encoded in AC #5-bis. One bundle-risk flagged: S1 outcome flip mid-review (KD-7 → AC #17). `requires_cpo_signoff: true` set in frontmatter; the brainstorm `## User-Brand Impact` + this plan's `## User-Brand Impact` are the canonical CPO sign-off records (link from PR description). `user-impact-reviewer` invoked at PR review per `hr-weigh-every-decision-against-target-user-impact`.

### Legal (CLO)

**Status:** reviewed (carry-forward from brainstorm refresh 2026-05-11).
**Assessment:** Sign-off stands. One delta — S2 fixture manifest switched from publisher-PDF references to synthesized + public-domain (KD-2 → AC #16). S1 spike payload verified hard-coded synthetic. No `compliance-posture.md` impact. No new sub-processor surface (chapter routing uses standard Anthropic `messages.create` covered by current DPA).

### Engineering (CTO)

**Status:** reviewed (carry-forward + brainstorm refresh 2026-05-11).
**Assessment:** Zero 4-day drift on touched files (only the Phase 3.A merge itself). Three underspecified edges in the parent plan surfaced and encoded: KD-3 mid-stream cap → AC #14; KD-4 buffer source → TR1; KD-5 stale-context invalidation → AC #13. All four Sharp Edges from parent plan remain load-bearing. Bundle risk: medium, mitigated by spike-outputs-in-PR-body convention (KD-1 → AC #15) and the single-commit invariant (TR4 → AC #18).

### Finance (CFO)

**Status:** reviewed (carry-forward from parent plan).
**Assessment:** Worst-case 5-turn chapter Q&A on Sonnet 4.6 ≈ $0.30–0.40 (RED-S1). With cache hits (GREEN-S1), 10-turn ≈ same range. No new `usage_ledger` table required. Bundle does not change cost envelope from parent.

### Product/UX Gate

**Tier:** ADVISORY. **Decision:** auto-accepted (pipeline mode — plan is being authored inside a pipeline-mode invocation; no interactive prompt).
**Agents invoked:** none (no new UI surface; all code is server-side).
**Skipped specialists:** ux-design-lead (no new page or component files), copywriter (no domain leader recommended copywriter in brainstorm refresh — system-styled "source PDF changed" and "ambiguous-which-document" copy carry CMO-light decisions deferred to implementation per brainstorm Open Question 2; user signs off pre-merge).
**Pencil available:** N/A (no wireframe target).

#### Findings

All new code is server-side. No new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files (verified — files-to-create list contains zero such paths). Loaded-chapter prefix and disambiguation copy are system-styled annotations reusing the existing convention. The new "source PDF changed" and "ambiguous-which-document" copy are CMO-light decisions deferred to implementation; implementer drafts + user signs off pre-merge.

**Brainstorm-recommended specialists:** none. The 2026-05-11 brainstorm refresh recommended no new specialists beyond the leaders already in the carry-forward set. The bundle does not modify the customer-facing surface beyond parent plan scope.

## Risks

Carry-forward from parent plan §Risks (S1 RED, S2 outliers, misrouted-chapter fabrication, cache-bust on chapter switch, routing-turn cost cap, per-chapter extraction failure). Bundle-specific additions:

- **Cross-document confusion (KD-6).** Two chapter-chunked PDFs in active KB context simultaneously. `selectChapter` picks one silently. Mitigation: AC #5-bis (router returns `ambiguous-which-document` OR prefix carries document title); integration tests 10–11. **Architectural reachability concern flagged 2026-05-11 (review panel — DHH P1, Architecture P1.2, Spec-flow F4):** under the current resolver architecture, `cc-dispatcher.ts` passes a single `contextPath` per turn so the runner cannot see >1 chapter-chunked `documentExtractMeta` at the same dispatch turn. KD-6's protection may not be reachable until the resolver pipeline surfaces multi-PDF context. Plan keeps KD-6 / AC #5-bis per user brief (encode KD-1..KD-8 as AC #5-bis, #13-#18). **Implementer pre-flight (Phase 3.2):** grep `cc-dispatcher.ts` and the resolver call sites for any path that could pass >1 `documentExtractMeta` per turn. If confirmed unreachable, tests 10–11 become forward-looking guards (not current-bug regression tests) and an issue is filed to revisit the protection once resolver multi-PDF support lands. If reachable, the test cases verify a live failure mode.
- **Stale-context routing (KD-5).** User rotates the PDF mid-conversation; `state.chapterChunkedContext` persists with the old outline. Mitigation: AC #13 (clear on `documentExtractMeta.chapters` empty or path mismatch); integration test case 8.
- **Mid-stream cap-hit losing activeChapter (KD-3).** Cap hit during answer streaming truncates the turn; if `activeChapter` is cleared, the user's next turn pays a fresh routing turn. Mitigation: AC #14; integration test case 7.
- **Two-commit landing reopens directive-without-delivery window (TR4).** Phase 3.A's multi-agent review identified this as `single-user incident`. Mitigation: single-commit invariant (AC #18); `git log` verification at ship time.
- **S1 outcome flip post-review (KD-7).** Operator re-runs S1 between draft and ready and the outcome changes; `cache_control` ships under stale review attention. Mitigation: AC #17 + `rf-review-finding-default-fix-inline` re-review trigger.
- **Generated fixture page-count drift (Open Question 3).** `generate-outline-fixture.ts` produces a fixture outside the 200–500pg range, failing the spike's heuristic ground-truth assumption. Mitigation: generator asserts page count + SHA-256 print; manifest records the asserted range; Phase 2b spike fails fast if outside the range.

## Sharp Edges

Carry-forward verbatim from parent plan §Sharp Edges (4 items: `cache_control` cumulative-prefix invariant + system-prompt byte-stability test; chapter-router model pinning; PDF-deletion semantics; AC #9 trap). Bundle-specific additions:

- **Single-commit invariant is brand-survival load-bearing (TR4 → AC #18).** Implementers naturally split work into "infrastructure first, wiring second" commits. For this bundle, that's the exact failure mode (directive-without-delivery) the multi-agent review of PR #3440 identified as `single-user incident`. The implementer MUST stage the directive revival in `buildSoleurGoSystemPrompt` + the dispatch-time content-block attachment in `dispatch()` + the symmetric leader edits in the same `git commit` invocation. Verification command (run before push): `git log --oneline -- apps/web-platform/server/soleur-go-runner.ts apps/web-platform/server/agent-runner.ts` MUST show paired changes per commit.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is populated; do not regress on a future edit. (Required marker per AGENTS.md `hr-weigh-every-decision-against-target-user-impact` + plan skill Phase 2.6.)
- **S1 outcome change between draft and ready is a code change (KD-7 → AC #17).** Don't treat a `cache_control` attachment line flip as "just config" — it's a one-line dispatch-path change that affects every chapter-Q&A turn under cache pressure. Trigger a new review round per `rf-review-finding-default-fix-inline` and AGENTS.md `rf-before-spawning-review-agents-push-the`.
- **`pushStructuredUserMessage` helper boundary.** The new helper accepts a `MessageParam`-shaped content array. Implementers MUST NOT introduce a runtime import of `@anthropic-ai/sdk` to construct this — `MessageParam` is a `import type` only. Any value-import of `@anthropic-ai/sdk` violates AC #9. Review agents (architecture-strategist) check this at PR review.
- **Fixture-generator script ownership (brainstorm Open Question 1).** `generate-outline-fixture.ts` lives in `scripts/spike/` (alongside the probe scripts). Revisit only if a second use case lands; do not pre-extract to `scripts/test-helpers/`.
- **Cross-document disambiguation copy (brainstorm Open Question 2).** Final wording for "ambiguous-which-document" and "source PDF changed" is a CMO-light decision deferred to implementation. Implementer proposes copy in the PR body + tags user for sign-off before marking PR ready. Do NOT mark the PR ready with placeholder copy.
- **Multi-PDF detection is `documentExtractMeta`-driven, not session-driven.** `state.multiPdfChapterChunked` is computed from the resolver's view at session creation. If a second PDF is attached mid-session, the next turn's resolver pass should update this — KD-5 stale-context invalidation triggers a re-route which recomputes the flag. Integration test 8 implicitly covers this; if it surfaces as a gap during implementation, file a follow-up issue rather than expanding bundle scope.

## Test Strategy

- Unit + integration tests woven through Phase 3 (per `cq-write-failing-tests-before` — RED before GREEN).
- Test runner: `vitest run` invoked via `./node_modules/.bin/vitest` (parent plan §Test Strategy clarified this — the `bun test` reference in brainstorm context is transcription drift from Phase 1).
- Fixture sweep at Phase 2 (S2 spike) gates Phase 3; PDF binaries `.gitignore`d, manifest committed with SHA-256.
- No new test framework — `vitest` per project conventions; no devDep additions beyond re-adding `@anthropic-ai/sdk`.
- Pre-merge: full `vitest run` + `tsc --noEmit` green. Record passing count for AC reference.
- Spike outputs (S1 token counts, S2 fixture coverage table) pasted verbatim in PR body (AC #15).
- **GREEN-S1 specific test** (only if Phase 1 returns GREEN): assert `cache_creation_input_tokens > 0` on first within-chapter turn, `cache_read_input_tokens > 0` on second. RED-S1 omits.
- **System-prompt byte-stability assertion** (parent §Sharp Edges) is in `test/soleur-go-runner-chapter-chunked.test.ts` case 2. Fail-loud on drift.

## Resume

To continue this bundle in a fresh session after `/clear`:

```
/soleur:work knowledge-base/project/plans/2026-05-11-feat-pdf-chapter-chunking-bundle-plan.md

Branch: feat-pdf-chapter-chunking-bundle. Worktree: .worktrees/feat-pdf-chapter-chunking-bundle/. Issues: #3472 #3473 #3474. PR: #3550 (draft). Parent plan: knowledge-base/project/plans/2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md. Bundle brainstorm: knowledge-base/project/brainstorms/2026-05-11-pdf-chapter-chunking-bundle-brainstorm.md. Bundle spec: knowledge-base/project/specs/feat-pdf-chapter-chunking-bundle/spec.md. USER_BRAND_CRITICAL=true. KD-1..KD-8 encoded as AC #5-bis, #13–#18 (see plan §Acceptance Criteria). Phase order: (1) S1 spike → paste output to PR body; (2) S2 spike + KD-2 fixture rework → paste table to PR body; (3) directive revival + dispatch wiring in single commit per TR4 (AC #18) — both runners + tests; (4) PR body composition; (5) ready-for-review → `/soleur:review`. Single-commit invariant verification: `git log --oneline -- apps/web-platform/server/soleur-go-runner.ts apps/web-platform/server/agent-runner.ts` before push.
```
