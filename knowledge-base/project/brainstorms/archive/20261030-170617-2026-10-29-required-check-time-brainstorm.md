# Brainstorm: cut PR required-check wall-clock (epic #11556, Lever-A slice + Lever-B diagnosis)

**Date:** 2026-10-29
**Issue:** #11556 (open tracking epic — this brainstorm scopes its Lever-A slice; the epic remains the parent tracker)
**Branch:** feat-11556-required-check-time
**Draft PR:** #11561
**Lane:** cross-domain
**Status:** Ready for plan

## What We're Building

A Lever-A slice of epic #11556 ("cut PR required-check time from ~1h to 20 min or less, for us and for our users"), rescoped by measurement: the epic's lever-(a) mechanism (duration-derived shard assignment) already shipped via ADR-240 (`scripts/suite-shard-legs.tsv`, sticky-LPT over `suite-timings-*` medians), so the work is not "build derivation" but **diagnose and fix the two atomic suites that dominate both the PR run and the merge_group run**, then re-price the manifest and re-baseline wall-clock.

Measured on PR run 40936890587 (2026-10-29, green, no retries) and merge_group run 40936383604, both decomposed from `suite-timings-scripts-{0..7}` artifacts:

| Leg | Suite-sum (PR run) | Wall (PR run) | Dominant suite | Manifest price | Actual |
|---|---|---|---|---|---|
| 1/8 | 54.2 min | 54.9 min | `plugins/soleur/test/ci-pr-affected-replay.test.sh` | 1,184 ms (**floor**) | **1,491,362 ms = 24.9 min** |
| 3/8 | 50.1 min | 50.9 min | `scripts/test-all-affected` | 337 s (measured, main) | **1,772,399 ms = 29.5 min** |
| 2,4,5,6,7,8/8 | 17.6–25.1 min | 18.3–25.8 min | — | ~15 min predicted | mild PR inflation |

- Suite-sum ≈ wall-clock on every leg → **per-leg setup is ~1 min, not ~14 min**; dependency/tool caching is near-worthless for this bottleneck.
- On the merge_group run the **same two suites** dominate (replay 20.1 min, test-all-affected 18.2 min) → the queue's ~53 min is the same atomic floor paid again plus ~7 min queue+roots, not a separate duplication problem. ADR-276 makes the queue's full battery non-negotiable, so the fix is suite cost, not skipping.
- `ci-pr-affected-replay` is floor-priced because it has never been measured in the last-5-green-main-runs sample (fresh S4 tooling, Oct 26–28); floor rows pass through `--incremental` regen byte-identical. `test-all-affected` costs ~5× its main median on PR events.
- Last measured PR p90 was 24.4 min (Oct 4, n=102, pre-S4-tooling growth) — the 64-min run is likely the new normal but is n=1; a fresh baseline is part of the deliverable.

## Why This Approach

Approach 1 selected: **atomic-suite surgery + full regen + fresh baseline**, dropping the epic's caching/ordering items (already shipped or measured worthless).

