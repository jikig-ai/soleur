---
title: "CI required-check time — split/bound the two atomic S4 suites + manifest regen + p90 baseline"
status: specified
issue: 11562
epic: 11556
brainstorm: knowledge-base/project/brainstorms/2026-10-29-required-check-time-brainstorm.md
branch: feat-11556-required-check-time
pr: 11561
date: 2026-10-29
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Spec: required-check time — atomic-suite surgery + regen + baseline (#11562, epic #11556 Lever A)

## Problem Statement

Epic #11556 targets required-check wall-clock ~1 h → ≤20 min (PR) / ≤15 min (merge queue). Its Lever-A premise was partially stale: duration-derived shard assignment already shipped via ADR-240 (`scripts/suite-shard-legs.tsv`, sticky-LPT over `suite-timings-*` medians; `scripts/regenerate-shard-manifest.py`). Decomposition of run 40936890587's `suite-timings-scripts-{0..7}` artifacts shows the two slow legs are not imbalance — each carries ONE dominant atomic suite that no manifest rebalance can split:

- `plugins/soleur/test/ci-pr-affected-replay.test.sh` on leg 1/8: priced **1,184 ms (floor — never measured on main)**; actual **24.9 min** on the PR run, **20.1 min** on merge_group.
- `scripts/test-all-affected` on leg 3/8: priced **337 s (main median)**; actual **29.5 min** on the PR run (5.3× divergence), **18.2 min** on merge_group.

The remaining ~111−54 ≈ 57 overshoot-minutes are mild PR-event inflation across the other six legs (17.6–25.1 vs ~15 predicted). Per-leg setup is ~1 min (suite-sum ≈ wall-clock), so dependency caching is near-worthless; cancel-in-progress and fail-fast ordering are already shipped or counterproductive.

## Goals

- **G1.** Diagnose `test-all-affected`'s PR-vs-main cost divergence (337 s → 1,772 s) and then split ( `--rows` precedent, #8864/`shard-totality-mutations`) or bound it so no single light leg exceeds ~25 min of suite time.
- **G2.** Bound `ci-pr-affected-replay.test.sh`: pin a bounded replay corpus (fixtures) and/or cap live run enumeration; the live enumeration path stays exercised by the existing advisory `affected-index-ratchet` job.
- **G3.** Full regen: `python3 scripts/regenerate-shard-manifest.py --runs 5 --write` for both groups — re-prices the 74 floor rows (`watch-*` pinned at 140–150 s) that `--incremental` carries verbatim; then evaluate `--legs K` dry-run for the post-surgery pack.
- **G4.** Fresh PR required-check p90 baseline (cohort method: queue vs execution vs ejection-requeue), recorded in the sharding runbook's Measured history — the Oct-4 figure (p90 24.4, n=102) predates S4 tooling growth.
- **G5.** Update `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` topology/history and the stale ci.yml comments (e.g. ~9.5 min/leg prediction, "collected but not yet consumed").

## Non-Goals

- **NG1.** Dependency/tool/browser caching work — measured ~1 min/leg setup; derive-cache restore is contractually bound to parked PR D (#10414).
- **NG2.** Serial job ordering / fail-fast staging — consumes the 73/75 declared-path budget and regresses green-path p90, the DoD metric.
- **NG3.** `merge_group` battery reduction, dedupe, or cancellation — ADR-276 non-negotiable; Lever-B question already answered (same atomic floor, not duplication).
- **NG4.** Affected-selection (S4 PR C/D) re-attempt — parked behind index completion (#10448) + required ratchet (#10859).
- **NG5.** Scheduled regen cadence / floor-row-drift automation — Productize Candidate `ci-shard-balance-watch`, filed as deferred issue.
- **NG6.** Lever D (`deploy-script-tests` red, #10781), Lever E (digest reporting), Lever F (user CI layout — placeholder filed).
- **NG7.** `registry-gate-mutation-battery` split — deferred; tracked by open #9323.

## Functional Requirements

- **FR1.** After the change, no `test-scripts` light leg carries a suite priced or measured above ~25 min on a PR run.
- **FR2.** `ci-pr-affected-replay.test.sh` retains its ratchet/battery coverage via `--rows` label-split (suite is fixture-stubbed; cost is mutant-respawn volume, not live enumeration — plan-review corrected); ranged-floor equality preserved (its own self-tests stay green).
- **FR3.** Both `suite-shard-legs{,-heavy}.tsv` and `suite-durations{,-heavy}.tsv` regenerated in the same commit as any K/matrix change (generator refuses K≠N).
- **FR4.** The PR records the fresh p90 baseline and method in the runbook.

## Technical Requirements

- **TR1.** CLO invariants: `scripts/required-checks.txt` byte-identical; totality coverage preserved (`shard-totality-mutations` is NOT a required context — verified 2026-10-29, `required-checks.txt:68` carries only `test`); manifests committed and deterministic; `fetch-depth: 0` preserved on the CLA-dependent shard; `merge_group` synthetic re-reporting preserved; no concurrency-cancel on `merge_group`.
- **TR2.** Light↔heavy leg moves are NOT free (heavy carries no likec4, different timeout math) — any suite relocation must respect the toolchain-parity assertion (`scripts-shard-runtime-coverage.test.sh`).
- **TR3.** Split suites must keep totality coverage (`scripts-shard-totality.test.sh`, 42-row mutation battery).
- **TR4.** `timeout-minutes: 60` stays (silent bound; ~6× post-surgery nominal, do-not-lower per ci.yml comment chain).
- **TR5.** If any suite gains a new skip path, record the classifier rationale inline per the `ci-shard-totality-classify.sh` precedent (CLO P2).

## Acceptance Criteria

- Worst `test-scripts` leg ≤ ~28 min on a PR run (from ~55).
- merge_group critical path ≤ ~38 min (from ~53).
- `gh api .../jobs` + `suite-timings-*` decomposition shows leg spread ≤ ~10 min.
- All CLO invariants (TR1) verified green post-merge.
- Fresh p90 baseline recorded; epic #11556 updated with actuals.

## Open Questions (from brainstorm)

1. `test-all-affected` 5.3× PR-vs-main divergence mechanism — diagnose first (OQ1).
2. `ci-pr-affected-replay` bounded-corpus design — how much of the 25-min live enumeration is load-bearing vs pinnable (OQ2).
3. K=8 optimum after suite surgery — `--legs K` dry-run decides (OQ5).
4. Regen cadence ownership pending `ci-shard-balance-watch` (OQ4).
5. Epic DoD amendment for the user-facing half — operator decision at epic review (OQ3).

## Domain Assessments (carry-forward)

- **Engineering:** machinery shipped; gap is drift + atomic floor. Edit points: ci.yml matrix/comments, `regenerate-shard-manifest.py`, both TSVs, the runbook. Never hand-merge TSVs.
- **Product:** Lever A alone cannot hit 20 min; Lever-F placeholder filed as commitment device; `affected-tests.sh` already runs in foreign repos — verify F's residual before sizing.
- **Legal:** clean; preserve the three invariants + CLA evidence chain; no doc/register amendments.
- **Operations:** public repo → runner minutes $0; constraint is the ~60-job concurrency pool; ledger a $0 Actions row with flip conditions (follow-up).
