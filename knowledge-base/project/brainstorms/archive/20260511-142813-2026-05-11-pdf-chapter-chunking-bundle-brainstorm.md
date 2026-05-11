---
title: "Bundle scoping: chapter-chunking dispatch + S1/S2 spikes (#3472, #3473, #3474)"
date: 2026-05-11
type: bundle-scoping
brand_survival_threshold: single-user incident
parent_plan: knowledge-base/project/plans/2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-07-large-pdf-chapter-chunking-brainstorm.md
parent_spec: knowledge-base/project/specs/feat-large-pdf-files-api/spec.md
branch: feat-pdf-chapter-chunking-bundle
draft_pr: 3550
issues:
  - 3472  # feat: chapter-chunking dispatch-time routing (Phase 3.B)
  - 3473  # S1 spike: cache_control forwarding probe
  - 3474  # S2 spike: pdfjs getOutline() coverage
related:
  - 3436  # CLOSED parent
  - 3440  # MERGED 2026-05-07 (Phase 3.A foundations)
  - 3450  # embedding retrieval (S2 RED pivot target)
---

# Bundle Scoping: PDF Chapter-Chunking Phase 3.B + Spikes

## Why This Is a Brainstorm, Not a Plan

The 2026-05-07 plan covers the full Phase 3.B design. This document scopes how three issues (#3472, #3473, #3474) ship together as one PR. It captures **four delta findings** from a focused CPO/CLO/CTO refresh that the parent plan does not cover, and binds them to the existing acceptance criteria.

## What We're Building

A single PR (drafted as #3550 on branch `feat-pdf-chapter-chunking-bundle`) that:

1. Runs the **S1 spike** (cache_control end-to-end forwarding) using the already-shipped script `apps/web-platform/scripts/spike/cache-control-forwarding.ts`. Spike outputs (`cache_creation_input_tokens`, `cache_read_input_tokens`) get pasted verbatim into the PR body. Outcome decides one line in the dispatch path.
2. Runs the **S2 spike** (pdfjs `getOutline()` coverage on two fixture PDFs) using the already-shipped script `apps/web-platform/scripts/spike/pdf-outline-coverage.ts`. Outcome either confirms `MIN_OUTLINE_ENTRIES = 3` / `OUTLINE_PAGE_COVERAGE_MIN = 0.8` or pivots Phase 1 of the plan to embedding retrieval (#3450).
3. Implements **Phase 3.B dispatch wiring** per the existing plan §Phase 3 (lines 117-173) and #3472's issue body — re-introduce the chapter-chunked system-prompt directive in both runners, wire `selectChapter` per turn, attach the chapter as a `document` content block (with or without `cache_control` per S1 outcome), prepend `[Answering from chapter <N>: "<title>"]`, refund routing cost on slice failure, emit `cost_ceiling` on cap-hit between routing and answer turns, mirror in `agent-runner.ts` for the leader path.

The single-commit invariant (directive + dispatch attachment together) is preserved.

## Why Bundle, Not Stage

| Option considered | Outcome |
|---|---|
| Bundle in one PR (chosen) | Spike outputs adjacent to the code that depends on them. Operator-driven follow-throughs collapse from 3 issues to 1 merge. No risk that S1 GREEN never gets wired post-merge. |
| Spikes first, separate PRs | Adds two PR cycles. Risk: S1 outcome lands but never propagates. S2 outcome similar. Operator-driven cadence is the bottleneck, not engineering. |
| Ship #3472 RED-default, spikes later | Already the plan's fallback. Acceptable but loses the empirical signal that S1/S2 exist to produce, and creates two phantom follow-through issues that depend on a human running a script. |

Decision driver: spikes are **scripts already in repo**, not design work. Bundling 30 minutes of operator script-running into a multi-day implementation PR is correct PR shape.

## User-Brand Impact

**Threshold:** `single-user incident` (inherited from parent plan §User-Brand Impact, lines 34-47).

The named failure modes from the parent plan remain:
- Surprise bill ($50+ on a manuscript Q&A session) — bounded by `cc-cost-caps.ts`.
- Fabricated chapter answer with no warning — bounded by loaded-chapter prefix + numeric-index routing.
- Refusal where chapter-chunking should have worked — bounded by S2 spike + outline heuristic.

**Phase 3.A revert tightens the invariant.** After the multi-agent review of PR #3440, the chapter-chunked **system-prompt directive** was reverted; both runners fall through to the `too_many_pages` bridge today. Shipping the directive without the matching dispatch-time content-block attachment would launder fabricated chapter answers under a confident `[Answering from chapter N]` prefix. The bundle PR's load-bearing rule: directive revival and dispatch attachment MUST land in the same commit. No partial directive in any intermediate commit on the branch.

**New failure mode surfaced by CPO refresh (delta #1, see Key Decisions):** cross-document confusion when the KB has more than one chapter-chunkable PDF. `selectChapter` operates per active PDF; the prefix doesn't name which book answered. A founder asking "summarize chapter 3" with two manuscripts attached can get the wrong book's chapter 3 silently. Addressed in AC #5-bis below.

## Key Decisions

### KD-1 — Bundle shape: single PR, spike outputs in PR body
Run both spikes inside `.worktrees/feat-pdf-chapter-chunking-bundle/` against Doppler-dev credentials before opening the PR for review. Paste S1 token counts and S2 fixture coverage table verbatim into the PR body as their own sections, prefixed with explicit `GREEN-S1` / `RED-S1` and per-fixture `usable` / `fall-through` verdicts. The implementation diff lives below the spike outputs. PR-body order is non-cosmetic — it lets review agents read the empirical signal first.

### KD-2 — S2 fixtures: switch from publisher PDFs to synthesized + public-domain
**Source:** CLO refresh assessment.

Current manifest at `apps/web-platform/scripts/spike/pdf-outline-fixtures.json` documents `sourceUrl: "TODO: operator records source URL (e.g., a Manning/O'Reilly purchase ...)"`. Manning/O'Reilly per-seat licenses forbid redistribution; the `sourceUrl` field would create a written record pointing at copyrighted material even when the binary itself is `.gitignore`d. This violates `cq-test-fixtures-synthesized-only` (the spirit, even though that rule was scoped to committed fixtures).

Mitigation, scoped to the manifest:
- **`outline-bearing.pdf`** — generate programmatically via `pdfkit` (or LaTeX `\tableofcontents` + 200 pages of lorem ipsum). Outline must include ≥10 top-level entries with depth ≥1 that resolve via `getDestination` → `getPageIndex`. Script lives at `apps/web-platform/scripts/spike/generate-outline-fixture.ts` (new, included in this PR).
- **`no-outline.pdf`** — pre-1929 US public-domain scan (archive.org PD set) or CC0 source. Manifest records the archive.org URL + SHA-256.

Manifest example sourceUrl updated to remove "Manning/O'Reilly purchase" and reference the generated/public-domain sources.

### KD-3 — Mid-stream cost-cap behavior must be explicit in tests
**Source:** CTO refresh assessment.

Plan §Risks (line 265) covers cap-check **between** routing and answer turns. Underspecified: cap exceeded **during** answer-turn streaming. Existing `cc-cost-caps.ts` mid-stream behavior governs, but the bundle PR adds an integration assertion: when cap is hit mid-stream, `state.activeChapter` MUST persist so the user's next turn does not pay another routing turn. Added as a new test scenario in `test/soleur-go-runner-chapter-chunked.test.ts`.

### KD-4 — Buffer-source decision: re-read per turn
**Source:** CTO refresh assessment + plan §Resume note (line 289).

Two shapes were left open by the plan: (a) `readFile(fullPath)` per turn vs (b) thread a `documentExtractBuffer` (binary) through the resolver result onto `documentExtractMeta`. The bundle commits to **(a) re-read per turn**:
- OS page cache makes hot-file re-reads ~5ms on a 30MB PDF (acceptable inside the routing→slice→answer envelope).
- Avoids carrying a 30MB binary on `documentExtractMeta` (which serializes through the runner state machine).
- Matches the existing pattern in both resolvers (which already read the file to extract text).

Shape (b) deferred. Re-evaluate if telemetry shows >100ms re-read p95 in production.

### KD-5 — Stale-context invalidation: clear activeChapter on PDF rotation
**Source:** CTO refresh assessment.

If `state.chapterChunkedContext` is set but a later turn's `documentExtractMeta.chapters` is empty (e.g., user replaces / rotates the PDF mid-conversation, or the source PDF is deleted from KB), the dispatch path MUST clear `state.activeChapter`, force re-route, and surface "the source PDF changed — re-routing." Add as a new test scenario.

### KD-6 — AC #5 extension: cross-document disambiguation
**Source:** CPO refresh assessment (delta).

Parent plan AC #5 covers misroute-correctable-in-one-turn within a single PDF. It does NOT cover: KB has >1 chapter-chunkable PDF attached, founder asks "summarize chapter 3" without naming the book, `selectChapter` picks one PDF silently.

Bundle PR ACs add:
- **AC #5-bis:** When the active KB context contains >1 chapter-chunked PDF, the loaded-chapter prefix MUST carry the document title: `[Answering from <book title>, chapter <N>: "<title>"]`. OR the routing turn returns a `kind: "ambiguous-which-document"` shape that lists the candidate PDFs and asks the user to choose.

Single-PDF case keeps the existing prefix shape — no change to the parent plan's already-tested first-text-block prefix injection.

### KD-7 — S1 outcome flip triggers re-review, not commit-and-merge
**Source:** CPO refresh assessment.

If the S1 spike GREEN-flips after review agents have already analyzed a RED-default dispatch diff, the `cache_control` marker would ship under stale review attention. Operational rule for the bundle PR:
- Run S1 BEFORE marking the PR ready for review (not after).
- If S1 outcome changes between draft and ready, the changed attachment line counts as a code change requiring a new review round (treat as a re-review trigger per `rf-review-finding-default-fix-inline`).

### KD-8 — Carry-forward verbatim from parent plan
The following parent-plan elements ship unchanged in the bundle:
- Domain sign-offs (CPO/CLO/CTO/CFO) — carry-forward stands per all three refresh agents.
- AC items #1, #2, #3, #4, #6, #7, #8, #9, #10, #11, #12.
- All four Sharp Edges (lines 268-273).
- Phase 3 implementation spec (lines 117-173).
- Risk inventory (lines 261-266).

The bundle PR's User-Brand Impact section in the PR body links back to the parent plan's section verbatim with the four KD-2/3/5/6 additions called out.

## Non-Goals

- Pivoting to embedding retrieval (#3450) unless S2 RED makes Phase 1 untenable. The bundle PR does **not** pre-implement #3450.
- Adding `pdf_metadata` as an agent-callable MCP tool (#3454) — acknowledged in parent plan, materially out of scope here.
- Adding shared `resolvePdfArtifactContext` module — parent plan adopted parallel resolvers; bundle preserves that shape.
- Side-channel via bare `@anthropic-ai/sdk` — explicitly rejected as v1 fallback in parent plan; bundle preserves.
- Cache-hit-rate logging (post-merge AC #15 in parent plan) — remains post-merge operator action, not part of the bundle PR.

## Open Questions

1. **S2 fixture generation script ownership** — does `generate-outline-fixture.ts` live in `scripts/spike/` (alongside the probe scripts) or `scripts/test-helpers/`? Lean toward `scripts/spike/` since it only serves S2; revisit if a second use case lands.
2. **Cross-document disambiguation copy** — the exact wording of `kind: "ambiguous-which-document"` response copy is a CMO-light decision deferred to implementation. The plan author should propose copy + send to user for sign-off before merging.
3. **Generated PDF size cap** — the synthesized outline-bearing fixture should be 200-500pg per plan §S2. Confirm the generator hits the page range without producing a multi-MB binary that fails ingestion.

## Domain Assessments

**Assessed (refresh):** Product (CPO), Legal (CLO), Engineering (CTO). Carry-forward (unchanged): Finance (CFO).

**Assessed (omitted on scope):** Marketing, Operations, Sales, Support — bundle does not change customer-facing surface beyond what parent plan already covered.

### Product (CPO)

**Summary:** Carry-forward sign-off stands. One delta — cross-document disambiguation (KD-6) is a new AC item user-impact-reviewer would have flagged at PR review. Bundle risk flagged: S1 outcome flip mid-review (KD-7).

### Legal (CLO)

**Summary:** Carry-forward stands. One delta — S2 fixture manifest must switch from publisher-PDF examples to synthesized + public-domain (KD-2). S1 spike payload verified hard-coded synthetic. No `compliance-posture.md` impact.

### Engineering (CTO)

**Summary:** Zero 4-day drift on touched files (only the 3.A merge itself). Three underspecified edges in #3472 (KD-3, KD-4, KD-5). All four Sharp Edges from parent plan remain load-bearing. Bundle risk: medium, mitigated by spike-outputs-in-PR-body convention (KD-1).

## Capability Gaps

None reported. The bundle reuses existing skills (`work`, `review`, `ship`) and existing agents (`user-impact-reviewer`, `architecture-strategist`, `data-integrity-guardian`). The only new artifact is the synthesized-fixture generator script (KD-2), which is implementation work, not a missing capability.

## Next Steps

- Spec: `knowledge-base/project/specs/feat-pdf-chapter-chunking-bundle/spec.md` — bundle-scoped spec referencing the parent plan, encoding KD-1 through KD-8 as bundle-specific ACs.
- Plan handoff: `/soleur:plan` will read the parent plan (`2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md`) and this bundle brainstorm; minor plan addendum needed for KD-2 fixture-generator script and KD-3/4/5/6 ACs.
- Bundle-scoping notes appended to #3472, #3473, #3474 pointing all three at this brainstorm + draft PR #3550.
