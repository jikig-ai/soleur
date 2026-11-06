---
title: "ci: split/bound the two atomic S4 suites dominating test-scripts legs 1/8 and 3/8"
date: 2026-10-29
slug: ci-required-check-atomic-suites
branch: feat-11556-required-check-time
issue: 11562
epic: 11556
lane: cross-domain
type: chore
brand_survival_threshold: single-user incident
---

# Plan: bound the two atomic S4 suites + full manifest regen + p90 baseline

## Overview

Issue #11562 (child of epic #11556). Measured diagnosis (brainstorm `knowledge-base/project/brainstorms/2026-10-29-required-check-time-brainstorm.md`; artifact legs are 0-based `suite-timings-scripts-{0..7}` = shards `{1..8}/8`): leg 1/8 runs 54.9 min because `plugins/soleur/test/ci-pr-affected-replay.test.sh` costs 24.9 min while manifest-priced at 1,184 ms (floor — never measured on main, **not event-sensitive**: 20.1 min on merge_group); leg 3/8 runs 50.9 min because `scripts/test-all-affected` costs 29.5 min on PR and 18.2 min on merge_group vs 337 s main median — a **non-push-event** divergence (~4–5×), not PR-specific. Suite-sum ≈ wall-clock on every leg (~1 min/leg setup), so the work is bounding/splitting two suites and re-pricing the manifest — not rebalancing or caching.

## Premise Validation

- #11562 OPEN, #11556 OPEN (epic), #11563/#11564 filed by this brainstorm. No cited blocker stale.
- `scripts/suite-shard-legs.tsv` (n=8, 668 rows) + `scripts/regenerate-shard-manifest.py` exist and are the live mechanism (ADR-240).
- CORRECTION: `shard-totality-mutations` is **not** in `scripts/required-checks.txt` (only `test` at :68; the job self-describes "NOT a required check", ci.yml:1746–1755) — spec TR1's "stays required" is a stale invariant (spec amended).
- Plan-review verified the cost driver: `ci-pr-affected-replay.test.sh` is **fully stubbed** (PATH-shim `gh`, recorded fixtures) — no live enumeration exists to cap. Its 24.9 min is ~1,276 assertions / ~469 mutants × Python-proc respawn + `rt_*` fixture repos + `ow_*` real-second soak probes. The fix is row-splitting, not corpus bounding.

## Scope Check (Ask Mapping)

