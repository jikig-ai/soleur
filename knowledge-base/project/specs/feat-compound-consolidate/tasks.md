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

- [x] 1.1 Self-test (`cq-write-failing-tests-before`): `--self-test` asserts (a) positive near-dup,
  (b) false-negative pair (first-token divergent — no blocking key), (c) title-less slug fallback,
  (d) exempt-class excluded from `top_pairs`. 7/7 pass.
- [x] 1.2 Implemented `scripts/kb-staleness-metric.sh` (pure-local, NO API): all-pairs
  `Jaccard(title∪tags)≥0.6`, no blocking key, title-less slug fallback, exempt classes in denominator
  but never in `top_pairs`.
- [x] 1.3 Emits `kb-redundancy-metrics-<date>.json` (no `schema` field): corpus_count, redundant_pairs,
  density, top_pairs. Self-test GREEN.
- [x] 1.4 Baseline committed: **corpus 1550, density 0.19%** (3 pairs) — far below the 15% floor.
- [x] 1.5 `kb-health.md` created: snapshot + JSON pointer + closure-lifecycle one-liner.
- [x] 1.6 Baseline 0.19% < 15% → kb-health.md notes the absolute shortcut is **inert**; only +5pp delta
  governs → gate not pre-decided.

## Phase 2 — Dated checkpoint via sweeper follow-through directive + #5292 wiring (FR5, FR6)

> **[Work-time adaptation]** No workflow YAML edit needed. The sweeper exposes a `soleur:followthrough`
> directive convention (script under `scripts/followthroughs/` + native `earliest=` date guard + `env -i`
> scoped secrets). The exit-code semantics (0=PASS→auto-close, 1=FAIL→comment+stay-open) map exactly onto
> kill/build by framing the verified condition as "is the kill condition met?". Cleaner than editing the
> workflow; reuses its entire security model + `GITHUB_TOKEN` auth. Tested via the two convention suites.

- [x] 2.1 Create `scripts/followthroughs/kb-consolidation-checkpoint.sh` — runs `kb-staleness-metric.sh`,
  applies spec clause 1 (redundancy), exit 0 (not material → auto-close wontfix) / 1 (material →
  build-candidate, stay open for founder named_outcome) / 2 (transient). Pure-local, no secrets.
- [x] 2.2 Validate: `shellcheck` clean; runs under sweeper `env -i` sandbox; both verdict branches tested;
  `sweep-followthroughs.test.sh` (23/23) + `ship-followthrough-directive.test.sh` pass.
- [x] 2.3 `gh issue edit 5292`: added directive + dated `named_outcome:` field + `follow-through` label;
  issue stays OPEN.
- [x] 2.4 Brainstorm line ~59 stale 3-clause gate annotated `[Superseded by spec §Re-Eval]` (plan session).

## Phase 3 — Verify & ship

- [ ] 3.1 All Pre-merge ACs green (self-test, JSON shape, no-API grep, zero-corpus-mutation grep,
  actionlint, single-authoritative-gate check).
- [ ] 3.2 PR body: `Closes #5298`, `Ref #5292` (never `Closes #5292`).
- [ ] 3.3 `/soleur:review` → `/soleur:qa` → ship per lifecycle.
