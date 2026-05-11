---
title: "Bundle spec: PDF chapter-chunking Phase 3.B + S1/S2 spikes"
issues:
  - 3472
  - 3473
  - 3474
related:
  - 3436   # CLOSED parent
  - 3440   # MERGED Phase 3.A foundations
  - 3450   # embedding retrieval (S2 RED pivot target)
parent_plan: knowledge-base/project/plans/2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-07-large-pdf-chapter-chunking-brainstorm.md
parent_spec: knowledge-base/project/specs/feat-large-pdf-files-api/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-11-pdf-chapter-chunking-bundle-brainstorm.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_user_impact_reviewer: true
draft_pr: 3550
branch: feat-pdf-chapter-chunking-bundle
---

# Spec: PDF Chapter-Chunking Phase 3.B Bundle

## Problem Statement

Phase 3.A foundations (PR #3440, merged 2026-05-07) shipped the chapter router module, outline extraction, resolver wiring, and spike scripts — but deliberately **reverted** the chapter-chunked system-prompt directive in both runners. Today, oversized PDFs with usable outlines silently fall through to the `too_many_pages` bridge: the directive cannot ship without the dispatch-time content-block attachment without crossing the `single-user incident` brand-survival threshold (fabricated chapter answers laundered under a confident prefix).

Two operator-driven spikes (#3473 / #3474) are required inputs to the Phase 3.B implementation: S1 decides whether `cache_control: ephemeral` attaches to the chapter content block (one-line gating); S2 decides whether the outline heuristic constants hold or Phase 1 needs to pivot to embedding retrieval (#3450).

The three issues are mutually dependent and should ship together.

## Goals

- **G1.** Bundle #3472 + #3473 + #3474 into a single PR off branch `feat-pdf-chapter-chunking-bundle` (draft PR #3550).
- **G2.** Run S1 + S2 spikes inside the worktree before review, paste outputs verbatim into PR body as their own labeled sections, then implement Phase 3.B dispatch per parent plan §Phase 3.
- **G3.** Preserve the single-commit invariant (directive revival + dispatch attachment in the same commit).
- **G4.** Encode four refresh-surfaced deltas (cross-document disambiguation, mid-stream cap behavior, fixture licensing fix, stale-context invalidation) as bundle-specific ACs.

## Non-Goals

- Pre-implementing embedding retrieval (#3450) unless S2 RED forces the pivot.
- Adding `pdf_metadata` MCP tool (#3454).
- Extracting shared `resolvePdfArtifactContext` (#3437 deferred per parent plan).
- Cache-hit-rate logging (parent plan post-merge AC #15).

## Functional Requirements

### FR1 — Spike execution sequence
Operator (or implementer) runs both spikes against Doppler `dev` BEFORE marking PR #3550 ready for review:

```
doppler run -p soleur -c dev -- ./node_modules/.bin/tsx apps/web-platform/scripts/spike/cache-control-forwarding.ts
doppler run -p soleur -c dev -- ./node_modules/.bin/tsx apps/web-platform/scripts/spike/pdf-outline-coverage.ts
```

S1 result and S2 fixture table are pasted verbatim into the PR body as `## Spike S1 — cache_control forwarding` and `## Spike S2 — outline coverage` sections, above the implementation diff narrative.

### FR2 — S2 fixture sourcing (bundle delta KD-2)
The S2 fixture manifest (`apps/web-platform/scripts/spike/pdf-outline-fixtures.json`) is updated to remove Manning/O'Reilly references. Two fixtures:

- **`outline-bearing.pdf`** — generated programmatically by a new helper script `apps/web-platform/scripts/spike/generate-outline-fixture.ts` (committed in this PR) using `pdfkit`. Outline must include ≥10 top-level entries that resolve via `getDestination` → `getPageIndex`. Page count 200-500.
- **`no-outline.pdf`** — public-domain source (archive.org pre-1929 US or CC0). Manifest records archive.org URL + SHA-256.

Manifest example `sourceUrl` references the helper script (for outline-bearing) or archive.org (for no-outline).

### FR3 — Phase 3.B implementation
Per #3472 body + parent plan §Phase 3 (lines 117-173). Summarized in the parent plan §Files to Edit / §Files to Create. No deviation from the parent plan implementation spec except for the four ACs below.

### FR4 — Cross-document disambiguation (bundle delta KD-6)
When `documentExtractMeta.chapters` is populated for >1 PDF in the active KB context simultaneously, the loaded-chapter prefix MUST carry the document title:

```
[Answering from "<book title>", chapter <N>: "<title>"]
```

OR the routing turn returns a new `kind: "ambiguous-which-document"` shape that lists candidate PDFs and asks the user to choose. The single-PDF case keeps the existing prefix shape — no change to the parent plan's already-tested first-text-block prefix injection.

### FR5 — Stale-context invalidation (bundle delta KD-5)
If `state.chapterChunkedContext` is set but a later turn's `documentExtractMeta.chapters` is empty (PDF replaced, rotated, or deleted from KB mid-conversation), dispatch MUST clear `state.activeChapter`, force a re-route, and surface a system-styled "the source PDF changed — re-routing" message.

## Technical Requirements

### TR1 — Buffer source: re-read per turn (bundle delta KD-4)
Dispatch slices the chapter via `readFile(fullPath)` per turn. Do NOT thread a `documentExtractBuffer` on `documentExtractMeta`. Rationale documented in brainstorm KD-4.

### TR2 — Mid-stream cost-cap behavior (bundle delta KD-3)
When `cc-cost-caps.ts` cap is hit DURING answer-turn streaming (not just between routing and answer), `state.activeChapter` MUST persist into the next user turn so the next turn does not pay another routing turn. Verified by integration test.

### TR3 — S1 outcome triggers re-review (bundle delta KD-7)
S1 must run BEFORE PR ready-for-review. If S1 outcome flips after review agents have analyzed the diff, the `cache_control` attachment change counts as a code change requiring a new review round.

### TR4 — Single-commit invariant
The system-prompt directive revival in both runners (`buildSoleurGoSystemPrompt` and `agent-runner.ts` system-prompt assembly) and the dispatch-time `document` content-block attachment MUST land in the same commit on `feat-pdf-chapter-chunking-bundle`. No intermediate commit may carry the directive without the attachment. Verify on the branch with `git log --oneline --grep="chapter-chunked directive"`.

## Acceptance Criteria

### Carry-forward verbatim from parent plan AC items
- **AC #1** — 400pg PDF + "summarize chapter 3" → grounded summary citing chapter 3, p95 < 8s.
- **AC #2** — 400pg PDF + "summarize this" → TOC-derived overview, not refusal.
- **AC #3** — PDF without outline → `too_many_pages` bridge unchanged.
- **AC #4** — Per-conv cost on Sonnet 4.6 under $0.50 across 5 turns RED-S1 / 10 turns GREEN-S1.
- **AC #5** — Loaded-chapter prefix appears in every chapter-grounded response (single-PDF case).
- **AC #6** — Cap-hit between routing and answer turn emits `cost_ceiling`.
- **AC #7** — Per-chapter extraction failure surfaces explicit copy + refunds routing cost.
- **AC #8** — Both BYOK and Soleur-key users have access via `cc-cost-caps.ts`.
- **AC #9** — No new runtime direct dep on `@anthropic-ai/sdk` (devDep type-only is permitted).
- **AC #10** — Leader path symmetry via `leader-document-resolver.ts`.
- **AC #11** — `## User-Brand Impact` section in PR body, CPO sign-off carry-forward, `user-impact-reviewer` invoked.
- **AC #12** — S1 spike outcome documented verbatim in PR body.

### Bundle-specific ACs (deltas)
- **AC #5-bis (KD-6)** — When KB has >1 chapter-chunked PDF in active context, prefix carries document title OR routing returns `ambiguous-which-document`. Verified by integration test.
- **AC #13 (KD-5)** — Stale `chapterChunkedContext` (PDF rotated/deleted) clears `activeChapter`, forces re-route, surfaces "source PDF changed" copy. Verified by integration test.
- **AC #14 (KD-3)** — Mid-stream cap-hit preserves `activeChapter` across the cap boundary. Verified by integration test.
- **AC #15 (KD-1)** — PR body contains `## Spike S1` and `## Spike S2` sections with verbatim outputs and explicit verdict (`GREEN-S1` / `RED-S1`, per-fixture `usable` / `fall-through`).
- **AC #16 (KD-2)** — S2 fixture manifest references the generator script (outline-bearing) and archive.org / CC0 source (no-outline). No publisher-PDF references in the committed manifest.
- **AC #17 (KD-7)** — S1 ran before PR marked ready; if S1 outcome flipped post-review, a new review round was triggered (verified by reviewer slate audit at ship time).
- **AC #18 (TR4)** — Single-commit invariant: directive + dispatch attachment in the same commit. Verified by `git log --oneline -- apps/web-platform/server/soleur-go-runner.ts apps/web-platform/server/agent-runner.ts` showing no commit on the branch with one without the other.

### Post-merge (operator) — carry-forward from parent plan
- **AC #19** — Monitor `cost_ceiling` event rate for 1 week.
- **AC #20** — Monitor outline-unusable rate; file tuning issue if >30%.
- **AC #21 (GREEN-S1 only)** — Log `cache_creation` vs `cache_read` token ratio; file follow-up if <50% hit rate.

## Sharp Edges (carry-forward, all load-bearing)

Per parent plan §Sharp Edges (lines 268-273). All four remain in force for the bundle:
- `cache_control` cumulative-prefix invariant + system-prompt byte-stability test.
- Chapter-router model pin (Sonnet 4.6 / 200K) — do not let runner model bleed in.
- PDF-deletion semantics on stale conversation.
- AC #9 trap: `@anthropic-ai/sdk` MUST be `import type` only.

## Open Items Tracked Outside This Spec

- **Cross-document copy** (Open Question 2 in brainstorm) — implementer proposes copy, user signs off pre-merge.
- **#3450** (embedding retrieval) — remains independent. Pre-implementation here would be premature.
- **#3454** (pdf_metadata MCP tool) — chapter-chunking widens the agent-native gap; update #3454 post-merge to note.

## Files Touched by the Bundle PR

### New (this PR)
- `apps/web-platform/scripts/spike/generate-outline-fixture.ts` — S2 fixture generator (KD-2).
- `apps/web-platform/test/soleur-go-runner-chapter-chunked.test.ts` — full flow integration tests.
- `apps/web-platform/test/agent-runner-chapter-chunked.test.ts` — leader mirror.
- `apps/web-platform/test/pdf-chapter-router-cross-document.test.ts` — KD-6 disambiguation (new file or extension of `pdf-chapter-router.test.ts`).

### Edited (this PR)
- `apps/web-platform/server/soleur-go-runner.ts` — re-introduce directive, wire dispatch.
- `apps/web-platform/server/agent-runner.ts` — symmetric leader integration.
- `apps/web-platform/scripts/spike/pdf-outline-fixtures.json` — sourceUrl cleanup (KD-2).
- `apps/web-platform/package.json` — re-add `@anthropic-ai/sdk` devDep; regenerate `bun.lock` + `package-lock.json`.
- `apps/web-platform/test/soleur-go-runner-chapter-chunked-prompt.test.ts` — flip from "directive REVERTED" to "directive PRESENT".
- `apps/web-platform/test/agent-runner-chapter-chunked-prompt.test.ts` — leader symmetric.

## Resume

```
/soleur:plan — bundle: PDF chapter-chunking Phase 3.B + S1/S2 spikes (#3472, #3473, #3474). Parent plan: knowledge-base/project/plans/2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md. Bundle brainstorm: knowledge-base/project/brainstorms/2026-05-11-pdf-chapter-chunking-bundle-brainstorm.md. Bundle spec: knowledge-base/project/specs/feat-pdf-chapter-chunking-bundle/spec.md. Branch: feat-pdf-chapter-chunking-bundle. Draft PR: #3550.

Plan must: (1) sequence spike runs first; (2) add fixture generator script per KD-2; (3) encode AC #5-bis, AC #13, AC #14 as new test scenarios; (4) preserve single-commit invariant per TR4.
```