| Verbatim ask (issue #11562 / spec) | Plan item |
|---|---|
| Diagnose `test-all-affected` divergence; split or bound | Phase 1 → Phase 3 |
| Bound/split `ci-pr-affected-replay` | Phase 2 (rows split — corrected mechanism) |
| Full `--runs 5` regen both manifests | Phase 3 (light only — heavy unchanged, see note) |
| Fresh p90 baseline + runbook/spec updates | Phase 4 |
| CLO invariants preserved | Guard Contract below |

## Research Insights / Cut List

- Mechanism minimality: every mechanism named already exists — `--rows` label-split (precedent: `lint-orphan-test-suites` `-a`/`-b`, #8864 — an **in-runner label** split inside a leg, *not* the `shard-totality-mutations` job-matrix shape, #9035), `--runs 5` regen, `--timings-dir` offline pricing, `in_range` row plumbing.
- Cut: bounded-replay-corpus for the replay suite (already fixture-hermetic — no such cost exists); K-bump path (kept only as a conditional fallback — see Phase 3); heavy-group regen (no suite changes group — pure churn on a second conflict surface); scheduled regen machinery (deferred #11564).

## Value-Proposition Measurement

`gh api .../actions/runs/40936890587/jobs` + `gh run download -n suite-timings-scripts-N`: legs 1/8,3/8 = 54.9/50.9 min wall ≈ 54.2/50.1 suite-sum; same two suites dominate merge_group 40936383604. Post-surgery expectation: worst leg ≤ ~28 min PR, ≤ ~38 min merge_group.

## Implementation Phases

### Phase 1 — Diagnose `test-all-affected` (G1, decide bound vs split)

The suite is hermetic (fixtures; `ENV_SCRUB` unsets `CI`) but walks the **real repo's** enumerate/diff surface — cost scales with the merged diff. Recipe: wrap `SECONDS` deltas per named row-block (runner honors `TEST_TIMING_LOG`), or run once locally with an emulated merge-base diff and rank. Decision rule: if the divergence lives in live-IO (real-repo walk / `gh` surface) → **bound** (pinned corpus — kills the variance class; the advisory `affected-index-ratchet` job exercises the live path on every PR, ci.yml:417). If it lives in divisible fixture-portable compute → `--rows` split. CTO weighting: bound-first for a variance bug. Record the rationale in the PR body.

### Phase 2 — `--rows` label-split `ci-pr-affected-replay.test.sh` (G2)

Split the `row_*`/`rt_*`/`ow_*` arms across **in-runner labels** (the lint-orphan `-a`/`-b` shape — each arm a separately registered suite the LPT packer distributes). Preconditions this must carry:

- `in_range` sequencing — every site dispatched on every leg, only ranged ones execute (so relevance declines stay identical per arm), + `_EXPECTED_EXECUTED` equality — the lint-orphan contract (`scripts/lint-orphan-test-suites.test.sh`).
- `DECLARED_TOTAL`-style census per suite family — `FLOOR_ASSERTIONS=1276` / `FLOOR_MUTANTS=469` / `OW_MUT_RUN >= OW_SITES` are exact-count floors that fail under naive `--rows`; each must be re-expressed as ranged-sum equality (the `shard-totality-mutations` `_rows_tile_check` / Direction-2 contract).
- New labels registered via `run_suite`+`skip_suite` pairs **inside the same relevance gate arm** so legs never diverge on declines; verify the totality census covers a battery in `plugins/soleur/test/` (it does — precedents live there) and, if `test-all-affected` splits, that the census reaches `scripts/`.
- Placement: tabled-at-floor arms deal onto least-loaded legs (could re-pile); price the new arms via `--timings-dir` from a local run *in the same PR* so the manifest lands them honestly.

### Phase 3 — Apply decision + regen (G1/G3)

- `test-all-affected`: apply Phase-1 outcome (bound → pinned corpus inside the same suite file; split → same Phase-2 preconditions). Fallback if neither reaches ≤ ~28 min: heavy-group relocation or partial split + explicitly-accepted floor pricing.
- `python3 scripts/regenerate-shard-manifest.py --runs 5 --write` — light group only. **Sequencing:** event-gated suites (the replay suite has never appeared in a main-run timing sample) re-price to `src=floor` on a `--runs` regen — price them via `--timings-dir` from the local/CI runs in this PR, or state the accepted-floor rationale sized to the post-bound cost. Land the regen as the **last isolated commit**; document "re-run `--incremental` after rebase" in runbook + PR body (sibling `--incremental` deltas conflict on durations; never hand-merge).
- `--legs K` dry-run for K ∈ {8,10,12} as **verification only**: a K bump ships only if post-surgery predicted worst leg still exceeds the bound (COO: ~60-job pool).
- Delete or justify the stray tracked snapshots `scripts/suite-shard-legs.tsv.n` / `scripts/suite-durations.tsv.n` (stale 2026-10-12 copy, no consumer — conflict/drift trap).
- Fix stale ci.yml comments (~9.5 min/leg, "collected but not yet consumed") + runbook topology table.

### Phase 4 — Baseline + close-out (G4/G5)

- Fresh PR leg-time sample via jobs API (~10–15 recent green PR runs; queue vs execution decomposition); record in runbook Measured history. The full epic-level p90 cohort stays on #11556 — this PR proves its own ACs.
- Update the epic issue with actuals (spec AC) + comment on #11562.
- Amend spec TR1 (totality not required — done at plan time).
- **Regen-ownership checkpoint (CTO):** implementer owns a dated first post-merge check (~2 weeks): `--runs 5` dry-run, diff predicted-vs-incumbent, paste into runbook Measured history — this is also the observation that arms #11564's re-eval trigger.
- Rollback note: if post-merge coverage regression found, revert the suite edit then `--incremental --write` — never revert TSVs over sibling incremental deltas.

## Files to Edit

- `scripts/test-all-affected.test.sh` — bound (pinned corpus) or `--rows` per Phase 1
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` — `--rows` label-split + ranged-floor retrofit
- `scripts/ci-pr-affected-replay.py` — if bounding caps an enumeration path script-side (Phase 1 decides)
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` — regenerated only (never hand-edited); delete `.tsv.n` strays or justify
- `scripts/test-all.sh` — new `run_suite`/`skip_suite` label registrations for split arms (inside same gate arms)
- `.github/workflows/ci.yml` — stale comments only (no matrix edit unless conditional K fires)
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` — topology, Measured history, rebase-regen note, ownership checkpoint

## Guard Contract / Invariants

- `scripts/required-checks.txt` byte-identical; `test` aggregate name untouched; no leg becomes a required context.
- Coverage preserved: totality guards green; every suite (incl. new split labels) runs on exactly one leg; per-suite floors re-expressed ranged — *bounding keeps labels identical so totality cannot see intra-suite cuts: the suite's own floors/mutation rows are the only net, they must stay non-vacuous.*
- **TR5:** any new skip path records its classifier rationale inline per the `ci-shard-totality-classify.sh` precedent.
- Manifests committed + deterministic; FR3 = manifests regenerated **in the same commit** as any matrix/K change (generator refuses K≠N).
- `fetch-depth: 0` on `test-webplat` (CLA epoch derivation) preserved; `merge_group` synthetic re-reporting preserved; NO concurrency-cancel on `merge_group`; `timeout-minutes: 60` unchanged.
- No affected-selection (S4 PR C/D) touch — parked behind #10448/#10859.

## Observability

```yaml
liveness_signal:
  what: leg-balance of test-scripts — max suite time per leg
  cadence: every ci.yml run (suite-timings-* artifacts, if: always())
  alert_target: operator via runbook Measured history; drift probe deferred to #11564
  configured_in: .github/workflows/ci.yml test-scripts upload step
error_reporting:
  destination: CI job failure + suite verdict lines in test-all.sh output
  fail_loud: yes — failed leg fails the required `test` aggregate
failure_modes:
  - mode: leg exceeds bound after surgery
    detection: suite-timings artifact sum per leg > threshold
    alert_route: red `test` aggregate; runbook regen instructions
  - mode: floor-priced split arms land unpriced / re-pile on one leg
    detection: new labels' src=floor rows vs --timings-dir measured values; leg-spread check
    alert_route: red leg on the run; --timings-dir re-price
  - mode: silent 60-min timeout kill (only bound, no annotation — legs at 54.9 were ~5 min from it)
    detection: job conclusion=killed/cancelled with no suite verdict
    alert_route: red `test` aggregate; job log tail
  - mode: floor-priced suite silently growing (the ci-pr-affected-replay class)
    detection: grep `floor` rows in scripts/suite-durations.tsv vs measured — automated probe deferred to #11564; interim = the Phase-4 ownership checkpoint
    alert_route: ownership checkpoint + probe filed
logs:
  where: suite-timings-*.tsv artifacts + committed scripts/suite-durations{,-heavy}.tsv
  retention: artifacts 14 days; committed tables permanent
discoverability_test:
  command: grep '^# n=' scripts/suite-shard-legs.tsv
  expected_output: "# n=8"
```

## Alternative Approaches Considered

- Bounded replay corpus for the replay suite — **rejected on the facts**: the suite is already fixture-stubbed; cost is mutant respawn volume, not live enumeration.
- Job-matrix split (shard-totality-mutations shape) — rejected: creates new job names/runner overhead; label-split keeps arms inside the leg packer.
- Move suites to `test-scripts-heavy` — relocates the atomic floor into a 3-leg group; kept as Phase-3 fallback only.
- Measure-only regen + baseline — leaves ~55-min overshoot; rejected.
- Scheduled regen machinery — filed #11564 (probe semantics undesigned; interim = ownership checkpoint).

## Acceptance Criteria

- Worst `test-scripts` light leg ≤ ~28 min on this PR's green run; merge_group critical path ≤ ~38 min.
- **FR1 restored:** no single light-leg *suite* > ~25 min (per-suite bound, not just leg totals).
- Per-leg `suite-timings-*` spread ≤ ~10 min on a green PR run.
- Split arms satisfy ranged-floor equality (in_range/DECLARED_TOTAL contract); suite controls green.
- Both manifests + durations regenerated via `--runs 5` (+ `--timings-dir` for event-gated rows); `# n=` matches matrix N; **same commit** as any K change.
- `scripts/required-checks.txt` byte-identical; totality tests green; no `merge_group` cancel; spec TR1 amended.
- Runbook records fresh baseline + ownership checkpoint; epic #11556 updated with actuals.

## Domain Review (carry-forward)

- **Engineering:** machinery exists; gap is drift + atomic floor. Never hand-merge TSVs; regen last-commit + rebase re-run note.
- **Product:** Lever A cannot reach ≤20 min alone — honest intermediate milestone; #11563 holds the user-facing half.
- **Legal:** clean; invariants preserve the Art. 5(2) evidence chain; corpus-bound suites keep totality-blind coverage only via their own non-vacuous floors (TR5 + ranged-floor contract).
- **Operations:** runner minutes $0 (public repo); ~60-job concurrency pool is the real constraint on any K bump; corpus freshness = the advisory ratchet job is the guard.

## Open Questions Resolved at Work Time

1. `test-all-affected` divergence mechanism — Phase 1 decides bound vs split (bound-first lean).
2. `ci-pr-affected-replay` arm partition — which rows go to which label (pack via `--timings-dir` pricing).
3. Regen cadence ownership — interim = Phase-4 checkpoint; automation = #11564.
4. K optimum — only if post-surgery predicted worst leg still exceeds bound.
