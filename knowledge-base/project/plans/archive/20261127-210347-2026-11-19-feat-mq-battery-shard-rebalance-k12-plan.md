---
title: "feat(ci): rebalance merge-queue battery shards — fresh merge_group medians + light matrix K=8 → K=12"
date: 2026-11-19
slug: mq-battery-shard-rebalance-k12
branch: feat-one-shot-mq-battery-shards
issue: 11556
lane: single-domain
type: feat
---

# feat(ci): rebalance merge-queue battery shards — fresh merge_group medians + light matrix K=8 → K=12

## Enhancement Summary

**Deepened on:** 2026-11-19 (mechanical deepen pass — subagent fan-out unavailable on this harness; every gate and citation check ran inline sequentially)
**Sections enhanced:** Guard Contract (new), Scope Check (restructured to canonical 3-subsection schema), Overview/blast-radius citations (live-verified)

### Key Improvements

1. Corrected the K=7→K=8 precedent citation: PR is **#9449** (commit `6973f2adf9`); #9307 is the umbrella issue it references — a live `gh pr view`/`git log` check caught the mis-number.
2. Added `## Guard Contract` for the Phase-2 zero-measured-input refusal, keyed to the real write-path structure: the refusal belongs on the full-reprice arm (same site `drift_gate` occupies at L1319), with `--incremental` as the legitimate carve-out member.
3. Restructured `## Scope Check` to `### Ask Mapping` / `### Plan-Item Provenance` / `### Split Assessment` with verbatim asks and a reasoned single-PR verdict.
4. Completed the K-sensitive surfaces table (ci.yml L1983 `1/8` example, monitor L471 "8-way"; `test-all.sh` verified K-literal-free).

### New Considerations Discovered

- **#9449's own diff** confirms the blast-radius set (ci.yml, both TSVs, totality mutations+test, regen test, runbook) and that `main-health-monitor.yml` was NOT a manifest consumer then — it gained sharding later via #9410, so the lockstep coupling is new relative to that precedent (as the plan already flags).
- The monitor's own comment cites "(#9307)" at L473 — the umbrella issue reference is consistent with the corrected numbering.

## Overview