The atomic-floor rule applies: worst leg ≥ largest indivisible suite. No manifest rebalance can bring leg 1/8 below ~25 min or leg 3/8 below ~30 min while those suites run whole. Splitting/bounding them (the `--rows` precedent from #8864/`shard-totality-mutations`) attacks ~55 min of measured overshoot; a full `--runs 5 --write` regen then re-prices every stale floor row (74 rows; `watch-*` pinned at 140–150 s against a 1,200 ms default); and a fresh p90 gives the epic an honest baseline.

Rejected: measure-only (leaves the overshoot in place; the manifest cannot price a suite it cannot measure); surgery+machinery (scheduled regen cadence is real but belongs in a follow-up — see Productize Candidate).

## User-Brand Impact

- **Artifact:** the PR required-check pipeline (`test` aggregate, `test-scripts`/`test-scripts-heavy` legs, shard manifests) and the CI templates the plugin teaches to user repositories.
- **Vector:** a rebalancing/split that silently dropped suite coverage, or a reorder that let a required check report green without running, would ship a bad commit to our repo and — via the templates the plugin teaches — to a user's repo.
- **Threshold:** `single-user incident`.

CLO invariants the plan must preserve (from the CLO assessment): (1) required-check name set in `scripts/required-checks.txt` byte-identical; (2) `shard-totality-mutations` remains in the required set (it proves every suite runs on exactly one leg); (3) the shard manifests stay committed and deterministic; plus the CLA evidence chain — `fetch-depth: 0` on the CLA-dependent shard checkout, `merge_group` synthetic re-reporting, and **no** concurrency-cancel on `merge_group`.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Scope = epic Lever-A slice, **reframed by measurement** | Epic's (a)-(d) partially stale: derivation already shipped (ADR-240); caching ~1 min/leg of value; ordering/cancel mostly shipped and serial ordering would regress the green-path p90 the DoD measures. |
| D2 | Primary work = split or bound `ci-pr-affected-replay` and `test-all-affected` | 54.3 of ~111 overshoot-minutes; both are S4-program tooling suites whose cost grew post-Oct-4. Diagnose `test-all-affected`'s PR-vs-main divergence (5.3×) before choosing split vs bound. Use the `--rows` split precedent (#8864). |
| D3 | Full `python3 scripts/regenerate-shard-manifest.py --runs 5 --write` regen for both manifests | Re-prices measured rows AND stale floor rows that `--incremental` pins verbatim. Same-PR edit with any K change (generator refuses K≠N writes). |
| D4 | Fresh PR p90 baseline measurement | Last is Oct-4 vintage (p90 24.4, n=102); post-S4-growth reality unmeasured. Method: runbook cohort method — queue vs execution vs ejection-requeue decomposition, not medians. |
| D5 | No new dependency/tool caching in this slice | Suite-sum ≈ wall-clock (~1 min/leg setup). npm/Playwright/Docker caches already exist; derive-cache restore is contractually bound to parked PR D #10414 — do not absorb it here. |
| D6 | No serial job ordering or merge_group cancellation | Already max-parallel behind ≤3-min root gates; serial edges consume the 73/75 declared-path budget and hurt green p90; `merge_group` cancel breaks queue evidence (CLO). Cancel-in-progress on PR events already exists. |
| D7 | Lever-B question answered, no separate Lever-B work | merge_group ≈ PR because the same atomic floor dominates both runs + ~7 min queue/roots. ADR-276 full-battery invariant stands; nothing to dedupe. |
| D8 | Do NOT re-attempt affected-selection (S4 PR C/D) | Deliberately parked behind index completion (#10448 drain, baseline ~1,513 pairs) + required ratchet (#10859 soak) + re-ruled go/no-go. Reference, don't touch. |
| D9 | Regen cadence stays manual in this slice | Scheduled regen is the Productize Candidate below; adding bot-PR machinery to this PR inflates scope. Record the ownership question as an open question. |
| D10 | Productize Candidate: `ci-shard-balance-watch` | Floor-priced suites that grow unboundedly (the `ci-pr-affected-replay` failure mode: 1.2 s price vs 24.9 min actual) are a recurring drift class — a scheduled probe that flags floor/never-measured rows above a bound, or a balance-drift ratchet. Deferred-item issue filed at brainstorm end. |

## Open Questions

1. `test-all-affected` PR-vs-main divergence (337 s → 1,772 s): is the 5.3× a merge-base derivation cost, a live-repo probe set that only runs on PR events, or growth in the audited suite count? Plan must diagnose before choosing split vs bound.
2. `ci-pr-affected-replay` (the S4 ratchet/observation-window suite): does it need 25 min of live run enumeration per CI leg, or can it pin a bounded replay corpus (fixtures) and soak the live path elsewhere (e.g. the existing advisory `affected-index-ratchet` job)?
3. Epic DoD posture (CPO flag): the epic's DoD is internal-only but its title promises "for our users" — amend the DoD to include a user-side criterion, or rely on the Lever-F placeholder issue filed below? Operator decision at epic-review time; not blocking this slice.
4. Regen-cadence ownership: who runs `--runs 5` and how often, pending the Productize Candidate automation (D10)?
5. K=8 still optimal? With two suites removed to heavy/dedicated legs or split, the packer may re-derive a different optimum — evaluate with `--legs K` dry-run at plan time.
6. `timeout-minutes: 60` is the only bound and silent — at ~55 min the worst leg nearly tripped it; after surgery the headroom returns, but the comment chain says do not lower. Leave as-is.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

The machinery the epic asks for is already built — the gap is drift, variance, and the atomic floor. Rebalance risk surface is LOW (required context is the `test` aggregate only; coverage is membership-independent via the totality battery + hash fallback; toolchain parity asserted per leg). Concrete edit points: ci.yml matrix arrays + stale comments, `regenerate-shard-manifest.py`, both TSV manifests, the sharding runbook. Named risk: sticky-LPT diff-stability vs aggressive rebalancing (manifest merge conflicts land on sibling PRs — regenerate, never hand-merge).

### Product (CPO)

Lever A's ceiling (~29 min balanced) cannot reach the epic's 20-min goal alone; the DoD is internal-only while the title promises "for our users" — file the Lever-F placeholder issue as a commitment device and consider amending the epic DoD. Verified: `affected-tests.sh` already runs in foreign repos, so Lever F's "usable without our test runner" is partially built — verify the residual before sizing it.

### Legal (CLO)

Legally clean. The Art. 5(2) accountability concern is already engineered around: committed manifest + required mutation-tested totality guard + stable `test` aggregate name = the proof a merged PR ran the full required set. Preserve the three invariants and the CLA evidence chain (see User-Brand Impact). No document/register amendments.

### Operations (COO)

Repo is PUBLIC — GitHub-hosted runner minutes are $0; the real constraint is the ~60-job shared concurrency pool, not dollars. Recommend ledgering a $0 "GitHub Actions (public repo)" row with flip conditions. Cache storage has a 10 GB/repo cap — irrelevant now that caching is descoped. Flagged: regen-cadence ownership, and `deploy-script-tests` red-on-main (#10781) as adjacent friction (Lever D, out of scope).

## Capability Gaps

- **No scheduled manifest-regen / floor-row-drift mechanism.** Evidence: the `ci-leg-balance-9232` daily sweep closed 2026-09-30 (runbook `ci-test-scripts-sharding.md`); `grep -rn "regenerate-shard-manifest" .github/workflows/` returns no scheduled job; floor rows (74 of 668) re-price only on manual `--runs` regen. This is the recurring-drift class behind D10.
- **No per-leg top-suite reporter in CI output.** Evidence: `suite-timings-*.tsv` artifacts are produced and uploaded `if: always()` (ci.yml:1622–1645) but the only consumer is operator-run `regenerate-shard-manifest.py`; nothing posts a top-15 to the step summary. `sort -t$'\t' -k2 -rn` covers the need ad hoc — flag as "nice to have, not tooling to build" per CTO.

## Deferred Items (issues filed at brainstorm end)

1. **Lever-F placeholder** (commitment device per CPO): user-repo reference CI layout + budget advice in ship/preflight; verify what `affected-tests.sh` already covers before sizing. Links the epic's user-facing half to a schedulable issue.
2. **`ci-shard-balance-watch` productize candidate** (D10): scheduled probe/ratchet flagging floor-priced or never-measured manifest rows above a cost bound.
3. Heavy-group atomic floor: `registry-gate-mutation-battery` split remains deferred — already tracked by open #9323 (path-gate the self-test mutation batteries) — **no duplicate filed**.
4. Fresh PR p90 is measured in this slice; the recurring per-PR wall-clock ratchet is epic Lever E — not filed here (epic tracks it).

## Out of Scope

- Lever C affected-selection re-attempt (parked behind #10448/#10859 — D8)
- Lever D `deploy-script-tests` red-on-main (#10781) and flake tracking
- Lever E weekly-digest wall-clock reporting and ratchets
- Lever F user-facing CI layout beyond filing the placeholder issue
- Any merge_group battery reduction, dedupe, or cancellation (ADR-276 invariant)
- Serial job ordering / fail-fast staging (D6)
