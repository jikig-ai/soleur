Child of epic #11556 (Lever A, reframed by measurement).

## Measured diagnosis (2026-10-29, run 40936890587 + merge_group 40936383604)

The epic's Lever-A premise is partially stale — duration-derived shard assignment already shipped (ADR-240, `scripts/suite-shard-legs.tsv` sticky-LPT over `suite-timings-*` medians). The two 54/50-min legs are not imbalance; each carries ONE dominant suite the manifest cannot price:

| Suite | Manifest price | Actual on PR run | Actual on merge_group |
|---|---|---|---|
| `plugins/soleur/test/ci-pr-affected-replay.test.sh` (leg 1/8) | 1,184 ms (floor — never measured on main) | 1,491,362 ms = 24.9 min | 1,204,093 ms = 20.1 min |
| `scripts/test-all-affected` (leg 3/8) | 337 s (main median) | 1,772,399 ms = 29.5 min | 1,090,061 ms = 18.2 min |

Suite-sum ≈ wall-clock on every leg (~1 min/leg setup) — dependency/tool caching is near-worthless for this bottleneck. Other legs: 17.6–25.1 min vs ~15 min predicted (mild PR inflation). merge_group's ~53 min is the SAME atomic floor paid a second time + ~7 min queue/roots (Lever-B question answered: nothing to dedupe; ADR-276 full-battery invariant stands).

## Scope

1. **Diagnose `test-all-affected`'s PR-vs-main divergence** (337 s → 1,772 s, ~5.3×): merge-base derivation cost? PR-event-only probe set? Then split or bound it (`--rows` split precedent, #8864/shard-totality-mutations).
2. **Bound `ci-pr-affected-replay.test.sh`** (S4 tooling, floor-priced at 1.2 s): pin a bounded replay corpus via fixtures and/or cap live run enumeration; keep the live path exercised by the existing advisory `affected-index-ratchet` job.
3. **Full manifest regen** — `python3 scripts/regenerate-shard-manifest.py --runs 5 --write` for both groups (re-prices 74 stale floor rows incl. `watch-*` at 140–150 s); evaluate `--legs K` dry-run after suite surgery.
4. **Fresh PR p90 baseline** — last measured 2026-10-04 (p90 24.4, n=102, pre-S4-growth); decompose queue vs execution vs ejection-requeue per the runbook cohort method.

## Invariants (CLO-mandated, acceptance criteria)

- Required-check name set in `scripts/required-checks.txt` byte-identical post-change.
- `shard-totality-mutations` remains in the required set; shard manifests stay committed and deterministic.
- `fetch-depth: 0` preserved on the CLA-dependent shard checkout; `merge_group` synthetic re-reporting preserved; NO concurrency-cancel on `merge_group`.
- No affected-selection (S4 PR C/D) re-attempt — parked behind #10448/#10859.

## Explicitly NOT in scope

- Dependency/tool caching (measured ~1 min/leg), serial job ordering, `merge_group` cancellation, derive-cache restore (bound to parked #10414), Lever C/D/E/F.

## Expected outcome

Worst leg ~55 → ~25–28 min; merge_group ~53 → ~35–38 min. Does NOT reach the epic's ≤20/≤15 goals alone — honest intermediate milestone.

Brainstorm: `knowledge-base/project/brainstorms/2026-10-29-required-check-time-brainstorm.md` (draft PR #11561, branch feat-11556-required-check-time).