Lower the median merge_group `ci.yml` battery wall-time from ~37 min to under 30 min by (a) re-pricing the committed shard-duration tables from fresh `merge_group` run artifacts — the canonical full-battery population, since push-dedupe elides `test-scripts` on `push` runs — (b) regenerating the light shard manifest with the sticky-LPT balancer, and (c) bumping the light `test-scripts` matrix from K=8 to K=12 legs in `ci.yml` and `main-health-monitor.yml` so the achievable per-leg floor drops from ~29 min of serial suite work to ~19–20 min. Precedent: K=6→K=7 (#8854, commit `ebca96756b`) and K=7→K=8 (#9449, commit `6973f2adf9`; umbrella issue #9307) bumps — verified live via `gh pr view`/`git log` 2026-11-19.

**Diagnosis (measured 2026-11-19, merge_group run 44422317370):** the committed manifest is *already* balanced under its committed prices — `scripts/suite-shard-legs.tsv` leg sums over `suite-durations.tsv` are 29.5–30.8 min. The observed 22–37.7 min wall spread is two distinct problems:

1. **K=8 cannot beat ~30 min.** Total light suite work is ~233–239 min; the perfect K=8 leg is ~29.1 min of suite time + ~0.8 min per-leg job overhead ≈ 30 min wall. Rebalancing alone can only redistribute onto the 30-min floor.
2. **Committed prices drifted.** The merge_group run's actual per-leg suite sums were 21.6–36.9 min. Leg 5 ran +6.6 min over its price (top drifts: `lint-orphan-test-suites-mutations-b` 268→406 s, `ci-head-verdict` 357→413 s, `check-web-host-escrow-config` 192→227 s); leg 8 ran −7.9 min under. The heavy table is worse: `registry-gate-mutation-battery` priced 491 s (2026-09-29 stamp) vs 1133 s actual — a 2.3× drift that explains the `test-scripts-heavy (1/3)` 19.4-min leg. All under the watch's 4×/120 s `PRICE_DRIFT_ROW` flag bound, so nothing alerted.

## Premise Validation

Checked: #12699 MERGED (battery-gate follow-ups), #12881 MERGED (audit `--method GET` fix), #12728 OPEN (sibling-worktree SIGTERM — confirmed known flake, context only). Machinery map verified on the branch: `scripts/suite-shard-legs.tsv`, `suite-shard-legs-heavy.tsv`, `suite-durations.tsv`, `suite-durations-heavy.tsv`, `scripts/regenerate-shard-manifest.py`, `scripts/test-all.sh`, `plugins/soleur/test/{scripts-shard-totality,regenerate-shard-manifest}.test.sh`, `scripts/ci-battery-gate-replay.sh` all exist. **One stale path:** `scripts/test-all-pr-battery-gate` does not exist (no such file on branch or `origin/main`); the real artifact is `scripts/test-all-pr-battery-gate.test.sh` and its suite label `scripts/test-all-pr-battery-gate` (a timing label, seen at 42 s on leg 8). Proposed mechanisms (manifest regen, K bump, `--rows` arm splits) sit inside ADR-240's adopted mechanism, not its rejected alternatives — K bumps are the runbook's documented precedent.

**Open questions resolved (from `scripts/regenerate-shard-manifest.py` source):**

1. The generator optimizes **duration-weighted** balance — sticky-LPT over per-label medians (`assign()`); not count. But the committed manifest's last write was `--incremental` (provenance `incremental`, 2026-11-16): incumbent rows pin verbatim, only newly-registered labels deal in — so assignment never rebalanced after the last re-price.
2. `suite-durations.tsv` is **not** auto-refreshed: refresh is operator/agent-run (`--timings-dir`/`--runs`); `shard-balance-watch` is notify-only. Heavy table last measured 2026-09-29.
3. The 8-way count is **not pinned**: `scripts-shard-totality.test.sh` derives N from ci.yml's matrix; the generator refuses a committed manifest whose `n` ≠ the workflow's declared count; K=6→7→8 bumps are documented history. **New coupling this precedent lacked:** `main-health-monitor.yml` consumes the same `suite-shard-legs.tsv` and must bump in lockstep (manifest `n` mismatch degrades its legs to positional round-robin).

## Research Insights

Measured on this branch (merge_group run 44422317370, `suite-timings-scripts-{0..7}` artifacts downloaded and diffed against committed prices):

| Leg | Committed price sum | Actual suite sum | Job wall |
|---|---|---|---|
| 1/8 | 30.8 min | 24.9 min | 26.0 min |
| 2/8 | 29.6 min | 33.3 min | 34.2 min |
| 3/8 | 29.5 min | 31.3 min | 32.3 min |
| 4/8 | 30.1 min | 28.6 min | 29.3 min |
| 5/8 | 30.3 min | 36.9 min | 37.7 min |
| 6/8 | 29.8 min | 28.5 min | 29.3 min |
| 7/8 | 29.5 min | 28.2 min | 28.9 min |
| 8/8 | 29.5 min | 21.6 min | 22.4 min |

Per-leg job overhead ≈ 0.8 min (wall ≈ suite sum + ~50 s). Battery tail after the light matrix: `test-scripts-heavy (1/3)` 19.4 min, `test-webplat-mutations (approval-guard1-mutation)` 19.1 min — everything else ≤ 9.6 min. **Light legs are the only binding constraint at ≥ ~20 min.**

**Property List** (what the ask buys, one observable outcome each)

1. P1: median merge_group battery wall < 30 min — requires the worst light leg's *priced* load well under ~29 min, not merely balanced at 30.
2. P2: committed duration tables price the population they balance — merge_group medians, not push runs (artifact-sparse) or 51-day-old samples.
3. P3: every consumer of the shared light manifest agrees on N — ci.yml matrix, `main-health-monitor.yml` matrix, manifest `# n=` header, totality-mutation literals — so no leg's suites run nowhere and no consumer falls to positional.
4. P4: a future regen cannot silently price off the artifact-sparse push population — the all-floor count-balanced footgun (`--runs` over elided push runs produces an all-floor manifest with only a WARN) is closed or fenced.
5. P5: the change verifies after merge — a fresh merge_group run's `gh run view --json jobs` shows the worst leg materially under 30 min.

**Cut List** (mechanisms considered and cut)

- Splitting `test-all-affected-{a,b,c,d}` further → already `--rows` arms (DECLARED_TOTAL=38 → 1-13/14-32/33-36/37-38); at ~700 s each they pack fine at K=12. Cut.
- Splitting `registry-gate-mutation-battery` into `--rows` arms → the battery script has no `--rows` range support (its "rows" are Python anchor indices, not a CLI range); adding it is a suite-internals change, and heavy (19.4 min) stays under the post-change light bound anyway. Deferred — file follow-up only if its fresh median crosses ~20 min.
- Trimming `ci-head-verdict`/`monitor-pr-checks` → ~6–7 min suites are absorbable by packing at K=12; suite-time surgery is a separate investigation. Cut.
- Raising `test-scripts-heavy` K → 3 atomic one-suite legs; K>3 changes nothing without suite splits. Cut.
- Tightening `watch-shard-balance-11564.sh`'s leg-ratio bound (1.30 → lower) → observed leg-5 ratio was 1.27×, just under the flag; tuning cadence-vs-churn is a policy call, not required for <30 min. Deferred to decision-challenges as taste.
- Auto-regen workflow → ADR-240 deliberately keeps regen operator-invoked (checked-in derived data, sticky-LPT churn control); the weekly watch already detects drift past threshold. Cut.

**K-sensitive surfaces (blast radius — extends the K=7→8 precedent's table with the monitor, which did not consume the manifest then)**

| Surface | Why it changes |
|---|---|
| `.github/workflows/ci.yml` L1805 `shard: ["1/8"…"8/8"]` literal | the one real K (light) |
| `.github/workflows/ci.yml` comments L1779–1780 (K=8), L1983 (`matrix.shard` is `1/8` example), L2006 ("eight legs"), L245 (`test-scripts (1/8)` example) | prose |
| `.github/workflows/main-health-monitor.yml` L482 `shard:` literal + comments L471–472 ("8-way", `n=8`), L57–68 (`matrix 1/8..8/8`, "8-way") | **shared-manifest consumer — must move in the same commit or its legs go positional** |
| `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` | regenerated wholesale via `--timings-dir … --write`, never hand-edited (union-merge conflicts; runbook rule) |
| `scripts/suite-durations-heavy.tsv` (+ `suite-shard-legs-heavy.tsv` provenance stamp) | regenerated via `--group heavy --timings-dir … --write` — reprices `registry-gate-mutation-battery` off its 51-day-old 491 s price; manifest rows stay 1-suite-per-leg |
| `plugins/soleur/test/scripts-shard-totality-mutations.sh` L435–436 | ROW5 `old`/`new` literals embed the 8-value matrix; `old` must match ci.yml byte-for-byte, `new` drops the last leg |
| `plugins/soleur/test/scripts-shard-totality.test.sh` L10, L177 | comments only ("eight legs", `["1/8".."8/8"]` example) |
| `scripts/regenerate-shard-manifest.py` | add an event selector so ci.yml-group `--runs` can sample `merge_group` runs (P4 footgun) |
| `plugins/soleur/test/regenerate-shard-manifest.test.sh` | fixture rows for the new flag |
| `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` | topology table K=8→12, measured-history entry, monitor coupling |

## User-Brand Impact

**If this lands broken, the user experiences:** a required `test` check that hangs or silently under-runs the battery — either merges stall behind a red/absent check (the pre-shard #7902 shape: a 35.25-min single job blocked every web-platform deploy fail-closed), or a dropped shard leg lets a regression reach production behind a green pipeline — the under-run direction `scripts-shard-totality.test.sh` exists to catch.

**If this leaks, the user's [data / workflow / money] is exposed via:** no data surface — the change moves suite-to-leg assignments; the exposure is CI integrity, not secrets.

**Brand-survival threshold:** none

- `threshold: none, reason:` internal CI scheduling change; `.github/workflows/*.yml` and `scripts/` do not match the sensitive-path regex (same disposition as the K=7→8 plan); the worst defect is a red or under-running battery caught by `scripts-shard-totality.test.sh`/`scripts-shard-manifest.test.sh` before merge.

## Implementation Phases

### Phase 1 — Fresh merge_group measurements + dry-run sizing (no writes)

1. Download `suite-timings-scripts-*` (light) and `suite-timings-scripts-heavy-*` artifacts for the last 5 green `merge_group` `ci.yml` runs — sample as of plan time: 44485722708, 44422317370, 44367783886, 44361074603, 44341020337 (re-list at work time: `gh run list --workflow ci.yml --event merge_group --status success -L 5`); per run `gh run download <id> -R jikig-ai/soleur -p 'suite-timings-*' -D <dir>` exactly as `watch-shard-balance-11564.sh` does.
2. Run `python3 scripts/regenerate-shard-manifest.py --drift-report --timings-dir <5 dirs>` — record `LEG_OBSERVED`, `BOUND_PERFECT`, `PRICE_DRIFT_ROW`s. This is the measurement record the manifest/durations rewrite stands on.
3. Dry-run packing at candidate K: `python3 scripts/regenerate-shard-manifest.py --durations <fresh-table> --legs K --manifest /tmp/legs-K.tsv` for K ∈ {10, 12, 14} (arbitrary-K emission is the #9232 feature; committed writes at K ≠ workflow N are refused, so this is dry-run-only). Emit the predicted per-leg table into the PR body.
4. **Choose K = the smallest value whose predicted worst leg stays ≥ the heavy matrix's fresh median wall (~19–20 min)** — below that, light sharding buys nothing because heavy binds. Predicted: K=12 → ~19.4 min mean leg (+ ~0.8 min overhead ≈ 20–21 min wall); K=10 → ~24 min; K=14 → under heavy. Ruling recorded in `decision-challenges.md`: **K=12** unless the fresh medians shift the heavy wall materially.

### Phase 2 — Generator source hardening (P4, small)

`green_main_runs()` uses `gh run list --branch main` — `push` events where push-dedupe routinely elides `test-scripts`, so the documented `--runs 5 --write` can produce an artifact-sparse or all-floor (count-balanced) manifest with only a WARN. Add an event selector (e.g. `--event {auto,push,merge_group}`; ci.yml groups default to `merge_group`, the infra group keeps its current source) plus refusal to `--write` a committed manifest whose measured-input count is zero unless a new explicit flag acknowledges it. Fixture rows in `plugins/soleur/test/regenerate-shard-manifest.test.sh`. (Ruled a technical hardening call — recorded in decision-challenges.md.)

### Phase 3 — K bump + regeneration (one commit's worth of coupled edits)

1. `.github/workflows/ci.yml`: `test-scripts` matrix `shard: ["1/8"…"8/8"]` → `["1/12", "2/12", …, "12/12"]` (L1805); update K prose at L1779–1780, L2006, L245.
2. `.github/workflows/main-health-monitor.yml`: same literal at L482 + comments L57–68, L472. **Same commit** — the shared manifest tolerates no n mismatch.
3. `python3 scripts/regenerate-shard-manifest.py --timings-dir <5 dirs> --write` — emits n=12 manifest + fresh light durations; the committed-write n-pin now reads 12 from ci.yml. Handle the drift gate honestly: a fresh re-price may trip `DRIFT_TOTAL_PCT`/per-suite bounds vs the merge-base blob — that is the *point* of the re-price; pass `--allow-growth` only after eyeballing the violation list (the stamp records the acknowledged set).
4. `python3 scripts/regenerate-shard-manifest.py --group heavy --timings-dir <5 dirs> --write` — reprices the heavy table (manifest stays 3 atomic legs).
5. `plugins/soleur/test/scripts-shard-totality-mutations.sh` L435–436: update ROW5 `old` literal to the new 12-value ci.yml bytes; `new` drops `"12/12"`.
6. Comment/prose updates: `scripts-shard-totality.test.sh` L10/L177 ("eight legs" → generic or "twelve"), runbook topology table + a Measured-history entry recording this bump and the drift finding. `scripts/test-all.sh` verified to carry no K literal at plan time (its leg prose is generic; the #9449 review's "still said seven legs" was already fixed) — re-grep at work time to confirm.
7. **Sentinel sweep before push** (the brief's gate list, all touched surfaces): `bash plugins/soleur/test/scripts-shard-totality.test.sh`, `bash plugins/soleur/test/scripts-shard-totality-mutations.sh` (or the battery's CI arm), `bash plugins/soleur/test/regenerate-shard-manifest.test.sh`, `bash plugins/soleur/test/scripts-shard-manifest.test.sh`, `bash plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`, `bash plugins/soleur/test/ci-shard-totality-skip.test.sh`, `bash scripts/watch-shard-balance-11564.test.sh`.

### Phase 4 — Post-merge verification (P5)

After the next merge_group run completes: `gh run view <id> --json jobs` — confirm the worst `test-scripts` leg ≤ ~22 min and the battery wall < 30 min; confirm `test-scripts-heavy (1/3)` did not become the tail. `wallclock-p90-watch` (epic #11556's instrument) reads the same runs — no new measurement machinery needed.

## Files to Edit

- `.github/workflows/ci.yml` — light matrix literal + K prose
- `.github/workflows/main-health-monitor.yml` — light matrix literal + K prose
- `scripts/suite-shard-legs.tsv` — **generated**; regen output only
- `scripts/suite-durations.tsv` — **generated**; regen output only
- `scripts/suite-durations-heavy.tsv` — **generated**; regen output only
- `scripts/suite-shard-legs-heavy.tsv` — **generated**; provenance stamp refresh if the regen emits it
- `scripts/regenerate-shard-manifest.py` — `--event` source selector + zero-measured-input `--write` refusal
- `plugins/soleur/test/scripts-shard-totality-mutations.sh` — ROW5 `old`/`new` literals
- `plugins/soleur/test/scripts-shard-totality.test.sh` — leg-count comments
- `plugins/soleur/test/regenerate-shard-manifest.test.sh` — fixture rows for the new flag
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` — topology table + measured history + monitor-coupling note

## Files to Create

None — every artifact is a regen or an edit of an existing file.

## Acceptance Criteria

- [ ] AC1: `scripts/suite-durations.tsv` `# generated-from-runs=` provenance names merge_group-sourced timing dirs sampled at work time; `scripts/suite-durations-heavy.tsv` is re-priced off its 2026-09-29 stamp.
- [ ] AC2: `scripts/suite-shard-legs.tsv` header `# n=12` and every `test-scripts` matrix literal in `ci.yml` AND `main-health-monitor.yml` reads `/12` — verified by `grep -c '"/12"'` on both matrix lines plus `scripts-shard-manifest.test.sh` green.
- [ ] AC3: `bash plugins/soleur/test/scripts-shard-totality.test.sh` exits 0 (union of 12 legs == registered set, no duplicates) — the check that would catch a dropped leg.
- [ ] AC4: `bash plugins/soleur/test/regenerate-shard-manifest.test.sh` and `bash plugins/soleur/test/scripts-shard-manifest.test.sh` exit 0, including the ROW5 mutation literal updated to the 12-value matrix.
- [ ] AC5: the generator refuses `--runs`-class sampling of a wrong-population source without acknowledgement — a merge_group default for ci.yml groups is in place, or the alternative fencing agreed at work time is committed and covered by a fixture row.
- [ ] AC6: predicted leg table in the PR body (dry-run output) shows worst light leg ≤ ~21 min of priced suite time.
- [ ] AC7: post-merge verification recorded: on the first green merge_group run after merge, `gh run view <id> --json jobs` shows the worst `test-scripts` leg < 30 min wall (expect ~20–22) and `test` umbrella ≤ ~30 min; the result is commented on this plan or the PR.
- [ ] AC8: no `#N`-required-check changes — `scripts/required-checks.txt` untouched (matrix leg names are not required contexts; the synthetic `test` job still gates).

## Test Scenarios

- Sentinel sweep (Phase 3.7) — the enumerated six suites run green locally before push.
- Mutation row ROW5 (dropping the last matrix leg literal) drives `scripts-shard-totality.test.sh` red in the fixture and green on the real tree.
- `--legs 12 --write` to the committed manifest *before* the ci.yml bump must die on the n-pin (assert the refusal message; then apply the workflow edit and retry — ordering proof).
- Drift-report dry-run output recorded in the PR body: `LEG_OBSERVED`, `BOUND_PERFECT`, any `PRICE_DRIFT_ROW`s.
- If `--allow-growth` was needed: the violation list it acknowledged is pasted into the PR body.

## Guard Contract

Phase 2 adds one new gate to `scripts/regenerate-shard-manifest.py`; the existing gates (n-pin, drift gate, totality union) are only *exercised*, not modified.

### Guard 1 — zero-measured-input `--write` refusal

**Property.** A committed durations/manifest `--write` produced from a timing population with zero `src=measured` rows must refuse (exit 2) unless an explicit acknowledge flag is passed — an all-floor price table is a count-balanced manifest masquerading as a measured one, and today it lands behind only a WARN.

**Assembly.** Two write paths converge on the committed table and the refusal must key on the right one: the full-reprice arm (`if args.write:` at ~L1312, where `drift_gate` already fires at L1319 over `new_rows`/`src_map` — the new refusal reads the same `src_map` count, BEFORE the `open(..., "w")` calls at L1334/L1338) and the `--incremental` arm (~L1162–1183), which legitimately carries zero *new* measurements — its `new_rows` derive from the incumbent table verbatim, so the refusal must be scoped to the full-reprice population, not the shared pre-write position. Sources upstream of `src_map` (`--durations`, `--timings-dir`, `--run`/`--runs` with the new `--event` selector) all funnel through `aggregate_runs()` — one chokepoint.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | `--timings-dir` dirs containing timing TSVs for zero registered labels (artifact-empty run) → `--write` on the committed path — refuse exit 2 | RED |
| 2 | Same input but the refusal's print lands AFTER the `open(..., "w")` calls — warning emitted, artifact still written: the vacuous-guard shape | RED (the artifact must not be written) |
| 3 | `--incremental --write` — the second member of the write set — must NOT refuse on zero new measurements: its contract is verbatim incumbent pass-through; an unconditioned refusal bricks the add/remove path | GREEN (carve-out honored) |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "lower the median merge_group CI battery wall-time (currently ~37 min median over 11 successful runs since 2026-11-17)" | Whole plan / P1 / AC7 | mapped |
| 2 | "Leg-sums per durations.tsv do NOT explain the observed spread → either durations are stale, many suites lack rows, or the manifest generator balances on count not duration. Diagnose first." | Diagnosis §Overview + Phase 1 | mapped |
| 3 | "Regenerate/rebalance shard legs on fresh durations — target the leg-5 outlier; consider 8→10+ shards if fleet concurrency allows" | Phase 1.3 dry-run + Phase 3 K=12 bump + regen | mapped |
| 4 | "Split the meta-suites (test-all-affected-\*) — they run sub-suites serially inside one leg." | Cut List | descoped — justification: already `--rows` arms (1-13/14-32/33-36/37-38); ~700 s each packs acceptably at K=12 |
| 5 | "Trim the heaviest single suites (ci-head-verdict 357s, monitor-pr-checks 394s) if profiling shows redundant work." | Cut List | descoped — justification: ask was conditional on profiling showing redundancy; packing at K=12 absorbs ~6–7 min suites, so no surgery is warranted this PR |
| 6 | "test-scripts-heavy (1/3) at 19.4m — rebalance after the main legs fix." | Phase 3.4 heavy re-price (legs are 3 atomic suites — re-price is the only rebalance available without suite splits; recorded in decision-challenges) | mapped |
| 7 | "Required-set constraint: the `test` umbrella is a required merge check; merge_group MUST run the full required set — selection tightness is NOT a lever for queue merges" | Design constraint — no selection/skip changes anywhere; AC8 + totality sentinel remain the proof | mapped |
| 8 | "VERIFY: rerun `gh run view <new merge_group id> --json jobs` after merge to confirm the leg-5 tail actually shortened; median target <30 min." | Phase 4 / AC7 | mapped |
| 9 | "Sentinels to run before pushing: scripts-shard-totality, regenerate-shard-manifest, test-all-\* gates touched." | Phase 3.7 sentinel sweep + Test Scenarios | mapped |
| 10 | "Does the manifest generator optimize duration-weighted balance or just count? (Read the generator before proposing.)" | Premise Validation answer 1 (sticky-LPT, duration-weighted) | mapped |
| 11 | "Is suite-durations.tsv refreshed automatically from CI artifacts, or is it drifting stale?" | Premise Validation answer 2 (operator-run only; watch is notify-only) | mapped |
| 12 | "Is the 8-way shard count a pinned convention (totality sentinel) or free to grow?" | Premise Validation answer 3 (free; generator n-pin guards consistency) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Phase 1 measurement + dry-run | "Diagnose first." | asked |
| `.github/workflows/ci.yml` matrix + prose | "consider 8→10+ shards if fleet concurrency allows" | asked |
| `scripts/suite-shard-legs.tsv` + `suite-durations.tsv` regen | "Regenerate/rebalance shard legs on fresh durations" | asked |
| `scripts/suite-durations-heavy.tsv` + `suite-shard-legs-heavy.tsv` regen | "test-scripts-heavy (1/3) at 19.4m — rebalance after the main legs fix." | asked |
| `plugins/soleur/test/scripts-shard-totality{,-mutations}.{test.,}sh` updates | "Sentinels to run before pushing: scripts-shard-totality" | asked |
| `plugins/soleur/test/regenerate-shard-manifest.test.sh` fixture rows | "regenerate-shard-manifest" (sentinel list) | asked |
| Phase 4 post-merge verify | "VERIFY: rerun `gh run view <new merge_group id> --json jobs` after merge" | asked |
| `.github/workflows/main-health-monitor.yml` | — | inferred — justification: shared-manifest consumer discovered by grep (L482 consumes the same `suite-shard-legs.tsv`); an n mismatch degrades its legs to positional round-robin, so it must move in the same commit — a safety contract, not scope growth |
| `scripts/regenerate-shard-manifest.py` (`--event` + zero-measured refusal, Phase 2) | — | inferred — justification: the ask's own diagnosis (stale durations) is produced by the documented `--runs` path sampling push events where push-dedupe elides `test-scripts`; without a merge_group source the "fresh durations" ask is unrepeatable and the all-floor write lands behind only a WARN — the safety fix the finding demands |
| runbook `ci-test-scripts-sharding.md` | — | inferred — justification: the runbook owns the K topology table and measured history; a bump without it leaves wrong operational guidance for the next regen (same treatment as #9449) |

### Split Assessment

- Subsystems touched: 4 — `.github`, `scripts`, `plugins/soleur`, `knowledge-base`
- Planned files: 11 | Estimated changed lines: ~90 authored + a wholesale TSV re-price (generated churn)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the >=4-root trip is a false positive: the manifest `# n=` pin, both workflow matrices, the regenerated TSVs, and the ROW5 literals are one atomic change (the generator refuses a committed write at n≠workflow N, and a monitor-only lag degrades to positional legs); splitting any root leaves a consumer inconsistent. #9449 shipped the identical root set as one commit.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to CI shard scheduling; no user-facing surface, no product flow, no copy.

## Observability

The observable effect is the existing `suite-timings-scripts-<k>` artifact upload plus job wall time — both queryable without SSH via `gh api`/`gh run view`. `wallclock-p90-watch` (#11774) already measures required-check wall-clock weekly across `pull_request` and `merge_group` runs; this change needs no new measurement machinery, only that the AC7 spot check lands.

```yaml
liveness_signal:
  what: worst `test-scripts` leg wall-time on green merge_group ci.yml runs
  cadence: every merge_group run (watch samples weekly)
  alert_target: shard-balance drift watch tracker issue (existing)
  configured_in: .github/workflows/shard-balance-watch.yml
error_reporting:
  destination: leg job conclusion → `test` umbrella verdict classifier (existing)
  fail_loud: yes — a dead leg reds the run; a silently unassigned suite reds scripts-shard-totality
failure_modes:
  - mode: manifest n ≠ workflow N (a consumer falls to positional)
    detection: scripts-shard-manifest.test.sh n-pin + `[shard] manifest n=` stderr notice
    alert_route: required `test` check red
  - mode: dropped registration (totality breach)
    detection: scripts-shard-totality.test.sh union assertion
    alert_route: required `test` check red
  - mode: re-priced weights trip the drift gate unacknowledged
    detection: regenerate-shard-manifest.py exit 2 with violation list
    alert_route: implementer-visible refusal at regen time
logs:
  where: per-leg `suite-timings-*.tsv` artifacts (14-day retention) + leg job logs
  retention: GitHub artifact/run retention
discoverability_test:
  command: grep -c -e '# n=12' scripts/suite-shard-legs.tsv
  expected_output: "1"
```

## Open Code-Review Overlap

1 open scope-out touches the planned files: **#8881** (review of the #8854 K=6→K=7 rebalance — "9-seat panel, 0 P1, findings fixed inline"; its body names `scripts/regenerate-shard-manifest.py`). **Disposition: acknowledge** — it documents the prior bump's review outcomes, not an unclosed refactor request; nothing in it is re-scoped by this plan. If work-time inspection shows an un-resolved finding, fold it into Phase 2.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Rebalance only, keep K=8 | Perfect balance ≈ 29.1 min suite + 0.8 overhead ≈ 30 min wall — the <30 median target has zero headroom against ±25% per-suite variance. Rejected by the measured floor. |
| K=10 | Safe (~24 min) but leaves ~6 min of headroom on the table vs K=12's ~20–21 min, and the epic #11556 goal is 20 min. Held as fallback if dry-run at K=12 mispredicts. |
| K=14+ | Drops light's predicted worst leg under the heavy leg's ~19–20 min wall — extra leg jobs buy nothing once heavy binds. |
| Split `registry-gate-mutation-battery` via `--rows` | Battery has no row-range CLI support today; deferred follow-up if its fresh median stays > ~20 min and becomes the recurring tail. |
| Add a scheduled auto-regen workflow | ADR-240 deliberately keeps regen manual (sticky-LPT churn control); the weekly watch already detects drift. |
| Keep `--runs` sampling push runs | Push runs are artifact-sparse under push-dedupe — the measured population wouldn't be the merge_group population the manifest actually balances. Phase 2 fixes the source. |

## Sharp Edges

- **Never hand-edit the TSVs** — union-merge conflicts; regeneration is the only write path (runbook rule).
- **The drift gate is a feature:** if the fresh re-price refuses on `DRIFT_*` bounds, read the violation list — it is the measurement of the drift this PR exists to fix — then `--allow-growth` and paste the list into the PR body. Do not treat the refusal as a blocker to route around.
- **Commit ordering:** the generator refuses a committed `--write` at K ≠ workflow N — bump both workflow files FIRST, then regen (single commit is cleanest; CI on the PR will see n=12 consistently).
- **`main-health-monitor.yml` is a silent second consumer** — a ci.yml-only bump degrades its legs to positional with only a stderr notice. Both files, same commit.
- **Do not run `regenerate-shard-manifest.py --runs N --write` for the light/heavy groups** until Phase 2 lands — it samples push runs, and push-dedupe elides the shards job; an all-artifactless sample writes an all-floor manifest with only a WARN. Use `--timings-dir` over downloaded merge_group artifacts (the watch's own method).
- **Merge-queue union-merge:** the TSVs land on every sibling PR — expect a conflict if a sibling regen merges first; resolve by re-running the regen, never hand-merging.
- A plan whose `## User-Brand Impact` section is empty or threshold-less fails `deepen-plan` Phase 4.6 — filled above.
