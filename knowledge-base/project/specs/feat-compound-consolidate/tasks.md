---
title: Tasks — KB Recall-Quality Prereq (#5298)
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-14-feat-kb-recall-quality-prereq-plan.md
spec: knowledge-base/project/specs/feat-compound-consolidate/spec.md
created: 2026-06-14
---

# Tasks: KB Recall-Quality Prereq (gate for deferred #5292)

Derived from the finalized (post-3-reviewer) plan. v1 = decision apparatus, NOT the consolidation pass.
**Zero corpus mutation** (FR4 live demo cut). **Pure-local metric** (no external API).

## Phase 1 — Deterministic redundancy metric + SSH-free surface (FR1, FR2)

- [ ] 1.1 Write failing self-test first (`cq-write-failing-tests-before`): `scripts/kb-staleness-metric.sh --self-test`
  with synthesized fixtures asserting (a) positive near-dup pair, (b) false-negative pair (titles diverge
  in first tokens), (c) title-less file → slug fallback, (d) exempt-class file excluded from `top_pairs`.
- [ ] 1.2 Implement `scripts/kb-staleness-metric.sh` (pure-local, NO API): corpus = learnings excl.
  `**/archive/**`; all-pairs `Jaccard(title-tokens ∪ tags) ≥ 0.6` (no blocking key); title-less slug
  fallback; exempt classes (`compliance/`, `security-issues/`, incident/PIR, frontmatter
  `category: compliance|security-issues`/`regulation:`) in denominator but never in `top_pairs`.
- [ ] 1.3 Emit `knowledge-base/project/kb-redundancy-metrics-2026-06-14.json` (no `schema` field):
  `corpus_count`, `redundant_pairs`, `density`, `top_pairs[]`. Make self-test pass (GREEN).
- [ ] 1.4 Run once → commit the 2026-06-14 baseline JSON.
- [ ] 1.5 Create `knowledge-base/project/kb-health.md`: snapshot (corpus_count, baseline density, top-3
  pairs) + JSON pointer + the FR4 closure-lifecycle one-liner (`superseded_by:` additive convention).
- [ ] 1.6 If baseline density ≥ 15%, note in kb-health.md that the gate's absolute shortcut is inert
  (only +5pp delta governs) so the gate is not pre-decided.

## Phase 2 — Dated checkpoint folded into existing sweeper + #5292 wiring (FR5, FR6)

- [ ] 2.1 Edit `.github/workflows/scheduled-followthrough-sweeper.yml`: add a guarded step — on/after
  2026-08-13, if #5292 open and no prior `kb-checkpoint` marker comment, run `kb-staleness-metric.sh`,
  apply spec §Re-Evaluation Criteria, comment the verdict on #5292. `GITHUB_TOKEN` + `permissions:
  { contents: read, issues: write }` (NOT App token, NOT PAT). CR/LF-strip values echoed to `::notice::`.
- [ ] 2.2 Validate: `actionlint` clean; `bash -n` on the extracted `run:` snippet; date-guard + open/
  unadjudicated guard present; no Anthropic/agent. (Fallback: standalone date-guarded `scheduled-*.yml`.)
- [ ] 2.3 `gh issue edit 5292`: add a dated `named_outcome:` field (empty) + the FR4 convention one-liner.
- [ ] 2.4 Annotate brainstorm line ~59 stale 3-clause gate as `[Superseded by spec §Re-Eval]` (done in plan
  session — verify it remains).

## Phase 3 — Verify & ship

- [ ] 3.1 All Pre-merge ACs green (self-test, JSON shape, no-API grep, zero-corpus-mutation grep,
  actionlint, single-authoritative-gate check).
- [ ] 3.2 PR body: `Closes #5298`, `Ref #5292` (never `Closes #5292`).
- [ ] 3.3 `/soleur:review` → `/soleur:qa` → ship per lifecycle.
