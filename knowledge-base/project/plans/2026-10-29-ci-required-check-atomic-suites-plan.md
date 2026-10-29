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

Issue #11562 (child of epic #11556). Measured diagnosis (brainstorm `knowledge-base/project/brainstorms/2026-10-29-required-check-time-brainstorm.md`): leg 1/8 runs 54.9 min because `plugins/soleur/test/ci-pr-affected-replay.test.sh` costs 24.9 min on a PR run while manifest-priced at 1,184 ms (floor — never measured on main); leg 3/8 runs 50.9 min because `scripts/test-all-affected` costs 29.5 min on a PR run vs 337 s main median (5.3× PR-event divergence). Suite-sum ≈ wall-clock on every leg (~1 min/leg setup), so the work is bounding/splitting two suites and re-pricing the manifest — not rebalancing or caching.

## Premise Validation

- #11562 OPEN, #11556 OPEN (epic), #11563/#11564 filed by this brainstorm. No cited blocker stale.
- `scripts/suite-shard-legs.tsv` (n=8, 668 rows) + `scripts/regenerate-shard-manifest.py` exist and are the live mechanism (ADR-240) — verified by reading ci.yml:1428–1456 + runbook.
- CORRECTION to a domain-leader claim: `shard-totality-mutations` is **not** in `scripts/required-checks.txt` (only `test` at line 68) — the CLO's "remains required" invariant is moot; totality coverage is preserved as a proof mechanism, not a required-name invariant.
- Mechanism minimality (0.6b): every mechanism the ask names already exists — `--rows` suite split (#8864/`shard-totality-mutations`), `--runs 5` regen, bounded fixture corpora (standard suite shape). Cut list: no new machinery; scheduled regen deferred to #11564.

## Value-Proposition Measurement

`gh api repos/jikig-ai/soleur/actions/runs/40936890587/jobs` + `gh run download <run> -n suite-timings-scripts-N`: legs 1/8,3/8 = 54.9/50.9 min wall, 54.2/50.1 suite-sum; same two suites dominate merge_group run 40936383604 (20.1/18.2 min). Post-surgery expectation: worst leg ≤ ~28 min PR, ≤ ~38 min merge_group.

## Implementation Phases

### Phase 1 — Diagnose `test-all-affected` PR-vs-main divergence (G1, OQ1)

Read `scripts/test-all-affected.test.sh` (4,116 lines) and `scripts/ci-pr-affected-replay.py` to identify which phase is event-sensitive: merge-base derivation, the audit reach (source-closure walk over depth-8 `source` chains), the naming walk, or the live `gh` run enumeration. Compare the suite's own per-phase timing if it emits any; otherwise instrument once locally with a stubbed diff surface. Then choose, per suite:

- **Split** via the `--rows` precedent (#8864, `shard-totality-mutations` `1-14/15-28/29-42`) when the work is divisible and all arms must run; or
- **Bound** via a fixture/pinned corpus when a live-repo enumeration is the cost and a recorded corpus covers the same assertions (the advisory `affected-index-ratchet` job + `scripts/followthroughs/` soak probes keep the live path exercised elsewhere).

### Phase 2 — Bound `ci-pr-affected-replay.test.sh` (G2)

5,062 lines; floor-priced 1.2 s. Cap live `gh` run enumeration behind a bounded replay corpus (fixtures committed under its `fixtures/` or a `--rows` split if the mutation rows themselves are the cost). Preserve coverage: the suite's own controls (anti-vacuity floor, instrument self-test, "a mutant that crashes is never a kill") must stay green; FR2.

### Phase 3 — Full manifest regen (G3)

`python3 scripts/regenerate-shard-manifest.py --runs 5 --write` and `--group heavy --runs 5 --write` — re-prices the 74 floor rows (`watch-*` pinned at 140–150 s). Then `--legs K` dry-run for K ∈ {8, 10, 12} to check whether a K bump is worth the extra per-leg setup + runner-pool pressure (COO: ~60-job shared concurrency). If K changes, same-PR edit to ci.yml matrix + both manifests (generator refuses K≠N). Update stale ci.yml comments (~9.5 min/leg, "collected but not yet consumed") and the runbook topology table.

### Phase 4 — Fresh p90 baseline + docs (G4, G5)

Compute a fresh PR required-check p90 (cohort method: queue vs execution vs ejection-requeue) over the last ~30 green PR runs via the jobs API; record method + numbers in the runbook's Measured history. Update spec/notes.

## Files to Edit

- `scripts/test-all-affected.test.sh` — split or bound per Phase 1 diagnosis
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` (+ any new `fixtures/` corpus) — Phase 2
- `scripts/suite-shard-legs.tsv`, `scripts/suite-shard-legs-heavy.tsv`, `scripts/suite-durations.tsv`, `scripts/suite-durations-heavy.tsv` — regenerated (never hand-edited)
- `.github/workflows/ci.yml` — stale comments; matrix arrays only if Phase 3 K dry-run justifies
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` — topology + Measured history

## Guard Contract / Invariants (CLO + machinery)

- `scripts/required-checks.txt` byte-identical; `test` aggregate name untouched; no leg becomes a required context.
- Totality coverage preserved: `scripts-shard-totality.test.sh` + 42-row mutation battery stay green; every suite runs on exactly one leg.
- Manifests stay committed + deterministic (regenerate, never hand-merge).
- `fetch-depth: 0` preserved on the CLA-dependent shard checkout; `merge_group` synthetic re-reporting preserved; NO concurrency-cancel on `merge_group`.
- Light↔heavy moves only with toolchain-parity evidence (`scripts-shard-runtime-coverage.test.sh`); `timeout-minutes: 60` unchanged.
- No affected-selection (S4 PR C/D) touch — parked behind #10448/#10859.

## Observability

```yaml
liveness_signal:
  what: leg-balance of test-scripts — max predicted suite time per leg
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
  - mode: floor-priced suite silently growing (the ci-pr-affected-replay class)
    detection: grep `floor` rows in scripts/suite-durations.tsv vs measured reality — automated probe deferred to #11564
    alert_route: manual regen; probe filed
  - mode: manifest/matrix n-mismatch
    detection: runner degrades to positional round-robin with stderr notice
    alert_route: scripts-shard-manifest.test.sh red
logs:
  where: suite-timings-*.tsv artifacts + committed scripts/suite-durations{,-heavy}.tsv
  retention: artifacts 14 days; committed tables permanent
discoverability_test:
  command: grep '^# n=' scripts/suite-shard-legs.tsv
  expected_output: "# n=8"
```

## Alternative Approaches Considered

- Measure-only regen + baseline (deferred suite surgery): leaves ~55-min overshoot — rejected; the manifest cannot price an unmeasurable suite.
- Move the two suites to `test-scripts-heavy`: relocates the atomic floor into a 3-leg group; heavy legs carry different toolchain/timeout math (TR2) — rejected as sole fix; remains an option if splitting proves unsafe.
- Scheduled regen machinery now: scope inflation + bot-PR surface — filed as #11564 instead.
- Job-level path filters on the heavy legs: rejected mechanism per ADR-262 (unreported-vs-skipped semantics in a required context).

## Acceptance Criteria

- Worst `test-scripts` light leg ≤ ~28 min on a PR run (from ~55); merge_group critical path ≤ ~38 min (from ~53).
- Per-leg `suite-timings-*` spread ≤ ~10 min on a green PR run.
- `ci-pr-affected-replay.test.sh` and `test-all-affected` bounded or split with controls green (anti-vacuity floor, instrument self-test, mutation rows).
- Both manifests + durations tables regenerated via `--runs 5`; `grep '^# n='` matches matrix N.
- `scripts/required-checks.txt` byte-identical; totality tests green; no `merge_group` cancellation introduced.
- Runbook records fresh p90 baseline + method.

## Domain Review (carry-forward from brainstorm)

- **Engineering:** machinery exists; gap is drift + atomic floor. Never hand-merge TSVs; sticky-LPT diff-stability means regen conflicts on sibling PRs regenerate rather than merge.
- **Product:** Lever A cannot reach the epic's ≤20-min goal alone — honest intermediate milestone; #11563 holds the user-facing half.
- **Legal:** clean; invariants above preserve the Art. 5(2) evidence chain; no doc/register amendments.
- **Operations:** public repo → runner minutes $0; constraint is the ~60-job concurrency pool (relevant to any K bump).

## Open Questions Resolved at Work Time

1. `test-all-affected` divergence mechanism — Phase 1 diagnosis decides split vs bound.
2. `ci-pr-affected-replay` bounded-corpus design — how much of the 25-min live enumeration is load-bearing.
3. K=8 vs larger — decided by Phase 3 `--legs K` dry-run.
